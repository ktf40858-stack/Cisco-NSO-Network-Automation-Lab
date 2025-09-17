# NSO Network Automation Lab

This repository contains configuration files, scripts, and documentation for Cisco NSO (Network Services Orchestrator) network automation implementation.

## Structure

- **configs/**: NSO configuration files
  - **devices/**: Device-specific configurations (authgroups, definitions, groups)
  - **services/**: Service configurations (VLAN, DNS templates)
- **scripts/**: Automation and deployment scripts
- **docs/**: Documentation and guides
- **templates/**: XML templates for NSO services

## Quick Start

1. Run the setup script:
   ```bash
   ./scripts/setup-nso-instance.sh
   ```

2. Deploy configurations:
   ```bash
   ./scripts/deploy-configs.sh
   ```

3. Verify deployment:
   ```bash
   ./scripts/verification-tests.sh
   ```

## Documentation

- [Architecture Overview](docs/architecture.md)
- [Deployment Guide](docs/deployment-guide.md)
- [Troubleshooting](docs/troubleshooting.md)

## Requirements

- Cisco NSO 5.x or higher
- Linux/Unix environment
- Python 3.x (for automation scripts)

## License

See [LICENSE](LICENSE) file for details.