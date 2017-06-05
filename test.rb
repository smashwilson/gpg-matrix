#!/usr/bin/env ruby

require './versions'
require './helpers'
require 'fileutils'
require 'tmpdir'
require 'colorize'
require 'pty'
require 'expect'

ENV['GPG_TTY'] = `tty`

def with_tmpdirs
  Dir.mktmpdir 'gpg-home-', '/tmp' do |gpg_home_dir|
    ENV['GNUPGHOME'] = gpg_home_dir

    Dir.mktmpdir 'gpg-git-', '/tmp' do |repo_dir|
      yield repo_dir
    end
  end
end

def verify_git_setup info
  with_tmpdirs do |repo_dir|
    puts ".. environment:".yellow
    puts "cd #{repo_dir}".bold
    puts "export GNUPGHOME=#{ENV['GNUPGHOME']}".bold
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

    Dir.chdir repo_dir do
      puts '.. initializing the repository'.yellow
      File.write(File.join(repo_dir, 'afile.txt'), "contents\n")

      run 'git init .', log: true
      run "git config gpg.program '#{info[:gpg_bin]}'", log: true
      run "git config commit.gpgsign true", log: true
      run "git config user.signingkey #{signing_key}", log: true
      run "git add afile.txt", log: true

      puts '.. ensuring that a git commit succeeds'.yellow
      PTY.spawn('export GPG_TTY=$(tty) ; git commit -m blorp') do |r, w, pid|
        begin
          puts r.expect(/Enter passphrase:/)
          puts "[password entered]".bold
          w.print "trustno1\r\n"
          w.flush
          puts r.gets(nil)

          status = PTY.check(pid)
          raise RuntimeError.new('commit failed') unless status.success?
        rescue Errno::EIO
        end
      end

      puts '.. ensure that the git commit is signed'.yellow
      run "git verify-commit HEAD", log: true
    end
  end
end

def verify_atom_tests info
end

ENV['GIT_TRACE'] = '1'

results = {}
all_ok = true
GPG_VERSION_INFO.each do |version, info|
  puts
  puts ">> #{version} <<".ljust(120, '<').black.on_light_cyan.bold
  puts

  result = {}

  begin
    verify_git_setup info
    result[:git] = 'OK'.light_green
  rescue RuntimeError => e
    puts e.message.light_red
    puts e.backtrace.join("\n ").light_red
    result[:git] = 'FAIL'.light_red.bold
    all_ok = false
  end

  results[version] = result
end

puts
puts ">> results <<".black.on_light_cyan.bold
GPG_VERSION_INFO.each do |version, info|
  puts "#{version.rjust 10}: git #{results[version][:git]}"
end

exit 1 unless all_ok
