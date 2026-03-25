#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Foundry OpenAI Monitor — One-click deployment
#
# Deploys the full monitoring stack to any subscription/tenant:
#   1. Log Analytics Workspace  (Bicep)
#   2. Azure Monitor Workbook   (Bicep)
#   3. Diagnostic settings on all OpenAI resources (az CLI)
#
# Usage:
#   # Interactive — prompts for missing values
#   ./deploy.sh
#
#   # Non-interactive — pass via env vars
#   SUBSCRIPTION_ID=xxx RESOURCE_GROUP=my-rg LOCATION=eastus2 ./deploy.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- Configuration (override via env vars) ----------
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
LOCATION="${LOCATION:-}"
WORKSPACE_NAME="${WORKSPACE_NAME:-law-foundry-monitor}"
WORKBOOK_NAME="${WORKBOOK_NAME:-Foundry OpenAI Monitor}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
DIAG_SETTING_NAME="${DIAG_SETTING_NAME:-foundry-diagnostic-all-logs}"

# ---------- Prompt for missing values ----------
if [ -z "$SUBSCRIPTION_ID" ]; then
  echo -n "Subscription ID: "
  read -r SUBSCRIPTION_ID
fi

az account set --subscription "$SUBSCRIPTION_ID"
echo "✅ Subscription set: $SUBSCRIPTION_ID"

if [ -z "$RESOURCE_GROUP" ]; then
  echo -n "Resource Group (will be created if missing): "
  read -r RESOURCE_GROUP
fi

if [ -z "$LOCATION" ]; then
  # Try to get from existing RG, otherwise prompt
  LOCATION=$(az group show --name "$RESOURCE_GROUP" --query location -o tsv 2>/dev/null || true)
  if [ -z "$LOCATION" ]; then
    echo -n "Location (e.g. eastus2, southeastasia): "
    read -r LOCATION
  fi
fi

# ---------- Ensure resource group exists ----------
if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
  echo "Creating resource group '$RESOURCE_GROUP' in '$LOCATION'..."
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" -o none
fi

# ============================================================
# Step 1: Deploy Bicep (LAW + Workbook)
# ============================================================
echo ""
echo "=== Step 1/2: Deploying Infrastructure (Bicep) ==="
echo "  Workspace : $WORKSPACE_NAME"
echo "  Workbook  : $WORKBOOK_NAME"
echo "  Location  : $LOCATION"
echo ""

DEPLOY_OUTPUT=$(az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$SCRIPT_DIR/main.bicep" \
  --parameters \
    location="$LOCATION" \
    workspaceName="$WORKSPACE_NAME" \
    workbookDisplayName="$WORKBOOK_NAME" \
    retentionInDays="$RETENTION_DAYS" \
  --query "properties.outputs" \
  -o json)

LAW_RESOURCE_ID=$(echo "$DEPLOY_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['workspaceId']['value'])")
WORKBOOK_URL=$(echo "$DEPLOY_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['workbookPortalUrl']['value'])")

echo "✅ Infrastructure deployed!"
echo "  LAW ID    : $LAW_RESOURCE_ID"
echo "  Workbook  : $WORKBOOK_URL"

# ============================================================
# Step 2: Enable diagnostic settings on all OpenAI resources
# ============================================================
echo ""
echo "=== Step 2/2: Enabling Diagnostic Settings ==="

OPENAI_IDS=$(az resource list \
  --resource-type "Microsoft.CognitiveServices/accounts" \
  --query "[].id" -o tsv 2>/dev/null || true)

if [ -z "$OPENAI_IDS" ]; then
  echo "⚠  No Azure OpenAI resources found in subscription. Skipping diagnostics."
  echo "   Run enable.sh later after creating OpenAI resources."
else
  TOTAL=0; CREATED=0; SKIPPED=0; FAILED=0

  while IFS= read -r RID; do
    TOTAL=$((TOTAL + 1))
    NAME=$(basename "$RID")
    RG=$(echo "$RID" | sed -n 's|.*/resourceGroups/\([^/]*\)/.*|\1|Ip')
    echo "  [$TOTAL] $NAME (RG: $RG)"

    EXISTING=$(az monitor diagnostic-settings list \
      --resource "$RID" \
      --query "length((value || \`[]\`)[?name=='$DIAG_SETTING_NAME'])" -o tsv 2>/dev/null || echo "0")

    if [ "$EXISTING" = "1" ]; then
      echo "       ⏭  Already configured."
      SKIPPED=$((SKIPPED + 1))
      continue
    fi

    LOG_CATEGORIES=$(az monitor diagnostic-settings categories list \
      --resource "$RID" \
      --query "value[?categoryType=='Logs'].name" -o tsv 2>/dev/null)

    if [ -z "$LOG_CATEGORIES" ]; then
      echo "       ⚠  No log categories. Skipping."
      SKIPPED=$((SKIPPED + 1))
      continue
    fi

    LOGS_JSON="["
    FIRST=1
    while IFS= read -r CAT; do
      [ -z "$CAT" ] && continue
      [ $FIRST -eq 0 ] && LOGS_JSON+=","
      LOGS_JSON+="{\"category\":\"$CAT\",\"enabled\":true}"
      FIRST=0
    done <<< "$LOG_CATEGORIES"
    LOGS_JSON+="]"

    if az monitor diagnostic-settings create \
      --name "$DIAG_SETTING_NAME" \
      --resource "$RID" \
      --workspace "$LAW_RESOURCE_ID" \
      --logs "$LOGS_JSON" \
      --metrics '[{"category":"AllMetrics","enabled":true}]' \
      -o none 2>&1; then
      echo "       ✅  Created."
      CREATED=$((CREATED + 1))
    else
      echo "       ❌  Failed."
      FAILED=$((FAILED + 1))
    fi
  done <<< "$OPENAI_IDS"

  echo ""
  echo "  Diagnostics summary: $TOTAL total, $CREATED created, $SKIPPED skipped, $FAILED failed"
fi

# ============================================================
# Done
# ============================================================
echo ""
echo "================================================"
echo "✅ Deployment complete!"
echo ""
echo "📊 Open Workbook in Azure Portal:"
echo "   $WORKBOOK_URL"
echo ""
echo "💡 Data will appear in 5-10 minutes after first API calls."
echo "================================================"
