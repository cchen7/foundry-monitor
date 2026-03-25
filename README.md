# 🔍 Foundry OpenAI Monitor

One-click monitoring solution for all Azure OpenAI (CognitiveServices/accounts) resources in a subscription. Deploys a Log Analytics Workspace, comprehensive Azure Monitor Workbook, and configures diagnostic settings across all resources automatically.

## What You Get

| Component | Description |
|---|---|
| **Log Analytics Workspace** | Centralized log store for all diagnostics |
| **Azure Monitor Workbook** | 23-panel dashboard with 5 monitoring sections |
| **Diagnostic Settings** | Auto-configured on every OpenAI resource in the subscription |

### Dashboard Sections

- 📊 **Overview** — Total requests, tokens, avg latency, error rate (KPI tiles)
- 📈 **HTTP Requests** — Request trend, per-resource breakdown, status code distribution
- 🪙 **Token Usage** — Prompt vs completion tokens, by model, by resource
- ⏱️ **Latency** — Avg/Max trend, P50/P95/P99 by model, per-resource table
- ❌ **Errors** — Error rate trend, by status code, by resource

## Quick Start

### Prerequisites

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az`) logged in
- A subscription with Azure OpenAI resources

### One-Click Deploy

```bash
git clone https://github.com/cchen7/foundry-monitor.git
cd foundry-monitor

# Interactive — prompts for subscription, resource group, location
./deploy.sh

# Or non-interactive
SUBSCRIPTION_ID=xxx RESOURCE_GROUP=my-rg LOCATION=eastus2 ./deploy.sh
```

This will:
1. Create a Log Analytics Workspace
2. Deploy the monitoring Workbook
3. Scan all Azure OpenAI resources and enable diagnostic settings

### Bicep-Only (Infrastructure)

If you only need the LAW + Workbook without auto-configuring diagnostics:

```bash
az deployment group create \
  -g <resource-group> \
  -f main.bicep \
  --parameters workspaceName=my-law workbookDisplayName="My Dashboard"
```

Then run `enable.sh` separately to configure diagnostics.

## File Structure

```
foundry-monitor/
├── main.bicep              # Bicep template (LAW + Workbook)
├── workbook-content.json   # Workbook definition (23 panels)
├── deploy.sh               # Full deployment orchestrator
├── enable.sh               # Standalone diagnostic settings script
└── deploy-workbook.sh      # Standalone workbook deployment script
```

## Configuration

All scripts support environment variable overrides:

| Variable | Default | Description |
|---|---|---|
| `SUBSCRIPTION_ID` | *(prompted)* | Target Azure subscription |
| `RESOURCE_GROUP` | *(prompted)* | Resource group for LAW + Workbook |
| `LOCATION` | *(auto-detected)* | Azure region |
| `WORKSPACE_NAME` | `law-foundry-monitor` | Log Analytics Workspace name |
| `WORKBOOK_NAME` | `Foundry OpenAI Monitor` | Workbook display name |
| `RETENTION_DAYS` | `30` | Log retention period (30–730 days) |

## Cost Estimate

| Component | Cost |
|---|---|
| Workbook | **Free** |
| Platform Metrics (AzureMetrics) | **Free** |
| Diagnostic Logs | ~$2.76/GB/month |

Typical monthly cost by API call volume:

| Monthly Calls | Est. Log Volume | Est. Cost |
|---|---|---|
| 10,000 | ~30 MB | ~$0.08 |
| 100,000 | ~300 MB | ~$0.83 |
| 1,000,000 | ~3 GB | ~$8.28 |

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  Subscription                    │
│                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐      │
│  │ OpenAI 1 │  │ OpenAI 2 │  │ OpenAI N │      │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘      │
│       │              │              │            │
│       └──────── Diagnostic ─────────┘            │
│                 Settings                         │
│                    │                             │
│           ┌────────▼────────┐                    │
│           │  Log Analytics  │                    │
│           │   Workspace     │                    │
│           └────────┬────────┘                    │
│                    │                             │
│           ┌────────▼────────┐                    │
│           │ Azure Monitor   │                    │
│           │    Workbook     │                    │
│           └─────────────────┘                    │
└─────────────────────────────────────────────────┘
```

## License

MIT
