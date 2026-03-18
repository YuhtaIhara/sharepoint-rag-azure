# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability, please report it through [GitHub Security Advisories](https://github.com/YuhtaIhara/sharepoint-rag-azure/security/advisories/new).

Do **not** open a public issue for security vulnerabilities.

## Security Design

- **Threat Model**: STRIDE-based analysis covering 11 threat scenarios
- **Authentication**: Entra ID SSO (MSAL) for users, Managed Identity for service-to-service
- **Authorization**: ACL-based document filtering using SharePoint folder permissions
- **Secrets Management**: Azure Key Vault with RBAC access control

See [Security Design Document](docs/03-security.md) for full details.
