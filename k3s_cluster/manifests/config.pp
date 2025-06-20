# @summary Manages K3S configuration
#
# This class handles the configuration of K3S including config files,
# environment variables, and cluster-specific settings.
#
class k3s_cluster::config {
  include k3s_cluster::params

  # Merge default config with user-provided options
  $final_config = merge($k3s_cluster::params::default_config, $k3s_cluster::config_options)

  # Create configuration file
  file { "${k3s_cluster::params::config_dir}/config.yaml":
    ensure  => file,
    content => to_yaml($final_config),
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    require => File[$k3s_cluster::params::config_dir],
  }

  # Create environment file for systemd service
  $env_vars = {
    'K3S_NODE_NAME' => $facts['networking']['hostname'],
  }

  # Add server-specific environment variables
  if $k3s_cluster::node_type == 'server' {
    if $k3s_cluster::cluster_init {
      $server_env = merge($env_vars, {
        'K3S_CLUSTER_INIT' => 'true',
      })
    } else {
      $server_env = $env_vars
    }
    $final_env = $server_env
  } else {
    # Agent-specific environment variables
    $agent_env = merge($env_vars, {
      'K3S_URL'   => $k3s_cluster::server_url,
      'K3S_TOKEN' => $k3s_cluster::token,
    })
    $final_env = $agent_env
  }

  # Create environment file
  file { $k3s_cluster::params::env_file:
    ensure  => file,
    content => template('k3s_cluster/service.env.erb'),
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
  }
}
