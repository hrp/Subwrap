# Tested by: ../../test/subversion_extensions_test.rb

gem 'colored'
require 'colored'

require 'facets/class_extension'
#require 'facets/class_extend'
#require '/var/lib/gems/1.8/gems/xfacets-1.8.54/lib/facets/core/module/class_extension.rb'

require 'subwrap/svn_command'

# :todo: move to quality_extensions
class Array
  def to_regexp_char_class
    "[#{join('')}]"
  end
end

class String
  def colorize_svn_question_mark; self.yellow.bold; end
  def colorize_svn_add;           self.green.bold; end
  def colorize_svn_modified;      self.cyan.bold; end
  def colorize_svn_updated;       self.yellow.bold; end
  def colorize_svn_deleted;       self.magenta.bold; end
  def colorize_svn_conflict;      self.red.bold; end
  def colorize_svn_tilde;         self.red.bold; end
  def colorize_svn_exclamation;   self.red.bold; end

  def colorize_svn_status_code
    if Subversion.color
      self.gsub('?') { $&.colorize_svn_question_mark }.
           gsub('A') { $&.colorize_svn_add }.
           gsub('M') { $&.colorize_svn_modified }.
           gsub('D') { $&.colorize_svn_deleted }.
           gsub('C') { $&.colorize_svn_conflict }.
           gsub('~') { $&.colorize_svn_tilde }.
           gsub('!') { $&.colorize_svn_exclamation }
    else
      self
    end
  end
  def colorize_svn_status_lines
    if Subversion.color
      self.gsub(/^ *([^ ])\s/) { $&.colorize_svn_status_code }
    else
      self
    end
  end
  def colorize_svn_update_lines
    if Subversion.color
      self.gsub(/^ *U\s/)  { $&.colorize_svn_updated }.
           gsub(/^ *A\s/)  { $&.colorize_svn_add }.
           gsub(/^ *M\s/)  { $&.colorize_svn_modified }.
           gsub(/^ *D\s/)  { $&.colorize_svn_deleted }.
           gsub(/^ *C\s/)  { $&.colorize_svn_conflict }
    else
      self
    end
  end
  def colorize_svn_diff
    if Subversion.color
      self.gsub(/^(Index: )(.*)$/) { $2.ljust(100).black_on_white}.   #
           gsub(/^=+\n/, '')                                          # Get rid of the boring ========= lines
    else
      self
    end
  end
end


# These are methods used by the SvnCommand for filtering and whatever else it needs...
# It could probably be moved into SvnCommand, but I thought it might be good to at least make it *possible* to use them apart from SvnCommand.
# Rename to Subversion::Filters ? Then each_unadded would be an odd man out.
module Subversion
  module Extensions
    Interesting_status_flags = ["M", "A", "D", "?"]
    Uninteresting_status_flags = ["X", "W"]
    Status_flags = Interesting_status_flags | Uninteresting_status_flags

    class_extension do  # These are actually class methods, but we have to do it this way so that the Subversion.extend(Subversion::Extensions) will also add these class methods to Subversion.

      def status_lines_filter(input, options)
        uninteresting_status_flags = []
        if options[:only_statuses].nonempty?
          uninteresting_status_flags = Interesting_status_flags - options[:only_statuses]
        end
        uninteresting_status_flags += Uninteresting_status_flags

        input = (input || "").reject { |line|
          line =~ /^$/    # Blank lines
        }.reject { |line|
          line =~ /^ ?#{uninteresting_status_flags.to_regexp_char_class}/
        }.join

        #-------------------------------------------------------------------------------------------
        before_externals, *externals = input.split(/^Performing status on external item at.*$/)

        before_externals ||= ''
        if before_externals != ""
          if options[:files_only]
            before_externals = before_externals.strip.
              gsub(/^ ?#{Status_flags.to_regexp_char_class}..... /, '') \
              + "\n" 
          else
            before_externals = before_externals.strip.colorize_svn_status_lines + "\n" 
          end
        end

        externals = externals.join.strip
        if externals != ""
          externals = 
            '_'*40 + ' externals '.underline + '_'*40 + "\n" +
            externals.reject { |line|
              line =~ /^Performing status on external item at/
            }.reject { |line|
              line =~ /^$/    # Blank lines
            }.join.strip.colorize_svn_status_lines + "\n" 
        end
          
        before_externals +
               externals
      end

      def update_lines_filter(input)
        input.reject { |line|
          line =~ /^$/    # Blank lines
        }.reject { |line|
          line =~ /^Fetching external item into/
          # Eventually we may want it to include this whole block, but only iff there is something updated for this external.
        }.reject { |line|
          line =~ /^External at revision/
        }.join.colorize_svn_update_lines
        # Also get rid of all but one "At revision _."?
      end

      def unadded_lines_filter(input)
        input.select { |line|
          line =~ /^\?/
        }.join
      end
      def unadded_filter(input)
        unadded_lines_filter(input).map { |line|
          # Just keep the filename part
          line =~ /^\?\s+(.+)/
          $1
        }
      end

      def each_unadded(input)
        unadded_filter(input).each { |line|
          yield line
        }
      end

      # This is just a wrapper for Subversion::diff that adds some color
      def colorized_diff(*args)
        Subversion::diff(*args).colorize_svn_diff.add_exit_code_error
      end

      # A wrapper for Subversion::revision_properties that formats it for display on srceen
      def printable_revision_properties(rev)
        Subversion::revision_properties(rev).map do |property|
          "#{property.name.ljust(20)} = '#{property.value}'"
        end.join("\n")
      end

    end # class_extension

  end # module Extensions
end # module Subversion
