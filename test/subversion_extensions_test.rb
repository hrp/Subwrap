require File.dirname(__FILE__) + '/test_helper'
require 'subwrap/subversion_extensions'

Subversion.color = false    # Makes testing simpler. We can just test that the *colorization* features are working via *manual* tests.

class SubversionExtensionsTest < Test::Unit::TestCase
  def setup
  end

  def test_status_lines_filter
    
    #String.any_instance.stubs(:underline).returns(lambda {|a| a})  # Doesn't work! Lame! So we can't make the return value depend on the input?
    String.any_instance.stubs(:underline).returns(lambda {' externals '})

    input = <<End
M      gemables/calculator/test/calculator_test.rb
X      gemables/calculator/tasks/shared
?      gemables/calculator/lib/calculator_extensions.rb

Performing status on external item at 'plugins/flubber/tasks/shared'

Performing status on external item at 'applications/underlord/vendor/plugins/nifty'
X      applications/underlord/vendor/plugins/nifty/tasks/shared
X      applications/underlord/vendor/plugins/nifty/doc_include/template

Performing status on external item at 'applications/underlord/vendor/plugins/nifty/tasks/shared'
M      applications/underlord/vendor/plugins/nifty/tasks/shared/base.rake
End
    expected = <<End
M      gemables/calculator/test/calculator_test.rb
?      gemables/calculator/lib/calculator_extensions.rb
________________________________________ externals ________________________________________
M      applications/underlord/vendor/plugins/nifty/tasks/shared/base.rake
End
    
    assert_equal expected, out = Subversion.status_lines_filter( input ), out.inspect
  end

  def test_update_lines_filter
    input = <<End
U      gemables/calculator/test/calculator_test.rb
U      gemables/calculator/tasks/shared
U      gemables/calculator/lib/calculator_extensions.rb

Fetching external item into 'plugins/flubber/tasks/shared'
U      plugins/flubber/tasks/shared/blah.rb
External at revision 134143078
End
    expected = <<End
U      gemables/calculator/test/calculator_test.rb
U      gemables/calculator/tasks/shared
U      gemables/calculator/lib/calculator_extensions.rb
U      plugins/flubber/tasks/shared/blah.rb
End
    
    assert_equal expected, out = Subversion.update_lines_filter( input ), out.inspect
  end

  def test_unadded_filter
    input = <<End
M      gemables/calculator/test/calculator_test.rb
X      gemables/calculator/tasks/shared
?      gemables/calculator/lib/calculator_extensions.rb
End
    expected = <<End
?      gemables/calculator/lib/calculator_extensions.rb
End
    
    assert_equal expected, out = Subversion.unadded_lines_filter( input ), out.inspect
    assert_equal ['gemables/calculator/lib/calculator_extensions.rb'], out = Subversion.unadded_filter( input ), out.inspect
  end
end
