#!/bin/bash
# K3S EC2 Testing Script with Ruby 3.3.8
# This script provides an easy interface for testing K3S deployments on EC2

set -e

# Ruby path
RUBY_PATH="/opt/homebrew/Library/Homebrew/vendor/portable-ruby/3.3.8/bin/ruby"
if [ ! -f "$RUBY_PATH" ]; then
    echo "⚠️  Ruby 3.3.8 not found at expected path, falling back to system ruby"
    RUBY_PATH="ruby"
fi

echo "🚀 K3S EC2 Testing with Ruby $(${RUBY_PATH} --version | cut -d' ' -f2)"
echo "=============================================="

# Validate syntax first
echo "🔍 Validating EC2 testing script syntax..."
if ! $RUBY_PATH -c aws_ec2_testing.rb >/dev/null 2>&1; then
    echo "❌ EC2 testing script has syntax errors:"
    $RUBY_PATH -c aws_ec2_testing.rb
    exit 1
fi
echo "✅ EC2 testing script syntax is valid"

# Run pre-deployment test
echo
echo "🔍 Running pre-deployment validation..."
if ! ../k3s_cluster/scripts/pre-deployment-test.sh; then
    echo "❌ Pre-deployment test failed. Please fix issues before continuing."
    exit 1
fi

echo
echo "🎯 Ready to deploy! Choose an option:"
echo "1. Single node Ubuntu test"
echo "2. Multi-node Ubuntu test (1 server + 2 agents)"
echo "3. Single node RHEL test"
echo "4. Custom deployment"
echo "5. List existing instances"
echo "6. Cleanup all test instances"
echo

read -p "Enter your choice (1-6): " choice

case $choice in
    1)
        echo "🚀 Deploying single node Ubuntu K3S cluster..."
        $RUBY_PATH -e "
        require_relative 'aws_ec2_testing.rb'
        tester = AwsEc2K3sTesting.new
        tester.create_temp_resources
        result = tester.launch_instance('ubuntu', 'single')
        puts '✅ Deployment initiated. Check AWS console for progress.'
        puts result
        "
        ;;
    2)
        echo "🚀 Deploying multi-node Ubuntu K3S cluster..."
        $RUBY_PATH -e "
        require_relative 'aws_ec2_testing.rb'
        tester = AwsEc2K3sTesting.new
        tester.create_temp_resources
        
        puts '📡 Launching server node...'
        server = tester.launch_instance('ubuntu', 'server')
        
        puts '🤖 Launching agent nodes...'
        agent1 = tester.launch_instance('ubuntu', 'agent')
        agent2 = tester.launch_instance('ubuntu', 'agent')
        
        puts '✅ Multi-node deployment initiated.'
        puts 'Server:', server
        puts 'Agent 1:', agent1
        puts 'Agent 2:', agent2
        "
        ;;
    3)
        echo "🚀 Deploying single node RHEL K3S cluster..."
        $RUBY_PATH -e "
        require_relative 'aws_ec2_testing.rb'
        tester = AwsEc2K3sTesting.new
        tester.create_temp_resources
        result = tester.launch_instance('rhel', 'single')
        puts '✅ Deployment initiated. Check AWS console for progress.'
        puts result
        "
        ;;
    4)
        echo "📋 Available OS options: ubuntu, rhel, opensuse, sles, debian, rocky, almalinux, fedora"
        echo "📋 Available deployment types: single, server, agent"
        read -p "Enter OS: " os
        read -p "Enter deployment type: " deployment_type
        
        $RUBY_PATH -e "
        require_relative 'aws_ec2_testing.rb'
        tester = AwsEc2K3sTesting.new
        tester.create_temp_resources
        result = tester.launch_instance('$os', '$deployment_type')
        puts '✅ Custom deployment initiated.'
        puts result
        "
        ;;
    5)
        echo "📋 Listing existing test instances..."
        $RUBY_PATH -e "
        require_relative 'aws_ec2_testing.rb'
        tester = AwsEc2K3sTesting.new
        tester.list_test_instances
        "
        ;;
    6)
        echo "🧹 Cleaning up all test instances..."
        read -p "Are you sure you want to cleanup ALL test instances? (y/N): " confirm
        if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
            $RUBY_PATH -e "
            require_relative 'aws_ec2_testing.rb'
            tester = AwsEc2K3sTesting.new
            tester.cleanup_all_resources
            puts '✅ Cleanup completed.'
            "
        else
            echo "Cleanup cancelled."
        fi
        ;;
    *)
        echo "❌ Invalid choice. Please run the script again."
        exit 1
        ;;
esac

echo
echo "🎉 Script completed successfully!"
echo "�� Monitor your instances in the AWS EC2 console"
echo "🔍 Check /var/log/k3s-puppet-install.log on instances for detailed logs"
