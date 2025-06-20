# Example: Complete K3S uninstallation
#
# This example completely removes K3S with full cleanup

class { 'k3s_cluster':
  ensure             => 'absent',
  cleanup_containers => true,
  cleanup_iptables   => true,
  force_uninstall    => true,
}
