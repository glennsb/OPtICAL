# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'optical/version'

Gem::Specification.new do |spec|
  spec.name          = "optical"
  spec.version       = Optical::VERSION
  spec.authors       = ["Stuart Glenn"]
  spec.email         = ["Stuart-Glenn@omrf.org"]
  spec.summary       = %q{OMRF Pipeline for CHiPSeq Analysis}
  spec.description   = %q{A set of wrapper scripts for CHiPSeq analysis developed at the Oklahoma Medical Research Foundation}
  spec.homepage      = ""
  spec.license       = "BSD"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.1"

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
end
