# Azure Resource Deployment

This repository contains scripts for deploying Azure resources including app registrations, bot registrations, and Teams applications.

## Quick Start

1. **Setup**:
   ```bash
   ./setup.sh
   ```

2. **Configure**:
   - Edit `config/environment.yaml` with your settings
   - Update tenant ID and other environment-specific values

3. **Validate**:
   ```bash
   ./scripts/validate-deployment.sh
   ```

4. **Deploy**:
   ```bash
   ./scripts/deploy.sh
   ```

5. **Configure Bot & Teams**:
   ```bash
   ./scripts/bot-teams-config.sh
   ```

## Documentation

- [Deployment Guide](docs/DEPLOYMENT.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Configuration Reference](docs/CONFIGURATION.md)

## Scripts

- `deploy.sh` - Main deployment script
- `cleanup.sh` - Resource cleanup
- `validate-deployment.sh` - Pre-deployment validation
- `bot-teams-config.sh` - Bot and Teams configuration

## Support

See troubleshooting guide or contact your Azure administrator.
