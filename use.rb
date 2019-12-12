#!/usr/bin/env ruby

require './versions'
require './helpers'
require 'fileutils'
require 'tmpdir'
require 'erb'

def usage
  $stderr.puts "Usage: #{$0} [version]"
  $stderr.puts "Temporarily configure Atom and git to use a specified version of gpg."
  $stderr.puts
  $stderr.puts "Available versions:"
  GPG_VERSION_INFO.keys.each do |version|
    $stderr.puts "  #{version}"
  end
  exit 1
end

usage unless ARGV.length == 1

# Determine the chosen GPG version
version = ARGV[0]
info = GPG_VERSION_INFO[version]
usage unless info

puts '.. creating an isolated GPG environment'.yellow
Dir.mktmpdir "gpg-home-#{version}", '/tmp' do |gpg_home_dir|
  ENV['GNUPGHOME'] = gpg_home_dir
  ENV['LOG_DIR'] = File.join(gpg_home_dir, 'logs')
  FileUtils.mkdir_p ENV['LOG_DIR']

  puts '.. generating gpg-agent configuration file'.yellow
  gpg_agent_template = File.read(File.join(__dir__, 'conf', 'gpg-agent.conf.erb'))
  renderer = ERB.new(gpg_agent_template)
  b = binding
  File.write(File.join(gpg_home_dir, 'gpg-agent.conf'), renderer.result(b))

  puts '.. starting the gpg-agent'.yellow
  agent_out = `#{info[:bin]}/gpg-agent --daemon`
  puts agent_out
  unless $?.success?
    raise RuntimeError.new('Unable to start GPG agent')
  end

  puts '.. extracting GPG agent environment variables'.yellow
  agent_info = agent_out[/GPG_AGENT_INFO\s*=\s*([^;]+)/, 1]
  ENV['GPG_AGENT_INFO'] = agent_info

  puts '.. generating key'.yellow
  run "#{info[:gpg_bin]} --gen-key --batch < #{__dir__}/key-parameters"

  puts '.. listing GPG key'.yellow
  list_out = `#{info[:gpg_bin]} --list-keys --with-colons`
  puts list_out
  unless $?.success?
    raise RuntimeError.new('Unable to list GPG keys')
  end

  puts '.. extracting key ID'.yellow
  signing_key = list_out[/^pub:.*/].split(':')[4]
  unless signing_key
    raise RuntimeError.new('Unable to parse key ID')
  end

  Dir.mktmpdir "gpg-git-#{version}", '/tmp' do |repo_dir|
    Dir.chdir repo_dir do
      puts '.. initializing the repository'.yellow
      File.write(File.join(repo_dir, 'afile.txt'), "contents\n")
      File.write(File.join(repo_dir, 'bfile.txt'), "contents\n")

      run 'git init .', log: true
      run "git config gpg.program '#{info[:gpg_bin]}'", log: true
      run "git config commit.gpgsign true", log: true
      run "git config user.signingkey #{signing_key}", log: true
      run "git add afile.txt", log: true

      puts '.. launching Atom'.yellow
      puts "GPG agent log file: [#{File.join(ENV['LOG_DIR'], 'gpg-agent.log').cyan}]"
      puts "GPG key passphrase: [#{'with a space'.cyan}]"

      run "atom -d --wait #{repo_dir}"

      puts '... stopping GPG agent'.yellow
      run "killall gpg-agent", log: true
    end
  end
end
