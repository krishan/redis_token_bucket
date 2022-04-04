# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'redis_token_bucket/version'

Gem::Specification.new do |spec|
  spec.name          = "redis_token_bucket"
  spec.version       = RedisTokenBucket::VERSION
  spec.authors       = ["Kristian Hanekamp"]
  spec.email         = ["kris.hanekamp@gmail.com"]

  spec.summary       = %q{Token Bucket Rate Limiting using Redis}
  spec.homepage      = "https://github.com/krishan/redis_token_bucket"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "redis", "~> 3.0"

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.5"
end
