# -------------------------------------------------------
# KUBERNETES WORKLOADS (deployed by Terraform, not kubectl)
#
# These resources replace the manual `kubectl apply -f ../k8s/` step.
# They deploy the exact same objects as k8s/vulnerable-dashboard.yaml and
# k8s/leaked-credentials.yaml (kept there as annotated reference), using the
# hashicorp/kubernetes provider already configured in main.tf (exec auth via
# `aws eks get-token`).
#
# WHY: the Service below is type LoadBalancer, which makes the in-cluster AWS
# controller create an NLB out-of-band. When kubectl owned these objects,
# `terraform destroy` never saw that NLB and left it orphaned unless you
# remembered to `kubectl delete -f ../k8s/` first. With Terraform owning the
# Service, `terraform destroy` deletes it - in dependency order, before the
# cluster - and the NLB is torn down automatically. No kubectl in the lifecycle.
#
# The intentional misconfigurations are preserved verbatim - they are the
# teaching content of this range. See k8s/*.yaml for the full annotations.
# -------------------------------------------------------

# ATTACK CHAIN STEP 1 (SA half) - service account the vulnerable pod runs as.
resource "kubernetes_service_account_v1" "vulnerable_dashboard" {
  metadata {
    name      = "vulnerable-dashboard-sa"
    namespace = "default"
  }
}

# ATTACK CHAIN STEP 3 (RBAC half) - OVER-BROAD ROLE BINDING
# Binds cluster-admin to the workload's service account: code execution in the
# pod (or theft of its mounted token) becomes full control of the cluster.
resource "kubernetes_cluster_role_binding_v1" "vulnerable_dashboard" {
  metadata {
    name = "vulnerable-dashboard-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.vulnerable_dashboard.metadata[0].name
    namespace = "default"
  }
}

# ATTACK CHAIN STEP 5 - PLAINTEXT SECRETS IN A CONFIGMAP
# Credential-shaped values in a ConfigMap (not a Secret): readable with minimal
# RBAC, unencrypted at rest. Values are deliberately fake placeholders.
resource "kubernetes_config_map_v1" "leaked_credentials" {
  metadata {
    name      = "leaked-credentials"
    namespace = "default"
  }

  data = {
    AWS_ACCESS_KEY_ID     = "AKIAFAKEEXAMPLE0000"
    AWS_SECRET_ACCESS_KEY = "this-is-a-placeholder-not-a-real-credential"
    DB_PASSWORD           = "hunter2-placeholder-not-real"
  }
}

# ATTACK CHAIN STEP 1 + 2 - EXPOSED, PRIVILEGED, HOST-NETWORKED POD
# No securityContext hardening (contrast range-01's nginx deployment):
# privileged: true removes container isolation, hostNetwork: true shares the
# node's network namespace (so IMDS at 169.254.169.254 is reachable), and the
# leaked ConfigMap is pulled into the environment in plaintext.
resource "kubernetes_deployment_v1" "vulnerable_dashboard" {
  metadata {
    name   = "vulnerable-dashboard"
    labels = { app = "vulnerable-dashboard" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "vulnerable-dashboard" }
    }

    template {
      metadata {
        labels = { app = "vulnerable-dashboard" }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.vulnerable_dashboard.metadata[0].name

        # Places the pod directly on the node's network namespace - the
        # container-breakout half of the chain (reaches the node's IMDS).
        host_network = true

        container {
          name  = "app"
          image = "nginx:1.27-alpine" # stand-in image for an exposed app

          # privileged: true removes container isolation entirely -
          # host filesystem and devices become reachable from inside.
          security_context {
            privileged = true
          }

          port {
            container_port = 80
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map_v1.leaked_credentials.metadata[0].name
            }
          }
        }
      }
    }
  }

  # Nodes must exist before the pod can schedule; this also forces the pod to be
  # torn down before the node group on destroy.
  depends_on = [aws_eks_node_group.main]
}

# ATTACK CHAIN STEP 1 - INTERNET-FACING ENTRY POINT
# type: LoadBalancer publishes the pod to the internet with no auth in front.
# Terraform owning this resource is what makes `terraform destroy` clean up the
# backing AWS NLB instead of orphaning it.
resource "kubernetes_service_v1" "vulnerable_dashboard" {
  metadata {
    name = "vulnerable-dashboard-service"

    annotations = {
      # Provision a Network Load Balancer (L4) instead of the legacy Classic ELB
      # the in-tree provisioner defaults to - matches range-01 so the two diff
      # cleanly. With the in-tree NLB, load_balancer_source_ranges is enforced at
      # the worker-node security group.
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
    }
  }

  spec {
    type     = "LoadBalancer"
    selector = { app = "vulnerable-dashboard" }

    # Scope the load balancer's inbound to the operator's IP (see access.tf)
    # instead of the internet. With the NLB annotation above, this is enforced at
    # the worker-node security group, so it also covers the hostNetwork pod's
    # direct node:80 exposure.
    load_balancer_source_ranges = local.allowed_source_cidrs

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 80
    }
  }

  depends_on = [aws_eks_node_group.main]
}
