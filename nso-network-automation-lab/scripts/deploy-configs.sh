#!/bin/bash
# NSO Configuration Deployment Script
# Deploys configurations to NSO and syncs with devices

set -e

# Configuration Variables
NSO_USER="admin"
NSO_PASSWORD="admin"
CONFIG_DIR="../configs"
BACKUP_DIR="../backups"
LOG_FILE="../logs/deploy-$(date +%Y%m%d_%H%M%S).log"
NSO_INSTANCE_DIR="~/nso-instance"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1" >> "$LOG_FILE"
}

setup_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    log_info "Deployment started at $(date)"
}

check_nso_status() {
    log_info "Checking NSO status..."

    if ncs --status &> /dev/null; then
        log_info "NSO is running"
    else
        log_error "NSO is not running. Starting NSO..."
        ncs
        sleep 5
    fi
}

create_backup() {
    log_info "Creating configuration backup..."

    mkdir -p "$BACKUP_DIR"
    BACKUP_FILE="$BACKUP_DIR/config-backup-$(date +%Y%m%d_%H%M%S).xml"

    ncs_cli -u $NSO_USER -C << EOF > "$BACKUP_FILE"
show running-config | display xml
exit
EOF

    log_info "Backup created: $BACKUP_FILE"
}

sync_from_devices() {
    log_info "Syncing configuration from devices..."

    ncs_cli -u $NSO_USER -C << EOF | tee -a "$LOG_FILE"
devices sync-from
exit
EOF

    log_info "Device sync completed"
}

load_authgroups() {
    log_info "Loading authgroup configurations..."

    # Create labadmin authgroup
    ncs_cli -u $NSO_USER -C << EOF | tee -a "$LOG_FILE"
config
devices authgroups group labadmin
default-map remote-name cisco
default-map remote-password cisco
exit
commit
exit
EOF
    log_info "Labadmin authgroup created successfully"
}

load_device_definitions() {
    log_info "Loading device definitions..."

    # Add all lab devices
    ncs_cli -u $NSO_USER -C << 'EOF' | tee -a "$LOG_FILE"
config

! Edge Switch 01
devices device edge-sw01
address 10.10.20.172
port 23
authgroup labadmin
device-type cli ned-id cisco-ios-cli-6.91
device-type cli protocol telnet
state admin-state unlocked
exit

! Core Router 01
devices device core-rtr01
address 10.10.20.173
authgroup labadmin
device-type cli ned-id cisco-iosxr-cli-7.45
device-type cli protocol telnet
ssh host-key-verification none
state admin-state unlocked
exit

! Dev Core Router 01
devices device dev-core-rtr01
address 10.10.20.174
authgroup labadmin
device-type cli ned-id cisco-iosxr-cli-7.45
device-type cli protocol telnet
ssh host-key-verification none
state admin-state unlocked
exit

! Distribution Router 01
devices device dist-rtr01
address 10.10.20.175
authgroup labadmin
device-type cli ned-id cisco-ios-cli-6.91
device-type cli protocol telnet
ssh host-key-verification none
state admin-state unlocked
exit

! Dev Distribution Router 01
devices device dev-dist-rtr01
address 10.10.20.176
authgroup labadmin
device-type cli ned-id cisco-ios-cli-6.91
device-type cli protocol telnet
ssh host-key-verification none
state admin-state unlocked
exit

! Dev Distribution Switch 01
devices device dev-dist-sw01
address 10.10.20.178
authgroup labadmin
device-type cli ned-id cisco-nx-cli-5.23
device-type cli protocol telnet
ned-settings cisco-nx behaviours show-interface-all enable
ssh host-key-verification none
state admin-state unlocked
exit

commit
exit
EOF
    log_info "Device definitions loaded successfully"
}

load_device_groups() {
    log_info "Loading device groups..."

    ncs_cli -u $NSO_USER -C << 'EOF' | tee -a "$LOG_FILE"
config

! IOS Devices Group
devices device-group IOS-DEVICES
device-name dist-rtr01
device-name dev-dist-rtr01
device-name edge-sw01
exit

! IOS-XR Devices Group
devices device-group XR-DEVICES
device-name core-rtr01
device-name dev-core-rtr01
exit

! NX-OS Devices Group
devices device-group NXOS-DEVICES
device-name dev-dist-sw01
exit

! All Devices Group
devices device-group ALL
device-group IOS-DEVICES
device-group XR-DEVICES
device-group NXOS-DEVICES
exit

commit
exit
EOF
    log_info "Device groups loaded successfully"
}

connect_to_devices() {
    log_info "Connecting to devices..."

    # Get list of devices
    DEVICES=$(ncs_cli -u $NSO_USER -C -c "show devices list" | awk '/^[a-zA-Z]/ {print $1}' | tail -n +2)

    for device in $DEVICES; do
        log_info "Connecting to device: $device"

        ncs_cli -u $NSO_USER -C << EOF 2>&1 | tee -a "$LOG_FILE"
devices device $device connect
exit
EOF

        if [ $? -eq 0 ]; then
            log_info "Successfully connected to $device"
        else
            log_error "Failed to connect to $device"
        fi
    done
}

deploy_vlan_services() {
    log_info "Deploying VLAN services..."

    # Configure VLAN 42 on NX-OS device
    ncs_cli -u $NSO_USER -C << 'EOF' | tee -a "$LOG_FILE"
config
devices device dev-dist-sw01 config
vlan 42
name TheAnswer
exit
interface Vlan42
description "The Answer VLAN Interface"
no shutdown
ip address 10.42.42.42/24
no ip redirects
no ipv6 redirects
exit
exit
commit
exit
EOF
    log_info "VLAN 42 deployed successfully"
}

deploy_dns_services() {
    log_info "Deploying DNS services..."

    # Create and apply DNS template
    ncs_cli -u $NSO_USER -C << 'EOF' | tee -a "$LOG_FILE"
config

! Create DNS template
devices template SET-DNS-SERVER
ned-id cisco-nx-cli-5.23
config
ip name-server servers 208.67.222.222
ip name-server servers 208.67.220.220
exit
exit

commit

! Apply template to NX-OS device
devices device dev-dist-sw01 apply-template template-name SET-DNS-SERVER
commit
exit
EOF
    log_info "DNS services deployed successfully"
}

perform_dry_run() {
    log_info "Performing dry-run..."

    ncs_cli -u $NSO_USER -C << EOF | tee -a "$LOG_FILE"
config
commit dry-run
exit
EOF

    read -p "Continue with actual deployment? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "Deployment cancelled by user"
        exit 0
    fi
}

sync_to_devices() {
    log_info "Syncing configuration to devices..."

    ncs_cli -u $NSO_USER -C << EOF | tee -a "$LOG_FILE"
devices sync-to
exit
EOF

    log_info "Configuration synced to devices"
}

verify_deployment() {
    log_info "Verifying deployment..."

    # Check device sync status
    ncs_cli -u $NSO_USER -C << EOF | tee -a "$LOG_FILE"
devices check-sync
exit
EOF

    # Check service status
    ncs_cli -u $NSO_USER -C << EOF | tee -a "$LOG_FILE"
show services
exit
EOF

    log_info "Deployment verification completed"
}

generate_report() {
    log_info "Generating deployment report..."

    REPORT_FILE="$BACKUP_DIR/deployment-report-$(date +%Y%m%d_%H%M%S).txt"

    {
        echo "NSO Deployment Report"
        echo "====================="
        echo "Date: $(date)"
        echo ""
        echo "Device Status:"
        ncs_cli -u $NSO_USER -C -c "show devices list"
        echo ""
        echo "Service Status:"
        ncs_cli -u $NSO_USER -C -c "show services"
        echo ""
        echo "Sync Status:"
        ncs_cli -u $NSO_USER -C -c "devices check-sync"
    } > "$REPORT_FILE"

    log_info "Report generated: $REPORT_FILE"
}

# Main execution
main() {
    log_info "Starting NSO configuration deployment..."

    setup_logging
    check_nso_status
    create_backup

    # Load configurations
    load_authgroups
    load_device_definitions
    load_device_groups

    # Connect and sync
    connect_to_devices
    sync_from_devices

    # Deploy services
    deploy_vlan_services
    deploy_dns_services

    # Perform deployment
    perform_dry_run
    sync_to_devices

    # Verify and report
    verify_deployment
    generate_report

    log_info "Deployment completed successfully!"
}

# Handle command line arguments
case "${1:-}" in
    --dry-run)
        DRY_RUN=true
        main
        ;;
    --force)
        FORCE=true
        main
        ;;
    --help)
        echo "Usage: $0 [--dry-run|--force|--help]"
        echo "  --dry-run  : Perform dry-run only"
        echo "  --force    : Skip confirmation prompts"
        echo "  --help     : Show this help message"
        exit 0
        ;;
    *)
        main
        ;;
esac