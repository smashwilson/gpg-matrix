#!/bin/env ruby

require 'fileutils'
require 'rest-client'
require 'nokogiri'
require 'uri'

require './versions'

def run command
  system command
  raise RuntimeError.new("failed: #{command}") unless $?.success?
end

# Download and build dependencies
dep_dir = File.join(__dir__, '.gpg', 'deps')
base_uri = 'https://gnupg.org/download/index.html'
download_page = Nokogiri::HTML(RestClient.get(base_uri))

DEPENDENCY_PREFIXES = {}

%w(libgpg-error libgcrypt libassuan ksba ntbtls npth).each do |depname|
  dep_src_dir = File.join(dep_dir, depname, 'src')
  dep_out_dir = File.join(dep_dir, depname, 'out')

  unless File.directory? dep_src_dir
    dep_url = download_page.css('a[href]')
      .map { |a| URI.join(base_uri, a['href']).to_s }
      .find { |href| href =~ /\/(?:lib)?#{depname}-[0-9.]+\.tar\.bz2\Z/ }
    if dep_url.nil?
      raise RuntimeError.new("Unable to find download for #{depname}")
    end
    puts "downloading dependency #{depname}"

    dep_download = RestClient::Request.execute(method: :get, url: dep_url, raw_response: true)
    FileUtils.mkdir_p dep_src_dir
    run "tar xvfj #{dep_download.file.path} -C #{dep_src_dir}"
  else
    puts "dependency #{depname} is already present"
  end

  unless File.directory? dep_out_dir
    FileUtils.mkdir_p dep_out_dir
    puts "building dependency #{depname}"

    dep_src_subdir = Dir.entries(dep_src_dir).find { |subdir| subdir =~ /^#{depname}-/ }

    Dir.chdir File.join(dep_src_dir, dep_src_subdir) do
      dep_args = DEPENDENCY_PREFIXES.map do |depname, prefix|
        "--with-#{depname}-prefix=#{prefix}"
      end

      run "sh ./configure --prefix=#{dep_out_dir} #{dep_args.join ' '}"
      run 'make'
      run 'make install'
    end
  else
    puts "dependency #{depname} is already built"
  end

  DEPENDENCY_PREFIXES[depname] = dep_out_dir
end

GPG_VERSION_DIRS.each do |version, dirs|
  unless File.directory? dirs[:src]
    puts "downloading gpg source for version #{version}"
    FileUtils.mkdir_p(dirs[:src])

    download = RestClient::Request.execute(
      method: :get,
      url: "https://gnupg.org/ftp/gcrypt/gnupg/gnupg-#{version}.tar.bz2",
      raw_response: true
    )

    run "tar xvfj #{download.file.path} -C #{dirs[:src]}"
  else
    puts "gpg version #{version} already present"
  end

  src_subdir = Dir.entries(dirs[:src]).find { |subdir| subdir =~ /gnupg-#{version}/ }
  unless src_subdir
    raise RuntimeError("unable to find extracted source for GPG version #{version}")
  end

  unless File.directory? dirs[:out]
    puts "building gpg version #{version}"

    Dir.chdir File.join(dirs[:src], src_subdir) do
      dep_args = DEPENDENCY_PREFIXES.map do |depname, prefix|
        "--with-#{depname}-prefix=#{prefix}"
      end

      run "./configure --prefix=#{dirs[:out]} #{dep_args.join ' '}"
      run "make"
      run "make install"
    end
  else
    puts "gpg version #{version} has already been built"
  end
end
