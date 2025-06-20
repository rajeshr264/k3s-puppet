# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2024-12-19

### Added

#### Core Features
- **Complete K3S Installation**: Support for both script-based and binary installation methods
- **Multi-Node Support**: Full support for server and agent node configurations
- **High Availability**: Embedded etcd and external datastore support
- **Comprehensive Uninstallation**: Complete cleanup including containers, iptables, and mount points

#### Installation Methods
- **Script Installation**: Using official K3S installation script with environment variable support
- **Binary Installation**: Direct binary download with systemd service creation
- **Version Control**: Support for specific K3S version installation
- **Air-Gap Support**: Binary installation method supports air-gapped environments

#### Configuration Management
- **YAML Configuration**: Complete config.yaml management with merge capabilities
- **Environment Variables**: Systemd service environment file management
- **TLS SAN Support**: Additional Subject Alternative Names for certificates
- **Custom Parameters**: Extensive configuration options support

#### Node Types
- **Server Nodes**: Full server configuration with cluster initialization
- **Agent Nodes**: Worker node configuration with server URL and token
- **Cluster Initialization**: First server node cluster bootstrap support
- **Multi-Server**: Additional server nodes for high availability

#### Security Features
- **Permission Management**: Proper file and directory permissions
- **Token Management**: Secure token handling for node joining
- **TLS Configuration**: Certificate management and SAN entries
- **Service Security**: Systemd service security configurations

#### Uninstallation Features
- **Complete Removal**: All K3S components and files
- **Container Cleanup**: Optional container and image removal
- **Network Cleanup**: Network interface and iptables rule removal
- **Mount Cleanup**: Cleanup of K3S-related mount points
- **Force Uninstall**: Forced removal for troubleshooting scenarios

#### Platform Support
- **RedHat Family**: CentOS 7/8/9, RHEL 7/8/9, Rocky 8, AlmaLinux 8
- **Debian Family**: Ubuntu 18.04/20.04/22.04, Debian 10/11/12
- **SUSE Family**: SLES 15
- **Fedora**: Fedora 40
- **Architecture Support**: x86_64, ARM64, ARM

#### Testing & Quality
- **Comprehensive Unit Tests**: 71+ unit tests covering all scenarios
- **PDK Compliance**: Built using Puppet Development Kit
- **Multi-OS Testing**: Tested across all supported operating systems
- **Edge Case Coverage**: Extensive error handling and validation

#### Documentation
- **Complete README**: Comprehensive usage examples and documentation
- **Parameter Reference**: Detailed parameter documentation
- **Usage Examples**: Single-node, multi-node, and HA examples
- **Troubleshooting**: Common issues and solutions

#### Dependencies
- **puppetlabs/stdlib**: >= 4.25.0 < 10.0.0
- **puppet/archive**: >= 4.6.0 < 8.0.0

### Technical Details

#### Classes
- `k3s_cluster`: Main interface class with comprehensive parameter validation
- `k3s_cluster::params`: OS-specific default parameters
- `k3s_cluster::install`: Installation logic for both script and binary methods
- `k3s_cluster::config`: Configuration file and environment management
- `k3s_cluster::service`: Systemd service management and health checks
- `k3s_cluster::uninstall`: Complete uninstallation with cleanup options

#### Templates
- `k3s.service.epp`: Systemd service file template
- `service.env.epp`: Service environment variables template
- `fix-kubeconfig-permissions.sh.epp`: Kubeconfig permission fix script
- `k3s_facts.yaml.epp`: Custom facts template
- `cleanup_interfaces.sh.erb`: Network interface cleanup script
- `cleanup_iptables.sh.erb`: Iptables rules cleanup script
- `cleanup_mounts.sh.erb`: Mount points cleanup script

#### Facts
- Custom facts for K3S installation status and configuration
- Node type and version information
- Service status and configuration paths

### Requirements
- Puppet >= 7.24 < 9.0.0
- Systemd-based operating systems
- Internet access for script installation (unless using binary method)

[0.1.0]: https://github.com/k3s-puppet/k3s-puppet/releases/tag/v0.1.0 