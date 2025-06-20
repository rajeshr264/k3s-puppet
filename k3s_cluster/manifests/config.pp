# @summary Manages K3S configuration
#
# This class handles the configuration of K3S including config files,
# environment variables, and cluster-specific settings.
#
class k3s_cluster::config {
  include k3s_cluster::params

  # Create configuration directory
  file { $k3s_cluster::params::config_dir:
    ensure => directory,
    mode   => '0755',
    owner  => 'root',
    group  => 'root',
  }

  # Create data directory
  file { $k3s_cluster::params::data_dir:
    ensure => directory,
    mode   => '0755',
    owner  => 'root',
    group  => 'root',
  }

  # Determine configuration based on automated token sharing
  if $k3s_cluster::auto_token_sharing and $k3s_cluster::node_type == 'agent' {
    # Agent with automated token sharing - use collected token from facts
    if $facts['k3s_server_url'] and $facts['k3s_server_token'] {
      $final_config = $k3s_cluster::config + {
        'server' => $facts['k3s_server_url'],
        'token'  => $facts['k3s_server_token'],
      }
    } else {
      # Fallback to manual configuration if facts not available yet
      $final_config = $k3s_cluster::config
    }
  } else {
    # Manual configuration or server node
    $final_config = $k3s_cluster::config
  }

  # Create configuration file
  file { "${k3s_cluster::params::config_dir}/config.yaml":
    ensure  => file,
    content => to_yaml($final_config),
    mode    => '0644',
    owner   => 'root',
    group   => 'root',
    require => File[$k3s_cluster::params::config_dir],
    notify  => Service[$k3s_cluster::params::service_name],
  }

  # Create additional facts about configuration
  file { '/etc/facter/facts.d/k3s_config.yaml':
    ensure  => file,
    content => epp('k3s_cluster/k3s_facts.yaml.epp', {
      'config_data' => $final_config,
      'node_type'   => $k3s_cluster::node_type,
    }),
    mode    => '0644',
    owner   => 'root',
    group   => 'root',
    require => File['/etc/facter/facts.d'],
  }

  # Note: Environment variables are handled by the K3S installer
  # No additional environment file needed for basic installation
}
