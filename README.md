# OSPCT Infrastructure - Sequência de Execução

## Arquitetura

```
networking/vpc/vpc-ospct          → VPC, Subnets, NAT Gateway
networking/security-groups/rds-sg → Security Group do RDS (porta 5432)
computing/ec2/instance-01        → EC2 Instance (public subnet)
database/rds                      → PostgreSQL RDS (private subnet)
```

## Diagrama de Dependências

```
         VPC
        /   \
      EC2   Subnets
       |       |
    RDS-SG ----┘
       |
      RDS
```

---

## 🚀 Apply (criar infraestrutura)

Executar na ordem de cima para baixo — os recursos base primeiro.

```bash
# 1. VPC (base de tudo)
cd prod/us-east-2/networking/vpc/vpc-ospct
tg apply

# 2. EC2 (depende da VPC)
cd prod/us-east-2/computing/ec2/instance-01
tg apply

# 3. Security Group do RDS (depende da VPC e EC2)
cd prod/us-east-2/networking/security-groups/rds-sg
tg apply

# 4. RDS (depende da VPC, EC2 e SG)
cd prod/us-east-2/database/rds
tg apply
```

---

## 💣 Destroy (destruir infraestrutura)

Executar na ordem inversa — os recursos dependentes primeiro.

```bash
# 1. RDS (depende de tudo)
cd prod/us-east-2/database/rds
tg destroy

# 2. Security Group do RDS
cd prod/us-east-2/networking/security-groups/rds-sg
tg destroy

# 3. EC2
cd prod/us-east-2/computing/ec2/instance-01
tg destroy

# 4. VPC (base de tudo, destrói por último)
cd prod/us-east-2/networking/vpc/vpc-ospct
tg destroy
```

---

## ⚠️ Observações

- **Credenciais AWS**: certifique-se de que o token está válido antes de executar (`aws sso login` ou export das credenciais).
- **NAT Gateway**: é o recurso mais caro (~$32/mês). Se quiser economizar sem destruir tudo, destrua a VPC ou desabilite o NAT.
- **State remoto (S3)**: não é destruído pelo `tg destroy`. Continua existindo com custo de centavos.
- **Após o destroy**: confira no console AWS que não restaram recursos órfãos (snapshots, EIPs, volumes EBS).

## 🔗 Teste de Conectividade

Para validar que a EC2 alcança o RDS após o apply:

```bash
# De dentro da EC2 (via SSH)
nc -zv meu-rds-db.<id>.us-east-2.rds.amazonaws.com 5432
```
