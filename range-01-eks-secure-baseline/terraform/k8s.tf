# -------------------------------------------------------
# KUBERNETES WORKLOADS (deployed by Terraform, not kubectl)
#
# These resources replace the manual `kubectl apply -f nginx-*.yaml` step.
# They deploy the exact same objects as k8s/nginx-deployment.yaml and
# k8s/nginx-service.yaml (kept there as annotated reference), using the
# hashicorp/kubernetes provider already configured in main.tf (exec auth via
# `aws eks get-token`).
#
# WHY: nginx-service is type LoadBalancer, which makes the in-cluster AWS
# controller create an NLB out-of-band. When kubectl owned these objects,
# `terraform destroy` never saw that NLB and left it orphaned unless you
# remembered to `kubectl delete -f ../k8s/` first. With Terraform owning the
# Service, `terraform destroy` deletes it - in dependency order, before the
# cluster - and the NLB is torn down automatically. No kubectl in the lifecycle.
# -------------------------------------------------------

resource "kubernetes_deployment_v1" "nginx" {
  metadata {
    name   = "nginx-deployment"
    labels = { app = "nginx" }
  }

  spec {
    replicas = 2

    selector {
      match_labels = { app = "nginx" }
    }

    template {
      metadata {
        labels = { app = "nginx" }
      }

      spec {
        # emptyDir volumes give the read-only-root-filesystem container writable
        # paths for nginx's cache and runtime pid/socket.
        volume {
          name = "nginx-cache"
          empty_dir {}
        }

        volume {
          name = "nginx-run"
          empty_dir {}
        }

        container {
          name  = "nginx"
          image = "nginx:1.27-alpine"

          port {
            container_port = 80
          }

          # Resource requests/limits are a security and stability best practice -
          # prevents one pod from starving others on the same node.
          resources {
            requests = {
              cpu    = "100m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "128Mi"
            }
          }

          volume_mount {
            name       = "nginx-cache"
            mount_path = "/var/cache/nginx"
          }

          volume_mount {
            name       = "nginx-run"
            mount_path = "/var/run"
          }

          # Hardened pod security context - the baseline range-02 deliberately
          # omits. Runs as non-root, no privilege escalation, read-only root
          # filesystem, all Linux capabilities dropped.
          security_context {
            run_as_non_root            = true
            run_as_user                = 101
            allow_privilege_escalation = false
            read_only_root_filesystem  = true

            capabilities {
              drop = ["ALL"]
            }
          }
        }
      }
    }
  }

  # Nodes must exist before the pods can schedule; this also forces the pods to
  # be torn down before the node group on destroy.
  depends_on = [aws_eks_node_group.main]
}

resource "kubernetes_service_v1" "nginx" {
  metadata {
    name = "nginx-service"

    annotations = {
      # Creates a Network Load Balancer (cheaper and simpler than the classic
      # Elastic LB). The default in-tree provisioner is enough for this NLB.
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
    }
  }

  spec {
    type     = "LoadBalancer"
    selector = { app = "nginx" }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 80
    }
  }

  depends_on = [aws_eks_node_group.main]
}
