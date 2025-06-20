# @summary Manages the K3S service
#
# This class handles the K3S systemd service management including
# starting, stopping, and enabling the service.
#
class k3s_cluster::service {
  include k3s_cluster::params

  service { 'k3s':
    ensure  => running,
    enable  => true,
    require => [
      File["${k3s_cluster::params::config_dir}/config.yaml"],
    ],
  }
}
