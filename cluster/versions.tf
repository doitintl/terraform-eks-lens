terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.100"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.2"
    }
  }
  required_version = ">= 1.5.0"
}
