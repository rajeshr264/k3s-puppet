#!/usr/bin/env ruby

require_relative 'aws_ec2_testing'

class K3sMultiNodeDebugger < AwsEc2K3sTesting
  def debug_multi_node_deployment
    puts "🔍 K3S Multi-Node Deployment Debugger"
    puts "="*50
    
    begin
      # Create temporary resources
      create_temp_resources
      
      # Launch server node first
      puts "\n1️⃣ Launching K3S Server Node (Ubuntu)..."
      server_info = launch_instance('ubuntu', 'server')
      puts "   Server Instance: #{server_info['instance_id']}"
      puts "   Server Public IP: #{server_info['public_ip']}"
      puts "   Server Private IP: #{server_info['private_ip']}"
      
      # Wait for server to be ready and get token
      puts "\n2️⃣ Waiting for K3S server to be ready..."
      server_ready = wait_for_k3s_server(server_info)
      
      if server_ready
        puts "   ✅ K3S server is ready!"
        
        # Get the server token manually
        puts "\n3️⃣ Extracting K3S server token..."
        server_token = get_server_token(server_info)
        puts "   Token: #{server_token[0..20]}..." if server_token
        
        if server_token
          # Launch agent node
          puts "\n4️⃣ Launching K3S Agent Node (RHEL)..."
          agent_info = launch_instance('rhel', 'agent')
          puts "   Agent Instance: #{agent_info['instance_id']}"
          puts "   Agent Public IP: #{agent_info['public_ip']}"
          puts "   Agent Private IP: #{agent_info['private_ip']}"
          
          # Configure agent manually with server details
          puts "\n5️⃣ Configuring agent to join server..."
          agent_joined = configure_agent_manually(agent_info, server_info, server_token)
          
          if agent_joined
            puts "   ✅ Agent configuration completed!"
            
            # Verify the cluster
            puts "\n6️⃣ Verifying multi-node cluster..."
            verify_cluster(server_info, agent_info)
          else
            puts "   ❌ Agent failed to join server"
          end
        else
          puts "   ❌ Could not extract server token"
        end
      else
        puts "   ❌ K3S server failed to start properly"
      end
      
    ensure
      puts "\n🧹 Cleaning up resources..."
      cleanup_temp_resources
    end
  end
  
  private
  
  def wait_for_k3s_server(server_info)
    puts "   Waiting for SSH connectivity..."
    max_attempts = 30
    
    # Wait for SSH
    max_attempts.times do |attempt|
      begin
        ssh_command(server_info['public_ip'], 'ubuntu', 'echo "SSH ready"')
        puts "   SSH connection established"
        break
      rescue
        sleep 10 if attempt < max_attempts - 1
      end
    end
    
    # Wait for K3S service
    puts "   Waiting for K3S service to start..."
    30.times do |attempt|
      begin
        status = ssh_command(server_info['public_ip'], 'ubuntu', 'sudo systemctl is-active k3s 2>/dev/null || echo "inactive"')
        if status.strip == "active"
          puts "   K3S service is active"
          
          # Wait for node to be ready
          puts "   Waiting for node to be ready..."
          10.times do
            node_status = ssh_command(server_info['public_ip'], 'ubuntu', 'sudo k3s kubectl get nodes --no-headers 2>/dev/null | awk \'{print $2}\' || echo "NotReady"')
            if node_status.strip == "Ready"
              puts "   Node is ready"
              return true
            end
            sleep 5
          end
        end
      rescue => e
        puts "   Attempt #{attempt + 1}: #{e.message}" if attempt % 5 == 0
      end
      sleep 10
    end
    
    false
  end
  
  def get_server_token(server_info)
    begin
      # Get the node token from the server
      token = ssh_command(server_info['public_ip'], 'ubuntu', 'sudo cat /var/lib/rancher/k3s/server/node-token 2>/dev/null || echo "NOT_FOUND"')
      return token.strip if token.strip != "NOT_FOUND" && !token.strip.empty?
      
      # Alternative: try to get from kubeconfig
      puts "   Trying alternative token extraction..."
      alt_token = ssh_command(server_info['public_ip'], 'ubuntu', 'sudo k3s kubectl config view --raw -o jsonpath="{.users[0].user.token}" 2>/dev/null || echo "NOT_FOUND"')
      return alt_token.strip if alt_token.strip != "NOT_FOUND" && !alt_token.strip.empty?
      
    rescue => e
      puts "   Error getting token: #{e.message}"
    end
    
    nil
  end
  
  def configure_agent_manually(agent_info, server_info, token)
    user = LATEST_AMIS['rhel']['user']
    
    puts "   Installing K3S agent manually..."
    
    # Create K3S agent installation script with RPM lock handling
    agent_script = <<~SCRIPT
      #!/bin/bash
      set -e
      
      echo "Installing K3S agent..."
      echo "Server: #{server_info['private_ip']}:6443"
      echo "Token: #{token[0..10]}..."
      
      # Function to check if RPM is locked
      check_rpm_lock() {
          if sudo fuser /var/lib/rpm/.rpm.lock >/dev/null 2>&1; then
              return 0  # locked
          else
              return 1  # not locked
          fi
      }
      
      # Wait for RPM lock to be released
      echo "Checking for RPM locks..."
      timeout=300  # 5 minutes
      elapsed=0
      while check_rpm_lock; do
          if [ $elapsed -ge $timeout ]; then
              echo "Timeout waiting for RPM lock to be released, forcing cleanup"
              sudo rm -f /var/lib/rpm/.rpm.lock
              break
          fi
          echo "RPM database is locked, waiting... ($elapsed/$timeout seconds)"
          sleep 10
          elapsed=$((elapsed + 10))
      done
      
      # Kill any hanging package processes
      echo "Cleaning up any hanging package processes..."
      sudo pkill -f "yum\\|dnf\\|rpm" 2>/dev/null || true
      
      # Stop SSM agent if present to avoid conflicts
      sudo systemctl stop amazon-ssm-agent 2>/dev/null || true
      
      # Wait a bit more for processes to fully stop
      sleep 5
      
      # Install K3S with retries
      for attempt in {1..3}; do
          echo "K3S installation attempt $attempt..."
          
          if curl -sfL https://get.k3s.io | K3S_URL=https://#{server_info['private_ip']}:6443 K3S_TOKEN=#{token} sh -; then
              echo "✅ K3S agent installed successfully"
              
              # Restart SSM agent
              sudo systemctl start amazon-ssm-agent 2>/dev/null || true
              
              # Wait for service to be active
              sleep 10
              sudo systemctl is-active k3s-agent
              
              echo "K3S agent installation completed successfully"
              exit 0
          else
              echo "❌ Installation attempt $attempt failed"
              if [ $attempt -lt 3 ]; then
                  echo "Retrying in 30 seconds..."
                  sleep 30
                  
                  # Clean up any partial installation
                  sudo systemctl stop k3s-agent 2>/dev/null || true
                  sudo rm -f /usr/local/bin/k3s 2>/dev/null || true
              fi
          fi
      done
      
      echo "❌ All K3S installation attempts failed"
      exit 1
    SCRIPT
    
    begin
      # Upload and run the script
      ssh_command(agent_info['public_ip'], user, "echo '#{agent_script}' > /tmp/install_k3s_agent.sh")
      ssh_command(agent_info['public_ip'], user, "chmod +x /tmp/install_k3s_agent.sh")
      result = ssh_command(agent_info['public_ip'], user, "sudo /tmp/install_k3s_agent.sh")
      
      puts "   Agent installation output:"
      puts result.split("\n").map { |line| "     #{line}" }.join("\n")
      
      # Verify agent service
      agent_status = ssh_command(agent_info['public_ip'], user, 'sudo systemctl is-active k3s-agent 2>/dev/null || echo "inactive"')
      return agent_status.strip == "active"
      
    rescue => e
      puts "   Error configuring agent: #{e.message}"
      
      # Try to get more detailed error information
      begin
        error_logs = ssh_command(agent_info['public_ip'], user, 'sudo journalctl -u k3s-agent --no-pager --lines=10 | tail -5 || echo "No logs available"')
        puts "   Agent error logs:"
        puts error_logs.split("\n").map { |line| "     #{line}" }.join("\n")
      rescue
        puts "   Could not retrieve error logs"
      end
      
      return false
    end
  end
  
  def verify_cluster(server_info, agent_info)
    puts "   Checking cluster nodes from server..."
    
    begin
      # Get nodes from server
      nodes_output = ssh_command(server_info['public_ip'], 'ubuntu', 'sudo k3s kubectl get nodes -o wide')
      puts "   Cluster nodes:"
      puts nodes_output.split("\n").map { |line| "     #{line}" }.join("\n")
      
      # Count nodes
      node_count = ssh_command(server_info['public_ip'], 'ubuntu', 'sudo k3s kubectl get nodes --no-headers | wc -l').strip.to_i
      
      if node_count >= 2
        puts "   ✅ Multi-node cluster verified! #{node_count} nodes found."
        
        # Show cluster info
        cluster_info = ssh_command(server_info['public_ip'], 'ubuntu', 'sudo k3s kubectl cluster-info')
        puts "   Cluster info:"
        puts cluster_info.split("\n").map { |line| "     #{line}" }.join("\n")
        
        return true
      else
        puts "   ❌ Only #{node_count} node(s) found. Agent may not have joined successfully."
        
        # Debug agent status
        puts "   Checking agent status..."
        agent_user = LATEST_AMIS['rhel']['user']
        agent_logs = ssh_command(agent_info['public_ip'], agent_user, 'sudo journalctl -u k3s-agent --no-pager --lines=10 | tail -5')
        puts "   Agent logs:"
        puts agent_logs.split("\n").map { |line| "     #{line}" }.join("\n")
        
        return false
      end
      
    rescue => e
      puts "   Error verifying cluster: #{e.message}"
      return false
    end
  end
end

# Run the debugger
if __FILE__ == $0
  debugger = K3sMultiNodeDebugger.new
  debugger.debug_multi_node_deployment
end
