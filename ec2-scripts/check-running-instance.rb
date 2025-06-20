#!/usr/bin/env ruby
# Quick script to check the status of the running instance from your test

require_relative 'aws_ec2_testing'

# Instance details from your test output
instance_id = "i-0c4f81d050dbfef54"
public_ip = "44.246.212.150"
session_id = "0492c513a7cd3f3a"

puts "🔍 Checking Running Instance Status"
puts "=" * 50
puts "Instance ID: #{instance_id}"
puts "Public IP: #{public_ip}"
puts "Session ID: #{session_id}"
puts ""

# Create a testing instance to use SSH methods
testing = AwsEc2K3sTesting.new
testing.instance_variable_set(:@session_id, session_id)
testing.instance_variable_set(:@temp_resources, {
  'security_group_id' => 'sg-07aa60a838954d8b1',
  'key_pair_name' => "k3s-testing-#{session_id}",
  'key_file_path' => "/tmp/k3s-testing-#{session_id}.pem"
})

user = "ubuntu"

# Check if we can still connect
puts "🔗 Testing SSH Connection..."
begin
  result = testing.ssh_command(public_ip, user, 'echo "Connection test"')
  puts "✅ SSH connection successful"
rescue => e
  puts "❌ SSH connection failed: #{e.message}"
  puts "The instance might have been terminated or the key file might be missing."
  exit 1
end

# Check various status items
checks = [
  {
    name: "Instance Uptime",
    command: "uptime"
  },
  {
    name: "Cloud-init Status", 
    command: "cloud-init status"
  },
  {
    name: "User Data Log (last 30 lines)",
    command: "sudo tail -30 /var/log/cloud-init-output.log"
  },
  {
    name: "Check for K3S Debug Log",
    command: "sudo tail -20 /var/log/k3s-debug.log || echo 'Debug log not found'"
  },
  {
    name: "Check Test Completion Marker",
    command: "cat /tmp/k3s_test_complete || echo 'Test marker not found'"
  },
  {
    name: "K3S Process Status",
    command: "ps aux | grep k3s | grep -v grep || echo 'No K3S processes'"
  },
  {
    name: "K3S Service Status",
    command: "sudo systemctl status k3s || echo 'K3S service not found'"
  },
  {
    name: "Check if K3S is installed",
    command: "which k3s || echo 'K3S binary not found'"
  },
  {
    name: "Puppet Process Status",
    command: "ps aux | grep puppet | grep -v grep || echo 'No Puppet processes'"
  },
  {
    name: "Current Directory Contents",
    command: "ls -la /tmp/ | grep k3s"
  }
]

checks.each_with_index do |check, index|
  puts "\n#{index + 1}. 🔍 #{check[:name]}"
  puts "-" * 40
  
  begin
    result = testing.ssh_command(public_ip, user, check[:command])
    puts result
  rescue => e
    puts "❌ Error: #{e.message}"
  end
  
  sleep 1
end

puts "\n🛠️  Attempting Manual K3S Installation"
puts "=" * 40

begin
  puts "Installing K3S directly..."
  result = testing.ssh_command(public_ip, user, "curl -sfL https://get.k3s.io | sudo sh -")
  puts result
  
  sleep 10
  
  puts "\nChecking K3S status after manual install..."
  result = testing.ssh_command(public_ip, user, "sudo systemctl status k3s")
  puts result
  
  puts "\nTesting K3S functionality..."
  result = testing.ssh_command(public_ip, user, "sudo k3s kubectl get nodes")
  puts result
  
rescue => e
  puts "❌ Manual installation failed: #{e.message}"
end

puts "\n📋 Summary"
puts "=" * 40
puts "If the manual K3S installation worked, then the issue is with the user data script."
puts "If it didn't work, there might be a network or system issue."
puts ""
puts "To clean up this instance, run:"
puts "aws ec2 terminate-instances --instance-ids #{instance_id}" 