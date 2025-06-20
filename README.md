# K3S Puppet Module

Puppet module for deploying K3S on one or more nodes with comprehensive automation and testing capabilities.

## Mission

This module automates the deployment and configuration of K3S (Lightweight Kubernetes) clusters across multiple operating systems, providing a robust foundation for container orchestration in diverse environments.

## Features

### Core Functionality
- **Single-node and multi-node** K3S deployments
- **Automated token sharing** between server and agent nodes
- **Complete lifecycle management** (install, configure, uninstall)
- **Cross-platform support** for major Linux distributions
- **High availability** configurations with external datastores

### Advanced Capabilities
- **Binary and script-based** installation methods
- **Custom configuration** via YAML files
- **TLS certificate management** with SAN support
- **Network policy** and CNI customization
- **Comprehensive cleanup** with container and network removal

### Testing & Validation
- **Multi-OS testing** on AWS EC2 (Ubuntu, RHEL, openSUSE, SLES, Debian)
- **Test-Driven Development** approach with comprehensive unit tests
- **Automated infrastructure** provisioning and cleanup
- **Cost-aware testing** with usage reporting

## Quick Start

### Prerequisites
- Puppet 8.x
- Supported OS: Ubuntu 22.04+, RHEL 9+, openSUSE Leap 15.5+, SLES 15 SP5+, Debian 12+
- Network connectivity for K3S installation

### Basic Installation

```puppet
# Single node deployment
class { 'k3s_cluster':
  ensure => 'present',
}

# Server node with cluster initialization
class { 'k3s_cluster':
  ensure       => 'present',
  node_type    => 'server',
  cluster_init => true,
}

# Agent node joining existing cluster
class { 'k3s_cluster':
  ensure     => 'present',
  node_type  => 'agent',
  server_url => 'https://k3s-server:6443',
  token      => 'your-cluster-token',
}
```

## Multi-OS Testing on AWS EC2

### Prerequisites
```bash
# Authenticate with AWS
aws-azure-login

# Set up your AWS configuration (optional - defaults provided)
export AWS_SECURITY_GROUP="your-security-group"
export AWS_KEY_NAME="your-key-name" 
export AWS_KEY_PATH="$HOME/keys/your-key-name.pem"
export AWS_REGION="us-west-2"

# Ensure your key exists
ls $AWS_KEY_PATH
```

### Test Single Node on All Operating Systems
```bash
# Test all supported OSes (Ubuntu, RHEL, openSUSE, SLES, Debian)
./ec2-scripts/k3s-multi-os-testing.sh single

# Test specific OS
./ec2-scripts/k3s-multi-os-testing.sh single ubuntu
./ec2-scripts/k3s-multi-os-testing.sh single rhel
```

### Test Multi-Node Deployment
```bash
# Multi-node with automated token sharing
./ec2-scripts/k3s-multi-os-testing.sh multi
```

### Manage Test Infrastructure
```bash
# List running test instances
./ec2-scripts/k3s-multi-os-testing.sh list

# Generate test report
./ec2-scripts/k3s-multi-os-testing.sh report

# Cleanup all test instances
./ec2-scripts/k3s-multi-os-testing.sh cleanup
```

## Automated Multi-Node Deployment

The module supports fully automated multi-node deployments using Puppet's exported resources:

```puppet
# Server node - exports cluster information
class { 'k3s_cluster':
  ensure             => 'present',
  node_type          => 'server',
  cluster_init       => true,
  cluster_name       => 'production',
  auto_token_sharing => true,
}

# Agent nodes - automatically collect server information
class { 'k3s_cluster':
  ensure             => 'present',
  node_type          => 'agent',
  cluster_name       => 'production',
  auto_token_sharing => true,
  wait_for_token     => true,
}
```

## Advanced Configuration

### High Availability Setup
```puppet
class { 'k3s_cluster':
  ensure             => 'present',
  node_type          => 'server',
  cluster_init       => true,
  datastore_endpoint => 'mysql://user:pass@host:3306/k3s',
  tls_san            => ['k3s.example.com', '192.168.1.100'],
  config_options     => {
    'write-kubeconfig-mode' => '0644',
    'disable'               => ['traefik'],
    'cluster-cidr'          => '10.42.0.0/16',
    'service-cidr'          => '10.43.0.0/16',
  },
}
```

### Custom Configuration with YAML
```puppet
class { 'k3s_cluster':
  ensure      => 'present',
  config_file => '/etc/rancher/k3s/config.yaml',
  config_options => {
    'write-kubeconfig-mode' => '0644',
    'tls-san'               => ['k3s.example.com'],
    'disable'               => ['traefik', 'metrics-server'],
    'node-label'            => ['environment=production'],
  },
}
```

### Complete Uninstallation
```puppet
class { 'k3s_cluster':
  ensure             => 'absent',
  cleanup_containers => true,
  cleanup_iptables   => true,
  cleanup_interfaces => true,
  force_uninstall    => true,
}
```

## Parameters

### Core Parameters
- **`ensure`** - Whether K3S should be present or absent (default: 'present')
- **`node_type`** - Type of node: 'server' or 'agent' (default: 'server')
- **`installation_method`** - Installation method: 'script' or 'binary' (default: 'script')
- **`version`** - Specific K3S version to install (default: 'latest')

### Cluster Configuration
- **`cluster_init`** - Initialize a new cluster on server nodes (default: false)
- **`server_url`** - URL of K3S server for agent nodes
- **`token`** - Cluster token for authentication
- **`datastore_endpoint`** - External datastore URL for HA

### Automated Token Sharing
- **`cluster_name`** - Unique identifier for the cluster
- **`auto_token_sharing`** - Enable automatic token sharing (default: false)
- **`wait_for_token`** - Wait for server token on agent nodes (default: false)
- **`token_timeout`** - Timeout for token collection in seconds (default: 300)

### Network & Security
- **`tls_san`** - Additional Subject Alternative Names for TLS certificates
- **`config_options`** - Hash of additional K3S configuration options
- **`config_file`** - Path to K3S configuration file

### Cleanup Options
- **`cleanup_containers`** - Remove containers during uninstall (default: false)
- **`cleanup_iptables`** - Clean iptables rules during uninstall (default: false)
- **`cleanup_interfaces`** - Remove network interfaces during uninstall (default: false)
- **`force_uninstall`** - Force kill processes during uninstall (default: false)

## File Structure

```
k3s-puppet/
├── k3s_cluster/                    # Main Puppet module
│   ├── manifests/                  # Puppet manifests
│   │   ├── init.pp                 # Main class
│   │   ├── params.pp               # OS-specific parameters
│   │   ├── install.pp              # Installation logic
│   │   ├── config.pp               # Configuration management
│   │   ├── service.pp              # Service management
│   │   ├── uninstall.pp            # Cleanup and removal
│   │   └── token_automation.pp     # Automated token sharing
│   ├── templates/                  # ERB/EPP templates
│   │   ├── k3s.service.epp         # Systemd service
│   │   ├── service.env.epp         # Environment variables
│   │   ├── collect-cluster-info.sh.epp # Token collection script
│   │   └── cleanup_*.sh.erb        # Cleanup scripts
│   ├── lib/                        # Puppet extensions
│   │   └── puppet/
│   │       ├── type/               # Custom resource types
│   │       └── provider/           # Resource providers
│   ├── examples/                   # Usage examples
│   │   ├── single_node.pp          # Basic single node
│   │   ├── multi_node_*.pp         # Multi-node configurations
│   │   └── automated_*.pp          # Automated deployment examples
│   └── spec/                       # Unit tests
├── ec2-scripts/                    # AWS testing automation
│   ├── k3s-multi-os-testing.sh     # Multi-OS testing script
│   ├── aws_ec2_testing.rb          # Testing library
│   ├── ec2-test-automation.sh      # Infrastructure automation
│   └── single-node-userdata.sh     # User data templates
├── spec/                           # Integration tests
│   └── aws_ec2_testing_spec.rb     # AWS testing unit tests
├── test_single_node.sh             # Local testing script
├── Vagrantfile                     # VM testing environment
├── AWS_CONFIGURATION.md            # AWS setup and configuration guide
├── AUTOMATED_DEPLOYMENT.md         # Automation guide
├── AWS_EC2_TESTING.md              # AWS testing guide
├── EC2_QUICKSTART.md               # Quick start guide
└── README.md                       # This file
```

## Troubleshooting

### Installation Issues

#### curl Command Failures
If you encounter errors like `'curl -sfL https://get.k3s.io | sh -' returned 1`, the module automatically uses `wget` as a fallback. This is handled transparently, but you can force the binary installation method if needed:

```puppet
class { 'k3s_cluster':
  ensure              => 'present',
  installation_method => 'binary',  # Use binary instead of script
}
```

#### Directory Permission Issues
If you see "Cannot create /etc/rancher/k3s; parent directory /etc/rancher does not exist", ensure you're using the latest version of the module. This issue was resolved in recent versions.

#### Network Connectivity
Ensure the target nodes have internet access to download K3S binaries. For air-gapped installations, use the binary method with a local mirror.

## Testing

### Unit Tests
```bash
cd k3s_cluster
bundle install
bundle exec rake spec
```

### Multi-OS Integration Tests
```bash
# Test all supported operating systems
./ec2-scripts/k3s-multi-os-testing.sh single

# Test specific deployment scenarios
./ec2-scripts/k3s-multi-os-testing.sh single ubuntu
```

### Local Testing
```bash
# Test with Vagrant
vagrant up
vagrant ssh

# Test with local script
./test_single_node.sh
```

## Supported Operating Systems

### Primary Support
- **Ubuntu 22.04 LTS** - Full feature support
- **Red Hat Enterprise Linux 9** - Full feature support
- **openSUSE Leap 15.5** - Full feature support
- **SUSE Linux Enterprise Server 15 SP5** - Full feature support
- **Debian 12 (Bookworm)** - Full feature support

### Architecture Support
- **x86_64** - Primary support
- **ARM64** - Basic support (limited testing)

## Dependencies

### Puppet Modules
- **puppetlabs/stdlib** (>= 6.0.0)
- **puppet/archive** (>= 4.0.0) - For binary installations

### System Requirements
- **Memory**: Minimum 512MB, recommended 1GB+
- **CPU**: Minimum 1 core, recommended 2+ cores
- **Disk**: Minimum 2GB free space
- **Network**: Internet access for installation

## License

Licensed under the Apache License, Version 2.0. See LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality (TDD approach)
4. Implement the feature
5. Ensure all tests pass
6. Submit a pull request

## Support

- **AWS Configuration**: See AWS_CONFIGURATION.md for environment variable setup
- **Documentation**: See AUTOMATED_DEPLOYMENT.md for detailed automation guide
- **AWS Testing**: See AWS_EC2_TESTING.md for comprehensive testing instructions
- **Quick Start**: See EC2_QUICKSTART.md for rapid deployment guide
- **Issues**: Submit via GitHub issues with detailed reproduction steps
