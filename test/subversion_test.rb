$mock_subversion = true
require File.dirname(__FILE__) + '/test_helper'

class SubversionTest < Test::Unit::TestCase
  def setup
    Subversion.reset_executed
  end

  def test_add
    Subversion.add('foo', 'bar', 'hello', 'world')
    assert_equal 'svn add foo bar hello world', Subversion.executed.first
  end

  def test_ignore
    Subversion.ignore('foo', 'some/path/foo')
    assert_equal "svn propset svn:ignore 'foo' ./", Subversion.executed[1]
    assert_equal "svn propset svn:ignore 'foo' some/path", Subversion.executed[3]
  end

  def test_externalize
    Subversion.externalize('some/repo/path')
    Subversion.externalize('some/repo/path', :as => 'foo')
    Subversion.externalize('some/repo/path', :as => 'foo', :local_path => 'local/path')
    Subversion.externalize('some/repo/path', :as => 'vendor/plugins/foo')

    assert_equal "svn propset svn:externals '#{'path'} some/repo/path' .", Subversion.executed[1]  # Used to be 'path'.ljust(29)
    assert_equal "svn propset svn:externals '#{'foo'} some/repo/path' .", Subversion.executed[3]
    assert_equal "svn propset svn:externals '#{'foo'} some/repo/path' local/path", Subversion.executed[5]
    assert_equal "svn propset svn:externals '#{'foo'} some/repo/path' vendor/plugins", Subversion.executed[7]
  end

  def test_remove
    Subversion.remove 'foo', 'bar', 'hello/world'
    assert_equal 'svn rm foo bar hello/world', Subversion.executed.first
  end

  def test_remove_without_delete
    tmpdir = "tmp#{$$}"
    entries = "#{tmpdir}/.svn/entries"
    FileUtils.mkdir_p "#{tmpdir}/.svn", :mode => 0755
    File.open entries, 'w' do |file|
      file.write <<-EOS
        <?xml version="1.0" encoding="utf-8"?>
        <wc-entries
          xmlns="svn:">
        <entry
          name="existing_file"
          kind="file"/>
        <entry
          name="just_added_file"
          schedule="add"
          kind="file"/>
        <entry
          name="unchanging_file"
          kind="file"/>
        </wc-entries>
      EOS
    end
    File.chmod(0444, entries)
    FileUtils.touch ["#{tmpdir}/existing_file", "#{tmpdir}/just_added_file", "#{tmpdir}/unchanging_file"]

    begin
      doc = REXML::Document.new(IO.read(entries))
      assert_not_nil REXML::XPath.first(doc, '//entry[@name="existing_file"]')
      Subversion.remove_without_delete "#{tmpdir}/existing_file"
      # the element should now be scheduled for delete
      doc = REXML::Document.new(IO.read(entries))
      assert_not_nil REXML::XPath.first(doc, '//entry[@name="existing_file"][@schedule="delete"]')

      doc = REXML::Document.new(IO.read(entries))
      assert_not_nil REXML::XPath.first(doc, '//entry[@name="just_added_file"][@schedule="add"]')
      Subversion.remove_without_delete "#{tmpdir}/just_added_file"
      doc = REXML::Document.new(IO.read(entries))
      # the element should now be gone
      assert_nil REXML::XPath.first(doc, '//entry[@name="just_added_file"]')
    ensure
      FileUtils.rm_r tmpdir
    end
  end
end

class DiffsParserTest < Test::Unit::TestCase
#  def test_diff_class_acts_like_hash
#    diff = Subversion::Diff['file.rb' => "some differences"]
#    assert_equal 'some differences', diff['file.rb']
#  end
  def test_parser_error
    assert_raise(Subversion::DiffsParser::ParseError) { Subversion::DiffsParser.new('what').parse }
  end
  def test_parser
    diffs = Subversion::DiffsParser.new(<<End).parse
Index: lib/test_extensions.rb
===================================================================
--- lib/test_extensions.rb      (revision 2871)
+++ lib/test_extensions.rb      (revision 2872)
@@ -6,6 +6,7 @@
 require_local 'some_file'

 gem 'quality_extensions'
+require 'quality_extensions/regexp/join'
 require 'quality_extensions/kernel/capture_output.rb'
 require 'quality_extensions/kernel/simulate_input.rb'

Index: Readme
===================================================================
--- Readme      (revision 0)
+++ Readme      (revision 2872)
@@ -0,0 +1,2 @@
+* Blah blah blah
+* Blah blah blah
End
    assert_equal Subversion::Diffs, diffs.class
    assert       diffs.frozen?
    assert_equal 2, diffs.keys.size
    assert_equal 2, diffs.values.size
    assert_equal <<End, diffs['lib/test_extensions.rb'].diff
 require_local 'some_file'

 gem 'quality_extensions'
+require 'quality_extensions/regexp/join'
 require 'quality_extensions/kernel/capture_output.rb'
 require 'quality_extensions/kernel/simulate_input.rb'

End
    assert_equal <<End, diffs['Readme'].diff
+* Blah blah blah
+* Blah blah blah
End

  end

end
