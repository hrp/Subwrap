# This is the auto-require, which I suppose never gets used any more thanks to RubyGems' annoying change

$LOAD_PATH.unshift File.expand_path(File.join(File.dirname(__FILE__)))    # This is mainly for development, to make sure the development version is used instead of loading the same file from the installed gem because the gem path happens to be earlier on in the $LOAD_PATH.
$LOAD_PATH.uniq!
require 'subwrap/subversion'
Subversion
