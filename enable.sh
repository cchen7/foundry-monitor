#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Enable Azure Monitor diagnostic settings for ALL Azure OpenAI
# (CognitiveServices/accounts) resources across the subscription.
#
# - Scans the entire subscription (not limited to one RG)
# - Enables ALL available log categories per resource
# - Enables AllMetrics
# - Idempotent: skips resources that already have the setting
# ============================================================

# ---------- Configuration ----------
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-07d9302c-2554-489e-bb80-a2250deafb40}"
LAW_RESOURCE_ID="${LAW_RESOURCE_ID:-/subscriptions/07d9302c-2554-489e-bb80-a2250deafb40/resourcegroups/ai-project-podautomation/providers/microsoft.operationalinsights/workspaces/workspace-aiprojectpodautomationz4gm}"
SETTING_NAME="${SETTING_NAME:-foundry-diagnostic-all-logs}"

# ---------- Counters ----------
TOTAL=0; CREATED=0; SKIPPED=0; FAILED=0

echo "=== Foundry Monitor: Enable Diagnostic Settings ==="
echo "Subscription : $SUBSCRIPTION_ID"
echo "LAW Resource : $LAW_RESOURCE_ID"
echo "Setting Name : $SETTING_NAME"
echo ""

az account set --subscription "$SUBSCRIPTION_ID"

# Discover all CognitiveServices/accounts across the entire subscription
OPENAI_IDS=$(az resource list \
  --resource-type "Microsoft.CognitiveServices/accounts" \
  --query "[].id" -o tsv)

if [ -z "$OPENAI_IDS" ]; then
  echo "No Azure OpenAI resources found in subscription. Exiting."
  exit 0
fi

while IFS= read -r RID; do
  TOTAL=$((TOTAL + 1))
  NAME=$(basename "$RID")
  RG=$(echo "$RID" | sed -n 's|.*/resourceGroups/\([^/]*\)/.*|\1|Ip')
  echo "[$TOTAL] Processing: $NAME  (RG: $RG)"

  # --- Idempotency check ---
  EXISTING=$(az monitor diagnostic-settings list \
    --resource "$RID" \
    --query "length((value || \`[]\`)[?name=='$SETTING_NAME'])" -o tsv 2>/dev/null || echo "0")

  if [ "$EXISTING" = "1" ]; then
    echo "    ⏭  Already configured. Skipping."
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # --- Build logs JSON: enable ALL available log categories ---
  LOG_CATEGORIES=$(az monitor diagnostic-settings categories list \
    --resource "$RID" \
    --query "value[?categoryType=='Logs'].name" -o tsv 2>/dev/null)

  if [ -z "$LOG_CATEGORIES" ]; then
    echo "    ⚠  No log categories found. Skipping."
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

  # --- Create diagnostic setting ---
  if az monitor diagnostic-settings create \
    --name "$SETTING_NAME" \
    --resource "$RID" \
    --workspace "$LAW_RESOURCE_ID" \
    --logs "$LOGS_JSON" \
    --metrics '[{"category":"AllMetrics","enabled":true}]' \
    -o none 2>&1; then
    echo "    ✅  Diagnostic setting created."
    CREATED=$((CREATED + 1))
  else
    echo "    ❌  Failed to create diagnostic setting."
    FAILED=$((FAILED + 1))
  fi

done <<< "$OPENAI_IDS"

# ---------- Summary ----------
echo ""
echo "=== Summary ==="
echo "Total resources : $TOTAL"
echo "Created         : $CREATED"
echo "Skipped (exist) : $SKIPPED"
echo "Failed          : $FAILED"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
