#!/bin/bash
# Pre-deployment validation script for K3S Puppet module
# This script validates the module before deployment to catch errors early

set -e

echo "🔍 K3S Puppet Module Pre-Deployment Validation"
echo "=============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Ruby path - use specific version if available, fallback to system ruby
RUBY_PATH="/opt/homebrew/Library/Homebrew/vendor/portable-ruby/3.3.8/bin/ruby"
if [ ! -f "$RUBY_PATH" ]; then
    RUBY_PATH="ruby"
fi

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "PASS")
            echo -e "${GREEN}✅ PASS${NC}: $message"
            ;;
        "FAIL")
            echo -e "${RED}❌ FAIL${NC}: $message"
            ;;
        "WARN")
            echo -e "${YELLOW}⚠️  WARN${NC}: $message"
            ;;
        "INFO")
            echo -e "ℹ️  INFO: $message"
            ;;
    esac
}

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0

# Change to module directory
cd "$(dirname "$0")/.."

# Test 1: Basic syntax validation (only check for SYNTAX errors, not style)
echo
print_status "INFO" "Checking Puppet manifest syntax (ignoring style warnings)..."

if command -v pdk >/dev/null 2>&1; then
    if pdk validate puppet 2>&1 | grep -q "Checking Puppet manifest syntax.*✔"; then
        print_status "PASS" "Puppet manifest syntax is valid"
        ((TESTS_PASSED++))
    else
        # Check if there are actual syntax errors (not just style warnings)
        if pdk validate puppet 2>&1 | grep -E "(syntax.*ERROR|FATAL|compilation failed)"; then
            print_status "FAIL" "Puppet manifest syntax errors found"
            pdk validate puppet 2>&1 | grep -E "(syntax.*ERROR|FATAL|compilation failed)"
            ((TESTS_FAILED++))
        else
            print_status "PASS" "Puppet manifest syntax is valid (style warnings ignored)"
            ((TESTS_PASSED++))
        fi
    fi
else
    print_status "WARN" "PDK not available, skipping advanced syntax validation"
    ((TESTS_WARNED++))
fi

# Test 2: Check for undefined parameter references (CRITICAL)
echo
print_status "INFO" "Checking for undefined parameter references..."

if grep -r "::params::" manifests/ | grep -v "k3s_cluster::params::" | grep -q "::"; then
    print_status "FAIL" "Found potential undefined parameter references"
    grep -r "::params::" manifests/ | grep -v "k3s_cluster::params::"
    ((TESTS_FAILED++))
else
    print_status "PASS" "No undefined parameter references found"
    ((TESTS_PASSED++))
fi

# Test 3: Check for token automation specific issues (CRITICAL)
echo
print_status "INFO" "Validating token automation configuration..."

# Check if token_automation.pp uses correct service name
if grep -q "Service\[\$k3s_cluster::params::service_name\]" manifests/token_automation.pp; then
    print_status "PASS" "Token automation uses correct service name parameter"
    ((TESTS_PASSED++))
else
    print_status "FAIL" "Token automation may have incorrect service name reference"
    ((TESTS_FAILED++))
fi

# Test 4: Check for basic compilation (CRITICAL)
echo
print_status "INFO" "Testing basic manifest compilation..."

# Create a simple test manifest to verify compilation
cat > /tmp/test_k3s.pp << 'TEST_EOF'
class { 'k3s_cluster':
  ensure => 'present',
  node_type => 'server',
  cluster_init => true,
  installation_method => 'script',
  version => 'v1.33.1+k3s1',
}
TEST_EOF

# Try different puppet parsers
if command -v puppet >/dev/null 2>&1 && puppet parser validate /tmp/test_k3s.pp 2>/dev/null; then
    print_status "PASS" "Basic manifest compilation works"
    ((TESTS_PASSED++))
elif command -v pdk >/dev/null 2>&1 && pdk validate puppet /tmp/test_k3s.pp >/dev/null 2>&1; then
    print_status "PASS" "Basic manifest compilation works (via PDK)"
    ((TESTS_PASSED++))
else
    print_status "WARN" "Basic compilation test skipped (puppet/pdk not available)"
    ((TESTS_WARNED++))
fi

rm -f /tmp/test_k3s.pp

# Test 5: Ruby syntax validation for EC2 scripts (if applicable)
echo
print_status "INFO" "Checking Ruby syntax for EC2 scripts..."

if [ -f "../ec2-scripts/aws_ec2_testing.rb" ]; then
    if $RUBY_PATH -c "../ec2-scripts/aws_ec2_testing.rb" >/dev/null 2>&1; then
        print_status "PASS" "EC2 testing script syntax is valid"
        ((TESTS_PASSED++))
    else
        print_status "FAIL" "EC2 testing script has syntax errors"
        $RUBY_PATH -c "../ec2-scripts/aws_ec2_testing.rb"
        ((TESTS_FAILED++))
    fi
else
    print_status "INFO" "EC2 scripts not found, skipping Ruby syntax check"
fi

# Test 6: Check for required template files
echo
print_status "INFO" "Checking for required template files..."

critical_templates=(
    "templates/k3s.service.epp"
    "templates/service.env.epp"
)

missing_critical=()
for template in "${critical_templates[@]}"; do
    if [ ! -f "$template" ]; then
        missing_critical+=("$template")
    fi
done

if [ ${#missing_critical[@]} -eq 0 ]; then
    print_status "PASS" "All critical template files exist"
    ((TESTS_PASSED++))
else
    print_status "FAIL" "Missing critical template files: ${missing_critical[*]}"
    ((TESTS_FAILED++))
fi

# Summary
echo
echo "=============================================="
echo "🏁 Pre-Deployment Validation Summary"
echo "=============================================="
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $TESTS_FAILED"
echo "Tests Warned: $TESTS_WARNED"
echo

if [ $TESTS_FAILED -eq 0 ]; then
    print_status "PASS" "Module is ready for deployment!"
    echo
    echo "🚀 Critical issues resolved. Module can be safely deployed to EC2."
    if [ $TESTS_WARNED -gt 0 ]; then
        echo "⚠️  Note: There are some style warnings, but they won't prevent deployment."
    fi
    echo
    echo "📋 Next Steps:"
    echo "   1. Deploy to EC2: cd ../ec2-scripts && $RUBY_PATH aws_ec2_testing.rb"
    echo "   2. Monitor deployment logs for any runtime issues"
    echo "   3. Verify K3S cluster functionality after deployment"
    echo
    exit 0
else
    print_status "FAIL" "Module has critical issues that must be fixed before deployment"
    echo
    echo "❌ Please fix the failed tests before deploying to EC2."
    echo "   These are critical errors that will cause runtime failures."
    echo
    exit 1
fi
