# AWS EC2 Testing Guide for K3S Puppet Module

This guide provides comprehensive instructions for testing the K3S Puppet module on AWS EC2 instances across multiple operating systems with **automatic temporary resource management**.

## Overview

The updated testing system automatically creates and cleans up all AWS resources, including:
- **Security Groups**: Auto-created with K3S-specific ports
- **Key Pairs**: Temporary SSH keys for each test session
- **EC2 Instances**: Launched with latest AMIs and proper tagging
- **Network Configuration**: Automatic VPC and subnet selection

## Prerequisites

### 1. AWS CLI Installation and Configuration
```bash
# Install AWS CLI (if not already installed)
brew install awscli  # macOS
# or
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Authenticate with AWS (required before testing)
aws-azure-login
```

### 2. Ruby Environment
```bash
# Ensure Ruby is installed
ruby --version

# Required gems are built-in: json, open3, yaml, securerandom, base64
```

### 3. Repository Setup
```bash
git clone <your-k3s-puppet-repo>
cd k3s-puppet
```

## Supported Operating Systems

The testing system uses the latest AMIs for the following operating systems:

| OS | Version | AMI ID | User |
|---|---|---|---|
| Ubuntu | 22.04 LTS | ami-0f6d76bf212f00b86 | ubuntu |
| RHEL | 8.10 | ami-0aeb132689ea6087f | ec2-user |
| openSUSE | Leap 15.6 | ami-0d104f700c1d53625 | ec2-user |
| SLES | 15 SP7 | ami-052cee36f31273da3 | ec2-user |
| Debian | 12 (Bookworm) | ami-0e8d2601dd7a0c105 | admin |
| Rocky Linux | 9.6 | ami-0fadb4bc4d6071e9e | rocky |
| AlmaLinux | 10.0 | ami-03caa4ee6c381105b | ec2-user |
| Fedora | Cloud Base | ami-0596830e5de86d47e | fedora |

## Testing Methods

### Method 1: Quick Single-Node Test (Recommended for First Run)

Test K3S deployment on Ubuntu (fastest and most reliable):

```bash
# Quick Ubuntu test
./ec2-scripts/ec2-test-automation.sh quick-test

# With custom region
AWS_REGION=us-east-1 ./ec2-scripts/ec2-test-automation.sh quick-test
```

**Expected Output:**
```
K3S EC2 Test Automation
=======================
Region: us-west-2
Instance Type: t3.medium
Command: quick-test

[INFO] 2025-06-19 22:30:00 - Checking prerequisites...
[SUCCESS] 2025-06-19 22:30:01 - Prerequisites check passed
[INFO] 2025-06-19 22:30:01 - Starting quick test (Ubuntu single-node)...

Creating temporary AWS resources...
Security Group: sg-abc123def456
Key Pair: k3s-testing-a1b2c3d4

Launching Ubuntu instance...
Instance launched: i-0123456789abcdef0
Instance ready! Public IP: 54.123.45.67

Testing K3S deployment...
K3S deployment completed successfully on Ubuntu 22.04 LTS

✅ K3S Multi-OS Test Report
✅ UBUNTU: active

[SUCCESS] 2025-06-19 22:35:00 - Quick test completed successfully
```

### Method 2: Full Multi-OS Testing

Test all supported operating systems:

```bash
# Test all OS (takes 60-90 minutes)
./ec2-scripts/ec2-test-automation.sh full-test
```

### Method 3: Multi-Node Testing

Test multi-node deployment with mixed operating systems:

```bash
# Multi-node test (Ubuntu server + RHEL/openSUSE/Debian agents)
./ec2-scripts/ec2-test-automation.sh multi-node-test
```

### Method 4: Performance Testing

Compare deployment performance across operating systems:

```bash
# Performance comparison
./ec2-scripts/ec2-test-automation.sh performance-test
```

### Method 5: Individual OS Testing

Test specific operating systems:

```bash
# Test single OS
./ec2-scripts/k3s-multi-os-testing.sh single ubuntu
./ec2-scripts/k3s-multi-os-testing.sh single rhel
./ec2-scripts/k3s-multi-os-testing.sh single opensuse

# Test all OS
./ec2-scripts/k3s-multi-os-testing.sh single
```

## Resource Management

### Automatic Cleanup

All resources are automatically cleaned up after each test session. However, you can manually clean up if needed:

```bash
# Clean up all test resources
./ec2-scripts/ec2-test-automation.sh cleanup

# Or using the multi-OS script
./ec2-scripts/k3s-multi-os-testing.sh cleanup
```

### Check Current Status

View running test instances:

```bash
# Show current test instances
./ec2-scripts/ec2-test-automation.sh status

# Or using the multi-OS script
./ec2-scripts/k3s-multi-os-testing.sh list
```

### Session-Based Resource Tracking

Each test session creates resources with unique identifiers:
- **Session ID**: 8-character hex string (e.g., `a1b2c3d4`)
- **Security Group**: `k3s-testing-{session-id}`
- **Key Pair**: `k3s-testing-{session-id}`
- **Instances**: Tagged with `SessionId` and `CreatedBy=k3s-multi-os-testing`

## Configuration Options

### Environment Variables

```bash
# AWS region (default: us-west-2)
export AWS_REGION=us-east-1

# Instance type (default: t3.medium - 2 vCPU, 4GB RAM)
export INSTANCE_TYPE=t3.large

# Enable verbose output
export VERBOSE=true
```

### Command Line Options

```bash
# Use different region
./ec2-scripts/ec2-test-automation.sh -r us-east-1 quick-test

# Use different instance type
./ec2-scripts/ec2-test-automation.sh -t t3.large full-test

# Verbose output
./ec2-scripts/ec2-test-automation.sh -v quick-test
```

## Test Scenarios

### 1. Single-Node Deployment
- Launches one instance per OS
- Installs K3S in server mode
- Verifies cluster functionality
- Tests basic pod deployment

### 2. Multi-Node Deployment
- Ubuntu server node (cluster initialization)
- Multiple agent nodes with different OS
- Tests cross-OS cluster communication
- Verifies automated token sharing

### 3. Performance Testing
- Measures deployment time per OS
- Compares resource usage
- Identifies optimal configurations

## Expected Test Results

### Successful Test Output
```
K3S Multi-OS Test Report
========================
Session ID: a1b2c3d4e5f6g7h8
Timestamp: 2025-06-19T22:30:00Z
Region: us-west-2
Instance Type: t3.medium

Summary:
  Total Tests: 8
  Successful: 8
  Failed: 0

✅ PASS UBUNTU: active
✅ PASS RHEL: active
✅ PASS OPENSUSE: active
✅ PASS SLES: active
✅ PASS DEBIAN: active
✅ PASS ROCKY: active
✅ PASS ALMALINUX: active
✅ PASS FEDORA: active
```

### Test Failure Indicators
```
❌ FAIL RHEL: FAILED
❌ FAIL OPENSUSE: SSH connection failed after 30 attempts
```

## Troubleshooting

### Common Issues

#### 1. AWS Authentication
```bash
# Error: AWS credentials not configured or expired
# Solution: Run aws-azure-login
aws-azure-login

# Verify credentials
aws sts get-caller-identity
```

#### 2. Resource Limits
```bash
# Error: Instance limit exceeded
# Solution: Check AWS service limits or use different region
aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A
```

#### 3. AMI Access Issues
```bash
# Error: AMI not accessible
# Solution: Verify region and AMI availability
aws ec2 describe-images --image-ids ami-0f6d76bf212f00b86 --region us-west-2
```

#### 4. Network Connectivity
```bash
# Error: SSH timeout
# Solution: Check security group rules and instance status
aws ec2 describe-instances --instance-ids i-1234567890abcdef0
```

#### 5. Instance Connection Issues
```bash
# Check security group allows SSH (port 22)
aws ec2 describe-security-groups --group-ids sg-xxxxxxxxx

# Verify key pair permissions
chmod 400 ~/.ssh/your-key.pem
```

#### 6. K3S Service Not Starting
```bash
# Check service status
sudo systemctl status k3s
sudo journalctl -u k3s --no-pager

# Common fixes
sudo systemctl daemon-reload
sudo systemctl restart k3s
```

#### 7. RPM Lock Issues on RHEL-Based Systems

**Problem**: Agent installation fails with "can't create transaction lock" error
```
error: can't create transaction lock on /var/lib/rpm/.rpm.lock (Resource temporarily unavailable)
```

**Root Cause**: Multiple package managers running simultaneously, often due to:
- AWS Systems Manager agent running automatic updates
- Cloud-init installing packages
- Multiple yum/dnf processes

**Solution 1**: Use the dedicated fix script
```bash
# On the agent node
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/k3s-puppet/main/ec2-scripts/fix-agent-rpm-lock.sh
chmod +x fix-agent-rpm-lock.sh
sudo ./fix-agent-rpm-lock.sh <server_ip> <token>
```

**Solution 2**: Manual RPM lock cleanup
```bash
# Wait for existing operations to complete
while sudo fuser /var/lib/rpm/.rpm.lock >/dev/null 2>&1; do
    echo "Waiting for RPM lock..."
    sleep 10
done

# Kill hanging processes
sudo pkill -f "yum|dnf|rpm" 2>/dev/null || true

# Stop conflicting services temporarily
sudo systemctl stop amazon-ssm-agent packagekit 2>/dev/null || true

# Remove stale lock files
sudo rm -f /var/lib/rpm/.rpm.lock /var/lib/rpm/.dbenv.lock

# Install K3S
curl -sfL https://get.k3s.io | K3S_URL=https://<server_ip>:6443 K3S_TOKEN=<token> sh -

# Restart services
sudo systemctl start amazon-ssm-agent packagekit 2>/dev/null || true
```

**Solution 3**: Skip SELinux package if persistent issues
```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_SELINUX_RPM=true K3S_URL=https://<server_ip>:6443 K3S_TOKEN=<token> sh -
```

#### 8. Token Extraction Issues

### Debug Mode

Enable verbose logging for troubleshooting:

```bash
# Enable debug output
./ec2-scripts/ec2-test-automation.sh -v quick-test

# Check AWS CLI debug
AWS_CLI_FILE_ENCODING=UTF-8 aws sts get-caller-identity --debug
```

### Manual Cleanup

If automatic cleanup fails:

```bash
# List test instances
aws ec2 describe-instances \
  --filters "Name=tag:CreatedBy,Values=k3s-multi-os-testing" \
  --query "Reservations[].Instances[?State.Name!='terminated'].[InstanceId,Tags[?Key=='Name'].Value|[0]]" \
  --output table

# Terminate specific instances
aws ec2 terminate-instances --instance-ids i-1234567890abcdef0

# Delete security groups
aws ec2 delete-security-group --group-id sg-abc123def456

# Delete key pairs
aws ec2 delete-key-pair --key-name k3s-testing-a1b2c3d4
```

## Cost Management

### Estimated Costs (us-west-2)

| Test Type | Duration | Instances | Estimated Cost |
|---|---|---|---|
| Quick Test | 15 minutes | 1 x t3.medium | $0.01 |
| Full Test | 90 minutes | 8 x t3.medium | $0.50 |
| Multi-Node Test | 45 minutes | 4 x t3.medium | $0.12 |
| Performance Test | 60 minutes | 4 x t3.medium | $0.17 |

### Cost Optimization

```bash
# Use smaller instance type for basic testing
INSTANCE_TYPE=t3.small ./ec2-scripts/ec2-test-automation.sh quick-test

# Use different region for lower costs
AWS_REGION=us-east-1 ./ec2-scripts/ec2-test-automation.sh quick-test

# Always clean up after testing
./ec2-scripts/ec2-test-automation.sh cleanup
```

## Security Considerations

### Temporary Resources
- Security groups are session-specific and automatically deleted
- SSH keys are generated per session and stored in `/tmp`
- All resources are tagged for easy identification and cleanup

### Network Security
- Security groups allow SSH (22) from 0.0.0.0/0 for testing
- K3S ports (6443, 10250, 8472) are restricted to same security group
- Consider using VPN or IP restrictions for production testing

### Key Management
- SSH keys are automatically generated and cleaned up
- Private keys are stored with 600 permissions in `/tmp`
- Keys are deleted after each test session

## Advanced Usage

### Custom AMI Testing

To test with custom AMIs, modify the `LATEST_AMIS` hash in `ec2-scripts/aws_ec2_testing.rb`:

```ruby
LATEST_AMIS = {
  'custom-os' => {
    'ami_id' => 'ami-your-custom-ami',
    'name' => 'Custom OS',
    'user' => 'custom-user',
    'package_manager' => 'apt'  # or 'dnf', 'zypper'
  }
}
```

### Integration with CI/CD

```yaml
# GitHub Actions example
name: K3S Multi-OS Testing
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v1
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-west-2
      - name: Run K3S tests
        run: ./ec2-scripts/ec2-test-automation.sh quick-test
```

## Support and Contribution

For issues, questions, or contributions:
1. Check the troubleshooting section above
2. Review test logs and error messages
3. Open an issue with detailed error information
4. Include session ID and timestamp for resource tracking

## Changelog

### Version 2.0 (Current)
- **Temporary Resource Management**: Automatic creation and cleanup of AWS resources
- **Latest AMI Support**: Updated to use latest AMIs for all supported OS
- **Enhanced Error Handling**: Better error messages and recovery
- **Session-Based Tracking**: Unique session IDs for resource management
- **Expanded OS Support**: Added Rocky Linux, AlmaLinux, and Fedora
- **Performance Testing**: Added deployment time measurement
- **Improved Documentation**: Comprehensive troubleshooting and examples

### Version 1.0 (Legacy)
- Manual resource management with user-provided security groups and key pairs
- Limited OS support (Ubuntu, RHEL, openSUSE, SLES, Debian)
- Basic testing functionality 