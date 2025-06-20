#!/bin/bash
# list-k3s-instances.sh - List all K3S test instances across regions
# Usage: ./list-k3s-instances.sh [region]

set -e

# Configuration
REGION="${1:-us-west-2}"

echo "📋 K3S Test Instances Report"
echo "Region: $REGION"
echo "="*50

# Function to check if AWS CLI is available
check_aws_cli() {
    if ! command -v aws >/dev/null 2>&1; then
        echo "❌ AWS CLI not found. Please install AWS CLI."
        exit 1
    fi
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        echo "❌ AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
}

# Function to list instances
list_instances() {
    echo "🔍 Searching for K3S test instances..."
    
    local instances_json
    instances_json=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters \
            "Name=tag:Name,Values=k3s-test-*" \
            "Name=tag:CreatedBy,Values=k3s-multi-os-testing" \
        --query 'Reservations[].Instances[].{
            InstanceId:InstanceId,
            Name:Tags[?Key==`Name`].Value|[0],
            SessionId:Tags[?Key==`SessionId`].Value|[0],
            OS:Tags[?Key==`OS`].Value|[0],
            DeploymentType:Tags[?Key==`DeploymentType`].Value|[0],
            State:State.Name,
            LaunchTime:LaunchTime,
            InstanceType:InstanceType,
            PublicIpAddress:PublicIpAddress,
            PrivateIpAddress:PrivateIpAddress
        }' \
        --output json 2>/dev/null || echo "[]")
    
    local count
    count=$(echo "$instances_json" | jq 'length')
    
    if [ "$count" -eq 0 ]; then
        echo "✅ No K3S test instances found"
        return 0
    fi
    
    echo "📊 Found $count instance(s):"
    echo ""
    
    # Group by state
    local running_count stopped_count terminated_count other_count
    running_count=$(echo "$instances_json" | jq '[.[] | select(.State == "running")] | length')
    stopped_count=$(echo "$instances_json" | jq '[.[] | select(.State == "stopped")] | length')
    terminated_count=$(echo "$instances_json" | jq '[.[] | select(.State == "terminated")] | length')
    other_count=$(echo "$instances_json" | jq '[.[] | select(.State != "running" and .State != "stopped" and .State != "terminated")] | length')
    
    echo "📈 Summary by State:"
    echo "   🟢 Running: $running_count"
    echo "   🔴 Stopped: $stopped_count"
    echo "   ⚫ Terminated: $terminated_count"
    echo "   🟡 Other: $other_count"
    echo ""
    
    # Display detailed list
    echo "📝 Detailed List:"
    echo ""
    
    echo "$instances_json" | jq -r 'sort_by(.LaunchTime) | reverse | .[] | 
        @base64' | while read -r instance; do
        local decoded
        decoded=$(echo "$instance" | base64 -d)
        
        local instance_id name session_id os deployment_type state launch_time instance_type public_ip private_ip
        instance_id=$(echo "$decoded" | jq -r '.InstanceId')
        name=$(echo "$decoded" | jq -r '.Name // "unknown"')
        session_id=$(echo "$decoded" | jq -r '.SessionId // "unknown"')
        os=$(echo "$decoded" | jq -r '.OS // "unknown"')
        deployment_type=$(echo "$decoded" | jq -r '.DeploymentType // "unknown"')
        state=$(echo "$decoded" | jq -r '.State')
        launch_time=$(echo "$decoded" | jq -r '.LaunchTime')
        instance_type=$(echo "$decoded" | jq -r '.InstanceType')
        public_ip=$(echo "$decoded" | jq -r '.PublicIpAddress // "none"')
        private_ip=$(echo "$decoded" | jq -r '.PrivateIpAddress // "none"')
        
        # Calculate age
        local launch_timestamp age_seconds age_hours age_days
        launch_timestamp=$(date -d "$launch_time" +%s 2>/dev/null || echo "0")
        age_seconds=$(($(date +%s) - launch_timestamp))
        age_hours=$((age_seconds / 3600))
        age_days=$((age_hours / 24))
        
        # State emoji
        local state_emoji
        case "$state" in
            "running") state_emoji="🟢" ;;
            "stopped") state_emoji="🔴" ;;
            "terminated") state_emoji="⚫" ;;
            "pending") state_emoji="🟡" ;;
            "stopping") state_emoji="🟠" ;;
            *) state_emoji="❓" ;;
        esac
        
        echo "  $state_emoji $instance_id ($name)"
        echo "     Session: $session_id"
        echo "     OS: $os | Type: $deployment_type | Instance: $instance_type"
        echo "     State: $state"
        echo "     Public IP: $public_ip | Private IP: $private_ip"
        if [ $age_days -gt 0 ]; then
            echo "     Age: ${age_days}d ${age_hours}h (launched: $launch_time)"
        else
            echo "     Age: ${age_hours}h (launched: $launch_time)"
        fi
        echo ""
    done
    
    # Cost estimation (rough)
    local running_instances
    running_instances=$(echo "$instances_json" | jq '[.[] | select(.State == "running")]')
    local running_cost_per_hour=0.0464  # Rough estimate for t3.medium
    local total_running_cost_per_hour
    total_running_cost_per_hour=$(echo "$running_count * $running_cost_per_hour" | bc -l 2>/dev/null || echo "0")
    
    if [ "$running_count" -gt 0 ]; then
        echo "💰 Estimated Cost (Running Instances Only):"
        echo "   Per hour: \$$(printf "%.4f" "$total_running_cost_per_hour")"
        echo "   Per day: \$$(echo "$total_running_cost_per_hour * 24" | bc -l | xargs printf "%.2f")"
        echo "   Per month: \$$(echo "$total_running_cost_per_hour * 24 * 30" | bc -l | xargs printf "%.2f")"
        echo ""
        echo "⚠️  Remember to terminate instances when not needed!"
    fi
}

# Function to show cleanup suggestions
show_cleanup_suggestions() {
    echo "🛠️  Cleanup Options:"
    echo ""
    echo "1. Cleanup orphaned instances (older than 24h):"
    echo "   ./ec2-scripts/cleanup-orphaned-instances.sh $REGION"
    echo ""
    echo "2. Dry run to see what would be cleaned:"
    echo "   ./ec2-scripts/cleanup-orphaned-instances.sh $REGION --dry-run"
    echo ""
    echo "3. Manual cleanup of specific instances:"
    echo "   aws ec2 terminate-instances --region $REGION --instance-ids i-xxxxxxxxx"
    echo ""
    echo "4. Cleanup all k3s-test instances (DANGEROUS):"
    echo "   aws ec2 describe-instances --region $REGION \\"
    echo "     --filters 'Name=tag:Name,Values=k3s-test-*' \\"
    echo "     --query 'Reservations[].Instances[?State.Name!=\`terminated\`].InstanceId' \\"
    echo "     --output text | xargs aws ec2 terminate-instances --region $REGION --instance-ids"
}

# Main execution
main() {
    check_aws_cli
    echo ""
    list_instances
    echo ""
    show_cleanup_suggestions
}

# Run main function
main "$@" 