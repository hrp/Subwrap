require 'rubygems'
require 'facets/filelist' if !defined?(FileList)

module Project
  PrettyName    = "Subwrap: Enhanced Subversion Command"
  Name          = "subwrap"
  RubyForgeName = "subwrap"
  Version       = "0.5.1"
  Specification = Gem::Specification.new do |s|
    s.name    = Project::Name
    s.summary = "A nifty wrapper command for Subversion's command-line svn client"
    s.version = Project::Version
    s.author  = 'Tyler Rick'
    s.description = <<-EOF
      This is a wrapper command for Subversion's command-line svn client that adds a few new subcommands.
    EOF
    s.email = "rubyforge.org@tylerrick.com"
    s.homepage = "http://#{Project::RubyForgeName}.rubyforge.org/"
    s.rubyforge_project = Project::Name
    s.platform = Gem::Platform::RUBY
    s.add_dependency("colored")
    #s.add_dependency("escape")
    s.add_dependency("facets", '>= 2.4.4')
    s.add_dependency("quality_extensions", '>= 1.1.0')
    s.add_dependency("rscm")
    s.post_install_message = <<-End
---------------------------------------------------------------------------------------------------
You should now be able to run the subwrap command.

IMPORTANT: If you want to replace the normal svn command with subwrap, please run 
sudo `which _subwrap_post_install` or check the Readme to find out how to manually add it to your path.

Also, it is recommended that you install the termios gem so that you don't have to press enter
after selecting an option from the menu, but it will work without it.
---------------------------------------------------------------------------------------------------
    End

    # Documentation
    s.has_rdoc = true
    s.extra_rdoc_files = ['Readme']
    s.rdoc_options << '--title' << Project::Name << '--main' << 'Readme' << '--line-numbers'

    # Files
    s.files = FileList[
      '{lib,test,examples}/**/*.rb',
      'bin/*',
      'ProjectInfo.rb',
      'Readme'
    ].to_a
    s.test_files = Dir.glob('test/*.rb')
    s.require_path = "lib"
    s.executables = ['command_completion_for_subwrap', '_subwrap_post_install', 'subwrap']
    #s.executables = "svn"    # Doing this actually causes RubyGems to override the existing /usr/bin/svn during install. Not good!
  end
end unless defined?(Project)


