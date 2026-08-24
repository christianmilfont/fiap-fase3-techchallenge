terraform {
  # Estado remoto em S3. O bucket é criado por ./bootstrap.
  # Os valores concretos ficam em backend.hcl (nao versionado):
  #   terraform init -backend-config=backend.hcl
  backend "s3" {
    key = "togglemaster/infra.tfstate"
    # use_lockfile habilita o lock nativo do S3 (Terraform >= 1.11),
    # dispensando a tabela DynamoDB de lock.
    use_lockfile = true
    encrypt      = true
  }
}
