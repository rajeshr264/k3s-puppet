#!/bin/bash
# fix-agent-rpm-lock.sh - Fix RPM lock issues when installing K3S agents on RHEL-based systems

set -e

# Check if required parameters are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <server_ip> <token>"
    echo "Example: $0 10.0.1.100 K109d5da14fefe5dddfa1..."
    exit 1
fi

SERVER_IP="$1"
TOKEN="$2"

echo "🔧 K3S Agent Installation with RPM Lock Fix"
echo "Server: ${SERVER_IP}:6443"
echo "Token: ${TOKEN:0:10}..."
echo

# Function to check if RPM is locked
check_rpm_lock() {
    if sudo fuser /var/lib/rpm/.rpm.lock >/dev/null 2>&1; then
        return 0  # locked
    else
        return 1  # not locked
    fi
}

# Function to wait for RPM lock release
wait_for_rpm_lock() {
    echo "🔍 Checking for RPM locks..."
    timeout=300  # 5 minutes
    elapsed=0
    
    while check_rpm_lock; do
        if [ $elapsed -ge $timeout ]; then
            echo "⏰ Timeout waiting for RPM lock to be released"
            echo "🧹 Forcing cleanup of stale lock files..."
            sudo rm -f /var/lib/rpm/.rpm.lock
            sudo rm -f /var/lib/rpm/.dbenv.lock
            break
        fi
        echo "🔒 RPM database is locked, waiting... ($elapsed/$timeout seconds)"
        sleep 10
        elapsed=$((elapsed + 10))
    done
}

# Function to clean up package processes
cleanup_package_processes() {
    echo "🧹 Cleaning up any hanging package processes..."
    
    # Kill hanging package manager processes
    sudo pkill -f "yum" 2>/dev/null || true
    sudo pkill -f "dnf" 2>/dev/null || true
    sudo pkill -f "rpm" 2>/dev/null || true
    sudo pkill -f "packagekit" 2>/dev/null || true
    
    # Stop services that might interfere
    sudo systemctl stop packagekit 2>/dev/null || true
    sudo systemctl stop amazon-ssm-agent 2>/dev/null || true
    
    # Wait for processes to fully stop
    sleep 5
}

# Function to restart services
restart_services() {
    echo "🔄 Restarting system services..."
    sudo systemctl start packagekit 2>/dev/null || true
    sudo systemctl start amazon-ssm-agent 2>/dev/null || true
}

# Function to install K3S agent with retries
install_k3s_agent() {
    local max_attempts=3
    
    for attempt in $(seq 1 $max_attempts); do
        echo "🚀 K3S installation attempt $attempt/$max_attempts..."
        
        # Set environment variables for K3S installation
        export K3S_URL="https://${SERVER_IP}:6443"
        export K3S_TOKEN="${TOKEN}"
        
        if curl -sfL https://get.k3s.io | sh -; then
            echo "✅ K3S agent installed successfully on attempt $attempt"
            return 0
        else
            echo "❌ Installation attempt $attempt failed"
            
            if [ $attempt -lt $max_attempts ]; then
                echo "⏳ Retrying in 30 seconds..."
                
                # Clean up any partial installation
                sudo systemctl stop k3s-agent 2>/dev/null || true
                sudo rm -f /usr/local/bin/k3s 2>/dev/null || true
                sudo rm -f /etc/systemd/system/k3s-agent.service 2>/dev/null || true
                sudo systemctl daemon-reload 2>/dev/null || true
                
                sleep 30
                
                # Re-run cleanup before next attempt
                cleanup_package_processes
                wait_for_rpm_lock
            fi
        fi
    done
    
    echo "❌ All K3S installation attempts failed"
    return 1
}

# Function to verify installation
verify_installation() {
    echo "🔍 Verifying K3S agent installation..."
    
    # Check if service exists
    if ! sudo systemctl list-unit-files | grep -q k3s-agent; then
        echo "❌ K3S agent service not found"
        return 1
    fi
    
    # Check service status
    if sudo systemctl is-active k3s-agent >/dev/null 2>&1; then
        echo "✅ K3S agent service is active"
    else
        echo "⚠️  K3S agent service is not active, attempting to start..."
        sudo systemctl start k3s-agent
        sleep 10
        
        if sudo systemctl is-active k3s-agent >/dev/null 2>&1; then
            echo "✅ K3S agent service started successfully"
        else
            echo "❌ Failed to start K3S agent service"
            echo "📋 Service logs:"
            sudo journalctl -u k3s-agent --no-pager --lines=10
            return 1
        fi
    fi
    
    # Check if agent can reach server
    echo "🌐 Testing connectivity to K3S server..."
    if timeout 10 bash -c "echo >/dev/tcp/${SERVER_IP}/6443" 2>/dev/null; then
        echo "✅ Can reach K3S server at ${SERVER_IP}:6443"
    else
        echo "⚠️  Cannot reach K3S server at ${SERVER_IP}:6443"
        echo "This might be a network/firewall issue"
    fi
    
    return 0
}

# Main execution
main() {
    echo "🏁 Starting K3S agent installation process..."
    
    # Step 1: Wait for any existing RPM operations to complete
    wait_for_rpm_lock
    
    # Step 2: Clean up hanging processes
    cleanup_package_processes
    
    # Step 3: Install K3S agent with retries
    if install_k3s_agent; then
        # Step 4: Restart system services
        restart_services
        
        # Step 5: Verify installation
        if verify_installation; then
            echo "🎉 K3S agent installation completed successfully!"
            echo "📊 Final status:"
            sudo systemctl status k3s-agent --no-pager --lines=3
            exit 0
        else
            echo "❌ Installation verification failed"
            exit 1
        fi
    else
        restart_services
        echo "❌ K3S agent installation failed"
        exit 1
    fi
}

# Run main function
main "$@" 