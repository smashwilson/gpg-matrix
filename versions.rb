#!/bin/env ruby

GPG_VERSIONS = %w(1.2.0 1.4.21 2.0.29 2.1.21)

GPG_VERSION_INFO = Hash[GPG_VERSIONS.map do |version|
  root_dir = File.join(__dir__, '.gpg', version)
  src_dir = File.join(root_dir, 'src')
  out_dir = File.join(root_dir, 'out')
  bin_dir = File.join(out_dir, 'bin')

  patch_dir = File.join(__dir__, 'patches', version)

  [version, {
    out: out_dir,
    src: src_dir,
    bin: bin_dir,
    patch: patch_dir,
    configure: '',
    cflags: '',
    make: ''
  }]
end]

GPG_VERSION_INFO['1.2.0'][:configure] = '--disable-asm'
GPG_VERSION_INFO['1.2.0'][:cflags] = "-include #{__dir__}/patches/1.2.0/defs.h"

GPG_VERSION_INFO['2.0.29'][:make] = '-e ABSOLUTE_STDINT_H=\'"/usr/include/stdint.h"\''
