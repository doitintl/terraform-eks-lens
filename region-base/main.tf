data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

// S3 Bucket for EKS Lens artifacts
resource "aws_s3_bucket" "doit_eks_lens" {
  bucket        = "doitintl-eks-metrics-${local.account_id}-${local.region}"
  force_destroy = true
}

resource "aws_s3_bucket_lifecycle_configuration" "doit_eks_lens" {
  bucket = aws_s3_bucket.doit_eks_lens.id

  rule {
    id = "ExpiredDocumentsRule"

    expiration {
      days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    status = "Enabled"
  }
}

// S3 Policy
data "aws_iam_policy_document" "doit_eks_lens_s3" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.doit_eks_lens.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${aws_s3_bucket.doit_eks_lens.arn}/*"]
  }
}

resource "aws_iam_policy" "doit_eks_lens" {
  name   = "doit_eks_lens_s3_${local.region}"
  policy = data.aws_iam_policy_document.doit_eks_lens_s3.json
}

// Grant DoiT access to the EKS Lens S3 bucket
data "aws_iam_policy_document" "doit_eks_lens_import" {
  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::068664126052:root"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "doit_eks_lens_import" {
  name               = "doitintl_eks_import_${local.region}"
  assume_role_policy = data.aws_iam_policy_document.doit_eks_lens_import.json
  permissions_boundary = var.permissions_boundary

  tags = {
    Name = "doitintl_eks_import_${local.region}"
  }

}

resource "aws_iam_role_policy_attachment" "doit_eks_lens_import" {
  role       = aws_iam_role.doit_eks_lens_import.name
  policy_arn = aws_iam_policy.doit_eks_lens.arn
}
