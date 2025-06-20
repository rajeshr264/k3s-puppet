# Example: Automated Multi-node K3S Cluster - Agent Node
#
# This example demonstrates how to configure a K3S agent node that will
# automatically collect server information and tokens using Puppet's
# exported resources feature.
#
# Prerequisites:
# - PuppetDB configured for exported resources
# - Server node already configured with auto_token_sharing enabled
# - Puppet agent running on both server and agent nodes
# - Network connectivity to the server node
#
# Usage:
# Apply this configuration to your agent node(s).
# The agent will automatically discover and collect cluster information
# from the server node(s) and join the cluster.

class { 'k3s_cluster':
  ensure             => 'present',
  node_type          => 'agent',
  cluster_name       => 'production-k3s',
  auto_token_sharing => true,

  # Token collection settings
  wait_for_token     => true,   # Wait for token collection to complete
  token_timeout      => 300,    # 5 minutes timeout for token collection

  # Optional: K3S configuration options for agent nodes
  config_options     => {
    'node-label'     => [
      'node-role.kubernetes.io/worker=true',
      'environment=production',
    ],
    'kubelet-arg'    => [
      'max-pods=110',
    ],
  },
}

# Optional: Create a notification about the agent setup
notify { 'k3s_agent_automated_setup':
  message => 'K3S agent configured with automated token collection. Will join cluster automatically.',
  require => Class['k3s_cluster'],
}
