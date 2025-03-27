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


// https://github.com/open-telemetry/opentelemetry-collector/blob/main/processor/memorylimiterprocessor/README.md
variable "otel_env" {
  type = map(string)
  default = {
    // "GOMEMLIMIT"  = "2750MiB"
  }
}

variable "otel_memory_limiter" {
  type = object({
    check_interval         = string
    limit_percentage       = number
    spike_limit_percentage = number
  })
  default = {
    check_interval         = "1s"
    limit_percentage       = 70
    spike_limit_percentage = 30
  }
}

variable "otel_resources" {
  type = object({
    limits = optional(object({
      cpu    = optional(string)
      memory = optional(string)
    }))
    requests = optional(object({
      cpu    = optional(string)
      memory = optional(string)
      })
  ) })

  default = {}
}

variable "kube_state_tolerations" {
  type = list(object({
    key      = optional(string)
    operator = optional(string)
    value    = optional(string)
    effect   = optional(string)
  }))

  default = []
}

variable "otel_tolerations" {
  type = list(object({
    key      = optional(string)
    operator = optional(string)
    value    = optional(string)
    effect   = optional(string)
  }))

  default = []
}

variable "otel_node_selector" {
  type = map(string)
  default = null
}

variable "kube_state_node_selector" {
  type = map(string)
  default = null
}

variable "kube_image_pull_secrets" {
  type = list(string)
  default = []
}