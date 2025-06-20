#!/bin/bash
# K3S Puppet Module - Single Node Test Script
# This script tests the single node K3S deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Check system requirements
check_requirements() {
    log "Checking system requirements..."
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot determine OS version"
        exit 1
    fi
    
    source /etc/os-release
    log "Detected OS: $PRETTY_NAME"
    
    # Check systemd
    if ! command -v systemctl >/dev/null 2>&1; then
        error "systemd is required but not found"
        exit 1
    fi
    
    # Check internet connectivity
    if ! ping -c 1 google.com >/dev/null 2>&1; then
        warn "No internet connectivity detected - binary installation may be required"
    fi
    
    log "System requirements check passed"
}

# Install Puppet if not present
install_puppet() {
    if command -v puppet >/dev/null 2>&1; then
        log "Puppet already installed: $(puppet --version)"
        return 0
    fi
    
    log "Installing Puppet..."
    
    case "$ID" in
        ubuntu|debian)
            wget -q https://apt.puppet.com/puppet8-release-${VERSION_CODENAME}.deb
            dpkg -i puppet8-release-${VERSION_CODENAME}.deb
            apt-get update
            apt-get install -y puppet-agent
            ;;
        centos|rhel|fedora)
            rpm -Uvh https://yum.puppet.com/puppet8-release-el-$(rpm -E %rhel).noarch.rpm
            yum install -y puppet-agent
            ;;
        *)
            error "Unsupported OS: $ID"
            exit 1
            ;;
    esac
    
    # Add Puppet to PATH
    export PATH="/opt/puppetlabs/bin:$PATH"
    echo 'export PATH="/opt/puppetlabs/bin:$PATH"' >> /root/.bashrc
    
    log "Puppet installed successfully"
}

# Setup module for testing
setup_module() {
    log "Setting up K3S module for testing..."
    
    # Create module directory
    mkdir -p /etc/puppetlabs/code/environments/production/modules
    
    # Copy current module
    if [[ -d "$(pwd)" ]]; then
        cp -r "$(pwd)" /etc/puppetlabs/code/environments/production/modules/k3s_cluster
        log "Module copied to Puppet module path"
    else
        error "Cannot find module directory"
        exit 1
    fi
}

# Test basic single node deployment
test_basic_deployment() {
    log "Testing basic single node K3S deployment..."
    
    # Apply the configuration
    puppet apply -e "class { 'k3s_cluster': ensure => 'present' }" --detailed-exitcodes
    
    # Check if K3S service is running
    if systemctl is-active k3s >/dev/null 2>&1; then
        log "K3S service is running"
    else
        error "K3S service is not running"
        systemctl status k3s
        exit 1
    fi
    
    # Wait for K3S to be ready
    log "Waiting for K3S to be ready..."
    timeout 60 bash -c 'until k3s kubectl get nodes >/dev/null 2>&1; do sleep 2; done'
    
    # Check cluster status
    log "Checking cluster status..."
    k3s kubectl get nodes
    k3s kubectl get pods -A
    
    log "Basic deployment test passed!"
}

# Test with custom configuration
test_custom_config() {
    log "Testing custom configuration..."
    
    # Create custom config test
    cat > /tmp/k3s_custom_test.pp << 'EOF'
class { 'k3s_cluster':
  ensure => 'present',
  config_options => {
    'write-kubeconfig-mode' => '0644',
    'disable' => ['traefik'],
    'node-label' => ['environment=test', 'role=single-node'],
  },
}
EOF
    
    # Apply custom configuration
    puppet apply /tmp/k3s_custom_test.pp --detailed-exitcodes
    
    # Verify custom settings
    if k3s kubectl get nodes --show-labels | grep -q "environment=test"; then
        log "Custom node labels applied successfully"
    else
        warn "Custom node labels not found"
    fi
    
    # Check if traefik is disabled
    if ! k3s kubectl get pods -n kube-system | grep -q traefik; then
        log "Traefik successfully disabled"
    else
        warn "Traefik is still running"
    fi
    
    log "Custom configuration test passed!"
}

# Test uninstallation
test_uninstall() {
    log "Testing K3S uninstallation..."
    
    # Apply uninstall configuration
    puppet apply -e "class { 'k3s_cluster': ensure => 'absent', cleanup_containers => true }" --detailed-exitcodes
    
    # Check if service is stopped
    if ! systemctl is-active k3s >/dev/null 2>&1; then
        log "K3S service successfully stopped"
    else
        warn "K3S service is still running"
    fi
    
    # Check if binary is removed
    if [[ ! -f /usr/local/bin/k3s ]]; then
        log "K3S binary successfully removed"
    else
        warn "K3S binary still exists"
    fi
    
    log "Uninstallation test passed!"
}

# Cleanup function
cleanup() {
    log "Cleaning up test environment..."
    
    # Remove test files
    rm -f /tmp/k3s_custom_test.pp
    rm -f puppet8-release-*.deb
    
    # Stop K3S if running
    if systemctl is-active k3s >/dev/null 2>&1; then
        systemctl stop k3s
    fi
    
    log "Cleanup completed"
}

# Main test execution
main() {
    log "Starting K3S Puppet Module Single Node Test"
    log "============================================"
    
    # Setup trap for cleanup
    trap cleanup EXIT
    
    # Run tests
    check_root
    check_requirements
    install_puppet
    setup_module
    test_basic_deployment
    test_custom_config
    test_uninstall
    
    log "============================================"
    log "All tests completed successfully!"
    log "K3S Puppet module is working correctly"
}

# Run main function
main "$@" 