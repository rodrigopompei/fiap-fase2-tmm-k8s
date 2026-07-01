# ─────────────────────────────────────────────────────────────────────────────
# Stage 1 - Builder
# Estratégia multi-stage: este estágio compila o binário Go em um ambiente
# completo. O Stage 2 copia apenas o binário final, resultando em uma imagem
# de produção mínima (~10 MB) sem compilador, código-fonte ou cache de módulos.
# ─────────────────────────────────────────────────────────────────────────────

# Usa a imagem oficial Go 1.21 baseada em Alpine (Linux mínimo ~5 MB).
# O alias "builder" permite que o Stage 2 referencie este estágio via --from=builder.
FROM golang:1.21-alpine AS builder

# Instala o git via gerenciador de pacotes Alpine.
# --no-cache : não salva o índice de pacotes na imagem (economiza espaço).
# O git é necessário para que o "go mod download" busque módulos
# hospedados diretamente em repositórios Git (GitHub, etc.).
RUN apk add --no-cache git

# Configura flags globais do comando "go".
# -mod=mod : permite que o Go atualize/crie o arquivo go.sum automaticamente
#            durante o build, evitando falhas quando go.sum está desatualizado.
ENV GOFLAGS=-mod=mod

# Define /app como diretório de trabalho dentro do container.
# Todos os comandos COPY e RUN seguintes serão executados a partir deste caminho.
WORKDIR /app

# Copia APENAS o arquivo de manifesto de dependências antes do código-fonte.
# Técnica de cache de camadas: se go.mod não mudar entre builds,
# o Docker reutiliza a camada de download de módulos, acelerando o build.
COPY go.mod ./

# Baixa todas as dependências declaradas em go.mod para o cache local do Go.
# Executado antes de copiar o código para maximizar o reuso do cache.
RUN go mod download

# Copia todos os arquivos .go (código-fonte da aplicação).
# Feito após o download para que mudanças no código não invalidem o cache de módulos.
COPY *.go ./

# Compila o binário estático para Linux.
# CGO_ENABLED=0       : desabilita o CGo, gerando um binário puramente estático
#                       (sem dependência de libc). Obrigatório para rodar em Alpine
#                       ou imagens scratch sem glibc instalado.
# GOOS=linux          : compila para Linux independente do SO da máquina host.
# -ldflags="-s -w"    : -s remove a tabela de símbolos; -w remove informações de
#                       debug do DWARF. Reduz o tamanho do binário significativamente.
# -trimpath           : remove caminhos absolutos do host do binário compilado
#                       (melhora segurança e garante builds reproduzíveis).
# -o evaluation-service: nome do arquivo de saída gerado.
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-s -w" \
    -trimpath \
    -o evaluation-service .


# ─────────────────────────────────────────────────────────────────────────────
# Stage 2 - Runtime
# Nova imagem do zero. Apenas o binário compilado é trazido do Stage 1.
# Resultado: imagem final sem compilador Go, sem código-fonte, sem módulos.
# ─────────────────────────────────────────────────────────────────────────────

# Alpine 3.19 como base de runtime (~5 MB). Muito menor que a imagem golang (~300 MB).
FROM alpine:3.19

# Instala dois pacotes essenciais para aplicações de produção:
# ca-certificates : certificados TLS raiz, necessários para conexões HTTPS/TLS
#                   (ex: chamadas ao AWS SQS, Redis com TLS, serviços internos).
# tzdata          : banco de dados de fusos horários; permite configurar a
#                   variável TZ no container sem precisar recompilar a aplicação.
RUN apk add --no-cache ca-certificates tzdata

# Cria um grupo e um usuário de sistema sem privilégios.
# -S (system)     : cria sem diretório home e sem shell de login.
# appuser pertence ao appgroup (boa prática: isolar permissões por grupo).
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Troca para o usuário sem privilégios (princípio do menor privilégio).
# Todos os processos a partir daqui rodam como appuser, nunca como root.
USER appuser

# Define /app como diretório de trabalho do container de runtime.
WORKDIR /app

# Copia APENAS o binário compilado do Stage 1 para a imagem final.
# Nada mais do ambiente de build (compilador, código, módulos) é incluído.
COPY --from=builder /app/evaluation-service .

# Documenta que o container escuta na porta 8004.
# Não faz binding efetivo — o mapeamento real é feito no docker-compose ou "docker run -p".
EXPOSE 8004

# Verifica periodicamente se a aplicação está saudável.
# --interval=30s    : executa a checagem a cada 30 segundos.
# --timeout=5s      : a checagem deve responder em até 5s (Go responde rápido).
# --start-period=10s: aguarda 10s após o start antes de iniciar as checagens
#                     (tempo para o serviço conectar ao Redis, SQS e outros deps).
# --retries=3       : após 3 falhas consecutivas o container é marcado "unhealthy".
# wget está disponível no Alpine por padrão; -qO- suprime output e lê o corpo.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:8004/health || exit 1

# ENTRYPOINT (diferente de CMD): o binário é sempre executado e não pode ser
# substituído por argumentos passados no "docker run". Garante que o container
# sempre inicie o evaluation-service, independente de como for invocado.
ENTRYPOINT ["./evaluation-service"]
