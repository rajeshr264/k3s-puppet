#!/bin/bash
# Enhanced K3S Multi-OS EC2 Testing Script
# Implements TDD approach with comprehensive multi-OS support
# Uses temporary AWS resources (auto-created and cleaned up)

set -e

# Get the directory where this script is located
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration - can be overridden with environment variables
readonly AWS_REGION="${AWS_REGION:-us-west-2}"
readonly INSTANCE_TYPE="${INSTANCE_TYPE:-t3.medium}"

# Supported operating systems (matches latest AMIs)
readonly SUPPORTED_OS=("ubuntu" "rhel" "debian" "rocky" "almalinux" "fedora")

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Show usage information
show_usage() {
    cat << EOF
K3S Multi-OS Testing Script

Usage: $0 <command> [options]

Commands:
    single [os]     Test single node deployment (all OS or specific OS)
    multi           Test multi-node deployment with mixed OS
    list            List all running test instances
    cleanup         Clean up all test resources
    report          Generate test report
    help            Show this help message

Examples:
    $0 single                    # Test all supported operating systems
    $0 single ubuntu             # Test only Ubuntu
    $0 multi                     # Test multi-node deployment
    $0 cleanup                   # Clean up all resources

Supported Operating Systems:
    ${SUPPORTED_OS[*]}

Environment Variables:
    AWS_REGION      AWS region (default: us-west-2)
    INSTANCE_TYPE   EC2 instance type (default: t3.medium)

Prerequisites:
    - AWS CLI installed and configured
    - Run 'aws-azure-login' to authenticate
    - Ruby with required gems (json, securerandom, base64)

EOF
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
    
    # Check AWS credentials and suggest azure-login if needed
    if ! aws sts get-caller-identity --region "$AWS_REGION" >/dev/null 2>&1; then
        warn "AWS credentials not configured or expired."
        log "Please run: aws-azure-login"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Test single node deployment
test_single_node() {
    local target_os="$1"
    
    if [[ -n "$target_os" ]]; then
        if [[ ! " ${SUPPORTED_OS[*]} " =~ " ${target_os} " ]]; then
            error "Unsupported OS: $target_os"
            error "Supported OS: ${SUPPORTED_OS[*]}"
            exit 1
        fi
        log "Testing single node deployment on $target_os"
        test_os_list=("$target_os")
    else
        log "Testing single node deployment on all supported operating systems"
        test_os_list=("${SUPPORTED_OS[@]}")
    fi
    
    # Create Ruby script for testing
    cat > /tmp/k3s_single_test.rb << EOF
#!/usr/bin/env ruby

require_relative '$SCRIPT_DIR/aws_ec2_testing'

def main
  os_list = ARGV
  
  if os_list.empty?
    puts "No operating systems specified"
    exit 1
  end
  
  testing = AwsEc2K3sTesting.new
  test_results = []
  
  begin
    # Create temporary resources
    testing.create_temp_resources
    
    # Test each OS
    os_list.each do |os|
      puts "\n" + "="*50
      puts "Testing #{os.upcase}"
      puts "="*50
      
      begin
        # Launch instance
        instance_info = testing.launch_instance(os, 'single')
        
        # Test the instance
        result = testing.test_instance(instance_info)
        test_results << result
        
        if result['success']
          puts "✅ #{os.upcase} test PASSED"
        else
          puts "❌ #{os.upcase} test FAILED: #{result['error'] || result['k3s_status']}"
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
    
    # Generate final report
    testing.generate_test_report(test_results)
    
  ensure
    # Always cleanup resources
    testing.cleanup_temp_resources
  end
  
  # Exit with error code if any tests failed
  failed_tests = test_results.count { |r| !r['success'] }
  exit(failed_tests > 0 ? 1 : 0)
end

main
EOF
    
    # Run the test
    ruby /tmp/k3s_single_test.rb "${test_os_list[@]}"
    local exit_code=$?
    
    # Cleanup
    rm -f /tmp/k3s_single_test.rb
    
    return $exit_code
}

# Test multi-node deployment
test_multi_node() {
    log "Testing multi-node deployment with mixed operating systems"
    
    # Create Ruby script for multi-node testing
    cat > /tmp/k3s_multi_test.rb << EOF
#!/usr/bin/env ruby

require_relative '$SCRIPT_DIR/aws_ec2_testing'

def main
  testing = AwsEc2K3sTesting.new
  test_results = []
  
  begin
    # Create temporary resources
    testing.create_temp_resources
    
    puts "\n" + "="*60
    puts "Multi-Node K3S Deployment Test"
    puts "="*60
    
    # Launch server node (Ubuntu)
    puts "\nLaunching server node (Ubuntu)..."
    server_info = testing.launch_instance('ubuntu', 'server')
    
    # Launch agent nodes (different OS)
    agent_os_list = ['rhel', 'debian']
    agent_instances = []
    
    agent_os_list.each do |os|
      puts "\nLaunching agent node (#{os.upcase})..."
      agent_info = testing.launch_instance(os, 'agent')
      agent_instances << agent_info
    end
    
    # Test server node
    puts "\nTesting server node..."
    server_result = testing.test_instance(server_info)
    test_results << server_result
    
    # Test agent nodes
    agent_instances.each do |agent_info|
      puts "\nTesting agent node (#{agent_info['os'].upcase})..."
      agent_result = testing.test_instance(agent_info)
      test_results << agent_result
    end
    
    # Generate final report
    testing.generate_test_report(test_results)
    
  ensure
    # Always cleanup resources
    testing.cleanup_temp_resources
  end
  
  # Exit with error code if any tests failed
  failed_tests = test_results.count { |r| !r['success'] }
  exit(failed_tests > 0 ? 1 : 0)
end

main
EOF
    
    # Run the test
    ruby /tmp/k3s_multi_test.rb
    local exit_code=$?
    
    # Cleanup
    rm -f /tmp/k3s_multi_test.rb
    
    return $exit_code
}

# List running test instances
list_instances() {
    log "Listing all K3S test instances..."
    
    cat > /tmp/k3s_list.rb << EOF
#!/usr/bin/env ruby

require_relative '$SCRIPT_DIR/aws_ec2_testing'

testing = AwsEc2K3sTesting.new
testing.list_test_instances
EOF
    
    ruby /tmp/k3s_list.rb
    rm -f /tmp/k3s_list.rb
}

# Cleanup all test resources
cleanup_all() {
    log "Cleaning up all K3S test resources..."
    
    cat > /tmp/k3s_cleanup.rb << EOF
#!/usr/bin/env ruby

require_relative '$SCRIPT_DIR/aws_ec2_testing'

# Find all test instances and clean them up
begin
  result = `aws ec2 describe-instances \
    --filters "Name=tag:CreatedBy,Values=k3s-multi-os-testing" \
    --query "Reservations[].Instances[?State.Name!=\\\`terminated\\\`].Tags[?Key==\\\`SessionId\\\`].Value" \
    --output text \
    --region #{ENV['AWS_REGION'] || 'us-west-2'}`
  
  session_ids = result.strip.split(/\s+/).uniq.reject(&:empty?)
  
  if session_ids.empty?
    puts "No test resources found to cleanup"
  else
    puts "Found #{session_ids.length} test session(s) to cleanup"
    
    session_ids.each do |session_id|
      puts "Cleaning up session: #{session_id}"
      
      # Create testing instance with the session ID
      testing = AwsEc2K3sTesting.new
      testing.instance_variable_set(:@session_id, session_id)
      testing.cleanup_temp_resources
    end
  end
  
rescue => e
  puts "Error during cleanup: #{e.message}"
  exit 1
end
EOF
    
    ruby /tmp/k3s_cleanup.rb
    rm -f /tmp/k3s_cleanup.rb
    
    success "Cleanup completed"
}

# Generate test report
generate_report() {
    log "Generating test report for recent test sessions..."
    
    cat > /tmp/k3s_report.rb << EOF
#!/usr/bin/env ruby

require_relative '$SCRIPT_DIR/aws_ec2_testing'

# This would typically read from stored test results
# For now, just show current instance status
testing = AwsEc2K3sTesting.new
testing.list_test_instances
EOF
    
    ruby /tmp/k3s_report.rb
    rm -f /tmp/k3s_report.rb
}

# Main execution
main() {
    local command="$1"
    shift
    
    case "$command" in
        "single")
            check_prerequisites
            test_single_node "$1"
            ;;
        "multi")
            check_prerequisites
            test_multi_node
            ;;
        "list")
            list_instances
            ;;
        "cleanup")
            cleanup_all
            ;;
        "report")
            generate_report
            ;;
        "help"|"--help"|"-h"|"")
            show_usage
            ;;
        *)
            error "Unknown command: $command"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# Script header
cat << EOF

K3S Multi-OS Testing Script
===========================
Region: $AWS_REGION
Instance Type: $INSTANCE_TYPE

EOF

# Run main function with all arguments
main "$@" 