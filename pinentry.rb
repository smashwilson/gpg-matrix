#!/usr/bin/env ruby

pinentry_break = File.exists?(File.join __dir__, '.pinentry.break')

File.write(File.join(ENV['LOG_DIR'], 'pinentry.log'), "Pinentry invoked with break=#{pinentry_break}")

STDOUT.sync = true

puts "OK Your orders please"
while line = $stdin.gets do
  case line
  when /^GETPIN/
    if pinentry_break
      puts "ERR 83918950 Inappropriate ioctl for device <Pinentry>"
      exit 1
    end
    puts "D trustno1"
    puts "OK"
  when /^GETINFO flavor/
    puts "D matrix:matrix\nOK"
  when /^GETINFO version/
    puts "D 0.0.0\nOK"
  when /^GETINFO pid/
    puts "D #{Process.pid}\nOK"
  else
    puts "OK"
  end
end
