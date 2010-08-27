$mock_subversion = true
require File.dirname(__FILE__) + '/test_helper'
require 'subwrap/svn_command.rb'
require 'facets/string/to_re'
require 'yaml'
require 'facets/module/alias'
require 'quality_extensions/colored/toggleability'
require 'quality_extensions/regexp/join'



# Makes testing simpler. We can test all the *colorization* features via *manual* testing (since they're not as critical).
Subversion.color = false
String.color_on! false

#pp Subversion::SvnCommand.instance_methods.sort

# Since this doesn't work: Subversion::SvnCommand.any_instance.stubs(:system).returns(Proc.new {|a| p a; puts "Tried to call system(#{a})" })
class Subversion::SvnCommand
  def system(*args)
    Subversion::SvnCommand.executed_system << args.join(' ')
  end
  def self.executed_system
    @@executed_system ||= []
  end
  def self.reset_executed_system(as = [])
    @@executed_system = as
  end
end
module Kernel
  def exit_code
    o = Object.new
    class << o
      def success?
        true
      end
    end
    o
  end
end


module Subversion
class BaseSvnCommandTest < Test::Unit::TestCase
  def setup
    Subversion.reset_executed
  end
  def test_dummy_test
    # Because it tries to run this base class too!
  end
  # When we don't care what the output is -- we just don't want to see it while running the test!
  def silence(&block)
    capture_output(&block)
    nil
  end
end


class SvnCommandTest < BaseSvnCommandTest
  def test_invalid_quotes_gives_informative_error
    assert_exception(ArgumentError, lambda { |exception|
      assert_equal "Unmatched single quote: '", exception.message
    }) do
      SvnCommand.execute("foo -m 'stuff''")
    end
  end
  def test_unrecognized_option
    output = capture_output($stderr) do
      assert_exception(SystemExit, lambda { |exception|
      }) do
        SvnCommand.execute("status --blarg")
      end
    end
    assert_match /Unknown option '--blarg'/, output
  end
end

class ArgEscapingTest < BaseSvnCommandTest
  def test_argument_escaping
    args = nil
    silence { SvnCommand.execute( args = %q{commit -m 'a message with lots of !&`$0 |()<> garbage'} ) }
    assert_equal "svn #{args} --force-log", Subversion.executed[0]
  end
  def test_asterisk
    # Don't worry, this'll never happen, because the shell will expand the * *before* it gets to SvnCommand. But if you *did* sneak in an asterisk to SvnCommand.execute somehow, this is what would happen...
    SvnCommand.execute("add dir/* --non-recursive") 
    assert_equal "svn add --non-recursive 'dir/*'", Subversion.executed[0]
    # Actually, I lied... The * will *not* be expanded in the (rather uncommon) case that there are *no files matching the glob*. But that seems like a bash/shell problem, not our concern. Demo:
    # > mkdir foo
    # > echo foo/*
    # foo/*
    # > touch foo/file
    # > echo foo/*
    # foo/file
  end
  def test_multiline
    args = nil
    silence { SvnCommand.execute(args = "commit -m 'This is a
      |multi-line
      |message'".margin) }
    assert_equal "svn #{args} --force-log", Subversion.executed[0]
  end
  def test_multiword_arg_preserved_even_for_passthrough_subcommands
    # foo, for instance is entirely a passthrough subcommand; no 'def foo' exists, so it's handled entirely through method_missing.
    args = nil
    silence { SvnCommand.execute( args = %q{foo -m 'a multi-word message' --something-else 'something else'} ) }
    assert_equal "svn #{args}", Subversion.executed[0]
  end
end

#-----------------------------------------------------------------------------------------------------------------------------
# Built-in subcommands

# Test method_missing. Can we still call svn info, rm, etc. even if we haven't written subcommand modules for them?
class SubcommandPassThroughTest < BaseSvnCommandTest
  def test_1
    SvnCommand.execute("rm -q file1 file2 --force")
    assert_equal "svn rm -q file1 file2 --force", Subversion.executed[0]
  end
  def test_2
    SvnCommand.execute("info -q file1 file2 --force")
    assert_equal "svn info -q file1 file2 --force", Subversion.executed[0]
  end
end

class SvnAddTest < BaseSvnCommandTest
  def test_1
  end
  def test_2
    SvnCommand.execute('add "a b"') 
    assert_equal "svn add 'a b'", Subversion.executed[0]
  end
  def test_3
    SvnCommand.execute('add a b') 
    assert_equal "svn add a b", Subversion.executed[0]
  end
end

class SvnCommitTest < BaseSvnCommandTest
  def test_1
    silence { SvnCommand.execute("commit -m 'just an ordinary commit message!'") }
    assert_equal "svn commit -m 'just an ordinary commit message!' --force-log", Subversion.executed[0]
  end
  def test_lots_of_options
    silence { SvnCommand.execute("commit --non-recursive -q -m '' --targets some_file      ")  }
    assert_equal "svn commit --non-recursive -q -m '' --targets some_file --force-log", Subversion.executed[0]
  end
  def test_that_complex_quoting_doesnt_confuse_it
    original_message = "Can't decide how many \"'quotes'\" to use!"
    silence { SvnCommand.execute(%Q{commit -m "#{original_message.gsub('"', '\"')}"}) }

    expected_escaped_part = %q{'Can'\\''t decide how many "'\\''quotes'\\''" to use!'}
    assert_equal "svn commit -m #{expected_escaped_part} --force-log", Subversion.executed[0]
    assert_equal original_message, `echo #{expected_escaped_part}`.chomp    # We should have gotten back exactly what we put in originally
  end
end

class SvnDiffTest < BaseSvnCommandTest
  def test_1
    SvnCommand.execute("diff -r 123:125") 
    assert_equal [
      "svn diff  -r 123:125 ./",
      "svn status ./"
    ], Subversion.executed
  end
  def test_2
    #:fixme:
    #capture_output { SvnCommand.execute("diff -r { 2006-07-01 }") }
    #p Subversion.executed
    # Currently does this, since it thinks the arity is 1: 2006-07-01 } -r '{'
    #assert_equal "svn diff -r { 2006-07-01 }", Subversion.executed[0]
  end
end

class SvnHelpTest < BaseSvnCommandTest
  def test_1
    output = capture_output { SvnCommand.execute("help") }
    assert_equal "svn help ", Subversion.executed[0]
    assert_match /wrapper/, output
  end
end

class SvnLogTest < BaseSvnCommandTest
  def test_1
    capture_output { SvnCommand.execute("log") }
    assert_equal "svn log ", Subversion.executed[0]
  end
end

class SvnStatusTest < BaseSvnCommandTest
  # Duplicates a test in subversion_extensions_test.rb -- maybe can abbreviate this and leave the detailed filter tests to the other TestCase
  def test_status_does_some_filtering
    Subversion.stubs(:status).returns("
M      gemables/calculator/test/calculator_test.rb
X      gemables/calculator/tasks/shared
?      gemables/calculator/lib/calculator_extensions.rb

Performing status on external item at 'plugins/flubber/tasks/shared'

Performing status on external item at 'applications/underlord/vendor/plugins/nifty'
X      applications/underlord/vendor/plugins/nifty/tasks/shared
X      applications/underlord/vendor/plugins/nifty/lib/calculator
X      applications/underlord/vendor/plugins/nifty/doc_include/template

Performing status on external item at 'applications/underlord/vendor/plugins/nifty/tasks/shared'
M      applications/underlord/vendor/plugins/nifty/tasks/shared/base.rake
")
    String.any_instance.stubs(:underline).returns(lambda {' externals '})
    
    expected = <<End
M      gemables/calculator/test/calculator_test.rb
?      gemables/calculator/lib/calculator_extensions.rb
________________________________________ externals ________________________________________
M      applications/underlord/vendor/plugins/nifty/tasks/shared/base.rake
End

    assert_equal expected, out = capture_output { Subversion::SvnCommand.execute('st') }
  end

  def test_status_accepts_arguments
    SvnCommand.execute('st -u /path/to/file1 file2')
    assert_equal "svn status -u /path/to/file1 file2", Subversion.executed[0]

    Subversion.reset_executed
    SvnCommand.execute('st dir --no-ignore')
    # It will reorder some of the args (it puts all pass-through options and their args at the *beginning*), but that's okay...
    assert_equal "svn status --no-ignore dir", Subversion.executed[0]
    
  end
end #class SvnStatusTest

class SvnUpdateTest < BaseSvnCommandTest
  def test_1
    capture_output { SvnCommand.execute("up -q file1 file2 -r 17") }
    assert_equal "svn update -q -r 17 file1 file2", Subversion.executed[0]
  end
end

#-----------------------------------------------------------------------------------------------------------------------------
# Custom subcommands

#-----------------------------------------------------------------------------------------------------------------------------

# Notes about this test:
# If you start seeing errors like this:
#   NoMethodError: undefined method `chr' for nil:NilClass
# coming from one of the $stdin.getc.chr lines, it means that you didn't feed it enough simulated input! It was expectin to get
# another character from stdin but you didn't supply one!

class SvnEachUnaddedTest < BaseSvnCommandTest
  def setup
    super
    FileUtils.rm_rf('temp_dir/')
    FileUtils.mkdir_p('temp_dir/calculator/lib/')
    File.open(@filename = 'temp_dir/calculator/lib/unused.rb', 'w') { |file| file.puts "line 1 of unused.rb" }
  end
  def teardown
    FileUtils.rm_rf('temp_dir/')
  end

  def stub_status_1
    Subversion.stubs(:status).returns("
M      temp_dir/calculator/test/calculator_test.rb
X      temp_dir/calculator/tasks/shared
?      temp_dir/calculator/lib/unused.rb
")
  end
  def test_add
    stub_status_1
    output = simulate_input('a') do
      capture_output { SvnCommand.execute('each_unadded dir') }
    end
    assert_match /What do you want to do with .*unused\.rb/, output
    assert_match /Adding/, output
    assert_equal "svn add temp_dir/calculator/lib/unused.rb", Subversion.executed[0]
  end
  def test_ignore
    stub_status_1
    output = simulate_input('i') do
      capture_output { SvnCommand.execute('each_unadded dir') }
    end
    assert_match /What do you want to do with .*unused\.rb/, output
    assert_match /Ignoring/, output
    assert_equal [
        "svn propget svn:ignore temp_dir/calculator/lib",
        "svn propset svn:ignore 'unused.rb' temp_dir/calculator/lib"
      ], Subversion.executed
  end
  def test_preview_is_now_automatic
    stub_status_1
    output = simulate_input(
      #"p" +     # Preview
      "\n" +     # Blank line to do nothing (and exit loop)
      "\n"      # Blank line to do nothing (and exit loop)
    ) do
      capture_output { SvnCommand.execute('each_unadded dir') }
    end
    assert_match /What do you want to do with .*unused\.rb/, output
    assert_match "line 1 of unused.rb".to_re, output
  end
  def test_delete
    Subversion.stubs(:status).returns("
M      temp_dir/calculator/test/calculator_test.rb
X      temp_dir/calculator/tasks/shared
?      temp_dir/calculator/lib/unused.rb
?      temp_dir/calculator/lib/useless_directory
")
    FileUtils.mkdir_p(@dirname = 'temp_dir/calculator/lib/useless_directory')
    File.open(                   'temp_dir/calculator/lib/useless_directory/foo', 'w') { |file| file.puts "line 1 of foo" }

    assert File.exist?( @dirname ) 
    assert File.exist?( @filename ) 
    output = simulate_input(
      'd' +    # Delete
               # (The file doesn't require confirmation.)
      'd' +    # Delete
      'y'      # Yes I'm sure (The non-empty directory does.)
    ) do
      capture_output { SvnCommand.execute('each_unadded dir') }
    end
    assert_match /What do you want to do with .*unused\.rb/, output
    assert_match /What do you want to do with .*useless_directory/, output
    assert_match /Are you .*SURE/, output
    assert_match /Deleting.*Deleting/m, output
    assert !File.exist?( @filename ) 
    assert !File.exist?( @dirname ) 
  end
end #class

#-----------------------------------------------------------------------------------------------------------------------------
# Ignore
class SvnIgnoreTest < BaseSvnCommandTest
  def test_svn_ignore_relative_to_wd
    output = capture_output { SvnCommand.execute('ignore log') }
    assert_equal '', output
    assert_equal [
      "svn propget svn:ignore ./",
      "svn propset svn:ignore 'log' ./"
    ], Subversion.executed
  end
  def test_svn_ignore_relative_to_other_path
    output = capture_output { SvnCommand.execute('ignore log/*') }
    assert_equal '', output
    assert_equal [
      "svn propget svn:ignore log",
      "svn propset svn:ignore '*' log"
    ], Subversion.executed
  end
end

#-----------------------------------------------------------------------------------------------------------------------------
# Externals

class SvnExternalsTest < BaseSvnCommandTest

  # Causes .stub to break??
  #def setup
  #end
  def set_up_stubs   # This ought to just go in the normal "setup", but that caused weird errors. Ideas?
    yaml = %q{
    - !ruby/object:Subversion::ExternalsContainer
      container_dir: /home/tyler/code/gemables/subwrap/test
      entries: |+
        shared http://code.qualitysmith.com/gemables/test_extensions/lib

    - !ruby/object:Subversion::ExternalsContainer
      container_dir: /home/tyler/code/gemables/subwrap/tasks
      entries: |+
        shared                        http://code.qualitysmith.com/gemables/shared_tasks/tasks

    - !ruby/object:Subversion::ExternalsContainer
      container_dir: /home/tyler/code/gemables/subwrap/doc_include
      entries: |+
        template                      http://code.qualitysmith.com/gemables/template/doc/template
    }
    external_containers = YAML.load yaml
    Subversion.stubs(:externals_containers).returns(external_containers)
  end

  def test_svn_externalize
    set_up_stubs
    output = capture_output { SvnCommand.execute('externalize http://imaginethat.com/a/repo') }
    assert_equal '', output
    assert_equal [
      "svn propget svn:externals .",
      "svn propset svn:externals 'repo http://imaginethat.com/a/repo' ."
    ], Subversion.executed
  end


  def test_svn_externals_outline
    set_up_stubs
    output = capture_output { SvnCommand.execute('externals_outline') }

    assert_contains output, %q(
    |/home/tyler/code/gemables/subwrap/test
    |  * shared                    http://code.qualitysmith.com/gemables/test_extensions/lib
    |/home/tyler/code/gemables/subwrap/tasks
    |  * shared                    http://code.qualitysmith.com/gemables/shared_tasks/tasks
    |/home/tyler/code/gemables/subwrap/doc_include
    |  * template                  http://code.qualitysmith.com/gemables/template/doc/template
    ).margin
    assert_equal [], Subversion.executed
  end

  def test_svn_externals_items
    set_up_stubs
    output = capture_output { SvnCommand.execute('externals_items') }

    # :todo:

    assert_equal [], Subversion.executed
  end

  def test_svn_externals_containers
    set_up_stubs
    output = capture_output { SvnCommand.execute('externals_containers') } 

    assert_contains output, %q(
    |/home/tyler/code/gemables/subwrap/test
    |/home/tyler/code/gemables/subwrap/tasks
    |/home/tyler/code/gemables/subwrap/doc_include
    ).margin
    assert_equal [], Subversion.executed
  end

  def test_svn_edit_externals
    set_up_stubs
    output = simulate_input('yyy') do
      capture_output { SvnCommand.execute('edit_externals') } 
    end
    assert_match "No directory specified. Editing externals for *all*".to_re, output

    assert_match /Do you want to edit svn:externals for this directory/, output
    assert_equal [
      "svn propedit svn:externals /home/tyler/code/gemables/subwrap/test",
      "svn propedit svn:externals /home/tyler/code/gemables/subwrap/tasks",
      "svn propedit svn:externals /home/tyler/code/gemables/subwrap/doc_include"
    ], Subversion.executed
  end
end

#-----------------------------------------------------------------------------------------------------------------------------
# Commit messages

class SvnGetMessageTest < BaseSvnCommandTest
  def test_1
    Subversion.stubs(:status_against_server).returns("Status against revision:     56")
    output = simulate_input('i') do
      capture_output { SvnCommand.execute('get_message') }
    end
    assert_match "Message for r56 :".to_re, output
    assert_equal ["svn propget --revprop svn:log -r head"], Subversion.executed
  end
end

class SvnSetMessageTest < BaseSvnCommandTest
  def test_1
    Subversion.stubs(:status_against_server).returns("Status against revision:     56")
    output = simulate_input('i') do
      capture_output { SvnCommand.execute('set_message "this is my message"') }
    end
    assert_match "Message before changing:".to_re, output
    assert_match "Message for r56 :".to_re, output
    assert_equal [
      "svn propget --revprop svn:log -r head",
      "svn propset --revprop svn:log -r head 'this is my message'"
    ], Subversion.executed
  end
end

class SvnEditMessageTest < BaseSvnCommandTest
  def test_1
    Subversion.stubs(:status_against_server).returns("Status against revision:     56")
    Subversion.stubs(:get_revision_property).returns("The value I just set it to using vim, my favorite editor")
    output = simulate_input('i') do
      capture_output { SvnCommand.execute('edit_message') }
    end
    assert_equal ["svn propedit --revprop svn:log ./ -r head"], Subversion.executed
  end
end

class SvnEditMessageTest < BaseSvnCommandTest
  def test_can_actually_delete_property_too
    Subversion.stubs(:status_against_server).returns("Status against revision:     56")
    Subversion.stubs(:get_revision_property).returns("")
    output = simulate_input(
      'y'      # Yes I'm sure I want to delete the svn:fooo property for this revision.
    ) do
      capture_output { SvnCommand.execute('edit_revision_property svn:foo') }
    end
    assert_match /Are you sure you want to delete/, output
    assert_equal [
      "svn propedit --revprop svn:foo ./ -r head",
      "svn propdel --revprop svn:foo -r head"
    ], Subversion.executed
  end
end

#-----------------------------------------------------------------------------------------------------------------------------

class SvnViewCommitsTest < BaseSvnCommandTest
  def test_parse_revision_ranges
    assert_equal [134], SvnCommand.parse_revision_ranges(["134"])
    assert_equal [134, 135, 136], SvnCommand.parse_revision_ranges(["134-136"])
    assert_equal [134, 135, 136], SvnCommand.parse_revision_ranges(["134:136"])
    assert_equal [134, 135, 136], SvnCommand.parse_revision_ranges(["134..136"])
    assert_equal [134, 135, 136, 139], SvnCommand.parse_revision_ranges(["134-136", "139"])
  end
  def test_1
    messages = Dictionary[
      14, "Committed a bunch of really important stuff.",
      15, "Fixed a typo.",
      30, "Injected a horrible defect."
    ]
    Subversion.stubs(:log).with("-r 14 -v ").returns(messages[14])
    Subversion.stubs(:log).with("-r 15 -v ").returns(messages[15])
    Subversion.stubs(:log).with("-r 30 -v ").returns(messages[30])
    Subversion.stubs(:diff).returns(combined_diff = %q(
    |Index: lib/svn_command.rb
    |===================================================================
    |--- lib/svn_command.rb  (revision 2327)
    |+++ lib/svn_command.rb  (revision 2342)
    |@@ -3,9 +3,11 @@
    | require 'facets/more/command'
    | require 'facets/string/margin'
    | require 'facets/kernel/load'
    |+require 'extensions/symbol'
    | require 'pp'
    | require 'termios'
    | require 'stringio'
    |+require 'escape'    # http://www.a-k-r.org/escape/
    ).margin)
    output = capture_output { SvnCommand.execute('view-commits -r 14:15 30') }
    assert_equal %Q(
    |#{messages.values.join("\n")}
    |#{combined_diff}
    |
    ).margin, output
  end
end

#-----------------------------------------------------------------------------------------------------------------------------
# Changeset/commit/log Browser

class SvnRevisionsTest < BaseSvnCommandTest
  def set_up_stubs
    Subversion.stubs(:revisions).returns(
      begin
        RSCM::Revisions.class_eval do
          attr_accessor :revisions
        end
        RSCM::Revision.class_eval do
          attr_accessor :files
        end

        file1 = RSCM::RevisionFile.new
        file1.status = 'added'.upcase
        file1.path = 'dir/file1'
        file2 = RSCM::RevisionFile.new
        file2.status = 'modified'.upcase
        file2.path = 'dir/file2'

        revision1 = RSCM::Revision.new
        revision1.identifier = 1800
        revision1.developer = 'tyler'
        revision1.time = Time.utc(2007, 12, 01)
        revision1.message = 'I say! Quite the storm, what!'
        revision1.files = [file1, file2]

        revision2 = RSCM::Revision.new
        revision2.identifier = 1801
        revision2.developer = 'tyler'
        revision2.time = Time.utc(2007, 12, 02)
        revision2.message = 'These Romans are crazy!'
        revision2.files = [file2]

        revisions = RSCM::Revisions.new
        revisions.revisions = [revision1, revision2]
      end
    )
    Subversion.stubs(:latest_revision).returns(42)
    Subversion.stubs(:latest_revision_for_path).returns(42)
    Subversion.stubs(:diff).returns("the diff")
  end

  def test_view_changeset
    set_up_stubs

    output = simulate_input(
      'v' +     # View this changeset
      "\n" +    # Continue to revision 1800
      "\n"      # Try to continue, but of course there won't be any more revisions, so it will exit.
    ) do
      capture_output { SvnCommand.execute('revisions') }
    end
    #puts output
    #require 'unroller'
    #Unroller::trace :exclude_classes => /PP|PrettyPrint/ do

    assert_match Regexp.loose_join(
      "Getting list of revisions for './' ...
2 revisions found. Starting with most recent revision and going backward in time...",

# Show 1800
"2. r1800 | tyler | 2007-12-01 00:00:00
I say! Quite the storm, what!

A dir/file1
M dir/file2
r1800: View this changeset, Diff against specific revision, Grep the changeset, List or Edit revision properties, svn Cat all files, grep the cat, 
  mark as Reviewed, edit log Message, or browse using Up/Down/Enter keys >",

# Show the diff
"Diffing 1799:1800...",
"the diff",

# Show 1800 again
"r1800: View this changeset, Diff against specific revision, Grep the changeset, List or Edit revision properties, svn Cat all files, grep the cat, 
  mark as Reviewed, edit log Message, or browse using Up/Down/Enter keys >  Next...",

# Now show 1801
"1. r1801 | tyler | 2007-12-02 00:00:00
These Romans are crazy!

M dir/file2
r1801: View this changeset, Diff against specific revision, Grep the changeset, List or Edit revision properties, svn Cat all files, grep the cat, 
  mark as Reviewed, edit log Message, or browse using Up/Down/Enter keys >  Next...",
:multi_line => true
), output


=begin
/.*/
}.*
=end


    assert_equal [
      #"svn status -u ./"    # To find head
    ], Subversion.executed
  end
end


#-----------------------------------------------------------------------------------------------------------------------------
end #module Subversion


