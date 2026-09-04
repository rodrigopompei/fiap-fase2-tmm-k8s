# Pipelines CI/CD — ToggleMaster

Um workflow por microserviço, em [`workflows/`](workflows/):

| Workflow | Serviço | Stack | Repositório ECR | Versão |
| --- | --- | --- | --- | --- |
| [`auth-service.yml`](workflows/auth-service.yml) | auth-service | Go 1.21 | `fiap-fase2/auth-service` | 1.0.3 |
| [`evaluation-service.yml`](workflows/evaluation-service.yml) | evaluation-service | Go 1.21 | `fiap-fase2/evaluation-service` | 1.0.0 |
| [`flag-service.yml`](workflows/flag-service.yml) | flag-service | Python 3.12 | `fiap-fase2/flag-service` | 1.0.1 |
| [`targeting-service.yml`](workflows/targeting-service.yml) | targeting-service | Python 3.12 | `fiap-fase2/targeting-service` | 1.0.2 |
| [`analytics-service.yml`](workflows/analytics-service.yml) | analytics-service | Python 3.12 | `fiap-fase2/analytics-service` | 1.0.1 |

## Quando roda

Em **Pull Request para `main`** e em **push na `main`**, filtrado pelo diretório do
serviço — mexer só em `flag-service/` não dispara os outros quatro pipelines.
Também dá para disparar manualmente pela aba *Actions* (`workflow_dispatch`).

## Os quatro estágios

```
┌─ 1. build-test ────┐
├─ 2. lint ──────────┼──▶ 4. docker  (build → container scan → push ECR)
└─ 3. security-scan ─┘
```

Os três primeiros rodam em paralelo; o `docker` só começa se todos passarem.

| Estágio | Go | Python |
| --- | --- | --- |
| 1. Build & Unit Test | `go build`, `go vet`, `go test -race -cover` | `pip install`, `compileall`, `pytest` (se houver suíte) |
| 2. Linter | `golangci-lint` (bloqueante) + `gofmt` (informativo) | `flake8` (bloqueante) + `pylint` (informativo) |
| 3. SCA | Trivy `fs` sobre `go.mod`/`go.sum` | Trivy `fs` sobre `requirements.txt` |
| 3. SAST | `gosec` | `bandit` |
| 4. Container Scan | Trivy `image` | Trivy `image` |

Rulesets compartilhados: [`.golangci.yml`](../.golangci.yml) e [`.flake8`](../.flake8).

### Regra de bloqueio

- **SCA e Container Scan** reprovam em qualquer CVE **CRITICAL que já tenha
  correção publicada** (`ignore-unfixed: true`). CVE sem patch upstream não
  bloqueia — nenhum rebuild resolveria, e um gate impossível de passar não
  protege nada. Esses achados continuam visíveis no relatório informativo.
- **SAST** reprova em achados **HIGH** com confiança ≥ MEDIUM.
- Reprovar no estágio 3 impede o estágio 4: a imagem nunca chega ao ECR.

Cada job publica o relatório completo no *Job Summary* e como artefato
(retenção de 14 dias), inclusive quando o gate falha.

## Tag da imagem

`v<SERVICE_VERSION>-<sha7>` — por exemplo `v1.0.3-a1b2c3d`. O `SERVICE_VERSION`
fica no bloco `env:` de cada workflow e é bumpado à mão a cada release. Em Pull
Request usa-se o SHA real do último commit do PR, não o merge commit sintético.

Além da tag imutável, o push na `main` também move a tag `latest`.

## Push no ECR

Só acontece em **push na `main`**. Em Pull Request a imagem é construída e
escaneada, mas nunca publicada.

### Secrets necessários

O AWS Academy Learner Lab bloqueia `iam:CreateOpenIDConnectProvider`, então não
há OIDC — o pipeline usa credenciais temporárias do lab:

| Secret | Onde obter |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | *AWS Details → AWS CLI* no Learner Lab |
| `AWS_SECRET_ACCESS_KEY` | idem |
| `AWS_SESSION_TOKEN` | idem |

> ⚠️ Essas credenciais expiram junto com a sessão do laboratório. **Reconfigure
> os três secrets toda vez que reiniciar o lab**, senão o estágio 4 falha no
> login do ECR.

Os repositórios ECR são criados pelo Terraform (`terraform/modules/ecr`). Se o
repositório não existir, o pipeline falha com uma mensagem apontando para o
`terraform apply` em vez de criar recurso fora do state.

## Estado conhecido dos gates

Verificado localmente com as mesmas ferramentas e versões dos workflows:

| Serviço | 1. Build | 2. Lint | 3. SCA | 3. SAST | 4. Container |
| --- | --- | --- | --- | --- | --- |
| flag-service | ✅ | ✅ | ✅ | ✅ | ✅ |
| targeting-service | ✅ | ✅ | ✅ | ✅ | ✅ |
| analytics-service | ✅ | ✅ | ✅ | ✅ | ✅ |
| auth-service | ✅ | ✅ | ❌ | ✅ | ❌ |
| evaluation-service | ✅ | ✅ | ✅ | ✅ | ❌ |

Os dois serviços Go reprovam por CVE CRITICAL que vêm todas do **Go 1.21 estar
em EOL**:

| CVE | Onde | Correção |
| --- | --- | --- |
| `CVE-2025-68121` | `stdlib` v1.21.13 — validação incorreta de certificado em `crypto/tls` na retomada de sessão. Atinge o binário compilado dos dois serviços. | Go ≥ 1.24.13 / 1.25.7 |
| `CVE-2026-56854` | `golang.org/x/crypto` v0.20.0 — bypass de autenticação em `x/crypto/ssh`. Só no auth-service (dependência indireta do pgx; o pacote `ssh` não é importado pela aplicação). | `x/crypto` ≥ 0.55.0, que por sua vez exige Go ≥ 1.25 |

Isso é o gate funcionando como especificado, não um defeito do pipeline. Para
resolver, um único bump encadeado cobre os dois casos:

```bash
# go.mod dos dois serviços: go 1.21 -> go 1.25
# Dockerfile dos dois serviços: golang:1.21-alpine -> golang:1.25-alpine
# GO_VERSION nos dois workflows: '1.21' -> '1.25'
cd auth-service && go get golang.org/x/crypto@v0.55.0 && go mod tidy
```

## Exceções de scanner triadas

Nenhuma exceção silenciosa: cada uma está comentada no ponto de uso.

- **`gosec G704` (SSRF via taint analysis) — evaluation-service.** Em
  `fetchFlag()`/`fetchRule()` o host de destino vem de variável de ambiente
  confiável; só o segmento de path deriva do query param `flag_name`. A análise
  de taint do gosec não reconhece sanitizador nesse caminho — verificado que nem
  `url.PathEscape` zera o achado —, então não há correção possível em código.
  Excluído apenas do gate; segue no relatório e no SARIF.
  *TODO:* validar `flag_name` contra allowlist (`^[a-zA-Z0-9_-]{1,64}$`) na
  entrada do handler e reavaliar.
- **`gosec G401`/`G505` (crypto/sha1) — evaluation-service.** São MEDIUM, logo
  já não alcançam o gate de HIGH. O SHA-1 em `getDeterministicBucket()` serve
  para distribuir usuários em buckets de rollout percentual, não para segurança.
- **`misspell` desabilitado no golangci-lint.** Dicionário só de inglês; acusa
  falso positivo em todo comentário em português (`Eles` → `Eels`).
- **flake8 tolera divergências cosméticas de PEP 8** (`W291`, `W293`, `E302`,
  `E701`, …). Continuam bloqueantes os erros reais: pyflakes `F###`, sintaxe
  `E9##` e complexidade `C901` acima de 15.

## Rodar os checks localmente

```bash
# Go
cd auth-service && golangci-lint run --config=../.golangci.yml ./...
gosec -severity=high -confidence=medium ./...

# Python
flake8 flag-service
bandit -r flag-service --severity-level high --confidence-level medium

# Scanners (mesmos gates do CI)
trivy fs --scanners vuln --severity CRITICAL --ignore-unfixed --exit-code 1 flag-service
trivy image --scanners vuln --severity CRITICAL --ignore-unfixed --exit-code 1 flag-service:local

# Validar os próprios workflows
docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:latest
```
