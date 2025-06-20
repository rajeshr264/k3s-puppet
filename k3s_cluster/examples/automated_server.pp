# Example: Automated Multi-node K3S Cluster - Server Node
#
# This example demonstrates how to configure a K3S server node that will
# automatically export its token for agent nodes to collect using Puppet's
# exported resources feature.
#
# Prerequisites:
# - PuppetDB configured for exported resources
# - Puppet agent running on both server and agent nodes
# - Network connectivity between nodes
#
# Usage:
# Apply this configuration to your designated server node(s).
# The server will automatically export cluster information that
# agent nodes can collect and use for automated joining.

class { 'k3s_cluster':
  ensure             => 'present',
  node_type          => 'server',
  cluster_init       => true,
  cluster_name       => 'production-k3s',
  auto_token_sharing => true,

  # Server configuration
  tls_san            => [
    'k3s.example.com',
    'k3s-server.internal',
    '192.168.1.100',
    '10.0.1.100',
  ],

  # K3S configuration options
  config_options     => {
    'write-kubeconfig-mode' => '0644',
    'cluster-cidr'          => '10.42.0.0/16',
    'service-cidr'          => '10.43.0.0/16',
    'disable'               => ['traefik'],  # Disable if using external load balancer
    'node-label'            => [
      'node-role.kubernetes.io/master=true',
      'environment=production',
    ],
  },

  # Token automation settings
  token_timeout      => 300,  # 5 minutes timeout for token operations
}

# Optional: Create a notification about the server setup
notify { 'k3s_server_automated_setup':
  message => 'K3S server configured with automated token sharing. Agent nodes can now join automatically.',
  require => Class['k3s_cluster'],
}
