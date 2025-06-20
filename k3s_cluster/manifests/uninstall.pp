# @summary Handles K3S uninstallation
#
# This class manages the complete removal of K3S including services,
# files, containers, and optional cleanup of network resources.
#
class k3s_cluster::uninstall {
  include k3s_cluster::params

  # Stop and disable the service first
  service { $k3s_cluster::params::service_name:
    ensure => stopped,
    enable => false,
  }

  # Run the official uninstall script if it exists
  exec { 'k3s_uninstall_script':
    command => $k3s_cluster::params::uninstall_script,
    path    => ['/usr/local/bin', '/usr/bin', '/bin'],
    onlyif  => "test -f ${k3s_cluster::params::uninstall_script}",
    require => Service[$k3s_cluster::params::service_name],
  }

  # Remove configuration files
  file { $k3s_cluster::params::config_dir:
    ensure  => absent,
    force   => true,
    require => Exec['k3s_uninstall_script'],
  }

  # Remove data directory
  file { $k3s_cluster::params::data_dir:
    ensure  => absent,
    force   => true,
    require => Exec['k3s_uninstall_script'],
  }

  # Remove binary and symlinks
  file { [
    $k3s_cluster::params::binary_path,
    '/usr/local/bin/kubectl',
    '/usr/local/bin/crictl',
    '/usr/local/bin/ctr',
  ]:
    ensure  => absent,
    require => Exec['k3s_uninstall_script'],
  }

  # Optional cleanup tasks based on parameters
  if $k3s_cluster::cleanup_containers {
    exec { 'cleanup_k3s_containers':
      command => 'docker system prune -af || crictl rmi --prune || true',
      path    => ['/usr/bin', '/bin', '/usr/local/bin'],
      require => Service[$k3s_cluster::params::service_name],
    }
  }

  if $k3s_cluster::cleanup_iptables {
    exec { 'cleanup_k3s_iptables':
      command => template('k3s_cluster/cleanup_iptables.sh.erb'),
      path    => ['/usr/bin', '/bin', '/sbin'],
      require => Service[$k3s_cluster::params::service_name],
    }
  }

  if $k3s_cluster::cleanup_network_interfaces {
    exec { 'cleanup_k3s_interfaces':
      command => template('k3s_cluster/cleanup_interfaces.sh.erb'),
      path    => ['/usr/bin', '/bin', '/sbin'],
      require => Service[$k3s_cluster::params::service_name],
    }
  }

  if $k3s_cluster::cleanup_mounts {
    exec { 'cleanup_k3s_mounts':
      command => template('k3s_cluster/cleanup_mounts.sh.erb'),
      path    => ['/usr/bin', '/bin', '/sbin'],
      require => Service[$k3s_cluster::params::service_name],
    }
  }
}
