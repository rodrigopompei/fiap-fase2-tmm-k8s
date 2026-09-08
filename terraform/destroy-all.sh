#!/usr/bin/env bash
#
# Destroys all infrastructure: EKS cluster, RDS, ElastiCache, ALB, VPC, etc.
#
# WARNING: This is destructive and irreversible. All data will be deleted.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                     ⚠️  DESTROY WARNING  ⚠️                      ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║ This will DELETE:                                              ║"
echo "║   • EKS cluster (eks-tc3-lab-001)                              ║"
echo "║   • All Kubernetes resources (services, deployments, etc)      ║"
echo "║   • RDS database (all data lost)                               ║"
echo "║   • ElastiCache (Redis)                                        ║"
echo "║   • Load Balancer                                              ║"
echo "║   • VPC and all networking                                     ║"
echo "║   • Secrets Manager entries                                    ║"
echo "║   • ECR repositories                                           ║"
echo "║                                                                ║"
echo "║ This CANNOT be undone.                                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo
read -p "Type 'yes' to confirm destruction: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

echo
echo "Destroying infrastructure..."
cd "$SCRIPT_DIR"

terraform destroy -auto-approve -input=false

echo
echo "✅ Destruction complete."
echo
echo "The bootstrap stack (S3 bucket + DynamoDB table) remains:"
echo "  • toggle-master-tfstate-056007986659"
echo "  • toggle-master-tflock"
echo
echo "To restore: cd terraform && terraform apply -auto-approve -input=false"
