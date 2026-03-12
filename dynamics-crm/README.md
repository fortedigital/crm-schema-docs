# Microsoft Dynamics 365 CRM — Entity Diagrams

ER diagrams and entity definitions covering the standard Dynamics 365 Sales and Service entities.

## Pipeline

```
scripts/gather/   →   data/raw/   →   scripts/clean/   →   scripts/generate/   →   diagrams/
```

## Sample output

The [`sample/`](./sample/) directory contains placeholder output generated against a standard Dynamics 365 Sales and Service demo environment. It illustrates the pipeline output format but is **not** an export from any real environment.

Run the pipeline against your own Dataverse environment to generate actual output in the `output/` directory.

## Prerequisites

### Tools

| Tool | Install | Required for |
|---|---|---|
| [PowerShell 7+](https://aka.ms/powershell) | `winget install Microsoft.PowerShell` | All stages |
| [Node.js](https://nodejs.org/) (includes npm) | Download from nodejs.org or `winget install OpenJS.NodeJS` | mmdc |
| [Mermaid CLI (mmdc)](https://github.com/mermaid-js/mermaid-cli) | `npm install -g @mermaid-js/mermaid-cli` | Generate stage (PNG rendering) |

### Access

**Interactive auth (default)**

The user account must have access to the target Dataverse environment and be assigned a security role that allows reading entity metadata. **System Customizer** or **System Administrator** is recommended. A read-only role without metadata access will not work.

**Service principal auth**

Requires an Azure AD app registration with the Dataverse `user_impersonation` permission granted. The app registration must also be associated with a Dataverse application user assigned a security role with metadata read access (System Customizer or System Administrator).

Set `authMode: "ServicePrincipal"` in `scripts/gather/config.json` and provide the client secret via:

```powershell
$env:DATAVERSE_CLIENT_SECRET = '<your-secret>'
```

## Running the pipeline

```powershell
cd scripts

# Full pipeline — first run (picks environment interactively)
.\run-pipeline.ps1 -SelectEnvironment

# Full pipeline — subsequent runs
.\run-pipeline.ps1

# Skip stages you don't need
.\run-pipeline.ps1 -SkipGather              # clean + generate only
.\run-pipeline.ps1 -SkipGather -SkipClean   # generate only
```

Or run individual stages:

```powershell
.\gather\run-gather.ps1 [-SelectEnvironment]
.\clean\run-clean.ps1
.\generate\run-generate.ps1
```

### Data flow

```
Dataverse API
    │
    ▼
data/raw/                              ← gitignored
  entities.json
  attributes/<entity>.json
  relationships/<entity>.json
  view-usage/<entity>.json
    │
    ▼  scripts/clean/
data/clean/                            ← gitignored
  entities.json
  attributes/<entity>.json
  relationships.json
    │
    ▼  scripts/generate/
output/                                ← gitignored
  diagrams/*.mmd                       (Mermaid source)
  diagrams-rendered/*.png              (rendered by mmdc)
  entities/*.csv                       (bu_usage / comment: fill manually)
  dynamics-crm-entity-reference.md     (full reference document)
  dynamics-crm-entity-reference.html   (self-contained HTML with client-side Mermaid)
```

`mmdc` (Mermaid CLI) is required for the generate stage: `npm install -g @mermaid-js/mermaid-cli`

### Configuration

Copy the example config and fill in your environment details:

```powershell
cp scripts/gather/config.example.json scripts/gather/config.json
```

Then edit `scripts/gather/config.json` with your Dataverse URL, tenant ID, and client ID.

> **Note:** `scripts/gather/config.json` is gitignored to prevent accidental credential leaks. Always use `config.example.json` as the template.

### Auth modes

| Mode | How |
|---|---|
| Interactive (default) | Device-code flow — browser prompt once per session |
| Service principal | Set `authMode: ServicePrincipal` in config.json, pass secret via `$env:DATAVERSE_CLIENT_SECRET` |

### Diagram groups

Controlled by the `diagrams` section in `scripts/gather/config.json`.
Each key is a diagram file name; the value lists which entities appear in it.
An entity can appear in multiple diagrams (e.g. `account` is in core-entities, activities, and service).

## Reference

- [Dataverse Web API — EntityDefinitions](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/entitydefinitions)
- [Dataverse Web API — Attributes](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/attributemetadata)
- [Dataverse Web API — Relationships](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/relationshipmetadata)
