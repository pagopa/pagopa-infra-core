resource "kubernetes_namespace" "keda" {
  metadata {
    name = "keda"
    labels = {
      domain = "core" # Icinga Business Process domain (continuos-platform-monitoring-app)
    }
  }
}

resource "helm_release" "keda" {
  name       = "keda"
  chart      = "keda"
  repository = "https://kedacore.github.io/charts"
  version    = var.keda_helm.chart_version
  namespace  = kubernetes_namespace.keda.metadata[0].name
}
