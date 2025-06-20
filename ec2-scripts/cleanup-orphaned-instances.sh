#!/bin/bash
# cleanup-orphaned-instances.sh - Find and cleanup orphaned K3S test instances
# Usage: ./cleanup-orphaned-instances.sh [region] [--dry-run]

set -e

# Configuration
REGION="${1:-us-west-2}"
DRY_RUN="${2}"
MAX_AGE_HOURS=24  # Only cleanup instances older than 24 hours

echo "🧹 K3S Orphaned Instance Cleanup"
echo "Region: $REGION"
echo "Max Age: $MAX_AGE_HOURS hours"
if [ "$DRY_RUN" = "--dry-run" ]; then
    echo "Mode: DRY RUN (no instances will be terminated)"
else
    echo "Mode: LIVE (instances will be terminated)"
fi
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
    
    echo "✅ AWS CLI configured and credentials valid"
}

# Function to find orphaned instances
find_orphaned_instances() {
    echo "🔍 Searching for orphaned K3S test instances..."
    
    # Find instances with k3s-test naming pattern
    local instances_json
    instances_json=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters \
            "Name=tag:Name,Values=k3s-test-*" \
            "Name=tag:CreatedBy,Values=k3s-multi-os-testing" \
            "Name=instance-state-name,Values=running,pending,stopping,stopped" \
        --query 'Reservations[].Instances[].{
            InstanceId:InstanceId,
            Name:Tags[?Key==`Name`].Value|[0],
            SessionId:Tags[?Key==`SessionId`].Value|[0],
            State:State.Name,
            LaunchTime:LaunchTime,
            InstanceType:InstanceType,
            PublicIpAddress:PublicIpAddress
        }' \
        --output json 2>/dev/null || echo "[]")
    
    echo "$instances_json"
}

# Function to filter instances by age
filter_by_age() {
    local instances_json="$1"
    local current_time
    current_time=$(date -u +%s)
    local max_age_seconds=$((MAX_AGE_HOURS * 3600))
    
    echo "$instances_json" | jq --arg current_time "$current_time" --arg max_age_seconds "$max_age_seconds" '
        map(select(
            (.LaunchTime | fromdateiso8601) < ($current_time | tonumber) - ($max_age_seconds | tonumber)
        ))
    '
}

# Function to display instances
display_instances() {
    local instances_json="$1"
    local count
    count=$(echo "$instances_json" | jq 'length')
    
    if [ "$count" -eq 0 ]; then
        echo "✅ No orphaned instances found"
        return 0
    fi
    
    echo "⚠️  Found $count orphaned instance(s):"
    echo ""
    
    echo "$instances_json" | jq -r '.[] | 
        @base64' | while read -r instance; do
        local decoded
        decoded=$(echo "$instance" | base64 -d)
        
        local instance_id name session_id state launch_time instance_type public_ip
        instance_id=$(echo "$decoded" | jq -r '.InstanceId')
        name=$(echo "$decoded" | jq -r '.Name // "unknown"')
        session_id=$(echo "$decoded" | jq -r '.SessionId // "unknown"')
        state=$(echo "$decoded" | jq -r '.State')
        launch_time=$(echo "$decoded" | jq -r '.LaunchTime')
        instance_type=$(echo "$decoded" | jq -r '.InstanceType')
        public_ip=$(echo "$decoded" | jq -r '.PublicIpAddress // "none"')
        
        # Calculate age
        local launch_timestamp age_seconds age_hours
        launch_timestamp=$(date -d "$launch_time" +%s 2>/dev/null || echo "0")
        age_seconds=$(($(date +%s) - launch_timestamp))
        age_hours=$((age_seconds / 3600))
        
        echo "  📋 Instance: $instance_id"
        echo "     Name: $name"
        echo "     Session: $session_id"
        echo "     State: $state"
        echo "     Type: $instance_type"
        echo "     Public IP: $public_ip"
        echo "     Age: ${age_hours}h (launched: $launch_time)"
        echo ""
    done
    
    return 1  # Indicates instances were found
}

# Function to terminate instances
terminate_instances() {
    local instances_json="$1"
    local instance_ids
    
    instance_ids=$(echo "$instances_json" | jq -r '.[].InstanceId' | tr '\n' ' ')
    
    if [ -z "$instance_ids" ] || [ "$instance_ids" = " " ]; then
        echo "✅ No instances to terminate"
        return 0
    fi
    
    if [ "$DRY_RUN" = "--dry-run" ]; then
        echo "🔍 DRY RUN: Would terminate instances: $instance_ids"
        return 0
    fi
    
    echo "🗑️  Terminating instances: $instance_ids"
    
    # Terminate instances
    if aws ec2 terminate-instances \
        --region "$REGION" \
        --instance-ids $instance_ids >/dev/null 2>&1; then
        echo "✅ Termination request sent successfully"
        
        # Wait for termination (with timeout)
        echo "⏳ Waiting for instances to terminate..."
        if timeout 300 aws ec2 wait instance-terminated \
            --region "$REGION" \
            --instance-ids $instance_ids 2>/dev/null; then
            echo "✅ All instances terminated successfully"
        else
            echo "⚠️  Timeout waiting for termination (instances may still be terminating)"
        fi
    else
        echo "❌ Failed to terminate instances"
        return 1
    fi
}

# Function to cleanup tracking files
cleanup_tracking_files() {
    echo "🗑️  Cleaning up tracking files..."
    local count=0
    
    for file in /tmp/k3s-aws-instances-*.json; do
        if [ -f "$file" ]; then
            if [ "$DRY_RUN" = "--dry-run" ]; then
                echo "🔍 DRY RUN: Would delete tracking file: $file"
            else
                rm -f "$file"
                echo "   Deleted: $file"
            fi
            count=$((count + 1))
        fi
    done
    
    if [ $count -eq 0 ]; then
        echo "✅ No tracking files found"
    else
        echo "✅ Cleaned up $count tracking file(s)"
    fi
}

# Main execution
main() {
    check_aws_cli
    
    echo ""
    local all_instances filtered_instances
    all_instances=$(find_orphaned_instances)
    filtered_instances=$(filter_by_age "$all_instances")
    
    if display_instances "$filtered_instances"; then
        echo "✅ No cleanup needed"
    else
        echo ""
        if [ "$DRY_RUN" != "--dry-run" ]; then
            echo "⚠️  WARNING: This will permanently terminate the instances above!"
            echo "Press Ctrl+C to cancel, or any key to continue..."
            read -r
        fi
        
        terminate_instances "$filtered_instances"
    fi
    
    echo ""
    cleanup_tracking_files
    
    echo ""
    echo "🎉 Cleanup completed!"
    if [ "$DRY_RUN" = "--dry-run" ]; then
        echo "💡 Run without --dry-run to actually terminate instances"
    fi
}

# Run main function
main "$@" 