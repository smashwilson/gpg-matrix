#!/usr/bin/env ruby

STDOUT.sync = true

puts "OK Your orders please"
while line = $stdin.gets do
  case line
  when /^GETPIN/
    puts "D trustno1"
    puts "OK"
  else
    puts "OK"
  end
end
