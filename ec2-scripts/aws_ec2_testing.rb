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
  def initialize
    @session_id = SecureRandom.hex(8)
    @region = ENV['AWS_REGION'] || 'us-west-2'
    @instance_type = ENV['INSTANCE_TYPE'] || 't3.medium'
    @temp_resources = {
      'security_group_id' => nil,
      'key_pair_name' => nil,
      'key_file_path' => nil
    }
  end

  attr_reader :session_id, :region, :instance_type, :temp_resources

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
      # Create Puppet manifest for single node installation
      cat > /tmp/k3s_config.pp << 'EOF'
      class { 'k3s_cluster':
        ensure => 'present',
        node_type => 'server',
        cluster_init => true,
        installation_method => 'script',
        version => 'stable',
      }
      EOF
      
      echo '=== Running Puppet Apply ==='\n
      # Apply Puppet configuration with verbose output
      puppet apply /tmp/k3s_config.pp --verbose --detailed-exitcodes
      
      echo '=== Waiting for K3S Service ==='\n
      # Wait for K3S to be ready
      timeout 120 bash -c 'until systemctl is-active --quiet k3s; do echo "Waiting for K3S service..."; sleep 5; done'
      
      echo '=== Testing K3S Installation ==='\n
      # Test K3S functionality
      k3s --version
      k3s kubectl get nodes
      
      echo '=== Creating Test Completion Marker ==='\n
      # Create test completion marker
      if systemctl is-active --quiet k3s; then
        echo "K3S Puppet module deployment completed successfully on #{ami_config['name']}" > /tmp/k3s_test_complete
        echo "Deployment type: #{deployment_type}" >> /tmp/k3s_test_complete
        echo "Installation method: Puppet module" >> /tmp/k3s_test_complete
        echo "Timestamp: $(date)" >> /tmp/k3s_test_complete
        echo "K3S service is running" >> /tmp/k3s_test_complete
        k3s --version >> /tmp/k3s_test_complete
        k3s kubectl get nodes >> /tmp/k3s_test_complete
        echo "Puppet module test: SUCCESS" >> /tmp/k3s_test_complete
      else
        echo "K3S Puppet module deployment failed on #{ami_config['name']}" > /tmp/k3s_test_complete
        echo "Deployment type: #{deployment_type}" >> /tmp/k3s_test_complete
        echo "Installation method: Puppet module" >> /tmp/k3s_test_complete
        echo "Timestamp: $(date)" >> /tmp/k3s_test_complete
        echo "K3S service failed to start" >> /tmp/k3s_test_complete
        systemctl status k3s >> /tmp/k3s_test_complete 2>&1
        echo "Puppet module test: FAILED" >> /tmp/k3s_test_complete
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
  def test_instance(instance_info)
    instance_id = instance_info['instance_id']
    public_ip = instance_info['public_ip']
    os = instance_info['os']
    user = LATEST_AMIS[os]['user']
    
    puts "Testing instance #{instance_id} (#{public_ip})"
    
    # Wait for SSH to be available
    max_attempts = 30
    attempt = 0
    
    loop do
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
        sleep 10
      end
    end
    
    # Wait for user data script completion
    puts "Waiting for K3S deployment to complete..."
    max_wait = 600  # 10 minutes
    start_time = Time.now
    
    loop do
      begin
        result = ssh_command(public_ip, user, 'test -f /tmp/k3s_test_complete && echo "COMPLETE"')
        if result.strip == "COMPLETE"
          puts "K3S deployment completed"
          break
        end
      rescue
        # File doesn't exist yet, continue waiting
      end
      
      if Time.now - start_time > max_wait
        puts "Timeout waiting for K3S deployment"
        return false
      end
      
      sleep 30
    end
    
    # Get test results
    begin
      test_results = ssh_command(public_ip, user, 'cat /tmp/k3s_test_complete')
      puts "Test Results:"
      puts test_results
      
      # Check if K3S is running
      k3s_status = ssh_command(public_ip, user, 'sudo systemctl is-active k3s || echo "FAILED"')
      success = k3s_status.strip == "active"
      
      {
        'success' => success,
        'instance_id' => instance_id,
        'os' => os,
        'results' => test_results,
        'k3s_status' => k3s_status.strip
      }
    rescue => e
      puts "Failed to get test results: #{e.message}"
      {
        'success' => false,
        'instance_id' => instance_id,
        'os' => os,
        'error' => e.message
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
    begin
      result = run_aws_command([
        'ec2', 'describe-instances',
        '--filters', "Name=tag:SessionId,Values=#{@session_id}",
        '--query', 'Reservations[].Instances[?State.Name!=`terminated`].InstanceId',
        '--output', 'text',
        '--region', @region
      ])
      
      instance_ids = result.strip.split(/\s+/).reject(&:empty?)
      
      if instance_ids.any?
        puts "Terminating instances: #{instance_ids.join(', ')}"
        run_aws_command([
          'ec2', 'terminate-instances',
          '--instance-ids'] + instance_ids + [
          '--region', @region
        ])
        
        puts "Waiting for instances to terminate (with timeout)..."
        begin
          # Use a shorter timeout to avoid RequestExpired errors
          Timeout::timeout(300) do  # 5 minute timeout
            run_aws_command([
              'ec2', 'wait', 'instance-terminated',
              '--instance-ids'] + instance_ids + [
              '--region', @region
            ])
          end
          puts "✅ Instances terminated successfully"
        rescue Timeout::Error, StandardError => e
          puts "⚠️  Timeout waiting for termination, but instances are likely terminating"
          puts "   (This is normal - AWS termination can take several minutes)"
        end
      end
    rescue => e
      puts "Error cleaning up instances: #{e.message}"
      # Continue with cleanup even if instance cleanup fails
    end
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
    report = {
      'session_id' => @session_id,
      'timestamp' => Time.now.iso8601,
      'region' => @region,
      'instance_type' => @instance_type,
      'summary' => {
        'total_tests' => test_results.length,
        'successful' => test_results.count { |r| r['success'] },
        'failed' => test_results.count { |r| !r['success'] }
      },
      'results' => test_results
    }
    
    puts "\n" + "="*60
    puts "K3S Multi-OS Test Report"
    puts "="*60
    puts "Session ID: #{report['session_id']}"
    puts "Timestamp: #{report['timestamp']}"
    puts "Region: #{report['region']}"
    puts "Instance Type: #{report['instance_type']}"
    puts ""
    puts "Summary:"
    puts "  Total Tests: #{report['summary']['total_tests']}"
    puts "  Successful: #{report['summary']['successful']}"
    puts "  Failed: #{report['summary']['failed']}"
    puts ""
    
    test_results.each do |result|
      status = result['success'] ? "✅ PASS" : "❌ FAIL"
      puts "#{status} #{result['os'].upcase}: #{result['k3s_status'] || result['error']}"
    end
    
    puts "="*60
    
    report
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