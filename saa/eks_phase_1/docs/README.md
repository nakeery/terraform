# EKS Portfolio Project - Phase 1: Foundation

Secure EKS cluster with nginx deployed, built with Terraform.

## What this builds

- VPC with public/private subnets across 2 AZs
- NAT gateway for private subnet egress
- EKS cluster (control plane) with control plane logging enabled
- Managed node group running in private subnets only
- IAM roles for cluster, nodes, and IRSA (OIDC provider) foundation
- nginx deployed with hardened pod security context

## Cost warning

This is NOT a free-tier-friendly stack. Rough hourly costs while running:

| Resource | Cost |
|---|---|
| EKS control plane | ~$0.10/hr |
| NAT Gateway | ~$0.045/hr + data processing |
| 2x t3.medium nodes | ~$0.0832/hr |
| Network Load Balancer | ~$0.0225/hr |

**Destroy the stack after each session.** Don't leave this running overnight.

## Deploy

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Cluster creation takes 10-15 minutes - the control plane provisioning is slow,
this is normal.

## Connect kubectl

```bash
terraform output -raw configure_kubectl | bash
kubectl get nodes
```

You should see your worker nodes in `Ready` state.

## Deploy nginx

```bash
cd ../k8s
kubectl apply -f nginx-deployment.yaml
kubectl apply -f nginx-service.yaml

# Watch for the LoadBalancer to get an external address (takes 1-2 min)
kubectl get service nginx-service --watch
```

Once `EXTERNAL-IP` populates, `curl` it to confirm nginx is reachable.

## Verify

```bash
# Check pods are running and healthy
kubectl get pods -o wide

# Check the security context actually applied
kubectl get pod <pod-name> -o jsonpath='{.spec.containers[0].securityContext}'

# Check control plane logs are flowing (requires CloudWatch access)
aws logs describe-log-groups --log-group-name-prefix "/aws/eks/eks-portfolio"
```

## Teardown

```bash
# Delete Kubernetes resources first - this also tears down
# the NLB that Terraform doesn't manage directly
kubectl delete -f ../k8s/

# Then destroy the infrastructure
cd ../terraform
terraform destroy
```

Confirm in the AWS console that the NAT Gateway, EKS cluster, and any
load balancers are actually gone - orphaned NLBs from `LoadBalancer`
type services are a common source of surprise billing.

## What's next (Phase 2 preview)

- Falco for runtime security monitoring
- Calico for network policy enforcement
- Image scanning in the deployment pipeline
