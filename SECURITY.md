# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please **do not** open a public GitHub issue.

Instead, report it privately by emailing **<opensource@fortedigital.com>** with:

- A description of the vulnerability
- Steps to reproduce or proof-of-concept (if applicable)
- Potential impact

We will acknowledge receipt within **5 business days** and aim to provide a resolution or mitigation plan within **30 days** for confirmed vulnerabilities.

## Sensitive Data Reminder

This project contains scripts that connect to live CRM environments. Please ensure you:

- Never commit credentials, tokens, API keys, or personal environment URLs to the repository.
- Keep `config.json` files local and out of version control (the `.gitignore` already excludes `data/` directories — treat your own config values as sensitive).
- Rotate any credentials that may have been accidentally exposed.
