#!/usr/bin/env bash
# Deploys the infrastructure for the container track
# (Container Apps environment + container app). Run from the repo root.
# Requires the registry to exist and the image to be pushed.
# Usage: ./scripts/deploy-container.sh [--what-if] <resource-group> [params]

set -euo pipefail

WHAT_IF=false
if [ "${1:-}" = "--what-if" ]; then
  WHAT_IF=true
  shift
fi

RESOURCE_GROUP="${1:?Provide the resource group as the first argument}"
PARAM_FILE="${2:-infra/container.bicepparam}"
LOCATION="${LOCATION:-swedencentral}"
TEMPLATE="infra/container.bicep"

echo "Template:       $TEMPLATE"
echo "Parameters:     $PARAM_FILE"
echo "Resource group: $RESOURCE_GROUP"

if [ "$(az group exists --name "$RESOURCE_GROUP")" = "false" ]; then
  echo "Group:          missing, creating it in $LOCATION"
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
else
  echo "Group:          already exists"
fi

if [ "$WHAT_IF" = true ]; then
  echo "Mode:           preview (no resources change)"
  az deployment group what-if \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE" \
    --parameters "$PARAM_FILE"
  exit 0
fi

DEPLOYMENT_NAME="container-$(date +%Y%m%d-%H%M%S)"
echo "Mode:           deploy ($DEPLOYMENT_NAME)"

APP_URL=$(az deployment group create \
  --name "$DEPLOYMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$TEMPLATE" \
  --parameters "$PARAM_FILE" \
  --query properties.outputs.appUrl.value \
  --output tsv)

echo "Done. App URL: $APP_URL"
