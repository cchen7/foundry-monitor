#!/usr/bin/env bash
set -euo pipefail

SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-07d9302c-2554-489e-bb80-a2250deafb40}"
RESOURCE_GROUP="${RESOURCE_GROUP:-ai-project-podautomation}"
LAW_RESOURCE_ID="${LAW_RESOURCE_ID:-/subscriptions/07d9302c-2554-489e-bb80-a2250deafb40/resourcegroups/ai-project-podautomation/providers/microsoft.operationalinsights/workspaces/workspace-aiprojectpodautomationz4gm}"
WORKBOOK_NAME="${WORKBOOK_NAME:-Foundry OpenAI Monitor}"
LOCATION="${LOCATION:-eastus2}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTENT_FILE="$SCRIPT_DIR/workbook-content.json"

if [ ! -f "$CONTENT_FILE" ]; then
  echo "ERROR: workbook-content.json not found at $CONTENT_FILE"
  exit 1
fi

# Generate a deterministic GUID based on the workbook name
WORKBOOK_ID=$(python3 -c "import uuid; print(str(uuid.uuid5(uuid.NAMESPACE_DNS, '$WORKBOOK_NAME')))")

echo "=== Deploy Azure Monitor Workbook ==="
echo "Subscription : $SUBSCRIPTION_ID"
echo "Resource Group: $RESOURCE_GROUP"
echo "Workbook Name : $WORKBOOK_NAME"
echo "Workbook ID   : $WORKBOOK_ID"
echo "Location      : $LOCATION"
echo ""

az account set --subscription "$SUBSCRIPTION_ID"

# Check if resource group location
RG_LOCATION=$(az group show --name "$RESOURCE_GROUP" --query location -o tsv 2>/dev/null || echo "$LOCATION")
echo "Using location: $RG_LOCATION"

# Read and escape the content
SERIALIZED_DATA=$(python3 -c "
import json, sys
with open('$CONTENT_FILE') as f:
    content = json.load(f)
print(json.dumps(json.dumps(content)))
")

# Build the request body
BODY=$(python3 -c "
import json
serialized = $SERIALIZED_DATA
body = {
    'location': '$RG_LOCATION',
    'kind': 'shared',
    'properties': {
        'displayName': '$WORKBOOK_NAME',
        'serializedData': serialized,
        'version': '1.0',
        'sourceId': '$LAW_RESOURCE_ID',
        'category': 'workbook'
    }
}
print(json.dumps(body))
")

# Deploy the workbook
echo "Deploying workbook..."
if RESULT=$(az rest --method PUT \
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/workbooks/$WORKBOOK_ID?api-version=2022-04-01" \
  --body "$BODY" 2>&1); then
  echo ""
  echo "✅ Workbook deployed successfully!"
  echo ""
  echo "📊 Open in Azure Portal:"
  echo "   https://portal.azure.com/#@/resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/workbooks/$WORKBOOK_ID"
else
  echo "❌ Deployment failed:"
  echo "$RESULT"
  exit 1
fi
