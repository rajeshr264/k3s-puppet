# @summary Handles automated token sharing for multi-node K3S deployments
#
# This class implements automated token sharing using Puppet's exported resources
# to enable fully automated multi-node cluster deployments without manual token copying.
#
# @example Server node exporting token
#   class { 'k3s_cluster':
#     node_type           => 'server',
#     cluster_name        => 'my-cluster',
#     auto_token_sharing  => true,
#   }
#
# @example Agent node collecting token
#   class { 'k3s_cluster':
#     node_type          => 'agent',
#     cluster_name       => 'my-cluster',
#     auto_token_sharing => true,
#   }
#
class k3s_cluster::token_automation {

  # Only proceed if automated token sharing is enabled
  if $k3s_cluster::auto_token_sharing and $k3s_cluster::cluster_name {

    # Ensure facts directory exists for storing cluster information
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

    case $k3s_cluster::node_type {
      'server': {
        # Server nodes: Export token and server information for agent collection

        # Wait for K3S service to be fully ready and responsive
        exec { 'wait_for_k3s_server_ready':
          command   => "timeout ${k3s_cluster::token_timeout} bash -c 'until systemctl is-active k3s >/dev/null 2>&1 && [ -f /var/lib/rancher/k3s/server/node-token ]; do sleep 2; done'",
          path      => ['/bin', '/usr/bin'],
          require   => Service[$k3s_cluster::params::server_service_name],
          logoutput => true,
        }

        # Additional check to ensure K3S API is responding
        exec { 'wait_for_k3s_api_ready':
          command   => "timeout ${k3s_cluster::token_timeout} bash -c 'until k3s kubectl get nodes >/dev/null 2>&1; do sleep 2; done'",
          path      => ['/bin', '/usr/bin', '/usr/local/bin'],
          require   => Exec['wait_for_k3s_server_ready'],
          logoutput => true,
        }

        # Export cluster information as a resource for agents to collect
        # This uses Puppet's exported resources feature
        @@k3s_cluster_info { "${k3s_cluster::cluster_name}_${facts['networking']['hostname']}":
          ensure         => present,
          cluster_name   => $k3s_cluster::cluster_name,
          server_fqdn    => $facts['networking']['fqdn'],
          server_ip      => $facts['networking']['ip'],
          server_url     => "https://${facts['networking']['fqdn']}:6443",
          server_node    => $facts['networking']['hostname'],
          is_primary     => $k3s_cluster::cluster_init,
          token_file     => '/var/lib/rancher/k3s/server/node-token',
          export_time    => Integer($facts['timestamp']),
          tag            => "k3s_cluster_${k3s_cluster::cluster_name}",
          require        => Exec['wait_for_k3s_api_ready'],
        }

        # Create local facts about this server for reference
        file { '/etc/facter/facts.d/k3s_server_info.yaml':
          ensure  => file,
          content => @("EOF"),
            ---
            k3s_cluster_name: "${k3s_cluster::cluster_name}"
            k3s_node_type: "server"
            k3s_server_fqdn: "${facts['networking']['fqdn']}"
            k3s_server_url: "https://${facts['networking']['fqdn']}:6443"
            k3s_is_primary: ${k3s_cluster::cluster_init}
            k3s_token_exported: true
            k3s_export_timestamp: "${facts['timestamp']}"
            | EOF
          mode    => '0644',
          owner   => 'root',
          group   => 'root',
          require => [
            File['/etc/facter/facts.d'],
            Exec['wait_for_k3s_api_ready'],
          ],
        }

        notify { 'k3s_server_token_exported':
          message => "K3S server token exported for cluster '${k3s_cluster::cluster_name}'",
          require => K3s_cluster_info["${k3s_cluster::cluster_name}_${facts['networking']['hostname']}"],
        }
      }

      'agent': {
        # Agent nodes: Collect server information and tokens from exported resources

        # Collect all exported cluster information for this cluster
        K3s_cluster_info <<| cluster_name == $k3s_cluster::cluster_name |>>

        # Create a script that will collect and process the token information
        file { '/usr/local/bin/k3s-collect-cluster-info.sh':
          ensure  => file,
          mode    => '0755',
          owner   => 'root',
          group   => 'root',
          content => epp('k3s_cluster/collect-cluster-info.sh.epp', {
            'cluster_name'  => $k3s_cluster::cluster_name,
            'token_timeout' => $k3s_cluster::token_timeout,
            'wait_for_token' => $k3s_cluster::wait_for_token,
          }),
          require => File['/etc/facter/facts.d'],
        }

        # Execute the collection script to gather cluster information
        exec { 'collect_k3s_cluster_info':
          command     => '/usr/local/bin/k3s-collect-cluster-info.sh',
          path        => ['/bin', '/usr/bin', '/usr/local/bin'],
          require     => File['/usr/local/bin/k3s-collect-cluster-info.sh'],
          timeout     => $k3s_cluster::token_timeout,
          tries       => 3,
          try_sleep   => 10,
          logoutput   => true,
          refreshonly => false,
        }

        # The script will create this facts file if successful
        file { '/etc/facter/facts.d/k3s_cluster_info.yaml':
          ensure  => file,
          mode    => '0644',
          owner   => 'root',
          group   => 'root',
          require => Exec['collect_k3s_cluster_info'],
        }

        # Create notification about successful token collection
        exec { 'verify_token_collection':
          command => 'echo "Token collection completed successfully"',
          path    => ['/bin', '/usr/bin'],
          onlyif  => 'test -f /etc/facter/facts.d/k3s_cluster_info.yaml',
          require => File['/etc/facter/facts.d/k3s_cluster_info.yaml'],
        }

        notify { 'k3s_agent_token_collected':
          message => "K3S agent successfully collected token for cluster '${k3s_cluster::cluster_name}'",
          require => Exec['verify_token_collection'],
        }
      }

      default: {
        fail("Unsupported node type for token automation: ${k3s_cluster::node_type}")
      }
    }
  }
}
