# @summary Default parameters for K3S cluster module
#
# This class provides OS-specific default parameters for the K3S cluster module.
#
class k3s_cluster::params {
  case $facts['os']['family'] {
    'RedHat': {
      $package_manager = 'yum'
      $service_manager = 'systemd'
      $binary_path = '/usr/local/bin/k3s'
      $config_dir = '/etc/rancher/k3s'
      $data_dir = '/var/lib/rancher/k3s'
      $log_dir = '/var/log'
      $systemd_dir = '/etc/systemd/system'
      $kubeconfig_path = '/etc/rancher/k3s/k3s.yaml'
      $service_user = 'root'
      $service_group = 'root'
    }
    'Debian': {
      $package_manager = 'apt'
      $service_manager = 'systemd'
      $binary_path = '/usr/local/bin/k3s'
      $config_dir = '/etc/rancher/k3s'
      $data_dir = '/var/lib/rancher/k3s'
      $log_dir = '/var/log'
      $systemd_dir = '/etc/systemd/system'
      $kubeconfig_path = '/etc/rancher/k3s/k3s.yaml'
      $service_user = 'root'
      $service_group = 'root'
    }
    'Suse': {
      $package_manager = 'zypper'
      $service_manager = 'systemd'
      $binary_path = '/usr/local/bin/k3s'
      $config_dir = '/etc/rancher/k3s'
      $data_dir = '/var/lib/rancher/k3s'
      $log_dir = '/var/log'
      $systemd_dir = '/etc/systemd/system'
      $kubeconfig_path = '/etc/rancher/k3s/k3s.yaml'
      $service_user = 'root'
      $service_group = 'root'
    }
    default: {
      fail("Unsupported OS family: ${facts['os']['family']}")
    }
  }

  # Architecture-specific settings
  case $facts['os']['architecture'] {
    'x86_64', 'amd64': {
      $arch = 'amd64'
    }
    'aarch64', 'arm64': {
      $arch = 'arm64'
    }
    'armv7l': {
      $arch = 'arm'
    }
    default: {
      fail("Unsupported architecture: ${facts['os']['architecture']}")
    }
  }

  # Default configuration
  $default_config = {
    'write-kubeconfig-mode' => '0644',
    'disable-cloud-controller' => true,
  }

  # Service configuration
  $service_name = 'k3s'
  $service_file = "${systemd_dir}/${service_name}.service"
  $env_file = "${systemd_dir}/${service_name}.service.env"

  # Installation URLs
  $install_script_url = 'https://get.k3s.io'
  $binary_base_url = 'https://github.com/k3s-io/k3s/releases/download'

  # Uninstall script paths
  $uninstall_script = '/usr/local/bin/k3s-uninstall.sh'
  $agent_uninstall_script = '/usr/local/bin/k3s-agent-uninstall.sh'
}
