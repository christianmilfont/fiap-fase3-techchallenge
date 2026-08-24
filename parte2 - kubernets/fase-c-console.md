# Fase C — Console AWS (verificação visual e alternativa ao CLI)

Documento complementar ao `fase-c-eks.md`. Cobre dois usos:
1. **Alternativa**: criar recursos via Console em vez de CLI
2. **Verificação**: confirmar visualmente o que o CLI criou

---

## Account ID

Console → canto superior direito → clique no nome da conta → o número de 12 dígitos é o Account ID.

---

## ETAPA 1 — SQS

### Criar via Console
1. Console → **SQS** → **Create queue**
2. Type: **Standard**
3. Queue name: `togglemaster-queue`
4. Deixe todas as configurações padrão → **Create queue**

### Verificar no Console
Console → SQS → `togglemaster-queue` → aba **Details**
- Status: Active
- URL: `https://sqs.us-east-1.amazonaws.com/<ACCOUNT_ID>/togglemaster-queue`

---

## ETAPA 1 — DynamoDB

### Criar via Console
1. Console → **DynamoDB** → **Create table**
2. Table name: `ToggleMasterAnalytics`
3. Partition key: `event_id` (tipo: String)
4. Table settings: **Customize** → Capacity mode: **On-demand**
5. **Create table**

### Verificar no Console
Console → DynamoDB → Tables → `ToggleMasterAnalytics`
- Status: Active
- Partition key: event_id (S)

---

## ETAPA 1 — ECR (5 repositórios)

### Criar via Console
1. Console → **ECR** → **Create repository** (repita 5 vezes)
2. Visibility: **Private**
3. Repository name (um por vez):
   - `togglemaster/auth-service`
   - `togglemaster/flag-service`
   - `togglemaster/targeting-service`
   - `togglemaster/evaluation-service`
   - `togglemaster/analytics-service`
4. Deixe demais opções padrão → **Create repository**

### Verificar no Console
Console → ECR → Repositories → deve listar os 5 repositórios.

---

## ETAPA 2 — Cluster EKS

> Usar `eksctl` via CLI — não há alternativa equivalente de console que gere OIDC + node group + IAM em um passo só.

### Verificar no Console
Console → **EKS** → Clusters → `togglemaster`
- Status: **Active**
- Kubernetes version: 1.28+
- Aba **Compute** → Node groups → `standard-workers` → 2 nodes **Ready**
- Aba **Configuration** → **Authentication** → OIDC provider URL presente

### Capturar VPC e subnets via Console
Console → **EKS** → Clusters → `togglemaster` → aba **Networking**
- VPC ID: anotar
- Subnets: anotar pelo menos 2 privadas (AZs diferentes)
- Cluster security group: anotar

---

## ETAPA 3 — RDS

### DB Subnet Group via Console
1. Console → **RDS** → **Subnet groups** → **Create DB subnet group**
2. Name: `togglemaster-db-subnet-group`
3. VPC: selecione a VPC do EKS
4. Add subnets: selecione as 2 subnets privadas anotadas
5. **Create**

### Security Group para RDS via Console
1. Console → **EC2** → **Security Groups** → **Create security group**
2. Name: `togglemaster-rds-sg`
3. VPC: VPC do EKS
4. Inbound rules → **Add rule**:
   - Type: **PostgreSQL** (porta 5432)
   - Source: selecione o security group dos nodes EKS (o cluster SG anotado)
5. **Create security group** → anote o SG ID

### Criar RDS auth-db via Console
1. Console → **RDS** → **Create database**
2. Engine: **PostgreSQL** → versão 15
3. Templates: **Free tier** (ou Dev/Test para t3.micro)
4. DB instance identifier: `togglemaster-auth-db`
5. Master username: `postgres`
6. Master password: `<SENHA_FORTE>` (anote)
7. DB instance class: `db.t3.micro`
8. Storage: 20 GiB
9. Connectivity:
   - VPC: VPC do EKS
   - DB subnet group: `togglemaster-db-subnet-group`
   - Public access: **No**
   - VPC security group: selecione `togglemaster-rds-sg`
10. **Create database**

Repita para `togglemaster-flag-db` e `togglemaster-targeting-db`.

### Verificar RDS no Console
Console → RDS → Databases → cada instância deve mostrar **Available**
- Clique na instância → aba **Connectivity** → **Endpoint** (anote)

---

## ETAPA 3 — ElastiCache

### Cache Subnet Group via Console
1. Console → **ElastiCache** → **Subnet groups** → **Create subnet group**
2. Name: `togglemaster-cache-subnet-group`
3. VPC: VPC do EKS
4. Subnets: selecione as 2 privadas
5. **Create**

### Security Group para ElastiCache via Console
1. Console → **EC2** → **Security Groups** → **Create security group**
2. Name: `togglemaster-cache-sg`
3. VPC: VPC do EKS
4. Inbound rules → **Add rule**:
   - Type: **Custom TCP** → porta `6379`
   - Source: security group dos nodes EKS
5. **Create security group**

### Criar ElastiCache (Redis) via Console
1. Console → **ElastiCache** → **Create replication group**
2. Engine: **Redis**
3. Engine version: 7.0
4. Replication group ID: `togglemaster-redis`
5. Node type: `cache.t3.micro`
6. Number of replicas: **0** (single node)
7. Subnet group: `togglemaster-cache-subnet-group`
8. Security groups: `togglemaster-cache-sg`
9. **Create**

### Verificar ElastiCache no Console
Console → ElastiCache → Redis → `togglemaster-redis` → Status: **Available**
- Primary endpoint: anote (ex: `togglemaster-redis.xxx.ng.0001.use1.cache.amazonaws.com`)

---

## ETAPA 4 — ECR Login e Push de imagens

### Verificar imagens no Console após push
Console → **ECR** → Repositories → clique em cada repositório → aba **Images**
- Deve aparecer a tag `latest` com data e tamanho recentes

---

## ETAPA 5 — IRSA (IAM)

> Usar `eksctl create iamserviceaccount` — é o método recomendado para conta pessoal.

### Verificar policies no Console
Console → **IAM** → **Policies** → filtrar por `togglemaster`
- `togglemaster-analytics-policy`: deve estar presente
- `togglemaster-evaluation-policy`: deve estar presente

### Verificar roles IRSA no Console
Console → **IAM** → **Roles** → filtrar por `togglemaster`
- `eksctl-togglemaster-addon-iamserviceaccount-...` (duas roles criadas pelo eksctl)
- Clique em cada uma → aba **Trust relationships** → deve ter o OIDC provider do cluster como `Principal`
- Aba **Permissions** → deve ter a policy correspondente anexada

---

## ETAPA 6 — Helm (Metrics Server, KEDA, Nginx Ingress)

### Verificar Metrics Server no Console
Não aparece no console AWS — verificar via kubectl:
```bash
kubectl get deployment metrics-server -n kube-system
```

### Verificar Load Balancer criado pelo Nginx Ingress
Console → **EC2** → **Load Balancers**
- Deve aparecer um NLB (Network Load Balancer) criado automaticamente pelo Nginx Ingress
- Estado: **Active**
- DNS name: este é o `<LB-DNS>` usado nos curls da ETAPA 9

---

## ETAPA 8 — Verificar pods e deployments no Console

### Via Console EKS
Console → **EKS** → Clusters → `togglemaster` → aba **Resources** → **Workloads**
- Filtre por namespace (auth-service, flag-service, etc.)
- Cada Deployment deve mostrar pods **Running**

### Via kubectl (mais rápido)
```bash
kubectl get pods -A
```

---

## ETAPA 9 — Verificar DynamoDB no Console (após KEDA test)

Console → **DynamoDB** → Tables → `ToggleMasterAnalytics` → aba **Explore items**
- Deve mostrar os itens gravados pelo analytics-service
- Cada item tem: `event_id`, `user_id`, `flag_name`, `result`, `timestamp`

---

## TEARDOWN — Verificar que tudo foi destruído

### SQS
Console → SQS → a fila `togglemaster-queue` não deve existir

### DynamoDB
Console → DynamoDB → Tables → `ToggleMasterAnalytics` não deve existir

### RDS
Console → RDS → Databases → nenhuma instância `togglemaster-*`

### ElastiCache
Console → ElastiCache → Redis → nenhum `togglemaster-redis`

### EKS
Console → EKS → Clusters → nenhum `togglemaster`

### Load Balancer
Console → EC2 → Load Balancers → nenhum NLB do cluster (deve ter sido removido pelo helm uninstall ingress-nginx)

### NAT Gateway
Console → VPC → NAT Gateways → estado **Deleted** (pode levar alguns minutos)

### IAM Roles e Policies
Console → IAM → Roles → nenhuma role `eksctl-togglemaster-*`
Console → IAM → Policies → nenhuma policy `togglemaster-*`

### Cost Explorer (dia seguinte)
Console → **Billing** → **Cost Explorer** → verificar que não há custos em andamento de EC2, RDS, ElastiCache, NAT Gateway.
