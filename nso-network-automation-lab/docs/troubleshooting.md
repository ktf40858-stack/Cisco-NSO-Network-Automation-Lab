# NSO Troubleshooting Guide

## Common Issues and Solutions

### 1. NSO Service Issues

#### NSO Won't Start

**Symptoms:**
- `ncs` command fails
- Error: "NCS daemon failed to start"

**Diagnosis:**
```bash
# Check if port is in use
netstat -tuln | grep 8080
lsof -i :2024

# Check NSO status
ncs --status

# Review logs
tail -100 logs/ncs.log
```

**Solutions:**
```bash
# Kill existing NSO process
ncs --stop

# Clean up lock files
rm -f state/ncs.lock

# Start with clean state
ncs --with-package-reload

# Start in foreground for debugging
ncs --foreground --verbose
```

#### NSO Crashes or Hangs

**Symptoms:**
- NSO becomes unresponsive
- High CPU/memory usage

**Solutions:**
```bash
# Generate thread dump
kill -3 $(pgrep -f ncs.jar)

# Check Java heap
jmap -heap $(pgrep -f ncs.jar)

# Increase memory allocation
vi ncs.conf
# Add: <java-options>-Xmx8192m -XX:+UseG1GC</java-options>

# Restart NSO
ncs --reload
```

### 2. Device Connectivity Issues

#### Cannot Connect to Device

**Symptoms:**
- "connection refused" error
- "result false" when connecting

**Diagnosis:**
```bash
# Test network connectivity
ping <device-ip>
traceroute <device-ip>

# Test SSH connectivity
ssh -v admin@<device-ip>

# Check from NSO
devices device <device-name> connect
devices device <device-name> ping
```

**Solutions:**
```bash
# Update SSH host keys
devices device <device-name> ssh fetch-host-keys

# Check authgroup credentials
show running-config devices authgroups

# Update device credentials
devices authgroups group <group-name>
  default-map remote-name <username>
  default-map remote-password <password>
commit

# Verify NED compatibility
show packages package cisco-ios-cli-6.77 oper-status
```

#### Authentication Failures

**Symptoms:**
- "Authentication failed" messages
- "Permission denied" errors

**Solutions:**
```bash
# Test credentials manually
ssh username@device-ip

# Update authgroup
configure
devices authgroups group lab-group
  default-map remote-password
  <enter new password>
commit

# Use different authentication method
devices device <device-name>
  ssh key-dir /var/nso/ssh-keys
commit
```

### 3. Synchronization Problems

#### Out of Sync Errors

**Symptoms:**
- "out-of-sync" status
- Configuration drift warnings

**Diagnosis:**
```bash
# Check sync status
devices check-sync

# Compare configurations
devices device <device-name> compare-config

# Show sync details
devices device <device-name> check-sync outformat cli
```

**Solutions:**
```bash
# Sync from device (import current config)
devices device <device-name> sync-from

# Sync to device (push NSO config)
devices device <device-name> sync-to

# Force sync
devices device <device-name> sync-from force

# Resolve conflicts
configure
devices device <device-name>
  config
  <resolve configuration conflicts>
commit
```

### 4. Service Deployment Issues

#### Service Creation Failures

**Symptoms:**
- "Service creation failed"
- "No such service point" errors

**Diagnosis:**
```bash
# Check service status
services check-sync
show services

# Validate service model
packages package <package-name> check

# Review service logs
tail -f logs/devel.log
```

**Solutions:**
```bash
# Reload packages
packages reload

# Re-deploy service
services <service-type> <instance> re-deploy

# Delete and recreate service
configure
no services <service-type> <instance>
commit
services <service-type> <instance>
  <configure service>
commit

# Dry-run to identify issues
commit dry-run outformat cli
```

#### Template Errors

**Symptoms:**
- "Template processing failed"
- Variable substitution errors

**Solutions:**
```bash
# Validate template syntax
cd packages/<package>/templates
xmllint --noout *.xml

# Check template variables
show services <service> <instance> | display xml

# Debug template processing
configure
services <service> <instance>
commit dry-run outformat native
```

### 5. Performance Issues

#### Slow Operations

**Symptoms:**
- Long response times
- Timeout errors

**Diagnosis:**
```bash
# Check system resources
top
free -h
df -h

# Monitor NSO performance
show ncs-state internal cdb operational

# Check transaction times
show configuration commit list
```

**Solutions:**
```bash
# Optimize CDB
ncs_cli -u admin
cdb compact

# Tune Java garbage collection
# Edit ncs.conf
<java-options>
  -XX:+UseG1GC
  -XX:MaxGCPauseMillis=200
  -XX:ParallelGCThreads=4
</java-options>

# Enable connection pooling
devices global-settings
  connect-timeout 30
  read-timeout 120
  write-timeout 120
commit
```

### 6. Package and NED Issues

#### Package Loading Failures

**Symptoms:**
- "Failed to load package"
- "Bad package" errors

**Diagnosis:**
```bash
# Check package status
show packages package oper-status

# Validate package structure
cd packages/<package>
make clean all

# Review package logs
tail -f logs/ncs-python-vm.log
```

**Solutions:**
```bash
# Recompile package
cd packages/<package>/src
make clean all

# Reload specific package
packages package <package> redeploy

# Reset package state
ncs_cli -u admin
packages package <package> disable
commit
packages package <package> enable
commit
```

#### NED Version Mismatches

**Symptoms:**
- "Unknown model" errors
- Commands not recognized

**Solutions:**
```bash
# Check device software version
devices device <device> live-status exec show version

# Update NED
cd /opt/nso/packages/neds
tar -xzf cisco-ios-cli-6.77.tar.gz

# Migrate to new NED
devices device <device>
  device-type cli ned-id cisco-ios-cli-6.77
  migrate
commit
```

### 7. Transaction and Rollback Issues

#### Failed Transactions

**Symptoms:**
- "Transaction failed"
- "Aborted" status

**Diagnosis:**
```bash
# Check transaction log
show configuration commit list
show configuration rollback

# Review transaction details
show configuration commit list <id> details
```

**Solutions:**
```bash
# Rollback to previous configuration
rollback configuration <rollback-id>

# Clear pending transactions
configure
abort
exit

# Fix and retry
configure
<fix issues>
validate
commit
```

### 8. CLI and Web UI Issues

#### Cannot Access Web UI

**Symptoms:**
- Browser connection refused
- 404 errors

**Solutions:**
```bash
# Check web server status
show ncs-state webui

# Restart web server
webui restart

# Check certificate issues
openssl s_client -connect localhost:8080

# Reset web UI
configure
webui disable
commit
webui enable
commit
```

#### CLI Timeout Issues

**Symptoms:**
- Session disconnects
- "Idle timeout" messages

**Solutions:**
```bash
# Increase CLI timeout
configure
cli idle-timeout 0
cli complete-on-space false
commit

# Configure SSH keepalive
ssh server alive-interval 60
ssh server alive-count-max 3
commit
```

### 9. Logging and Debugging

#### Enable Debug Logging

```bash
# Enable developer logs
configure
java-vm java-logging logger com.tailf level debug
python-vm logging level debug
commit

# Enable device trace
devices device <device-name>
  trace raw
commit

# View trace files
tail -f logs/ned-cisco-ios-cli.trace
```

#### Analyze Logs

```bash
# Common log locations
logs/ncs.log          # Main NSO log
logs/devel.log        # Developer log
logs/audit.log        # Audit trail
logs/ncs-java-vm.log  # Java VM log
logs/ncs-python-vm.log # Python VM log

# Search for errors
grep -i error logs/*.log
grep -i exception logs/*.log

# Monitor real-time
tail -f logs/*.log | grep -E "ERROR|WARN|FAIL"
```

### 10. Recovery Procedures

#### Complete NSO Reset

```bash
# Backup current configuration
ncs-backup create

# Stop NSO
ncs --stop

# Clean state
cd /var/opt/nso/<instance>
rm -rf state/* logs/*

# Restore from backup
ncs-backup restore <backup-id>

# Start NSO
ncs
```

#### Emergency Recovery

```bash
# Start in safe mode
ncs --stop
ncs --with-package-reload --ignore-initial-validation

# Fix issues in safe mode
ncs_cli -u admin
configure
<fix configuration>
commit

# Restart normally
ncs --reload
```

## Diagnostic Commands Reference

### System Status
```bash
ncs --status
ncs --version
show ncs-state version
show ncs-state internal
```

### Device Diagnostics
```bash
devices check-sync
devices check-yang
devices device * compare-config
show devices list
```

### Service Diagnostics
```bash
services check-sync
show services errors
show services plan
services validate
```

### Performance Metrics
```bash
show ncs-state internal cdb operational datastore
show ncs-state internal callpoints
show java-vm status
```

## Getting Additional Help

### Documentation
- NSO User Guide: `/opt/nso/doc/guides/`
- NED Documentation: `/opt/nso/packages/neds/*/doc/`
- API Reference: `/opt/nso/doc/api/`

### Support Resources
- Cisco DevNet: https://developer.cisco.com/docs/nso/
- NSO Community: https://community.cisco.com/t5/nso/bd-p/5676j-dev-nso
- TAC Support: https://www.cisco.com/c/en/us/support/

### Collecting Support Information

```bash
# Generate support bundle
ncs_cli -u admin
request support-package create

# Collect system information
ncs --status > nso-status.txt
show tech-support > tech-support.txt
tar -czf nso-logs.tar.gz logs/
```

## Best Practices for Problem Prevention

1. **Regular Maintenance**
   - Monitor logs daily
   - Check sync status regularly
   - Create periodic backups

2. **Configuration Management**
   - Use version control
   - Test in lab first
   - Document changes

3. **Performance Monitoring**
   - Set up alerting
   - Track resource usage
   - Monitor transaction times

4. **Security**
   - Rotate credentials
   - Review audit logs
   - Update NEDs regularly