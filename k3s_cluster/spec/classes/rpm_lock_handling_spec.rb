require 'spec_helper'

describe 'k3s_cluster::install' do
  let(:title) { 'k3s_cluster::install' }

  context 'RPM lock handling on RedHat systems' do
    let(:facts) do
      {
        'os' => {
          'family' => 'RedHat',
          'name' => 'CentOS',
          'release' => {
            'major' => '8'
          }
        },
        'architecture' => 'x86_64'
      }
    end

    let(:params) do
      {
        'installation_method' => 'script',
        'version' => 'v1.28.2+k3s1'
      }
    end

    it { is_expected.to compile.with_all_deps }

    it 'creates RPM lock handler script on RedHat systems' do
      is_expected.to contain_file('/tmp/rpm-lock-handler.sh')
        .with_ensure('file')
        .with_owner('root')
        .with_group('root')
        .with_mode('0755')
    end

    it 'executes RPM lock handler before package installation' do
      is_expected.to contain_exec('handle-rpm-locks')
        .with_command('/tmp/rpm-lock-handler.sh')
        .with_path(['/bin', '/usr/bin', '/sbin', '/usr/sbin'])
        .that_requires('File[/tmp/rpm-lock-handler.sh]')
        .that_comes_before(['Package[wget]', 'Package[curl]'])
    end

    it 'creates enhanced K3S installation script' do
      is_expected.to contain_file('/tmp/k3s-install-with-retry.sh')
        .with_ensure('file')
        .with_owner('root')
        .with_group('root')
        .with_mode('0755')
    end

    it 'uses enhanced installation script with increased timeout' do
      is_expected.to contain_exec('install_k3s')
        .with_command('/tmp/k3s-install-with-retry.sh')
        .with_timeout(900)
        .that_requires('File[/tmp/k3s-install-with-retry.sh]')
    end
  end

  context 'No RPM lock handling on Debian systems' do
    let(:facts) do
      {
        'os' => {
          'family' => 'Debian',
          'name' => 'Ubuntu',
          'release' => {
            'major' => '22'
          }
        },
        'architecture' => 'x86_64'
      }
    end

    let(:params) do
      {
        'installation_method' => 'script',
        'version' => 'v1.28.2+k3s1'
      }
    end

    it { is_expected.to compile.with_all_deps }

    it 'does not create RPM lock handler on Debian systems' do
      is_expected.not_to contain_file('/tmp/rpm-lock-handler.sh')
    end

    it 'does not execute RPM lock handler on Debian systems' do
      is_expected.not_to contain_exec('handle-rpm-locks')
    end

    it 'still creates enhanced K3S installation script' do
      is_expected.to contain_file('/tmp/k3s-install-with-retry.sh')
        .with_ensure('file')
        .with_owner('root')
        .with_group('root')
        .with_mode('0755')
    end
  end

  context 'SUSE systems get RPM lock handling' do
    let(:facts) do
      {
        'os' => {
          'family' => 'Suse',
          'name' => 'SLES',
          'release' => {
            'major' => '15'
          }
        },
        'architecture' => 'x86_64'
      }
    end

    let(:params) do
      {
        'installation_method' => 'script',
        'version' => 'v1.28.2+k3s1'
      }
    end

    it { is_expected.to compile.with_all_deps }

    it 'creates RPM lock handler script on SUSE systems' do
      is_expected.to contain_file('/tmp/rpm-lock-handler.sh')
        .with_ensure('file')
        .with_owner('root')
        .with_group('root')
        .with_mode('0755')
    end

    it 'executes RPM lock handler before package installation' do
      is_expected.to contain_exec('handle-rpm-locks')
        .with_command('/tmp/rpm-lock-handler.sh')
        .that_requires('File[/tmp/rpm-lock-handler.sh]')
        .that_comes_before(['Package[wget]', 'Package[curl]'])
    end
  end

  context 'Binary installation method' do
    let(:facts) do
      {
        'os' => {
          'family' => 'RedHat',
          'name' => 'CentOS',
          'release' => {
            'major' => '8'
          }
        },
        'architecture' => 'x86_64'
      }
    end

    let(:params) do
      {
        'installation_method' => 'binary',
        'version' => 'v1.28.2+k3s1'
      }
    end

    it { is_expected.to compile.with_all_deps }

    it 'still creates RPM lock handler for binary method' do
      is_expected.to contain_file('/tmp/rpm-lock-handler.sh')
        .with_ensure('file')
    end

    it 'does not create enhanced installation script for binary method' do
      is_expected.not_to contain_file('/tmp/k3s-install-with-retry.sh')
    end
  end
end 
