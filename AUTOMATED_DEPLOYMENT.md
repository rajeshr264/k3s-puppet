# Automated Multi-Node K3S Deployment

This document describes the automated token sharing feature that enables fully automated multi-node K3S cluster deployments using Puppet's exported resources.

## Overview

The automated token sharing feature eliminates the manual step of copying tokens between server and agent nodes by using Puppet's exported resources mechanism. Server nodes automatically export their cluster information, and agent nodes automatically collect and use this information to join the cluster.

## Architecture

### Components

1. **Custom Resource Type** (`k3s_cluster_info`)
   - Manages cluster information as a Puppet resource
   - Handles validation of cluster parameters
   - Supports exported resource functionality

2. **Resource Provider** (`k3s_cluster_info/ruby`)
   - Reads K3S tokens from server nodes
   - Creates cluster information files for collection
   - Manages the lifecycle of cluster information

3. **Token Automation Class** (`k3s_cluster::token_automation`)
   - Orchestrates the export/collection process
   - Handles server-side token export
   - Manages agent-side token collection

4. **Collection Script** (`collect-cluster-info.sh.epp`)
   - Bash script for gathering cluster information
   - Supports both YAML and shell script formats
   - Includes timeout and retry logic

5. **Enhanced Configuration** (`k3s_cluster::config`)
   - Integrates collected tokens into K3S configuration
   - Supports both automated and manual token modes
   - Creates custom facts for cluster state

## Workflow

### Server Node Process

1. **K3S Installation**: Server installs K3S using standard process
2. **Service Startup**: K3S service starts and generates node token
3. **Token Export**: Server exports cluster information using `@@k3s_cluster_info`
4. **Fact Creation**: Server creates local facts about its cluster role

### Agent Node Process

1. **Resource Collection**: Agent collects exported `k3s_cluster_info` resources
2. **Token Gathering**: Collection script processes cluster information
3. **Fact Creation**: Agent creates facts with collected cluster details
4. **K3S Configuration**: Agent configures K3S with collected server URL and token
5. **Cluster Joining**: Agent joins cluster automatically

## Configuration Parameters

### New Parameters

- `cluster_name`: Unique identifier for the cluster (required for automation)
- `auto_token_sharing`: Enable/disable automated token sharing
- `wait_for_token`: Whether agents should wait for token collection
- `token_timeout`: Maximum time to wait for token collection (30-600 seconds)

### Usage Examples

#### Server Configuration
```puppet
class { 'k3s_cluster':
  node_type          => 'server',
  cluster_init       => true,
  cluster_name       => 'my-cluster',
  auto_token_sharing => true,
}
```

#### Agent Configuration
```puppet
class { 'k3s_cluster':
  node_type          => 'agent',
  cluster_name       => 'my-cluster',
  auto_token_sharing => true,
}
```

## Prerequisites

### PuppetDB Configuration

Exported resources require PuppetDB. Ensure your Puppet infrastructure includes:

1. **PuppetDB Server**: Running and accessible to Puppet server
2. **Puppet Server Configuration**: Connected to PuppetDB
3. **Agent Configuration**: Agents can query exported resources

Example PuppetDB configuration:
```ini
# /etc/puppetlabs/puppet/puppetdb.conf
[main]
server_urls = https://puppetdb.example.com:8081
```

### Network Requirements

- **DNS Resolution**: Nodes must resolve each other's hostnames
- **Port Access**: K3S API port (6443) must be accessible from agents to servers
- **Puppet Communication**: Standard Puppet agent-server communication

## Deployment Scenarios

### Basic Multi-Node Cluster

1. **Single Server + Multiple Agents**
   - One server node with `cluster_init => true`
   - Multiple agent nodes with same `cluster_name`

### High Availability Cluster

1. **Multiple Servers + Multiple Agents**
   - First server with `cluster_init => true`
   - Additional servers with `cluster_init => false`
   - All servers export tokens
   - Agents can connect to any available server

### Scaling Operations

1. **Adding Agents**: Simply deploy new agents with same `cluster_name`
2. **Adding Servers**: Deploy additional servers with automation enabled
3. **Replacing Nodes**: Remove old nodes, deploy new ones with same configuration

## File Locations

### Server Nodes
- Token file: `/var/lib/rancher/k3s/server/node-token`
- Export info: `/tmp/k3s_cluster_info_<cluster>_<hostname>.yaml`
- Server facts: `/etc/facter/facts.d/k3s_server_info.yaml`

### Agent Nodes
- Collection script: `/usr/local/bin/k3s-collect-cluster-info.sh`
- Collected facts: `/etc/facter/facts.d/k3s_cluster_info.yaml`
- Config facts: `/etc/facter/facts.d/k3s_config_info.yaml`

## Troubleshooting

### Common Issues

1. **Token Collection Timeout**
   ```bash
   # Check if server token is exported
   ls -la /tmp/k3s_cluster_info_*
   
   # Manually run collection script
   /usr/local/bin/k3s-collect-cluster-info.sh
   ```

2. **PuppetDB Issues**
   ```bash
   # Check exported resources
   puppet resource k3s_cluster_info
   
   # Query PuppetDB directly
   puppet query 'resources[certname,title,parameters] { type = "K3s_cluster_info" }'
   ```

3. **Network Connectivity**
   ```bash
   # Test server connectivity from agent
   telnet <server-hostname> 6443
   
   # Check DNS resolution
   nslookup <server-hostname>
   ```

### Debug Commands

```bash
# Check cluster facts on agent
cat /etc/facter/facts.d/k3s_cluster_info.yaml

# View collection script logs
journalctl -u puppet -f | grep k3s

# Check K3S service status
systemctl status k3s

# View K3S logs
journalctl -u k3s -f

# Test cluster connectivity
kubectl get nodes
```

## Security Considerations

### Token Security
- Tokens are temporarily stored in `/tmp` with restricted permissions (644)
- Facts files contain sensitive token information
- Consider encrypting PuppetDB communications

### Network Security
- K3S API communications are TLS encrypted
- Consider firewall rules for K3S ports
- Use private networks for cluster communication

### Access Control
- Limit access to Puppet facts containing tokens
- Secure PuppetDB access
- Regular token rotation (manual process)

## Limitations

1. **PuppetDB Dependency**: Requires PuppetDB for exported resources
2. **Token Rotation**: Manual token rotation not automated
3. **Network Dependencies**: Requires reliable DNS and network connectivity
4. **Timing Sensitivity**: Agents must run after servers are ready

## Best Practices

1. **Deployment Order**: Always deploy servers before agents
2. **Monitoring**: Monitor PuppetDB health and connectivity
3. **Testing**: Test automation in non-production environments first
4. **Documentation**: Document cluster names and node roles
5. **Backup**: Backup cluster tokens and certificates

## Integration with CI/CD

### Example Pipeline
```yaml
stages:
  - deploy-servers
  - wait-for-ready
  - deploy-agents
  - verify-cluster

deploy-servers:
  script:
    - puppet apply server-config.pp

wait-for-ready:
  script:
    - kubectl wait --for=condition=Ready node/server-01

deploy-agents:
  script:
    - puppet apply agent-config.pp

verify-cluster:
  script:
    - kubectl get nodes
    - kubectl get pods -A
```

## Enhanced Token Readiness Verification

The module includes comprehensive token readiness verification to ensure agents are only launched after the master server token is completely ready and validated. This prevents common timing issues where agents attempt to join with incomplete or invalid tokens.

### Verification Steps

The token readiness process includes:

1. **SSH Connectivity**: Verify connection to server node
2. **Service Status**: Confirm K3S service is active and running
3. **Node Readiness**: Wait for server node to reach "Ready" status
4. **Token Availability**: Check that token file exists and has valid content
5. **Token Format Validation**: Verify token follows K3S format (starts with 'K', 40+ characters)
6. **Authentication Testing**: Test token by performing actual API calls
7. **API Server Accessibility**: Confirm API server is responding to requests

### Automatic Sequencing

```puppet
# Server nodes export tokens only after full readiness verification
class { 'k3s_cluster':
  ensure                => 'present',
  node_type            => 'server',
  cluster_name         => 'production',
  auto_token_sharing   => true,
  token_timeout        => 300,  # Wait up to 5 minutes for token readiness
}

# Agent nodes automatically wait for validated tokens
class { 'k3s_cluster':
  ensure                => 'present', 
  node_type            => 'agent',
  cluster_name         => 'production',
  auto_token_sharing   => true,
  wait_for_token       => true,
}
```

### Manual Verification

You can manually verify token readiness using the standalone script:

```bash
# Verify server token is ready before launching agents
./ec2-scripts/verify-server-token-ready.sh <server_ip> <ssh_user> [ssh_key_path]

# Example output:
# 🎉 K3S Server Readiness Verification Complete!
# ✅ SSH connectivity: OK
# ✅ K3S service: Active  
# ✅ Node status: Ready
# ✅ Server token: Valid and authenticated
# ✅ API server: Ready and accessible
# 🚀 Server is ready for agent connections!
# TOKEN:K10abc123def456...
```

### Troubleshooting Token Issues

If token readiness verification fails:

1. **Check service logs**:
   ```bash
   sudo journalctl -u k3s --no-pager --lines=20
   ```

2. **Verify token file permissions**:
   ```bash
   sudo ls -la /var/lib/rancher/k3s/server/node-token
   sudo cat /var/lib/rancher/k3s/server/node-token
   ```

3. **Test API server manually**:
   ```bash
   sudo k3s kubectl get nodes
   sudo k3s kubectl cluster-info
   ```

4. **Check for port conflicts**:
   ```bash
   sudo netstat -tlnp | grep :6443
   sudo systemctl status k3s
   ```

This enhanced verification eliminates race conditions and ensures reliable multi-node deployments.

This automated deployment feature significantly simplifies K3S cluster management while maintaining security and reliability standards. 