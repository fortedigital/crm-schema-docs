# Contributing

Thank you for your interest in contributing to CRM Schema Docs! Contributions of all kinds are welcome — bug reports, feature requests, documentation improvements, and code changes.

## How to Contribute

### Reporting Bugs

Use the [bug report issue template](.github/ISSUE_TEMPLATE/bug_report.md) and include:

- A clear description of the problem
- Steps to reproduce
- Expected vs. actual behaviour
- Your environment (OS, PowerShell version, CRM system)

### Suggesting Features

Use the [feature request issue template](.github/ISSUE_TEMPLATE/feature_request.md) to describe the use case and expected behaviour.

### Submitting a Pull Request

1. **Fork** the repository and create a branch from `main`.
2. Make your changes, keeping commits focused and descriptive.
3. Update documentation if your change affects behaviour or usage.
4. Open a pull request using the provided template and describe what was changed and why.

## Guidelines

- Keep changes focused. One concern per pull request.
- Follow the existing code style for PowerShell scripts (consistent indentation, naming conventions).
- Do not commit sensitive data such as credentials, tokens, or personal environment URLs.
- Test your scripts locally before submitting.

## Development Setup

Each CRM system folder (`dynamics-crm/`, `salesforce/`, `hubspot/`) is self-contained. See the `README.md` in each folder for prerequisites and configuration steps.

**Requirements:**

- PowerShell 7+
- Appropriate CRM CLI tools or API access (see per-system READMEs)
- [Mermaid CLI](https://github.com/mermaid-js/mermaid-cli) (`mmdc`) for rendering PNG diagrams (optional)

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you agree to abide by its terms.
