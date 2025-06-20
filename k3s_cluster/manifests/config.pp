# @summary Manages K3S configuration
#
# This class handles the configuration of K3S including config files,
# environment variables, and cluster-specific settings.
#
class k3s_cluster::config {
  include k3s_cluster::params

  # Merge default config with user-provided options
  $final_config = stdlib::merge($k3s_cluster::params::default_config, $k3s_cluster::config_options)

  # Create configuration file
  file { "${k3s_cluster::params::config_dir}/config.yaml":
    ensure  => file,
    content => stdlib::to_yaml($final_config),
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    require => File[$k3s_cluster::params::config_dir],
  }



  # Note: Environment variables are handled by the K3S installer
  # No additional environment file needed for basic installation
}
