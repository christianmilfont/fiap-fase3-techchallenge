resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = var.namespace
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version

  wait    = true
  timeout = 900

  values = [yamlencode({
    global = {
      domain = var.server_domain
    }
    configs = {
      params = {
        # O LoadBalancer/ingress termina o TLS; sem isso o argocd-server
        # responde 307 em loop atras do proxy.
        "server.insecure" = var.server_service_type != "ClusterIP"
      }
    }
    server = {
      service = {
        type = var.server_service_type
      }
    }
  })]
}

# Bootstrap do app-of-apps: o Terraform cria apenas a Application raiz e todo o
# resto (AppProject + as 5 Applications) vem do Git. Usar o chart argocd-apps em
# vez de kubernetes_manifest evita que o plan precise falar com a API do cluster.
resource "helm_release" "root_app" {
  count = var.enable_root_app ? 1 : 0

  name      = "togglemaster-root"
  namespace = var.namespace

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.apps_chart_version

  values = [yamlencode({
    applications = {
      "togglemaster-root" = {
        namespace  = var.namespace
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        project    = "default"
        source = {
          repoURL        = var.gitops_repo_url
          targetRevision = var.gitops_revision
          path           = var.gitops_argocd_path
          directory = {
            recurse = true
            exclude = "root-app.yaml"
          }
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = var.namespace
        }
        syncPolicy = {
          automated = {
            prune    = true
            selfHeal = true
          }
        }
      }
    }
  })]

  depends_on = [helm_release.argocd]
}
