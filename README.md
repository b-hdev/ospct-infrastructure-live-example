# OSPCT Infrastructure - Arquitetura & Guia de Execução

Repositório de infraestrutura AWS corporativa orquestrado com **Terragrunt** e **Terraform**, com pipeline CI/CD automatizado via **GitHub Actions** e autenticação federada **OIDC**. Padronizado de acordo com as melhores práticas de segurança, isolamento em camadas e automação (referência Statpay).

---

## 🏗️ Arquitetura e Módulos

```
prod/us-east-2/
├── networking/
│   ├── vpc/vpc-ospct                 → VPC (10.0.0.0/16), 9 Subnets (Públicas, Privadas, Banco), NAT Gateway e IGW
│   ├── alb-public/                   → Application Load Balancer público (HTTPS 443 + Redirect 301 na 80)
│   └── security-groups/rds-sg        → Security Group restritivo do RDS (5432 exclusivo para o Bastion SSM)
├── computing/
│   ├── ecr/app-repo                  → Repositório Docker privado com scan de vulnerabilidades (CVE) e retenção
│   ├── ec2/instance-01               → EC2 Bastion em subnet privada com AWS SSM (sem IP público nem SSH)
│   ├── ec2/ecs/                      → ECS clássico com instâncias EC2 gerenciadas (cluster, ec2-node, service-app)
│   └── ecs-fargate/
│       ├── cluster/                  → ECS Cluster Serverless (ospct-fargate-cluster + Container Insights)
│       └── service-app/              → Service Fargate 100% privado atrás do ALB (imagem ECR, sem IP público)
├── security/
│   ├── acm-certificate/              → Certificado SSL/TLS (X.509 RSA-2048) registrado no AWS ACM para o ALB
│   ├── github-ci-user/               → IAM User GitHub Actions → AWS (least-privilege: ECR push + ECS deploy)
│   └── secrets-manager/app-secrets   → Cofre de credenciais da aplicação (API keys, JWT, db credentials)
├── database/
│   ├── rds/                          → PostgreSQL RDS padrão corporativo (db.t4g.micro, Free Tier elegível)
│   └── aurora-serverless-v2/         → Amazon Aurora PostgreSQL Serverless v2 (Cluster com 0.5 a 2.0 ACUs)
├── observability/
│   ├── sns-alerts/                   → Tópico SNS para disparo de incidentes por e-mail aos responsáveis
│   └── cloudwatch-alarms/            → Alarme CloudWatch de métricas (High CPU no ECS Fargate > 80% via SNS)
└── message/
    ├── sqs/queue-01/                 → Fila SQS padrão com criptografia SSE gerenciada
    └── ses/                          → Amazon SES Email Identity para envio transacional seguro

modules/
├── self-signed-cert/                 → Módulo Terraform: Certificado autoassinado (TLS + ACM import)
└── github-ci-user/                   → Módulo Terraform: IAM User + Access Key + Policies restritas para CI/CD

app/
├── Dockerfile                        → Multi-stage build production-grade (Alpine, non-root, dumb-init)
├── .dockerignore                     → Defense-in-depth (bloqueia .env, .git, secrets do build context)
├── server.js                         → Servidor Node.js HTTP (health check + status na porta 8080)
└── package.json                      → Metadata e scripts da aplicação

.github/workflows/
└── deploy.yml                        → Pipeline CI/CD: Build → Push ECR → Deploy ECS Fargate
```

---

## 📊 Diagrama de Fluxo e Segurança em Camadas

```
                        ┌───────────────────────────────┐
                        │      INTERNET PÚBLICA         │
                        └───────┬───────────────┬───────┘
                                │               │
                       (HTTP 80)│               │(HTTPS 443 Seguro)
                                ▼               │
                 ┌─────────────────────────────┐│
                 │   Redirecionamento 301      ││
                 │  (Força HTTPS Criptografado)││
                 └──────────────┬──────────────┘│
                                └───────┬───────┘
                                        ▼
                        ┌───────────────────────────────┐
                        │  Application Load Balancer    │  ◄── Subnets Públicas
                        │         (alb-public)          │      (10.0.101-103.0/24)
                        │   + Certificado SSL no ACM    │      Portas 80 e 443 abertas
                        └──────────────┬────────────────┘
                                       │ Encaminha tráfego
                                       │ (Porta 8080 interna)
                                       ▼
                        ┌───────────────────────────────┐
                        │     ECS Fargate Service       │  ◄── Subnets Privadas
                        │       (nginx-fargate-app)     │      (10.0.1-3.0/24)
                        └───────┬───────────────┬───────┘      (Sem IP público!)
                                │               │
              Puxa credenciais  │               │ Puxa imagens
                                ▼               ▼
                    ┌──────────────────┐  ┌──────────────────┐
                    │ Secrets Manager  │  │ AWS ECR App Repo │
                    │  (app-secrets)   │  │ (ospct-app-repo) │
                    └──────────────────┘  └──────────────────┘

   ─────────────────────────────────────────────────────────────────────────────
   Notificações e Observabilidade Automática:

   ECS Fargate (CPU > 80%) ──► CloudWatch Alarm ──► Tópico SNS ──► E-mail DevOps

   ─────────────────────────────────────────────────────────────────────────────
   Acesso Administrativo ao Banco (Zero Portas Expostas para a Internet):

   Operador Local
         │
         │ (Túnel Criptografado AWS SSM - Sem SSH / Sem Porta 22)
         ▼
   ┌──────────────────────────────┐
   │    EC2 Bastion SSM Tunnel    │  ◄── Subnet Privada (10.0.1.0/24)
   │  (ec2-ssm-database-tunnel)   │      SG restrito sem portas de entrada
   └──────────────┬───────────────┘
                  │
                  │ Tráfego TCP 5432 exclusivo (rds-sg)
                  ▼
   ┌──────────────────────────────┐
   │   PostgreSQL RDS Database    │  ◄── Subnets de Banco Isoladas
   │    (ospct-rds-postgres)      │      (10.0.201-203.0/24)
   └──────────────────────────────┘
```

---

## 🔄 Pipeline CI/CD (GitHub Actions → ECR → ECS Fargate)

```
  ┌─────────────────────────────────────────────────────────────────────────────┐
  │                         GITHUB ACTIONS PIPELINE                            │
  │                    (.github/workflows/deploy.yml)                          │
  └─────────────────────────────────────────────────────────────────────────────┘

  Push na main (app/**)     ──ou──     Workflow Dispatch (manual)
          │
          ▼
  ┌──────────────┐    OIDC JWT     ┌──────────────────────────┐
  │   Checkout   │───────────────►│  AWS STS AssumeRole      │
  │   Código     │                │  (credenciais temporárias)│
  └──────────────┘                └────────────┬─────────────┘
                                               │
          ┌────────────────────────────────────┘
          ▼
  ┌──────────────┐     ┌──────────────┐     ┌──────────────────────┐
  │  ECR Login   │────►│ Docker Build │────►│  Push ECR            │
  │  (token 12h) │     │ Multi-stage  │     │  Tags: SHA + latest  │
  └──────────────┘     └──────────────┘     └──────────┬───────────┘
                                                       │
          ┌────────────────────────────────────────────┘
          ▼
  ┌────────────────────┐     ┌───────────────────┐     ┌──────────────┐
  │ Download Task Def  │────►│  Update Image     │────►│  Deploy ECS  │
  │ (preserva config)  │     │  (apenas imagem)  │     │  + Stability │
  └────────────────────┘     └───────────────────┘     └──────────────┘
```

**Autenticação:** IAM User com Least Privilege (`security/github-ci-user/`) — permissões estritas para ECR push e ECS deploy.
**Rastreabilidade:** Cada imagem é taggeada com o SHA do commit (7 chars).
**Segurança:** Policies limitadas aos ARNs específicos do repositório ECR e do cluster/serviço ECS.

---

## 🔐 Políticas de Segurança: Produção vs Laboratório

Para manter a conformidade corporativa e garantir que configurações de estudo não vazem para produção real, adotamos os seguintes padrões:

| Recurso / Parâmetro | Em PRODUÇÃO Real (Statpay) | Em LABORATÓRIO / Estudos | Motivo Técnico |
| :--- | :--- | :--- | :--- |
| **`deletion_protection` (DB)** | `true` | `false` | Impede destruição acidental em prod; permite `tg destroy` rápido no lab. |
| **`skip_final_snapshot` (DB)** | `false` | `true` | Garante cópia de segurança antes de apagar; evita custos de snapshot no lab. |
| **`backup_retention_period` (DB)**| `7` a `30` dias | `1` dia | PITR (Point-in-Time Recovery) em prod; limite do AWS Free Tier no lab. |
| **`recovery_window_in_days` (Secrets)** | `7` a `30` dias | `0` dias | Quarentena de recuperação em prod; permite recriação com mesmo nome no lab. |
| **Certificado SSL/TLS (ACM)** | Validado por DNS no Route 53 | Autoassinado importado no ACM | Criptografa tráfego TLS 1.3 sem exigir domínio registrado previamente. |
| **Variáveis de Ambiente (`.env`)** | **Sem fallback padrão (Fail-Fast)** | **Sem fallback padrão (Fail-Fast)** | Aborta na hora se segredos como `APP_API_KEY` ou `AWS_ACCOUNT_ID` faltarem. |
| **Mocks em dependências** | Restritos a `["validate", "init"]` | Restritos a `["validate", "init"]` | Impede que `plan` ou `apply` rodem com IDs fictícios em contas reais. |
| **Autenticação CI/CD** | **OIDC / IAM User Least-Privilege** | **IAM User Least-Privilege (compatível SCP)** | Restrito aos ARNs exatos de ECR e ECS, sem acesso a outros serviços. |
| **Dockerfile** | **Multi-stage, non-root, dumb-init** | **Multi-stage, non-root, dumb-init** | Superfície de ataque mínima (Alpine ~5MB), signal handling correto, UID 1001 dedicado. |

---

## 🔑 Variáveis de Ambiente Obrigatórias

Todas as informações sensíveis ou identificáveis são lidas de variáveis de ambiente via `get_env()` (fail-fast). **Nenhum dado é hardcoded nos arquivos de configuração.**

```bash
# Exportar ANTES de rodar qualquer comando terragrunt
export AWS_ACCOUNT_ID="<seu-account-id-aws-12-digitos>"
```

| Variável | Onde é usada | Falha se ausente |
| :--- | :--- | :--- |
| `AWS_ACCOUNT_ID` | `prod/account.hcl` → remote state S3 bucket | ✅ Sim (fail-fast) |

---

## 🚀 Sequência de Apply (Criar Infraestrutura)

Para respeitar as dependências de rede e segurança, aplique na ordem abaixo:

### 1. Camada de Rede Base e Certificado SSL
```bash
# 1.1. VPC com subnets públicas, privadas, database e NAT Gateway
cd prod/us-east-2/networking/vpc/vpc-ospct
terragrunt apply --auto-approve

# 1.2. Certificado SSL/TLS no AWS ACM (Necessário antes do ALB)
cd prod/us-east-2/security/acm-certificate
terragrunt apply --auto-approve

# 1.3. Application Load Balancer Público (Porta 80 redirect 301 + HTTPS 443)
cd prod/us-east-2/networking/alb-public
terragrunt apply --auto-approve
```

### 2. Segurança, Registry e Mensageria
```bash
# 2.1. Cofre de Segredos da Aplicação (Secrets Manager)
cd prod/us-east-2/security/secrets-manager/app-secrets
terragrunt apply --auto-approve

# 2.2. Repositório Privado de Imagens Docker (AWS ECR)
cd prod/us-east-2/computing/ecr/app-repo
terragrunt apply --auto-approve

# 2.3. Fila de Mensagens (Amazon SQS)
cd prod/us-east-2/message/sqs/queue-01
terragrunt apply --auto-approve

# 2.4. Identidade de E-mail (Amazon SES)
cd prod/us-east-2/message/ses
terragrunt apply --auto-approve

# 2.5. IAM User GitHub Actions → AWS (Credenciais com Least-Privilege)
cd prod/us-east-2/security/github-ci-user
terragrunt apply --auto-approve

# ─────────────────────────────────────────────────────────────────────────────
# 🔑 COMO OBTER E CADASTRAR OS SECRETS NO GITHUB ACTIONS:
#
# 1. Obtenha a Access Key ID gerada pelo Terragrunt:
#    terragrunt output -raw access_key_id
#
# 2. Obtenha a Secret Access Key gerada pelo Terragrunt:
#    terragrunt output -raw secret_access_key
#
# 3. No GitHub: Acesse seu repositório → Settings → Secrets and variables → Actions
#    (URL direta: https://github.com/<org>/<repo>/settings/secrets/actions)
#
# 4. Clique em "New repository secret" e cadastre:
#    - Nome: AWS_ACCESS_KEY_ID      | Valor: <resultado do passo 1>
#    - Nome: AWS_SECRET_ACCESS_KEY  | Valor: <resultado do passo 2>
#
# 💡 Caso precise rotacionar as chaves no futuro:
#    aws iam create-access-key --user-name ospct-github-actions-deployer
# ─────────────────────────────────────────────────────────────────────────────
```

### 3. Camada de Dados e Bastion Seguro
```bash
# 3.1. Host Bastion Privado gerenciado via AWS SSM
cd prod/us-east-2/computing/ec2/instance-01
terragrunt apply --auto-approve

# 3.2. Security Group do Banco de Dados
cd prod/us-east-2/networking/security-groups/rds-sg
terragrunt apply --auto-approve

# 3.3. Banco de Dados PostgreSQL:
# Opção A: RDS PostgreSQL tradicional (Elegível a Free Tier)
cd prod/us-east-2/database/rds
terragrunt apply --auto-approve

# Opção B: Aurora PostgreSQL Serverless v2 (0.5 a 2.0 ACUs)
cd prod/us-east-2/database/aurora-serverless-v2
terragrunt apply --auto-approve
```

### 4. Camada de Computação e Observabilidade (ECS Fargate + SNS)
```bash
# 4.1. Cluster ECS Fargate com Container Insights
cd prod/us-east-2/computing/ecs-fargate/cluster
terragrunt apply --auto-approve

# 4.2. Serviço Fargate Privado integrado ao ALB e Secrets Manager
cd prod/us-east-2/computing/ecs-fargate/service-app
terragrunt apply --auto-approve

# 4.3. Tópico SNS para envio de Alertas por e-mail
cd prod/us-east-2/observability/sns-alerts
terragrunt apply --auto-approve

# 4.4. Alarme CloudWatch para High CPU (> 80%) com disparo para o SNS
cd prod/us-east-2/observability/cloudwatch-alarms
terragrunt apply --auto-approve

# 4.5. Push da primeira imagem Docker para o ECR (necessário antes do ECS iniciar)
cd app
docker build -t ospct-app .
ECR_URL=$(cd ../prod/us-east-2/computing/ecr/app-repo && terragrunt output -raw repository_url)
aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin "${ECR_URL%%/*}"
docker tag ospct-app:latest "${ECR_URL}:latest"
docker push "${ECR_URL}:latest"
```

---

## 💣 Sequência de Destroy (Destruir Infraestrutura)

Para desmontar o ambiente sem erros de dependência ou recursos órfãos, execute **rigorosamente na ordem inversa**:

```bash
# 0. Observabilidade e Alarmes
cd prod/us-east-2/observability/cloudwatch-alarms
terragrunt destroy --auto-approve

cd prod/us-east-2/observability/sns-alerts
terragrunt destroy --auto-approve

# 0.5. IAM User CI/CD (GitHub Actions)
cd prod/us-east-2/security/github-ci-user
terragrunt destroy --auto-approve

# 1. Serviço e Cluster ECS Fargate
cd prod/us-east-2/computing/ecs-fargate/service-app
terragrunt destroy --auto-approve

cd prod/us-east-2/computing/ecs-fargate/cluster
terragrunt destroy --auto-approve

# 2. Application Load Balancer e Certificado ACM
cd prod/us-east-2/networking/alb-public
terragrunt destroy --auto-approve

cd prod/us-east-2/security/acm-certificate
terragrunt destroy --auto-approve

# 3. Banco de Dados e Security Group
# Se utilizou RDS:
cd prod/us-east-2/database/rds
terragrunt destroy --auto-approve

# Se utilizou Aurora Serverless v2:
cd prod/us-east-2/database/aurora-serverless-v2
terragrunt destroy --auto-approve

cd prod/us-east-2/networking/security-groups/rds-sg
terragrunt destroy --auto-approve

# 4. Host Bastion Seguro
cd prod/us-east-2/computing/ec2/instance-01
terragrunt destroy --auto-approve

# 5. Segurança, Registry e Mensageria
cd prod/us-east-2/message/ses
terragrunt destroy --auto-approve

cd prod/us-east-2/message/sqs/queue-01
terragrunt destroy --auto-approve

cd prod/us-east-2/computing/ecr/app-repo
terragrunt destroy --auto-approve

cd prod/us-east-2/security/secrets-manager/app-secrets
terragrunt destroy --auto-approve

# 6. VPC, Subnets e NAT Gateway (Base da rede, destrói por último)
cd prod/us-east-2/networking/vpc/vpc-ospct
terragrunt destroy --auto-approve
```

---

## 🔗 Testes e Validação Prática

### 1. Teste de Redirecionamento HTTP (80) -> HTTPS (443) no ALB
```bash
# Obter o DNS público do ALB
cd prod/us-east-2/networking/alb-public
ALB_DNS=$(terragrunt output -raw dns_name)

# 1. Testar requisição HTTP na porta 80 (deve retornar 301 Moved Permanently com Location HTTPS)
curl -s -I "http://${ALB_DNS}"

# 2. Testar requisição HTTPS direta na porta 443 (deve retornar HTTP 200 OK do container privado)
curl -k -s -I "https://${ALB_DNS}"
```
*(A flag `-k` é usada apenas no curl para aceitar certificados autoassinados em ambiente de laboratório).*

### 2. Acesso Seguro ao PostgreSQL via Túnel SSM (Port Forwarding)
Sem abrir a porta 22 na internet e sem IP público na instância ou no banco, abra um túnel local diretamente para a porta 5432 do PostgreSQL:

```bash
# 1. Obter o Instance ID do Bastion e o Endpoint do RDS
INSTANCE_ID=$(cd prod/us-east-2/computing/ec2/instance-01 && terragrunt output -raw id)
RDS_ENDPOINT=$(cd prod/us-east-2/database/rds && terragrunt output -raw db_instance_address)

# 2. Iniciar o túnel seguro na sua máquina local (porta 5432)
aws ssm start-session \
  --target "${INSTANCE_ID}" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"${RDS_ENDPOINT}\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"5432\"]}"

# 3. Em outro terminal, conecte com seu cliente favorito (psql, DBeaver, TablePlus):
psql -h localhost -p 5432 -U dbadmin -d appdb
```

### 3. Push de Imagem no Repositório Privado AWS ECR
```bash
# 1. Obter o URL do ECR dinamicamente (sem hardcoding de Account ID)
ECR_URL=$(cd prod/us-east-2/computing/ecr/app-repo && terragrunt output -raw repository_url)

# 2. Login no ECR
aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin "${ECR_URL%%/*}"

# 3. Build, Tag e Push (com scan automático de vulnerabilidades)
cd app
docker build -t ospct-app .
docker tag ospct-app:latest "${ECR_URL}:latest"
docker push "${ECR_URL}:latest"
```

### 4. Testar Pipeline CI/CD (GitHub Actions)

> [!IMPORTANT]
> **Pré-requisito:** Certifique-se de ter cadastrado os secrets `AWS_ACCESS_KEY_ID` e `AWS_SECRET_ACCESS_KEY` no GitHub (**Settings → Secrets and variables → Actions**), conforme o **Passo 2.5**.

```bash
# Qualquer push na branch main com alterações em app/ dispara o pipeline:
git add app/
git commit -m "feat: deploy via CI/CD"
git push origin main

# Acompanhe em: https://github.com/b-hdev/ospct-infrastructure-live-example/actions
# O pipeline faz: Build → Push ECR (tag SHA) → Deploy ECS → Wait Stability
```

---

## 💡 Notas de Arquitetura e Decisões Técnicas

1. **State Lock Nativo no S3 (`use_lockfile = true`)**:
   - A partir do Terraform 1.10+, o bloqueio de concorrência é gerenciado diretamente nos metadados do bucket S3, eliminando a dependência legada de tabelas DynamoDB dedicadas.
2. **Entrada Controlada com Criptografia TLS**:
   - O tráfego público entra exclusivamente pelo ALB. A porta 80 força o redirecionamento permanente (HTTP_301) para a porta 443 (HTTPS), e o ALB entrega a requisição descriptografada na porta 8080 para os containers Fargate privados via Security Group restrito.
3. **Gestão de Senhas com Secrets Manager**:
   - O RDS utiliza `manage_master_user_password = true`, fazendo com que a AWS crie, proteja e rotacione a senha de administrador do banco diretamente no Secrets Manager.
4. **Aurora Serverless v2 no Free Tier**:
   - Contas sob o plano Free Tier da AWS impõem a restrição `WithExpressConfiguration` para provisionar clusters Aurora. Para contas nessa modalidade, o módulo `rds/` (`db.t4g.micro`) é a escolha recomendada por ser 100% suportada sem restrições.
5. **Ciclo de Vida para Teardown Rápido**:
   - Parâmetros como `enable_deletion_protection = false`, `skip_final_snapshot = true` e `recovery_window_in_days = 0` garantem que o `terragrunt destroy` limpe a conta integralmente sem custos residuais após sessões de estudo.
6. **CI/CD com Least-Privilege (Compatível com SCP)**:
   - Em organizações AWS com Service Control Policies (SCPs) que restringem OIDC Providers, um IAM User dedicado (`ospct-github-actions-deployer`) com policies restritas exclusivamente aos ARNs de ECR (`PushPull`) e ECS (`UpdateService`) garante total segurança sem violar governança.
7. **Dockerfile Multi-Stage Production-Grade**:
   - Imagem Alpine mínima (~5MB), usuário non-root dedicado (UID 1001), `dumb-init` para signal handling correto (PID 1 problem), `npm ci --omit=dev` para builds determinísticos, HEALTHCHECK nativo, e COPY seletivo (nunca `COPY . .`).
8. **Fail-Fast para Variáveis de Ambiente**:
   - Informações sensíveis (`AWS_ACCOUNT_ID`) são lidas via `get_env()` sem fallback. Se estiver ausente, o Terragrunt aborta imediatamente com erro explícito antes de qualquer operação.
