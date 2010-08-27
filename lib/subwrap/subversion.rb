# Tested by: ../../test/subversion_test.rb
#$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..')
$loaded ||= {}; if !$loaded[File.expand_path(__FILE__)]; $loaded[File.expand_path(__FILE__)] = true;

require 'fileutils'
require 'rexml/document'
require 'rexml/xpath'
require 'rubygems'

gem 'facets'
require 'facets/kernel/silence'
silence_warnings do
  require 'facets/kernel/require_local'
  require 'facets/kernel/in'
  require 'facets/enumerable/uniq_by'
  require 'facets/fileutils/which'
  require 'facets/fileutils/whereis'
end

gem 'quality_extensions'
require 'quality_extensions/module/initializer'
require 'quality_extensions/enumerable/map_with_index'
require 'quality_extensions/kernel/windows_platform'


# Had a lot of trouble getting ActiveSupport to load without giving errors! Eventually gave up on that idea since I only needed it for mattr_accessor and Facets supplies that.
#gem 'activesupport'  # mattr_accessor
#require 'active_support'
#require 'active_support/core_ext/module/attribute_accessors'
#require 'facets/class/cattr'
gem 'quality_extensions'
require 'quality_extensions/module/attribute_accessors'
require 'quality_extensions/module/guard_method'

# RSCM is used for some of the abstraction, such as for parsing log messages into nice data structures. It seems like overkill, though, to use RSCM for most things...
gem 'rscm'
#require 'rscm'
#require 'rscm/scm/subversion'
require 'rscm/scm/subversion_log_parser'

# Wraps the Subversion shell commands for Ruby.
module Subversion
  # True if you want output from svn to be colorized (useful if output is for human eyes, but not useful if using the output programatically)
  @@color = false
  mattr_accessor :color
  mguard_method :with_color!, :@@color

  # If true, will only output which command _would_ have been executed but will not actually execute it.
  @@dry_run = false
  mattr_accessor :dry_run

  # If true, will print all commands to the screen before executing them.
  @@print_commands = false
  mattr_accessor :print_commands
  mguard_method :print_commands!, :@@print_commands

  @@cached_commands = {}
  @@cached_commands[:latest_revision] = {}

  #-------------------------------------------------------------------------------------------------

  # Adds the given items to the repository. Items may contain wildcards.
  def self.add(*args)
    execute "add #{args.join ' '}"
  end

  # Sets the svn:ignore property based on the given +patterns+.
  # Each pattern is both the path (where the property gets set) and the property itself.
  # For instance:
  #   "log/*.log" would add "*.log" to the svn:ignore property on the log/ directory.
  #   "log" would add "log" to the svn:ignore property on the ./ directory.
  def self.ignore(*patterns)
    
    patterns.each do |pattern|
      path = File.dirname(pattern)
      path += '/' if path == '.'
      pattern = File.basename(pattern)
      add_to_property 'ignore', path, pattern
    end
    nil
  end
  def self.unignore(*patterns)
    raise NotImplementedError
  end

  # Adds the given repository URL (http://svn.yourcompany.com/path/to/something) as an svn:externals.
  #
  # Options may include:
  # * +:as+ - overrides the default behavior of naming the checkout based on the last component of the repo path
  # * +:local_path+ - specifies where to set the externals property. Defaults to '.' or the dirname of +as+ if +as+ is specified
  #   (for example, <tt>vendor/plugins</tt> if +as+ is <tt>vendor/plugins/plugin_name</tt>).
  #
  def self.externalize(repo_url, options = {})

    options[:as] ||= File.basename(repo_url)
    #options[:as] = options[:as].ljust(29)

    # You can't set the externals of './' to 'vendor/plugins/foo http://example.com/foo'
    # Instead, you have to set the externals of 'vendor/plugins/' to 'foo http://example.com/foo'
    # This will make that correction for you automatically.
    options[:local_path] ||= File.dirname(options[:as])   # Will be '.' if options[:as] has no dirname component.
                                                          # Will be 'vendor/plugins' if options[:as] is 'vendor/plugins/plugin_name'.
    options[:as] = File.basename(options[:as])

    add_to_property 'externals', options[:local_path], "#{options[:as]} #{repo_url}"
  end

  def self.export(path_or_url, target)
    execute "export #{path_or_url} #{target}"
  end

  # Removes the given items from the repository and the disk. Items may contain wildcards.
  def self.remove(*args)
    execute "rm #{args.join ' '}"
  end

  # Removes the given items from the repository and the disk. Items may contain wildcards.
  # To do: add a :force => true option to remove
  def self.remove_force(*args)
    execute "rm --force #{args.join ' '}"
  end

  # Removes the given items from the repository BUT NOT THE DISK. Items may contain wildcards.
  def self.remove_without_delete(*args)
    # resolve the wildcards before iterating
    args.collect {|path| Dir[path]}.flatten.each do |path|
      entries_file = "#{File.dirname(path)}/.svn/entries"
      File.chmod(0644, entries_file)

      xmldoc = REXML::Document.new(IO.read(entries_file))
      # first attempt to delete a matching entry with schedule == add
      unless xmldoc.root.elements.delete "//entry[@name='#{File.basename(path)}'][@schedule='add']"
        # then attempt to alter a missing schedule to schedule=delete
        entry = REXML::XPath.first(xmldoc, "//entry[@name='#{File.basename(path)}']")
        entry.attributes['schedule'] ||= 'delete' if entry
      end
      # write back to the file
      File.open(entries_file, 'w') { |f| xmldoc.write f, 0 }

      File.chmod(0444, entries_file)
    end
  end

  # Reverts the given items in the working copy. Items may contain wildcards.
  def self.revert(*args)
    execute "revert #{args.join ' '}"
  end

  # Marks the given items as being executable. Items may _not_ contain wildcards.
  def self.make_executable(*paths)
    paths.each do |path|
      self.set_property 'executable', '', path
    end
  end
  def self.make_not_executable(*paths)
    paths.each do |path|
      self.delete_property 'executable', path
    end
  end

  # Returns the status of items in the working directories +paths+. Returns the raw output from svn (use <tt>split("\n")</tt> if you want an array).
  def self.status(*args)
    args = ['./'] if args.empty?
    execute("status #{args.join ' '}")
  end

  def self.status_against_server(*args)
    args = ['./'] if args.empty?
    self.status('-u', *args)
  end

  def self.update(*args)
    args = ['./'] if args.empty?
    execute("update #{args.join ' '}")
  end

  def self.commit(*args)
    args = ['./'] if args.empty?
    execute("commit #{args.join ' '}")
  end

  # The output from `svn status` is nicely divided into two "sections": the section which pertains to the current working copy (not
  # counting externals as part of the working copy) and then the section with status of all of the externals.
  # This method returns the first section.
  def self.status_the_section_before_externals(path = './')
    status = status(path) || ''
    status.sub!(/(Performing status.*)/m, '')
  end

  # Returns an array of externals *items*. These are the actual externals listed in an svn:externals property.
  # Example:
  #   vendor/a
  #   vendor/b
  # Where 'vendor' is an ExternalsContainer containing external items 'a' and 'b'.
  def self.externals_items(path = './')
    status = status_the_section_before_externals(path)
    return [] if status.nil?
    status.select { |line|
      line =~ /^X/
    }.map { |line|
      # Just keep the filename part
      line =~ /^X\s+(.+)/
      $1
    }
  end

  # Returns an array of ExternalsContainer objects representing all externals *containers* in the working directory specified by +path+.
  def self.externals_containers(path = './')
    # Using self.externals_items is kind of a cheap way to do this, and it results in some redundancy that we have to filter out
    # (using uniq_by), but it seemed more efficient than the alternative (traversing the entire directory tree and querying for
    # `svn prepget svn:externals` at each stop to see if the directory is an externals container).
    self.externals_items(path).map { |external_dir|
      ExternalsContainer.new(external_dir + '/..')
    }.uniq_by { |external|
      external.container_dir
    }
  end

  # Returns the modifications to the working directory or URL specified in +args+.
  def self.diff(*args)
    args = ['./'] if args.empty?
    diff = execute("diff #{"--diff-cmd colordiff" if color?} #{args.join ' '}")

    # Fix annoyance: You can't seem to do a diff on a file that was *added*. If you do -r 1:2 for a file that was *added* in 2, it will say it can't find the repository location for that file in r1.
    if diff =~ /Unable to find repository location for '.*' in revision/ and @allow_diffs_for_added_files != false
      args.map!(&:to_s)
      args.map_with_index! do |arg, i| 
        if args[i-1].in? ['--revision', '-r']
          arg.gsub(/\d+:/, '') 
        elsif arg.in? ['--change', '-c']
          arg.gsub(/-c|--change/, '-r')
        else
          arg
        end
      end
      diff = execute("cat #{args.join ' '}") #.to_enum(:each_line).map(&:chomp).map(&:green).join("\n")
    end

    diff
  end
  # Parses the output from diff and returns an array of Diff objects.
  def self.diffs(*args)
    args = ['./'] if args.empty?
    raw_diffs = nil
    with_color! false do
      raw_diffs = diff(*args)
    end
    DiffsParser.new(raw_diffs).parse
  end

  def self.cat(*args)
    args = ['./'] if args.empty?
    execute("cat #{args.join ' '}")
  end

  # It's easy to get/set properties, but less easy to add to a property. This method uses get/set to simulate add.
  # It will uniquify lines, removing duplicates. (:todo: what if we want to set a property to have some duplicate lines?)
  def self.add_to_property(property, path, *new_lines)
    # :todo: I think it's possible to have properties other than svn:* ... so if property contains a prefix (something:), use it; else default to 'svn:'
    
    # Get the current properties
    lines = self.get_property(property, path).split "\n"
    puts "Existing lines: #{lines.inspect}" if $debug

    # Add the new lines, delete empty lines, and uniqueify all elements
    lines.concat(new_lines).uniq!
    puts "After concat(new_lines).uniq!: #{lines.inspect}" if $debug

    lines.delete ''
    # Set the property
    puts "About to set propety to: #{lines.inspect}" if $debug
    self.set_property property, lines.join("\n"), path
  end

  # :todo: Stop assuming the svn: namespace. What's the point of a namespace if you only allow one of them?
  def self.get_property(property, path = './')
    execute "propget svn:#{property} #{path}"
  end
  def self.get_revision_property(property_name, rev)
    execute("propget --revprop #{property_name} -r #{rev}").chomp
  end

  def self.delete_property(property, path = './')
    execute "propdel svn:#{property} #{path}"
  end
  def self.delete_revision_property(property_name, rev)
    execute("propdel --revprop #{property_name} -r #{rev}").chomp
  end

  def self.set_property(property, value, path = './')
    execute "propset svn:#{property} '#{value}' #{path}"
  end
  def self.set_revision_property(property_name, rev)
    execute("propset --revprop #{property_name} -r #{rev}").chomp
  end

  # Gets raw output of proplist command
  def self.proplist(rev)
    execute("proplist --revprop -r #{rev}")
  end
  # Returns an array of the names of all revision properties currently set on the given +rev+
  # Tessted by: ../../test/subversion_test.rb:test_revision_properties_names
  def self.revision_properties_names(rev)
    raw_list = proplist(rev)
    raw_list.scan(/^ +([^ ]+)$/).map { |matches|
      matches.first.chomp
    }
  end
  # Returns an array of RevisionProperty objects (name, value) for revisions currently set on the given +rev+
  # Tessted by: ../../test/subversion_test.rb:test_revision_properties
  def self.revision_properties(rev)
    revision_properties_names(rev).map { |property_name|
      RevisionProperty.new(property_name, get_revision_property(property_name, rev))
    }
  end

  def self.make_directory(dir)
    execute "mkdir #{dir}"
  end

  def self.help(*args)
    execute "help #{args.join(' ')}"
  end

  # Returns the raw output from svn log
  def self.log(*args)
    args = ['./'] if args.empty?
    execute "log #{args.join(' ')}"
  end

  # Returns the revision number for head.
  def self.latest_revision(path = './')
    (cached = @@cached_commands[:latest_revision][path]) and return cached
    url = url(path)

    #puts "Fetching latest revision from repository: #{url}"
    result = latest_revision_for_path(url).to_i
    @@cached_commands[:latest_revision][path] = result
    result
  end

  # Returns the revision number for the working directory(/file?) specified by +path+
  def self.latest_revision_for_path(path)
    # The revision returned by svn info seems to be a pretty reliable way to get this. Does anyone know of a better way?
    matches = info(path).match(/^Revision: (\d+)/)
    if matches
      matches[1].to_i
    else
      raise "Could not extract revision from #{info(path)}"
    end
  end

  # Returns an array of RSCM::Revision objects
  def self.revisions(*args)
    # Tried using this, but it seems to expect you to pass in a starting date or accept the default starting date of right now, which is silly if you actually just want *all* revisions...
    #@rscm = ::RSCM::Subversion.new
    #@rscm.revisions

    args = (['-v'] + args)
    log_output = Subversion.log(*args)
    parser = ::RSCM::SubversionLogParser.new(io = StringIO.new(log_output), url = 'http://ignore.me.com')
    # :todo: svn revisions -r 747 -- chops off line
    revisions = parser.parse_revisions
    revisions
  end


  def self.info(*args)
    args = ['./'] if args.empty?
    execute "info #{args.join(' ')}"
  end

  def self.url(path_or_url = './')
    matches = info(path_or_url).match(/^URL: (.+)/)
    matches && matches[1]
  end

  # :todo: needs some serious unit-testing love
  def self.base_url(path_or_url = './')
    matches = info(path_or_url).match(/^Repository Root: (.+)/)
    matches && matches[1]

     # It appears that we might need to use this old way (which looks at 'URL'), since there is actually a handy property called "Repository Root" that we can look at.
#    base_url = nil    # needed so that base_url variable isn't local to loop block (and reset during next iteration)!
#    started_using_dot_dots = false
#    loop do
#      matches = /^URL: (.+)/.match(info(path_or_url))
#      if matches && matches[1]
#        base_url = matches[1]
#      else
#        break base_url
#      end
#
#      # Keep going up the path, one directory at a time, until `svn info` no longer returns a URL (will probably eventually return 'svn: PROPFIND request failed')
#      if path_or_url.include?('/') && !started_using_dot_dots
#        path_or_url = File.dirname(path_or_url)
#      else
#        started_using_dot_dots = true
#        path_or_url = File.join(path_or_url, '..')
#      end
#      #puts 'going up to ' + path_or_url
#    end
  end
  def self.root_url(*args);        base_url(*args); end
  def self.repository_root(*args); base_url(*args); end

  
  def self.repository_uuid(path_or_url = './')
    matches = info(path_or_url).match(/^Repository UUID: (.+)/)
    matches && matches[1]
  end

  # By default, if you query a directory that is scheduled for addition but hasn't been committed yet (node doesn't have a UUID),
  # then we will still return true, because it is *scheduled* to be under version control. If you want a stricter definition,
  # and only want it to return true if the file exists in the *repository* (has a UUID)@ then pass strict = true
  def self.under_version_control?(file = './', strict = false)
    if strict
      !!repository_uuid(file)
    else # (scheduled_for_addition_counts_as_true)
      !!url(file)
    end
  end
  def self.working_copy_root(directory = './')
    uuid = repository_uuid(directory)
    return nil if uuid.nil?

    loop do
      # Keep going up, one level at a time, ...
      new_directory = File.expand_path(File.join(directory, '..'))
      new_uuid = repository_uuid(new_directory)

      # Until we get back a uuid that is nil (it's not a working copy at all) or different (you can have a working copy A inside of a different WC B)...
      break if new_uuid.nil? or new_uuid != uuid

      directory = new_directory
    end
    directory
  end

  # The location of the executable to be used
  # to do: Is there a smarter/faster way to do this? (Could cache this result in .subwrap or somewhere, so we don't have to do all this work on every invocation...)
  def self.executable
    # FileUtils.which('svn') would return our Ruby *wrapper* script for svn. We actually want to return here the binary/executable that we are
    # *wrapping* so we have to use whereis and then use the first one that is ''not'' a Ruby script.
    @@executable ||=
      FileUtils.whereis('svn') do |executable|
        if !self.ruby_script?(executable)               # We want to wrap the svn binary provided by Subversion, not our custom replacement for that.
          return windows_platform? ? %{"#{executable}"} : executable
        end
      end
    raise 'svn binary not found'
  end

  def self.ruby_script?(file_path)
    if windows_platform?
      # The 'file' command, we assume, is not available
      File.readlines(file_path)[0] =~ /ruby/
    else
      `file #{file_path}` =~ /ruby/
    end
  end

protected
  def self.execute(*args)
    options = args.last.is_a?(Hash) ? args.pop : {}
    method = options.delete(:method) || :capture

    command = "#{executable} #{args.join ' '}"
    actually_execute(method, command)
  end
  # This abstraction exists to assist with unit tests. Test cases can simply override this function so that no external commands need to be executed.
  def self.actually_execute(method, command)
    if Subversion.dry_run && !$ignore_dry_run_option
      puts "In execute(). Was about to execute this command via method :#{method}:"
      p command
    end
    if Subversion.print_commands
      #puts '{print'
      p command
      #puts '}print'
    end

    valid_options = [:capture, :exec, :popen]
    case method

      when :capture
        `#{command} 2>&1` 

      when :exec
        #Kernel.exec *args
        Kernel.exec command

      when :system
        Kernel.system command

      when :popen
        # This is just an idea of how maybe we could improve the LATENCY. Rather than waiting until the command completes
        # (which can take quite a while for svn status sometimes since it has to walk the entire directory tree), why not process
        # the output from /usr/bin/svn *in real-time*??
        #
        # Unfortunately, it looks like /usr/bin/svn itself might make that impossible. It seems that if it detects that its output is
        # being redirected to a pipe, it will not yield any output until the command is finished!
        #
        # So even though this command gives you output in real-time:
        #   find / | grep .
        # as does this:
        #   IO.popen('find /', 'r') {|p| line = ""; ( puts line; $stdout.flush ) until !(line = p.gets) }
        # as does this:
        #   /usr/bin/svn st
        #
        # ... as soon as you redirect svn to a *pipe*, it seems to automatically (annoyingly) buffer its output until it's finished:
        #   /usr/bin/svn st | grep .
        # So when I tried this: 
        #   IO.popen('/usr/bin/svn st', 'r') {|p| line = ""; ( puts line; $stdout.flush ) until !(line = p.gets) }
        # it didn't seem any more responsive than a plain puts `/usr/bin/svn st` ! Frustrating!
        #
        IO.popen(command, 'r') do |pipe|
          line = ""
          ( puts line; $stdout.flush ) until !(line = pipe.gets)
        end
      else
        raise ArgumentError.new(":method option must be one of #{valid_options.inspect}")
    end unless (Subversion.dry_run && !$ignore_dry_run_option)
  end
end









#-----------------------------------------------------------------------------------------------------------------------------
module Subversion
  RevisionProperty = Struct.new(:name, :value)

  # Represents an "externals container", which is a directory that has the <tt>svn:externals</tt> property set to something useful.
  # Each ExternalsContainer contains a set of "entries", which are the actual directories listed in the <tt>svn:externals</tt>
  # property and are "pulled into" the directory.
  class ExternalsContainer
    ExternalItem = Struct.new(:name, :repository_path)
    attr_reader :container_dir
    attr_reader :entries

    def initialize(external_dir)
      @container_dir = File.expand_path(external_dir)
      @entries = Subversion.get_property("externals", @container_dir)
      #p @entries
    end

    def has_entries?
      @entries.size > 0
    end

    def entries_structs
      entries.chomp.to_enum(:each_line).map { |line|
        line =~ /^(\S+)\s*(\S+)/
        ExternalItem.new($1, $2)
      }
    end

    def to_s
      entries_structs = entries_structs()
      longest_item_name = 
        [
          entries_structs.map { |entry|
            entry.name.size
          }.max.to_i,
          25
        ].max
      
      container_dir.bold + "\n" +
        entries_structs.map { |entry|
          "  * " + entry.name.ljust(longest_item_name + 1) + entry.repository_path + "\n"
        }.join
    end

    def ==(other)
      self.container_dir == other.container_dir
    end
  end

  # A collection of Diff objects in in file_name => diff format.
  class Diffs < Hash
  end

  class Diff
    attr_reader :filename, :diff
    initializer :filename do
      @diff = ''
    end
    def filename_pretty
      filename.ljust(100).black_on_white
    end
  end

  class DiffsParser
    class ParseError < Exception; end
    initializer :raw_diffs
    @state = nil
    def parse
      diffs = Diffs.new
      current_diff = nil
      @raw_diffs.each_line do |line|
        if line =~ /^Index: (.*)$/
          current_diff = Diff.new($1)
          diffs[current_diff.filename] = current_diff #unless current_diff.nil?
          @state = :immediately_after_filename
          next
        end

        if current_diff.nil?
          raise ParseError.new("The raw diff input didn't begin with 'Index:'!")
        end

        if @state == :immediately_after_filename
          if line =~ /^===================================================================$/ ||
             line =~ /^---.*\(revision \d+\)$/ ||
             line =~ /^\+\+\+.*\(revision \d+\)$/ ||
             line =~ /^@@ .* @@$/
            # Skip
            next
          else
            @state= :inside_the_actual_diff
          end
        end

        if @state == :inside_the_actual_diff
          current_diff.diff << line
        else
          raise ParseError.new("Expected to be in :inside_the_actual_diff state, but was not.")
        end
      end
      diffs.freeze
      diffs
    end
  end

end
end
