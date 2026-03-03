# Microsoft Dynamics 365 CRM — Entity Diagrams

ER diagrams and entity definitions covering the standard Dynamics 365 Sales and Service entities.

## Pipeline

```
scripts/gather/   →   data/raw/   →   scripts/clean/   →   scripts/generate/   →   diagrams/
```

## Diagrams

Entity names and relationships only — properties are in the CSV files below.

| File | Entities covered |
|---|---|
| [`diagrams/core-entities.mmd`](./diagrams/core-entities.mmd) | Account, Contact, Lead, Opportunity |
| [`diagrams/sales-process.mmd`](./diagrams/sales-process.mmd) | Opportunity, Quote, Order, Invoice, Product, line items |
| [`diagrams/activities.mmd`](./diagrams/activities.mmd) | ActivityPointer, Email, PhoneCall, Task, Appointment, ActivityParty |
| [`diagrams/service.mmd`](./diagrams/service.mmd) | Incident (Case), KnowledgeArticle, Subject |

## Entity definitions

One CSV per entity: `logical_name, display_name, type, required`

| Entity | File |
|---|---|
| Account | [`entities/account.csv`](./entities/account.csv) |
| Contact | [`entities/contact.csv`](./entities/contact.csv) |
| Lead | [`entities/lead.csv`](./entities/lead.csv) |
| Opportunity | [`entities/opportunity.csv`](./entities/opportunity.csv) |
| Quote | [`entities/quote.csv`](./entities/quote.csv) |
| Quote Line | [`entities/quotedetail.csv`](./entities/quotedetail.csv) |
| Order | [`entities/salesorder.csv`](./entities/salesorder.csv) |
| Order Line | [`entities/salesorderdetail.csv`](./entities/salesorderdetail.csv) |
| Invoice | [`entities/invoice.csv`](./entities/invoice.csv) |
| Invoice Line | [`entities/invoicedetail.csv`](./entities/invoicedetail.csv) |
| Product | [`entities/product.csv`](./entities/product.csv) |
| Activity (base) | [`entities/activitypointer.csv`](./entities/activitypointer.csv) |
| Email | [`entities/email.csv`](./entities/email.csv) |
| Phone Call | [`entities/phonecall.csv`](./entities/phonecall.csv) |
| Task | [`entities/task.csv`](./entities/task.csv) |
| Appointment | [`entities/appointment.csv`](./entities/appointment.csv) |
| Activity Party | [`entities/activityparty.csv`](./entities/activityparty.csv) |
| Case (Incident) | [`entities/incident.csv`](./entities/incident.csv) |
| Knowledge Article | [`entities/knowledgearticle.csv`](./entities/knowledgearticle.csv) |
| Subject | [`entities/subject.csv`](./entities/subject.csv) |

## Running the pipeline

Prerequisites: PowerShell 7+, [pac CLI](https://aka.ms/install-pac-cli), Dataverse access.
Optional: [`mmdc`](https://github.com/mermaid-js/mermaid-cli) for rendered diagram images in the .docx.

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
diagrams/*.mmd                         ← committed  (Mermaid source)
diagrams-rendered/*.png                ← committed  (rendered by mmdc)
entities/*.csv                         ← committed  (bu_usage / comment: fill manually)
dynamics-crm-entity-reference.md       ← committed  (full reference document)
```

`mmdc` (Mermaid CLI) is required for the generate stage: `npm install -g @mermaid-js/mermaid-cli`

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
