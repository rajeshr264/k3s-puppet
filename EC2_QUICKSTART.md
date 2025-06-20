# K3S EC2 Quick Start Guide

This guide will get you testing K3S on AWS EC2 in under 10 minutes!

## 🚀 Quick Setup

### 1. Prerequisites (2 minutes)

```bash
# Ensure AWS CLI is installed and configured
aws --version
aws configure list

# Create or verify your EC2 key pair exists
aws ec2 describe-key-pairs --key-names YOUR_KEY_NAME
```

### 2. Set Environment Variables (30 seconds)

```bash
export AWS_KEY_NAME="your-actual-key-name"
export AWS_REGION="us-east-1"  # or your preferred region
```

### 3. Run Single Node Test (5 minutes)

```bash
# Test single node deployment
./ec2-scripts/ec2-test-automation.sh single
```

**Expected Output:**
```
[20:30:15] Checking prerequisites...
[20:30:16] Prerequisites check passed!
[20:30:17] Starting single node K3S test...
[20:30:18] Launching single node instance...
[20:30:20] Launched single node instance: i-1234567890abcdef0
[20:30:21] Waiting for single-node (i-1234567890abcdef0) to be running...
[20:30:45] single-node is ready!
[20:30:46] Single node IP: 54.123.45.67
[20:30:47] SSH connection to 54.123.45.67 successful!
[20:35:47] Testing K3S functionality...
=== K3S Node Status ===
NAME               STATUS   ROLES                  AGE   VERSION
ip-172-31-45-123   Ready    control-plane,master   2m    v1.28.2+k3s1
```

### 4. Connect and Test (1 minute)

```bash
# SSH to your instance (use the IP from output)
ssh -i YOUR_KEY_NAME.pem ubuntu@INSTANCE_IP

# Test kubectl
kubectl get nodes
kubectl get pods -A

# Deploy test application
kubectl create deployment hello-k3s --image=nginx
kubectl get pods
```

## 🏗️ Multi-Node Test (10 minutes)

```bash
# Test multi-node deployment (1 server + 2 agents)
./ec2-scripts/ec2-test-automation.sh multi
```

**What happens:**
1. **Server Launch** (2 min): Launches and configures K3S server
2. **Token Retrieval** (30 sec): Automatically gets cluster token
3. **Agent Launch** (3 min): Launches 2 agent nodes with token
4. **Cluster Join** (3 min): Agents join the cluster
5. **Testing** (1 min): Deploys test workload across nodes

## 📋 Management Commands

```bash
# List all running test instances
./ec2-scripts/ec2-test-automation.sh list

# Cleanup all test instances (saves money!)
./ec2-scripts/ec2-test-automation.sh cleanup

# Show help
./ec2-scripts/ec2-test-automation.sh help
```

## 🔧 Customization

### Different Instance Types
```bash
# Edit the script to change instance types
# t3.medium (default) - good for testing
# t3.large - better performance
# t3.small - cost-effective for agents
```

### Different Regions
```bash
export AWS_REGION="us-west-2"
export AWS_AMI_ID="ami-0abcdef1234567890"  # Ubuntu 22.04 for us-west-2
```

### Custom Security Group
```bash
export AWS_SECURITY_GROUP="my-k3s-sg"
```

## 🐛 Troubleshooting

### "Key pair not found"
```bash
# Create a new key pair
aws ec2 create-key-pair --key-name my-k3s-key --query 'KeyMaterial' --output text > my-k3s-key.pem
chmod 400 my-k3s-key.pem
export AWS_KEY_NAME="my-k3s-key"
```

### "SSH connection failed"
```bash
# Wait longer - EC2 instances take time to boot
# Check security group allows SSH (port 22)
aws ec2 describe-security-groups --group-names k3s-test-sg
```

### "K3S installation failed"
```bash
# SSH to instance and check logs
ssh -i your-key.pem ubuntu@INSTANCE_IP
sudo tail -f /var/log/k3s-setup.log
sudo journalctl -u cloud-init-output -f
```

### "Multi-node agents not joining"
```bash
# Check network connectivity
# From agent to server on port 6443
telnet SERVER_PRIVATE_IP 6443
```

## 💰 Cost Management

**Estimated Costs (us-east-1):**
- Single node (t3.medium): ~$0.04/hour
- Multi-node (1 t3.medium + 2 t3.small): ~$0.08/hour
- **Always run cleanup when done!**

```bash
# Always cleanup to avoid charges
./ec2-scripts/ec2-test-automation.sh cleanup
```

## 🎯 What Gets Tested

### Single Node
- ✅ K3S installation via Puppet
- ✅ Service startup and health
- ✅ Node readiness
- ✅ Basic pod scheduling
- ✅ kubectl access

### Multi-Node
- ✅ Server initialization
- ✅ Automatic token sharing
- ✅ Agent cluster joining
- ✅ Cross-node networking
- ✅ Multi-node pod distribution
- ✅ Cluster-wide service discovery

## 📁 Files Created

```
k3s-puppet/
├── AWS_EC2_TESTING.md      # Comprehensive guide
├── EC2_QUICKSTART.md       # This quick start
└── ec2-scripts/
    ├── single-node-userdata.sh    # Single node setup
    └── ec2-test-automation.sh      # Main automation script
```

## 🔄 Next Steps

After successful testing:

1. **Integrate with your CI/CD**: Use these scripts in your pipeline
2. **Customize the Puppet module**: Add your specific requirements
3. **Production deployment**: Use the full module with proper security
4. **Monitoring**: Add monitoring and alerting for production clusters

## 🆘 Need Help?

1. **Check the comprehensive guide**: `AWS_EC2_TESTING.md`
2. **Review script help**: `./ec2-scripts/ec2-test-automation.sh help`
3. **Debug with SSH**: Connect to instances and check logs
4. **AWS Console**: Monitor instances in EC2 dashboard

---

**Happy K3S testing! 🚀**

Remember to cleanup your instances when done to avoid AWS charges! 