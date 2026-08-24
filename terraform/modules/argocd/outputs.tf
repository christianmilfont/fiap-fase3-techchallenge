output "namespace" {
  description = "Namespace do ArgoCD."
  value       = helm_release.argocd.namespace
}

output "chart_version" {
  description = "Versão do chart instalada."
  value       = helm_release.argocd.version
}

output "admin_password_command" {
  description = "Comando para ler a senha inicial do usuário admin."
  value       = "kubectl -n ${helm_release.argocd.namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "server_url_command" {
  description = "Comando para descobrir o endereço da UI do ArgoCD."
  value       = "kubectl -n ${helm_release.argocd.namespace} get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}
