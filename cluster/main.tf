data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id         = data.aws_caller_identity.current.account_id
  region             = data.aws_region.current.region
  s3_bucket          = "doitintl-eks-metrics-${local.account_id}-${local.region}"
  s3_policy_arn      = "arn:aws:iam::${local.account_id}:policy/doit_eks_lens_s3_${local.region}"
  cluster_issuer_url = replace(var.cluster_oidc_issuer_url, "https://", "")
}

// Policy to allow the EKS Lens pod to interact with the S3 bucket
data "aws_iam_policy_document" "doit_eks_lens_collector" {
  count = var.ec2_cluster ? 0 : 1

  statement {
    effect = "Allow"

    principals {
      type = "Federated"
      identifiers = [
        "arn:aws:iam::${local.account_id}:oidc-provider/${local.cluster_issuer_url}",
      ]
    }

    actions = [
      "sts:AssumeRoleWithWebIdentity",
    ]

    condition {
      test = "StringEquals"
      values = [
        "system:serviceaccount:${var.namespace}:doit-collector",
      ]
      variable = "${local.cluster_issuer_url}:sub"
    }

    condition {
      test = "StringEquals"
      values = [
        "sts.amazonaws.com",
      ]
      variable = "${local.cluster_issuer_url}:aud"
    }
  }
}

resource "aws_iam_role" "doit_eks_lens_collector" {
  count = var.ec2_cluster ? 0 : 1

  name                 = "doit_eks_${local.region}_${var.cluster.name}"
  assume_role_policy   = data.aws_iam_policy_document.doit_eks_lens_collector[count.index].json
  permissions_boundary = var.permissions_boundary
}

resource "aws_iam_role_policy_attachment" "doit_eks_lens_collector" {
  count = var.ec2_cluster ? 0 : 1

  role       = aws_iam_role.doit_eks_lens_collector[count.index].name
  policy_arn = local.s3_policy_arn
}

// Required if running EKS Lens Collector on a self-managed cluster on EC2
resource "aws_iam_user" "doit_eks_lens_collector" {
  count = var.ec2_cluster ? 1 : 0
  name  = "doit_eks_lens_collector_${local.region}_${var.cluster.name}"
  path  = "/"

  force_destroy = true
}

resource "aws_iam_access_key" "doit_eks_lens_collector" {
  count = var.ec2_cluster ? 1 : 0
  user  = aws_iam_user.doit_eks_lens_collector[count.index].id
}

resource "aws_iam_user_policy_attachment" "iam_policy" {
  count      = var.ec2_cluster ? 1 : 0
  policy_arn = local.s3_policy_arn
  user       = aws_iam_user.doit_eks_lens_collector[count.index].name
}

// Wait 60s for collector to run and start writing metrics to S3
resource "time_sleep" "wait_60_seconds" {
  count      = var.deploy_manifests ? 1 : 0
  depends_on = [kubernetes_deployment.collector]

  create_duration = "60s"
}

// Register/de-register cluster on DoiT
resource "null_resource" "doit_webhook_create" {
  count      = var.deploy_manifests ? 1 : 0
  depends_on = [time_sleep.wait_60_seconds]

  provisioner "local-exec" {
    when       = create
    command    = <<EOT
    curl -X POST -H 'Content-Type: application/json' -d '{
      "account_id": "${local.account_id}",
      "region": "${local.region}",
      "cluster_name": "${var.cluster.name}",
      "deployment_id": "${var.cluster.deployment_id}"
    }' ${var.doit_webhook_url}/terraform-validate
    EOT
    on_failure = fail # in case this fails, the resources will be tainted and a re-apply will be necessary
  }

}

resource "null_resource" "doit_webhook_destroy" {
  count = var.deploy_manifests ? 1 : 0

  triggers = {
    account_id    = local.account_id
    region        = local.region
    cluster_name  = var.cluster.name
    deployment_id = var.cluster.deployment_id
    webhook_url   = var.doit_webhook_url
  }

  provisioner "local-exec" {
    when       = destroy
    command    = <<EOT
    curl -X POST -H 'Content-Type: application/json' -d '{
      "account_id": "${self.triggers.account_id}",
      "region": "${self.triggers.region}",
      "cluster_name": "${self.triggers.cluster_name}",
      "deployment_id": "${self.triggers.deployment_id}"
    }' ${self.triggers.webhook_url}/terraform-destroy
    EOT
    on_failure = fail # in case this fails, the resources will be tainted and a re-apply will be necessary
  }
}
