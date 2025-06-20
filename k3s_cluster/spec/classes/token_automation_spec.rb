# frozen_string_literal: true

require 'spec_helper'

describe 'k3s_cluster::token_automation' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      context 'when auto_token_sharing is disabled' do
        let(:pre_condition) do
          <<-PP
            class { 'k3s_cluster':
              auto_token_sharing => false,
            }
          PP
        end

        it { is_expected.to compile }
        it { is_expected.not_to contain_file('/etc/facter') }
        it { is_expected.not_to contain_exec('wait_for_k3s_server_ready') }
      end

      context 'when auto_token_sharing is enabled but cluster_name is not set' do
        let(:pre_condition) do
          <<-PP
            class { 'k3s_cluster':
              auto_token_sharing => true,
            }
          PP
        end

        it { is_expected.to compile }
        it { is_expected.not_to contain_file('/etc/facter') }
        it { is_expected.not_to contain_exec('wait_for_k3s_server_ready') }
      end

      context 'when auto_token_sharing is enabled with cluster_name for server node' do
        let(:pre_condition) do
          <<-PP
            class { 'k3s_cluster':
              node_type           => 'server',
              auto_token_sharing  => true,
              cluster_name        => 'test-cluster',
              cluster_init        => true,
              token_timeout       => 300,
            }
          PP
        end

        it { is_expected.to compile.with_all_deps }

        # Test facts directory creation
        it { is_expected.to contain_file('/etc/facter').with_ensure('directory') }
        it { is_expected.to contain_file('/etc/facter/facts.d').with_ensure('directory') }

        # Test server-specific resources
        it { is_expected.to contain_exec('wait_for_k3s_server_ready') }
        it { is_expected.to contain_exec('wait_for_k3s_api_ready') }
        it { is_expected.to contain_exec('wait_for_server_token_ready') }
        it { is_expected.to contain_exec('collect_cluster_info') }

        # Test that the service dependency uses correct parameter
        it {
          is_expected.to contain_exec('wait_for_k3s_server_ready')
            .with_require(['Service[k3s]'])
        }

        # Test exported resource
        it {
          is_expected.to contain_k3s_cluster_info("test-cluster_#{facts[:networking][:hostname]}")
            .with_cluster_name('test-cluster')
            .with_server_fqdn(facts[:networking][:fqdn])
            .with_is_primary(true)
        }

        # Test server facts file
        it {
          is_expected.to contain_file('/etc/facter/facts.d/k3s_server_info.yaml')
            .with_ensure('file')
            .with_content(/k3s_cluster_name: "test-cluster"/)
            .with_content(/k3s_node_type: "server"/)
            .with_content(/k3s_is_primary: true/)
        }

        # Test notification
        it { is_expected.to contain_notify('k3s_server_token_exported') }

        # Test script files
        it { is_expected.to contain_file('/tmp/wait-for-token-ready.sh') }
        it { is_expected.to contain_file('/tmp/collect-cluster-info.sh') }
      end

      context 'when auto_token_sharing is enabled with cluster_name for agent node' do
        let(:pre_condition) do
          <<-PP
            class { 'k3s_cluster':
              node_type           => 'agent',
              auto_token_sharing  => true,
              cluster_name        => 'test-cluster',
              wait_for_token      => true,
              token_timeout       => 300,
            }
          PP
        end

        it { is_expected.to compile.with_all_deps }

        # Test facts directory creation
        it { is_expected.to contain_file('/etc/facter').with_ensure('directory') }
        it { is_expected.to contain_file('/etc/facter/facts.d').with_ensure('directory') }

        # Test agent-specific resources
        it { is_expected.to contain_file('/usr/local/bin/k3s-collect-cluster-info.sh') }
        it { is_expected.to contain_exec('collect_k3s_cluster_info') }
        it { is_expected.to contain_exec('verify_token_collection') }

        # Test cluster info facts file
        it {
          is_expected.to contain_file('/etc/facter/facts.d/k3s_cluster_info.yaml')
            .with_ensure('file')
            .with_require(['Exec[collect_k3s_cluster_info]'])
        }

        # Test notification
        it { is_expected.to contain_notify('k3s_agent_token_collected') }
      end

      context 'when unsupported node type is specified' do
        let(:pre_condition) do
          <<-PP
            class { 'k3s_cluster':
              node_type           => 'invalid',
              auto_token_sharing  => true,
              cluster_name        => 'test-cluster',
            }
          PP
        end

        it { is_expected.to compile.and_raise_error(/Unsupported node type for token automation: invalid/) }
      end

      context 'parameter validation' do
        let(:pre_condition) do
          <<-PP
            class { 'k3s_cluster':
              node_type           => 'server',
              auto_token_sharing  => true,
              cluster_name        => 'test-cluster',
              token_timeout       => 600,
            }
          PP
        end

        it { is_expected.to compile }

        # Test that token_timeout parameter is properly used
        it {
          is_expected.to contain_exec('wait_for_k3s_server_ready')
            .with_command(/timeout 600/)
        }

        it {
          is_expected.to contain_exec('wait_for_server_token_ready')
            .with_timeout(600)
        }
      end

      context 'dependency chain validation' do
        let(:pre_condition) do
          <<-PP
            class { 'k3s_cluster':
              node_type           => 'server',
              auto_token_sharing  => true,
              cluster_name        => 'test-cluster',
            }
          PP
        end

        it { is_expected.to compile }

        # Test proper dependency chain for server
        it {
          is_expected.to contain_exec('wait_for_k3s_api_ready')
            .with_require(['Exec[wait_for_k3s_server_ready]'])
        }

        it {
          is_expected.to contain_exec('wait_for_server_token_ready')
            .with_require(['File[/tmp/wait-for-token-ready.sh]', 'Exec[wait_for_k3s_api_ready]'])
        }

        it {
          is_expected.to contain_exec('collect_cluster_info')
            .with_require(['File[/tmp/collect-cluster-info.sh]', 'Exec[wait_for_server_token_ready]'])
        }
      end
    end
  end
end 