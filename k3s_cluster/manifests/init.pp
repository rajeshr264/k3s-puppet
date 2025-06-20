# @summary K3S Cluster Management Module
#
# This module manages K3S cluster installation, configuration, and lifecycle.
# It supports both single-node and multi-node deployments with various configuration options.
#
# @param ensure
#   Whether K3S should be present or absent
# @param node_type
#   Type of K3S node: 'server' or 'agent'
# @param installation_method
#   Installation method: 'script' (default) or 'binary'
# @param version
#   K3S version to install (default: 'v1.33.1+k3s1')
# @param server_url
#   URL of K3S server for agent nodes
# @param token
#   Token for joining the cluster
# @param cluster_init
#   Initialize cluster (only for first server node)
# @param config_options
#   Hash of additional configuration options
# @param cleanup_containers
#   Whether to cleanup containers on uninstall
# @param cleanup_iptables
#   Whether to cleanup iptables rules on uninstall
# @param cleanup_network_interfaces
#   Whether to cleanup network interfaces on uninstall
# @param cleanup_mounts
#   Whether to cleanup mount points on uninstall
# @param cluster_name
#   Unique cluster identifier for automated token sharing
# @param auto_token_sharing
#   Enable automatic token sharing between nodes
# @param wait_for_token
#   Whether agent nodes should wait for server tokens
# @param token_timeout
#   Timeout for token collection (30-600 seconds)
#
class k3s_cluster (
  Enum['present', 'absent']                $ensure                      = 'present',
  Enum['server', 'agent']                  $node_type                   = 'server',
  Enum['script', 'binary']                 $installation_method         = 'script',
  String                                   $version                     = 'v1.33.1+k3s1',
  Optional[Stdlib::HTTPUrl]                $server_url                  = undef,
  Optional[String]                         $token                       = undef,
  Boolean                                  $cluster_init                = false,
  Hash                                     $config_options              = {},
  Boolean                                  $cleanup_containers          = true,
  Boolean                                  $cleanup_iptables            = true,
  Boolean                                  $cleanup_network_interfaces  = true,
  Boolean                                  $cleanup_mounts              = true,
  Optional[String]                         $cluster_name                = undef,
  Boolean                                  $auto_token_sharing          = false,
  Boolean                                  $wait_for_token              = true,
  Integer[30, 600]                         $token_timeout               = 300,
) {
  # Validate parameters
  if $node_type == 'agent' and !$server_url and !$auto_token_sharing {
    fail('Agent nodes require either server_url or auto_token_sharing to be enabled')
  }

  if $node_type == 'agent' and !$token and !$auto_token_sharing {
    fail('Agent nodes require either token or auto_token_sharing to be enabled')
  }

  if $auto_token_sharing and !$cluster_name {
    fail('auto_token_sharing requires cluster_name to be set')
  }

  # Include parameter defaults
  include k3s_cluster::params

  case $ensure {
    'present': {
      # Handle automated token sharing if enabled
      if $auto_token_sharing {
        include k3s_cluster::token_automation
      }

      # Install K3S
      include k3s_cluster::install
      
      # Configure K3S
      include k3s_cluster::config
      
      # Manage K3S service
      include k3s_cluster::service

      # Establish proper ordering
      Class['k3s_cluster::install']
      -> Class['k3s_cluster::config']
      -> Class['k3s_cluster::service']

      if $auto_token_sharing {
        Class['k3s_cluster::token_automation']
        -> Class['k3s_cluster::install']
      }
    }
    'absent': {
      include k3s_cluster::uninstall
    }
    default: {
      fail("Invalid ensure value: ${ensure}")
    }
  }
}
