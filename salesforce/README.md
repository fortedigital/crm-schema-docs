# Salesforce CRM

ER diagrams and field reference for a Salesforce org (Sales Cloud / Service Cloud).

## Pipeline

```
scripts/gather/   →  data/raw/      (requires sf CLI + org auth)
scripts/clean/    →  data/clean/    (local transform, no auth)
scripts/generate/ →  diagrams/      (Mermaid .mmd files)
                     objects/       (field CSVs, one per object)
                     salesforce-object-reference.md  +  diagrams-rendered/
```

## Quick start

```powershell
# Prerequisites
npm install --global @salesforce/cli
npm install --global @mermaid-js/mermaid-cli

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

Configure in `scripts/gather/config.json`:

```json
{
  "environment": {
    "orgAlias": "oras-sf",
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
