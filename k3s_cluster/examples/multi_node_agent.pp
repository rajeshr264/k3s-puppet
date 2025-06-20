# Example: Multi-node K3S cluster - Agent node
#
# This example creates an agent node that joins an existing cluster

class { 'k3s_cluster':
  ensure     => 'present',
  node_type  => 'agent',
  server_url => 'https://k3s-server.example.com:6443',
  token      => 'your-node-token-here',
}
