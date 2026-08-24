output "state_bucket_name" {
  description = "Bucket S3 do estado remoto."
  value       = aws_s3_bucket.state.id
}

output "backend_config" {
  description = "Conteúdo sugerido para o backend.hcl da raiz."
  value       = <<-EOT
    bucket = "${aws_s3_bucket.state.id}"
    key    = "${var.project_name}/infra.tfstate"
    region = "${var.aws_region}"
  EOT
}
