#!/usr/bin/env bash
#
# Atualiza a tag da imagem no arquivo kustomization.yaml do serviço
# Chamado pela pipeline de CI após fazer push da imagem para o ECR
#
# Uso: ./gitops/update-image-tag.sh <service-name> <new-image-tag>
#
# Exemplo:
#   ./gitops/update-image-tag.sh auth-service v1.0.3-a1b2c3d
#
set -euo pipefail

SERVICE_NAME="${1:-}"
IMAGE_TAG="${2:-}"

if [ -z "$SERVICE_NAME" ] || [ -z "$IMAGE_TAG" ]; then
  echo "❌ Uso: $0 <service-name> <image-tag>"
  echo "Exemplo: $0 auth-service v1.0.3-a1b2c3d"
  exit 1
fi

KUSTOMIZATION_FILE="gitops/apps/${SERVICE_NAME}/kustomization.yaml"

if [ ! -f "$KUSTOMIZATION_FILE" ]; then
  echo "❌ Arquivo não encontrado: $KUSTOMIZATION_FILE"
  exit 1
fi

echo "📝 Atualizando imagem no arquivo: $KUSTOMIZATION_FILE"
echo "   Serviço: $SERVICE_NAME"
echo "   Nova tag: $IMAGE_TAG"

# Usa sed para atualizar a tag da imagem
# Procura pela linha 'newTag: <qualquer-valor>' e substitui por 'newTag: <nova-tag>'
sed -i.bak "s|^\( *newTag: \).*$|\1${IMAGE_TAG}|" "$KUSTOMIZATION_FILE"

# Verifica se a atualização foi bem-sucedida
if grep -q "newTag: ${IMAGE_TAG}" "$KUSTOMIZATION_FILE"; then
  echo "✅ Imagem atualizada com sucesso"

  # Remove o arquivo de backup
  rm -f "${KUSTOMIZATION_FILE}.bak"

  # Mostra a mudança
  echo
  echo "📋 Novo conteúdo da seção 'images':"
  grep -A 3 "^images:" "$KUSTOMIZATION_FILE"
else
  echo "❌ Falha ao atualizar a imagem"
  # Restaura o backup
  mv "${KUSTOMIZATION_FILE}.bak" "$KUSTOMIZATION_FILE"
  exit 1
fi

echo
echo "✅ Pronto para commit: $KUSTOMIZATION_FILE"
