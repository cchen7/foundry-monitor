// ============================================================
// Foundry OpenAI Monitor — Full deployment
// Creates: Log Analytics Workspace + Azure Monitor Workbook
// Usage:  az deployment group create -g <rg> -f main.bicep
// ============================================================

@description('Location for all resources. Defaults to resource group location.')
param location string = resourceGroup().location

@description('Name of the Log Analytics Workspace (used when creating a new one).')
param workspaceName string = 'law-foundry-monitor'

@description('Resource ID of an existing Log Analytics Workspace. If provided, skips LAW creation.')
param existingWorkspaceId string = ''

@description('Display name for the Workbook.')
param workbookDisplayName string = 'Foundry OpenAI Monitor'

@description('Log Analytics data retention in days (30-730). Only used when creating a new workspace.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

// ─── Determine mode ─────────────────────────────────────────
var createNewWorkspace = empty(existingWorkspaceId)

// ─── Log Analytics Workspace (conditional) ──────────────────
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (createNewWorkspace) {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
  }
}

var effectiveWorkspaceId = createNewWorkspace ? workspace.id : existingWorkspaceId

// ─── Workbook ───────────────────────────────────────────────
// NOTE: Diagnostic settings for existing OpenAI resources are handled
// by enable.sh (imperative), since Bicep can't discover existing
// resources across multiple resource groups at deploy time.
var rawWorkbookContent = loadTextContent('workbook-content.json')
var workbookContent = replace(rawWorkbookContent, '{{LAW_RESOURCE_ID}}', effectiveWorkspaceId)

resource workbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: guid(workbookDisplayName, resourceGroup().id)
  location: location
  kind: 'shared'
  properties: {
    displayName: workbookDisplayName
    serializedData: workbookContent
    version: '1.0'
    sourceId: effectiveWorkspaceId
    category: 'workbook'
  }
}

// ─── Outputs ────────────────────────────────────────────────
output workspaceId string = effectiveWorkspaceId
output workspaceName string = createNewWorkspace ? workspace.name : last(split(existingWorkspaceId, '/'))
output workbookId string = workbook.id
output workbookPortalUrl string = '${environment().portal}/#@/resource${workbook.id}'
