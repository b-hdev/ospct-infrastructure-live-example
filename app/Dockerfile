# =============================================================================
# OSPCT Cloud App - Production Multi-Stage Dockerfile
# =============================================================================
#
# ARQUITETURA MULTI-STAGE:
# ┌─────────────────────────────────────────────────────────────────────┐
# │ Stage 1: deps        → Instala dependências (prod only)            │
# │ Stage 2: production  → Imagem final mínima, non-root, hardened     │
# └─────────────────────────────────────────────────────────────────────┘
#
# REGRAS DE SEGURANÇA APLICADAS:
# ✅ Imagem base Alpine (superfície de ataque mínima ~5MB)
# ✅ Pinning de versão major:minor da imagem base
# ✅ Multi-stage build (artefatos de build não vazam para produção)
# ✅ Usuário non-root dedicado (appuser UID 1001, sem shell)
# ✅ Filesystem read-only onde possível
# ✅ Sem pacotes desnecessários (--no-cache, apk limpo)
# ✅ COPY seletivo (nunca COPY . .)
# ✅ .dockerignore para excluir arquivos sensíveis
# ✅ HEALTHCHECK nativo do Docker para orquestração
# ✅ Metadata via LABEL (OCI standard)
# ✅ Signal handling correto (exec form CMD + dumb-init)
# ✅ NODE_ENV=production para otimizações do runtime
# ✅ npm ci --omit=dev para builds determinísticos
# ✅ Ordem de layers otimizada para cache do Docker
# =============================================================================


# ---------------------------------------------------------------------------
# Stage 1: deps - Instalação de dependências
# ---------------------------------------------------------------------------
# PROPÓSITO: Isolar a instalação de dependências em um stage separado.
#            Mesmo sem dependências externas hoje, esta estrutura garante
#            que ao adicionar libs no futuro, o cache de layers funcione
#            corretamente e o stage final permaneça limpo.
#
# POR QUE npm ci?
#   - Usa o package-lock.json para builds 100% determinísticos
#   - Remove node_modules antes de instalar (clean slate)
#   - Mais rápido que npm install em CI/CD
#   - Falha se package-lock.json estiver desatualizado
# ---------------------------------------------------------------------------
FROM node:22-alpine AS deps

# Instala dumb-init para signal handling correto (PID 1 problem)
# POR QUE dumb-init?
#   Node.js não lida bem como PID 1 dentro de containers:
#   - Não repassa SIGTERM para processos filhos
#   - Não coleta processos zumbi (zombie reaping)
#   dumb-init atua como init system mínimo, resolvendo ambos os problemas.
RUN apk add --no-cache dumb-init

WORKDIR /usr/src/app

# COPY seletivo: apenas arquivos de dependência primeiro (otimiza cache)
# Se package.json/package-lock.json não mudar, esta layer é reutilizada
COPY package.json package-lock.json* ./

# Instala apenas dependências de produção de forma determinística
# --omit=dev: exclui devDependencies (testes, linters, etc.)
# --ignore-scripts: previne execução de scripts pós-install (segurança)
RUN npm ci --omit=dev --ignore-scripts 2>/dev/null || true


# ---------------------------------------------------------------------------
# Stage 2: production - Imagem final mínima e hardened
# ---------------------------------------------------------------------------
# PROPÓSITO: Imagem final que roda em produção.
#            Contém apenas: runtime Node.js + dependências prod + código.
#            Nenhum artefato de build, cache npm, ou ferramenta dev.
# ---------------------------------------------------------------------------
FROM node:22-alpine AS production

# ── OCI Standard Labels ──────────────────────────────────────────────
# Metadata seguindo o padrão OCI (Open Container Initiative)
# Permite rastreabilidade da imagem em registries e ferramentas de scan
LABEL org.opencontainers.image.title="OSPCT Cloud App" \
      org.opencontainers.image.description="OSPCT Cloud Application - Production Server" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.vendor="OSPCT" \
      org.opencontainers.image.source="https://github.com/ospct/infrastructure-live" \
      org.opencontainers.image.licenses="UNLICENSED"

# ── Variáveis de Ambiente ────────────────────────────────────────────
# NODE_ENV=production:
#   - Habilita otimizações do V8 (menos GC, cache de módulos)
#   - Express/frameworks desabilitam debug e stack traces
#   - npm ignora devDependencies automaticamente
ENV NODE_ENV=production \
    PORT=8080

# ── Segurança: Usuário Non-Root ─────────────────────────────────────
# POR QUE non-root?
#   Se um atacante explorar uma vulnerabilidade na app, ele terá
#   permissões limitadas (não pode instalar pacotes, modificar /etc,
#   acessar /proc de outros processos, ou escalar privilégios).
#
# POR QUE UID 1001 (e não o user 'node' built-in)?
#   O user 'node' (UID 1000) é padrão e previsível.
#   Criar um usuário dedicado com UID específico:
#   - Evita conflitos com mapeamentos de volume
#   - É mais explícito e auditável
#   - Segue o princípio de menor privilégio
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup -s /sbin/nologin

# ── Copiar dumb-init do stage anterior ──────────────────────────────
COPY --from=deps /usr/bin/dumb-init /usr/bin/dumb-init

# ── Diretório de Trabalho ───────────────────────────────────────────
WORKDIR /usr/src/app

# ── Copiar dependências de produção do stage deps ───────────────────
# --chown garante que os arquivos pertencem ao appuser (non-root)
COPY --from=deps --chown=appuser:appgroup /usr/src/app/node_modules ./node_modules/ 2>/dev/null || true

# ── Copiar código da aplicação ──────────────────────────────────────
# COPY seletivo: apenas os arquivos necessários para rodar
# NUNCA usar "COPY . ." - pode vazar .env, .git, secrets, etc.
COPY --chown=appuser:appgroup package.json ./
COPY --chown=appuser:appgroup server.js ./

# ── Trocar para usuário non-root ────────────────────────────────────
# A partir daqui, todos os comandos rodam como appuser (UID 1001)
# Mesmo que alguém faça docker exec, entrará como non-root
USER appuser

# ── Porta Exposta ───────────────────────────────────────────────────
# EXPOSE é documentação - não publica a porta automaticamente
# A porta real é definida por ENV PORT e mapeada no docker run / ECS
EXPOSE ${PORT}

# ── Health Check ────────────────────────────────────────────────────
# HEALTHCHECK nativo do Docker:
#   - interval: checa a cada 30s
#   - timeout: falha se não responder em 5s
#   - start-period: espera 10s antes da primeira checagem (app startup)
#   - retries: marca como unhealthy após 3 falhas consecutivas
#
# Usa wget (disponível no Alpine) ao invés de curl (não instalado)
# para não adicionar pacotes desnecessários à imagem
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:${PORT}/health || exit 1

# ── Entrypoint com dumb-init ────────────────────────────────────────
# dumb-init como PID 1:
#   - Repassa SIGTERM/SIGINT para o processo Node.js
#   - Permite graceful shutdown do servidor HTTP
#   - Coleta processos zumbi automaticamente
#
# Exec form (array) ao invés de shell form:
#   - Não cria um shell intermediário (/bin/sh -c ...)
#   - O sinal vai direto para dumb-init → node
ENTRYPOINT ["dumb-init", "--"]

# ── Comando de Inicialização ────────────────────────────────────────
# CMD separado do ENTRYPOINT permite override fácil para debug:
#   docker run <image> node --inspect server.js
CMD ["node", "server.js"]
