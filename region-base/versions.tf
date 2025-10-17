terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.17"
    }

  }
  required_version = ">= 1.5.0"
}
