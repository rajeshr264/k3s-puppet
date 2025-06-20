#!/bin/bash
# Single Node K3S Test - User Data Script
# This script automatically sets up a single-node K3S cluster using the Puppet module

set -e

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/k3s-setup.log
}

log "Starting K3S single node setup..."

# Update system
log "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install required packages
log "Installing required packages..."
apt-get install -y curl wget git python3-yaml

# Install Puppet
log "Installing Puppet..."
wget -q https://apt.puppet.com/puppet8-release-jammy.deb
dpkg -i puppet8-release-jammy.deb
apt-get update
apt-get install -y puppet-agent

# Add Puppet to PATH
export PATH="/opt/puppetlabs/bin:$PATH"
echo 'export PATH="/opt/puppetlabs/bin:$PATH"' >> /root/.bashrc
echo 'export PATH="/opt/puppetlabs/bin:$PATH"' >> /home/ubuntu/.bashrc

# Create module directory
log "Setting up Puppet module directory..."
mkdir -p /etc/puppetlabs/code/environments/production/modules

# For testing purposes, we'll create the module content directly
# In a real scenario, you would clone from your Git repository
log "Setting up K3S Puppet module..."
cd /tmp

# Clone your repository (replace with actual repository URL)
# git clone https://github.com/your-username/k3s-puppet.git
# cp -r k3s-puppet/k3s_cluster /etc/puppetlabs/code/environments/production/modules/

# For now, create a minimal module structure for testing
mkdir -p /etc/puppetlabs/code/environments/production/modules/k3s_cluster/{manifests,templates,lib/puppet/type,lib/puppet/provider/k3s_cluster_info}

# Create basic init.pp for single node testing
cat > /etc/puppetlabs/code/environments/production/modules/k3s_cluster/manifests/init.pp << 'EOF'
class k3s_cluster (
  Enum['present', 'absent'] $ensure = 'present',
  Enum['server', 'agent'] $node_type = 'server',
  String $version = 'v1.33.1+k3s1',
  Hash $config_options = {},
) {
  
  case $ensure {
    'present': {
      # Install K3S using the official script with specific version
      exec { 'install_k3s':
        command => "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${version} sh -",
        path    => ['/bin', '/usr/bin'],
        creates => '/usr/local/bin/k3s',
        timeout => 300,
      }
      
      # Ensure K3S service is running
      service { 'k3s':
        ensure  => running,
        enable  => true,
        require => Exec['install_k3s'],
      }
      
      # Create config directory
      file { '/etc/rancher/k3s':
        ensure => directory,
        mode   => '0755',
        owner  => 'root',
        group  => 'root',
      }
      
      # Create config file if options provided
      if !empty($config_options) {
        file { '/etc/rancher/k3s/config.yaml':
          ensure  => file,
          content => to_yaml($config_options),
          mode    => '0644',
          owner   => 'root',
          group   => 'root',
          require => File['/etc/rancher/k3s'],
          notify  => Service['k3s'],
        }
      }
    }
    
    'absent': {
      # Uninstall K3S
      exec { 'uninstall_k3s':
        command => '/usr/local/bin/k3s-uninstall.sh',
        path    => ['/bin', '/usr/bin'],
        onlyif  => 'test -f /usr/local/bin/k3s-uninstall.sh',
      }
    }
  }
}
EOF

# Apply K3S configuration
log "Applying K3S Puppet configuration..."
puppet apply -e "class { 'k3s_cluster': ensure => 'present', version => 'v1.33.1+k3s1' }" --detailed-exitcodes

# Wait for K3S to be ready
log "Waiting for K3S to be ready..."
timeout 120 bash -c 'until k3s kubectl get nodes >/dev/null 2>&1; do sleep 5; done'

# Set up kubectl access for ubuntu user
log "Setting up kubectl access..."
mkdir -p /home/ubuntu/.kube
cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config
chmod 600 /home/ubuntu/.kube/config

# Install kubectl for easier testing
log "Installing kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Create test completion marker
log "Creating completion marker..."
echo "K3S single node installation completed at $(date)" > /var/log/k3s-test-complete.log
echo "Node status:" >> /var/log/k3s-test-complete.log
k3s kubectl get nodes >> /var/log/k3s-test-complete.log

# Test basic functionality
log "Testing basic K3S functionality..."
k3s kubectl create deployment test-nginx --image=nginx || true
k3s kubectl get pods

log "K3S single node setup complete!"
log "You can now SSH to the instance and run: kubectl get nodes" 