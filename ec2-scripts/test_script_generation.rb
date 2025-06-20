#!/usr/bin/env ruby

require_relative 'aws_ec2_testing'

puts "🧪 Testing K3S User Data Script Generation"
puts "==========================================="

testing = AwsEc2K3sTesting.new
script = testing.generate_user_data_script('ubuntu', 'single')

puts "\n📄 Generated User Data Script:"
puts "================================"
puts script

puts "\n📊 Script Analysis:"
puts "==================="
puts "• Lines: #{script.lines.count}"
puts "• Size: #{script.bytesize} bytes"
puts "• Has shebang: #{script.include?('#!/bin/bash') ? '✅' : '❌'}"
puts "• Has error handling: #{script.include?('set -e') ? '✅' : '❌'}"
puts "• Has logging: #{script.include?('tee') ? '✅' : '❌'}"
puts "• Has K3S install: #{script.include?('get.k3s.io') ? '✅' : '❌'}"
puts "• Has service check: #{script.include?('systemctl') ? '✅' : '❌'}"
puts "• Has test marker: #{script.include?('k3s_test_complete') ? '✅' : '❌'}"

puts "\n✅ Script generation test completed!" 