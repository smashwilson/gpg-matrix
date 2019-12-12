#!/bin/env ruby

GPG_VERSIONS = %w(1.4.21 2.0.30 2.1.21 2.2.0)

GPG_VERSION_INFO = Hash[GPG_VERSIONS.map do |version|
  root_dir = File.join(__dir__, '.gpg', version)
  src_dir = File.join(root_dir, 'src')
  out_dir = File.join(root_dir, 'out')
  bin_dir = File.join(out_dir, 'bin')
  gpg_bin = File.join(bin_dir, 'gpg')

  log_dir = File.join(__dir__, 'logs', version)
  patch_dir = File.join(__dir__, 'patches', version)

  [version, {
    out: out_dir,
    src: src_dir,
    bin: bin_dir,
    patch: patch_dir,
    log: log_dir,
    configure: '',
    cflags: '',
    make: '',
    gpg_bin: gpg_bin
  }]
end]

def for_versions *versions
  versions.each do |version|
    info = GPG_VERSION_INFO[version]
    yield info if info
  end
end

for_versions '2.0.30' do |i|
  i[:make] = '-e ABSOLUTE_STDINT_H=\'"/usr/include/stdint.h"\''
end

for_versions '2.0.30', '2.1.21' do |i|
  i[:gpg_bin] = File.join i[:bin], 'gpg2'
end
