# Example: Multi-node K3S cluster - Server node
#
# This example creates the first server node in a multi-node cluster

class { 'k3s_cluster':
  ensure         => 'present',
  node_type      => 'server',
  cluster_init   => true,
  tls_san        => [
    'k3s.example.com',
    '192.168.1.100',
  ],
  config_options => {
    'write-kubeconfig-mode' => '0644',
    'cluster-cidr'          => '10.42.0.0/16',
    'service-cidr'          => '10.43.0.0/16',
    'disable'               => ['traefik'],
  },
}
