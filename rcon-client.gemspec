# frozen_string_literal: true

require_relative "lib/rcon/client/version"

Gem::Specification.new do |spec|
  spec.name = "rcon-client"
  spec.version = RCon::Client::VERSION
  spec.authors = ["OZAWA Sakuro"]
  spec.email = ["10973+sakuro@users.noreply.github.com"]

  spec.summary = "rcon-client"
  spec.description = "rcon-client"
  spec.homepage = "https://github.com/sakuro/rcon-client"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}.git"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) {
    Dir[
      "lib/**/*.rb",
      "exe/*",
      "sig/**/*.rbs",
      "LICENSE*.txt",
      "README.md",
      "CHANGELOG.md"
    ]
  }
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) {|f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "concurrent-ruby", "~> 1.3"
  spec.add_dependency "zeitwerk", "~> 2.7"
end
