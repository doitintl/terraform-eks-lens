variable "permissions_boundary" {
  type        = string
  description = "If provided, all IAM roles will be created with this permissions boundary attached."
  default     = ""
}
