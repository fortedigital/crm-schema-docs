# Salesforce CRM

ER diagrams and field reference for a Salesforce org (Sales Cloud / Service Cloud).

## Sample output

The [`sample/`](./sample/) directory contains placeholder output representing a standard Salesforce Sales Cloud and Service Cloud org. It illustrates the pipeline output format but is **not** an export from any real environment.

Run the pipeline against your own Salesforce org to generate actual output in `diagrams/`, `objects/`, and `salesforce-object-reference.md`.

## Pipeline

```
scripts/gather/   →  data/raw/      (requires sf CLI + org auth)
scripts/clean/    →  data/clean/    (local transform, no auth)
scripts/generate/ →  diagrams/      (Mermaid .mmd files)
                     objects/       (field CSVs, one per object)
                     salesforce-object-reference.md  +  diagrams-rendered/
```

## Prerequisites

### Tools

| Tool | Install | Required for |
|---|---|---|
| [PowerShell 7+](https://aka.ms/powershell) | `winget install Microsoft.PowerShell` | All stages |
| [Node.js](https://nodejs.org/) (includes npm) | Download from nodejs.org or `winget install OpenJS.NodeJS` | sf CLI and mmdc |
| [Salesforce CLI (sf)](https://developer.salesforce.com/tools/salesforcecli) | `npm install -g @salesforce/cli` | Gather stage (auth + org selection) |
| [Mermaid CLI (mmdc)](https://github.com/mermaid-js/mermaid-cli) | `npm install -g @mermaid-js/mermaid-cli` | Generate stage (PNG rendering) |

### Access

**Interactive auth (default)**

The Salesforce user account must have:

- **API Enabled** — profile permission required for all REST and Tooling API calls
- **View Setup and Configuration** — required for Tooling API access used during object discovery
- Read access to the objects being documented

**System Administrator** profile satisfies all of these. For custom profiles, ensure both permissions above are explicitly enabled.

**JWT auth (non-interactive)**

In addition to the above user permissions, JWT auth requires a Connected App configured in the Salesforce org with:

- OAuth enabled and a digital signature (X.509 certificate) uploaded
- The running user's profile or permission set pre-authorized on the Connected App
- `clientId`, `username`, and `jwtKeyFile` set in `scripts/gather/config.json`

## Quick start

```powershell
# Full pipeline — authenticate interactively, then run all stages
.\scripts\run-pipeline.ps1 -SelectOrg

# Re-generate from existing raw data
.\scripts\run-pipeline.ps1 -SkipGather

# Re-generate outputs only
.\scripts\run-pipeline.ps1 -SkipGather -SkipClean
```

## Auth modes

| Mode | Description |
|---|---|
| `Interactive` | Browser login via `sf org login web` — one-time per session |
| `JWT` | Non-interactive via `sf org login jwt` — requires Connected App + private key |

Copy the example config and fill in your environment details:

```powershell
cp scripts/gather/config.example.json scripts/gather/config.json
```

Configure in `scripts/gather/config.json`:

```json
{
  "environment": {
    "orgAlias": "<your-org-alias>",
    "apiVersion": "62.0",
    "authMode": "Interactive"
  }
}
```

For JWT auth, also set `clientId`, `username`, and `jwtKeyFile`.

## Object discovery

| Mode | What it selects |
|---|---|
| `custom` | All custom objects (`__c` suffix), excluding custom settings |
| `namespace` | Objects with a given namespace prefix (empty = org-specific custom) |
| `filter` | Raw SOQL `WHERE` clause on `EntityDefinition` |

Configure in `scripts/gather/config.json`:

```json
{
  "objectSource": {
    "mode": "custom",
    "namespace": "",
    "filter": ""
  }
}
```

## Diagram groups

The `diagrams` section of `config.json` controls which objects appear in each diagram.
Objects not in the discovered set are silently skipped.

## Outputs

| File | Description |
|---|---|
| `diagrams/*.mmd` | Mermaid ER diagrams (one per group) |
| `diagrams-rendered/*.png` | Rendered PNGs — committed alongside the .md |
| `objects/*.csv` | Field reference per object — `api_name, label, type, required, is_custom, usage, bu_usage, comment` |
| `salesforce-object-reference.md` | Combined reference: embedded diagrams + field tables |

The `bu_usage` and `comment` columns in the CSVs are manual — fill them in as needed.
They are preserved across pipeline re-runs.

## Relationship notation

| Mermaid | Type | Meaning |
|---|---|---|
| `\|\|--o{` | Lookup | Parent to zero-or-many children (child lookup is optional) |
| `\|\|--\|{` | MasterDetail | Parent to one-or-many children (child must have parent) |
