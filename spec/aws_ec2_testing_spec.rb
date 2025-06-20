require 'spec_helper'
require 'json'
require_relative '../ec2-scripts/aws_ec2_testing'

describe 'AWS EC2 K3S Testing' do
  let(:testing) { AwsEc2K3sTesting.new }

  # Mock AWS CLI responses for testing
  let(:mock_aws_identity) do
    {
      'UserId' => 'AIDACKCEVSQ6C2EXAMPLE',
      'Account' => '123456789012',
      'Arn' => 'arn:aws:iam::123456789012:user/test-user'
    }
  end

  let(:mock_key_pairs) do
    {
      'KeyPairs' => [
        {
          'KeyPairId' => 'key-1234567890abcdef0',
          'KeyFingerprint' => 'example-fingerprint',
          'KeyName' => 'k3s-testing-key',
          'KeyType' => 'rsa',
          'Tags' => []
        }
      ]
    }
  end

  let(:mock_security_groups) do
    {
      'SecurityGroups' => [
        {
          'Description' => 'K3S testing security group',
          'GroupName' => 'k3s-testing-security-group',
          'IpPermissions' => [],
          'OwnerId' => '123456789012',
          'GroupId' => 'sg-1234567890abcdef0',
          'IpPermissionsEgress' => [],
          'Tags' => [],
          'VpcId' => 'vpc-12345678'
        }
      ]
    }
  end

  let(:supported_os_amis) do
    {
      'us-west-2' => {
        'ubuntu' => {
          'ami_id' => 'ami-0c2d3e23f757b5d84',
          'name' => 'Ubuntu 22.04 LTS',
          'user' => 'ubuntu',
          'package_manager' => 'apt'
        },
        'rhel' => {
          'ami_id' => 'ami-0c94855ba95b798c7',
          'name' => 'Red Hat Enterprise Linux 9',
          'user' => 'ec2-user',
          'package_manager' => 'dnf'
        },
        'opensuse' => {
          'ami_id' => 'ami-0c2d3e23f757b5d85',
          'name' => 'openSUSE Leap 15.5',
          'user' => 'ec2-user',
          'package_manager' => 'zypper'
        },
        'sles' => {
          'ami_id' => 'ami-0c2d3e23f757b5d86',
          'name' => 'SUSE Linux Enterprise Server 15 SP5',
          'user' => 'ec2-user',
          'package_manager' => 'zypper'
        },
        'debian' => {
          'ami_id' => 'ami-0c2d3e23f757b5d87',
          'name' => 'Debian 12 (Bookworm)',
          'user' => 'admin',
          'package_manager' => 'apt'
        }
      }
    }
  end

  describe 'Prerequisites validation' do
    context 'when AWS CLI is not installed' do
      it 'should fail with appropriate error message' do
        # Test will fail initially - this drives implementation
        expect { validate_aws_cli_installed }.to raise_error(/AWS CLI not found/)
      end
    end

    context 'when AWS credentials are not configured' do
      it 'should fail with appropriate error message' do
        allow_any_instance_of(Object).to receive(:`).with('aws sts get-caller-identity 2>/dev/null').and_return('')
        expect { validate_aws_credentials }.to raise_error(/AWS credentials not configured/)
      end
    end

    context 'when aws-azure-login is required' do
      it 'should prompt for azure login when credentials are expired' do
        # Test for azure login requirement
        expect { check_azure_login_requirement }.to output(/Please run aws-azure-login/).to_stdout
      end
    end

    context 'when key pair exists' do
      it 'should validate key pair exists in specified region' do
        allow_any_instance_of(Object).to receive(:`).and_return(mock_key_pairs.to_json)
        expect(validate_key_pair('k3s-testing-key', 'us-west-2')).to be_truthy
      end
    end

    context 'when security group exists' do
      it 'should validate security group exists' do
        allow_any_instance_of(Object).to receive(:`).and_return(mock_security_groups.to_json)
        expect(validate_security_group('k3s-testing-security-group', 'us-west-2')).to be_truthy
      end
    end
  end

  describe 'Operating System Support' do
    context 'supported K3S operating systems' do
      it 'should support Ubuntu 22.04 LTS' do
        os_config = get_os_config('ubuntu', 'us-west-2')
        expect(os_config).to include(
          'name' => 'Ubuntu 22.04 LTS',
          'user' => 'ubuntu',
          'package_manager' => 'apt'
        )
      end

      it 'should support Red Hat Enterprise Linux 9' do
        os_config = get_os_config('rhel', 'us-west-2')
        expect(os_config).to include(
          'name' => 'Red Hat Enterprise Linux 9',
          'user' => 'ec2-user',
          'package_manager' => 'dnf'
        )
      end

      it 'should support openSUSE Leap 15.5' do
        os_config = get_os_config('opensuse', 'us-west-2')
        expect(os_config).to include(
          'name' => 'openSUSE Leap 15.5',
          'user' => 'ec2-user',
          'package_manager' => 'zypper'
        )
      end

      it 'should support SUSE Linux Enterprise Server 15' do
        os_config = get_os_config('sles', 'us-west-2')
        expect(os_config).to include(
          'name' => 'SUSE Linux Enterprise Server 15 SP5',
          'user' => 'ec2-user',
          'package_manager' => 'zypper'
        )
      end

      it 'should support Debian 12 (Bookworm)' do
        os_config = get_os_config('debian', 'us-west-2')
        expect(os_config).to include(
          'name' => 'Debian 12 (Bookworm)',
          'user' => 'admin',
          'package_manager' => 'apt'
        )
      end

      it 'should fail for unsupported operating systems' do
        expect { get_os_config('centos', 'us-west-2') }.to raise_error(/Unsupported operating system/)
      end
    end

    context 'AMI discovery' do
      it 'should find latest AMI for each supported OS' do
        supported_os_amis['us-west-2'].keys.each do |os|
          ami_id = find_latest_ami(os, 'us-west-2')
          expect(ami_id).to match(/^ami-[0-9a-f]{17}$/)
        end
      end

      it 'should cache AMI lookups for performance' do
        # First call should query AWS
        expect_any_instance_of(Object).to receive(:`).once.and_return('{"Images": [{"ImageId": "ami-12345"}]}')
        
        ami_id1 = find_latest_ami('ubuntu', 'us-west-2')
        ami_id2 = find_latest_ami('ubuntu', 'us-west-2')  # Should use cache
        
        expect(ami_id1).to eq(ami_id2)
      end
    end
  end

  describe 'Instance Configuration' do
    context 'instance specifications' do
      it 'should use 2 vCPU and 4GB RAM instance type' do
        instance_type = get_instance_type_for_requirements(vcpu: 2, memory_gb: 4)
        expect(instance_type).to eq('t3.medium')
      end

      it 'should configure 20GB root volume' do
        block_device_mappings = get_block_device_mappings(root_volume_size: 20)
        expect(block_device_mappings).to include(
          hash_including(
            'DeviceName' => '/dev/sda1',
            'Ebs' => hash_including('VolumeSize' => 20)
          )
        )
      end
    end

    context 'networking configuration' do
      it 'should use default VPC' do
        vpc_config = get_vpc_configuration
        expect(vpc_config['use_default']).to be_truthy
      end

      it 'should use public subnet for instances' do
        subnet_config = get_subnet_configuration
        expect(subnet_config['type']).to eq('public')
      end

      it 'should assign public IP addresses' do
        network_config = get_network_configuration
        expect(network_config['associate_public_ip']).to be_truthy
      end
    end

    context 'user-specific configuration' do
      it 'should use configurable security group' do
        config = get_user_configuration
        expect(config['security_group']).to eq(ENV['AWS_SECURITY_GROUP'] || 'k3s-testing-security-group')
      end

      it 'should use configurable region' do
        config = get_user_configuration
        expect(config['region']).to eq(ENV['AWS_REGION'] || 'us-west-2')
      end

      it 'should use configurable key pair' do
        config = get_user_configuration
        expect(config['key_name']).to eq(ENV['AWS_KEY_NAME'] || 'k3s-testing-key')
      end

      it 'should use configurable key file path' do
        config = get_user_configuration
        expected_path = ENV['AWS_KEY_PATH'] || "#{ENV['HOME']}/keys/#{ENV['AWS_KEY_NAME'] || 'k3s-testing-key'}.pem"
        expect(config['key_path']).to eq(expected_path)
      end
    end
  end

  describe 'User Data Script Generation' do
    context 'OS-specific installation scripts' do
      it 'should generate Ubuntu-specific installation script' do
        script = generate_user_data_script('ubuntu', 'single')
        expect(script).to include('apt-get update')
        expect(script).to include('apt-get install -y')
        expect(script).to include('wget https://apt.puppet.com/puppet8-release-jammy.deb')
      end

      it 'should generate RHEL-specific installation script' do
        script = generate_user_data_script('rhel', 'single')
        expect(script).to include('dnf update -y')
        expect(script).to include('dnf install -y')
        expect(script).to include('rpm -Uvh https://yum.puppet.com/puppet8-release-el-9.noarch.rpm')
      end

      it 'should generate openSUSE-specific installation script' do
        script = generate_user_data_script('opensuse', 'single')
        expect(script).to include('zypper refresh')
        expect(script).to include('zypper install -y')
        expect(script).to include('rpm -Uvh https://yum.puppet.com/puppet8-release-sles-15.noarch.rpm')
      end

      it 'should generate SLES-specific installation script' do
        script = generate_user_data_script('sles', 'single')
        expect(script).to include('zypper refresh')
        expect(script).to include('zypper install -y')
        expect(script).to include('rpm -Uvh https://yum.puppet.com/puppet8-release-sles-15.noarch.rpm')
      end

      it 'should generate Debian-specific installation script' do
        script = generate_user_data_script('debian', 'single')
        expect(script).to include('apt-get update')
        expect(script).to include('apt-get install -y')
        expect(script).to include('wget https://apt.puppet.com/puppet8-release-bookworm.deb')
      end
    end

    context 'deployment type variations' do
      it 'should generate server node configuration' do
        script = generate_user_data_script('ubuntu', 'server')
        expect(script).to include("node_type => 'server'")
        expect(script).to include('cluster_init => true')
      end

      it 'should generate agent node configuration' do
        script = generate_user_data_script('ubuntu', 'agent')
        expect(script).to include("node_type => 'agent'")
        expect(script).to include('auto_token_sharing => true')
      end
    end
  end

  describe 'Multi-OS Testing Workflow' do
    context 'single node testing' do
      it 'should test all supported operating systems' do
        supported_os_amis['us-west-2'].keys.each do |os|
          expect { test_single_node_os(os) }.not_to raise_error
        end
      end

      it 'should run tests in parallel for efficiency' do
        start_time = Time.now
        test_results = test_all_os_parallel('single')
        end_time = Time.now
        
        # Parallel execution should be faster than sequential
        expect(end_time - start_time).to be < (supported_os_amis['us-west-2'].size * 60) # Less than 1 min per OS
        expect(test_results.size).to eq(supported_os_amis['us-west-2'].size)
      end
    end

    context 'multi-node testing' do
      it 'should support mixed OS multi-node clusters' do
        cluster_config = {
          'server' => { 'os' => 'ubuntu', 'count' => 1 },
          'agents' => [
            { 'os' => 'rhel', 'count' => 1 },
            { 'os' => 'opensuse', 'count' => 1 }
          ]
        }
        
        expect { test_multi_node_mixed_os(cluster_config) }.not_to raise_error
      end

      it 'should validate cross-OS cluster compatibility' do
        compatibility_matrix = get_os_compatibility_matrix
        expect(compatibility_matrix['ubuntu']['rhel']).to be_truthy
        expect(compatibility_matrix['rhel']['opensuse']).to be_truthy
        expect(compatibility_matrix['debian']['sles']).to be_truthy
      end
    end
  end

  describe 'Test Reporting and Cleanup' do
    context 'test result collection' do
      it 'should collect test results from all OS instances' do
        test_results = collect_test_results(['i-1234567890abcdef0', 'i-1234567890abcdef1'])
        expect(test_results).to be_an(Array)
        expect(test_results.first).to include('instance_id', 'os', 'status', 'k3s_version')
      end

      it 'should generate comprehensive test report' do
        report = generate_test_report(mock_test_results)
        expect(report).to include('summary', 'details', 'failures', 'recommendations')
      end
    end

    context 'resource cleanup' do
      it 'should cleanup all test instances after completion' do
        instance_ids = ['i-1234567890abcdef0', 'i-1234567890abcdef1']
        expect { cleanup_test_instances(instance_ids) }.not_to raise_error
      end

      it 'should provide cost estimation for test run' do
        cost_estimate = calculate_test_cost(
          instances: 5,
          duration_hours: 2,
          instance_type: 't3.medium',
          region: 'us-west-2'
        )
        expect(cost_estimate).to be > 0
        expect(cost_estimate).to be < 1.0  # Should be less than $1 for typical test
      end
    end
  end

  describe 'User Configuration' do
    it 'should have configurable AWS settings' do
      config = AwsEc2K3sTesting::USER_CONFIG
      expect(config).to have_key('security_group')
      expect(config).to have_key('region')
      expect(config).to have_key('key_name')
      expect(config).to have_key('key_path')
    end

    it 'should use environment variables when available' do
      # Mock environment variables
      allow(ENV).to receive(:[]).with('AWS_SECURITY_GROUP').and_return('test-security-group')
      allow(ENV).to receive(:[]).with('AWS_REGION').and_return('us-east-1')
      allow(ENV).to receive(:[]).with('AWS_KEY_NAME').and_return('test-key')
      allow(ENV).to receive(:[]).with('AWS_KEY_PATH').and_return('/path/to/test-key.pem')
      allow(ENV).to receive(:[]).with('HOME').and_return('/home/user')

      # Reload the class to pick up new environment variables
      load File.join(File.dirname(__FILE__), '../ec2-scripts/aws_ec2_testing.rb')
      
      config = AwsEc2K3sTesting::USER_CONFIG
      expect(config['security_group']).to eq('test-security-group')
      expect(config['region']).to eq('us-east-1')
      expect(config['key_name']).to eq('test-key')
      expect(config['key_path']).to eq('/path/to/test-key.pem')
    end

    it 'should have reasonable defaults' do
      # Mock environment variables to be nil
      allow(ENV).to receive(:[]).and_return(nil)
      allow(ENV).to receive(:[]).with('HOME').and_return('/home/user')

      # Reload the class to pick up defaults
      load File.join(File.dirname(__FILE__), '../ec2-scripts/aws_ec2_testing.rb')
      
      config = AwsEc2K3sTesting::USER_CONFIG
      expect(config['security_group']).to eq('k3s-testing-security-group')
      expect(config['region']).to eq('us-west-2')
      expect(config['key_name']).to eq('k3s-testing-key')
      expect(config['key_path']).to eq('/home/user/keys/k3s-testing-key.pem')
    end
  end

  # Helper methods that will be implemented
  private

  def mock_test_results
    [
      {
        'instance_id' => 'i-1234567890abcdef0',
        'os' => 'ubuntu',
        'status' => 'success',
        'k3s_version' => 'v1.28.2+k3s1',
        'test_duration' => 300
      },
      {
        'instance_id' => 'i-1234567890abcdef1',
        'os' => 'rhel',
        'status' => 'success',
        'k3s_version' => 'v1.28.2+k3s1',
        'test_duration' => 320
      }
    ]
  end
end 