# Guia Prático para Vídeo de Demonstração - Terraform IaC
## ToggleMaster - Fase 3

## 🎥 Script Sugerido para o Vídeo (10-15 minutos)

### Parte 1: Introdução e Estrutura (2-3 minutos)

```bash
# Navegar para o diretório do Terraform
cd terraform

# Mostrar estrutura do projeto
ls -la
tree -L 2 -I '.terraform' # se tiver tree instalado
# ou
Get-ChildItem -Recurse -Depth 2
```

**Falar sobre:**
- Organização em módulos
- Separação por ambientes (dev/prod)
- Módulos principais: networking, eks, rds, elasticache, etc.

---

### Parte 2: Inicialização e Plan (3-4 minutos)

```bash
# Verificar se já tem backend.hcl configurado
ls -la backend.hcl

# Se não tiver, copiar o exemplo
cp backend.hcl.example backend.hcl
# Editar com as credenciais do AWS Academy
# (não mostrar credenciais no vídeo)

# Inicializar o Terraform
terraform init -backend-config=backend.hcl

# Executar terraform plan para ver o que será criado
terraform plan -out=tfplan
```

**Explicar durante o plan:**
- Quantos recursos serão criados
- Principais recursos: VPC, EKS, RDS, etc.
- Terraform calcula automaticamente dependências
- Mostrar que é uma execução "dry-run" (não aplica mudanças)

---

### Parte 3: Terraform Apply (3-4 minutos)

```bash
# Aplicar as mudanças
terraform apply tfplan
```

**Falar durante o apply:**
- Terraform criando recursos na ordem correta
- Dependências sendo resolvidas automaticamente
- Tempo estimado para cada recurso
- VPC → Subnets → EKS → RDS → ElastiCache → etc.

---

### Parte 4: Verificação dos Recursos (3-4 minutos)

```bash
# Verificar outputs do Terraform
terraform output -json

# Verificar URLs dos bancos de dados
terraform output -json database_urls

# Verificar URL do Redis
terraform output -raw redis_url

# Verificar URL da fila SQS
terraform output -raw sqs_queue_url

# Verificar URLs dos repositórios ECR
terraform output -json ecr_repository_urls

# Configurar acesso ao cluster EKS
terraform output -raw kubeconfig_command | bash

# Verificar nós do cluster
kubectl get nodes

# Verificar pods do sistema
kubectl get pods -n kube-system
```

**Falar sobre:**
- Outputs fornecem informações importantes para os aplicativos
- URLs de bancos, Redis, SQS serão usadas nos secrets/configmaps
- ECR URLs serão usadas nos deployments
- Acesso ao cluster via kubeconfig

---

### Parte 5: Verificação na AWS Console (2-3 minutos)

**Navegar no console AWS e mostrar:**

1. **VPC** (EC2 → Virtual Private Cloud)
   - VPC criada
   - Subnets públicas e privadas
   - Route tables
   - NAT Gateway

2. **EKS** (Elastic Kubernetes Service)
   - Cluster criado
   - Node groups
   - Status do cluster

3. **RDS** (Relational Database Service)
   - 3 instâncias PostgreSQL
   - togglemaster-auth-db
   - togglemaster-flag-db
   - togglemaster-targeting-db

4. **ElastiCache**
   - Cluster Redis
   - togglemaster-redis

5. **DynamoDB**
   - Tabela ToggleMasterAnalytics
   - Partition key: event_id

6. **SQS** (Simple Queue Service)
   - Fila togglemaster-queue
   - Dead Letter Queue

7. **ECR** (Elastic Container Registry)
   - 5 repositórios
   - togglemaster/auth-service
   - togglemaster/flag-service
   - togglemaster/targeting-service
   - togglemaster/evaluation-service
   - togglemaster/analytics-service

---

### Parte 6: ArgoCD Instalado via Terraform (2-3 minutos)

```bash
# Verificar pods do ArgoCD
kubectl get pods -n argocd

# Verificar serviço do ArgoCD
kubectl get svc -n argocd

# Obter senha inicial do admin
terraform output -raw argocd_admin_password_command | bash

# Obter URL do servidor ArgoCD
terraform output -raw argocd_server_url_command | bash
```

**Falar sobre:**
- ArgoCD foi instalado via módulo Terraform
- Isso é infraestrutura, não pipeline
- Helm chart oficial usado
- ArgoCD estará pronto para GitOps

---

### Parte 7: Security no Terraform (1-2 minutos)

```bash
# Mostrar configuração de security scanning
cat .checkov.yaml

# Verificar IAM roles criadas automaticamente
# (via console AWS ou aws cli)
aws iam list-roles | grep togglemaster

# Mostrar security groups
aws ec2 describe-security-groups --filters Name=group-name,Values=*togglemaster*
```

**Falar sobre:**
- IAM roles automáticas para EKS
- Security groups configurados
- Checkov/Trivy para security scanning
- Security as code

---

## 🎯 Comandos Alternativos (Caso não tenha backend configurado)

### Opção 1: Usar ambiente dev (se já configurado)

```bash
cd terraform/environments/dev

# Verificar se tem backend.hcl
ls -la backend.hcl

# Se não tiver
cp ../../backend.hcl.example backend.hcl
# Editar com suas credenciais

# Inicializar
terraform init -backend-config=backend.hcl

# Plan
terraform plan -var-file="dev.tfvars" -out=tfplan

# Apply
terraform apply tfplan
```

### Opção 2: Bootstrap (se for primeira vez)

```bash
cd terraform/bootstrap

# Criar bucket S3 para estado
terraform init
terraform apply

# Pegar configuração do backend
terraform output backend_config

# Voltar para o diretório principal
cd ..

# Criar backend.hcl com o output
# (copiar o output e editar o arquivo)
```

---

## 🔧 Troubleshooting Comum

### Erro: Backend não configurado

```bash
# Verificar se backend.hcl existe
ls -la backend.hcl

# Se não existir, copiar o exemplo
cp backend.hcl.example backend.hcl

# Editar com suas credenciais AWS Academy
```

### Erro: Credenciais AWS expiradas (AWS Academy)

```bash
# Configurar novas credenciais
aws configure

# Ou exportar variáveis de ambiente
export AWS_ACCESS_KEY_ID="sua_key"
export AWS_SECRET_ACCESS_KEY="sua_secret"
export AWS_SESSION_TOKEN="seu_token"
```

### Erro: Provider não instalado

```bash
# Re-inicializar o Terraform
terraform init -upgrade
```

### Erro: Lock no state

```bash
# Se alguém else estiver aplicando mudanças
# Esperar ou forçar unlock (cuidado!)
terraform force-unlock <LOCK_ID>
```

---

## 📝 Checklist para o Vídeo

### Antes de gravar:
- [ ] Ter credenciais AWS Academy configuradas
- [ ] Ter backend.hcl configurado corretamente
- [ ] Ter executado `terraform init` recentemente
- [ ] Verificar que não há mudanças pendentes
- [ ] Ter acesso ao console AWS

### Durante a gravação:
- [ ] Explicar cada comando antes de executar
- [ ] Mostrar outputs importantes
- [ ] Navegar no console AWS para verificar recursos
- [ ] Falar sobre segurança (IAM, security groups)
- [ ] Explicar integração com CI/CD e GitOps

### Depois da gravação:
- [ ] Verificar que todos os recursos foram criados
- [ ] Limpar recursos se necessário (terraform destroy)
- [ ] Documentar qualquer problema encontrado

---

## 🎓 Pontos-Chave para Enfatizar

1. **Declarativo**: Descreve o estado desejado, não os passos
2. **Idempotente**: Executar múltiplas vezes é seguro
3. **State Management**: Estado no S3 permite colaboração
4. **Modularidade**: Código organizado e reutilizável
5. **Security**: IAM roles, security groups, scanning
6. **Integração**: Prepara para CI/CD e GitOps

---

## ⚠️ Notas Importantes

### AWS Academy
- Credenciais são temporárias (expiram)
- Podem precisar ser renovadas durante o vídeo
- Ter credenciais de backup prontas

### Custos
- Recursos criados geram custos na AWS
- Lembre-se de destruir após o vídeo: `terraform destroy`
- Principalmente EKS, RDS, ElastiCache

### Tempo
- Terraform apply pode levar 10-15 minutos
- Planeje o tempo do vídeo accordingly
- Pode acelerar partes da gravação

### Múltiplas Execuções
- Se já rodou antes, `terraform plan` mostrará "No changes"
- Para demonstrar criação, pode usar `terraform destroy` primeiro
- Ou focar na explicação do código existente

---

## 🚀 Comandos Rápidos de Referência

```bash
# Inicialização
terraform init -backend-config=backend.hcl

# Plan
terraform plan -out=tfplan

# Apply
terraform apply tfplan

# Outputs
terraform output -json
terraform output -json database_urls
terraform output -raw redis_url
terraform output -raw sqs_queue_url
terraform output -json ecr_repository_urls

# Acesso ao cluster
terraform output -raw kubeconfig_command | bash
kubectl get nodes

# ArgoCD
kubectl get pods -n argocd
terraform output -raw argocd_admin_password_command | bash

# Destroy (limpeza)
terraform destroy
```

---

## 📚 Recursos Adicionais

- **Documentação Terraform**: https://www.terraform.io/docs
- **Provider AWS**: https://registry.terraform.io/providers/hashicorp/aws/latest
- **Módulos EKS**: https://registry.terraform.io/modules/terraform-aws-modules/eks/aws
- **ArgoCD**: https://argoproj.github.io/argo-cd/

---

**Boa sorte com a apresentação!** 🎥