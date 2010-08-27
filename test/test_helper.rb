require 'test/unit'
require 'rubygems'
require 'facets/kernel/load'
gem 'mocha'
require 'stubba'
$LOAD_PATH << File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib'))

gem 'test_extensions'
require 'test_extensions'
gem 'quality_extensions'

require 'subwrap/subversion'
if $mock_subversion
  module Subversion
    def self.executable
      @@executable = "svn"
    end
    def self.actually_execute(method, command)
      @@executed << "#{command}"
      ''
    end
    def self.executed
      @@executed
    end
    def self.reset_executed(as = [])
      @@executed = as
    end
  end
end

