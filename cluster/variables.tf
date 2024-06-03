variable "cluster" {
  type = object({
    name             = string
    deployment_id    = string
    kube_state_image = string
    otel_image       = string
  })
}

variable "doit_webhook_url" {
  type    = string
  default = "https://console.doit.com/webhooks/v1/eks-metrics"
}

variable "cluster_oidc_issuer_url" {
  type        = string
  description = "The OIDC Identity issuer URL for the cluster"
  nullable    = false
}

variable "ec2_cluster" {
  type        = bool
  description = "Set to true if this is a self-managed cluster running on EC2"
  default     = false
}

variable "deploy_manifests" {
  type        = bool
  description = "Set to false if you don't want the module to deploy EKS Lens to the cluster"
  default     = true
}

variable "permissions_boundary" {
  type        = string
  description = "If provided, all IAM roles will be created with this permissions boundary attached."
  default     = ""
}
