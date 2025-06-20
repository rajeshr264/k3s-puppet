# Example: Complete Automated Multi-node K3S Cluster Deployment
#
# This example demonstrates a complete automated multi-node K3S cluster
# deployment using Puppet's exported resources for token sharing.
#
# This example shows how to configure:
# - Primary server node (cluster initialization)
# - Additional server nodes (HA setup)
# - Multiple agent/worker nodes
#
# Prerequisites:
# - PuppetDB configured for exported resources
# - Puppet agent running on all nodes
# - Network connectivity between all nodes
# - DNS resolution or /etc/hosts entries for server names

# =============================================================================
# PRIMARY SERVER NODE CONFIGURATION
# =============================================================================
# Apply this configuration to your first/primary server node
# This node will initialize the cluster and export tokens

node 'k3s-server-01.example.com' {
  class { 'k3s_cluster':
    ensure             => 'present',
    node_type          => 'server',
    cluster_init       => true,                    # Initialize new cluster
    cluster_name       => 'production-k3s',
    auto_token_sharing => true,

    # High-availability configuration
    tls_san            => [
      'k3s.example.com',                          # Load balancer FQDN
      'k3s-api.internal',                         # Internal API endpoint
      '192.168.1.100',                            # Load balancer IP
      '192.168.1.101',                            # Server 1 IP
      '192.168.1.102',                            # Server 2 IP
      '192.168.1.103',                            # Server 3 IP
    ],

    # Production K3S configuration
    config_options     => {
      'write-kubeconfig-mode' => '0644',
      'cluster-cidr'          => '10.42.0.0/16',
      'service-cidr'          => '10.43.0.0/16',
      'disable'               => ['traefik', 'servicelb'],  # Use external LB
      'node-label'            => [
        'node-role.kubernetes.io/control-plane=true',
        'node-role.kubernetes.io/master=true',
        'environment=production',
        'cluster=production-k3s',
      ],
      'kube-apiserver-arg'    => [
        'audit-log-path=/var/log/k3s-audit.log',
        'audit-log-maxage=30',
        'audit-log-maxbackup=10',
        'audit-log-maxsize=100',
      ],
    },

    token_timeout      => 600,  # 10 minutes for initial setup
  }
}

# =============================================================================
# ADDITIONAL SERVER NODES CONFIGURATION (for HA)
# =============================================================================
# Apply this configuration to additional server nodes for high availability

node /^k3s-server-0[23]\.example\.com$/ {
  class { 'k3s_cluster':
    ensure             => 'present',
    node_type          => 'server',
    cluster_init       => false,                   # Join existing cluster
    cluster_name       => 'production-k3s',
    auto_token_sharing => true,

    # Use the same TLS SAN configuration as primary
    tls_san            => [
      'k3s.example.com',
      'k3s-api.internal',
      '192.168.1.100',
      '192.168.1.101',
      '192.168.1.102',
      '192.168.1.103',
    ],

    # Same configuration as primary server
    config_options     => {
      'write-kubeconfig-mode' => '0644',
      'cluster-cidr'          => '10.42.0.0/16',
      'service-cidr'          => '10.43.0.0/16',
      'disable'               => ['traefik', 'servicelb'],
      'node-label'            => [
        'node-role.kubernetes.io/control-plane=true',
        'node-role.kubernetes.io/master=true',
        'environment=production',
        'cluster=production-k3s',
      ],
      'kube-apiserver-arg'    => [
        'audit-log-path=/var/log/k3s-audit.log',
        'audit-log-maxage=30',
        'audit-log-maxbackup=10',
        'audit-log-maxsize=100',
      ],
    },

    wait_for_token     => true,
    token_timeout      => 300,
  }
}

# =============================================================================
# WORKER/AGENT NODES CONFIGURATION
# =============================================================================
# Apply this configuration to worker nodes

node /^k3s-worker-\d+\.example\.com$/ {
  class { 'k3s_cluster':
    ensure             => 'present',
    node_type          => 'agent',
    cluster_name       => 'production-k3s',
    auto_token_sharing => true,

    # Worker node specific configuration
    config_options     => {
      'node-label'     => [
        'node-role.kubernetes.io/worker=true',
        'environment=production',
        'cluster=production-k3s',
        "worker-pool=${facts['networking']['hostname']}",
      ],
      'kubelet-arg'    => [
        'max-pods=110',
        'cluster-dns=10.43.0.10',
        'resolv-conf=/etc/resolv.conf',
      ],
    },

    wait_for_token     => true,
    token_timeout      => 300,
  }
}

# =============================================================================
# SPECIALIZED WORKER NODES (e.g., GPU nodes, storage nodes)
# =============================================================================
# Apply this configuration to specialized worker nodes

node /^k3s-gpu-\d+\.example\.com$/ {
  class { 'k3s_cluster':
    ensure             => 'present',
    node_type          => 'agent',
    cluster_name       => 'production-k3s',
    auto_token_sharing => true,

    # GPU worker node specific configuration
    config_options     => {
      'node-label'     => [
        'node-role.kubernetes.io/worker=true',
        'environment=production',
        'cluster=production-k3s',
        'hardware=gpu',
        'nvidia.com/gpu=true',
      ],
      'kubelet-arg'    => [
        'max-pods=50',  # Fewer pods for GPU workloads
        'feature-gates=DevicePlugins=true',
      ],
    },

    wait_for_token     => true,
    token_timeout      => 300,
  }
}

# =============================================================================
# DEPLOYMENT WORKFLOW
# =============================================================================
#
# 1. Deploy primary server first:
#    puppet apply -e "include k3s_cluster" on k3s-server-01
#
# 2. Wait for primary server to be ready (check with kubectl get nodes)
#
# 3. Deploy additional servers (if HA is desired):
#    puppet apply -e "include k3s_cluster" on k3s-server-02, k3s-server-03
#
# 4. Deploy worker nodes:
#    puppet apply -e "include k3s_cluster" on all k3s-worker-* nodes
#
# 5. Verify cluster:
#    kubectl get nodes
#    kubectl get pods -A
#
# =============================================================================
# TROUBLESHOOTING
# =============================================================================
#
# Check token collection status:
#   cat /etc/facter/facts.d/k3s_cluster_info.yaml
#
# Check exported resources:
#   puppet resource k3s_cluster_info
#
# Manual token collection:
#   /usr/local/bin/k3s-collect-cluster-info.sh
#
# Check cluster status:
#   systemctl status k3s
#   journalctl -u k3s -f
#
# =============================================================================
