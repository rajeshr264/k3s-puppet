#!/bin/bash
# K3S EC2 Test Automation Script
# Comprehensive testing with temporary AWS resource management
# Updated to use latest AMIs and automated resource cleanup

set -e

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly AWS_REGION="${AWS_REGION:-us-west-2}"
readonly INSTANCE_TYPE="${INSTANCE_TYPE:-t3.medium}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Show usage
show_usage() {
    cat << EOF
K3S EC2 Test Automation Script

Usage: $0 [OPTIONS] <command>

Commands:
    quick-test              Quick single-node test (Ubuntu only)
    full-test               Test all supported operating systems
    multi-node-test         Test multi-node deployment
    performance-test        Performance testing across OS
    cleanup                 Clean up all test resources
    status                  Show current test instances

Options:
    -r, --region REGION     AWS region (default: us-west-2)
    -t, --type TYPE         Instance type (default: t3.medium)
    -v, --verbose           Verbose output
    -h, --help              Show this help

Examples:
    $0 quick-test                    # Quick Ubuntu test
    $0 full-test                     # Test all OS
    $0 multi-node-test               # Multi-node deployment
    $0 -r us-east-1 full-test        # Test in us-east-1

Prerequisites:
    - AWS CLI installed and configured
    - Run 'aws-azure-login' for authentication
    - Ruby with required gems

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -t|--type)
                INSTANCE_TYPE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                COMMAND="$1"
                shift
                break
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws >/dev/null 2>&1; then
        error "AWS CLI not found. Please install AWS CLI."
        exit 1
    fi
    
    # Check Ruby
    if ! command -v ruby >/dev/null 2>&1; then
        error "Ruby not found. Please install Ruby."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity --region "$AWS_REGION" >/dev/null 2>&1; then
        warn "AWS credentials not configured or expired."
        log "Please run: aws-azure-login"
        exit 1
    fi
    
    # Check Ruby testing library
    if [[ ! -f "$SCRIPT_DIR/aws_ec2_testing.rb" ]]; then
        error "AWS EC2 testing library not found at $SCRIPT_DIR/aws_ec2_testing.rb"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Quick test - single Ubuntu instance
quick_test() {
    log "Starting quick test (Ubuntu single-node)..."
    
    cat > /tmp/k3s_quick_test.rb << EOF
#!/usr/bin/env ruby
require_relative '$SCRIPT_DIR/aws_ec2_testing'

testing = AwsEc2K3sTesting.new
test_results = []

begin
  puts "Creating temporary AWS resources..."
  testing.create_temp_resources
  
  puts "Launching Ubuntu instance..."
  instance_info = testing.launch_instance('ubuntu', 'single')
  
  puts "Testing K3S deployment..."
  result = testing.test_instance(instance_info)
  test_results << result
  
  # Generate report
  testing.generate_test_report(test_results)
  
ensure
  puts "Cleaning up resources..."
  testing.cleanup_temp_resources
end

exit(test_results.any? { |r| !r['success'] } ? 1 : 0)
EOF
    
    ruby /tmp/k3s_quick_test.rb
    local exit_code=$?
    rm -f /tmp/k3s_quick_test.rb
    
    if [[ $exit_code -eq 0 ]]; then
        success "Quick test completed successfully"
    else
        error "Quick test failed"
    fi
    
    return $exit_code
}

# Full test - all supported operating systems
full_test() {
    log "Starting full test (all supported operating systems)..."
    
    cat > /tmp/k3s_full_test.rb << EOF
#!/usr/bin/env ruby
require_relative '$SCRIPT_DIR/aws_ec2_testing'

# All supported operating systems
os_list = ['ubuntu', 'rhel', 'opensuse', 'sles', 'debian', 'rocky', 'almalinux', 'fedora']

testing = AwsEc2K3sTesting.new
test_results = []

begin
  puts "Creating temporary AWS resources..."
  testing.create_temp_resources
  
  os_list.each do |os|
    puts "\n" + "="*60
    puts "Testing #{os.upcase}"
    puts "="*60
    
    begin
      puts "Launching #{os} instance..."
      instance_info = testing.launch_instance(os, 'single')
      
      puts "Testing K3S deployment on #{os}..."
      result = testing.test_instance(instance_info)
      test_results << result
      
      if result['success']
        puts "✅ #{os.upcase} test PASSED"
      else
        puts "❌ #{os.upcase} test FAILED"
      end
      
    rescue => e
      puts "❌ #{os.upcase} test FAILED: #{e.message}"
      test_results << {
        'success' => false,
        'os' => os,
        'error' => e.message
      }
    end
  end
  
  # Generate comprehensive report
  testing.generate_test_report(test_results)
  
ensure
  puts "Cleaning up all resources..."
  testing.cleanup_temp_resources
end

# Exit with error if any tests failed
failed_tests = test_results.count { |r| !r['success'] }
puts "\nFinal Results: #{test_results.count { |r| r['success'] }} passed, #{failed_tests} failed"
exit(failed_tests > 0 ? 1 : 0)
EOF
    
    ruby /tmp/k3s_full_test.rb
    local exit_code=$?
    rm -f /tmp/k3s_full_test.rb
    
    if [[ $exit_code -eq 0 ]]; then
        success "Full test completed successfully"
    else
        error "Full test completed with failures"
    fi
    
    return $exit_code
}

# Multi-node test
multi_node_test() {
    log "Starting multi-node test (mixed operating systems)..."
    
    cat > /tmp/k3s_multi_node_test.rb << EOF
#!/usr/bin/env ruby
require_relative '$SCRIPT_DIR/aws_ec2_testing'

testing = AwsEc2K3sTesting.new
test_results = []

begin
  puts "Creating temporary AWS resources..."
  testing.create_temp_resources
  
  puts "\n" + "="*60
  puts "Multi-Node K3S Deployment Test"
  puts "="*60
  
  # Launch server node (Ubuntu - most stable)
  puts "\nLaunching server node (Ubuntu)..."
  server_info = testing.launch_instance('ubuntu', 'server')
  
  # Launch agent nodes with different OS
  agent_configs = [
    { os: 'rhel', name: 'RHEL Agent' },
    { os: 'opensuse', name: 'openSUSE Agent' },
    { os: 'debian', name: 'Debian Agent' }
  ]
  
  agent_instances = []
  agent_configs.each do |config|
    puts "\nLaunching #{config[:name]} (#{config[:os]})..."
    agent_info = testing.launch_instance(config[:os], 'agent')
    agent_instances << agent_info
  end
  
  # Test server node
  puts "\nTesting server node..."
  server_result = testing.test_instance(server_info)
  test_results << server_result
  
  # Test agent nodes
  agent_instances.each do |agent_info|
    puts "\nTesting #{agent_info['os']} agent node..."
    agent_result = testing.test_instance(agent_info)
    test_results << agent_result
  end
  
  # Generate report
  testing.generate_test_report(test_results)
  
ensure
  puts "Cleaning up all resources..."
  testing.cleanup_temp_resources
end

# Exit with error if any tests failed
failed_tests = test_results.count { |r| !r['success'] }
puts "\nMulti-Node Results: #{test_results.count { |r| r['success'] }} passed, #{failed_tests} failed"
exit(failed_tests > 0 ? 1 : 0)
EOF
    
    ruby /tmp/k3s_multi_node_test.rb
    local exit_code=$?
    rm -f /tmp/k3s_multi_node_test.rb
    
    if [[ $exit_code -eq 0 ]]; then
        success "Multi-node test completed successfully"
    else
        error "Multi-node test completed with failures"
    fi
    
    return $exit_code
}

# Performance test
performance_test() {
    log "Starting performance test across operating systems..."
    
    cat > /tmp/k3s_performance_test.rb << EOF
#!/usr/bin/env ruby
require_relative '$SCRIPT_DIR/aws_ec2_testing'
require 'benchmark'

# Test subset of OS for performance comparison
performance_os = ['ubuntu', 'rhel', 'opensuse', 'debian']

testing = AwsEc2K3sTesting.new
test_results = []

begin
  puts "Creating temporary AWS resources..."
  testing.create_temp_resources
  
  performance_os.each do |os|
    puts "\n" + "="*60
    puts "Performance Testing #{os.upcase}"
    puts "="*60
    
    deployment_time = Benchmark.realtime do
      begin
        puts "Launching #{os} instance..."
        instance_info = testing.launch_instance(os, 'single')
        
        puts "Testing K3S deployment performance on #{os}..."
        result = testing.test_instance(instance_info)
        result['deployment_time'] = deployment_time
        test_results << result
        
      rescue => e
        puts "❌ #{os.upcase} performance test FAILED: #{e.message}"
        test_results << {
          'success' => false,
          'os' => os,
          'error' => e.message,
          'deployment_time' => deployment_time
        }
      end
    end
    
    puts "#{os.upcase} deployment time: #{deployment_time.round(2)} seconds"
  end
  
  # Generate performance report
  puts "\n" + "="*60
  puts "Performance Summary"
  puts "="*60
  
  test_results.each do |result|
    status = result['success'] ? "✅ PASS" : "❌ FAIL"
    time = result['deployment_time'] ? "#{result['deployment_time'].round(2)}s" : "N/A"
    puts "#{status} #{result['os'].upcase}: #{time}"
  end
  
  testing.generate_test_report(test_results)
  
ensure
  puts "Cleaning up all resources..."
  testing.cleanup_temp_resources
end

# Exit with error if any tests failed
failed_tests = test_results.count { |r| !r['success'] }
exit(failed_tests > 0 ? 1 : 0)
EOF
    
    ruby /tmp/k3s_performance_test.rb
    local exit_code=$?
    rm -f /tmp/k3s_performance_test.rb
    
    if [[ $exit_code -eq 0 ]]; then
        success "Performance test completed successfully"
    else
        error "Performance test completed with failures"
    fi
    
    return $exit_code
}

# Cleanup all resources
cleanup_resources() {
    log "Cleaning up all K3S test resources..."
    
    # Use the k3s-multi-os-testing.sh script for cleanup
    if [[ -f "$SCRIPT_DIR/k3s-multi-os-testing.sh" ]]; then
        bash "$SCRIPT_DIR/k3s-multi-os-testing.sh" cleanup
    else
        warn "k3s-multi-os-testing.sh not found, using direct cleanup"
        
        # Direct cleanup using AWS CLI
        aws ec2 describe-instances \
            --filters "Name=tag:CreatedBy,Values=k3s-multi-os-testing" \
            --query "Reservations[].Instances[?State.Name!='terminated'].InstanceId" \
            --output text \
            --region "$AWS_REGION" | \
        xargs -r aws ec2 terminate-instances --instance-ids --region "$AWS_REGION"
    fi
    
    success "Cleanup completed"
}

# Show status of test instances
show_status() {
    log "Showing status of K3S test instances..."
    
    if [[ -f "$SCRIPT_DIR/k3s-multi-os-testing.sh" ]]; then
        bash "$SCRIPT_DIR/k3s-multi-os-testing.sh" list
    else
        aws ec2 describe-instances \
            --filters "Name=tag:CreatedBy,Values=k3s-multi-os-testing" \
            --query "Reservations[].Instances[?State.Name!='terminated'].[InstanceId,Tags[?Key=='Name'].Value|[0],Tags[?Key=='OS'].Value|[0],State.Name,PublicIpAddress]" \
            --output table \
            --region "$AWS_REGION"
    fi
}

# Main execution
main() {
    # Parse arguments
    parse_args "$@"
    
    # Show script header
    cat << EOF

K3S EC2 Test Automation
=======================
Region: $AWS_REGION
Instance Type: $INSTANCE_TYPE
Command: ${COMMAND:-help}

EOF
    
    # Check prerequisites for commands that need them
    case "$COMMAND" in
        quick-test|full-test|multi-node-test|performance-test)
            check_prerequisites
            ;;
    esac
    
    # Execute command
    case "$COMMAND" in
        quick-test)
            quick_test
            ;;
        full-test)
            full_test
            ;;
        multi-node-test)
            multi_node_test
            ;;
        performance-test)
            performance_test
            ;;
        cleanup)
            cleanup_resources
            ;;
        status)
            show_status
            ;;
        help|"")
            show_usage
            ;;
        *)
            error "Unknown command: $COMMAND"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@" 