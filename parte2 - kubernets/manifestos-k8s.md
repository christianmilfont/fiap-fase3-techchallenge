# Manifestos Kubernetes — ToggleMaster

Implantação dos 5 microserviços no cluster minikube local.
RDS, ElastiCache, SQS e DynamoDB são serviços externos simulados pelo Floci — não rodam como pods.

---

## Dependências entre serviços

```mermaid
graph LR
    subgraph FLOCI ["Floci — serviços AWS emulados (host.minikube.internal)"]
        EXT_REDIS["ElastiCache (Redis)\n:6379"]
        EXT_RDS1["RDS auth-db\n:7001"]
        EXT_RDS2["RDS flag-db\n:7002"]
        EXT_RDS3["RDS targeting-db\n:7003"]
        EXT_SQS["SQS\n:4566"]
        EXT_DDB["DynamoDB\n:4566"]
    end

    AUTH["auth-service\n:8001"] --> EXT_RDS1
    FLAG["flag-service\n:8002"] --> EXT_RDS2
    FLAG --> AUTH
    TARGET["targeting-service\n:8003"] --> EXT_RDS3
    TARGET --> AUTH
    EVAL["evaluation-service\n:8004"] --> FLAG
    EVAL --> TARGET
    EVAL --> EXT_REDIS
    EVAL -->|publica eventos| EXT_SQS
    ANALYTICS["analytics-service\n:8005"] -->|consome| EXT_SQS
    ANALYTICS --> EXT_DDB
```

**DNS cross-namespace:**

- `http://auth-service.auth-service.svc.cluster.local:8001`
- `http://flag-service.flag-service.svc.cluster.local:8002`
- `http://targeting-service.targeting-service.svc.cluster.local:8003`

### O que cada serviço faz

**auth-service (:8001)** — autenticação. Gera `SERVICE_API_KEY` (plaintext retornado uma vez, hash SHA256 salvo no banco). Expõe `GET /auth/validate` (chamado internamente por flag-service e targeting-service para autenticar cada request). Admin endpoint: `POST /auth/admin/keys` requer `MASTER_KEY`.

**flag-service (:8002)** — CRUD das feature flags. Todas as rotas (exceto `/health`) exigem `Bearer SERVICE_API_KEY`. O evaluation-service chama `GET /flags/:name` via DNS interno em caso de **cache MISS**.

**targeting-service (:8003)** — CRUD das regras de segmentação por flag. Mesma autenticação que flag-service. Regra `PERCENTAGE` controla se um `user_id` é incluído (SHA1(`userID+flagName`) % 100). O evaluation-service chama `GET /rules/:name` via DNS interno em cache MISS.

**evaluation-service (:8004)** — hot path sem autenticação. Recebe `GET /evaluate?user_id=...&flag_name=...`. Em **cache MISS**: busca flag-service + targeting-service em paralelo via DNS interno, salva no Redis com TTL 30s. Em **cache HIT**: serve do Redis sem tocar os outros serviços. Sempre envia evento assíncrono para SQS. HPA escala baseado em CPU > 70%.

**analytics-service (:8005)** — worker puro, sem API pública (só `/health`). Consome SQS em loop e grava em DynamoDB. KEDA escala de 0 → N baseado em `ApproximateNumberOfMessages`. Em ambiente local usa Floci para ambos.

**Autenticação — resumo:** `/evaluate` não tem auth (endpoint de cliente). `/flags/*` e `/rules/*` exigem `Bearer SERVICE_API_KEY` (chave criada no bootstrap). `/auth/admin/keys` exige `Bearer MASTER_KEY`. Não há restrição de rede adicional a configurar — o código já impõe isso.

---

## Limpeza pré-deploy

A validação de infra deixa resquícios no Floci (ECR repos de teste, dados) e no minikube (namespace `togglemaster`). Limpar antes de aplicar os manifestos reais.

### Floci — reset completo

Mais seguro que limpeza seletiva: apaga tudo e recria do zero.

```bash
# 1. Derrubar Floci
docker compose -f ./floci/docker-compose.yaml down -v
docker stop floci-ecr-registry floci-valkey-togglemaster-redis floci-rds-auth-db floci-k8s
docker rm floci-ecr-registry floci-valkey-togglemaster-redis floci-rds-auth-db floci-k8s

# 2. Apagar dados persistidos (ECR repos, RDS, SQS, DynamoDB — tudo some)
rm -rf ./floci/floci-k8s-data/

# 3. Subir Floci limpo
docker compose -f ./floci/docker-compose.yaml up -d
sleep 15

# 4. Verificar saúde
curl -s http://localhost:4566/_localstack/health | jq '.services.sqs, .services.rds, .services.ecr, .services.dynamodb, .services.elasticache'
```

Recriar todos os recursos AWS no Floci limpo:

```bash
# SQS
aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request \
  sqs create-queue --queue-name togglemaster-queue

# DynamoDB
aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request \
  dynamodb create-table --table-name ToggleMasterAnalytics \
  --attribute-definitions AttributeName=event_id,AttributeType=S \
  --key-schema AttributeName=event_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

# ElastiCache (Redis) — spawna container valkey/valkey:8 na porta 6379
aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request \
  elasticache create-replication-group \
  --replication-group-id togglemaster-redis \
  --replication-group-description "ToggleMaster Redis" \
  --cache-node-type cache.t3.micro \
  --engine redis \
  --num-cache-clusters 1

# RDS — 3 instâncias independentes
for DB in auth-db flag-db targeting-db; do
  aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request \
    rds create-db-instance \
    --db-instance-identifier $DB \
    --db-instance-class db.t3.micro \
    --engine postgres \
    --master-username postgres \
    --master-user-password postgres \
    --allocated-storage 20
done

# Confirmar portas (esperado: auth-db=7001, flag-db=7002, targeting-db=7003)
aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request \
  rds describe-db-instances \
  --query 'DBInstances[*].[DBInstanceIdentifier,Endpoint.Port]'

# ECR — 5 repositórios para os serviços reais
for SVC in auth-service flag-service targeting-service evaluation-service analytics-service; do
  aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request \
    ecr create-repository --repository-name togglemaster/$SVC
done

# Login ECR
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 \
aws ecr get-login-password --endpoint-url http://localhost:4566 | \
  docker login --username AWS --password-stdin localhost:5100
```

Confirmar que o Redis (valkey) subiu e responde:

```bash
docker ps --format '{{.Names}}\t{{.Image}}' | grep valkey
```

```bash
kubectl run redis-test --rm -i --restart=Never --image=redis:7-alpine -- \
  redis-cli -h host.minikube.internal -p 6379 ping
```

> Esperado: container `floci-valkey-togglemaster-redis` listado e `PONG` no segundo comando. `redis-cli` no host não funciona pelo proxy do Floci — teste sempre de dentro do cluster (`host.minikube.internal`), que é como o `evaluation-service` enxerga.

**Conveniência:** `./floci/floci-init.sh` executa tudo acima (SQS + DynamoDB + RDS + ElastiCache + ECR + docker login) em um comando.

**Preencher:**

- [x] Floci health OK após reset
- [x] SQS: `togglemaster-queue` criada
- [x] DynamoDB: `ToggleMasterAnalytics` criada
- [x] ElastiCache: `togglemaster-redis` → valkey na 6379, PONG de dentro do cluster
- [x] RDS: auth-db=7001, flag-db=7002, targeting-db=7003
- [x] ECR: 5 repos criados, docker login OK

### minikube — limpar namespaces de validação

A validação criou `togglemaster` + os 5 namespaces de produção com `ecr-registry-secret`. Todos precisam sumir — serão recriados pelos manifestos nas ETAPAs 2-7.

```bash
# Deletar tudo que a validação criou (NS E SECRETS)
kubectl delete namespace togglemaster --ignore-not-found
for NS in auth-service flag-service targeting-service evaluation-service analytics-service; do
  kubectl delete namespace $NS --ignore-not-found
done

# Confirmar estado limpo (só keda e infra do minikube devem aparecer)
kubectl get namespaces


# PODS DO KEDA
kubectl get pods -n keda
```

**Preencher:**

- [x] togglemaster deletado
- [x] 5 namespaces de serviço deletados
- [x] KEDA: `kubectl get pods -n keda` → Running

---

## Pré-requisitos

- [x] Floci limpo e recursos recriados (limpeza acima)
- [x] minikube sem namespace `togglemaster` e sem os 5 namespaces de serviço (limpos acima)
- [x] KEDA instalado
- [ ] **`hey`** — CLI de load test HTTP (citado no PDF). Dispara N requisições concorrentes e exibe latência, throughput e distribuição de status codes.

**Instalar `hey`** (requer Go instalado):

```bash
go install github.com/rakyll/hey@latest
```

Binário vai para `~/go/bin/hey`. Verificar:

```bash
hey --version
```

Adicione ao PATH se necessário:

```bash
export PATH=$PATH:~/go/bin
```

---

## Estrutura de arquivos

```
parte2 - kubernets/manifests/
  auth-service/
    namespace.yaml          secret.yaml
    ecr-registry-secret.yaml  configmap.yaml
    deployment.yaml         service.yaml
    ingress.yaml
  flag-service/         (idem)
  targeting-service/    (idem)
  evaluation-service/   (idem + hpa.yaml)
  analytics-service/    (idem + trigger-auth.yaml, scaledobject.yaml)
```

`ecr-registry-secret.yaml` — `type: kubernetes.io/dockerconfigjson`, `.dockerconfigjson` em base64. Gerado via `kubectl create secret docker-registry --dry-run=client -o yaml`. Já commitado.

---

## ETAPA 1 — Build e push das 5 imagens

Roda **após** a limpeza pré-deploy (Floci resetado, ECR repos recriados pelo `floci-init.sh`, namespaces deletados). Os pods criados nas ETAPAs 2-7 puxam a imagem nova — sem necessidade de rollout restart.

Defina o registry uma vez (vale para toda a sessão do terminal):

```bash
REGISTRY=localhost:5100/000000000000
```

Para cada serviço são 2 comandos: build e push. Rode um, olhe o resultado, rode o próximo.

**auth-service**

```bash
docker build --no-cache -t $REGISTRY/togglemaster/auth-service:latest ./auth-service
```

```bash
docker push $REGISTRY/togglemaster/auth-service:latest
```

**flag-service**

```bash
docker build --no-cache -t $REGISTRY/togglemaster/flag-service:latest ./flag-service
```

```bash
docker push $REGISTRY/togglemaster/flag-service:latest
```

**targeting-service**

```bash
docker build --no-cache -t $REGISTRY/togglemaster/targeting-service:latest ./targeting-service
```

```bash
docker push $REGISTRY/togglemaster/targeting-service:latest
```

**evaluation-service**

```bash
docker build --no-cache -t $REGISTRY/togglemaster/evaluation-service:latest ./evaluation-service
```

```bash
docker push $REGISTRY/togglemaster/evaluation-service:latest
```

**analytics-service**

```bash
docker build --no-cache -t $REGISTRY/togglemaster/analytics-service:latest ./analytics-service
```

```bash
docker push $REGISTRY/togglemaster/analytics-service:latest
```

Se um `docker build` der erro, o terminal mostra o erro e você **não roda o push** desse serviço — corrija e rebuilde antes de seguir.

Conferir o que está no registry depois dos pushes:

```bash
curl -s http://localhost:5100/v2/_catalog | jq
```

Ver o sha (digest) de uma imagem específica — útil para anotar e comparar depois de um rebuild:

```bash
curl -sI -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  http://localhost:5100/v2/000000000000/togglemaster/auth-service/manifests/latest \
  | grep -i docker-content-digest
```

### Rebuild incremental (sem apagar o cluster)

Quando só o código de um serviço mudou e o cluster está de pé — não precisa reapagar namespaces. Faça serviço por serviço, um comando de cada vez. Exemplo com `auth-service` (troque o nome para o serviço que você alterou).

**1. Anote o sha atual** (referência para comparar no passo 4):

```bash
curl -sI -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  http://localhost:5100/v2/000000000000/togglemaster/auth-service/manifests/latest \
  | grep -i docker-content-digest
```

**2. Build:**

```bash
docker build -t $REGISTRY/togglemaster/auth-service:latest ./auth-service
```

**3. Push:**

```bash
docker push $REGISTRY/togglemaster/auth-service:latest
```

**4. Confira o sha de novo** — tem que ser **diferente** do passo 1. Se for igual, o push não subiu nada novo (build falhou ou nada mudou) e o rollout vai puxar a imagem velha:

```bash
curl -sI -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  http://localhost:5100/v2/000000000000/togglemaster/auth-service/manifests/latest \
  | grep -i docker-content-digest
```

**5. Reinicie o deployment** (puxa a imagem nova do registry):

```bash
kubectl rollout restart deployment/auth-service -n auth-service
```

**6. Acompanhe o rollout até terminar:**

```bash
kubectl rollout status deployment/auth-service -n auth-service --timeout=90s
```

**7. Veja o pod que está rodando agora:**

```bash
kubectl get pods -n auth-service
```

**8. Leia o log desse pod** (copie o nome do pod do passo 7):

```bash
kubectl logs <NOME-DO-POD> -n auth-service
```

> Durante o rollout existem 2 pods (o velho terminando e o novo). Pegue o nome do pod novo no passo 7 (`STATUS: Running`, `AGE` baixo) antes de ler o log no passo 8. `kubectl logs deployment/auth-service` pode pegar o pod velho e te mostrar o log errado.

> Floci ECR precisa estar de pé e logado (`docker login localhost:5100`). Se o Floci foi reiniciado sem `rm -rf floci-k8s-data/`, os repos ECR ainda existem — só rebuild e push.

---

# BASE TEÓRICA DE APOIO PARA OS MANIFESTOS

## ecr-registry-secret

O Kubernetes guarda credenciais de registry privado (ECR, Docker Hub, etc.) para que os pods consigam puxar imagens.

Formato do conteúdo — é o mesmo JSON do ~/.docker/config.json após um docker login:

{
 "auths": {
 "localhost:5100": {
 "username": "AWS",
 "password": "<token-do-ecr>",
 "auth": "<base64(AWS:<token>)>"
 }
 }
}

Esse JSON inteiro vai em base64 no campo .dockerconfigjson do Secret.

No cluster, todo Deployment que precisa puxar imagem do ECR declara:

imagePullSecrets:

- name: ecr-registry-secret

Kubernetes pega o token do Secret e faz o pull autenticado.

Por que precisa disso no ECR real: o token do ECR expira a cada 12h (aws ecr get-login-password gera um temporário). No Floci local o token é test e nunca expira — mas o Secret existe do mesmo jeito porque os manifestos precisam ser idênticos ao que vai pro EKS.

# Como foi gerado o ecr-registry-secret.yaml no repo:

kubectl create secret docker-registry ecr-registry-secret \
 --docker-server=localhost:5100 \
 --docker-username=AWS \
 --docker-password=test \
 --namespace=auth-service \
 --dry-run=client -o yaml

--dry-run=client -o yaml gera o YAML sem aplicar — daí commitou no repo.

# O que é Ingress

Sem Ingress, cada serviço dentro do cluster só é acessível internamente. O Ingress é um roteador de entrada — recebe requisição de fora e decide qual serviço interno vai responder, baseado no path da URL.

você (navegador/curl)
 │
 ▼
 Nginx Ingress Controller ← um pod no cluster que escuta na porta 80/443
 │
 ├── /auth/... → auth-service:8001
 ├── /flags/... → flag-service:8002
 ├── /rules/... → targeting-service:8003
 ├── /evaluate/... → evaluation-service:8004
 └── /analytics/... → analytics-service:8005

---

# O arquivo linha a linha

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
 name: auth-service-ingress
 namespace: auth-service
 annotations:
 nginx.ingress.kubernetes.io/rewrite-target: /$2 # ← ISSO AQUI
spec:
 ingressClassName: nginx # ← usa o Nginx como controller
 rules:

- http:
  paths:
- path: /auth(/|$)(.*) # ← ESSE REGEX
  pathType: ImplementationSpecific
  backend:
  service:
  name: auth-service
  port:
  number: 8001

### ingressClassName: nginx

Diz qual controller processa esse Ingress. Tem o Nginx instalado no cluster — ele lê esse campo e se responsabiliza pelo roteamento.

### path: /auth(/|$)(.*)

Regex com dois grupos de captura:

- (/|$) → grupo 1: barra ou fim de string
- (.*) → grupo 2: o resto da URL

Exemplos do que casa:
/auth/ ✓
/auth/login ✓
/auth ✓
/authXYZ ✗ (não casa — precisa de barra ou fim)

### annotation: rewrite-target: /$2

Sem isso, o Nginx passaria /auth/login pro serviço — mas o serviço não conhece /auth/. Ele só conhece /login.

O /$2 pega o grupo 2 do regex (o que vem depois de /auth/) e manda só isso pro serviço:

você faz: curl http://$(minikube ip)/auth/login
nginx recebe: /auth/login
nginx extrai $2: login
nginx manda pra auth-service:8001: /login
auth-service vê: GET /login ← correto

Sem o rewrite, auth-service receberia GET /auth/login → 404 porque a rota não existe no app.

### pathType: ImplementationSpecific

Deixa o Nginx interpretar o path como regex. Os outros tipos (Exact e Prefix) não aceitam regex — tratariam /auth(/|$)(.*) como string literal.

---

Resumo em uma linha

▎ Ingress = "se a URL começa com /auth/, corta o /auth/ e manda o resto pro auth-service na porta 8001."

Regex + rewrite (atual — padrão de mercado)

annotations:
 nginx.ingress.kubernetes.io/rewrite-target: /$2
path: /auth(/|$)(.*)

App não muda, Nginx corta o prefixo antes de passar. É o padrão mais documentado porque permite apps sem prefixo (como os nossos) atrás de um único Ingress.

# 

## ETAPA 2 — auth-service

Base de tudo — flag, targeting e evaluation dependem dele.

```bash
kubectl apply -f manifests/auth-service/namespace.yaml
kubectl apply -f manifests/auth-service/ecr-registry-secret.yaml
kubectl apply -f manifests/auth-service/secret.yaml
kubectl apply -f manifests/auth-service/configmap.yaml
kubectl apply -f manifests/auth-service/deployment.yaml
kubectl apply -f manifests/auth-service/service.yaml
kubectl apply -f manifests/auth-service/ingress.yaml

kubectl wait --for=condition=ready pod -l app=auth-service -n auth-service --timeout=90s
kubectl get pods -n auth-service
```

**Preencher:** - [x] auth-service: Running

---

## ETAPA 3 — Bootstrap: SERVICE_API_KEY

`evaluation-service` autentica chamadas ao flag e targeting via API key registrada no auth-service. Precisa ser feito com auth-service já Running.

O Ingress já está no ar — acesse via `minikube ip` direto, sem port-forward.

```bash
minikube ip
```

Anote o IP (ex: `192.168.49.2`). Use ele nos comandos abaixo.

Confirmar que auth-service responde pelo Ingress:

```bash
curl -s http://$(minikube ip)/auth/health
```

Criar a API key:

```bash
curl -s -X POST http://$(minikube ip)/auth/admin/keys \
  -H "Authorization: Bearer local-dev-master-key" \
  -H "Content-Type: application/json" \
  -d '{"name":"evaluation-service"}'
```

A API retorna a key em **plaintext** (ex: `tm_abc123...`). Anote esse valor.

> **Como a key circula no sistema (versão local):**
>
> | Onde                                  | Formato     | Por quê                                                   |
> | ------------------------------------- | ----------- | --------------------------------------------------------- |
> | Retorno da API                        | plaintext   | é o valor real gerado                                     |
> | `curl -H "Authorization: Bearer ..."` | plaintext   | HTTP não usa base64 aqui                                  |
> | `secret.yaml` campo `data:`           | **base64**  | `data:` no K8s exige base64 — diferente do EKS (stringData) |
> | Dentro do pod (env var)               | plaintext   | K8s decodifica base64 ao injetar                          |
> | Banco do auth-service                 | hash SHA256 | nunca armazena a key em si                                |
>
> O banco **nunca viu** a key em plaintext. Por isso a key só aparece uma vez (neste curl) e não pode ser recuperada depois.

Converter e colar em `manifests/evaluation-service/secret.yaml` no campo `SERVICE_API_KEY`:

```bash
echo -n "<valor-da-key>" | base64
```

Cole o valor base64 resultante no campo `SERVICE_API_KEY` do `data:` no secret.yaml.

Esta mesma key (em plaintext) é usada nos curls das ETAPAs 4 e 5 (`Authorization: Bearer <KEY_RETORNADA>`) para criar flags e regras.

**Preencher:** - [ ] secret.yaml `SERVICE_API_KEY` atualizado (valor base64)

---

## ETAPA 4 — flag-service

```bash
kubectl apply -f manifests/flag-service/namespace.yaml
kubectl apply -f manifests/flag-service/ecr-registry-secret.yaml
kubectl apply -f manifests/flag-service/secret.yaml
kubectl apply -f manifests/flag-service/configmap.yaml
kubectl apply -f manifests/flag-service/deployment.yaml
kubectl apply -f manifests/flag-service/service.yaml
kubectl apply -f manifests/flag-service/ingress.yaml

kubectl get pods -n flag-service
```

Com flag-service Running, criar flag de demonstração:

```bash
curl -s -X POST http://$(minikube ip)/flags \
  -H "Authorization: Bearer <SERVICE_API_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"name":"enable-new-dashboard","description":"Feature flag de demonstracao","is_enabled":true}'
```

Esperado: `201` com `"is_enabled": true`.

Confirmar no banco:

```bash
curl -s http://$(minikube ip)/flags \
  -H "Authorization: Bearer <SERVICE_API_KEY>"
```

**Preencher:** - [ ] flag-service: Running - [ ] flag `enable-new-dashboard` criada no RDS

---

## ETAPA 5 — targeting-service

```bash
kubectl apply -f manifests/targeting-service/namespace.yaml
kubectl apply -f manifests/targeting-service/ecr-registry-secret.yaml
kubectl apply -f manifests/targeting-service/secret.yaml
kubectl apply -f manifests/targeting-service/configmap.yaml
kubectl apply -f manifests/targeting-service/deployment.yaml
kubectl apply -f manifests/targeting-service/service.yaml
kubectl apply -f manifests/targeting-service/ingress.yaml

kubectl get pods -n targeting-service
```

> **Padrão para ver logs de qualquer pod:** `kubectl get pods` lista nomes como `targeting-service-64b85d4f89-hgbql`. Use o nome exato ou o seletor de label:
> ```bash
> # Opção 1: nome exato (copie do kubectl get pods acima)
> kubectl logs <POD-NAME> -n targeting-service
> # Exemplo: kubectl logs targeting-service-64b85d4f89-hgbql -n targeting-service
>
> # Opção 2: seletor de label (não precisa copiar o nome)
> kubectl logs -f -l app=targeting-service -n targeting-service
> ```
> Esse mesmo padrão vale para todos os serviços: troque `targeting-service` pelo namespace/label do serviço desejado.

Com targeting-service Running, criar regra de segmentação para a flag:

```bash
curl -s -X POST http://$(minikube ip)/rules \
  -H "Authorization: Bearer <SERVICE_API_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"flag_name":"enable-new-dashboard","rules":{"type":"PERCENTAGE","value":100}}'
```

`value: 100` = 100% dos usuários — todos recebem a flag como `true`.

```bash
curl -s http://$(minikube ip)/rules/enable-new-dashboard \
  -H "Authorization: Bearer <SERVICE_API_KEY>"
```

**Preencher:** - [ ] targeting-service: Running - [ ] regra criada para `enable-new-dashboard`

---

## Escalabilidade — Dois mecanismos independentes

O projeto usa **dois** sistemas de autoscaling distintos. Eles não se comunicam diretamente.

```
┌─────────────────────────────────────────────────────────────────┐
│  MECANISMO 1 — HPA por CPU (ETAPA 6)                           │
│                                                                  │
│  evaluation-service pods                                         │
│       │                                                          │
│       ▼ CPU consumida                                            │
│  Metrics Server  ──→  HPA  ──→  escala evaluation-service       │
│                                                                  │
│  Métrica: uso médio de CPU dos pods                              │
│  Gatilho: CPU média > 70% do request (100m)                     │
│  Arquivo: manifests/evaluation-service/hpa.yaml                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  MECANISMO 2 — KEDA por fila SQS (ETAPA 7)                     │
│                                                                  │
│  fila SQS togglemaster-queue                                     │
│       │                                                          │
│       ▼ ApproximateNumberOfMessages                              │
│  KEDA ScaledObject  ──→  escala analytics-service               │
│                                                                  │
│  Métrica: profundidade da fila SQS                               │
│  Fórmula: réplicas = ceil( msgs_na_fila ÷ 5 )                   │
│  Arquivo: manifests/analytics-service/scaledobject.yaml         │
└─────────────────────────────────────────────────────────────────┘
```

**Conexão indireta**: evaluation-service produz mensagens na SQS ao avaliar flags. Com carga alta (HPA escala evaluation) → mais mensagens → KEDA escala analytics. Mas são dois sistemas independentes com métricas diferentes.

---

## ETAPA 6 — evaluation-service

Secret já preenchido (ETAPA 3). Aplicar tudo + HPA. **Depende do Redis** (ElastiCache criado na limpeza pré-deploy) — sem ele o pod sobe e morre com `Não foi possível conectar ao Redis: connection refused`.

> Aplique arquivo-por-arquivo na ordem abaixo. **Não use `kubectl apply -f .`** na pasta inteira — o namespace é criado no mesmo lote dos recursos que dependem dele e o primeiro apply falha com `namespaces "..." not found`.

```bash
kubectl apply -f manifests/evaluation-service/namespace.yaml
kubectl apply -f manifests/evaluation-service/ecr-registry-secret.yaml
kubectl apply -f manifests/evaluation-service/secret.yaml
kubectl apply -f manifests/evaluation-service/configmap.yaml
kubectl apply -f manifests/evaluation-service/deployment.yaml
kubectl apply -f manifests/evaluation-service/service.yaml
kubectl apply -f manifests/evaluation-service/ingress.yaml
kubectl apply -f manifests/evaluation-service/hpa.yaml

kubectl get pods -n evaluation-service
kubectl get hpa -n evaluation-service
```

**Preencher:** - [ ] evaluation-service: Running - [ ] HPA criado

### 6.0 — Workflow de validação do evaluation-service (cache + SQS)

Requer flag e regra criadas nas ETAPAs 4 e 5. Use 2 terminais.

**Terminal 1 — observar logs do pod ao vivo:**

```bash
kubectl logs -f deployment/evaluation-service -n evaluation-service
```

**Terminal 2 — Passo 1: primeira chamada (cache MISS):**

```bash
curl -s "http://$(minikube ip)/evaluate?user_id=alice&flag_name=enable-new-dashboard"
```

Esperado no Terminal 2: `{"flag_name":"enable-new-dashboard","user_id":"alice","result":true}`

Esperado no Terminal 1 (logs):
```
Cache MISS para flag 'enable-new-dashboard'
Evento de avaliação enviado para SQS (Flag: enable-new-dashboard)
```

O evaluation-service chamou flag-service + targeting-service em paralelo, armazenou o resultado no Redis (TTL 30s) e enviou o evento ao SQS.

**Terminal 2 — Passo 2: segunda chamada imediata (cache HIT):**

```bash
curl -s "http://$(minikube ip)/evaluate?user_id=bob&flag_name=enable-new-dashboard"
```

Esperado no Terminal 1 (logs):
```
Cache HIT para flag 'enable-new-dashboard'
Evento de avaliação enviado para SQS (Flag: enable-new-dashboard)
```

A segunda chamada serviu do Redis — sem chamar flag-service nem targeting-service. `user_id` diferente não importa: a cache key é `flag_info:enable-new-dashboard` (só o nome da flag).

**Terminal 2 — Passo 3: verificar mensagens na fila SQS:**

```bash
aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request \
  sqs get-queue-attributes \
  --queue-url http://localhost:4566/000000000000/togglemaster-queue \
  --attribute-names ApproximateNumberOfMessages
```

Esperado: `"ApproximateNumberOfMessages": "2"` (uma por chamada).

> Após 30s o cache expira. Próxima chamada será MISS novamente.

---

### 6.1 — Testar HPA por CPU (PDF pág. 9 — obrigatório no vídeo)

O PDF exige: *"Gere carga no evaluation-service (com hey, ab ou Postman) e mostre o HPA aumentando as réplicas."*

> Abra 3 terminais lado a lado.

**Terminal 1 — observar HPA ao vivo:**

```bash
kubectl get hpa -n evaluation-service -w
```

Saída antes de escalar:

```
NAME                     TARGETS   MINPODS   MAXPODS   REPLICAS
evaluation-service-hpa   12%/70%   1         5         1
```

**Terminal 2 — observar pods ao vivo:**

```bash
kubectl get pods -n evaluation-service -w
```

**Terminal 3 — disparar carga com `hey`:**

O Ingress já roteia `/evaluate/` para o evaluation-service — sem port-forward.

```bash
hey -z 120s -c 50 "http://$(minikube ip)/evaluate?user_id=utest&flag_name=enable-new-dashboard"
```

- `-z 120s` — dispara por 120 segundos
- `-c 50` — 50 workers concorrentes

Cada request executa o fluxo real: Redis lookup → lógica de avaliação → envia evento ao SQS de forma assíncrona. Gera mensagens SQS como efeito colateral (pode acionar o KEDA em ETAPA 7).

Saída esperada no Terminal 1 com carga ativa (HPA ativou):

```
NAME                     TARGETS   MINPODS   MAXPODS   REPLICAS
evaluation-service-hpa   85%/70%   1         5         3
```

`TARGETS` = `CPU_atual% / CPU_alvo%`. Quando atual > alvo, réplicas sobem. `hey` imprime relatório (latência, req/s, status codes) ao terminar.

Após `Ctrl+C` no Terminal 3, CPU cai → HPA reduz réplicas de volta a 1 (~5 min de estabilização, configurado `stabilizationWindowSeconds: 30`).

> **Antes de continuar para ETAPA 7:** o `hey` gerou mensagens SQS como efeito colateral — KEDA pode ter escalado o analytics-service. Aguarde analytics voltar a 0 réplicas antes do teste de KEDA:
> ```bash
> kubectl get pods -n analytics-service
> ```
> Esperado: nenhum pod listado.

**Preencher:**

- [ ] `TARGETS` > 70% com `hey` rodando
- [ ] REPLICAS > 1 nos Terminais 1 e 2
- [ ] `hey` encerrado (Ctrl+C)

---

## ETAPA 7 — analytics-service + KEDA

**Diferente dos outros serviços.** O deployment tem `replicas: 0` — quem decide quantos pods sobem é o KEDA, olhando a fila SQS. Então, ao contrário das ETAPAs 2-6, **aqui é normal não ter nenhum pod depois do apply.** O que você valida nesta etapa é o KEDA (ScaledObject), não a contagem de pods.

### 7.1 — Aplicar os manifestos

```bash
kubectl apply -f manifests/analytics-service/namespace.yaml
```

```bash
kubectl apply -f manifests/analytics-service/ecr-registry-secret.yaml
```

```bash
kubectl apply -f manifests/analytics-service/secret.yaml
```

```bash
kubectl apply -f manifests/analytics-service/configmap.yaml
```

```bash
kubectl apply -f manifests/analytics-service/deployment.yaml
```

```bash
kubectl apply -f manifests/analytics-service/service.yaml
```

```bash
kubectl apply -f manifests/analytics-service/ingress.yaml
```

```bash
kubectl apply -f manifests/analytics-service/trigger-auth.yaml
```

```bash
kubectl apply -f manifests/analytics-service/scaledobject.yaml
# fonte
https://keda.sh/docs/2.20/scalers/aws-dynamodb-streams/#trigger-specification
```

### 7.2 — Verificar o KEDA (este é o check da etapa)

```bash
kubectl get scaledobject analytics-service-scaler -n analytics-service -w
```

Esperado: `READY=True` e `ACTIVE=False`.

- `READY=True` → KEDA conseguiu falar com a SQS do Floci. **Este é o sinal de que o deploy deu certo.**
- `ACTIVE=False` → fila vazia, então 0 pods. Correto.

> Se `READY=False`, rode
> 
>  `kubectl describe scaledobject analytics-service-scaler -n analytics-service` e olhe os Events. 
> 
> Erro `403 InvalidClientTokenId` = o trigger está batendo na AWS real. O campo de endpoint custom no KEDA 2.x é **`awsEndpoint`** (não `endpoint`) — confira `scaledobject.yaml`.

### 7.3 — Confirmar que está com 0 pods (esperado)

```bash
kubectl get pods -n analytics-service -w
```

Esperado: `No resources found`. **Isso não é erro** — KEDA mantém 0 pods enquanto a fila estiver vazia.

### 7.4 — Provar o autoscaling (0 → N pods)

#### O que o KEDA mede

Métrica monitorada: **`ApproximateNumberOfMessages`** — profundidade da fila SQS (mensagens aguardando processamento). KEDA consulta essa métrica a cada ~30s via API SQS.

**Fórmula de escala** — definida em `scaledobject.yaml`:

```
réplicas = ceil( mensagens_na_fila ÷ queueLength )
                                      └─ linha 15: queueLength = "5"
ceiling, teto: é uma operação matemática que arredonda um número para cima, retornando o menor número inteiro que é maior ou igual ao número original 
```

| Mensagens na fila | Cálculo        | Pods                            |
| ----------------- | -------------- | ------------------------------- |
| 0                 | ceil(0/5)      | 0 — scale to zero               |
| 4                 | ceil(4/5) = 1  | 1                               |
| 6                 | ceil(6/5) = 2  | 2                               |
| 25                | ceil(25/5) = 5 | 5 — teto (`maxReplicaCount: 5`) |

O pod que sobe é o worker que **consome** a fila. Ao drenar as mensagens, a profundidade cai para 0 e o KEDA escala de volta para 0 após o cooldown (~5 min).

---

#### Passo 1 — confirmar estado inicial (fila vazia, 0 pods)

```bash
aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request \
  sqs get-queue-attributes \
  --queue-url http://localhost:4566/000000000000/togglemaster-queue \
  --attribute-names ApproximateNumberOfMessages \
  --query 'Attributes.ApproximateNumberOfMessages'
```

```bash
kubectl get pods -n analytics-service
```

Esperado: `"0"` e `No resources found`.

---

#### Passo 2 — enviar 6 mensagens (formato correto — grava no DynamoDB)

O worker espera JSON com `user_id`, `flag_name`, `result` e `timestamp`. Formato errado → worker falha → **não grava no DynamoDB e não deleta da fila** (mensagem fica em loop).

Envie uma de cada vez — cada send retorna `MessageId` confirmando o recebimento:

```bash
aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request \
  sqs send-message \
  --queue-url http://localhost:4566/000000000000/togglemaster-queue \
  --message-body '{"user_id":"u1","flag_name":"enable-new-dashboard","result":true,"timestamp":"2026-06-29T16:00:00Z"}'
```

```bash
aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request \
  sqs send-message \
  --queue-url http://localhost:4566/000000000000/togglemaster-queue \
  --message-body '{"user_id":"u2","flag_name":"enable-new-dashboard","result":false,"timestamp":"2026-06-29T16:00:01Z"}'
```

```bash
aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request \
  sqs send-message \
  --queue-url http://localhost:4566/000000000000/togglemaster-queue \
  --message-body '{"user_id":"u3","flag_name":"dark-mode","result":true,"timestamp":"2026-06-29T16:00:02Z"}'
```

```bash
aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request \
  sqs send-message \
  --queue-url http://localhost:4566/000000000000/togglemaster-queue \
  --message-body '{"user_id":"u4","flag_name":"dark-mode","result":false,"timestamp":"2026-06-29T16:00:03Z"}'
```

```bash
aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request \
  sqs send-message \
  --queue-url http://localhost:4566/000000000000/togglemaster-queue \
  --message-body '{"user_id":"u5","flag_name":"beta-checkout","result":true,"timestamp":"2026-06-29T16:00:04Z"}'
```

```bash
aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request \
  sqs send-message \
  --queue-url http://localhost:4566/000000000000/togglemaster-queue \
  --message-body '{"user_id":"u6","flag_name":"beta-checkout","result":true,"timestamp":"2026-06-29T16:00:05Z"}'
```

6 mensagens → `ceil(6/5) = 2 pods`. Observe no terminal do watch a métrica `ApproximateNumberOfMessages` subir de 0 para 6.

> Os timestamps acima são valores de exemplo — o analytics-service armazena o que recebe, datas passadas funcionam. O loop do Passo 5 usa `$(date -u +%Y-%m-%dT%H:%M:%SZ)` para timestamps reais.

---

#### Passo 3 — aguardar polling do KEDA (~30s) e confirmar escala

```bash
kubectl get scaledobject analytics-service-scaler -n analytics-service
```

Esperado: `ACTIVE=True`.

```bash
kubectl get pods -n analytics-service
```

Esperado: 1-2 pods `Running`.

> KEDA faz polling a cada ~30s. Se ainda não escalou, espere mais 30s e repita os dois comandos acima.

---

#### Passo 4 — confirmar gravação no DynamoDB (prova o fluxo completo)

Após os pods consumirem a fila, os eventos aparecem na tabela:

```bash
aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request \
  dynamodb scan --table-name ToggleMasterAnalytics \
  --query 'Items[*].[event_id.S, user_id.S, flag_name.S, result.BOOL]' \
  --output text
```

Esperado: 6 linhas — uma por mensagem enviada. Isso fecha o fluxo: **fila SQS → KEDA escala → worker consome → DynamoDB grava**.

---

#### Passo 5 — rajada de 25 mensagens (garante ACTIVE=True)

Se ACTIVE ainda False após os 6 envios do Passo 3, o worker consumiu as mensagens antes do KEDA fazer poll (~30s). Solução: rajada grande para a fila sobreviver o intervalo de polling.

25 mensagens → `ceil(25/5) = 5 pods` = `maxReplicaCount`. KEDA escala no próximo poll (~30s).

> Abra 4 terminais lado a lado antes de enviar as mensagens.

**Terminal 1 — observar ScaledObject ao vivo:**

```bash
kubectl get scaledobject analytics-service-scaler -n analytics-service -w
```

**Terminal 2 — observar pods ao vivo:**

```bash
kubectl get pods -n analytics-service -w
```

**Terminal 3 — logs do analytics-service (aparecem após KEDA escalar):**

```bash
kubectl logs -f -l app=analytics-service -n analytics-service --max-log-requests=5
```

> Os pods começam em 0. Assim que o KEDA escalar, logs de processamento SQS aparecem aqui.

**Terminal 4 — enviar rajada (escolha Opção A ou B):**

**Opção A — direto via AWS CLI (Floci local):**

```bash
for i in $(seq 1 25); do
  aws --endpoint-url http://localhost:4566 --region us-east-1 --no-sign-request \
    sqs send-message \
    --queue-url http://localhost:4566/000000000000/togglemaster-queue \
    --message-body "{\"user_id\":\"u$i\",\"flag_name\":\"enable-new-dashboard\",\"result\":true,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
done
```

**Opção B — via endpoint da aplicação (pipeline real):**

Requer evaluation-service Running e flag `enable-new-dashboard` criada (ETAPA 4).

```bash
for i in $(seq 1 25); do
  curl -s "http://$(minikube ip)/evaluate?user_id=u$i&flag_name=enable-new-dashboard" > /dev/null
done
```

Cada chamada: evaluation-service avalia → envia para SQS de forma assíncrona. 25 chamadas = 25 mensagens na fila.

Aguarde ~30s. Esperado nos Terminais 1 e 2: `ACTIVE=True`, 3-5 pods `Running`. No Terminal 3, logs do worker confirmam processamento de cada mensagem SQS.

---

#### Passo 6 — aguardar scale-down a 0 (opcional — cooldown ~5 min)

Após a fila esvaziar, KEDA aguarda o `cooldownPeriod` (padrão 300s) antes de voltar a 0. Confirme quando quiser:

```bash
kubectl get scaledobject analytics-service-scaler -n analytics-service
```

Quando `ACTIVE=False`: todos os pods voltaram a 0. Comportamento correto.

**Preencher:**

- [x] ScaledObject READY=True após apply (KEDA conectou na SQS)
- [x] Estado inicial: fila=0, pods=0
- [x] Após rajada: métrica ApproximateNumberOfMessages>0, KEDA ACTIVE=True, pods Running
- [x] DynamoDB: itens gravados (fluxo SQS→worker→DynamoDB confirmado)
- [ ] Scale-down: ACTIVE=False, 0 pods (após ~5 min com fila vazia)

---

## ETAPA 8 — Validação via Ingress

```bash
MINIKUBE_IP=$(minikube ip)
curl http://$MINIKUBE_IP/auth/health
curl http://$MINIKUBE_IP/flags/health
curl http://$MINIKUBE_IP/rules/health
curl http://$MINIKUBE_IP/evaluate/health
curl http://$MINIKUBE_IP/analytics/health
```

Rotas:
| Path | Serviço | Porta |
|---|---|---|
| `/auth/...` | auth-service | 8001 |
| `/flags/...` | flag-service | 8002 |
| `/rules/...` | targeting-service | 8003 |
| `/evaluate/...` | evaluation-service | 8004 |
| `/analytics/...` | analytics-service | 8005 |

> analytics-service pode não responder se KEDA ainda não escalou (replicas=0). Enviar mensagem na fila primeiro (ETAPA 9) para forçar escala.

**Preencher:**

- [x] /auth/health: 200 OK
- [x] /flags/health: 200 OK
- [x] /rules/health: 200 OK
- [x] /evaluate/health: 200 OK
- [x] /analytics/health: 200 OK (após scale-up)

---

## Checklist de Validação Consolidado

Confirme que cada item foi executado e passou antes de gravar o vídeo ou fazer o deploy no EKS.

**Infraestrutura local (Floci + minikube)**
- [ ] Floci UP e saudável (`curl localhost:4566/_localstack/health`)
- [ ] minikube UP (`minikube status`)
- [ ] 5 imagens buildadas e no registry local (`docker images | grep togglemaster`)

**Deploy dos serviços**
- [ ] auth-service: pod `1/1 Running` — `kubectl get pods -n auth-service`
- [ ] flag-service: pod `1/1 Running` — `kubectl get pods -n flag-service`
- [ ] targeting-service: pod `1/1 Running` — `kubectl get pods -n targeting-service`
- [ ] evaluation-service: pod `1/1 Running` — `kubectl get pods -n evaluation-service`
- [ ] analytics-service: `0 pods` (esperado — KEDA controla)

**Bootstrap e dados**
- [ ] SERVICE_API_KEY gerada (ETAPA 3) e colocada no secret (base64)
- [ ] Flag `enable-new-dashboard` criada (ETAPA 4): `curl http://$(minikube ip)/flags -H "Bearer <KEY>"`
- [ ] Regra PERCENTAGE 100% criada (ETAPA 5): `curl http://$(minikube ip)/rules/enable-new-dashboard -H "Bearer <KEY>"`

**Validação dos fluxos**
- [ ] Cache MISS no 1º `/evaluate`: log `Cache MISS para flag 'enable-new-dashboard'` (ETAPA 6.0)
- [ ] Cache HIT no 2º `/evaluate`: log `Cache HIT para flag 'enable-new-dashboard'` (ETAPA 6.0)
- [ ] Mensagem na fila SQS após evaluate: `ApproximateNumberOfMessages >= 1` (ETAPA 6.0 Passo 3)

**Escalabilidade**
- [ ] HPA: TARGETS > 70% com `hey` rodando, REPLICAS > 1 (ETAPA 6.1)
- [ ] KEDA: após rajada de 25 msgs, pods analytics passam de 0 para N (ETAPA 7.4 Passo 5)
- [ ] analytics logs: mensagens SQS processadas aparecem no `kubectl logs` (ETAPA 7.4 Passo 5)
- [ ] DynamoDB: `scan` retorna itens com user_id, flag_name, result, timestamp (ETAPA 7.4 Passo 4)

**Ingress (ETAPA 8)**
- [ ] Todos os 5 `/health` retornam 200 OK via `$(minikube ip)`

---

## Convenções (PDF pág. 7-8)

- `imagePullSecrets: [{name: ecr-registry-secret}]` — todo Deployment
- Secrets via `data:` + base64 — nunca plaintext
- ConfigMap para URLs e configs não-sensíveis
- Requests & Limits em todo container
- ReadinessProbe + LivenessProbe em todo container (`/health`)
- analytics-service: `replicas: 0` — KEDA gerencia

## Para Fase C (EKS real)

1. Remover `imagePullSecrets` dos Deployments — IRSA assume

2. Substituir `host.minikube.internal` pelos endpoints reais:
   
   - RDS: endpoint do AWS RDS
   
   - ElastiCache: endpoint do AWS ElastiCache
   
   - SQS/DynamoDB: URLs AWS reais (sem `endpoint_url`)

3. Substituir credenciais fake (`test`) por IRSA — remover `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` dos secrets
