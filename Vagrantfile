# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # Use Ubuntu 22.04 LTS
  config.vm.box = "ubuntu/jammy64"
  
  # Configure VM resources
  config.vm.provider "virtualbox" do |vb|
    vb.memory = "2048"
    vb.cpus = 2
    vb.name = "k3s-test-node"
  end
  
  # Configure networking
  config.vm.network "private_network", ip: "192.168.56.10"
  config.vm.hostname = "k3s-test"
  
  # Sync the module directory
  config.vm.synced_folder ".", "/vagrant"
  
  # Provisioning script
  config.vm.provision "shell", inline: <<-SHELL
    # Update system
    apt-get update
    
    # Install Puppet
    wget https://apt.puppet.com/puppet8-release-jammy.deb
    dpkg -i puppet8-release-jammy.deb
    apt-get update
    apt-get install -y puppet-agent
    
    # Add Puppet to PATH
    echo 'export PATH="/opt/puppetlabs/bin:$PATH"' >> /home/vagrant/.bashrc
    export PATH="/opt/puppetlabs/bin:$PATH"
    
    # Install required gems
    /opt/puppetlabs/puppet/bin/gem install r10k
    
    # Create module directory
    mkdir -p /etc/puppetlabs/code/environments/production/modules
    
    # Copy module
    cp -r /vagrant /etc/puppetlabs/code/environments/production/modules/k3s_cluster
    
    echo "=== Vagrant VM Ready for K3S Testing ==="
    echo "To test:"
    echo "1. vagrant ssh"
    echo "2. sudo puppet apply -e \"include k3s_cluster\""
    echo "3. kubectl get nodes"
  SHELL
end 