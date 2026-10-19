# OSPCT Infrastructure - Sequência de Execução & Arquitetura

Repositório de infraestrutura AWS orquestrado com **Terragrunt** e **Terraform**.

---

## 🏗️ Arquitetura e Módulos

```
prod/us-east-2/
├── networking/
│   ├── vpc/vpc-ospct                 → VPC, Subnets (públicas e privadas), NAT Gateway
│   └── security-groups/rds-sg        → Security Group do RDS (libera porta 5432 para EC2)
├── computing/
│   ├── ec2/instance-01               → EC2 Standalone / Bastion (public subnet)
│   ├── ec2/ecs/                      → ECS clássico com instâncias EC2 gerenciadas (cluster, ec2-node, service-app)
│   └── ecs-fargate/
│       ├── cluster/                  → ECS Cluster Serverless (ospct-fargate-cluster + Spot)
│       └── service-app/              → Task Definition + Service Fargate (awsvpc na porta 8080)
├── security/
│   └── secrets-manager/app-secrets   → Cofre de credenciais da aplicação (API keys, JWT)
├── database/
│   └── rds/                          → PostgreSQL RDS com master password gerenciada no Secrets Manager
└── message/
    └── sqs/queue-01/                 → Fila SQS padrão (módulo local)
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
      │(instance-01) │   └─────┬──────┘            └──────┬───────┘
      └──────┬───────┘         │                          │
             └────────┬────────┘                          ▼
                      ▼                            ┌──────────────┐
               ┌─────────────┐                     │ ECS EC2-Node │
               │   RDS DB    │                     └──────┬───────┘
               └─────────────┘                            │
                                                          ▼
                                                   ┌──────────────┐
                                                   │ ECS Service  │
                                                   │ (Nginx 8080) │
                                                   └──────────────┘
```

---

## 🚀 Apply (Criar Infraestrutura)

Execute na ordem de dependência — os componentes base primeiro:

### 1. Rede Base
```bash
# VPC, Subnets públicas/privadas e NAT Gateway
cd prod/us-east-2/networking/vpc/vpc-ospct
tg apply
```

### 2. Mensageria (Opcional / Independente)
```bash
# Fila SQS
cd prod/us-east-2/message/sqs/queue-01
tg apply
```

### 3. Banco de Dados e Instância Bastion
```bash
# EC2 Standalone de acesso/bastion
cd prod/us-east-2/computing/ec2/instance-01
tg apply

# Security Group do RDS
cd prod/us-east-2/networking/security-groups/rds-sg
tg apply

# Banco de dados PostgreSQL RDS
cd prod/us-east-2/database/rds
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

### 5. Stack ECS com Fargate (Serverless - Sem EC2)
```bash
# 5.1. Cluster Fargate com Capacity Providers (Fargate + Spot)
cd prod/us-east-2/computing/ecs-fargate/cluster
tg apply

# 5.2. Task Definition e Service Fargate direto na VPC (awsvpc na porta 8080)
cd prod/us-east-2/computing/ecs-fargate/service-app
tg apply
```

---

## 💣 Destroy (Destruir Infraestrutura)

Execute rigorosamente na **ordem inversa** — os recursos dependentes primeiro:

```bash
# 1. ECS Service (para os containers e desaloca as portas)
cd prod/us-east-2/computing/ec2/ecs/service-app
tg destroy

# 2. ECS EC2-Node (remove a VM do cluster)
cd prod/us-east-2/computing/ec2/ecs/ec2-node
tg destroy

# 3. ECS Cluster
cd prod/us-east-2/computing/ec2/ecs/cluster
tg destroy

# 4. RDS (destrói o banco de dados)
cd prod/us-east-2/database/rds
tg destroy

# 5. Security Group do RDS
cd prod/us-east-2/networking/security-groups/rds-sg
tg destroy

# 6. EC2 Standalone
cd prod/us-east-2/computing/ec2/instance-01
tg destroy

# 7. SQS
cd prod/us-east-2/message/sqs/queue-01
tg destroy

# 8. VPC e NAT Gateway (base de tudo, destrói por último)
cd prod/us-east-2/networking/vpc/vpc-ospct
tg destroy
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

---

## ⚠️ Observações e Boas Práticas

- **Credenciais AWS**: renove a sessão antes de executar comandos (`aws login` ou `aws sso login`).
- **AMI Dinâmica do ECS**: O nó do ECS utiliza `ami_ssm_parameter` para puxar sempre a versão oficial mais recente da Amazon Linux 2023 ECS-Optimized sem depender de AMI IDs estáticos.
- **Portas e Non-Root**: O container utiliza `nginxinc/nginx-unprivileged:1.31-alpine` com `network_mode = bridge` na porta `8080:8080` para maior segurança.
- **Dimensionamento de Recursos (ECS)**: O container Nginx está fixado em `256` CPU units e `128 MB` de memória (`memoryReservation = 128`). Como o consumo real do Nginx raramente passa de 30-50 MB, 128 MB garante estabilidade sob alta carga e viabiliza *Rolling Updates* seguros dentro de uma única instância `t3.micro` (~950 MB livres) sem esgotar a RAM da máquina.
- **Custos**: O **NAT Gateway** é o recurso mais oneroso (~$32/mês). Lembre-se de destruí-lo com `tg destroy` na VPC quando o ambiente de estudos não estiver em uso.
- **State remoto (S3)**: Mantido no bucket S3 configurado no [root.hcl](root.hcl). O `tg destroy` remove apenas os recursos provisionados, preservando o histórico de estado.
