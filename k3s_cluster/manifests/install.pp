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

  # Handle RPM lock issues on RPM-based systems before installation
  if $facts['os']['family'] in ['RedHat', 'Suse'] {
    file { '/tmp/rpm-lock-handler.sh':
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0755',
      content => epp('k3s_cluster/rpm-lock-handler.sh.epp'),
    }

    exec { 'handle-rpm-locks':
      command => '/tmp/rpm-lock-handler.sh',
      path    => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
      require => File['/tmp/rpm-lock-handler.sh'],
      before  => [Package['wget'], Package['curl']],
    }
  }

  case $k3s_cluster::installation_method {
    'script': {
      # Ensure wget is installed (preferred method)
      package { 'wget':
        ensure => installed,
      }

      # Also ensure curl is available as fallback
      package { 'curl':
        ensure => installed,
      }

      # Download the K3S installation script using wget (with curl fallback)
      exec { 'download_k3s_script':
        command => "wget -O /tmp/k3s-install.sh ${k3s_cluster::params::install_script_url} || curl -sfL ${k3s_cluster::params::install_script_url} -o /tmp/k3s-install.sh",
        path    => ['/usr/bin', '/bin', '/usr/local/bin'],
        creates => '/tmp/k3s-install.sh',
        timeout => 60,
        require => [File[$k3s_cluster::params::config_dir], Package['wget'], Package['curl']],
      }

      # Make the script executable
      file { '/tmp/k3s-install.sh':
        ensure  => file,
        mode    => '0755',
        require => Exec['download_k3s_script'],
      }

      # Create enhanced installation script with RPM lock handling and retry logic
      file { '/tmp/k3s-install-with-retry.sh':
        ensure  => file,
        owner   => 'root',
        group   => 'root',
        mode    => '0755',
        content => epp('k3s_cluster/k3s-install-with-retry.sh.epp'),
        require => File['/tmp/k3s-install.sh'],
      }

      # Install using the enhanced K3S installation script with retry logic
      exec { 'install_k3s':
        command => '/tmp/k3s-install-with-retry.sh',
        path    => ['/usr/bin', '/bin', '/usr/local/bin', '/sbin', '/usr/sbin'],
        creates => $k3s_cluster::params::binary_path,
        timeout => 900,  # Increased timeout for retry logic
        require => File['/tmp/k3s-install-with-retry.sh'],
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
