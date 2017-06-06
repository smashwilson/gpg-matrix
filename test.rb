#!/usr/bin/env ruby

require './versions'
require './helpers'
require 'fileutils'
require 'tmpdir'
require 'colorize'
require 'pty'
require 'expect'
require 'erb'

ENV['GIT_TRACE'] = '1'
unless ENV['ATOM_GITHUB_SRC']
  $stderr.puts "Please set ATOM_GITHUB_SRC to the root directory of your atom/github clone."
  exit 1
end
ATOM_GITHUB_ROOT = ENV['ATOM_GITHUB_SRC']

gpg_wrapper = nil
['gpg-wrapper.sh', 'gpg-no-tty.sh'].each do |candidate|
  wrapper_path = File.join ATOM_GITHUB_ROOT, 'bin', 'gpg-wrapper.sh'
  gpg_wrapper = wrapper_path if File.exist? wrapper_path
end
GPG_HELPER_PATH = gpg_wrapper

PINENTRY_PATH = File.join ATOM_GITHUB_ROOT, 'bin', 'gpg-pinentry.sh'
PINENTRY_BREAK_FILE  = File.join __dir__, '.pinentry.break'

def with_tmpdirs
  Dir.mktmpdir 'gpg-home-', '/tmp' do |gpg_home_dir|
    ENV['GNUPGHOME'] = gpg_home_dir

    Dir.mktmpdir 'gpg-git-', '/tmp' do |repo_dir|
      Dir.mktmpdir 'atom-git', '/tmp' do |atom_dir|
        yield repo_dir, atom_dir
      end
    end
  end
end

def prepare info, trial
  # Reset environment variables
  File.delete(PINENTRY_BREAK_FILE) if File.exist?(PINENTRY_BREAK_FILE)
  ENV['ATOM_GITHUB_TMP'] = ''
  ENV['ATOM_GITHUB_ASKPASS_PATH'] = ''
  ENV['ATOM_GITHUB_WORKDIR_PATH'] = ''
  ENV['ATOM_GITHUB_DUGITE_PATH'] = ''
  ENV['ATOM_GITHUB_PINENTRY_PATH'] = ''
  ENV['DISPLAY'] = ''
  ENV['ATOM_GITHUB_ORIGINAL_PATH'] = ''
  ENV['ATOM_GITHUB_ORIGINAL_GIT_ASKPASS'] = ''
  ENV['ATOM_GITHUB_ORIGINAL_SSH_ASKPASS'] = ''

  ENV['SSH_ASKPASS'] = ''
  ENV['GIT_ASKPASS'] = ''
  ENV['GPG_TTY'] = ''
  ENV['GPG_AGENT_INFO'] = ''

  log_dir = File.join(info[:log], trial)
  FileUtils.rm_rf log_dir
  ENV['LOG_DIR'] = log_dir

  with_tmpdirs do |repo_dir, atom_dir|
    puts ".. environment:".yellow
    puts "cd #{repo_dir}".bold
    puts "export GNUPGHOME=#{ENV['GNUPGHOME']}".bold
    puts "export GPG_TTY=$(tty)".bold

    puts ".. templating configuration files".yellow
    FileUtils.mkdir_p log_dir

    gpg_agent_template = File.read(File.join(__dir__, 'conf', 'gpg-agent.conf.erb'))
    renderer = ERB.new(gpg_agent_template)

    b = binding
    File.write(File.join(ENV['GNUPGHOME'], 'gpg-agent.conf'), renderer.result(b))

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

      yield repo_dir, atom_dir
    end
  end
end

def verify_git_setup info
  prepare info, 'git' do
    puts '.. ensuring that a git commit succeeds'.yellow
    PTY.spawn('export GPG_TTY=$(tty) ; git commit -m blorp') do |r, w, pid|
      begin
        puts r.expect(/Enter passphrase:/)
        puts "[password entered]".bold
        w.print "with a space\r\n"
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

def verify_atom_user_pinentry info
  prepare info, 'atom_user' do |repo_dir, atom_dir|
    puts '.. ensuring that an Atom git commit succeeds when the pinentry application works without a tty'.yellow
    run "git -c gpg.program=#{GPG_HELPER_PATH} commit -m blorp", log: true
    run "git verify-commit HEAD", log: true
  end
end

def verify_atom_atom_pinentry info
  prepare info, 'atom_atom' do |repo_dir, atom_dir|
    puts '.. ensuring that an Atom git commit succeeds when the user pinentry application does not work'.yellow

    File.write(PINENTRY_BREAK_FILE , '')

    ENV['ATOM_GITHUB_TMP'] = atom_dir
    ENV['ATOM_GITHUB_ASKPASS_PATH'] = File.join __dir__, 'askpass.rb'
    ENV['ATOM_GITHUB_WORKDIR_PATH'] = repo_dir
    ENV['ATOM_GITHUB_DUGITE_PATH'] = File.join ATOM_GITHUB_ROOT, 'node_modules', 'dugite'
    ENV['ATOM_GITHUB_PINENTRY_PATH'] = PINENTRY_PATH
    ENV['ATOM_GITHUB_ORIGINAL_PATH'] = ENV['PATH']
    ENV['ATOM_GITHUB_ORIGINAL_GIT_ASKPASS'] = ENV['GIT_ASKPASS']
    ENV['ATOM_GITHUB_ORIGINAL_SSH_ASKPASS'] = ENV['SSH_ASKPASS']
    ENV['DISPLAY'] = 'atom-github-placeholder'
    ENV['GIT_ASKPASS'] = File.join __dir__, 'askpass.rb'

    run "git -c gpg.program=#{GPG_HELPER_PATH} commit -m blorp", log: true
    run "git verify-commit HEAD", log: true
  end
end

results = {}
all_ok = true
GPG_VERSION_INFO.each do |version, info|
  result = {
    :git => 'WAIT'.yellow,
    :atom_user => 'WAIT'.yellow,
    :atom_atom => 'WAIT'.yellow
  }

  trials = {
    :git => method(:verify_git_setup),
    :atom_user => method(:verify_atom_user_pinentry),
    :atom_atom => method(:verify_atom_atom_pinentry)
  }

  trials.each do |key, func|
    begin
      puts
      puts ">> #{version} #{key} <<".ljust(120, '<').black.on_light_cyan.bold
      puts

      func.call(info)
      result[key] = '  OK'.light_green
    rescue RuntimeError => e
      puts e.message.light_red
      puts e.backtrace.join("\n ").light_red
      result[key] = 'FAIL'.light_red.bold
      all_ok = false
    end
  end

  results[version] = result
end

puts
puts ">> results <<".black.on_light_cyan.bold
GPG_VERSION_INFO.each do |version, info|
  puts "#{version.rjust 10}: git #{results[version][:git]} " +
    "atom[user pinentry] #{results[version][:atom_user]} " +
    "atom[atom] #{results[version][:atom_atom]}"
end

exit 1 unless all_ok
