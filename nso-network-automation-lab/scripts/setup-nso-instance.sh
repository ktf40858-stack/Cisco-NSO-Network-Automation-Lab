#!/bin/bash
# NSO Instance Setup Script
# Sets up and initializes a new NSO instance

set -e

# Configuration Variables
NSO_VERSION="5.7"
NSO_HOME="~/nso"
NSO_INSTANCE_DIR="~/nso-instance"
NSO_PORT="8080"
NED_DIR="~/nso/packages/neds"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if NSO is installed
    if ! command -v ncs &> /dev/null; then
        log_error "NSO is not installed. Please install NSO first."
        exit 1
    fi

    # Check Java
    if ! command -v java &> /dev/null; then
        log_error "Java is not installed. Please install Java 8 or later."
        exit 1
    fi

    # Check Python
    if ! command -v python3 &> /dev/null; then
        log_warning "Python 3 is not installed. Some features may not work."
    fi

    log_info "Prerequisites check completed."
}

create_nso_instance() {
    log_info "Creating NSO instance with lab NEDs"

    # Backup existing instance if present
    if [ -d "$NSO_INSTANCE_DIR" ]; then
        log_warning "Instance directory already exists. Backing up..."
        mv "$NSO_INSTANCE_DIR" "${NSO_INSTANCE_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    fi

    # Create new instance with all required NEDs
    log_info "Setting up NSO instance with lab NEDs..."
    cd "$NSO_HOME"
    ncs-setup \
        --package packages/neds/a10-acos-cli-3.0 \
        --package packages/neds/alu-sr-cli-3.4 \
        --package packages/neds/cisco-asa-cli-6.6 \
        --package packages/neds/cisco-asa-cli-6.18 \
        --package packages/neds/cisco-ios-cli-3.0 \
        --package packages/neds/cisco-ios-cli-3.8 \
        --package packages/neds/cisco-ios-cli-6.91 \
        --package packages/neds/cisco-iosxr-cli-3.0 \
        --package packages/neds/cisco-iosxr-cli-3.5 \
        --package packages/neds/cisco-iosxr-cli-7.45 \
        --package packages/neds/cisco-nx-cli-3.0 \
        --package packages/neds/cisco-nx-cli-5.23 \
        --package packages/neds/dell-ftos-cli-3.0 \
        --package packages/neds/juniper-junos-nc-3.0 \
        --dest "$NSO_INSTANCE_DIR"

    log_info "NSO instance created at: $NSO_INSTANCE_DIR"
}

configure_nso_instance() {
    log_info "Configuring NSO instance..."

    cd "$NSO_INSTANCE_DIR"

    # Update ncs.conf for web UI port
    sed -i "s/<port>8080<\/port>/<port>$NSO_PORT<\/port>/g" ncs.conf

    # Enable SSH for CLI access
    cat >> ncs.conf << EOF

    <ssh>
      <enabled>true</enabled>
      <ip>0.0.0.0</ip>
      <port>2024</port>
    </ssh>
EOF

    # Configure logging
    cat >> ncs.conf << EOF

    <developer-log>
      <enabled>true</enabled>
      <level>trace</level>
    </developer-log>
EOF

    log_info "Configuration completed."
}

load_initial_config() {
    log_info "Loading initial configuration..."

    cd "$NSO_INSTANCE_DIR"

    # Start NSO
    ncs

    # Wait for NSO to start
    sleep 5

    # Load lab configuration
    log_info "Creating labadmin authgroup..."
    ncs_cli -u admin -C << EOF
config
devices authgroups group labadmin
default-map remote-name cisco
default-map remote-password cisco
exit
commit
exit
EOF

    log_info "Initial configuration loaded."
}

create_admin_user() {
    log_info "Configuring admin user..."

    ncs_cli -u admin -C << EOF
config
aaa authentication users user admin
password admin
ssh-keydir ~/nso/ssh-keys
homedir ~/nso
uid 1000
gid 1000
commit
exit
EOF

    log_info "Admin user configured"
}

setup_packages() {
    log_info "Setting up packages..."

    cd "$NSO_INSTANCE_DIR"

    # Compile packages
    make all

    # Reload packages
    ncs_cli -u admin -C << EOF
packages reload
exit
EOF

    log_info "Packages setup completed."
}

verify_installation() {
    log_info "Verifying installation..."

    # Check NSO status
    if ncs --status &> /dev/null; then
        log_info "NSO is running"
    else
        log_error "NSO is not running"
        return 1
    fi

    # Check web UI
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:$NSO_PORT | grep -q "200\|302"; then
        log_info "Web UI is accessible at http://localhost:$NSO_PORT"
    else
        log_warning "Web UI might not be accessible"
    fi

    # List devices
    log_info "Configured devices:"
    ncs_cli -u admin -C << EOF
show devices list
exit
EOF

    log_info "Installation verification completed."
}

# Main execution
main() {
    log_info "Starting NSO instance setup..."

    check_prerequisites
    create_nso_instance
    configure_nso_instance
    load_initial_config
    create_admin_user
    setup_packages
    verify_installation

    log_info "NSO instance setup completed successfully!"
    log_info "Access NSO at:"
    log_info "  Web UI: http://localhost:$NSO_PORT"
    log_info "  SSH CLI: ssh admin@localhost -p 2024"
    log_info "  CLI: ncs_cli -u admin -C"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Add devices using: ./deploy-configs.sh"
    log_info "  2. Sync from devices: devices sync-from"
    log_info "  3. Deploy services: commit dry-run"
}

# Run main function
main "$@"