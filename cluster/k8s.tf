locals {
  namespace = "doit-eks-metrics"

  base_labels = {
    "app.kubernetes.io/name" = "doit_eks_lens"
  }

  kube_state_metrics_labels = merge(
    local.base_labels,
    { "app.kubernetes.io/component" = "doit-kube-state-metrics" }
  )

  doit_collector_labels = merge(
    local.base_labels,
    { "app.kubernetes.io/component" = "doit-collector" }
  )

  doit_collector_deployment_labels = merge(
    local.doit_collector_labels,
    { "doit.com/metrics-deployment-id" = var.cluster.deployment_id }
  )
}

resource "kubernetes_namespace_v1" "doit_eks_metrics" {
  count = var.deploy_manifests ? 1 : 0

  metadata {
    name = local.namespace
  }
}

resource "kubernetes_service_account" "doit_kube_state_metrics" {
  count = var.deploy_manifests ? 1 : 0

  metadata {
    name      = "doit-kube-state-metrics"
    namespace = kubernetes_namespace_v1.doit_eks_metrics[count.index].metadata[0].name
  }
}

resource "kubernetes_cluster_role" "doit_kube_state_metrics" {
  count = var.deploy_manifests ? 1 : 0

  metadata {
    name   = "doit-kube-state-metrics"
    labels = local.kube_state_metrics_labels
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps", "nodes", "pods", "services", "serviceaccounts", "resourcequotas", "replicationcontrollers", "limitranges", "persistentvolumeclaims", "persistentvolumes", "namespaces", "endpoints"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["statefulsets", "daemonsets", "deployments", "replicasets"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["cronjobs", "jobs"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = ["authentication.k8s.io"]
    resources  = ["tokenreviews"]
    verbs      = ["create"]
  }

  rule {
    api_groups = ["authorization.k8s.io"]
    resources  = ["subjectaccessreviews"]
    verbs      = ["create"]
  }

  rule {
    api_groups = ["policy"]
    resources  = ["poddisruptionbudgets"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = ["certificates.k8s.io"]
    resources  = ["certificatesigningrequests"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = ["discovery.k8s.io"]
    resources  = ["endpointslices"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses", "volumeattachments"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = ["admissionregistration.k8s.io"]
    resources  = ["mutatingwebhookconfigurations", "validatingwebhookconfigurations"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["networkpolicies", "ingressclasses", "ingresses"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["clusterrolebindings", "clusterroles", "rolebindings", "roles"]
    verbs      = ["list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "doit_kube_state_metrics" {
  count = var.deploy_manifests ? 1 : 0

  metadata {
    name   = "doit-kube-state-metrics"
    labels = local.kube_state_metrics_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.doit_kube_state_metrics[count.index].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.doit_kube_state_metrics[count.index].metadata[0].name
    namespace = local.namespace
  }
}

resource "kubernetes_deployment" "kube_state_metrics" {
  count = var.deploy_manifests ? 1 : 0

  metadata {
    name      = "kube-state-metrics"
    namespace = kubernetes_namespace_v1.doit_eks_metrics[count.index].metadata[0].name
    labels    = local.kube_state_metrics_labels
  }

  spec {
    replicas = 1

    selector {
      match_labels = local.kube_state_metrics_labels
    }

    template {
      metadata {
        labels = local.kube_state_metrics_labels
      }

      spec {
        service_account_name            = kubernetes_service_account.doit_kube_state_metrics[count.index].metadata[0].name
        automount_service_account_token = true

        dynamic "image_pull_secrets" {
          for_each = var.kube_image_pull_secrets
          content {
            name = image_pull_secrets.value
          }
        }

        container {
          name  = "kube-state-metrics"
          image = var.cluster.kube_state_image

          image_pull_policy = "IfNotPresent"

          env {
            name = "NODE_NAME"
            value_from {
              field_ref {
                api_version = "v1"
                field_path  = "spec.nodeName"
              }
            }
          }

          args = [
            "--port=8080",
            "--resources=cronjobs,daemonsets,deployments,jobs,nodes,pods,replicasets,replicationcontrollers,resourcequotas,statefulsets",
            "--metric-labels-allowlist=pods=[*],nodes=[*]",
          ]

          port {
            container_port = 80
            name           = "http-metrics"
          }

          liveness_probe {
            failure_threshold = 3
            http_get {
              path   = "/healthz"
              port   = 8080
              scheme = "HTTP"
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            success_threshold     = 1
            timeout_seconds       = 5
          }

          readiness_probe {
            failure_threshold = 3
            http_get {
              path   = "/"
              port   = 8080
              scheme = "HTTP"
            }
          }
        }

        dynamic "toleration" {
          for_each = var.kube_state_tolerations
          content {
            key      = toleration.value.key
            operator = toleration.value.operator
            value    = toleration.value.value
            effect   = toleration.value.effect
          }
        }

        node_selector = try(var.kube_state_node_selector, null)

      }
    }
  }
}

resource "kubernetes_service" "kube_state_metrics" {
  count = var.deploy_manifests ? 1 : 0

  metadata {
    name      = "kube-state-metrics"
    namespace = kubernetes_namespace_v1.doit_eks_metrics[count.index].metadata[0].name
    labels    = local.kube_state_metrics_labels
  }

  spec {
    port {
      name        = "http-metrics"
      port        = 8080
      target_port = 8080
    }

    selector = local.kube_state_metrics_labels
  }
}

resource "kubernetes_service_account" "doit_collector" {
  count = var.deploy_manifests ? 1 : 0

  metadata {
    name      = "doit-collector"
    namespace = kubernetes_namespace_v1.doit_eks_metrics[count.index].metadata[0].name
    labels    = local.doit_collector_labels

    // conditionally add the eks.amazonaws.com/role-arn annotation if the AWS access key is not provided (used for ec2 cluster deployments)
    annotations = {
      "eks.amazonaws.com/role-arn" = var.ec2_cluster == false ? aws_iam_role.doit_eks_lens_collector[count.index].arn : ""
    }
  }
}

resource "kubernetes_cluster_role" "doit_otel" {
  count = var.deploy_manifests ? 1 : 0

  metadata {
    name   = "doit-otel"
    labels = local.doit_collector_labels
  }

  rule {
    api_groups = [""]
    resources  = ["events", "namespaces", "namespaces/status", "nodes", "nodes/spec", "nodes/stats", "nodes/proxy", "pods", "pods/status", "replicationcontrollers", "replicationcontrollers/status", "resourcequotas", "services"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["daemonsets", "deployments", "replicasets", "statefulsets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["extensions"]
    resources  = ["daemonsets", "deployments", "replicasets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    verbs      = ["create", "get", "list", "update"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "nodes", "endpoints"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["nodes/proxy"]
    verbs      = ["get"]
  }

  rule {
    api_groups = [""]
    resources  = ["nodes/stats", "configmaps", "events"]
    verbs      = ["create", "get"]
  }

  rule {
    api_groups     = [""]
    resources      = ["configmaps"]
    resource_names = ["otel-container-insight-clusterleader"]
    verbs          = ["get", "update"]
  }
}

resource "kubernetes_cluster_role_binding" "doit_otel" {
  count = var.deploy_manifests ? 1 : 0

  metadata {
    name   = "doit-otel"
    labels = local.doit_collector_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.doit_otel[count.index].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.doit_collector[count.index].metadata[0].name
    namespace = local.namespace
  }
}

resource "kubernetes_config_map" "doit_collector_config" {
  count = var.deploy_manifests ? 1 : 0

  metadata {
    name      = "doit-collector-config"
    namespace = kubernetes_namespace_v1.doit_eks_metrics[count.index].metadata[0].name
    labels    = local.doit_collector_deployment_labels
  }

  data = {
    "collector.yaml" = "${templatefile(
      "${path.module}/collector-config.yaml",
      {
        doit_metrics_deployment_id = var.cluster.deployment_id
        collector_bucket_name      = local.s3_bucket
        collector_bucket_prefix    = "eks-metrics/${local.account_id}/${local.region}/${var.cluster.name}"
        region                     = local.region
        check_interval             = var.otel_memory_limiter.check_interval
        limit_percentage           = var.otel_memory_limiter.limit_percentage
        spike_limit_percentage     = var.otel_memory_limiter.spike_limit_percentage
      }
    )}"
  }
}

// Conditionally create a secret with AWS credentials if cluster is self-managed running on EC2
resource "kubernetes_secret" "collector_aws_credentials" {
  count = var.deploy_manifests && var.ec2_cluster ? 1 : 0

  metadata {
    name      = "aws-credentials"
    namespace = kubernetes_namespace_v1.doit_eks_metrics[count.index].metadata[0].name
    labels    = local.doit_collector_deployment_labels
  }

  data = {
    AWS_ACCESS_KEY_ID     = aws_iam_access_key.doit_eks_lens_collector[count.index].id
    AWS_SECRET_ACCESS_KEY = aws_iam_access_key.doit_eks_lens_collector[count.index].secret
  }

  type = "kubernetes.io/generic"
}

resource "kubernetes_deployment" "collector" {
  count = var.deploy_manifests ? 1 : 0

  depends_on = [kubernetes_config_map.doit_collector_config]

  metadata {
    name      = "collector"
    namespace = kubernetes_namespace_v1.doit_eks_metrics[count.index].metadata[0].name
    labels    = local.doit_collector_deployment_labels
  }

  spec {
    replicas = 1

    selector {
      match_labels = local.doit_collector_deployment_labels
    }

    template {
      metadata {
        labels = local.doit_collector_deployment_labels
      }

      spec {
        restart_policy       = "Always"
        service_account_name = kubernetes_service_account.doit_collector[count.index].metadata[0].name

        dynamic "image_pull_secrets" {
          for_each = var.kube_image_pull_secrets
          content {
            name = image_pull_secrets.value
          }
        }

        container {
          name  = "otelcol"
          image = var.cluster.otel_image

          image_pull_policy = "IfNotPresent"

          args = ["--config=/conf/collector.yaml"]

          // conditionally mount AWS credentials if provided (used for ec2 cluster deployments)
          dynamic "env_from" {
            for_each = var.ec2_cluster ? [true] : []
            content {
              secret_ref {
                name = kubernetes_secret.collector_aws_credentials[count.index].metadata[0].name
              }
            }
          }

          env {
            name = "K8S_NODE_NAME"
            value_from {
              field_ref {
                api_version = "v1"
                field_path  = "spec.nodeName"
              }
            }
          }

          env {
            name = "POD_NAME"
            value_from {
              field_ref {
                api_version = "v1"
                field_path  = "metadata.name"
              }
            }
          }

          env {
            name = "HOST_IP"
            value_from {
              field_ref {
                field_path = "status.hostIP"
              }
            }
          }

          env {
            name = "HOST_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }

          env {
            name = "K8S_NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }

          dynamic "env" {
            for_each = var.otel_env
            content {
              name  = env.key
              value = env.value
            }
          }

          resources {
            requests = var.otel_resources.requests
            limits   = var.otel_resources.limits
          }

          volume_mount {
            mount_path = "/conf"
            name       = "doit-collector-config"
            read_only  = true
          }

          liveness_probe {
            failure_threshold = 3
            http_get {
              path   = "/"
              port   = 13133
              scheme = "HTTP"
            }
            period_seconds    = 10
            success_threshold = 1
            timeout_seconds   = 1
          }
        }

        volume {
          name = "doit-collector-config"

          config_map {
            default_mode = "0640"
            name         = "doit-collector-config"

            items {
              key  = "collector.yaml"
              path = "collector.yaml"
            }
          }
        }

        dynamic "toleration" {
          for_each = var.otel_tolerations
          content {
            key      = toleration.value.key
            operator = toleration.value.operator
            value    = toleration.value.value
            effect   = toleration.value.effect
          }
        }

        node_selector = try(var.otel_node_selector, null)

      }
    }
  }
}
