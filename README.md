# OSPCT Infrastructure - Arquitetura & Guia de Execução

Repositório de infraestrutura AWS corporativa orquestrado com **Terragrunt** e **Terraform**, padronizado de acordo com as melhores práticas de segurança, isolamento em camadas e automação (referência Statpay).

---

## 🏗️ Arquitetura e Módulos

```
prod/us-east-2/
├── networking/
│   ├── vpc/vpc-ospct                 → VPC (10.0.0.0/16), 9 Subnets (Públicas, Privadas, Banco), NAT Gateway e IGW
│   ├── alb-public/                   → Application Load Balancer público (Porta 80 HTTP, entrada controlada)
│   └── security-groups/rds-sg        → Security Group restritivo do RDS (5432 exclusivo para o Bastion SSM)
├── computing/
│   ├── ecr/app-repo                  → Repositório Docker privado com scan de vulnerabilidades (CVE) e retenção
│   ├── ec2/instance-01               → EC2 Bastion em subnet privada com AWS SSM (sem IP público nem SSH)
│   ├── ec2/ecs/                      → ECS clássico com instâncias EC2 gerenciadas (cluster, ec2-node, service-app)
│   └── ecs-fargate/
│       ├── cluster/                  → ECS Cluster Serverless (ospct-fargate-cluster + Container Insights)
│       └── service-app/              → Service Fargate 100% privado atrás do ALB (sem IP público)
├── security/
│   └── secrets-manager/app-secrets   → Cofre de credenciais da aplicação (API keys, JWT, db credentials)
├── database/
│   ├── rds/                          → PostgreSQL RDS padrão corporativo (db.t4g.micro, Free Tier elegível)
│   └── aurora-serverless-v2/         → Amazon Aurora PostgreSQL Serverless v2 (Cluster com 0.5 a 2.0 ACUs)
├── observability/
│   └── cloudwatch-alarms/            → Alarme CloudWatch de métricas (High CPU no ECS Fargate > 80%)
└── message/
    ├── sqs/queue-01/                 → Fila SQS padrão com criptografia SSE gerenciada
    └── ses/                          → Amazon SES Email Identity para envio transacional seguro
```

---

## 📊 Diagrama de Fluxo e Segurança em Camadas

```
                        ┌───────────────────────────────┐
                        │      INTERNET PÚBLICA         │
                        └──────────────┬────────────────┘
                                       │ (HTTP 80)
                                       ▼
                        ┌───────────────────────────────┐
                        │  Application Load Balancer    │  ◄── Subnets Públicas
                        │         (alb-public)          │      (10.0.101-103.0/24)
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

## 🚀 Sequência de Apply (Criar Infraestrutura)

Para respeitar as dependências de rede e segurança, aplique na ordem abaixo:

### 1. Camada de Rede Base
```bash
# 1.1. VPC com subnets públicas, privadas, database e NAT Gateway
cd prod/us-east-2/networking/vpc/vpc-ospct
terragrunt apply --auto-approve

# 1.2. Application Load Balancer Público (Entrada controlada da aplicação)
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

### 4. Camada de Computação e Observabilidade (ECS Fargate)
```bash
# 4.1. Cluster ECS Fargate com Container Insights
cd prod/us-east-2/computing/ecs-fargate/cluster
terragrunt apply --auto-approve

# 4.2. Serviço Fargate Privado integrado ao ALB e Secrets Manager
cd prod/us-east-2/computing/ecs-fargate/service-app
terragrunt apply --auto-approve

# 4.3. Alarme CloudWatch para High CPU (> 80%)
cd prod/us-east-2/observability/cloudwatch-alarms
terragrunt apply --auto-approve
```

---

## 💣 Sequência de Destroy (Destruir Infraestrutura)

Para desmontar o ambiente sem erros de dependência ou recursos órfãos, execute **rigorosamente na ordem inversa**:

```bash
# 0. Alarme do CloudWatch
cd prod/us-east-2/observability/cloudwatch-alarms
terragrunt destroy --auto-approve

# 1. Serviço e Cluster ECS Fargate
cd prod/us-east-2/computing/ecs-fargate/service-app
terragrunt destroy --auto-approve

cd prod/us-east-2/computing/ecs-fargate/cluster
terragrunt destroy --auto-approve

# 2. Application Load Balancer
cd prod/us-east-2/networking/alb-public
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

### 1. Teste de Acesso à Aplicação via ALB
Obtenha o endereço público do Load Balancer e teste a resposta HTTP:
```bash
# Obter o DNS público do ALB
cd prod/us-east-2/networking/alb-public
ALB_DNS=$(terragrunt output -raw dns_name)

# Testar com curl (deve retornar HTTP/1.1 200 OK)
curl -s -I "http://${ALB_DNS}"
```

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
# 1. Login no ECR
aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin 248557779673.dkr.ecr.us-east-2.amazonaws.com

# 2. Tag e Push de imagem com scan automático de vulnerabilidades
docker tag minha-app:latest 248557779673.dkr.ecr.us-east-2.amazonaws.com/ospct-app-repo:latest
docker push 248557779673.dkr.ecr.us-east-2.amazonaws.com/ospct-app-repo:latest
```

---

## 💡 Notas de Arquitetura e Decisões Técnicas

1. **State Lock Nativo no S3 (`use_lockfile = true`)**:
   - A partir do Terraform 1.10+, o bloqueio de concorrência é gerenciado diretamente nos metadados do bucket S3, eliminando a dependência legada de tabelas DynamoDB dedicadas.
2. **Entrada Controlada**:
   - Zero containers Fargate expostos na internet. O Security Group do serviço aceita conexões na porta 8080 exclusivamente a partir do Security Group do ALB.
3. **Gestão de Senhas com Secrets Manager**:
   - O RDS utiliza `manage_master_user_password = true`, fazendo com que a AWS crie, proteja e rotacione a senha de administrador do banco diretamente no Secrets Manager.
4. **Aurora Serverless v2 no Free Tier**:
   - Contas sob o plano Free Tier da AWS impõem a restrição `WithExpressConfiguration` para provisionar clusters Aurora. Para contas nessa modalidade, o módulo `rds/` (`db.t4g.micro`) é a escolha recomendada por ser 100% suportada sem restrições.
5. **Ciclo de Vida para Teardown Rápido**:
   - Parâmetros como `enable_deletion_protection = false`, `skip_final_snapshot = true` e `recovery_window_in_days = 0` garantem que o `terragrunt destroy` limpe a conta integralmente sem custos residuais após sessões de estudo.
