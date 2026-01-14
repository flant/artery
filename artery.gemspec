# frozen_string_literal: true

# Maintain your gem's version:
require_relative 'lib/artery/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = 'artery'
  s.version     = Artery::VERSION
  s.authors     = ['Sergey Gnuskov']
  s.email       = ['sergey.gnuskov@flant.com']
  s.homepage    = 'https://github.com/flant/artery'
  s.summary     = 'Main messaging system between Rails [micro]services implementing message bus pattern on NATS.'
  # s.description = "TODO: Description of Artery."
  s.license     = 'MIT'

  s.files       = Dir['{app,config,exe,db,lib}/**/*', 'MIT-LICENSE', 'Rakefile', 'README.md']
  s.bindir      = 'exe'
  s.executables = s.files.grep(%r{^exe/}) { |f| File.basename(f) }

  s.required_ruby_version = '>= 2.7'

  s.add_dependency 'artery-browser', '~> 0.1'
  s.add_dependency 'multiblock', '~> 0.2'

  s.add_dependency 'nats-pure',    '~> 2.0', '< 3'
  s.add_dependency 'rails',        '>= 4.2', '< 8.2'
  s.metadata['rubygems_mfa_required'] = 'true'
end
