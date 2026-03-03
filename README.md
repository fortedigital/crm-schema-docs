# CRM Entity Diagrams

Mermaid ER diagrams documenting entities, relationships, and properties for CRM systems.

## Systems

| Folder | CRM |
|---|---|
| [`dynamics-crm/`](./dynamics-crm/) | Microsoft Dynamics 365 CRM |
| [`salesforce/`](./salesforce/) | Salesforce CRM |

## Diagram format

All diagrams use [Mermaid](https://mermaid.js.org/) `erDiagram` syntax (`.mmd` files).
They render natively in GitHub, GitLab, and most modern Markdown viewers.

## Scripts

Each system folder contains a `scripts/` directory with utilities to extract or
generate entity metadata, written in PowerShell (`.ps1`) or Bash (`.sh`).
