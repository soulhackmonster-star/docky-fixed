#!/usr/bin/env ruby
require 'xcodeproj'
project = Xcodeproj::Project.open('Docky.xcodeproj')
target = project.targets.find { |t| t.name == 'Docky (App Store)' }
abort 'no target' unless target

puts "=== Build phases ==="
target.build_phases.each do |phase|
  puts "  #{phase.class.name.split('::').last}: #{phase.display_name}"
end

puts
puts "=== Sources count: #{target.source_build_phase.files.count} ==="
target.source_build_phase.files.first(5).each do |f|
  puts "  #{f.file_ref&.path || '(nil)'}"
end

puts
puts "=== Resources count: #{target.resources_build_phase.files.count} ==="
target.resources_build_phase.files.first(5).each do |f|
  puts "  #{f.file_ref&.path || '(nil)'}"
end

puts
puts "=== Frameworks count: #{target.frameworks_build_phase.files.count} ==="
target.frameworks_build_phase.files.first(5).each do |f|
  puts "  #{f.file_ref&.path || '(nil)'}"
end
