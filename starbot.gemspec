require File.expand_path("../lib/starbot/version", __FILE__)
require "rubygems"
::Gem::Specification.new do |s|
  s.name                        = "starbot"
  s.version                     = Starbot::VERSION
  s.platform                    = ::Gem::Platform::RUBY
  s.authors                     = ['Gavin Brock', 'Caleb Crane', 'Eric Platon']
  s.email                       = ["starbot@simulacre.org"]
  s.homepage                    = "http://www.github.com/simulacre/starbot"
  s.summary                     = 'Starbot is a transport independent chat bot'
  s.description                 = 'Starbot answers questions and volunteers information'
  s.required_rubygems_version   = ">= 1.3.6"
  s.rubyforge_project           = 'starbot'
  s.files                       = Dir["lib/**/*.rb", "bin/*", "*.md"]
  s.require_paths               = ['lib']
  s.executables                 = Dir["bin/*"].map{|f| f.split("/")[-1] }

  s.add_dependency 'linguistics'
  s.add_dependency 'rufus-scheduler'

  s.add_development_dependency 'rspec'
end
