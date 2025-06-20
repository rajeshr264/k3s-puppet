# @summary Automated K3S Token Sharing
#
# This class handles automated token sharing between K3S server and agent nodes
# using Puppet's exported resources feature. It enables seamless multi-node
# cluster deployment without manual token management.
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

    # Facts directory is created by k3s_cluster::config

    case $k3s_cluster::node_type {
      'server': {
        # Server nodes: Export token and server information for agent collection

        # Wait for K3S service to be fully ready and responsive
        exec { 'wait_for_k3s_server_ready':
          command   => "timeout ${k3s_cluster::token_timeout} bash -c 'until systemctl is-active k3s >/dev/null 2>&1 && [ -f /var/lib/rancher/k3s/server/node-token ]; do sleep 2; done'",
          path      => ['/bin', '/usr/bin'],
          require   => Service[$k3s_cluster::params::service_name],
          logoutput => true,
        }

        # Additional check to ensure K3S API is responding
        exec { 'wait_for_k3s_api_ready':
          command   => "timeout ${k3s_cluster::token_timeout} bash -c 'until k3s kubectl get nodes >/dev/null 2>&1; do sleep 2; done'",
          path      => ['/bin', '/usr/bin', '/usr/local/bin'],
          require   => Exec['wait_for_k3s_server_ready'],
          logoutput => true,
        }

        # Enhanced token readiness verification
        file { '/tmp/wait-for-token-ready.sh':
          ensure  => file,
          owner   => 'root',
          group   => 'root',
          mode    => '0755',
          content => epp('k3s_cluster/wait-for-token-ready.sh.epp'),
        }

        exec { 'wait_for_server_token_ready':
          command   => '/tmp/wait-for-token-ready.sh',
          path      => ['/usr/local/bin', '/usr/bin', '/bin'],
          timeout   => $k3s_cluster::token_timeout,
          tries     => 2,
          try_sleep => 30,
          require   => [
            File['/tmp/wait-for-token-ready.sh'],
            Exec['wait_for_k3s_api_ready'],
          ],
        }

        # Collect cluster information script
        file { '/tmp/collect-cluster-info.sh':
          ensure  => file,
          owner   => 'root',
          group   => 'root',
          mode    => '0755',
          content => epp('k3s_cluster/collect-cluster-info.sh.epp', {
            'cluster_name'   => $k3s_cluster::cluster_name,
            'token_timeout'  => $k3s_cluster::token_timeout,
            'wait_for_token' => $k3s_cluster::wait_for_token,
          }),
        }

        # Execute cluster info collection
        exec { 'collect_cluster_info':
          command   => '/tmp/collect-cluster-info.sh',
          path      => ['/usr/local/bin', '/usr/bin', '/bin'],
          timeout   => 120,
          creates   => '/tmp/k3s_cluster_info.yaml',
          require   => [
            File['/tmp/collect-cluster-info.sh'],
            Exec['wait_for_server_token_ready'],
          ],
        }

        # For single-node deployments, create local token information
        # For multi-node deployments with storeconfigs, export the resource
        $current_timestamp = $facts['timestamp'] ? {
          undef   => Integer(Timestamp().strftime('%s')),
          default => Integer($facts['timestamp'])
        }

        # Only use exported resources if storeconfigs is available
        if $settings::storeconfigs {
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
            export_time    => $current_timestamp,
            tag            => "k3s_cluster_${k3s_cluster::cluster_name}",
            require        => Exec['collect_cluster_info'],
          }

          notify { 'k3s_server_token_exported':
            message => "K3S server token exported for cluster '${k3s_cluster::cluster_name}' (using storeconfigs)",
            require => K3s_cluster_info["${k3s_cluster::cluster_name}_${facts['networking']['hostname']}"],
          }
        } else {
          # For single-node or non-storeconfigs deployments, just create local facts
          notify { 'k3s_server_token_local':
            message => "K3S server ready for cluster '${k3s_cluster::cluster_name}' (single-node mode)",
            require => Exec['collect_cluster_info'],
          }
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
            k3s_export_timestamp: "${current_timestamp}"
            | EOF
          mode    => '0644',
          owner   => 'root',
          group   => 'root',
        }
      }

      'agent': {
        # Agent nodes: Collect server information and tokens from exported resources

        if $settings::storeconfigs {
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
        } else {
          # For single-node deployments, agent nodes are not typically used
          # But if they are, they need manual token configuration
          notify { 'k3s_agent_manual_config':
            message => "K3S agent node requires manual token configuration (storeconfigs not available)",
          }

          # Create placeholder facts file for consistency
          file { '/etc/facter/facts.d/k3s_cluster_info.yaml':
            ensure  => file,
            content => @("EOF"),
              ---
              k3s_cluster_name: "${k3s_cluster::cluster_name}"
              k3s_node_type: "agent"
              k3s_token_collected: false
              k3s_requires_manual_config: true
              k3s_collection_timestamp: "${Integer(Timestamp().strftime('%s'))}"
              | EOF
            mode    => '0644',
            owner   => 'root',
            group   => 'root',
          }
        }
      }

      default: {
        fail("Unsupported node type for token automation: ${k3s_cluster::node_type}")
      }
    }
  }
}
