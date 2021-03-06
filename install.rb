#!/usr/bin/env ruby

require 'fileutils'
require 'rest-client'
require 'nokogiri'
require 'uri'
require 'colorize'

require './versions'
require './helpers'

# Download and build dependencies
dep_dir = File.join(__dir__, '.gpg', 'deps')
base_uri = 'https://gnupg.org/download/index.html'
download_page = Nokogiri::HTML(RestClient.get(base_uri))
pinentry_path = File.join __dir__, 'pinentry.rb'

DEPENDENCY_PREFIXES = {}

%w(libgpg-error libgcrypt libassuan ksba npth pinentry).each do |depname|
  dep_src_dir = File.join(dep_dir, depname, 'src')
  dep_out_dir = File.join(dep_dir, depname, 'out')
  dep_out_flag = File.join(dep_out_dir, '.success')

  unless File.directory? dep_src_dir
    dep_url = download_page.css('a[href]')
      .map { |a| URI.join(base_uri, a['href']).to_s }
      .find { |href| href =~ /\/(?:lib)?#{depname}-[0-9.]+\.tar\.bz2\Z/ }
    if dep_url.nil?
      raise RuntimeError.new("Unable to find download for #{depname}")
    end
    puts ".. downloading dependency #{depname}".yellow

    dep_download = RestClient::Request.execute(method: :get, url: dep_url, raw_response: true)
    FileUtils.mkdir_p dep_src_dir
    run "tar xvfj #{dep_download.file.path} -C #{dep_src_dir}"
  else
    puts ".. dependency #{depname} is already present".green
  end

  unless File.file? dep_out_flag
    FileUtils.rm_rf dep_out_dir
    FileUtils.mkdir_p dep_out_dir
    puts ".. building dependency #{depname}".yellow

    dep_src_subdir = Dir.entries(dep_src_dir).find { |subdir| subdir =~ /^(?:lib)?#{depname}-/ }

    Dir.chdir File.join(dep_src_dir, dep_src_subdir) do
      dep_args = DEPENDENCY_PREFIXES.map do |depname, prefix|
        "--with-#{depname}-prefix=#{prefix}"
      end

      run "sh ./configure --prefix=#{dep_out_dir} #{dep_args.join ' '} --disable-dependency-tracking"
      run 'make'
      run 'make install'

      File.write(dep_out_flag, '')
    end
    puts ".. built dependency #{depname}".green
  else
    puts ".. dependency #{depname} is already built".green
  end

  DEPENDENCY_PREFIXES[depname] = dep_out_dir
end

GPG_VERSION_INFO.each do |version, info|
  unless File.directory? info[:src]
    puts ".. downloading gpg source for version #{version.bold}".green
    FileUtils.mkdir_p(info[:src])

    download = RestClient::Request.execute(
      method: :get,
      url: "https://gnupg.org/ftp/gcrypt/gnupg/gnupg-#{version}.tar.bz2",
      raw_response: true
    )

    run "tar xvfj #{download.file.path} -C #{info[:src]}"

    if File.directory? info[:patch]
      Dir["#{info[:patch]}/*.patch"].each do |patchfile|
        Dir.chdir info[:src] do
          run "patch -p1 -i #{patchfile}"
        end
      end
    end
  else
    puts ".. gpg version #{version} already present".green
  end

  src_subdir = Dir.entries(info[:src]).find { |subdir| subdir =~ /gnupg-#{version}/ }
  unless src_subdir
    raise RuntimeError("unable to find extracted source for GPG version #{version}")
  end

  build_flag = File.join info[:out], '.success'
  unless File.file? build_flag
    puts ".. building gpg version #{version}".green

    FileUtils.rm_rf info[:out]
    FileUtils.mkdir_p info[:out]

    Dir.chdir File.join(info[:src], src_subdir) do
      dep_args = DEPENDENCY_PREFIXES.map do |depname, prefix|
        "--with-#{depname}-prefix=#{prefix}"
      end
      dep_args << "--with-pinentry-pgm=#{pinentry_path}"

      original_cflags = ENV['CFLAGS']
      ENV['CFLAGS'] = info[:cflags] if info[:cflags]

      run "./configure --prefix=#{info[:out]} #{info[:configure]} #{dep_args.join ' '} --disable-dependency-tracking", log: true
      run "make #{info[:make]}", log: true
      run "make install", log: true

      ENV['CFLAGS'] = original_cflags

      File.write(build_flag, '')
    end
  else
    puts ".. gpg version #{version} has already been built".green
  end
end
