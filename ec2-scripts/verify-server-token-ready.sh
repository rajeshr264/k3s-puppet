#!/bin/bash
# verify-server-token-ready.sh - Comprehensive K3S server token readiness verification
# Usage: ./verify-server-token-ready.sh [server_ip] [ssh_user] [ssh_key_path]

set -e

# Configuration
SERVER_IP="${1:-localhost}"
SSH_USER="${2:-ubuntu}"
SSH_KEY_PATH="${3}"
MAX_WAIT_TIME=600  # 10 minutes total wait time
CHECK_INTERVAL=10  # Check every 10 seconds

echo "🔍 K3S Server Token Readiness Verification"
echo "Server: ${SERVER_IP}"
echo "SSH User: ${SSH_USER}"
echo "Max Wait Time: ${MAX_WAIT_TIME} seconds"
echo "="*50

# Function to run SSH command
run_ssh_command() {
    local command="$1"
    if [ -n "$SSH_KEY_PATH" ]; then
        ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$SERVER_IP" "$command"
    else
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$SERVER_IP" "$command"
    fi
}

# Step 1: Verify SSH connectivity
echo "1️⃣ Verifying SSH connectivity..."
max_ssh_attempts=20
for attempt in $(seq 1 $max_ssh_attempts); do
    if run_ssh_command "echo 'SSH connection successful'" >/dev/null 2>&1; then
        echo "   ✅ SSH connection established"
        break
    fi
    
    if [ $attempt -eq $max_ssh_attempts ]; then
        echo "   ❌ SSH connection failed after $max_ssh_attempts attempts"
        exit 1
    fi
    
    echo "   ⏳ SSH not ready, waiting... (attempt $attempt/$max_ssh_attempts)"
    sleep 5
done

# Step 2: Wait for K3S service to be active
echo "2️⃣ Waiting for K3S service to be active..."
service_ready=false
max_service_attempts=30

for attempt in $(seq 1 $max_service_attempts); do
    service_status=$(run_ssh_command "sudo systemctl is-active k3s 2>/dev/null || echo 'inactive'")
    
    if [ "$service_status" = "active" ]; then
        echo "   ✅ K3S service is active"
        service_ready=true
        break
    fi
    
    echo "   ⏳ K3S service not active (status: $service_status), waiting... (attempt $attempt/$max_service_attempts)"
    sleep $CHECK_INTERVAL
done

if [ "$service_ready" != "true" ]; then
    echo "   ❌ K3S service failed to become active"
    exit 1
fi

# Step 3: Wait for node to be ready
echo "3️⃣ Waiting for node to be ready..."
node_ready=false
max_node_attempts=20

for attempt in $(seq 1 $max_node_attempts); do
    node_status=$(run_ssh_command "sudo k3s kubectl get nodes --no-headers 2>/dev/null | awk '{print \$2}' || echo 'NotReady'")
    
    if [ "$node_status" = "Ready" ]; then
        echo "   ✅ Node is ready"
        node_ready=true
        break
    fi
    
    echo "   ⏳ Node not ready (status: $node_status), waiting... (attempt $attempt/$max_node_attempts)"
    sleep 15
done

if [ "$node_ready" != "true" ]; then
    echo "   ❌ Node failed to become ready"
    exit 1
fi

# Step 4: Wait for server token to be ready and valid
echo "4️⃣ Waiting for server token to be ready and valid..."
token_ready=false
max_token_attempts=30

for attempt in $(seq 1 $max_token_attempts); do
    echo "   🔍 Checking token availability (attempt $attempt/$max_token_attempts)..."
    
    # Check if token file exists and extract it
    token_result=$(run_ssh_command '
        if [ -f /var/lib/rancher/k3s/server/node-token ]; then
            token=$(sudo cat /var/lib/rancher/k3s/server/node-token 2>/dev/null | tr -d "\n\r")
            if [ ${#token} -gt 40 ] && [[ $token =~ ^K[0-9a-f] ]]; then
                echo "VALID:$token"
            else
                echo "INVALID:$token"
            fi
        else
            echo "MISSING:"
        fi
    ')
    
    if [[ $token_result == VALID:* ]]; then
        token=${token_result#VALID:}
        echo "   ✅ Valid token found: ${token:0:15}..."
        
        # Validate token by testing authentication
        echo "   🔍 Validating token authentication..."
        auth_result=$(run_ssh_command "sudo k3s kubectl get nodes --token=\"$token\" >/dev/null 2>&1 && echo 'AUTH_SUCCESS' || echo 'AUTH_FAILED'")
        
        if [ "$auth_result" = "AUTH_SUCCESS" ]; then
            echo "   ✅ Token authentication successful"
            token_ready=true
            break
        else
            echo "   ⚠️  Token exists but authentication failed, retrying..."
        fi
    elif [[ $token_result == INVALID:* ]]; then
        invalid_token=${token_result#INVALID:}
        echo "   ⚠️  Invalid token format: ${invalid_token:0:20}... (length: ${#invalid_token})"
    else
        echo "   ⏳ Token file not found"
    fi
    
    sleep $CHECK_INTERVAL
done

if [ "$token_ready" != "true" ]; then
    echo "   ❌ Server token failed to become ready after $(($max_token_attempts * $CHECK_INTERVAL)) seconds"
    exit 1
fi

# Step 5: Verify API server accessibility
echo "5️⃣ Verifying API server accessibility..."
api_ready=false
max_api_attempts=20

for attempt in $(seq 1 $max_api_attempts); do
    # Test API server port connectivity
    port_test=$(run_ssh_command 'timeout 5 bash -c "echo >/dev/tcp/localhost/6443" 2>/dev/null && echo "PORT_OPEN" || echo "PORT_CLOSED"')
    
    if [ "$port_test" = "PORT_OPEN" ]; then
        # Test basic API functionality
        api_test=$(run_ssh_command 'sudo k3s kubectl get nodes >/dev/null 2>&1 && echo "API_READY" || echo "API_NOT_READY"')
        
        if [ "$api_test" = "API_READY" ]; then
            echo "   ✅ API server is ready and accessible"
            
            # Show cluster info
            cluster_info=$(run_ssh_command 'sudo k3s kubectl cluster-info --request-timeout=10s 2>/dev/null | head -2')
            echo "   📊 Cluster info:"
            echo "$cluster_info" | sed 's/^/     /'
            
            api_ready=true
            break
        else
            echo "   ⏳ API server port open but API not ready... (attempt $attempt/$max_api_attempts)"
        fi
    else
        echo "   ⏳ API server port not accessible... (attempt $attempt/$max_api_attempts)"
    fi
    
    sleep $CHECK_INTERVAL
done

if [ "$api_ready" != "true" ]; then
    echo "   ❌ API server failed to become ready"
    exit 1
fi

# Final verification summary
echo ""
echo "🎉 K3S Server Readiness Verification Complete!"
echo "✅ SSH connectivity: OK"
echo "✅ K3S service: Active"
echo "✅ Node status: Ready"
echo "✅ Server token: Valid and authenticated"
echo "✅ API server: Ready and accessible"
echo ""
echo "🚀 Server is ready for agent connections!"

# Output the validated token for use by calling scripts
final_token=$(run_ssh_command 'sudo cat /var/lib/rancher/k3s/server/node-token 2>/dev/null | tr -d "\n\r"')
echo "TOKEN:$final_token"

exit 0 