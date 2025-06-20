# @summary Manages the K3S service
#
# This class handles the K3S systemd service management including
# starting, stopping, and enabling the service.
#
class k3s_cluster::service {
  include k3s_cluster::params

  # Determine service name based on node type
  $service_name = $k3s_cluster::node_type ? {
    'server' => $k3s_cluster::params::server_service_name,
    'agent'  => $k3s_cluster::params::agent_service_name,
  }

  # Manage the K3S service
  service { $service_name:
    ensure     => $k3s_cluster::service_ensure,
    enable     => $k3s_cluster::service_enable,
    hasstatus  => true,
    hasrestart => true,
    provider   => $k3s_cluster::params::service_provider,
    require    => File[$k3s_cluster::config_file],
  }

  # For server nodes, fix kubeconfig permissions after service starts
  if $k3s_cluster::node_type == 'server' {
    exec { 'fix_kubeconfig_permissions':
      command     => '/usr/local/bin/fix-k3s-kubeconfig-permissions.sh',
      path        => ['/bin', '/usr/bin', '/usr/local/bin'],
      refreshonly => true,
      subscribe   => Service[$service_name],
      require     => File['/usr/local/bin/fix-k3s-kubeconfig-permissions.sh'],
    }

    # Wait for kubeconfig file to be created
    exec { 'wait_for_kubeconfig':
      command => 'timeout 60 bash -c "until [ -f /etc/rancher/k3s/k3s.yaml ]; do sleep 2; done"',
      path    => ['/bin', '/usr/bin'],
      creates => '/etc/rancher/k3s/k3s.yaml',
      require => Service[$service_name],
      before  => Exec['fix_kubeconfig_permissions'],
    }
  }

  # Health check to ensure K3S is responding
  exec { 'k3s_health_check':
    command   => $k3s_cluster::node_type ? {
      'server' => 'k3s kubectl get nodes',
      'agent'  => 'systemctl is-active k3s-agent',
    },
    path      => ['/bin', '/usr/bin', '/usr/local/bin'],
    tries     => 5,
    try_sleep => 10,
    require   => Service[$service_name],
  }

  # Create a fact file with cluster information
  file { '/etc/facter/facts.d/k3s.yaml':
    ensure  => file,
    content => epp('k3s_cluster/k3s_facts.yaml.epp', {
      'node_type'     => $k3s_cluster::node_type,
      'version'       => $k3s_cluster::version,
      'service_name'  => $service_name,
      'config_file'   => $k3s_cluster::config_file,
    }),
    mode    => '0644',
    owner   => 'root',
    group   => 'root',
    require => Service[$service_name],
  }

  # Ensure /etc/facter/facts.d directory exists
  file { '/etc/facter':
    ensure => directory,
    mode   => '0755',
    owner  => 'root',
    group  => 'root',
  }

  file { '/etc/facter/facts.d':
    ensure  => directory,
    mode    => '0755',
    owner   => 'root',
    group   => 'root',
    require => File['/etc/facter'],
  }
}
