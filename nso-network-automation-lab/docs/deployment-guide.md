# NSO Network Automation Deployment Guide

## Prerequisites

### System Requirements
- **Operating System**: Linux (Ubuntu 20.04/22.04, RHEL 8/9, CentOS 8)
- **Memory**: Minimum 8GB RAM (16GB recommended)
- **Storage**: Minimum 20GB free space
- **CPU**: 4+ cores recommended
- **Java**: JDK 8 or higher
- **Python**: Python 3.6+

### Software Requirements
- Cisco NSO 5.7 or higher
- Required NEDs (Network Element Drivers)
- Git for version control
- Make utility for compilation

### Network Requirements
- Management network connectivity to all devices
- SSH access to network devices
- HTTPS access for Web UI (port 8080)
- SSH access for CLI (port 2024)

## Installation Steps

### 1. Install NSO

```bash
# Download NSO installer from Cisco
# Extract the installer
tar -xf nso-5.7.linux.x86_64.installer.bin

# Run the installer
sh nso-5.7.linux.x86_64.installer.bin /opt/nso

# Source NSO environment
source /opt/nso/ncsrc
```

### 2. Install NEDs

```bash
# Navigate to NEDs directory
cd /opt/nso/packages/neds

# Extract NED packages
tar -xzf cisco-ios-cli-6.77.tar.gz
tar -xzf cisco-iosxr-cli-7.38.tar.gz
tar -xzf cisco-asa-cli-6.12.tar.gz
```

### 3. Clone Repository

```bash
# Clone the automation lab repository
git clone https://github.com/your-org/nso-network-automation-lab.git
cd nso-network-automation-lab
```

### 4. Run Setup Script

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Run the setup script
./scripts/setup-nso-instance.sh
```

## Configuration Steps

### 1. Configure Authentication

#### Update Admin Password
```bash
ncs_cli -u admin
admin@ncs> configure
admin@ncs% set aaa authentication users user admin password
Enter new password: ********
Confirm password: ********
admin@ncs% commit
```

#### Configure Device Credentials
Edit `configs/devices/authgroups.cfg`:
```cisco
devices authgroups group production-group
 default-map remote-name your-username
 default-map remote-password your-password
!
```

### 2. Load Device Configurations

```bash
# Deploy device configurations
./scripts/deploy-configs.sh

# Or manually load configurations
ncs_cli -u admin
admin@ncs> configure
admin@ncs% load merge configs/devices/device-definitions.cfg
admin@ncs% commit
```

### 3. Connect to Devices

```bash
# Test connectivity to all devices
ncs_cli -u admin
admin@ncs> devices device * connect

# Sync from devices
admin@ncs> devices sync-from
```

### 4. Deploy Services

```bash
# Load VLAN service
ncs_cli -u admin
admin@ncs> configure
admin@ncs% load merge configs/services/vlan-service.cfg
admin@ncs% commit

# Load DNS service
admin@ncs% load merge configs/services/dns-template.cfg
admin@ncs% commit
```

## Deployment Scenarios

### Scenario 1: Lab Environment

1. **Minimal Setup**
   ```bash
   # Use test authgroup
   devices authgroups group test-group
    default-map remote-name testuser
    default-map remote-password testpass123
   ```

2. **Limited Devices**
   - Deploy only core switches initially
   - Add access switches incrementally

3. **Basic Services**
   - Start with VLAN service
   - Add DNS after validation

### Scenario 2: Production Environment

1. **High Availability Setup**
   ```bash
   # Configure HA
   high-availability enabled
   high-availability vip 10.0.0.100
   high-availability node primary
   ```

2. **Security Hardening**
   ```bash
   # Enable HTTPS only
   webui transport https port 443

   # Restrict SSH access
   ssh restrict-source 10.0.0.0/24
   ```

3. **Performance Tuning**
   ```xml
   <!-- Edit ncs.conf -->
   <java-vm>
     <java-options>-Xmx4096m -Xms2048m</java-options>
   </java-vm>
   ```

### Scenario 3: Multi-Site Deployment

1. **Regional NSO Instances**
   - Deploy NSO per region
   - Configure LSA (Layered Service Architecture)

2. **Device Distribution**
   ```cisco
   devices device-group region-west
    device-name sw-west-*
   !
   devices device-group region-east
    device-name sw-east-*
   !
   ```

## Verification

### 1. Run Verification Tests

```bash
# Execute comprehensive tests
./scripts/verification-tests.sh

# Check specific components
ncs_cli -u admin
admin@ncs> show packages package oper-status
admin@ncs> devices check-sync
admin@ncs> services check-sync
```

### 2. Validate Services

```bash
# Check VLAN deployment
show running-config devices device sw-core-01 config vlan

# Check DNS configuration
show running-config devices device sw-core-01 config ip name-server
```

### 3. Monitor Logs

```bash
# NSO logs
tail -f logs/ncs.log
tail -f logs/devel.log

# Device trace logs
tail -f logs/ned-cisco-ios-cli.trace
```

## Troubleshooting Deployment Issues

### Issue 1: Device Connection Failures

**Symptoms**: Cannot connect to devices
**Solution**:
```bash
# Check device reachability
ping 10.0.1.1

# Verify SSH access
ssh admin@10.0.1.1

# Check authgroups
show running-config devices authgroups

# Re-fetch SSH host keys
devices device sw-core-01 ssh fetch-host-keys
```

### Issue 2: Service Deployment Failures

**Symptoms**: Services not deploying correctly
**Solution**:
```bash
# Perform dry-run
commit dry-run outformat native

# Check service dependencies
show services vlan-service vlan-100 check-sync

# Force re-deploy
services vlan-service vlan-100 re-deploy
```

### Issue 3: Performance Issues

**Symptoms**: Slow response times
**Solution**:
```bash
# Increase Java heap size
vi ncs.conf
# Update: <java-options>-Xmx8192m</java-options>

# Restart NSO
ncs --reload
```

## Post-Deployment Tasks

### 1. Create Backup

```bash
# Backup configuration
ncs-backup

# Export configuration
show running-config | save backup-$(date +%Y%m%d).cfg
```

### 2. Set Up Monitoring

```bash
# Configure SNMP
snmp agent enabled
snmp community public-ro

# Configure syslog
logging server 10.0.4.30
```

### 3. Document Configuration

```bash
# Generate device inventory
show devices list > inventory.txt

# Document services
show services > services.txt
```

## Security Checklist

- [ ] Change default passwords
- [ ] Configure RBAC
- [ ] Enable audit logging
- [ ] Secure communication channels
- [ ] Implement backup encryption
- [ ] Configure session timeouts
- [ ] Restrict management access
- [ ] Enable compliance reporting

## Maintenance Tasks

### Daily
- Check device connectivity
- Review error logs
- Monitor service status

### Weekly
- Sync device configurations
- Create configuration backup
- Review change logs

### Monthly
- Update NEDs
- Performance analysis
- Security audit
- Capacity planning

## Advanced Deployment Options

### Using Ansible

```yaml
# ansible-playbook deploy-nso.yml
---
- name: Deploy NSO Configuration
  hosts: nso-server
  tasks:
    - name: Load device configuration
      nso_config:
        file: configs/complete-config.cfg

    - name: Sync devices
      nso_action:
        path: /devices
        action: sync-from
```

### Using Python API

```python
import ncs

with ncs.maapi.single_write_trans('admin', 'python') as t:
    root = ncs.maagic.get_root(t)

    # Add device
    device = root.devices.device.create('sw-new-01')
    device.address = '10.0.1.100'
    device.authgroup = 'lab-group'

    t.apply()
```

## Getting Help

- Documentation: `/opt/nso/doc/`
- Web UI Help: `http://localhost:8080/help`
- CLI Help: `admin@ncs> help`
- Logs: `logs/` directory
- Support: [Cisco NSO Support](https://developer.cisco.com/docs/nso/)