# Custom Puppet resource type for K3S cluster information
# This type is used with exported resources to share cluster information
# between server and agent nodes for automated token sharing.

Puppet::Type.newtype(:k3s_cluster_info) do
  @doc = "Manages K3S cluster information for automated token sharing between nodes"

  ensurable

  newparam(:name, :namevar => true) do
    desc "The unique name of the cluster info resource (typically cluster_name_hostname)"
    validate do |value|
      unless value =~ /^[a-zA-Z0-9_-]+$/
        raise ArgumentError, "k3s_cluster_info name must contain only alphanumeric characters, hyphens, and underscores"
      end
    end
  end

  newparam(:cluster_name) do
    desc "The name of the K3S cluster"
    validate do |value|
      unless value.is_a?(String) && !value.empty?
        raise ArgumentError, "cluster_name must be a non-empty string"
      end
    end
  end

  newparam(:server_fqdn) do
    desc "The fully qualified domain name of the server node"
    validate do |value|
      unless value.is_a?(String) && !value.empty?
        raise ArgumentError, "server_fqdn must be a non-empty string"
      end
    end
  end

  newparam(:server_ip) do
    desc "The IP address of the server node"
    validate do |value|
      unless value =~ /^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/ || value =~ /^(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$/
        raise ArgumentError, "server_ip must be a valid IPv4 or IPv6 address"
      end
    end
  end

  newparam(:server_url) do
    desc "The complete URL of the K3S server API"
    validate do |value|
      unless value =~ /^https?:\/\/.+:\d+$/
        raise ArgumentError, "server_url must be a valid URL with protocol and port"
      end
    end
  end

  newparam(:server_node) do
    desc "The hostname of the server node"
    validate do |value|
      unless value.is_a?(String) && !value.empty?
        raise ArgumentError, "server_node must be a non-empty string"
      end
    end
  end

  newparam(:is_primary) do
    desc "Whether this server node is the primary/initial server"
    newvalues(true, false)
    defaultto false
  end

  newparam(:token_file) do
    desc "Path to the token file on the server node"
    defaultto '/var/lib/rancher/k3s/server/node-token'
    validate do |value|
      unless value =~ /^\/.*$/
        raise ArgumentError, "token_file must be an absolute path"
      end
    end
  end

  newparam(:export_time) do
    desc "Timestamp when the cluster information was exported"
    validate do |value|
      unless value.is_a?(Integer) && value > 0
        raise ArgumentError, "export_time must be a positive integer timestamp"
      end
    end
  end

  newparam(:tag) do
    desc "Tag for resource collection and identification"
    validate do |value|
      unless value.is_a?(String) && !value.empty?
        raise ArgumentError, "tag must be a non-empty string"
      end
    end
  end

  # Auto-require any file resources for the token file
  autorequire(:file) do
    [self[:token_file]] if self[:token_file]
  end

  # Auto-require any service resources that might be related
  autorequire(:service) do
    ['k3s', 'k3s-server']
  end

  validate do
    # Ensure required parameters are present
    required_params = [:cluster_name, :server_fqdn, :server_ip, :server_url, :server_node]
    required_params.each do |param|
      if self[param].nil? || self[param].empty?
        fail("k3s_cluster_info requires #{param} to be specified")
      end
    end
  end
end
