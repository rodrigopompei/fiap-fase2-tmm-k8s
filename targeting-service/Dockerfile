# ─────────────────────────────────────────────────────────────────────────────
# Stage 1 - Build da Aplicação
# Estratégia multi-stage: este estágio instala dependências em um ambiente
# completo. O estágio final copia apenas o necessário, mantendo a imagem
# de produção enxuta e sem ferramentas de build.
# ─────────────────────────────────────────────────────────────────────────────

# Usa a imagem oficial Python 3.12 "slim" (Debian mínimo, sem extras desnecessários).
# O alias "builder" permite que o Stage 2 referencie este estágio via --from=builder.
FROM python:3.12-slim AS builder

# Define /app como diretório de trabalho dentro do container.
# Todos os comandos COPY e RUN seguintes serão executados a partir deste caminho.
WORKDIR /app

# Copia APENAS o arquivo de dependências antes do código-fonte.
# Técnica de cache de camadas: se requirements.txt não mudar entre builds,
# o Docker reutiliza a camada de instalação do pip, acelerando o build.
COPY requirements.txt .

# Instala as dependências Python listadas em requirements.txt.
# --no-cache-dir : não salva o cache de download do pip na imagem (reduz tamanho).
# --user         : instala em /root/.local em vez do sistema global,
#                  facilitando a cópia isolada para o Stage 2 sem precisar de root.
RUN pip install --no-cache-dir --user -r requirements.txt


# ─────────────────────────────────────────────────────────────────────────────
# Stage 2 - Criar a imagem final
# Nova imagem limpa, sem compilador nem cache de build.
# Apenas o runtime Python e os pacotes instalados no Stage 1 são incluídos.
# ─────────────────────────────────────────────────────────────────────────────

# Inicia uma nova imagem do zero (descarta tudo do Stage 1 exceto o que for copiado).
FROM python:3.12-slim

# Cria o usuário "appuser" sem senha e sem informações de perfil (gecos '').
# --disabled-password : impede login por senha (boa prática de segurança).
# A aplicação rodará como este usuário, nunca como root.
RUN adduser --disabled-password --gecos '' appuser

# Define /app como diretório de trabalho (mesma convenção do Stage 1).
WORKDIR /app

# Copia os pacotes instalados pelo pip do Stage 1 para o diretório do appuser.
# Origem  → /root/.local no builder (onde --user instalou os pacotes)
# Destino → /home/appuser/.local (home do usuário não-root desta imagem)
COPY --from=builder /root/.local /home/appuser/.local

# Copia todo o código-fonte do projeto para /app dentro do container.
COPY . .

# Garante que appuser é dono de todos os arquivos da aplicação e das libs.
# Necessário porque os COPYs anteriores foram executados como root.
RUN chown -R appuser:appuser /app /home/appuser/.local

# Troca para o usuário sem privilégios (princípio do menor privilégio).
# Todos os processos a partir daqui rodam como appuser, não como root.
USER appuser

# Adiciona o diretório de binários do pip local (~/.local/bin) ao PATH.
# Sem isso, o executável "gunicorn" (instalado via --user) não seria encontrado.
ENV PATH="/home/appuser/.local/bin:$PATH"

# Documenta que o container escuta na porta 8003.
# Não faz binding efetivo — o mapeamento real é feito no docker-compose ou "docker run -p".
EXPOSE 8003

# Verifica periodicamente se a aplicação está saudável.
# --interval=30s   : executa a checagem a cada 30 segundos.
# --timeout=30s    : a checagem deve responder em até 30 segundos.
# --start-period=5s: aguarda 5s após o start antes de iniciar as checagens (tempo de startup).
# --retries=3      : após 3 falhas consecutivas o container é marcado como "unhealthy".
# Usa urllib da stdlib Python (sem dependência de curl/wget na imagem).
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8003/health').read()" || exit 1

# Inicia a aplicação Flask via Gunicorn (servidor WSGI recomendado para produção).
# --bind 0.0.0.0:8003 : aceita conexões de qualquer interface de rede na porta 8003.
# app:app             : carrega o módulo "app.py" e usa o objeto Flask chamado "app".
CMD ["gunicorn", "--bind", "0.0.0.0:8003", "app:app"]