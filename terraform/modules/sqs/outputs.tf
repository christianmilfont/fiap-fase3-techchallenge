output "queue_url" {
  description = "URL da fila principal."
  value       = aws_sqs_queue.this.url
}

output "queue_arn" {
  description = "ARN da fila principal."
  value       = aws_sqs_queue.this.arn
}

output "queue_name" {
  description = "Nome da fila principal."
  value       = aws_sqs_queue.this.name
}

output "dlq_url" {
  description = "URL da DLQ (null se desabilitada)."
  value       = var.enable_dlq ? aws_sqs_queue.dlq[0].url : null
}
