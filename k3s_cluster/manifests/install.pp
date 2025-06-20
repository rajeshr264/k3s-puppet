# @summary Handles K3S installation
#
# This class manages the installation of K3S using either the official script
# or binary download method.
#
class k3s_cluster::install {
  include k3s_cluster::params

  # Create necessary directories
  file { '/etc/rancher':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  file { $k3s_cluster::params::config_dir:
    ensure  => directory,
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    require => File['/etc/rancher'],
  }

  file { '/var/lib/rancher':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  file { $k3s_cluster::params::data_dir:
    ensure  => directory,
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    require => File['/var/lib/rancher'],
  }

  case $k3s_cluster::installation_method {
    'script': {
      # Install using the official K3S installation script
      exec { 'install_k3s':
        command     => "curl -sfL ${k3s_cluster::params::install_script_url} | sh -",
        path        => ['/usr/bin', '/bin', '/usr/local/bin'],
        creates     => $k3s_cluster::params::binary_path,
        environment => [
          "INSTALL_K3S_VERSION=${k3s_cluster::version}",
          "INSTALL_K3S_EXEC=${k3s_cluster::node_type}",
        ],
        timeout     => 300,
        require     => File[$k3s_cluster::params::config_dir],
      }
    }
    'binary': {
      # Install using binary download
      $download_url = "${k3s_cluster::params::binary_base_url}/${k3s_cluster::version}/k3s"
      
      archive { '/tmp/k3s':
        source       => $download_url,
        extract      => false,
        cleanup      => false,
        require      => File[$k3s_cluster::params::config_dir],
      }

      file { $k3s_cluster::params::binary_path:
        ensure  => file,
        source  => '/tmp/k3s',
        owner   => 'root',
        group   => 'root',
        mode    => '0755',
        require => Archive['/tmp/k3s'],
      }

      # Create symlinks
      file { '/usr/local/bin/kubectl':
        ensure  => link,
        target  => $k3s_cluster::params::binary_path,
        require => File[$k3s_cluster::params::binary_path],
      }

      file { '/usr/local/bin/crictl':
        ensure  => link,
        target  => $k3s_cluster::params::binary_path,
        require => File[$k3s_cluster::params::binary_path],
      }

      file { '/usr/local/bin/ctr':
        ensure  => link,
        target  => $k3s_cluster::params::binary_path,
        require => File[$k3s_cluster::params::binary_path],
      }
    }
    default: {
      fail("Unsupported installation method: ${k3s_cluster::installation_method}")
    }
  }
}
