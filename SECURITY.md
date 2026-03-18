# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability, please report it via [GitHub Issues](../../issues) with the label `security`.

## Security Design

This project includes a comprehensive security design:

- **Threat Model**: STRIDE-based analysis covering 11 threat scenarios
- **Authentication**: Entra ID SSO (MSAL) for users, Managed Identity for service-to-service
- **Authorization**: ACL-based document filtering using SharePoint folder permissions
- **Secrets Management**: Azure Key Vault with RBAC access control

See [Security Design Document](docs/03-security.md) for full details.
