#!/usr/bin/env ruby
# Debug script for K3S installation issues
# This script will help identify what's going wrong with the K3S deployment

require_relative 'aws_ec2_testing'
require 'json'

class K3sDebugger < AwsEc2K3sTesting
  def debug_k3s_installation
    puts "🔍 Starting K3S Installation Debug Session"
    puts "=" * 60
    
    begin
      # Create temporary resources
      puts "\n📋 Creating temporary AWS resources..."
      create_temp_resources
      
      # Launch a single Ubuntu instance for debugging
      puts "\n🚀 Launching debug Ubuntu instance..."
      instance_info = launch_instance('ubuntu', 'single')
      
      puts "\n🔗 Instance Details:"
      puts "  Instance ID: #{instance_info['instance_id']}"
      puts "  Public IP: #{instance_info['public_ip']}"
      puts "  OS: #{instance_info['os']}"
      puts "  User: #{instance_info['ami_config']['user']}"
      
      # Wait for SSH to be available
      puts "\n⏳ Waiting for SSH connectivity..."
      wait_for_ssh(instance_info)
      
      # Debug the installation process step by step
      puts "\n🔧 Starting step-by-step debugging..."
      debug_installation_steps(instance_info)
      
    ensure
      puts "\n🧹 Cleaning up resources..."
      cleanup_temp_resources
    end
  end
  
  def wait_for_ssh(instance_info)
    public_ip = instance_info['public_ip']
    user = instance_info['ami_config']['user']
    max_attempts = 30
    attempt = 0
    
    loop do
      attempt += 1
      
      begin
        result = ssh_command(public_ip, user, 'echo "SSH Ready"')
        puts "✅ SSH connection established"
        break
      rescue => e
        if attempt >= max_attempts
          puts "❌ SSH connection failed after #{max_attempts} attempts"
          raise e
        end
        puts "⏳ SSH attempt #{attempt}/#{max_attempts} - retrying in 10 seconds..."
        sleep 10
      end
    end
  end
  
  def debug_installation_steps(instance_info)
    public_ip = instance_info['public_ip']
    user = instance_info['ami_config']['user']
    
    steps = [
      {
        name: "Check System Info",
        command: "uname -a && lsb_release -a && whoami"
      },
      {
        name: "Check Internet Connectivity",
        command: "ping -c 3 google.com && curl -I https://get.k3s.io"
      },
      {
        name: "Check User Data Execution",
        command: "sudo cat /var/log/cloud-init-output.log | tail -50"
      },
      {
        name: "Check Cloud Init Status",
        command: "cloud-init status --wait || echo 'Cloud-init not finished'"
      },
      {
        name: "Check if Puppet is Installed",
        command: "which puppet || echo 'Puppet not found'"
      },
      {
        name: "Check Puppet Version",
        command: "puppet --version || echo 'Puppet not working'"
      },
      {
        name: "Check if K3S is Installed",
        command: "which k3s || echo 'K3S not found'"
      },
      {
        name: "Check K3S Service Status",
        command: "sudo systemctl status k3s || echo 'K3S service not found'"
      },
      {
        name: "Check K3S Logs",
        command: "sudo journalctl -u k3s --no-pager -n 20 || echo 'No K3S logs'"
      },
      {
        name: "Check Test Completion Marker",
        command: "ls -la /tmp/k3s_test_complete || echo 'Test marker not found'"
      },
      {
        name: "Check Running Processes",
        command: "ps aux | grep -E '(puppet|k3s)' | grep -v grep"
      }
    ]
    
    steps.each_with_index do |step, index|
      puts "\n#{index + 1}. 🔍 #{step[:name]}"
      puts "-" * 40
      
      begin
        result = ssh_command(public_ip, user, step[:command])
        puts result
      rescue => e
        puts "❌ Error: #{e.message}"
      end
      
      sleep 2  # Brief pause between steps
    end
    
    # Try to manually install K3S to see what happens
    puts "\n🛠️  Manual K3S Installation Test"
    puts "=" * 40
    
    manual_install_commands = [
      "curl -sfL https://get.k3s.io | sh -",
      "sudo systemctl status k3s",
      "sudo k3s kubectl get nodes"
    ]
    
    manual_install_commands.each do |cmd|
      puts "\n▶️  Running: #{cmd}"
      begin
        result = ssh_command(public_ip, user, cmd)
        puts result
      rescue => e
        puts "❌ Error: #{e.message}"
      end
      sleep 5
    end
  end
  
  # Override the user data generation to create a simpler, more debuggable version
  def generate_user_data_script(os, deployment_type)
    ami_config = LATEST_AMIS[os]
    
    script = "#!/bin/bash\n"
    script += "set -e\n"
    script += "exec > >(tee /var/log/k3s-debug.log) 2>&1\n\n"
    script += "# K3S Debug Installation Script\n"
    script += "# OS: #{ami_config['name']}\n"
    script += "# Deployment Type: #{deployment_type}\n\n"
    
    script += "echo '=== Starting K3S Debug Installation ===' \n"
    script += "date\n\n"
    
    # Update system first
    script += "echo '=== Updating System ==='\n"
    script += "apt-get update\n"
    script += "apt-get install -y curl wget\n\n"
    
    # Try direct K3S installation without Puppet first
    script += "echo '=== Installing K3S Directly ==='\n"
    script += "curl -sfL https://get.k3s.io | sh -\n\n"
    
    script += "echo '=== Checking K3S Status ==='\n"
    script += "systemctl status k3s || true\n"
    script += "systemctl is-active k3s || true\n\n"
    
    script += "echo '=== Testing K3S ==='\n"
    script += "k3s --version || true\n"
    script += "k3s kubectl get nodes || true\n\n"
    
    # Create completion marker
    script += "echo '=== Creating Completion Marker ==='\n"
    script += "if systemctl is-active --quiet k3s; then\n"
    script += "  echo 'K3S installation completed successfully' > /tmp/k3s_test_complete\n"
    script += "  echo 'Service Status: active' >> /tmp/k3s_test_complete\n"
    script += "  k3s --version >> /tmp/k3s_test_complete\n"
    script += "else\n"
    script += "  echo 'K3S installation failed' > /tmp/k3s_test_complete\n"
    script += "  echo 'Service Status: failed' >> /tmp/k3s_test_complete\n"
    script += "  systemctl status k3s >> /tmp/k3s_test_complete\n"
    script += "fi\n\n"
    
    script += "echo '=== Debug Installation Complete ==='\n"
    script += "date\n"
    
    script
  end
end

# Run the debugger
if __FILE__ == $0
  debugger = K3sDebugger.new
  debugger.debug_k3s_installation
end 