#!/bin/bash
# Test script for K3S Puppet module deployment on AWS

echo "🧪 K3S Puppet Module Testing Options"
echo "===================================="
echo ""
echo "Choose your testing approach:"
echo ""
echo "1. GitHub Download Method (fixed with API URL)"
echo "   - Downloads module from your GitHub repository"
echo "   - Tests the complete GitHub integration workflow"
echo ""
echo "2. Embedded Module Method (guaranteed to work)"
echo "   - Embeds module directly in user data script"
echo "   - Avoids any GitHub download issues"
echo ""
echo "3. Quick script test (no AWS, just generate scripts)"
echo ""

read -p "Enter your choice (1/2/3): " choice

case $choice in
    1)
        echo ""
        echo "🚀 Testing GitHub Download Method..."
        echo "==================================="
        ./ec2-scripts/ec2-test-automation.sh quick-test
        ;;
    2)
        echo ""
        echo "🚀 Testing Embedded Module Method..."
        echo "===================================="
        ruby ec2-scripts/embedded-module-test.rb
        ;;
    3)
        echo ""
        echo "🔍 Testing Script Generation..."
        echo "==============================="
        echo ""
        echo "GitHub Download Method:"
        echo "----------------------"
        ruby ec2-scripts/test_script_generation.rb
        echo ""
        echo "Embedded Module Method:"
        echo "----------------------"
        ruby -e "
        require_relative 'ec2-scripts/embedded-module-test'
        tester = EmbeddedModuleTesting.new
        script = tester.generate_user_data_script('ubuntu', 'single')
        puts 'Script length: ' + script.lines.count.to_s + ' lines'
        puts 'Contains Puppet install: ' + (script.include?('puppet-agent') ? 'YES' : 'NO')
        puts 'Contains embedded module: ' + (script.include?('INIT_EOF') ? 'YES' : 'NO')
        puts 'Contains K3S install: ' + (script.include?('get.k3s.io') ? 'YES' : 'NO')
        "
        ;;
    *)
        echo "Invalid choice. Please run the script again and choose 1, 2, or 3."
        exit 1
        ;;
esac

echo ""
echo "✅ Test completed!" 