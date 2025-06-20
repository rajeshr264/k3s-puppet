# Example: Single Node K3S Cluster
# This example shows how to deploy a single-node K3S cluster

class { 'k3s_cluster':
  ensure             => 'present',
  node_type          => 'server',
  cluster_init       => true,
  installation_method => 'script',
  version            => 'stable',
}
