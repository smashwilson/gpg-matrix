require 'colorize'

def run command, options = {}
  puts command.on_green if options[:log]
  system command
  raise RuntimeError.new("failed: #{command}") unless $?.success?
end
