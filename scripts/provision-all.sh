#!/usr/bin/env bash
# Builds the whole environment back up from nothing, in the order that works.
#
# Usage: ./scripts/provision-all.sh <resource-group> <acr-name> [image-tag]
#   image-tag  defaults to v1

set -euo pipefail

RESOURCE_GROUP="${1:?Provide the resource group as the first argument}"
ACR_NAME="${2:?Provide your ACR name as the second argument}"
IMAGE_TAG="${3:-v1}"

echo "== 1/4 App Service track: group, plan, web app =="
./scripts/deploy-infra.sh "$RESOURCE_GROUP"

echo "== 2/4 Registry: it has to exist before an image can be pushed =="
az acr create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ACR_NAME" \
  --sku Basic \
  --admin-enabled true \
  --output none

echo "== 3/4 Image: the registry was torn down, so the image went with it =="
az acr build \
  --registry "$ACR_NAME" \
  --image "beacon:$IMAGE_TAG" \
  --file src/Beacon.Api/Dockerfile \
  .

echo "== 4/4 Container track: registry, environment and container app =="
./scripts/deploy-container.sh "$RESOURCE_GROUP"

echo
echo "Both tracks are up."
