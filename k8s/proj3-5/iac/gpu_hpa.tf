# Step 17: Deploy Helm charts for GPU metrics
resource "helm_release" "kube_prometheus_stack" {
  count = var.cluster_settings.create && var.application_settings.create && var.gpu_autoscaler.enabled ? 1 : 0

  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  name             = "kube-prometheus-stack"
  namespace        = "prometheus"
  create_namespace = true

  depends_on = [
    kubernetes_deployment.deployment,
  ]
}

resource "helm_release" "prometheus_adapter" {
  count = var.cluster_settings.create && var.application_settings.create && var.gpu_autoscaler.enabled ? 1 : 0

  name       = "prometheus-adapter"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-adapter"

  namespace = kubernetes_namespace.namespace[0].metadata[0].name

  set {
    name  = "rbac.create"
    value = "true"
  }

  set {
    name  = "prometheus.url"
    value = "http://kube-prometheus-stack-prometheus.prometheus.svc.cluster.local"
  }

  set {
    name  = "prometheus.port"
    value = "9090"
  }

  depends_on = [
    helm_release.kube_prometheus_stack,
  ]
}

resource "helm_release" "dcgm_exporter" {
  count = var.cluster_settings.create && var.application_settings.create && var.gpu_autoscaler.enabled ? 1 : 0

  repository = "https://nvidia.github.io/gpu-monitoring-tools/helm-charts"
  chart      = "dcgm-exporter"
  name       = "dcgm-exporter"
  namespace  = kubernetes_namespace.namespace[0].metadata[0].name

  depends_on = [
    helm_release.kube_prometheus_stack,
    helm_release.prometheus_adapter,
  ]
}

# Step 18: Create Kubernetes HPA-based on GPU metrics 
resource "kubernetes_horizontal_pod_autoscaler_v2beta2" "gpu_autoscaler" {
  count = var.cluster_settings.create && var.application_settings.create && var.gpu_autoscaler.enabled ? 1 : 0

  metadata {
    name      = var.application_settings.name
    namespace = kubernetes_namespace.namespace[0].metadata[0].name
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.deployment[0].metadata[0].name
    }

    min_replicas = var.gpu_autoscaler.min_replicas
    max_replicas = var.gpu_autoscaler.max_replicas

    metric {
      type = "Object"
      object {
        described_object {
          api_version = "apps/v1"
          kind        = "Service"
          name        = "dcgm-exporter"
        }
        metric {
          name = "DCGM_FI_DEV_GPU_UTIL"
        }
        target {
          type                = "Value"
          average_utilization = var.gpu_autoscaler.target_value
        }
      }
    }
  }

  depends_on = [
    helm_release.kube_prometheus_stack,
    helm_release.prometheus_adapter,
    helm_release.dcgm_exporter,
  ]
}
