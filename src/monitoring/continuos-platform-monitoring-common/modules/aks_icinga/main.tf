# -----------------------------------------------------------------------------
# Identità di Icinga nel cluster AKS: un ServiceAccount con un token, a cui si
# legano ClusterRole separati per ogni tipo di check
# -----------------------------------------------------------------------------
data "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_name
  resource_group_name = var.aks_resource_group_name
}

resource "kubernetes_namespace_v1" "icinga" {
  metadata {
    name = "icinga"
  }
}

resource "kubernetes_service_account_v1" "icinga" {
  metadata {
    name      = "icinga"
    namespace = kubernetes_namespace_v1.icinga.metadata[0].name
  }
}

# token senza scadenza legato al ServiceAccount: per ruotarlo basta ricreare il secret
resource "kubernetes_secret_v1" "icinga_token" {
  metadata {
    name      = "icinga-token"
    namespace = kubernetes_namespace_v1.icinga.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.icinga.metadata[0].name
    }
  }

  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

# letto da continuos-platform-monitoring-app per l'header Authorization dei check
resource "azurerm_key_vault_secret" "aks_icinga_token" {
  key_vault_id = var.key_vault_id
  name         = "aks-icinga-token-${data.azurerm_kubernetes_cluster.aks.name}"
  value        = kubernetes_secret_v1.icinga_token.data["token"]
  content_type = "text/plain"

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Permessi: un ClusterRole per tipo di check, tutti legati al ServiceAccount
# -----------------------------------------------------------------------------

# solo gli endpoint di health, nessun accesso alle risorse del cluster
resource "kubernetes_cluster_role_v1" "icinga_health" {
  metadata {
    name = "icinga-health"
  }

  rule {
    non_resource_urls = ["/readyz", "/readyz/*", "/livez", "/livez/*"]
    verbs             = ["get"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "icinga_health" {
  metadata {
    name = "icinga-health"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.icinga_health.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.icinga.metadata[0].name
    namespace = kubernetes_service_account_v1.icinga.metadata[0].namespace
  }
}

# lettura delle risorse sincronizzate da Icinga for Kubernetes (demone sulla VM
# Icinga, https://icinga.com/docs/icinga-for-kubernetes/). Least privilege al
# posto di "*": esclusi secrets (il demone ne salva solo i metadati) e pods/log
# (i log dei container finirebbero nel DB della VM); le relative sync restano
# ferme e loggano l'errore, il resto funziona
resource "kubernetes_cluster_role_v1" "icinga_read" {
  metadata {
    name = "icinga-read"
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces", "nodes", "pods", "services", "configmaps", "persistentvolumes", "persistentvolumeclaims"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets", "statefulsets", "daemonsets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["discovery.k8s.io"]
    resources  = ["endpointslices"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["events.k8s.io"]
    resources  = ["events"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "icinga_read" {
  metadata {
    name = "icinga-read"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.icinga_read.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.icinga.metadata[0].name
    namespace = kubernetes_service_account_v1.icinga.metadata[0].namespace
  }
}

# -----------------------------------------------------------------------------
# kubeconfig del ServiceAccount, usato dal demone Icinga for Kubernetes
# -----------------------------------------------------------------------------
locals {
  kubeconfig = yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{
      name = var.aks_name
      cluster = {
        # FQDN privato se il cluster è privato, altrimenti quello pubblico
        server                     = "https://${coalesce(data.azurerm_kubernetes_cluster.aks.private_fqdn, data.azurerm_kubernetes_cluster.aks.fqdn)}:443"
        certificate-authority-data = base64encode(kubernetes_secret_v1.icinga_token.data["ca.crt"])
      }
    }]
    users = [{
      name = "icinga"
      user = { token = kubernetes_secret_v1.icinga_token.data["token"] }
    }]
    contexts = [{
      name    = var.aks_name
      context = { cluster = var.aks_name, user = "icinga" }
    }]
    current-context = var.aks_name
  })
}
