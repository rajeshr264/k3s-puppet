# AWS Configuration Guide

This guide explains how to configure the K3S Puppet module for AWS EC2 testing using environment variables.

## Environment Variables

The module supports the following environment variables for AWS configuration:

### Required Configuration

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `AWS_SECURITY_GROUP` | Security group name for EC2 instances | `k3s-testing-security-group` | `my-k3s-security-group` |
| `AWS_KEY_NAME` | EC2 key pair name | `k3s-testing-key` | `my-aws-key` |
| `AWS_KEY_PATH` | Path to private key file | `$HOME/keys/$AWS_KEY_NAME.pem` | `$HOME/.ssh/my-key.pem` |
| `AWS_REGION` | AWS region for testing | `us-west-2` | `us-east-1` |

### Optional Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `INSTANCE_TYPE` | EC2 instance type | `t3.medium` |
| `SUBNET_TYPE` | Subnet type (public/private) | `public` |

## Setup Instructions

### 1. Set Environment Variables

Create a configuration file (e.g., `~/.k3s-aws-config`):

```bash
#!/bin/bash
# K3S AWS Testing Configuration

export AWS_SECURITY_GROUP="your-security-group-name"
export AWS_KEY_NAME="your-key-pair-name"
export AWS_KEY_PATH="$HOME/keys/your-key-pair-name.pem"
export AWS_REGION="us-west-2"

# Optional settings
export INSTANCE_TYPE="t3.medium"
export SUBNET_TYPE="public"
```

### 2. Load Configuration

Source the configuration before running tests:

```bash
source ~/.k3s-aws-config
```

Or export variables directly:

```bash
export AWS_SECURITY_GROUP="my-k3s-sg"
export AWS_KEY_NAME="my-aws-key"
export AWS_KEY_PATH="$HOME/.ssh/my-aws-key.pem"
export AWS_REGION="us-east-1"
```

### 3. Verify Configuration

Check that your configuration is loaded:

```bash
echo "Security Group: $AWS_SECURITY_GROUP"
echo "Key Name: $AWS_KEY_NAME"
echo "Key Path: $AWS_KEY_PATH"
echo "Region: $AWS_REGION"
```

## Prerequisites

### 1. AWS CLI Installation

```bash
# macOS
brew install awscli

# Linux (Ubuntu/Debian)
sudo apt-get install awscli

# Linux (RHEL/CentOS)
sudo yum install awscli
```

### 2. AWS Authentication

```bash
# If using aws-azure-login
aws-azure-login

# Or configure AWS credentials directly
aws configure
```

### 3. Security Group Setup

Create a security group with the following ports open:

```bash
# Create security group
aws ec2 create-security-group \
    --group-name "$AWS_SECURITY_GROUP" \
    --description "K3S testing security group" \
    --region "$AWS_REGION"

# Add K3S-specific rules
aws ec2 authorize-security-group-ingress \
    --group-name "$AWS_SECURITY_GROUP" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --region "$AWS_REGION"

aws ec2 authorize-security-group-ingress \
    --group-name "$AWS_SECURITY_GROUP" \
    --protocol tcp \
    --port 6443 \
    --cidr 0.0.0.0/0 \
    --region "$AWS_REGION"

aws ec2 authorize-security-group-ingress \
    --group-name "$AWS_SECURITY_GROUP" \
    --protocol tcp \
    --port 10250 \
    --cidr 0.0.0.0/0 \
    --region "$AWS_REGION"
```

### 4. Key Pair Setup

```bash
# Create key pair
aws ec2 create-key-pair \
    --key-name "$AWS_KEY_NAME" \
    --region "$AWS_REGION" \
    --query 'KeyMaterial' \
    --output text > "$AWS_KEY_PATH"

# Set proper permissions
chmod 600 "$AWS_KEY_PATH"
```

## Usage Examples

### Run Single Node Tests

```bash
# Test all operating systems
./ec2-scripts/k3s-multi-os-testing.sh single

# Test specific OS
./ec2-scripts/k3s-multi-os-testing.sh single ubuntu
```

### Run Multi-Node Tests

```bash
# Multi-node with automated token sharing
./ec2-scripts/k3s-multi-os-testing.sh multi
```

### Cleanup Resources

```bash
# List running instances
./ec2-scripts/k3s-multi-os-testing.sh list

# Cleanup all test instances
./ec2-scripts/k3s-multi-os-testing.sh cleanup
```

## Troubleshooting

### Common Issues

1. **Permission Denied for Key File**
   ```bash
   chmod 600 "$AWS_KEY_PATH"
   ```

2. **Security Group Not Found**
   ```bash
   aws ec2 describe-security-groups --group-names "$AWS_SECURITY_GROUP" --region "$AWS_REGION"
   ```

3. **Key Pair Not Found**
   ```bash
   aws ec2 describe-key-pairs --key-names "$AWS_KEY_NAME" --region "$AWS_REGION"
   ```

4. **AWS Credentials Expired**
   ```bash
   aws-azure-login
   # or
   aws configure
   ```

### Validation Commands

```bash
# Check AWS authentication
aws sts get-caller-identity

# Validate security group
aws ec2 describe-security-groups --group-names "$AWS_SECURITY_GROUP" --region "$AWS_REGION"

# Validate key pair
aws ec2 describe-key-pairs --key-names "$AWS_KEY_NAME" --region "$AWS_REGION"

# Test key file access
ls -la "$AWS_KEY_PATH"
```

## Cost Management

### Estimated Costs (us-west-2)

| Test Type | Duration | Instances | Est. Cost |
|-----------|----------|-----------|-----------|
| Single Node (1 OS) | 10 min | 1 x t3.medium | $0.05 |
| Single Node (All OS) | 15 min | 5 x t3.medium | $0.25 |
| Multi-Node | 20 min | 3 x t3.medium | $0.30 |

### Cost Optimization

- Tests automatically terminate instances after completion
- Use `cleanup` command to ensure no orphaned instances
- Monitor costs with AWS Cost Explorer
- Set up billing alerts for unexpected charges

## Security Considerations

- Use least-privilege IAM policies
- Restrict security group access to necessary IPs
- Store private keys securely (not in version control)
- Regularly rotate access keys
- Use temporary credentials when possible

## Support

For issues with AWS configuration:
1. Check AWS documentation
2. Verify IAM permissions
3. Ensure all prerequisites are met
4. Review AWS CloudTrail logs for API errors 