#!/bin/env ruby

require './versions'
require './helpers'
require 'fileutils'
require 'tmpdir'
require 'colorize'
require 'pty'
require 'expect'

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
    list_out = `#{info[:gpg_bin]} --list-keys`
    puts list_out
    unless $?.success?
      raise RuntimeError.new('Unable to list GPG keys')
    end

    puts '.. extracting key ID'.yellow
    signing_key = list_out[/pub\s+[^\/]+\/([0-9A-F]+)/, 1]
    unless signing_key
      puts list_out
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
      begin
        PTY.spawn('export GPG_TTY=$(tty) ; git commit -m blorp') do |r, w, pid|
          begin
            puts r.expect(/Enter passphrase:/)[0]
            w.print "trustno1\r\n"
            w.flush
            puts r.gets(nil)

            status = PTY.check(pid)
            raise RuntimeError.new('commit failed') unless status.success?
          rescue Errno::EIO
          end
        end
      rescue PTY::ChildExited
        #
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
GPG_VERSION_INFO.each do |version, info|
  puts
  puts ">> #{version} <<".ljust(120, '<').black.on_light_cyan.bold
  puts

  result = {}

  begin
    verify_git_setup info
    result[:git] = 'OK'.light_green
  rescue RuntimeError => e
    puts e.message
    puts e.backtrace.join("\n ")
    result[:git] = 'FAIL'.light_red
  end

  results[version] = result
end

puts
puts ">> results <<".black.on_light_cyan.bold
GPG_VERSION_INFO.each do |version, info|
  puts "#{version.rjust 10}: git #{results[version][:git]}"
end
