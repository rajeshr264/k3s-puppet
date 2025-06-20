# Provider for k3s_cluster_info resource type
# This provider handles reading K3S tokens and managing cluster information
# for automated token sharing between nodes.

require 'yaml'
require 'fileutils'

Puppet::Type.type(:k3s_cluster_info).provide(:ruby) do
  desc "Provider for K3S cluster information management"

  def exists?
    # Check if the cluster information has been properly exported
    info_file = "/tmp/k3s_cluster_info_#{resource[:cluster_name]}_#{resource[:server_node]}.yaml"
    File.exist?(info_file)
  end

  def create
    # Create/export the cluster information
    begin
      # Read the token from the server node (only if we're on a server)
      token_content = nil
      if File.exist?(resource[:token_file])
        token_content = File.read(resource[:token_file]).strip
        Puppet.info("Successfully read K3S token from #{resource[:token_file]}")
      else
        Puppet.warning("Token file #{resource[:token_file]} not found, will retry")
        return false
      end

      # Create cluster information structure
      cluster_info = {
        'cluster_name' => resource[:cluster_name],
        'server_fqdn' => resource[:server_fqdn],
        'server_ip' => resource[:server_ip],
        'server_url' => resource[:server_url],
        'server_node' => resource[:server_node],
        'is_primary' => resource[:is_primary],
        'node_token' => token_content,
        'export_time' => resource[:export_time],
        'tag' => resource[:tag]
      }

      # Write cluster information to a temporary file for collection
      info_file = "/tmp/k3s_cluster_info_#{resource[:cluster_name]}_#{resource[:server_node]}.yaml"
      File.open(info_file, 'w') do |file|
        file.write(cluster_info.to_yaml)
      end

      # Set appropriate permissions
      File.chmod(0644, info_file)

      # Also create a shell script version for easier consumption
      script_file = "/tmp/k3s_cluster_info_#{resource[:cluster_name]}_#{resource[:server_node]}.sh"
      File.open(script_file, 'w') do |file|
        file.write(generate_shell_script(cluster_info))
      end
      File.chmod(0755, script_file)

      Puppet.info("K3S cluster information exported successfully for cluster '#{resource[:cluster_name]}'")
      true
    rescue => e
      Puppet.err("Failed to export K3S cluster information: #{e.message}")
      false
    end
  end

  def destroy
    # Remove exported cluster information
    begin
      info_file = "/tmp/k3s_cluster_info_#{resource[:cluster_name]}_#{resource[:server_node]}.yaml"
      script_file = "/tmp/k3s_cluster_info_#{resource[:cluster_name]}_#{resource[:server_node]}.sh"

      File.delete(info_file) if File.exist?(info_file)
      File.delete(script_file) if File.exist?(script_file)

      Puppet.info("K3S cluster information removed for cluster '#{resource[:cluster_name]}'")
      true
    rescue => e
      Puppet.err("Failed to remove K3S cluster information: #{e.message}")
      false
    end
  end

  private

  def generate_shell_script(cluster_info)
    <<~SCRIPT
      #!/bin/bash
      # K3S Cluster Information for #{cluster_info['cluster_name']}
      # Generated on #{Time.now}

      export K3S_CLUSTER_NAME="#{cluster_info['cluster_name']}"
      export K3S_SERVER_FQDN="#{cluster_info['server_fqdn']}"
      export K3S_SERVER_IP="#{cluster_info['server_ip']}"
      export K3S_SERVER_URL="#{cluster_info['server_url']}"
      export K3S_SERVER_NODE="#{cluster_info['server_node']}"
      export K3S_IS_PRIMARY="#{cluster_info['is_primary']}"
      export K3S_NODE_TOKEN="#{cluster_info['node_token']}"
      export K3S_EXPORT_TIME="#{cluster_info['export_time']}"
      export K3S_TAG="#{cluster_info['tag']}"

      # Function to display cluster information
      show_cluster_info() {
        echo "=== K3S Cluster Information ==="
        echo "Cluster Name: $K3S_CLUSTER_NAME"
        echo "Server FQDN: $K3S_SERVER_FQDN"
        echo "Server URL: $K3S_SERVER_URL"
        echo "Server Node: $K3S_SERVER_NODE"
        echo "Is Primary: $K3S_IS_PRIMARY"
        echo "Export Time: $K3S_EXPORT_TIME"
        echo "=============================="
      }

      # Show info if script is executed directly
      if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        show_cluster_info
      fi
    SCRIPT
  end
end
