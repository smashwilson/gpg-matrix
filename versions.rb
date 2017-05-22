#!/bin/env ruby

GPG_VERSIONS = %w(1.2.0 1.4.21 2.0.29 2.1.21)

GPG_VERSION_DIRS = Hash[GPG_VERSIONS.map do |version|
  root_dir = File.join(__dir__, '.gpg', version)
  src_dir = File.join(root_dir, 'src')
  bin_dir = File.join(root_dir, 'bin')

  [version, {bin: bin_dir, src: src_dir}]
end]
