# OSPCT Infrastructure - Sequência de Execução & Arquitetura

Repositório de infraestrutura AWS orquestrado com **Terragrunt** e **Terraform**.

---

## 🏗️ Arquitetura e Módulos

```
prod/us-east-2/
├── networking/
│   ├── vpc/vpc-ospct                 → VPC, Subnets (públicas e privadas), NAT Gateway
│   ├── alb-public/                   → Application Load Balancer público (porta 80 HTTP, entrada controlada)
│   └── security-groups/rds-sg        → Security Group do RDS (libera porta 5432 para EC2)
├── computing/
│   ├── ecr/app-repo                  → Repositório Docker privado com scan de vulnerabilidades e retenção de imagens
│   ├── ec2/instance-01               → EC2 Bastion em subnet privada com AWS SSM (sem IP público nem SSH)
│   ├── ec2/ecs/                      → ECS clássico com instâncias EC2 gerenciadas (cluster, ec2-node, service-app)
│   └── ecs-fargate/
│       ├── cluster/                  → ECS Cluster Serverless (ospct-fargate-cluster + Spot)
│       └── service-app/              → Service Fargate 100% privado atrás do ALB (sem IP público)
├── security/
│   └── secrets-manager/app-secrets   → Cofre de credenciais da aplicação (API keys, JWT)
├── database/
│   ├── rds/                          → PostgreSQL RDS tradicional (mono-instância)
│   └── aurora-serverless-v2/         → Amazon Aurora PostgreSQL Serverless v2 (0.5 a 2.0 ACUs)
├── observability/
│   └── cloudwatch-alarms/            → Alarmes de métricas (High CPU no ECS Fargate)
└── message/
    ├── sqs/queue-01/                 → Fila SQS padrão (módulo local)
    └── ses/                          → Amazon SES Email Identity para envio transacional (módulo local)
```

---

## 📊 Diagrama de Dependências

```
                        ┌─────────────┐
                        │     VPC     │
                        └──────┬──────┘
             ┌─────────────────┼──────────────────────────┐
             │                 │                          │
             ▼                 ▼                          ▼
      ┌──────────────┐   ┌────────────┐            ┌──────────────┐
      │  EC2 Stand.  │   │  RDS SG    │            │  ECS Cluster │
      │(instance-01) │   └─────┬──────┘            │(EC2 / Fargate│
      └──────┬───────┘         │                   └──────┬───────┘
             └────────┬────────┘                          │
                      ▼                                   ▼
               ┌─────────────┐                     ┌──────────────┐
               │   RDS DB    │                     │ ECS Service  │
               └─────────────┘                     │(Task Def 8080│
                                                   └──────┬───────┘
                                                          │ (injeta segredos)
 ┌──────────────────────┐                          ┌──────▼───────┐
 │   Mensageria AWS     │                          │Secrets Manager
 │  SQS  │     SES      │                          │(app-secrets) │
 └───────┴──────────────┘                          └──────────────┘
```

---

## 🚀 Apply (Criar Infraestrutura)

Execute na ordem de dependência — os componentes base primeiro:

### 1. Rede Base
```bash
# 1.1. VPC, Subnets públicas/privadas e NAT Gateway
cd prod/us-east-2/networking/vpc/vpc-ospct
tg apply

# 1.2. Application Load Balancer Público (Entrada controlada da aplicação)
cd prod/us-east-2/networking/alb-public
tg apply
```

### 2. Segurança e Mensageria (Independentes de VPC)
```bash
# 2.1. Cofre de Segredos (Secrets Manager)
cd prod/us-east-2/security/secrets-manager/app-secrets
tg apply

# 2.2. Fila SQS
cd prod/us-east-2/message/sqs/queue-01
tg apply

# 2.3. Identidade de E-mail no SES (envio transacional)
cd prod/us-east-2/message/ses
tg apply

# 2.4. Repositório Privado de Containers (AWS ECR)
cd prod/us-east-2/computing/ecr/app-repo
tg apply
```

### 3. Banco de Dados e Host Bastion Seguro
```bash
# EC2 Bastion privado com AWS SSM (sem IP público nem porta 22)
cd prod/us-east-2/computing/ec2/instance-01
tg apply

# Security Group do RDS
cd prod/us-east-2/networking/security-groups/rds-sg
tg apply

# Opção A: Banco de dados PostgreSQL RDS tradicional
cd prod/us-east-2/database/rds
tg apply

# Opção B: Banco de dados Amazon Aurora Serverless v2 (Cluster com auto-scaling)
cd prod/us-east-2/database/aurora-serverless-v2
tg apply
```

### 4. Stack ECS com EC2
```bash
# 4.1. Cluster ECS e CloudWatch Log Group
cd prod/us-east-2/computing/ec2/ecs/cluster
tg apply

# 4.2. Instância EC2 Nó do Cluster (registra no cluster via UserData)
cd prod/us-east-2/computing/ec2/ecs/ec2-node
tg apply

# 4.3. Task Definition e Service (Nginx na porta 8080)
cd prod/us-east-2/computing/ec2/ecs/service-app
tg apply
```

### 5. Stack ECS com Fargate (Serverless - Subnets Privadas)
```bash
# 5.1. Cluster Fargate com Capacity Providers (Fargate + Spot)
cd prod/us-east-2/computing/ecs-fargate/cluster
tg apply

# 5.2. Service Fargate privado integrado ao ALB e ao Secrets Manager
cd prod/us-east-2/computing/ecs-fargate/service-app
tg apply

# 5.3. Observabilidade e Alarme de CPU do Fargate
cd prod/us-east-2/observability/cloudwatch-alarms
tg apply
```

---

## 💣 Destroy (Destruir Infraestrutura)

Execute rigorosamente na **ordem inversa** — os recursos dependentes primeiro:

```bash
# 0. Observabilidade (Alarme de métrica do Fargate)
cd prod/us-east-2/observability/cloudwatch-alarms
tg destroy

# 1. Stack ECS Fargate (remove containers registrados no ALB)
cd prod/us-east-2/computing/ecs-fargate/service-app
tg destroy

cd prod/us-east-2/computing/ecs-fargate/cluster
tg destroy

# 2. Application Load Balancer Público
cd prod/us-east-2/networking/alb-public
tg destroy

# 3. Stack ECS com EC2
cd prod/us-east-2/computing/ec2/ecs/service-app
tg destroy

cd prod/us-east-2/computing/ec2/ecs/ec2-node
tg destroy

cd prod/us-east-2/computing/ec2/ecs/cluster
tg destroy

# 4. Banco de Dados (RDS ou Aurora) e Security Group
# Se usou RDS:
cd prod/us-east-2/database/rds
tg destroy

# Se usou Aurora Serverless v2:
cd prod/us-east-2/database/aurora-serverless-v2
tg destroy

cd prod/us-east-2/networking/security-groups/rds-sg
tg destroy

# 5. EC2 Bastion SSM
cd prod/us-east-2/computing/ec2/instance-01
tg destroy

# 6. Segurança e Mensageria (SES, SQS, Secrets Manager)
cd prod/us-east-2/message/ses
tg destroy

cd prod/us-east-2/message/sqs/queue-01
tg destroy

cd prod/us-east-2/security/secrets-manager/app-secrets
tg destroy

cd prod/us-east-2/computing/ecr/app-repo
tg destroy

# 7. VPC e NAT Gateway (base de tudo, destrói por último)
cd prod/us-east-2/networking/vpc/vpc-ospct
tg destroy
```

---

## 🔗 Testes de Conectividade e Validação

### 1. Validar a Aplicação Web via ALB (Entrada Controlada)
Faça a requisição na porta 80 pública do Application Load Balancer, que repassará para o container privado:
```bash
# Obter o DNS do ALB
cd prod/us-east-2/networking/alb-public
tg output dns_name

# Testar via curl (deve retornar HTTP 200 do Nginx)
curl http://<DNS_NAME_DO_ALB>
```

### 2. Conectar à EC2 Bastion via AWS SSM (Sem SSH e sem IP público)
```bash
# Obter o Instance ID da máquina
cd prod/us-east-2/computing/ec2/instance-01
tg output id

# Iniciar sessão segura criptografada
aws ssm start-session --target <INSTANCE_ID>
```

---

## 🔗 Testes de Conectividade e Validação

### 1. Validar o Container Nginx no ECS
Obtenha o IP público da instância do ECS e faça uma requisição HTTP na porta 8080:
```bash
# Obter o IP público
cd prod/us-east-2/computing/ec2/ecs/ec2-node
tg output public_ip

# Testar via curl
curl http://<IP_PUBLICO_EC2_NODE>:8080
```
> Ou abra no navegador: `http://<IP_PUBLICO_EC2_NODE>:8080`

### 2. Validar Conexão EC2 → RDS
Para testar se a EC2 alcança o PostgreSQL nas subnets privadas:
```bash
# De dentro da EC2 instance-01 (via SSH):
nc -zv meu-rds-db.<id>.us-east-2.rds.amazonaws.com 5432
```

### 3. Validar e Testar Envio com Amazon SES
Para verificar o status da identidade e disparar um e-mail de teste:
```bash
# 1. Consultar status de verificação (deve retornar "VerificationStatus": "Success")
aws ses get-identity-verification-attributes \
  --identities "seu-email@gmail.com" \
  --region us-east-2

# 2. Disparar e-mail de teste via CLI (dentro do sandbox: de você para você)
aws ses send-email \
  --from "seu-email@gmail.com" \
  --destination "ToAddresses=seu-email@gmail.com" \
  --message "Subject={Data='Teste SES',Charset=utf-8},Body={Text={Data='Mensagem de teste enviada pelo SES.',Charset=utf-8}}" \
  --region us-east-2
```

---

## ⚠️ Observações e Boas Práticas

- **Credenciais AWS**: renove a sessão antes de executar comandos (`aws login` ou `aws sso login`).
- **AMI Dinâmica do ECS**: O nó do ECS utiliza `ami_ssm_parameter` para puxar sempre a versão oficial mais recente da Amazon Linux 2023 ECS-Optimized sem depender de AMI IDs estáticos.
- **Portas e Non-Root**: O container utiliza `nginxinc/nginx-unprivileged:1.31-alpine` com `network_mode = bridge` na porta `8080:8080` para maior segurança.
- **Dimensionamento de Recursos (ECS)**: O container Nginx está fixado em `256` CPU units e `128 MB` de memória (`memoryReservation = 128`). Como o consumo real do Nginx raramente passa de 30-50 MB, 128 MB garante estabilidade sob alta carga e viabiliza *Rolling Updates* seguros dentro de uma única instância `t3.micro` (~950 MB livres) sem esgotar a RAM da máquina.
- **Custos**: O **NAT Gateway** é o recurso mais oneroso (~$32/mês). Lembre-se de destruí-lo com `tg destroy` na VPC quando o ambiente de estudos não estiver em uso.
- **State remoto (S3)**: Mantido no bucket S3 configurado no [root.hcl](root.hcl). O `tg destroy` remove apenas os recursos provisionados, preservando o histórico de estado.
