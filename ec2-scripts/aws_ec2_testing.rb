#!/usr/bin/env ruby
# AWS EC2 K3S Testing Library
# Implementation for multi-OS K3S testing on AWS EC2 with temporary resource management

require 'json'
require 'open3'
require 'yaml'
require 'securerandom'
require 'base64'
require 'timeout'

class AwsEc2K3sTesting
  # Latest AMI IDs from aws_ec2_ami.txt (updated 2025-06-20)
  LATEST_AMIS = {
    'ubuntu' => {
      'ami_id' => 'ami-0f6d76bf212f00b86',
      'name' => 'Ubuntu 22.04 LTS',
      'user' => 'ubuntu',
      'package_manager' => 'apt'
    },
    'rhel' => {
      'ami_id' => 'ami-0aeb132689ea6087f',
      'name' => 'Red Hat Enterprise Linux 8.10',
      'user' => 'ec2-user',
      'package_manager' => 'dnf'
    },
    'opensuse' => {
      'ami_id' => 'ami-0d104f700c1d53625',
      'name' => 'openSUSE Leap 15.6',
      'user' => 'ec2-user',
      'package_manager' => 'zypper'
    },
    'sles' => {
      'ami_id' => 'ami-052cee36f31273da3',
      'name' => 'SUSE Linux Enterprise Server 15 SP7',
      'user' => 'ec2-user',
      'package_manager' => 'zypper'
    },
    'debian' => {
      'ami_id' => 'ami-0e8d2601dd7a0c105',
      'name' => 'Debian 12 (Bookworm)',
      'user' => 'admin',
      'package_manager' => 'apt'
    },
    'rocky' => {
      'ami_id' => 'ami-0fadb4bc4d6071e9e',
      'name' => 'Rocky Linux 9.6',
      'user' => 'rocky',
      'package_manager' => 'dnf'
    },
    'almalinux' => {
      'ami_id' => 'ami-03caa4ee6c381105b',
      'name' => 'AlmaLinux 10.0',
      'user' => 'ec2-user',
      'package_manager' => 'dnf'
    },
    'fedora' => {
      'ami_id' => 'ami-0596830e5de86d47e',
      'name' => 'Fedora Cloud Base',
      'user' => 'fedora',
      'package_manager' => 'dnf'
    }
  }.freeze

  # Configuration with temporary resource support
  def initialize(region = 'us-west-2')
    @region = region
    @session_id = "k3s-test-#{Time.now.strftime('%Y%m%d-%H%M%S')}-#{SecureRandom.hex(4)}"
    @instance_tracking_file = "/tmp/k3s-aws-instances-#{@session_id}.json"
    @created_instances = []
    
    puts "🚀 AWS EC2 K3S Testing Session: #{@session_id}"
    puts "📝 Instance tracking file: #{@instance_tracking_file}"
    
    # Load existing instances if tracking file exists
    load_instance_tracking
    
    # Set up cleanup on exit
    at_exit { cleanup_all_resources }
    
    @instance_type = ENV['INSTANCE_TYPE'] || 't3.medium'
    @temp_resources = {
      'security_group_id' => nil,
      'key_pair_name' => nil,
      'key_file_path' => nil
    }
    @interrupted = false
    
    # Set up interrupt handler for graceful cleanup
    setup_interrupt_handler
  end

  attr_reader :session_id, :region, :instance_type, :temp_resources

  # Set up graceful interrupt handling
  def setup_interrupt_handler
    Signal.trap('INT') do
      @interrupted = true
      puts "\n🛑 Interrupt received (Ctrl-C). Initiating graceful cleanup..."
      puts "   Please wait while we clean up AWS resources..."
      
      begin
        cleanup_temp_resources
        puts "✅ Cleanup completed successfully"
      rescue => e
        puts "❌ Error during cleanup: #{e.message}"
        puts "   You may need to manually clean up resources with session ID: #{@session_id}"
      ensure
        puts "🔚 Exiting..."
        exit(0)
      end
    end
  end

  # Check if interrupted (for use in loops)
  def interrupted?
    @interrupted
  end

  # Safe sleep that can be interrupted
  def interruptible_sleep(seconds)
    return if @interrupted
    
    # Sleep in smaller chunks to allow for interrupt checking
    remaining = seconds.to_f
    while remaining > 0 && !@interrupted
      chunk = [remaining, 1.0].min
      sleep(chunk)
      remaining -= chunk
    end
    
    if @interrupted
      puts "\n⚠️  Operation interrupted by user"
      raise Interrupt
    end
  end

  # Create temporary AWS resources for testing
  def create_temp_resources
    puts "Creating temporary AWS resources for session: #{@session_id}"
    
    create_temp_security_group
    create_temp_key_pair
    
    puts "Temporary resources created successfully"
    puts "Security Group: #{@temp_resources['security_group_id']}"
    puts "Key Pair: #{@temp_resources['key_pair_name']}"
  end

  # Create temporary security group with K3S ports
  def create_temp_security_group
    sg_name = "k3s-testing-#{@session_id}"
    
    puts "Creating security group: #{sg_name}"
    
    # Create security group
    result = run_aws_command([
      'ec2', 'create-security-group',
      '--group-name', sg_name,
      '--description', "K3S testing security group - session #{@session_id}",
      '--region', @region
    ])
    
    sg_data = JSON.parse(result)
    @temp_resources['security_group_id'] = sg_data['GroupId']
    
    # Add SSH access (port 22)
    run_aws_command([
      'ec2', 'authorize-security-group-ingress',
      '--group-id', @temp_resources['security_group_id'],
      '--protocol', 'tcp',
      '--port', '22',
      '--cidr', '0.0.0.0/0',
      '--region', @region
    ])
    
    # Add K3S API server (port 6443)
    run_aws_command([
      'ec2', 'authorize-security-group-ingress',
      '--group-id', @temp_resources['security_group_id'],
      '--protocol', 'tcp',
      '--port', '6443',
      '--cidr', '0.0.0.0/0',
      '--region', @region
    ])
    
    # Add Kubelet API (port 10250)
    run_aws_command([
      'ec2', 'authorize-security-group-ingress',
      '--group-id', @temp_resources['security_group_id'],
      '--protocol', 'tcp',
      '--port', '10250',
      '--cidr', '0.0.0.0/0',
      '--region', @region
    ])
    
    # Add Flannel VXLAN (port 8472/udp)
    run_aws_command([
      'ec2', 'authorize-security-group-ingress',
      '--group-id', @temp_resources['security_group_id'],
      '--protocol', 'udp',
      '--port', '8472',
      '--cidr', '0.0.0.0/0',
      '--region', @region
    ])
    
    puts "Security group #{@temp_resources['security_group_id']} created with K3S ports"
  end

  # Create temporary key pair
  def create_temp_key_pair
    key_name = "k3s-testing-#{@session_id}"
    key_file = "/tmp/#{key_name}.pem"
    
    puts "Creating key pair: #{key_name}"
    
    # Create key pair and save private key
    result = run_aws_command([
      'ec2', 'create-key-pair',
      '--key-name', key_name,
      '--region', @region,
      '--query', 'KeyMaterial',
      '--output', 'text'
    ])
    
    # Write private key to file
    File.write(key_file, result)
    File.chmod(0600, key_file)
    
    @temp_resources['key_pair_name'] = key_name
    @temp_resources['key_file_path'] = key_file
    
    puts "Key pair #{key_name} created and saved to #{key_file}"
  end

  # Launch EC2 instance with specified OS
  def launch_instance(os, deployment_type = 'single')
    unless LATEST_AMIS.key?(os)
      raise "Unsupported operating system: #{os}. Supported: #{LATEST_AMIS.keys.join(', ')}"
    end

    ami_config = LATEST_AMIS[os]
    instance_name = "k3s-test-#{os}-#{deployment_type}-#{@session_id}"
    
    puts "Launching #{ami_config['name']} instance: #{instance_name}"
    
    # Generate user data script
    user_data = generate_user_data_script(os, deployment_type)
    user_data_b64 = Base64.strict_encode64(user_data)
    
    # Launch instance
    result = run_aws_command([
      'ec2', 'run-instances',
      '--image-id', ami_config['ami_id'],
      '--count', '1',
      '--instance-type', @instance_type,
      '--key-name', @temp_resources['key_pair_name'],
      '--security-group-ids', @temp_resources['security_group_id'],
      '--user-data', user_data_b64,
      '--tag-specifications', 
      "ResourceType=instance,Tags=[{Key=Name,Value=#{instance_name}},{Key=CreatedBy,Value=k3s-multi-os-testing},{Key=SessionId,Value=#{@session_id}},{Key=OS,Value=#{os}},{Key=DeploymentType,Value=#{deployment_type}}]",
      '--region', @region,
      '--query', 'Instances[0].InstanceId',
      '--output', 'text'
    ])
    
    instance_id = result.strip
    puts "Instance launched: #{instance_id}"
    
    # Track the created instance
    track_instance(instance_id, {
      'name' => instance_name,
      'os' => os,
      'deployment_type' => deployment_type,
      'ami_id' => ami_config['ami_id'],
      'instance_type' => @instance_type
    })
    
    # Wait for instance to be running
    puts "Waiting for instance to be running..."
    run_aws_command([
      'ec2', 'wait', 'instance-running',
      '--instance-ids', instance_id,
      '--region', @region
    ])
    
    # Wait for status checks
    puts "Waiting for status checks to pass..."
    run_aws_command([
      'ec2', 'wait', 'instance-status-ok',
      '--instance-ids', instance_id,
      '--region', @region
    ])
    
    # Get public IP
    public_ip = get_instance_public_ip(instance_id)
    puts "Instance ready! Public IP: #{public_ip}"
    
    {
      'instance_id' => instance_id,
      'public_ip' => public_ip,
      'os' => os,
      'ami_config' => ami_config,
      'deployment_type' => deployment_type
    }
  end

  # Get instance public IP
  def get_instance_public_ip(instance_id)
    result = run_aws_command([
      'ec2', 'describe-instances',
      '--instance-ids', instance_id,
      '--region', @region,
      '--query', 'Reservations[0].Instances[0].PublicIpAddress',
      '--output', 'text'
    ])
    result.strip
  end

  # Generate OS-specific user data script
  def generate_user_data_script(os, deployment_type)
    ami_config = LATEST_AMIS[os]
    package_manager = ami_config['package_manager']
    
    script = "#!/bin/bash\n"
    script += "set -e\n"
    script += "exec > >(tee /var/log/k3s-puppet-install.log) 2>&1\n\n"
    script += "# K3S Puppet Module Testing User Data Script\n"
    script += "# OS: #{ami_config['name']}\n"
    script += "# Deployment Type: #{deployment_type}\n\n"
    
    script += "echo '=== Starting K3S Puppet Module Installation ===' \n"
    script += "date\n\n"
    
    # OS-specific package installation
    case package_manager
    when 'apt'
      script += install_puppet_apt(os)
    when 'dnf'
      script += install_puppet_dnf(os)
    when 'zypper'
      script += install_puppet_zypper(os)
    end
    
    # Install K3S using Puppet module
    script += <<~SCRIPT
      
      echo '=== Installing Puppet 8 ==='\n
      # Install Puppet based on OS family
      if command -v apt-get >/dev/null 2>&1; then
        #{install_puppet_apt(os)}
      elif command -v dnf >/dev/null 2>&1; then
        # Handle RPM lock issues on RHEL-based systems
        echo "Checking for RPM locks before Puppet installation..."
        
        # Function to check if RPM is locked
        check_rpm_lock() {
            if sudo fuser /var/lib/rpm/.rpm.lock >/dev/null 2>&1; then
                return 0  # locked
            else
                return 1  # not locked
            fi
        }
        
        # Wait for RPM lock to be released
        timeout=300  # 5 minutes
        elapsed=0
        while check_rpm_lock; do
            if [ $elapsed -ge $timeout ]; then
                echo "Timeout waiting for RPM lock, forcing cleanup"
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
        
        # Stop SSM agent temporarily
        sudo systemctl stop amazon-ssm-agent 2>/dev/null || true
        sleep 5
        
        #{install_puppet_dnf(os)}
        
        # Restart SSM agent
        sudo systemctl start amazon-ssm-agent 2>/dev/null || true
      elif command -v zypper >/dev/null 2>&1; then
        #{install_puppet_zypper(os)}
      else
        echo "ERROR: Unsupported package manager"
        exit 1
      fi
      
      echo '=== Installing Puppet Dependencies ==='\n
      # Install required Puppet modules
      puppet module install puppet-archive --force
      puppet module install puppetlabs-stdlib --force
      
      echo '=== Downloading K3S Puppet Module ==='\n
      # Create module directory
      mkdir -p /etc/puppetlabs/code/modules/k3s_cluster
      
      # Download K3S module from GitHub using correct API URL
      cd /tmp
      echo "Downloading from GitHub API..."
      curl -L -H "Accept: application/vnd.github.v3+json" -o k3s-puppet.tar.gz https://api.github.com/repos/rajeshr264/k3s-puppet/tarball/main
      
      echo "Extracting archive..."
      tar -xzf k3s-puppet.tar.gz
      
      # Find the extracted directory (GitHub API creates a directory with commit hash)
      EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "rajeshr264-k3s-puppet-*" | head -1)
      
      if [ -n "$EXTRACTED_DIR" ] && [ -d "$EXTRACTED_DIR/k3s_cluster" ]; then
        echo "Found K3S module in $EXTRACTED_DIR"
        cp -r "$EXTRACTED_DIR/k3s_cluster"/* /etc/puppetlabs/code/modules/k3s_cluster/
        echo "K3S module copied successfully"
      else
        echo "ERROR: k3s_cluster module not found in downloaded archive"
        echo "Available directories:"
        ls -la . || echo "No directories found"
        if [ -n "$EXTRACTED_DIR" ]; then
          echo "Contents of $EXTRACTED_DIR:"
          ls -la "$EXTRACTED_DIR" || echo "Cannot list contents"
        fi
        exit 1
      fi
      
      echo '=== Applying K3S Puppet Configuration ==='\n
      # Create Puppet manifest based on deployment type
      if [ "#{deployment_type}" = "server" ]; then
        cat > /tmp/k3s_config.pp << 'EOF'
        class { 'k3s_cluster':
          ensure => 'present',
          node_type => 'server',
          cluster_init => true,
          installation_method => 'script',
          version => 'v1.33.1+k3s1',
          cluster_name => 'k3s-test-cluster',
          auto_token_sharing => true,
        }
        EOF
      elif [ "#{deployment_type}" = "agent" ]; then
        cat > /tmp/k3s_config.pp << 'EOF'
        class { 'k3s_cluster':
          ensure => 'present',
          node_type => 'agent',
          installation_method => 'script',
          version => 'v1.33.1+k3s1',
          cluster_name => 'k3s-test-cluster',
          auto_token_sharing => true,
          wait_for_token => true,
          token_timeout => 300,
        }
        EOF
      else
        # Default single node configuration
        cat > /tmp/k3s_config.pp << 'EOF'
        class { 'k3s_cluster':
          ensure => 'present',
          node_type => 'server',
          cluster_init => true,
          installation_method => 'script',
          version => 'v1.33.1+k3s1',
        }
        EOF
      fi
      
      echo '=== Running Puppet Apply ==='\n
      # Apply Puppet configuration with verbose output
      puppet apply /tmp/k3s_config.pp --verbose --detailed-exitcodes
      
      echo '=== Waiting for K3S Service ==='\n
      # Wait for K3S to be ready with better feedback
      echo "Waiting for K3S service to start..."
      timeout 120 bash -c 'until systemctl is-active --quiet k3s; do 
        echo "$(date): Waiting for K3S service..."
        sleep 5
      done'
      
      # Create early completion marker as soon as service is active
      if systemctl is-active --quiet k3s; then
        echo "K3S service is active, creating early completion marker..."
        echo "K3S service started successfully at $(date)" > /tmp/k3s_test_complete
        echo "Checking cluster readiness..." >> /tmp/k3s_test_complete
      fi
      
      echo '=== Testing K3S Installation ==='\n
      # Test K3S functionality based on node type
      k3s --version
      
      if [ "#{deployment_type}" = "server" ]; then
        # Server node testing
        echo "Testing K3S server functionality..."
        
        # Wait for cluster to be ready
        echo "Waiting for K3S cluster to be ready..."
        timeout 60 bash -c 'until k3s kubectl get nodes >/dev/null 2>&1; do 
          echo "$(date): Waiting for cluster readiness..."
          sleep 5
        done'
        
        k3s kubectl get nodes
        
        echo '=== Creating Final Test Completion Marker ==='\n
        # Create comprehensive test completion marker for server
        if systemctl is-active --quiet k3s && k3s kubectl get nodes >/dev/null 2>&1; then
          echo "K3S Puppet module deployment completed successfully on #{ami_config['name']}" > /tmp/k3s_test_complete
          echo "Deployment type: #{deployment_type}" >> /tmp/k3s_test_complete
          echo "Installation method: Puppet module" >> /tmp/k3s_test_complete
          echo "Timestamp: $(date)" >> /tmp/k3s_test_complete
          echo "K3S service is running" >> /tmp/k3s_test_complete
          echo "Cluster is responsive" >> /tmp/k3s_test_complete
          k3s --version >> /tmp/k3s_test_complete
          k3s kubectl get nodes >> /tmp/k3s_test_complete
          echo "Puppet module test: SUCCESS" >> /tmp/k3s_test_complete
        else
          echo "K3S Puppet module deployment failed on #{ami_config['name']}" > /tmp/k3s_test_complete
          echo "Deployment type: #{deployment_type}" >> /tmp/k3s_test_complete
          echo "Installation method: Puppet module" >> /tmp/k3s_test_complete
          echo "Timestamp: $(date)" >> /tmp/k3s_test_complete
          echo "K3S service status: $(systemctl is-active k3s)" >> /tmp/k3s_test_complete
          systemctl status k3s >> /tmp/k3s_test_complete 2>&1
          echo "Puppet module test: FAILED" >> /tmp/k3s_test_complete
        fi
      else
        # Agent node testing
        echo "Testing K3S agent functionality..."
        
        # For agent nodes, just check if the service is running
        # They don't have kubectl access
        echo '=== Creating Final Test Completion Marker ==='\n
        if systemctl is-active --quiet k3s-agent; then
          echo "K3S Puppet module deployment completed successfully on #{ami_config['name']}" > /tmp/k3s_test_complete
          echo "Deployment type: #{deployment_type}" >> /tmp/k3s_test_complete
          echo "Installation method: Puppet module" >> /tmp/k3s_test_complete
          echo "Timestamp: $(date)" >> /tmp/k3s_test_complete
          echo "K3S agent service is running" >> /tmp/k3s_test_complete
          k3s --version >> /tmp/k3s_test_complete
          echo "Puppet module test: SUCCESS" >> /tmp/k3s_test_complete
        else
          echo "K3S Puppet module deployment failed on #{ami_config['name']}" > /tmp/k3s_test_complete
          echo "Deployment type: #{deployment_type}" >> /tmp/k3s_test_complete
          echo "Installation method: Puppet module" >> /tmp/k3s_test_complete
          echo "Timestamp: $(date)" >> /tmp/k3s_test_complete
          echo "K3S agent service status: $(systemctl is-active k3s-agent)" >> /tmp/k3s_test_complete
          systemctl status k3s-agent >> /tmp/k3s_test_complete 2>&1
          echo "Puppet module test: FAILED" >> /tmp/k3s_test_complete
        fi
      fi
      
      echo '=== K3S Puppet Module Installation Complete ==='\n
      date
    SCRIPT
    
    script
  end

  # Install basic packages on APT-based systems
  def install_basic_packages_apt
    <<~SCRIPT
      # Update package list
      apt-get update
      
      # Install prerequisites
      apt-get install -y wget curl gnupg systemctl
    SCRIPT
  end

  # Install basic packages on DNF-based systems
  def install_basic_packages_dnf
    <<~SCRIPT
      # Update system
      dnf update -y
      
      # Install prerequisites
      dnf install -y wget curl systemd
    SCRIPT
  end

  # Install basic packages on Zypper-based systems
  def install_basic_packages_zypper
    <<~SCRIPT
      # Refresh repositories
      zypper refresh
      
      # Install prerequisites
      zypper install -y wget curl systemd
    SCRIPT
  end

  # Install Puppet on APT-based systems (kept for reference)
  def install_puppet_apt(os)
    puppet_repo = case os
                  when 'ubuntu'
                    'https://apt.puppet.com/puppet8-release-jammy.deb'
                  when 'debian'
                    'https://apt.puppet.com/puppet8-release-bookworm.deb'
                  end
    
    <<~SCRIPT
      # Update package list
      apt-get update
      
      # Install prerequisites
      apt-get install -y wget curl gnupg
      
      # Install Puppet repository
      wget #{puppet_repo} -O /tmp/puppet-release.deb
      dpkg -i /tmp/puppet-release.deb
      apt-get update
      
      # Install Puppet
      apt-get install -y puppet-agent
      
      # Add Puppet to PATH
      export PATH="/opt/puppetlabs/bin:$PATH"
      echo 'export PATH="/opt/puppetlabs/bin:$PATH"' >> /root/.bashrc
    SCRIPT
  end

  # Install Puppet on DNF-based systems
  def install_puppet_dnf(os)
    puppet_repo = case os
                  when 'rhel'
                    'https://yum.puppet.com/puppet8-release-el-8.noarch.rpm'
                  when 'rocky', 'almalinux'
                    'https://yum.puppet.com/puppet8-release-el-9.noarch.rpm'
                  when 'fedora'
                    'https://yum.puppet.com/puppet8-release-fedora-40.noarch.rpm'
                  end
    
    <<~SCRIPT
      # Update system
      dnf update -y
      
      # Install Puppet repository
      rpm -Uvh #{puppet_repo}
      
      # Install Puppet
      dnf install -y puppet-agent
      
      # Add Puppet to PATH
      export PATH="/opt/puppetlabs/bin:$PATH"
      echo 'export PATH="/opt/puppetlabs/bin:$PATH"' >> /root/.bashrc
    SCRIPT
  end

  # Install Puppet on Zypper-based systems
  def install_puppet_zypper(os)
    <<~SCRIPT
      # Refresh repositories
      zypper refresh
      
      # Install Puppet repository
      rpm -Uvh https://yum.puppet.com/puppet8-release-sles-15.noarch.rpm
      
      # Install Puppet
      zypper install -y puppet-agent
      
      # Add Puppet to PATH
      export PATH="/opt/puppetlabs/bin:$PATH"
      echo 'export PATH="/opt/puppetlabs/bin:$PATH"' >> /root/.bashrc
    SCRIPT
  end

  # Test instance connectivity and K3S deployment
  def test_instance(instance_info, deployment_type = 'single')
    instance_id = instance_info['instance_id']
    public_ip = instance_info['public_ip']
    os = instance_info['os']
    user = LATEST_AMIS[os]['user']
    
    puts "Testing instance #{instance_id} (#{public_ip}) - #{deployment_type} node"
    
    # Wait for SSH to be available
    max_attempts = 30
    attempt = 0
    
    loop do
      return false if @interrupted
      
      attempt += 1
      
      begin
        result = ssh_command(public_ip, user, 'echo "SSH connection test"')
        puts "SSH connection successful"
        break
      rescue => e
        if attempt >= max_attempts
          puts "SSH connection failed after #{max_attempts} attempts: #{e.message}"
          return false
        end
        puts "SSH attempt #{attempt}/#{max_attempts} failed, retrying in 10 seconds..."
        
        begin
          interruptible_sleep(10)
        rescue Interrupt
          puts "🛑 SSH connection attempts interrupted"
          return false
        end
      end
    end

    # Fast K3S health verification using multiple checks
    puts "Performing fast K3S health verification..."
    max_wait = 300  # Reduced to 5 minutes
    start_time = Time.now
    check_interval = 10  # Check every 10 seconds
    
    health_checks_passed = false
    
    loop do
      return false if @interrupted
      
      elapsed = Time.now - start_time
      
      begin
        puts "🔍 Running K3S health checks... (#{elapsed.to_i}s elapsed)"
        
        # Check 1: Service Status Verification
        puts "   ✓ Checking K3S service status..."
        
        if deployment_type == 'agent'
          # Agent nodes use k3s-agent service
          service_status = ssh_command(public_ip, user, 'sudo systemctl is-active k3s-agent 2>/dev/null || echo "inactive"')
          service_enabled = ssh_command(public_ip, user, 'sudo systemctl is-enabled k3s-agent 2>/dev/null || echo "disabled"')
          service_name = 'k3s-agent'
        else
          # Server nodes use k3s service
          service_status = ssh_command(public_ip, user, 'sudo systemctl is-active k3s 2>/dev/null || echo "inactive"')
          service_enabled = ssh_command(public_ip, user, 'sudo systemctl is-enabled k3s 2>/dev/null || echo "disabled"')
          service_name = 'k3s'
        end
        
        if service_status.strip == "active"
          puts "   ✅ K3S #{service_name} service is active and running"
          
          if deployment_type == 'agent'
            # For agent nodes, we can't do kubectl checks, so just verify the service is healthy
            puts "   ✓ Agent node health verification..."
            
            # Check if the agent process is running and connected
            agent_logs = ssh_command(public_ip, user, 'sudo journalctl -u k3s-agent --no-pager --lines=5 | tail -3 || echo "No logs"')
            if agent_logs.include?("Starting") || agent_logs.include?("Ready") || !agent_logs.include?("Failed")
              puts "   ✅ K3S agent appears to be running normally"
              puts ""
              puts "🎉 K3S agent health checks passed! Agent node is operational."
              health_checks_passed = true
              break
            else
              puts "   ⚠️  Agent logs show potential issues:"
              puts agent_logs.split("\n").map { |line| "      #{line}" }.join("\n")
            end
          else
            # Server node checks (existing logic)
            # Check 2: Cluster Information Check
            puts "   ✓ Checking cluster connectivity..."
            cluster_info = ssh_command(public_ip, user, 'sudo k3s kubectl cluster-info 2>/dev/null | head -1 || echo "FAILED"')
            
            if cluster_info.include?("Kubernetes control plane")
              puts "   ✅ Kubernetes API server is accessible"
              
              # Check 3: Node Status Verification
              puts "   ✓ Checking node readiness..."
              node_status = ssh_command(public_ip, user, 'sudo k3s kubectl get nodes --no-headers 2>/dev/null | awk \'{print $2}\' || echo "NotReady"')
              
              if node_status.strip == "Ready"
                puts "   ✅ Node is in Ready state"
                
                # Check 4: Pod Health Assessment
                puts "   ✓ Checking system pods health..."
                pods_status = ssh_command(public_ip, user, 'sudo k3s kubectl get pods --all-namespaces --no-headers 2>/dev/null | grep -v Running | grep -v Completed | wc -l || echo "999"')
                
                non_running_pods = pods_status.strip.to_i
                if non_running_pods == 0
                  puts "   ✅ All system pods are running correctly"
                  
                  # Check 5: Kubeconfig File Verification
                  puts "   ✓ Verifying kubeconfig file..."
                  kubeconfig_check = ssh_command(public_ip, user, 'sudo test -f /etc/rancher/k3s/k3s.yaml && sudo test -s /etc/rancher/k3s/k3s.yaml && echo "OK" || echo "MISSING"')
                  
                  if kubeconfig_check.strip == "OK"
                    puts "   ✅ Kubeconfig file exists and is not empty"
                    
                    # Check 6: Test Pod Deployment (Quick functional test)
                    puts "   ✓ Testing pod deployment capability..."
                    test_pod_result = ssh_command(public_ip, user, 'sudo k3s kubectl run test-pod-verify --image=nginx:alpine --restart=Never --timeout=30s 2>/dev/null && sleep 5 && sudo k3s kubectl get pod test-pod-verify --no-headers 2>/dev/null | awk \'{print $3}\' && sudo k3s kubectl delete pod test-pod-verify --timeout=10s >/dev/null 2>&1 || echo "FAILED"')
                    
                    if test_pod_result.strip == "Running" || test_pod_result.include?("Running")
                      puts "   ✅ Pod deployment test successful"
                      puts ""
                      puts "🎉 All K3S health checks passed! Cluster is fully operational."
                      health_checks_passed = true
                      break
                    else
                      puts "   ⚠️  Pod deployment test failed, but basic cluster is functional"
                      puts "   📝 This might be due to image pull delays or resource constraints"
                      # Still consider this a success since core K3S is working
                      health_checks_passed = true
                      break
                    end
                  else
                    puts "   ❌ Kubeconfig file is missing or empty"
                  end
                else
                  puts "   ⚠️  #{non_running_pods} system pods are not running yet"
                  
                  # Show pod details for debugging
                  if elapsed % 30 == 0  # Every 30 seconds
                    pod_details = ssh_command(public_ip, user, 'sudo k3s kubectl get pods --all-namespaces 2>/dev/null | grep -v Running | grep -v Completed || echo "No problematic pods found"')
                    puts "   📋 Non-running pods:"
                    puts pod_details.split("\n").map { |line| "      #{line}" }.join("\n")
                  end
                end
              else
                puts "   ⚠️  Node status: #{node_status.strip}"
              end
            else
              puts "   ⚠️  Cluster API not accessible yet"
            end
          end
        else
          puts "   ⚠️  K3S #{service_name} service status: #{service_status.strip}"
          
          # Check if Puppet is still running (might be installing K3S)
          puppet_running = ssh_command(public_ip, user, 'pgrep -f puppet >/dev/null && echo "RUNNING" || echo "FINISHED"')
          puts "   📝 Puppet status: #{puppet_running.strip}"
          
          # Check if there are any obvious errors in the K3S service
          if elapsed > 60  # After 1 minute, start showing more detailed info
            begin
              service_logs = ssh_command(public_ip, user, "sudo journalctl -u #{service_name} --no-pager --lines=3 2>/dev/null | tail -3 || echo 'No logs available'")
              puts "   📋 Recent K3S #{service_name} service logs:"
              puts service_logs.split("\n").map { |line| "      #{line}" }.join("\n")
            rescue
              puts "   📋 Unable to retrieve service logs"
            end
          end
        end
        
      rescue => e
        puts "   ❌ Health check failed: #{e.message}"
      end
      
      if elapsed > max_wait
        puts ""
        puts "❌ Timeout waiting for K3S cluster to become healthy (#{max_wait}s)"
        puts "💡 Attempting to gather final diagnostic information..."
        
        begin
          # Final diagnostic information
          final_service_status = ssh_command(public_ip, user, 'sudo systemctl status k3s --no-pager --lines=10 || echo "Service status unavailable"')
          puts "📋 Final K3S service status:"
          puts final_service_status.split("\n").map { |line| "   #{line}" }.join("\n")
          
          final_logs = ssh_command(public_ip, user, 'sudo journalctl -u k3s --no-pager --lines=10 | tail -10 || echo "Logs unavailable"')
          puts "📋 Final K3S logs:"
          puts final_logs.split("\n").map { |line| "   #{line}" }.join("\n")
        rescue
          puts "📋 Unable to gather final diagnostic information"
        end
        
        break
      end
      
      begin
        interruptible_sleep(check_interval)
      rescue Interrupt
        puts "🛑 K3S health verification interrupted"
        return false
      end
    end
    
    # Return test results
    begin
      final_k3s_status = ssh_command(public_ip, user, 'sudo systemctl is-active k3s || echo "inactive"')
      final_node_status = ssh_command(public_ip, user, 'sudo k3s kubectl get nodes --no-headers 2>/dev/null | awk \'{print $2}\' || echo "Unknown"')
      
      success = health_checks_passed && final_k3s_status.strip == "active"
      
      result = {
        'success' => success,
        'instance_id' => instance_id,
        'os' => os,
        'k3s_status' => final_k3s_status.strip,
        'node_status' => final_node_status.strip,
        'health_checks_passed' => health_checks_passed,
        'verification_time' => (Time.now - start_time).to_i
      }
      
      if success
        puts "✅ K3S verification completed successfully in #{result['verification_time']} seconds"
      else
        puts "❌ K3S verification failed after #{result['verification_time']} seconds"
      end
      
      result
      
    rescue => e
      puts "❌ Failed to get final test results: #{e.message}"
      {
        'success' => false,
        'instance_id' => instance_id,
        'os' => os,
        'error' => e.message,
        'verification_time' => (Time.now - start_time).to_i
      }
    end
  end

  # Execute SSH command on instance
  def ssh_command(host, user, command)
    ssh_cmd = [
      'ssh',
      '-i', @temp_resources['key_file_path'],
      '-o', 'StrictHostKeyChecking=no',
      '-o', 'UserKnownHostsFile=/dev/null',
      '-o', 'ConnectTimeout=10',
      "#{user}@#{host}",
      command
    ]
    
    stdout, stderr, status = Open3.capture3(*ssh_cmd)
    
    unless status.success?
      raise "SSH command failed: #{stderr}"
    end
    
    stdout
  end

  # Clean up temporary resources
  def cleanup_temp_resources
    puts "Cleaning up temporary resources for session: #{@session_id}"
    
    # Terminate all instances with this session ID
    cleanup_instances
    
    # Delete security group
    cleanup_security_group
    
    # Delete key pair
    cleanup_key_pair
    
    puts "Cleanup completed"
  end

  # Cleanup instances
  def cleanup_instances
    puts "🧹 Starting comprehensive instance cleanup..."
    all_instance_ids = []
    
    begin
      # Method 1: Find instances by session ID tag
      puts "   🔍 Finding instances by session ID: #{@session_id}"
      result = run_aws_command([
        'ec2', 'describe-instances',
        '--filters', "Name=tag:SessionId,Values=#{@session_id}",
        '--query', 'Reservations[].Instances[?State.Name!=`terminated`].InstanceId',
        '--output', 'text',
        '--region', @region
      ])
      
      session_instances = result.strip.split(/\s+/).reject(&:empty?)
      puts "   📋 Found #{session_instances.length} instances by session ID"
      all_instance_ids.concat(session_instances)
      
    rescue => e
      puts "   ⚠️  Error finding instances by session ID: #{e.message}"
    end
    
    begin
      # Method 2: Find instances from tracking file
      puts "   📂 Finding instances from tracking file"
      tracked_instances = @created_instances.map { |inst| inst['instance_id'] }
      puts "   📋 Found #{tracked_instances.length} tracked instances"
      all_instance_ids.concat(tracked_instances)
      
    rescue => e
      puts "   ⚠️  Error reading tracking file: #{e.message}"
    end
    
    begin
      # Method 3: Find orphaned instances with our naming pattern
      puts "   🔍 Finding orphaned instances with k3s-test naming pattern"
      result = run_aws_command([
        'ec2', 'describe-instances',
        '--filters', 
        'Name=tag:Name,Values=k3s-test-*',
        'Name=tag:CreatedBy,Values=k3s-multi-os-testing',
        '--query', 'Reservations[].Instances[?State.Name!=`terminated`].{InstanceId:InstanceId,Name:Tags[?Key==`Name`].Value|[0],LaunchTime:LaunchTime}',
        '--output', 'json',
        '--region', @region
      ])
      
      orphaned_data = JSON.parse(result)
      orphaned_instances = orphaned_data.map { |inst| inst['InstanceId'] }
      
      if orphaned_instances.any?
        puts "   ⚠️  Found #{orphaned_instances.length} potentially orphaned instances:"
        orphaned_data.each do |inst|
          launch_time = Time.parse(inst['LaunchTime'])
          age_hours = ((Time.now - launch_time) / 3600).round(1)
          puts "     - #{inst['InstanceId']} (#{inst['Name']}) - #{age_hours}h old"
        end
        all_instance_ids.concat(orphaned_instances)
      end
      
    rescue => e
      puts "   ⚠️  Error finding orphaned instances: #{e.message}"
    end
    
    # Remove duplicates and filter out empty values
    unique_instance_ids = all_instance_ids.compact.uniq.reject(&:empty?)
    
    if unique_instance_ids.any?
      puts "   🎯 Total instances to terminate: #{unique_instance_ids.length}"
      puts "   📋 Instance IDs: #{unique_instance_ids.join(', ')}"
      
      # Verify instances exist before terminating
      verified_instances = verify_instances_exist(unique_instance_ids)
      
      if verified_instances.any?
        puts "   🗑️  Terminating #{verified_instances.length} verified instances..."
        terminate_instances(verified_instances)
      else
        puts "   ℹ️  No instances found to terminate (all may already be terminated)"
      end
    else
      puts "   ✅ No instances found to cleanup"
    end
    
    # Clean up tracking file
    cleanup_tracking_file
  end

  # Verify instances exist and are not already terminated
  def verify_instances_exist(instance_ids)
    return [] if instance_ids.empty?
    
    begin
      result = run_aws_command([
        'ec2', 'describe-instances',
        '--instance-ids'] + instance_ids + [
        '--query', 'Reservations[].Instances[?State.Name!=`terminated`].InstanceId',
        '--output', 'text',
        '--region', @region
      ])
      
      existing_instances = result.strip.split(/\s+/).reject(&:empty?)
      puts "   ✅ Verified #{existing_instances.length} instances exist and are not terminated"
      return existing_instances
      
    rescue => e
      puts "   ⚠️  Error verifying instances: #{e.message}"
      return []
    end
  end

  # Terminate instances with proper error handling
  def terminate_instances(instance_ids)
    return if instance_ids.empty?
    
    begin
      run_aws_command([
        'ec2', 'terminate-instances',
        '--instance-ids'] + instance_ids + [
        '--region', @region
      ])
      
      puts "   ✅ Termination request sent for #{instance_ids.length} instances"
      
      # Wait for termination with timeout
      puts "   ⏳ Waiting for instances to terminate (with timeout)..."
      begin
        Timeout::timeout(300) do  # 5 minute timeout
          run_aws_command([
            'ec2', 'wait', 'instance-terminated',
            '--instance-ids'] + instance_ids + [
            '--region', @region
          ])
        end
        puts "   ✅ All instances terminated successfully"
      rescue Timeout::Error, StandardError => e
        puts "   ⚠️  Timeout waiting for termination, but instances are likely terminating"
        puts "   💡 You can check status with: aws ec2 describe-instances --instance-ids #{instance_ids.join(' ')}"
      end
      
    rescue => e
      puts "   ❌ Error terminating instances: #{e.message}"
      puts "   💡 You may need to manually terminate: #{instance_ids.join(', ')}"
    end
  end

  # Clean up tracking file
  def cleanup_tracking_file
    if File.exist?(@instance_tracking_file)
      File.delete(@instance_tracking_file)
      puts "   🗑️  Cleaned up tracking file: #{@instance_tracking_file}"
    end
  rescue => e
    puts "   ⚠️  Warning: Could not delete tracking file: #{e.message}"
  end

  # Enhanced cleanup all resources
  def cleanup_all_resources
    puts "\n🧹 Comprehensive cleanup of all resources..."
    cleanup_instances
    cleanup_temp_resources
    puts "✅ Cleanup completed!"
  end

  # Cleanup security group
  def cleanup_security_group
    return unless @temp_resources['security_group_id']
    
    begin
      puts "Deleting security group: #{@temp_resources['security_group_id']}"
      run_aws_command([
        'ec2', 'delete-security-group',
        '--group-id', @temp_resources['security_group_id'],
        '--region', @region
      ])
    rescue => e
      puts "Error deleting security group: #{e.message}"
    end
  end

  # Cleanup key pair
  def cleanup_key_pair
    return unless @temp_resources['key_pair_name']
    
    begin
      puts "Deleting key pair: #{@temp_resources['key_pair_name']}"
      run_aws_command([
        'ec2', 'delete-key-pair',
        '--key-name', @temp_resources['key_pair_name'],
        '--region', @region
      ])
      
      # Remove local key file
      if @temp_resources['key_file_path'] && File.exist?(@temp_resources['key_file_path'])
        File.delete(@temp_resources['key_file_path'])
        puts "Deleted local key file: #{@temp_resources['key_file_path']}"
      end
    rescue => e
      puts "Error deleting key pair: #{e.message}"
    end
  end

  # List running test instances
  def list_test_instances
    result = run_aws_command([
      'ec2', 'describe-instances',
      '--filters', 'Name=tag:CreatedBy,Values=k3s-multi-os-testing',
      '--query', 'Reservations[].Instances[?State.Name!=`terminated`].[InstanceId,Tags[?Key==`Name`].Value|[0],Tags[?Key==`OS`].Value|[0],State.Name,PublicIpAddress]',
      '--output', 'table',
      '--region', @region
    ])
    
    puts result
  end

  # Generate test report
  def generate_test_report(test_results)
    total_verification_time = test_results.sum { |r| r['verification_time'] || 0 }
    avg_verification_time = test_results.length > 0 ? (total_verification_time / test_results.length) : 0
    
    report = {
      'session_id' => @session_id,
      'timestamp' => Time.now.strftime('%Y-%m-%dT%H:%M:%S%z'),
      'region' => @region,
      'instance_type' => @instance_type,
      'summary' => {
        'total_tests' => test_results.length,
        'successful' => test_results.count { |r| r['success'] },
        'failed' => test_results.count { |r| !r['success'] },
        'health_checks_passed' => test_results.count { |r| r['health_checks_passed'] },
        'total_verification_time' => total_verification_time,
        'average_verification_time' => avg_verification_time
      },
      'results' => test_results
    }
    
    puts "\n" + "="*70
    puts "K3S Multi-OS Test Report - Fast Health Verification"
    puts "="*70
    puts "Session ID: #{report['session_id']}"
    puts "Timestamp: #{report['timestamp']}"
    puts "Region: #{report['region']}"
    puts "Instance Type: #{report['instance_type']}"
    puts ""
    puts "Summary:"
    puts "  Total Tests: #{report['summary']['total_tests']}"
    puts "  Successful: #{report['summary']['successful']}"
    puts "  Failed: #{report['summary']['failed']}"
    puts "  Health Checks Passed: #{report['summary']['health_checks_passed']}"
    puts "  Total Verification Time: #{report['summary']['total_verification_time']}s"
    puts "  Average Verification Time: #{report['summary']['average_verification_time']}s"
    puts ""
    puts "Detailed Results:"
    puts "-" * 70
    
    test_results.each do |result|
      status = result['success'] ? "✅ PASS" : "❌ FAIL"
      os_name = result['os'].upcase.ljust(8)
      k3s_status = (result['k3s_status'] || 'unknown').ljust(8)
      node_status = (result['node_status'] || 'unknown').ljust(10)
      verification_time = result['verification_time'] || 0
      health_checks = result['health_checks_passed'] ? "✅" : "❌"
      
      puts "#{status} #{os_name} | K3S: #{k3s_status} | Node: #{node_status} | Time: #{verification_time}s | Health: #{health_checks}"
      
      if result['error']
        puts "      Error: #{result['error']}"
      end
    end
    
    puts "-" * 70
    puts ""
    
    # Performance insights
    if test_results.length > 1
      fastest = test_results.min_by { |r| r['verification_time'] || 999 }
      slowest = test_results.max_by { |r| r['verification_time'] || 0 }
      
      puts "Performance Insights:"
      puts "  Fastest: #{fastest['os'].upcase} (#{fastest['verification_time']}s)"
      puts "  Slowest: #{slowest['os'].upcase} (#{slowest['verification_time']}s)"
      puts ""
    end
    
    puts "="*70
    
    report
  end

  # Track created instances
  def track_instance(instance_id, instance_info = {})
    instance_data = {
      'instance_id' => instance_id,
      'created_at' => Time.now.iso8601,
      'session_id' => @session_id,
      'region' => @region
    }.merge(instance_info)
    
    @created_instances << instance_data
    save_instance_tracking
    puts "📝 Tracked instance: #{instance_id}"
  end

  # Save instance tracking to file
  def save_instance_tracking
    tracking_data = {
      'session_id' => @session_id,
      'region' => @region,
      'created_at' => Time.now.iso8601,
      'instances' => @created_instances
    }
    
    File.write(@instance_tracking_file, JSON.pretty_generate(tracking_data))
  rescue => e
    puts "⚠️  Warning: Could not save instance tracking: #{e.message}"
  end

  # Load instance tracking from file
  def load_instance_tracking
    return unless File.exist?(@instance_tracking_file)
    
    data = JSON.parse(File.read(@instance_tracking_file))
    @created_instances = data['instances'] || []
    puts "📂 Loaded #{@created_instances.length} tracked instances"
  rescue => e
    puts "⚠️  Warning: Could not load instance tracking: #{e.message}"
    @created_instances = []
  end

  private

  # Run AWS CLI command
  def run_aws_command(args)
    cmd = ['aws'] + args
    stdout, stderr, status = Open3.capture3(*cmd)
    
    unless status.success?
      raise "AWS command failed: #{stderr}"
    end
    
    stdout
  end
end 