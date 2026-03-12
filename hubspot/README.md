# HubSpot — Object Reference Pipeline

Generates ER diagrams, property CSVs, and HTML reference documents for a HubSpot portal.

## Prerequisites

- PowerShell 7+
- A HubSpot **Private App** token with CRM scopes (`crm.objects.*.read`, `crm.schemas.*`)
- `mmdc` (Mermaid CLI) for PNG rendering: `npm install -g @mermaid-js/mermaid-cli`

## Quick start

```powershell
# 1. Copy the example config and add your Private App token
#    cp scripts/gather/config.example.json scripts/gather/config.json
#    Then set: environment.privateAppToken and environment.portalId

# 2. Run the full pipeline
cd hubspot/scripts
.\run-pipeline.ps1

# Or run stages individually:
.\run-pipeline.ps1 -SkipGather          # clean + generate only
.\run-pipeline.ps1 -SkipGather -SkipClean  # generate only
```

## Pipeline stages

| Stage    | Script                     | Input              | Output                          |
|----------|----------------------------|--------------------|----------------------------------|
| Gather   | `gather/run-gather.ps1`    | HubSpot API        | `data/raw/`                      |
| Clean    | `clean/run-clean.ps1`      | `data/raw/`        | `data/clean/`                    |
| Generate | `generate/run-generate.ps1`| `data/clean/`      | `output/diagrams/`, `output/objects/`, `output/*.html`, `output/*.md` |

## Configuration

Copy the example config and fill in your portal details:

```powershell
cp scripts/gather/config.example.json scripts/gather/config.json
```

`scripts/gather/config.json`:

```json
{
  "environment": {
    "portalId": "12345678",
    "privateAppToken": "pat-eu1-...",
    "authMode": "PrivateApp"
  },
  "objectSource": {
    "mode": "all"
  },
  "diagrams": {
    "core-objects":  ["contacts", "companies", "deals"],
    "sales-process": ["deals", "line_items", "products", "quotes"],
    "service":       ["contacts", "companies", "tickets"]
  }
}
```

**objectSource modes:**
- `all` — standard + custom objects (default)
- `standard` — only built-in HubSpot objects
- `custom` — only custom objects from `/crm/v3/schemas`
- `filter` — specific list: `"filter": ["contacts", "my_custom_obj"]`

## Outputs

- `output/hubspot-object-reference.html` — self-contained interactive reference (objects in diagram groups)
- `output/hubspot-uncategorized-objects.html` — objects not in any diagram group
- `output/hubspot-object-reference.md` — Markdown with rendered PNG diagrams
- `output/diagrams/*.mmd` — Mermaid source files
- `output/diagrams-rendered/*.png` — rendered diagram images
- `output/objects/*.csv` — property list per object (manual `bu_usage`/`comment` columns preserved)

## Auth

The pipeline uses a HubSpot **Private App** token. Create one at:
> HubSpot → Settings → Integrations → Private Apps

Required scopes: `crm.objects.contacts.read`, `crm.objects.companies.read`,
`crm.objects.deals.read`, `crm.objects.tickets.read`, `crm.schemas.read`,
`crm.objects.custom.read` (for custom objects), `automation` (for workflows).

Alternatively set `$env:HUBSPOT_TOKEN` before running scripts.
