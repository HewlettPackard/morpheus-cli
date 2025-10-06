# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'morpheus/cli/version'

Gem::Specification.new do |spec|
  spec.name          = "morpheus-cli"
  spec.version       = Morpheus::Cli::VERSION
  spec.authors       = ["David Estes", "Bob Whiton", "Jeremy Michael Crosbie", "James Dickson"]
  spec.email         = ["davydotcom@gmail.com"]
  spec.summary       = "Provides CLI Interface to the Morpheus Public/Private Cloud Appliance"
  spec.description   = "Infrastructure agnostic cloud application management & orchestration CLI for Morpheus. Easily manage and orchestrate VMS on private or public infrastructure and containerized architectures."
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '>= 2.5.1' # according to http.rb doc
  spec.add_dependency "tins", '~> 1.43.0'
  spec.add_dependency "public_suffix", "4.0.7" # https://github.com/weppos/publicsuffix-ruby/blob/main/CHANGELOG.md
  spec.add_dependency "ffi", "1.15.5" # Fix for mismatched deps: https://github.com/ffi/ffi/issues/1103
  spec.add_development_dependency "bundler", "~> 2.2"
  spec.add_development_dependency "rake"
  spec.add_dependency 'term-ansicolor', '~> 1.3.0'
  spec.add_dependency "rest-client", "2.0.2"
  spec.add_dependency 'multipart-post'
  spec.add_dependency "filesize"
  spec.add_dependency 'mime-types'
  spec.add_dependency "http"
  spec.add_dependency "rubyzip", '~> 2.3.2'
  spec.add_dependency "money"
  spec.add_dependency "test-unit"
end
