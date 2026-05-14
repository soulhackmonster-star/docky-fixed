#!/usr/bin/env ruby
# Removes a target by name. Run with: ruby scripts/remove-target.rb 'Target Name'
require 'xcodeproj'
abort "Usage: ruby #{$0} <target name>" if ARGV.empty?

project = Xcodeproj::Project.open('Docky.xcodeproj')
target = project.targets.find { |t| t.name == ARGV[0] }
abort "Target not found: #{ARGV[0]}" unless target

target.remove_from_project
project.save
puts "Removed: #{ARGV[0]}"
