#!/usr/bin/env ruby
# Alternative approach: Embed K3S module directly in user data script
# This avoids any GitHub download issues

require_relative 'aws_ec2_testing'

class EmbeddedModuleTesting < AwsEc2K3sTesting
  # Override to create user data with embedded module
  def generate_user_data_script(os, deployment_type)
    ami_config = LATEST_AMIS[os]
    package_manager = ami_config['package_manager']
    
    script = "#!/bin/bash\n"
    script += "set -e\n"
    script += "exec > >(tee /var/log/k3s-puppet-install.log) 2>&1\n\n"
    script += "# K3S Puppet Module Testing (Embedded Module)\n"
    script += "# OS: #{ami_config['name']}\n"
    script += "# Deployment Type: #{deployment_type}\n\n"
    
    script += "echo '=== Starting K3S Puppet Module Installation (Embedded) ===' \n"
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
    
    # Embed the module directly
    script += <<~SCRIPT
      
      echo '=== Installing Puppet Dependencies ==='\n
      # Install required Puppet modules
      puppet module install puppet-archive --force
      puppet module install puppetlabs-stdlib --force
      
      echo '=== Creating Embedded K3S Puppet Module ==='\n
      # Create module structure
      mkdir -p /etc/puppetlabs/code/modules/k3s_cluster/{manifests,templates}
      
      # Create init.pp
      cat > /etc/puppetlabs/code/modules/k3s_cluster/manifests/init.pp << 'INIT_EOF'
      class k3s_cluster (
        Enum['present', 'absent'] $ensure = 'present',
        Enum['server', 'agent'] $node_type = 'server',
        Enum['script', 'binary'] $installation_method = 'script',
        String $version = 'stable',
        Optional[String] $server_url = undef,
        Optional[String] $token = undef,
        Boolean $cluster_init = false,
        Hash $config_options = {},
      ) {
        case $ensure {
          'present': {
            include k3s_cluster::install
            include k3s_cluster::config
            include k3s_cluster::service
            
            Class['k3s_cluster::install']
            -> Class['k3s_cluster::config']
            -> Class['k3s_cluster::service']
          }
          'absent': {
            include k3s_cluster::uninstall
          }
        }
      }
      INIT_EOF
      
      # Create install.pp
      cat > /etc/puppetlabs/code/modules/k3s_cluster/manifests/install.pp << 'INSTALL_EOF'
      class k3s_cluster::install {
        # Create config directory
        file { '/etc/rancher/k3s':
          ensure => directory,
          owner  => 'root',
          group  => 'root',
          mode   => '0755',
        }
        
        # Install K3S using script method
        exec { 'install_k3s':
          command     => "curl -sfL https://get.k3s.io | sh -",
          path        => ['/usr/bin', '/bin', '/usr/local/bin'],
          creates     => '/usr/local/bin/k3s',
          environment => [
            "INSTALL_K3S_VERSION=${k3s_cluster::version}",
            "INSTALL_K3S_EXEC=${k3s_cluster::node_type}",
          ],
          timeout     => 300,
          require     => File['/etc/rancher/k3s'],
        }
      }
      INSTALL_EOF
      
      # Create config.pp
      cat > /etc/puppetlabs/code/modules/k3s_cluster/manifests/config.pp << 'CONFIG_EOF'
      class k3s_cluster::config {
        # Basic configuration
        $default_config = {
          'write-kubeconfig-mode' => '0644',
        }
        
        $final_config = merge($default_config, $k3s_cluster::config_options)
        
        file { '/etc/rancher/k3s/config.yaml':
          ensure  => file,
          content => to_yaml($final_config),
          owner   => 'root',
          group   => 'root',
          mode    => '0600',
          require => File['/etc/rancher/k3s'],
        }
      }
      CONFIG_EOF
      
      # Create service.pp
      cat > /etc/puppetlabs/code/modules/k3s_cluster/manifests/service.pp << 'SERVICE_EOF'
      class k3s_cluster::service {
        service { 'k3s':
          ensure  => running,
          enable  => true,
          require => [
            File['/etc/rancher/k3s/config.yaml'],
            Exec['install_k3s'],
          ],
        }
      }
      SERVICE_EOF
      
      # Create uninstall.pp
      cat > /etc/puppetlabs/code/modules/k3s_cluster/manifests/uninstall.pp << 'UNINSTALL_EOF'
      class k3s_cluster::uninstall {
        service { 'k3s':
          ensure => stopped,
          enable => false,
        }
        
        exec { 'k3s_uninstall':
          command => '/usr/local/bin/k3s-uninstall.sh',
          path    => ['/usr/local/bin', '/usr/bin', '/bin'],
          onlyif  => 'test -f /usr/local/bin/k3s-uninstall.sh',
          require => Service['k3s'],
        }
      }
      UNINSTALL_EOF
      
      echo '=== Applying K3S Puppet Configuration ==='\n
      # Create Puppet manifest
      cat > /tmp/k3s_config.pp << 'MANIFEST_EOF'
      class { 'k3s_cluster':
        ensure => 'present',
        node_type => 'server',
        cluster_init => true,
        installation_method => 'script',
        version => 'stable',
      }
      MANIFEST_EOF
      
      echo '=== Running Puppet Apply ==='\n
      # Apply configuration
      puppet apply /tmp/k3s_config.pp --verbose --detailed-exitcodes
      
      echo '=== Waiting for K3S Service ==='\n
      # Wait for service
      timeout 120 bash -c 'until systemctl is-active --quiet k3s; do echo "Waiting for K3S..."; sleep 5; done'
      
      echo '=== Testing K3S Installation ==='\n
      # Test functionality
      k3s --version
      k3s kubectl get nodes
      
      echo '=== Creating Test Completion Marker ==='\n
      # Create completion marker
      if systemctl is-active --quiet k3s; then
        echo "K3S Embedded Puppet module deployment completed successfully on #{ami_config['name']}" > /tmp/k3s_test_complete
        echo "Deployment type: #{deployment_type}" >> /tmp/k3s_test_complete
        echo "Installation method: Embedded Puppet module" >> /tmp/k3s_test_complete
        echo "Timestamp: $(date)" >> /tmp/k3s_test_complete
        echo "K3S service is running" >> /tmp/k3s_test_complete
        k3s --version >> /tmp/k3s_test_complete
        k3s kubectl get nodes >> /tmp/k3s_test_complete
        echo "Embedded Puppet module test: SUCCESS" >> /tmp/k3s_test_complete
      else
        echo "K3S Embedded Puppet module deployment failed on #{ami_config['name']}" > /tmp/k3s_test_complete
        echo "Deployment type: #{deployment_type}" >> /tmp/k3s_test_complete
        echo "Installation method: Embedded Puppet module" >> /tmp/k3s_test_complete
        echo "Timestamp: $(date)" >> /tmp/k3s_test_complete
        echo "K3S service failed to start" >> /tmp/k3s_test_complete
        systemctl status k3s >> /tmp/k3s_test_complete 2>&1
        echo "Embedded Puppet module test: FAILED" >> /tmp/k3s_test_complete
      fi
      
      echo '=== K3S Embedded Puppet Module Installation Complete ==='\n
      date
    SCRIPT
    
    script
  end
  
  def test_embedded_module
    puts "🧪 Testing Embedded K3S Puppet Module"
    puts "======================================"
    
    begin
      # Create temporary resources
      puts "\n📋 Creating temporary AWS resources..."
      create_temp_resources
      
      # Launch instance
      puts "\n🚀 Launching Ubuntu instance with embedded module..."
      instance_info = launch_instance('ubuntu', 'single')
      
      puts "\n🔗 Instance Details:"
      puts "  Instance ID: #{instance_info['instance_id']}"
      puts "  Public IP: #{instance_info['public_ip']}"
      puts "  Method: Embedded Puppet Module"
      
      # Wait for completion
      puts "\n⏳ Waiting for deployment to complete..."
      wait_for_deployment_completion(instance_info)
      
      puts "\n✅ Embedded module test completed!"
      
    ensure
      puts "\n🧹 Cleaning up resources..."
      cleanup_temp_resources
    end
  end
end

# Run the embedded module test
if __FILE__ == $0
  tester = EmbeddedModuleTesting.new
  tester.test_embedded_module
end 