output "installed_addons" {
  description = "Add-ons efetivamente instalados por este módulo."
  value = compact([
    var.enable_secrets_store_csi_driver ? "secrets-store-csi-driver" : "",
    var.enable_secrets_store_csi_driver ? "secrets-store-csi-driver-provider-aws" : "",
    var.enable_aws_load_balancer_controller ? "aws-load-balancer-controller" : "",
    var.enable_keda ? "keda" : "",
  ])
}

output "keda_namespace" {
  description = "Namespace onde o KEDA foi instalado."
  value       = var.keda_namespace
}
