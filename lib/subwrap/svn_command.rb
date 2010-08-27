# Tested by: ../../test/svn_command_test.rb

require File.dirname(__FILE__) + '/../subwrap'

require 'rubygems'

require 'facets'
#require 'facets/more/command'    # Not until Facets includes my changes
#require 'facets/kernel/load'
#require 'facets/kernel/with'       # returning
#require 'facets/enumerable/every'
#require 'facets/array/select'      # select!
#require 'facets/string/margin'
#require 'facets/string/lines'
#require 'facets/string/index_all'
#require 'facets/string/to_re'
#require 'facets/string/to_rx'
#require 'facets/ruby' # to_proc
#require 'facets/kernel/in'

gem 'quality_extensions', '>=1.1.4'
require 'quality_extensions/array/expand_ranges'
require 'quality_extensions/array/shell_escape'
require 'quality_extensions/file_test/binary_file'
require 'quality_extensions/console/command'
require 'quality_extensions/string/with_knowledge_of_color'
require 'quality_extensions/module/attribute_accessors'
#require 'quality_extensions/module/class_methods'

require 'English'
require 'pp'
require 'stringio'
require 'subwrap/pager'

gem 'colored'
require 'colored'  # Lets us do "a".white.bold instead of "\033[1ma\033[0m"

silence_warnings do
  require_local '../../ProjectInfo'
  require 'subwrap/subversion'
  require 'subwrap/subversion_extensions'
end

begin
  gem 'termios'
  require 'termios'
  begin
    # Set up termios so that it returns immediately when you press a key.
    # (http://blog.rezra.com/articles/2005/12/05/single-character-input)
    t = Termios.tcgetattr(STDIN)
    save_terminal_attributes = t.dup
    t.lflag &= ~Termios::ICANON
    Termios.tcsetattr(STDIN, 0, t)

    # Set terminal_attributes back to how we found them...
    at_exit { Termios.tcsetattr(STDIN, 0, save_terminal_attributes) }
  rescue RuntimeError => exception    # Necessary for automated testing.
    if exception.message =~ /can't get terminal parameters/
      # :todo: Can we detect if they are piping/redirecting stdout? Don't show warning if they are simply piping stdout.
      # On the other hand, when ELSE do we expect to not find a terminal? Is this message *ever* helpful?
      # Only testing? Then maybe the tests should set an environment variable or *something* to communicate that they want non-interactive mode.
      puts 'Warning: Terminal not found.'
      $interactive = false
    else
      raise
    end
  end
  $termios_loaded = true
rescue Gem::LoadError
  $termios_loaded = false
end


module Kernel
  # Simply to allow us to override it
  # Should be renamed to exit_status maybe since it returns a Process::Status
  def exit_code
    $?
  end
end

# :todo: move to quality_extensions
class Object
  def nonnil?; !nil?; end
  def nonempty?; !empty?; end
end

class IO
  # Gets a single character, as a string.
  # Adjusts for the different behavior of getc if we are using termios to get it to return immediately when you press a single key
  # or if they are not using that behavior and thus have to press Enter after their single key.
  def getch
    response = getc
    if !$termios_loaded
      next_char = getc
      new_line_characters_expected = ["\n"]
      #new_line_characters_expected = ["\n", "\r"] if windows?
      if next_char.chr.in?(new_line_characters_expected)
        # Eat the newline character
      else
        # Don't eat it
        # (This case is necessary, for escape sequences, for example, where they press only one key, but it produces multiple characters.)
        $stdin.ungetc(next_char)
      end
    end
    response.chr
  end
end


class String
  # Makes the first character bold and underlined. Makes the whole string of the given color.
  # :todo: Move out to extensions/console/menu_item
  def menu_item(color = :white, letter = self[0..0], which_occurence = 0)
    index = index_all(/#{letter}/)[which_occurence]
    raise "Could not find a #{which_occurence}th occurence of '#{letter}' in string '#{self}'" if index.nil?
    before = self[0..index-1].send(color) unless index == 0
    middle = self[index..index].send(color).bold.underline
    after  = self[index+1..-1].send(color)
    before.to_s + middle + after
  end
  # Extracted so that we can override it for tests. Otherwise it will have a NoMethodError because $? will be nil because it will not have actually executed any commands.
  def add_exit_code_error
    self << "Exited with error!".bold.red if !exit_code.success?
    self
  end
  def relativize_path
    self.gsub(File.expand_path(FileUtils.getwd) + '/', '')   # Simplify the directory by removing the working directory from it, if possible
  end
  def highlight_occurences(search_pattern, color = :red)
    self.gsub(search_pattern) { $&.send(color).bold }
  end
end
def confirm(question, options = ['Yes', 'No'])
  print question + " " +
    "Yes".menu_item(:red) + ", " +
    "No".menu_item(:green) + 
    " > "
  response = ''
  # Currently allow user to press Enter to accept the default.
  response = $stdin.getch.downcase while !['y', 'n', "\n"].include?(begin response.downcase!; response end)
  response
end

#Subversion.extend(Subversion::Extensions)
require 'subwrap/subversion_extensions'
module Subversion
  include(Subversion::Extensions)
end
Subversion::color = true

module Subversion
  class SvnCommand < Console::Command
  end
end

# Handle user preferences
module Subversion
  class SvnCommand
    @@user_preferences = {}
    mattr_accessor :user_preferences
  end
end
if File.exists?(user_preference_file = "#{ENV['HOME']}/.subwrap.yml")
  Subversion::SvnCommand.user_preferences = YAML::load(IO.read(user_preference_file)) || {}
end

module Subversion
  class SvnCommand

    silence_warnings do
    # Constants
    C_standard_remote_command_options = {
      [:__username] => 1,
      [:__password] => 1,
      [:__no_auth_cache] => 0,
      [:__non_interactive] => 0,
      [:__config_dir] => 1,
    }
    C_standard_commitable_command_options = {
      [:_m, :__message] => 1,
      [:_F, :__file] => 1,
      [:__force_log] => 0,
      [:__editor_cmd] => 1,
      [:__encoding] => 1,
    }
    end

    # This shouldn't be necessary. Console::Command should allow introspection. But until such time...
    @@subcommand_list = [
      'each_unadded',
      'externals_items', 'externals_outline', 'externals_containers', 'edit_externals', 'externalize',
      'ignore', 'edit_ignores',
      'revisions',
      'get_message', 'set_message', 'edit_message',
      'view_commits',
      'url',
      'repository_root', 'working_copy_root', 'repository_uuid',
      'latest_revision',
      'delete_svn',
      'fix_out_of_date_commit_state'
    ]
    mattr_reader :subcommand_list

    def initialize(*args)
      @passthrough_options = []
      super
    end

    #-----------------------------------------------------------------------------------------------------------------------------
    # Global options
    
    global_option :__no_color, :__dry_run, :__debug, :__print_commands
    def __no_color
      Subversion::color = false
    end
    def __debug
      $debug = true
    end
    def __dry_run
      Subversion::dry_run = true
    end

    def __print_commands
      Subversion::print_commands = true
    end
    alias_method :__show_commands,  :__print_commands
    # Don't want to hide/conflict with svn's own -v/--verbose flag, so using capital initial letter
    alias_method :_V,               :__print_commands
    alias_method :__Verbose,        :__print_commands

    # Usually most Subversion commands are recursive and all-inclusive. This option adds file *exclusion* to most of Subversion's commands.
    # Use this if you want to commit (/add/etc.) everything *but* a certain file or set of files
    #   svn commit dir1 dir2 --except dir1/not_ready_yet.rb
    def __except
      # We'll have to use a FileList to do this. This option will remove all file arguments, put them into a FileList as inclusions, 
      # add the exclusions, and then pass the resulting list of files on to the *actual* svn command.
      # :todo:
    end
    alias_method :__exclude, :__except

    #-----------------------------------------------------------------------------------------------------------------------------
    # Default/dynamic behavior
    
    # Any subcommands that we haven't implemented here will simply be passed on to the built-in svn command.
    # :todo: Distinguish between subcommand_missing and method_missing !
    #   Currently, for example, if as isn't defined, this: puts Subversion.externalize(repo_path, {:as => as })
    #   will call method_missing and try to run `svn as`, which of course will fail (without a sensible relevant error)...
    #   I think we should probably just have a separate subcommand_missing, like we already have a separate option_missing !!!
    #   Even a simple type (sss instead of ss) causes trouble... *this* was causing a call to "/usr/bin/svn new_messsage" -- what huh??
    #      def set_message(new_message = nil)
    #        args << new_messsage if new_message
    def method_missing(subcommand, *args)
      #puts "method_missing(#{subcommand}, #{args.inspect})"
      svn :exec, subcommand, *args
    end
    # This is here solely to allow subcommandless commands like `svn --version`
    def default()
      svn :exec
    end

    def option_missing(option_name, args)
      #puts "#{@subcommand} defined? #{@subcommand_is_defined}"
      if !@subcommand_is_defined
        # It's okay to use this for pass-through subcommands, because we just pass all options/arguments verbatim anyway...
        #puts "option_missing(#{option_name}, #{args.inspect})"
      else
        # But for subcommands that are defined here, we should know better! All valid options should be explicitly listed!
        raise UnknownOptionError.new(option_name)
      end

      # The following is necessary because we really don't know the arity (how many subsequent tokens it should eat) of the option -- we don't know anything about the options, in fact; that's why we've landed in option_missing.
      # This is kind of a hokey solution, but for any unrecognized options/args (which will be *all* of them unless we list the available options in the subcommand module), we just eat all of the args, store them in @passthrough_options, and later we will add them back on.
      # What's annoying about it this solution is that *everything* after the first unrecognized option comes in as args, even if they are args for the subcommand and not for the *option*!
      # But...it seems to work to just pretend they're options.
      # It seems like this is mostly a problem for *wrappers* that try to use Console::Command. Sometimes you just want to *pass through all args and options* unchanged and just filter the output somehow.
      # Command doesn't make that super-easy though. If an option (--whatever) isn't defined, then the only way to catch it is in option_missing. And since we can't the arity unless we enumerate all options, we have to hokily treat the first option as having unlimited arity.
      #   Alternatives considered: 
      #     * Assume arity of 0. Then I'm afraid it would extract out all the option flags and leave the args that were meant for the args dangling there out of order ("-r 1 -m 'hi'" => "-r -m", "1 'hi'")
      #     * Assume arity of 1. Then if it was really 0, it would pick up an extra arg that really wasn't supposed to be an arg for the *option*.
      # Ideally, we wouldn't be using option_missing at all because all options would be listed in the respective subcommand module...but for subcommands handled through method_missing, we don't have that option.

      # The args will look like this, for example:
      #   option_missing(-m, ["a multi-word message", "--something-else", "something else"])
      # , so we need to be sure we wrap multi-word args in quotes as necessary. That's what the args.shell_escape does.

      @passthrough_options << "#{option_name}" << args.shell_escape
      @passthrough_options.flatten!  # necessary now that we have args.shell_escape ?

      return arity = args.size  # All of 'em
    end

    #-----------------------------------------------------------------------------------------------------------------------------
    # Built-in commands (in alphabetical order)

    #-----------------------------------------------------------------------------------------------------------------------------
    module Add
      Console::Command.pass_through({
        [:__targets] => 1,
        [:_N, :__non_recursive] => 0,
        [:_q, :__quiet] => 0,
        [:__config_dir] => 1,
        [:__force] => 0,
        [:__no_ignore] => 0,
        [:__auto_props] => 0,
        [:__no_auto_props] => 0,
      }, self)
    end
    def add(*args)
      #puts "add #{args.inspect}"
      svn :exec, 'add', *args
    end
    
    #-----------------------------------------------------------------------------------------------------------------------------
    module Commit
      Console::Command.pass_through({
          [:_q, :__quiet] => 0,
          [:_N, :__non_recursive] => 1,
          [:__targets] => 1,
          [:__no_unlock] => 0,
        }.
          merge(SvnCommand::C_standard_remote_command_options).
          merge(SvnCommand::C_standard_commitable_command_options), self
      )

      # Use this flag if you don't want a commit notification to be sent out.
      def __skip_notification
        @skip_notification = true
      end
      alias_method :__covert,     :__skip_notification
      alias_method :__minor_edit, :__skip_notification    # Like in MediaWiki. If you're just fixing a typo or something, then most people probably don't want to hear about it.
      alias_method :__minor,      :__skip_notification

      # Use this flag if you are about to commit some code for which you know the tests aren't or (probaby won't) pass.
      # This *may* cause your continuous integration system to either skip tests for this revision or at least be a little more
      # *leniant* towards you (a slap on the wrist instead of a public flogging, perhaps) when it runs the tests and finds that
      # they *are* failing.
      # You should probably only do this if you are planning on making multiple commits in rapid succession (sometimes Subversion
      # forces you to do an intermediate commit in order to move something that's already been scheduled for a move or somethhing,
      # for example). If things will be broken for a while, consider starting a branch for your changes and merging the branch
      # back into trunk only when you've gotten the code stable/working again.
      # (See http://svn.collab.net/repos/svn/trunk/doc/user/svn-best-practices.html)
      def __broken
        @broken = true
      end
      alias_method :__expect_to_break_tests,            :__broken
      alias_method :__knowingly_committing_broken_code, :__broken

      # Skips e-mail and marks reviewed=true
      # Similar to the 'reviewed' command, which just marks reviewed=true
      def __doesnt_need_review
        @__doesnt_need_review = true
      end

      # :todo: svn doesn't allow you to commit changes to externals in the same transaction as your "main working copy", but we
      # can provide the illusion that this is possible, by doing multiple commits, one for each working copy/external.
      #
      # When this option is used, the same commit message is used for all commits.
      #
      # Of course, this may not be what the user wants; the user may wish to specify a different commit message for the externals
      # than for the "main working copy", in which case the user should not be using this option!
      def __include_externals
        @include_externals = true
      end

      # Causes blame/author for this commit/file to stay the same as previous revision of the file
      # Useful to workaround bug where fixing indent and other inconsequential changes causes you to be displayed as the author if you do a blame, [hiding] the real author
      def __shirk_blame
        @shirk_blame = true
      end

    end #module Commit

    def commit(*args)
      directory = args.first || './'    # We can only pass one path to .latest_revision and .repository_root, so we'll just arbitrarily choose the first path. They should all be paths within the same repository anyway, so it shouldn't matter.
      if @broken || @skip_notification
        latest_rev_before_commit = Subversion.latest_revision(directory)
        repository_root = Subversion.repository_root(directory)
      end

      Subversion.print_commands! do
        puts svn(:capture, "propset svn:skip_commit_notification_for_next_commit true --revprop -r #{latest_rev_before_commit} #{repository_root}", :prepare_args => false)
      end if @skip_notification
      # :todo:
      # Add some logic to automatically skip the commit e-mail if the size of the files to be committed exceeds a threshold of __ MB.
      # (Performance idea: Only check the size of the files if svn st includes (bin)?)

      # Have to use :system rather than :capture because they may not have specified a commit message, in which case it will open up an editor...
      svn(:system, 'commit', *(['--force-log'] + args))

      puts ''.add_exit_code_error
      return if !exit_code.success?

      # The following only works if we do :capture (`svn`), but that doesn't work so well (at all) if svn tries to open up an editor (vim),
      # which is what happens if you don't specify a message.:
      #   puts output = svn(:capture, 'commit', *(['--force-log'] + args))
      #   just_committed = (matches = output.match(/Committed revision (\d+)\./)) && matches[1]

      Subversion.print_commands! do
        puts svn(:capture, "propset code:broken true --revprop -r #{latest_rev_before_commit + 1}", :prepare_args => false)
      end if @broken

      if @include_externals
        #:todo:
        #externals.each do |external|
        #svn(:system, 'commit', *(['--force-log'] + args + external))
        #end
      end


      # This should be disableable! ~/.subwrap ?
      # http://svn.collab.net/repos/svn/trunk/doc/user/svn-best-practices.html:
      #   After every svn commit, your working copy has mixed revisions. The things you just committed are now at the HEAD revision, and everything else is at an older revision.
      #puts "Whenever you commit something, strangely, your working copy becomes out of date (as you can observe if you run svn info and look at the revision number). This is a problem for svn log, and piston, to name two applications. So we will now update '#{(args.every + '/..').join(' ').white.bold}' just to make sure they're not out of date..."
      #print ''.bold # Clear the bold flag that svn annoyingly sets
      #working_copy_root = Subversion.working_copy_root(directory).to_s
      #response = confirm("Do you want to update #{working_copy_root.bold} now? (Any key other than y to skip) ")
      #if response == 'y'
        #puts "Updating #{working_copy_root} (non-recursively)..."
      #end
      #puts Subversion.update_lines_filter( Subversion.update(*args) )
    end

    # Ideas:
    # * look for .svn-commit files within current tree and if one is found, show what's in it and ask 
    #   "Found a commit message from a previous failed commit. {preview} Do you want to (u)se this message for the current commit, or (d)elete it?"

    # A fix for this annoying problem that I seem to come across all too frequentrly:
    #   svn: Commit failed (details follow):
    #   svn: Your file or directory 'whatever.rb' is probably out-of-date
    def fix_out_of_date_commit_state(dir)
      dir = $1 if dir =~ %r|^(.*)/$|                           # Strip trailing slash.

      puts Subversion.export("#{dir}", "#{dir}.new").          # Exports (copies) the contents of working copy 'dir' (including your uncommitted changes, don't worry! ... and you'll get a chance to confirm before anything is deleted; but sometimes although it exports files that are scheduled for addition, they are no longer scheduled for addition in the new working copy, so you have to re-add them) to non-working-copy 'dir.new'
        add_exit_code_error 
      return if !exit_code.success?

      system("mv #{dir} #{dir}.backup")                        # Just in case something goes ary
      puts ''.add_exit_code_error
      return if !exit_code.success?

      puts "Restoring #{dir}..."
      Subversion.update dir                                    # Restore the directory to a pristine state so we will no longer get that annoying error

      # Assure the user that dir.new really does have your latest changes
      #puts "Here's a diff. Your changes/additions will be in the *right* (>) file."
      #system("diff #{dir}.backup #{dir}")

      # Merge those latest changes back into the pristine working copy
      system("cp -R #{dir}.new/. #{dir}/")

      # Assure the user one more time
      puts Subversion.colorized_diff(dir)

      puts "Please check the output of " + "svn st #{dir}.backup".blue.bold + " to check if any files were scheduled for addition. You will need to manually re-add these, as the export will have caused those files to lost their scheduling."
      Subversion.print_commands! do
        print Subversion.status_lines_filter( Subversion.status("#{dir}.backup") )
        print Subversion.status_lines_filter( Subversion.status("#{dir}") )
      end

      # Actually commit
      puts
      response = confirm("Are you ready to try the commit again now?")
      puts
      if response == 'y'
        puts "Great! Go for it. (I'd do it for you but I don't know what commit command you were trying to execute when the problem occurred.)"
      end

      # Clean up
      #puts
      #response = confirm("Do you want to delete array.backup array.new now?")
      puts "Don't forget to " + "rm -rf #{dir}.backup #{dir}.new".blue.bold + " when you are done!"
      #rm_rf array.backup, array.new
      puts
    end

    #-----------------------------------------------------------------------------------------------------------------------------
    module Diff
      Console::Command.pass_through({
          [:_r, :__revision] => 1,
          [:_c, :__change] => 1,
          [:__old] => 1,
          [:__new] => 0,
          #[:_N, :__non_recursive] => 0,
          [:__diff_cmd] => 1,
          [:_x, :__extensions] => 1,      # :todo: should support any number of args??
          [:__no_diff_deleted] => 0,
          [:__notice_ancestry] => 1,
          [:__force] => 1,
        }.merge(SvnCommand::C_standard_remote_command_options), self
      )

      def __non_recursive
        @non_recursive = true
        @passthrough_options << '--non-recursive'
      end
      alias_method :_N, :__non_recursive

      def __ignore_externals
        @ignore_externals = true
      end
      alias_method :_ie,             :__ignore_externals
      alias_method :_skip_externals, :__ignore_externals
    end

    def diff(*directories)
      directories = ['./'] if directories.empty?
      puts Subversion.colorized_diff(*(prepare_args(directories)))

      begin # Show diff for externals (if there *are* any and the user didn't tell us to ignore them)
        output = StringIO.new
        #paths = args.reject{|arg| arg =~ /^-/} || ['./']
        directories.each do |path|
          (Subversion.externals_items(path) || []).each do |item|
            diff_output = Subversion.colorized_diff(item).strip
            unless diff_output == ""
              #output.puts '-'*100
              #output.puts item.ljust(100, ' ').black_on_white.bold.underline
              output.puts item.ljust(100).yellow_on_red.bold
              output.puts diff_output
            end
          end
        end
        unless output.string == ""
          #puts '='*100
          puts (' '*100).yellow.underline
          puts " Diff of externals (**don't forget to commit these too!**):".ljust(100, ' ').yellow_on_red.bold.underline
          puts output.string
        end
      end unless @ignore_externals || @non_recursive
    end

    #-----------------------------------------------------------------------------------------------------------------------------
    module Help
      Console::Command.pass_through({
        [:__version] => 0,
        [:_q, :__quiet] => 0,
        [:__config_dir] => 1,
      }, self)
    end
    def help(subcommand = nil)
      case subcommand
        when "externals"
          puts %Q{
                 | externals (ext): Lists all externals in the given working directory.
                 | usage: externals [PATH]
                 }.margin
          # :todo: Finish...

        when nil
          puts "You are using " + 
               's'.green.bold + 'u'.cyan.bold + 'b'.magenta.bold + 'w'.white.bold + 'r'.red.bold + 'a'.blue.bold + 'p'.yellow.bold + ' version ' + Project::Version
               ", a colorful, useful replacement/wrapper for the standard svn command."
          puts "subwrap is installed at: " + $0.bold
          puts "You may bypass this wrapper by using the full path to svn: " + Subversion.executable.bold
          puts
          puts Subversion.help(subcommand).gsub(<<End, '')

Subversion is a tool for version control.
For additional information, see http://subversion.tigris.org/
End

          puts
          puts 'Subcommands added by subwrap (refer to '.green.underline + 'http://subwrap.rubyforge.org/'.white.underline + ' for usage details):'.green.underline
          @@subcommand_list.each do |subcommand|
            aliases_list = subcommand_aliases_list(subcommand.option_methodize.to_sym)
            aliases_list = aliases_list.empty? ? '' : ' (' + aliases_list.join(', ') + ')'
            puts '   ' + subcommand + aliases_list
          end
          #p subcommand_aliases_list(:edit_externals)

        else
          #puts "help #{subcommand}"
          puts Subversion.help(subcommand)
      end
    end

    #-----------------------------------------------------------------------------------------------------------------------------
    module Log
      Console::Command.pass_through({
          [:_r, :__revision] => 1,
          [:_q, :__quiet] => 0,
          [:_v, :__verbose] => 0,
          [:__targets] => 1,
          [:__stop_on_copy] => 0,
          [:__incremental] => 0,
          [:__xml] => 0,
          [:__limit] => 1,
        }.merge(SvnCommand::C_standard_remote_command_options), self
      )
    end
    def log(*args)
      puts Subversion.log( prepare_args(args) )
      #svn :exec, *args
    end

    # Ideas:
    #   Just pass a number (5) and it will be treated as --limit 5 (unless File.exists?('5'))
 
    #-----------------------------------------------------------------------------------------------------------------------------
    module Mkdir
      Console::Command.pass_through({
          [:_q, :__quiet] => 0,
        }.
          merge(SvnCommand::C_standard_remote_command_options).
          merge(SvnCommand::C_standard_commitable_command_options), self
      )

      # Make parent directories as needed. (Like the --parents option of GNU mkdir.)
      def __parents; @create_parents = true; end
      alias_method :_p, :__parents
    end

    def mkdir(*directories)
      if @create_parents
        directories.each do |directory|
        
          # :todo: change this so that it's guaranteed to have an exit condition; currently, can get into infinite loop
          loop do
            puts "Creating '#{directory}'"
            FileUtils.mkdir_p directory   # Create it if it doesn't already exist
            if Subversion.under_version_control?(File.dirname(directory))
              # Yay, we found a working copy. Now we can issue an add command, from that directory, which will recursively add the
              # (non-working copy) directories we've been creating along the way.
              
              #puts Subversion.add prepare_args([directory])
              svn :system, 'add', *directory
              break
            else
              directory = File.dirname(directory)
            end
          end
        end
      else
        # Preserve default behavior.
        svn :system, 'mkdir', *directories
      end
    end

    #-----------------------------------------------------------------------------------------------------------------------------
    module Move
      Console::Command.pass_through({
          [:_r, :__revision] => 1,
          [:_q, :__quiet] => 0,
          [:__force] => 0,
        }.
          merge(SvnCommand::C_standard_remote_command_options).
          merge(SvnCommand::C_standard_commitable_command_options), self
      )

      # If the directory specified by the destination path does not exist, it will `svn mkdir --parents` the directory for you to
      # save you the trouble (and to save you from getting an error message!).
      #
      # For example, if you try to move file_name to dir1/dir2/new_file_name and dir1/dir2 is not under version control, then it
      # will effectively do these commands:
      #   svn mkdir --parents dir1/dir2
      #   svn mv a dir1/dir2/new_file_name   # The command you were originally trying to do
      def __parents; @create_parents = true; end
      alias_method :_p, :__parents
    end

    def move(*args)
      destination = args.pop

      # If the last character is a '/', then they obviously expect the destination to be a *directory*. Yet when I do this:
      #   svn mv a b/
      # and b doesn't exist,
      #   it moves a (a file) to b as a file, rather than creating directory b/ and moving a to b/a.
      # I find this default behavior less than intuitive, so I have "fixed" it here...
      # So instead of seeing this:
      #   A  b
      #   D  a
      # You should see this:
      #   A  b
      #   A  b/a
      #   D  a
      if destination[-1..-1] == '/'
        if !File.exist?(destination[0..-2])
          puts "Notice: It appears that the '" + destination.bold + "' directory doesn't exist. Would you like to create it now? Good..."
          self.mkdir destination   # @create_parents flag will be reused there
        elsif !File.directory?(destination[0..-2])
          puts "Error".red.bold + ": It appears that '" + destination.bold + "' already exists but is not actually a directory. " +
            "The " + 'destination'.bold + " must either be the path to a " + 'file'.underline + " that does " + 'not'.underline + " yet exist or the path to a " + 'directory'.underline + " (which may or may not yet exist)."
          return
        end
      end

      if @create_parents and !Subversion.under_version_control?(destination_dir = File.dirname(destination))
        puts "Creating parent directory '#{destination_dir}'..."
        self.mkdir destination_dir   # @create_parents flag will be reused there
      end

      # Unlike the built-in move, this one lets you list multiple source files 
      #   Source... DestinationDir
      # or
      #   Source Destination
      # Useful when you have a long list of files you want to move, such as when you are using wild-cards. Makes commands like this possible:
      #   svn mv source/* dest/
      if args.length >= 2
        sources = args

        sources.each do |source|
          puts filtered_svn('move', source, destination)
        end
      else
        svn :exec, 'move', *(args + [destination])
      end
    end
    alias_subcommand :mv => :move

    #-----------------------------------------------------------------------------------------------------------------------------
    module Copy
      Console::Command.pass_through({
          [:_r, :__revision] => 1,
          [:_q, :__quiet] => 0,
          [:__force] => 0,
        }.
          merge(SvnCommand::C_standard_remote_command_options).
          merge(SvnCommand::C_standard_commitable_command_options), self
      )
    end

    def copy(*args)
      destination = args.pop

      # Unlike the built-in copy, this one lets you list multiple source files 
      #   Source... DestinationDir
      # or
      #   Source Destination
      # Useful when you have a long list of files you want to copy, such as when you are using wild-cards. Makes commands like this possible:
      #   svn cp source/* dest/
      if args.length >= 2
        sources = args

        sources.each do |source|
          puts filtered_svn('copy', source, destination)
        end
      else
        svn :exec, 'copy', *(args + [destination])
      end
    end
    alias_subcommand :cp => :copy

    #-----------------------------------------------------------------------------------------------------------------------------
    module Import
      Console::Command.pass_through({
        [:_N, :__non_recursive] => 0,
        [:_q, :__quiet] => 0,
        [:__auto_props] => 0,
        [:__no_auto_props] => 0,
        }.
          merge(SvnCommand::C_standard_remote_command_options).
          merge(SvnCommand::C_standard_commitable_command_options), self
      )
    end
    def import(*args)
      p args
      svn :exec, 'import', *(args)
    end

    #-----------------------------------------------------------------------------------------------------------------------------
    module Status
      # Has no effect :(  :
      def initialize
        @only_statuses = []
      end
      # So we'll do this instead:
      def self.extended(klass)
        klass.instance_variable_set(:@only_statuses, [])
      end

      Console::Command.pass_through({
          [:_u, :__show_updates] => 0,
          [:_v, :__verbose] => 0,
          [:_N, :__non_recursive] => 0,
          [:_q, :__quiet] => 0,
          [:__no_ignore] => 0,
          [:__incremental] => 0,
          [:__xml] => 0,
          [:__ignore_externals] => 0,
        }.merge(SvnCommand::C_standard_remote_command_options), self
      )
      def __modified;  @only_statuses << 'M'; end
      def __added;     @only_statuses << 'A'; end
      def __untracked; @only_statuses << '?'; end
      def __deleted;   @only_statuses << 'D'; end
      alias_method :_M, :__modified
      alias_method :_A, :__added
      alias_method :_?, :__untracked
      alias_method :_D, :__deleted

      #document :__files_only do
      "Only list filenames, not statuses"
      "(also currently lists directories with property changes -- not sure if it should or not)"
      "Useful if you want to pipe a list of files to xargs, for instance."
      "Examples:"
      "subwrap st -M -A --files-only | xargs svn diff"
      "for f in `subwrap st -M -A --files-only` ; do diff $f new_path/$f ; done"
      "for f in `subwrap st -M -A --files-only` ; do cp $f new_path/$f ; done"
      #end
      def __files_only
        @files_only = true
      end
      alias_method :__files, :__files_only
    end
    def status(*args)
      options = {}
      options[:only_statuses] = @only_statuses
      options[:files_only] = @files_only
      print Subversion.status_lines_filter( Subversion.status(*(prepare_args(args))), options )
    end

    #-----------------------------------------------------------------------------------------------------------------------------
    module Update
      Console::Command.pass_through({
          [:_r, :__revision] => 1,
          [:_N, :__non_recursive] => 0,
          [:_q, :__quiet] => 0,
          [:__diff3_cmd] => 1,
          #[:__ignore_externals] => 0,
        }.merge(SvnCommand::C_standard_remote_command_options), self
      )

      def __ignore_externals;  @ignore_externals = true; end
      def __include_externals; @ignore_externals = false; end
      def __with_externals;    @ignore_externals = false; end
      alias_method :_ie,             :__ignore_externals
      alias_method :_skip_externals, :__ignore_externals

      def ignore_externals?
        @ignore_externals.nonnil? ?
          @ignore_externals : 
          (user_preferences['update'] && user_preferences['update']['ignore_externals'])
      end

      # Duplicated with Diff
      def __non_recursive
        @non_recursive = true
        @passthrough_options << '--non-recursive'
      end
      alias_method :_N, :__non_recursive

    end

    def update(*args)
      directory = (args[0] ||= './')
      revision_of_directory = Subversion.latest_revision_for_path(directory)
      puts "(Note: The working copy '#{directory.white.bold}' was at #{('r' + revision_of_directory.to_s).magenta.bold} before updating...)"

      @passthrough_options << '--ignore-externals' if ignore_externals?
      Subversion.print_commands! do   # Print the commands and options used so they can be reminded that they're using user_preferences['update']['ignore_externals']...
        puts Subversion.update_lines_filter( Subversion.update(*prepare_args(args)) )
      end
    end









    #-----------------------------------------------------------------------------------------------------------------------------
    # Custom subcommands
    #-----------------------------------------------------------------------------------------------------------------------------

    #-----------------------------------------------------------------------------------------------------------------------------
    def url(*args)
      puts Subversion.url(*args)
    end

    #-----------------------------------------------------------------------------------------------------------------------------

    def under_version_control(*args)
      puts Subversion.under_version_control?(*args)
    end
    alias_subcommand :under_version_control? => :under_version_control

    # Returns root/base *path* for a working copy
    def working_copy_root(*args)
      puts Subversion.working_copy_root(*args)
    end
    alias_subcommand :root => :working_copy_root

    # Returns the UUID for a working copy/URL
    def repository_uuid(*args)
      puts Subversion.repository_uuid(*args)
    end
    alias_subcommand :uuid => :repository_uuid

    # Returns root repository *URL* for a working copy
    def repository_root(*args)
      puts Subversion.repository_root(*args)
    end
    alias_subcommand :base_url => :repository_root
    alias_subcommand :root_url => :repository_root

    #-----------------------------------------------------------------------------------------------------------------------------
    def latest_revision(*args)
      puts Subversion.latest_revision
    end
    alias_subcommand :last_revision => :latest_revision
    alias_subcommand :head          => :latest_revision

    #-----------------------------------------------------------------------------------------------------------------------------

    # *Experimental*
    #
    # Combine commit messages / diffs for the given range for the given files. Gives one aggregate diff for the range instead of many individual diffs.
    #
    # Could be useful for code reviews?
    #
    # Pass in a list of revisions/revision ranges ("134", "134:136", "134-136", and "134-136 139" are all valid)
    #
    # :todo: How is this different from whats_new?
    #
    module ViewCommits
      def _r(*revisions)
        # This is necessary so that the -r option doesn't accidentally eat up an arg that wasn't meant to be a revision (a filename, for instance). The only problem with this is if there's actully a filename that matches these patterns! (But then we could just re-order ars.)
        revisions.select! do |revision|
          revision =~ /\d+|\d+:\d+/
        end
        @revisions = revisions
        @revisions.size
      end
    end
    def view_commits(path = "./")
      if @revisions.nil?
        raise "-r (revisions) option is mandatory"
      end
      $ignore_dry_run_option = true
      base_url = Subversion.base_url(path)
      $ignore_dry_run_option = false
      #puts "Base URL: #{base_url}"
      revisions = self.class.parse_revision_ranges(@revisions)
      revisions.each do |revision|
        puts Subversion.log("-r #{revision} -v #{base_url}")
      end
      
      puts Subversion.diff("-r #{revisions.first}:#{revisions.last} #{path}")
      #/usr/bin/svn diff http://code.qualitysmith.com/gemables/subversion@2279 http://code.qualitysmith.com/gemables/subwrap@2349 --diff-cmd colordiff

    end
    alias_subcommand :code_review => :view_commits

    def SvnCommand.parse_revision_ranges(revisions_array)
      revisions_array.map do |item|
        case item
          when /(\d+):(\d+)/
            ($1.to_i .. $2.to_i)
          when /(\d+)-(\d+)/
            ($1.to_i .. $2.to_i)
          when /(\d+)\.\.(\d+)/
            ($1.to_i .. $2.to_i)
          when /\d+/
            item.to_i
          else
            raise "Item in revisions_array had an unrecognized format: #{item}"
        end
      end.expand_ranges
    end

    #-----------------------------------------------------------------------------------------------------------------------------
    # Goes through each "unadded" file (each file reporting a status of <tt>?</tt>) reported by <tt>svn status</tt> and asks you what you want to do with them (add, delete, or ignore)
    def each_unadded(*args)
      catch :exit do

        $ignore_dry_run_option = true
        Subversion.each_unadded( Subversion.status(*args) ) do |file|
          $ignore_dry_run_option = false
          begin
            puts( ('-'*100).green )
            puts "What do you want to do with '#{file.white.underline}'?".white.bold
            begin
              if !File.exist?(file)
                raise "#{file} doesn't seem to exist -- even though it was reported by svn status"
              end
              if File.file?(file)
                if FileTest.binary_file?(file)
                  puts "(Binary file -- cannot show preview)".bold
                else
                  puts "File contents:"
                  # Only show the first x bytes so that we don't accidentally dump the contens of some 20 GB log file to screen...
                  contents = File.read(file, bytes_threshold = 5000) || ''
                  max_lines = 55
                  contents.lines[0..max_lines].each {|line| puts line}
                  puts "..." if contents.length >= bytes_threshold          # So they know that there may be *more* to the file than what's shown
                end
              elsif File.directory?(file)
                puts "Directory contains:"
                Dir.new(file).reject {|f| ['.','..'].include? f}.each do |f|
                  puts f
                end
              else
                raise "#{file} is not a file or directory -- what *is* it then???"
              end
            end
            print(
              "Add".menu_item(:green) + ", " +
              "Delete".menu_item(:red) + ", " +
              "add to " + "svn:".yellow + "Ignore".menu_item(:yellow) + " property, " + 
              "ignore ".yellow + "Contents".menu_item(:yellow) + " of directory, " + 
              "or " + "any other key".white.bold + " to do nothing > "
            )
            response = ""
            response = $stdin.getch.downcase # while !['a', 'd', 'i', "\n"].include?(begin response.downcase!; response end)

            case response
              when 'a'
                print "\nAdding... "
                Subversion.add file
                puts
              when 'd'
                puts

                response = ""
                if File.directory?(file)
                  response = confirm("Are you pretty much " + "SURE".bold + " you want to '" + "rm -rf #{file}".red.bold + "'? ")
                else
                  response = "y"
                end

                if response == 'y'
                  print "\nDeleting... "
                  FileUtils.rm_rf file
                  puts
                else
                  puts "\nI figured as much!"
                end
              when 'i'
                print "\nIgnoring... "
                Subversion.ignore file
                puts
              else
                # Skip / Do nothing with this file
                puts " (Skipping...)"
            end
          rescue Interrupt
            puts "\nGoodbye!"
            throw :exit
          end
        end # each_unadded

      end # catch :exit
    end
    alias_subcommand :eu => :each_unadded
    alias_subcommand :unadded => :each_unadded




    #-----------------------------------------------------------------------------------------------------------------------------
    # Externals-related commands
    
    # Prints out all the externals *items* for the given directory. These are the actual externals listed in an svn:externals property.
    # Example:
    #   vendor/a
    #   vendor/b
    # Where 'vendor' is an ExternalsContainer containing external items 'a' and 'b'.
    # (Use the -o/--omit-repository-path option if you just want the external paths/names without the repository paths)
    module ExternalsItems
      def __omit_repository_path
        @omit_repository_path = true
      end
      alias_method :__omit_repository, :__omit_repository_path
      alias_method :_o,                :__omit_repository_path
      alias_method :_name_only,        :__omit_repository_path
    end
    def externals_items(directory = "./")
      longest_path_name = 25

      externals_structs = Subversion.externals_containers(directory).map do |external|
        returning(
          external.entries_structs.map do |entry|
              Struct.new(:path, :repository_path).new(
                File.join(external.container_dir, entry.name).relativize_path,
                entry.repository_path
              )
            end
        ) do |entries_structs|
          longest_path_name = 
            [
              longest_path_name,
              entries_structs.map { |entry|
                entry.path.size
              }.max.to_i
            ].max
        end
      end

      puts externals_structs.map { |entries_structs|
        entries_structs.map { |entry|
          entry.path.ljust(longest_path_name + 1) +
            (@omit_repository_path ? '' : entry.repository_path)
        }
      }
      puts "(Tip: Also consider using svn externals_outline. Or use the -o/--omit-repository-path option if you just want a list of the paths that are externalled (without the repository URLs that they come from)".magenta unless @omit_repository_path
    end
    alias_subcommand :ei             => :externals_items
    alias_subcommand :externals_list => :externals_items
    alias_subcommand :el             => :externals_items
    alias_subcommand :externals      => :externals_items
    alias_subcommand :e              => :externals_items


    # For every directory that has the svn:externals property set, this prints out the container name and then lists the contents of its svn:externals property (dir, URL) as a bulleted list
    def externals_outline(directory = "./")
      puts Subversion.externals_containers(directory).map { |external|
        external.to_s.relativize_path
      }
    end
    alias_subcommand :e_outline => :externals_outline
    alias_subcommand :eo        => :externals_outline

    # Lists *directories* that have the svn:externals property set.
    def externals_containers(directory = "./")
      puts Subversion.externals_containers(directory).map { |external|
        external.container_dir
      }
    end
    alias_subcommand :e_containers => :externals_containers

    def edit_externals(directory = nil)
      catch :exit do
        if directory.nil? || !Subversion::ExternalsContainer.new(directory).has_entries?
          if directory.nil?
            puts "No directory specified. Editing externals for *all* externals dirs..."
            directory = "./"
          else
            puts "Editing externals for *all* externals dirs..."
          end
          Subversion.externals_containers(directory).each do |external|
            puts external.to_s
            command = "propedit svn:externals #{external.container_dir}"
            begin
              response = confirm("Do you want to edit svn:externals for this directory?".black_on_white)
              svn :system,  command if response == 'y'
            rescue Interrupt
              puts "\nGoodbye!"
              throw :exit
            ensure
              puts
            end
          end
          puts 'Done'
        else
          #system "#{Subversion.executable} propedit svn:externals #{directory}"
          svn :system, "propedit svn:externals #{directory}"
        end
      end # catch :exit
    end
    alias_subcommand :edit_ext => :edit_externals
    alias_subcommand :ee => :edit_externals
    alias_subcommand :edit_external => :edit_externals

    module Externalize
      # :todo: shortcut to create both __whatever method that sets instance variable 
      #   *and* accessor method 'whatever' for reading it (and ||= initializing it)
#      Console::Command.option({
#        :as => 1         # 1 is arity
#        :as => [1, nil]  # 1 is arity, nil is default?
#      )

      def __as(as); @as = as; end
      def as; @as; end
    end
    #   svn externalize http://your/repo/shared_tasks/tasks --as shared
    # or
    #   svn externalize http://your/repo/shared_tasks/tasks shared
    def externalize(repo_path, as_arg = nil)
      # :todo: let them pass in local_path as well? -- then we would need to accept 2 -- 3 -- args, the first one poylmorphic, the second optional
      # :todo: automated test for as_arg/as combo

      Subversion.externalize(repo_path, {:as => as || as_arg})
    end




    #-----------------------------------------------------------------------------------------------------------------------------
    # It seems that if a file has been modified, it doesn't matter if you svn:ignore it -- it *still* shows up in svn st/diff and
    # *still* will be committed if you commit the directory that contains it. That is bad.
    #
    # http://svn.haxx.se/users/archive-2006-11/0055.shtml
    # > Is there a way to mark a file as local changes only so that
    # > this file's changes will not be comitted? 
    # No. The standard solution is to check in a template with a different filename and have your users copy it to the real 
    # filename which is not under version control and on the ignore list.
    #
    # http://svnbook.red-bean.com/en/1.2/svn.advanced.props.html#svn.advanced.props.special.ignore
    # http://svnbook.red-bean.com/en/1.2/svn.advanced.html#svn.advanced.confarea.opts.config (global-ignores)
    #
    # In short, it looks like svn:ignore can ONLY be used to make svn ignore unversioned files. It doesn't work at all with versioned
    # files.
    #
    # But that's not an acceptable solution for some of us! Sometimes there are things in under version control that we want to make local changes to
    # without committing them and we can't just force all users of the repository to rename this file to whatever.dist...
    # At least not yet ... not without discussing it, etc. first. So in the meantime, we need something like this...
    #
    # So subwrap provides a higher-level mechanism for ignoring local changes to versioned files.
    #
    # We DON'T want to store local-ignores in an svn property, because then the property itself could accidentally get committed.
    #
    # But we need to store locally-ignored files SOMEWHERE persistent (in a file) ... how about in the .svn dir where svn keeps its
    # metadata? (Being careful, of course, not to conflict with any of its files/conventions.)
    
    # To do:
    # Have every command that needs to read ./.svn/local_ignores
    # Commands that need to respect local ignores:
    #   status
    #   diff
    #   commit!!
    # Since built-in svn commit doesn't let you say "commit this directory except for these files in it"...
    # Modify commit so that instead of passing dir name directly to svn, pass dir name with --non-recursive (to commit prop changes)
    #   and calculate a list of all files to commit within the directory and pass the filenames too...
    #   but reject from the file list everything listed in dir/.svn/local_ignores (for every subfolder too!)
    # Add an --except option to commit, which will do the same thing, but with user-supplied list
    
    module LocalIgnore
    end

    def local_ignore
      #...
    end
    alias_method :dont_commit,              :local_ignore
    alias_method :pretend_isnt_versioned,   :local_ignore

    #-----------------------------------------------------------------------------------------------------------------------------

    def ignore(file)
      Subversion.ignore(file)
    end

    # Example:
    #   svn edit_ignores tmp/sessions/
    def edit_ignores(directory = './')
      #puts Subversion.get_property("ignore", directory)
      # If it's empty, ask them if they want to edit it anyway??

      svn :system, "propedit svn:ignore #{directory}"
    end


    #-----------------------------------------------------------------------------------------------------------------------------
    # Commit message retrieving/editing

    module GetMessage
      def __revision(revision)
        @revision = revision
      end
      alias_method :_r,   :__revision
    end
    def get_message()
      #svn propget --revprop svn:log -r2325
      args = ['propget', '--revprop', 'svn:log']
      #args.concat ['-r', @revision ? @revision : Subversion.latest_revision]
      args.concat ['-r', (revision = @revision ? @revision : 'head')]
      puts "Message for r#{Subversion.latest_revision} :" if revision == 'head'

      $ignore_dry_run_option = true
      puts filtered_svn(*args)
      $ignore_dry_run_option = false
    end

    module SetMessage
      def __revision(revision)
        @revision = revision
      end
      alias_method :_r,   :__revision

      def __file(filename)
        @filename = filename
      end
    end
    def set_message(new_message)
      #svn propset --revprop -r 25 svn:log "Journaled about trip to New York."
      puts "Message before changing:"
      get_message

      args = ['propset', '--revprop', 'svn:log']
      args.concat ['-r', @revision ? @revision : 'head']
      args << new_message if new_message
      if @filename
        contents = File.readlines(@filename).join.strip
        puts "Read file '#{@filename}':"
        print contents
        puts
        args << contents
      end
      svn :exec, *args
    end

    # Lets you edit it with your default editor
    module EditRevisionProperty
      def __revision(revision)
        @revision = revision
      end
      alias_method :_r,   :__revision
    end
    def edit_revision_property(property_name, directory = './')
      args = ['propedit', '--revprop', property_name, directory]
      rev = @revision ? @revision : 'head'
      args.concat ['-r', rev]
      Subversion.print_commands! do
        svn :system, *args
      end

      value = Subversion::get_revision_property(property_name, rev)
      p value

      # Currently there is no seperate option to *delete* a revision property (propdel)... That would be useful for those
      # properties that are just boolean *flags* (set or not set).
      # I'm assuming most people will very rarely if ever actually want to set a property to the empty string (''), so
      # we can use the empty string as a way to trigger a propdel...
      if value == ''
        puts
        response = confirm("Are you sure you want to delete property #{property_name}".red.bold + "'? ")
        puts
        if response == 'y'
          Subversion.print_commands! do
            Subversion::delete_revision_property(property_name, rev)
          end
        end
      end
    end

    # Lets you edit it with your default editor
    module EditMessage
      def _r(revision)
        @revision = revision
      end
    end
    def edit_message(directory = './')
      edit_revision_property('svn:log', directory)
    end

    def edit_property(property_name, directory = './')
    end

    #-----------------------------------------------------------------------------------------------------------------------------
    # Cause a working copy to cease being a working copy
    def delete_svn(directory = './')
      puts "If you continue, all of the following directories/files will be deleted:"
      system("find #{directory} -name .svn -type d | xargs -n1 echo")
      response = confirm("Do you wish to continue?")
      puts

      if response == 'y'
        system("find #{directory} -name .svn -type d | xargs -n1 rm -r")
      end
    end

    #-----------------------------------------------------------------------------------------------------------------------------

    def add_all_unadded
      raise NotImplementedError
    end
    def grep
      raise NotImplementedError
    end
    def grep_externals
      raise NotImplementedError
    end
    def grep_log
      raise NotImplementedError
    end

    #-----------------------------------------------------------------------------------------------------------------------------
    # :todo: Pre-fetch svn diff in the background (fork the process) so you don't have to wait, in interactive mode.
    # :todo: When calling this command on a single file, 
    # * default to not showing all that annoying list of files (-v) but yes to automatically showing diffs.
    # * currently defaults to showingly only changes to this file, but should be option for View this changeset to show the full changeset
    # :todo: add number aliases (1) for view changeset, etc. so you can use numpad exclusively
    # :todo: rename interactive mode to different name, s.a. browse_revisions
    # Add --grep option to non-interactively search all changesets returned for a pattern.
    module ShowOrBrowseRevisions
      # We will pass all of these options through to 'svn log'
      Console::Command.pass_through({
          [:_q, :__quiet] => 0,
          [:_v, :__verbose] => 0,
          [:__targets] => 1,
          [:__stop_on_copy] => 0,
          [:__incremental] => 0,
          [:__xml] => 0,
          #[:__limit] => 1,
        }.merge(SvnCommand::C_standard_remote_command_options), self
      )

      #-------------------------------------------------------------------------
      def documentation
        "Examples:
        > subwrap revisions --limit 5 -r {2008-06-10}:head .
        "
      end

      #-------------------------------------------------------------------------
      def __revision(revisions)
        @revisions = revisions
      end
      alias_method :_r,   :__revision

      #-------------------------------------------------------------------------
      def __all
        @first_revision = '1'
        @last_revision  = 'head'
        @oldest_first_default = false
        @limit = false
      end

      def __limit(limit)
        @limit = limit
      end

      def __since_last_update
        @first_revision = '%base%'
        @last_revision  = 'head'
        @oldest_first_default = true
      end
      alias_method :__from_base,   :__since_last_update
      alias_method :__since_base,  :__since_last_update

      # :todo: Problem: I often forget to run this *before* doing an svn update. But as soon as I do an update, base is updated and now there is *nothing* new since last update.
      # Possible solution: 
      # :todo: Keep a log of updates (at least all updates that use this wrapper) and let you go back to any previous update as your starting point if you've updated very recently and want to go back farther than that.
      # (Or maybe .svn has a record of the previous update time somewhere that we can pick up?)
      #
      def __whats_new
        @first_revision = '%base%'
        @last_revision  = 'head'
        @oldest_first_default = true
      end
      alias_method :__new,         :__since_last_update
      alias_method :__whats_new,   :__since_last_update

      #-------------------------------------------------------------------------
      # revision can be revision number or date.
      # :todo: allow 'yesterday', etc. or absolute time
      #   Use chronic?
      # :todo:
      def __from(revision)
        @first_revision = revision
        @last_revision  = 'head'
        @oldest_first_default = true
      end
      alias_method :__since,   :__from

      def __back_to(revision)
        @first_revision = revision
        @last_revision  = 'head'
        @oldest_first_default = false
      end

      # :todo: if they're not at the root of the repo, this may not give them what they want
      # they may want the last revisions for a specific file, in which case the latest_revision will likely not be the right revision number
      def __last(revision_count)
        @first_revision = Subversion.latest_revision - revision_count.to_i + 1
        @last_revision  = Subversion.latest_revision
      end

      #-------------------------------------------------------------------------
      # Show diffs automatically for each revision without the user having to press v
      def __show_diffs
        @show_diffs = true
      end
      alias_method :__auto_diffs,   :__show_diffs

      #-------------------------------------------------------------------------
      def __show_file_list;      @show_file_list = true; end
      def __no_file_list;        @show_file_list = false; end

      #-------------------------------------------------------------------------
      def __fetch_all_diffs_up_front
        # :todo:
        # So that when you're actually stepping through revisions, viewing a diff is instantaneous...
      end

      #-------------------------------------------------------------------------
      # Start at earlier revision and go forwards rather than starting at the latest revision
      def __oldest_first
        @oldest_first = true
      end
      alias_method :__forward,         :__oldest_first
      alias_method :__forwards,        :__oldest_first
      alias_method :__chronological,   :__oldest_first

      def __newest_first
        @oldest_first = false
      end
      alias_method :__reverse,     :__newest_first
      alias_method :__backwards,   :__newest_first

      #-------------------------------------------------------------------------
      # Automatically fetch and print all diffs, pipe to a pager.
      # Great for catching up on what's new, skimming through recent commits.
      # (Whereas intercative mode is better for investigating, searching for the right commit that corresponds to some change you noticed, etc.)
      def __non_interactive
        @interactive = false
      end
      alias_method :__ni,     :__non_interactive

      def __paged
        @paged = true
      end

      def __interactive
        @interactive = true
      end

      #-------------------------------------------------------------------------
      # Only show revisions that are in need of a code review
      # :todo:
      def __unreviewed_only
        @unreviewed_only = true
      end

      # Only show revisions that were committed by a certain author.
      # :todo:
      def __by(author)
        @author_filter = author
      end
      def __author(author)
        @author_filter = author
      end
    end
    # :todo: what if they pass in *2* filenames?
    # See also: the implementation of revisions() in /usr/lib/ruby/gems/1.8/gems/rscm-0.5.1/lib/rscm/scm/subversion.rb
    
    module Revisions
      def self.extended(base)
        base.extend ShowOrBrowseRevisions
      end
    end
    def play_revisions(directory = './')
      @interactive = false
      show_or_browse_revisions(directory)
    end
    alias_subcommand :changesets      => :revisions
    alias_subcommand :show_log        => :revisions
    alias_subcommand :show_revisions  => :revisions
    alias_subcommand :show_changesets => :revisions

    module Browse
      def self.extended(base)
        base.extend ShowOrBrowseRevisions
      end
    end
    def browse(directory = './')
      @interactive = true
      show_or_browse_revisions(directory)
    end
    alias_subcommand :revisions         => :browse
    alias_subcommand :browse            => :browse
    alias_subcommand :browse_log        => :browse
    alias_subcommand :browse_revisions  => :browse
    alias_subcommand :browse_changesets => :browse
    # Other so-far-rejected name ideas: list_commits, changeset_browser, log_browser, interactive_log

    # This is designed to be a convenient replacement to the svn update command for those who wish to not only see a *list* of 
    # which files were updated as the update occurs but also wish to see *what changed* for each of those files.
    # So this command will effectively do a diff on each updated file and show you what has changed (= "what's new").
    #
    # Should this command run an update or do people want to run this command after an update??
    # Nah... an update can be really slow... and they may have just done one...
    module WhatsNew
      def self.extended(base)
        base.extend ShowOrBrowseRevisions
      end
    end
    def whats_new(directory = './')
      revision_of_directory = Subversion.latest_revision_for_path(directory)

      #__whats_new
      # (allow this to be overriden with, for example, a --since option)
      @first_revision_default = revision_of_directory.to_s
      @last_revision_default  = 'head'
      @oldest_first_default = true

      #puts "Updating..."
      #Subversion.update(directory)  # silent
      #Subversion.execute("update")

      @interactive = false
      show_or_browse_revisions(directory)
    end

    #-------------------------------------------------------------------------
    protected
    def show_or_browse_revisions(directory = './')
      #-----------------------------
      head = Subversion.latest_revision
      revision_of_directory = Subversion.latest_revision_for_path(directory)

      # By default, if you just do an svn log (which is what we do to get the metadata about each revision), svn will only show revisions up to and Last Changed Rev.
      # So if there have been newer revisions since then, it won't show the log messages for them. 
      # I can't think of a good reason why it shouldn't. I think it's a bug in the svn client.
      #
      # Also, it's possible for the Last Changed Rev of to be "out of date" even if you were the last committer! 
      # If you commit file lib/foo.rb, the Last Changed Rev of lib/foo.rb may be 13 but the Last Changed Rev of . will still be 10 until you update '.'.
      # In other words each *directory* has a different Last Changed Rev.
      # 
      # Anyway, to work around this bug, we explicitly get the head revision number from the server and pass that as the ending revision number to svn log.
      # So in our example, we would pass -r 1:13 to svn log even when doing `svn browse .`, to ensure that we get information for all revisions
      # all the way up to head (13).
      #
      # :todo: do the same for svn log
      if revision_of_directory and head and revision_of_directory < head
        puts "The working copy '#{directory.white.bold}' appears to be out-of-date (#{revision_of_directory.to_s.magenta.bold}) with respect to the head revision (#{head.to_s.magenta.bold}). Just so ya know..."
        #Subversion.update(directory)
      end
      #-----------------------------

      args = [directory]

      unless @revisions
        @first_revision_default ||= '1' #'%base%'
        @last_revision_default  ||= 'head'

        @first_revision ||= @first_revision_default
        @last_revision  ||= @last_revision_default
        #@first_revision, @last_revision = @last_revision, @first_revision if @oldest_first
        @revisions = "#{@first_revision}:#{@last_revision}"
      end
      @revisions.gsub! /%base%/, revision_of_directory.to_s
      args.concat ['-r', @revisions] 

      @limit_default = nil #10
      @limit = @limit_default               if @limit.nil? and @limit_default
      args.concat ['--limit', @limit_default.to_s] if @limit

      @oldest_first_default = true          if @oldest_first_default.nil?
      @oldest_first = @oldest_first_default if @oldest_first.nil?

      @show_diffs ||= true if !@interactive
      @show_diffs_default ||= false
      @show_diffs ||= @show_diffs_default

      if @show_file_list.nil?
        if directory == './' # They are using the default directory
          @show_file_list = true
        else
          @show_file_list = false
        end
      end

      #puts "@interactive=#{@interactive}"
      #puts "@oldest_first=#{@oldest_first}"
      #puts "@revisions=#{@revisions}"
      #pp prepare_args(args)

      #-----------------------------
      puts "Getting revision details for '#{directory.green.bold}', revisions #{@revisions.magenta.bold} #{"(up to #{@limit} of them) " if @limit}(this may take a moment) ..."
      #require 'unroller'
      #Unroller.trace :dir_match => __FILE__ do
      #Subversion.print_commands! do
        revisions = Subversion.revisions(*prepare_args(args))
      #end
      #end

      #-----------------------------
      run_pager if !@interactive and @paged
      puts "#{revisions.length.to_s.bold} revisions found. Starting with #{(@oldest_first ? 'oldest' : 'most recent').white.bold} revision and #{@oldest_first ? 'going forward in time' : 'going backward in time' }..."
      #pp revisions.map {|r| [r.identifier, r.time]}
      revisions.instance_variable_get(:@revisions).reverse! unless @oldest_first  # :todo: or just swap first and last when building @revisions? no, I think there are some cases when that wouldn't work...
      revision_ids = revisions.map(&:identifier)

      #-----------------------------------------------------------------------
      # The main loop through the array of revisions
      #revisions.each do |revision|
      i = 0
      #target_rev = nil # revision_ids.first
      show_revision = true
      show_menu = true
      revision = revisions[i]
      begin # rescue
      loop do
        show_revision = false if show_menu == false

        rev = revision.identifier
        other_rev = rev-1
        counter = revision_ids.index(rev) + 1

        #if target_rev
        #  if rev == target_rev
        #    target_rev = nil    # We have arrived.
        #  else
        #    next                # Keep going (hopefully in the right direction!)
        #  end
        #end

        #-----------------------------------------------------------------------
        show_diffs = proc {
          revs_to_compare = [other_rev, rev]
          #puts "\n"*10
          puts
          puts((' '*100).green.underline)
          print "Diffing #{revs_to_compare.min.to_s.magenta.bold}:#{revs_to_compare.max.to_s.magenta.bold}... ".bold
          puts
          #Subversion.repository_root
          #Subversion.print_commands! do
            SvnCommand.execute("diff #{directory} --ignore-externals -r #{revs_to_compare.min}:#{revs_to_compare.max}")
          #end
        }

        #-----------------------------------------------------------------------
        # Display the revision (number, date, description, files changed)
        if show_revision
          #puts((' '*100).green.underline)
          puts
          #puts((' '*100).on_green)

          #puts "#{revisions.length - revision_ids.index(rev)}. ".green.bold +
          puts (
              "r#{rev}".white.bold.on_green + (rev == head ? ' (head)'.bold.on_green : '') + 
              " | #{revision.developer} | #{revision.time.strftime('%Y-%m-%d %H:%M:%S')}".white.bold.on_green
            ).ljust_with_color(100, ' '.on_green)
          puts revision.message
          puts
          #pp revision
          if @show_file_list
            puts revision.map {|a|
              (a.status ? a.status[0..0].colorize_svn_status_code : ' ') +   # This check is necessary because RSCM doesn't recognize several Subversion status flags, including 'R', and status will return nil in these cases.
                ' ' + a.path
            }.join("\n")
          end
        else
          show_revision = true
        end

        #-----------------------------------------------------------------------
        if @show_diffs
          show_diffs.call
        end


        #-----------------------------------------------------------------------
        # Get response from user and then act on it
        go = nil
        catch :prev_or_next do
        loop do
          go = :nowhere

          #-----------------------------------------------------------------------
          # Display the menu
          if @interactive and show_menu
            print "r#{rev}".magenta.on_blue.bold + " (#{counter}/#{revisions.length})" + " (#{'?'.bold} for help)" + ' > '
          end

          #-----------------------------------------------------------------------
          if @interactive
            response = ""
            response = $stdin.getch.downcase
          else
            #response = "\n"
            go = :next
            throw :prev_or_next
          end

          # Escape sequence such as the up arrow key ("\e[A")
          if response == "\e"
            response << (next_char = $stdin.getch)
            if next_char == '['
              response << (next_char = $stdin.getch)
            end
          end

          if response == 'd' # diff against Other revision
            response = 'v'
            puts
            print 'All right, which revision shall it be then? '.bold + ' (backspace not currently supported)? '
            other_rev = $stdin.gets.chomp.to_i
          end

          case response

            when '?'   # Help
              show_menu = false
              puts
              puts(
                'View this changeset'.menu_item(:cyan) + ', ' +
                'Diff against specific revision'.menu_item(:cyan, 'D') + ', ' +
                'Grep the changeset'.menu_item(:cyan, 'G') + ', ' +
                'List or '.menu_item(:magenta, 'L') + '' +
                'Edit revision properties'.menu_item(:magenta, 'E') + ', ' +
                'svn Cat all files'.menu_item(:cyan, 'C') + ', ' +
                'grep the cat'.menu_item(:cyan, 'a') + ', ' + "\n  " +
                'mark as Reviewed'.menu_item(:green, 'R') + ', ' +
                'edit log Message'.menu_item(:yellow, 'M') + ', ' +
                'browse using ' + 'Up/Down/Left/Right/Space/Enter'.white.bold + ' keys' + ', ' +
                'Quit'.menu_item(:magenta)
              )
              show_revision = false # only show the menu

            when '1', 'v'  # View this changeset
              show_diffs.call
              show_revision = false # only show the menu

            when 'g'  # Grep the changeset
              # :todo; make it accept regexpes like /like.*this/im so you can make it case insensitive or multi-line
              revs_to_compare = [other_rev, rev]
              puts
              print 'Grep for'.bold + ' (Case sensitive; Regular expressions ' + 'like.*this'.bold.blue + ' allowed, but not ' + '/like.*this/im'.bold.blue + ') (backspace not currently supported): '
              search_pattern = $stdin.gets.chomp.to_rx
              puts((' '*100).green.underline)
              puts "Searching `svn diff #{directory} -r #{revs_to_compare.min}:#{revs_to_compare.max}` for #{search_pattern.to_s}... ".bold
              diffs = nil
              #Subversion.print_commands! do
                diffs = Subversion.diffs(directory, '-r', "#{revs_to_compare.min}:#{revs_to_compare.max}")
              #end

              hits = 0
              diffs.each do |filename, diff|
                #.grep(search_pattern)
                if diff.diff =~ search_pattern
                  puts diff.filename_pretty
                  puts( diff.diff.grep(search_pattern). # This will get us just the interesting *lines* (as an array). 
                    map { |line|                        # Now, for each line...
                      hits += 1
                      line.highlight_occurences(search_pattern)
                    }
                  )
                end
              end
              if hits == 0
                puts "Search term not found!".red.bold
              end
              show_revision = false

            when 'a'  # Grep the cat
              puts
              print 'Grep for'.bold + ' (Case sensitive; Regular expressions ' + 'like.*this'.bold.blue + ' allowed, but not ' + '/like.*this/im'.bold.blue + ') (backspace not currently supported): '
              search_pattern = $stdin.gets.chomp.to_rx
              puts((' '*100).green.underline)
              puts "Searching `svn cat #{directory} -r #{rev}` for #{search_pattern.to_s}... ".bold
              contents = nil
              Subversion.print_commands! do
                contents = Subversion.cat(directory, '-r', rev)
              end

              if contents =~ search_pattern
                puts( contents.grep(search_pattern). # This will get us just the interesting *lines* (as an array). 
                  map { |line|                       # Now, for each line...
                    line.highlight_occurences(search_pattern)
                  }
                )
              else
                puts "Search term not found!".red.bold
              end
              show_revision = false


            when 'l'  # List revision properties
              puts
              puts Subversion::printable_revision_properties(rev)
              show_revision = false

            when 'e'  # Edit revision property
              puts
              puts Subversion::printable_revision_properties(rev)
              puts "Warning: These properties are *not* under version control! Try not to permanently destroy anything *too* important...".red.bold
              puts "Note: If you want to *delete* a property, simply set its value to '' and it will be deleted (propdel) for you."
              print 'Which property would you like to edit'.bold + ' (backspace not currently supported)? '
              property_name = $stdin.gets.chomp
              unless property_name == ''
                Subversion.print_commands! do
                  @revision = rev
                  edit_revision_property(property_name, directory)
                end
              end

              show_revision = false

            when 'c'  # Cat all files from revision
              puts
              Subversion.print_commands! do
                puts Subversion.cat(directory, '-r', rev)
              end
              show_revision = true

            when 'r'  # Mark as reviewed
              puts
              your_name = ENV['USER'] # I would use the same username that Subversion itself would use if you committed
                                      # something (since it is sometimes different from your system username), but I don't know
                                      # how to retrieve that (except by poking around in your ~/.subversion/ directory, but
                                      # that seems kind of rude...).
              puts "Marking as reviewed by '#{your_name}'..."
              Subversion.print_commands! do
                puts svn(:capture, "propset code:reviewed '#{your_name}' --revprop -r #{rev}", :prepare_args => false)
                # :todo: Maybe *append* to code:reviewed (,-delimited) rather than overwriting it?, in case there is a policy of requiring 2 reviewers or something
              end
              show_revision = false

            when 'm'  # Edit log message
              puts
              Subversion.print_commands! do
                SvnCommand.execute("edit_message -r #{rev}")
              end
              show_revision = false

            when "\e[A", "\e\[D" # Previous (Up or Left)
              #i = revision_ids.index(rev)
              #target_rev = revision_ids[i - 1]
              puts " Previous..."
              go = :prev
              throw :prev_or_next
              #retry

            when "\n", "\e\[B", "\e\[C", " " # Next (Enter or Down or Right or Space)
              # Skip / Do nothing with this file
              puts " Next..."
              go = :next
              throw :prev_or_next
              #next

            when 'q' # Quit
              raise Interrupt, "Quitting"

            else
              # Invalid option. Do nothing.
              #puts response.inspect
              puts
              show_menu = false
              show_revision = false

          end # case response

        end # loop until they tell us they're ready to move on...
        end # catch :prev_or_next

        case go
        when :prev
          if i-1 < 0
            show_menu = false
            puts "Can't go back -- already at first revision in set!".red
          else
            show_menu = show_revision = true
            i -= 1
          end
        when :next
          if i+1 > revisions.length-1
            # We've reached the end
            if @interactive
              show_menu = false
              puts "Can't go forward -- already at last revision in set!".red
            else
              break
            end
          else
            show_menu = show_revision = true
            i += 1
          end
        end
        revision = revisions[i]

      end # loop / revisions.each

      rescue Interrupt
        puts "\nGoodbye!"
        return
      end # rescue
    end
    public

    #-----------------------------------------------------------------------------------------------------------------------------
    # Aliases
    #:stopdoc:
    alias_subcommand :st => :status
    alias_subcommand :up => :update
    alias_subcommand :ci => :commit
    #:startdoc:


    #-----------------------------------------------------------------------------------------------------------------------------
    # Helpers

  private
    def svn(method, *args)
      subcommand = args[0]
      options = args.last.is_a?(Hash) ? args.last : {}
      args = (
        [subcommand] + 
        (
          (options[:prepare_args] == false) ? 
            [] : 
            (prepare_args(args[1..-1] || []))
        ) + 
        [:method => method]
      )
      # puts "in svn(): about to call Subversion#execute(#{args.inspect})"
      Subversion.send :execute, *args
    end

    # Works identically to svn() except that it filters the output and displays a big red error message if /usr/bin/svn exied with an error.
    def filtered_svn(*args)
      # We have to use the :capture method if we're going to filter the output.
      svn(:capture, *args).add_exit_code_error
    end

    # Removes nil elements, converts to strings, and adds any pass-through args that may have been provided.
    def prepare_args(args=[])
      args.compact!       # nil elements spell trouble
      args.map!(&:to_s)   # shell_escape doesn't like Fixnums either
      @passthrough_options + args.shell_escape
    end
    # To allow testing/stubbing
    def system(*args)
      Kernel.system *args
    end
  end
end
