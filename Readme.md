# <i>Subwrap</i> -- an enhanced +svn+ command

* **Home page**: <http://subwrap.rubyforge.org/>
* **Project site**: <http://rubyforge.org/projects/subwrap>
* **Suggestions?**: <http://subwrap.uservoice.com>
* **Gem install**: `gem install subwrap`
* **Author**: Tyler Rick (<http://tylerrick.com>)
* **Copyright**: 2007 QualitySmith, Inc.
* **License**: [GNU General Public License](http://www.gnu.org/copyleft/gpl.html)

## What is it? 

This is a replacement **svn command-line client** meant to be used instead of the standard `svn` command. (Actually, it's a *wrapper*, not a strict replacement, because it still uses `/usr/bin/svn` to do all the dirty work.)

## Who is it for?

Anyone who feels like the standard svn command is missing some features and wants a slightly more powerful command-line svn tool...

Anyone who wants to hack/extend the svn command but is afraid to/too lazy to mess with the actual C source code...

## Installation

### Dependencies

* colored
* escape
* facets
* extensions
* quality_extensions
* rscm
* termios (recommended, but no longer required)
* win32console (Windows only, required for colored to work)

### Installation

* Install the gem (once per system_:

`sudo gem install subwrap --include-dependencies`

Tjijjihe command will now be available immediately by typing `subwrap` instead of `svn`. 

If you'd like to actually *replace* the standard `svn` command (that
is, if you'd like to be able to run it simply by typing `svn`), then you you will also need to run `sudo _subwrap_post_install`, which will
attempt to do the following (or you can do this manually):

(Linux only) Make the svn wrapper command *executable*:

`sudo chmod a+x /usr/lib/ruby/gems/1.8/gems/subwrap*/bin/*`

(Why can't we just set `executables = "svn"` in the gemspec and have it automatically install it to `/usr/bin`? Because that would cause it to **wipe out** the existing executable at `/usr/bin/svn`! If you know of a better, more automatic solution to this, please let me know!)

* (Linux only:) Next, you need to add the gem's +bin+ directory to be added to the **<i>front</i>** of your path (once per _user_). You may run `_subwrap_post_install` and let it attempt to do this for you, or you can do it manually:


* Add a `PATH=` command to your `~/.bash_profile` (or equivalent). For example:

    export PATH=`ls -dt --color=never /usr/lib/ruby/gems/1.8/gems/subwrap* | head -n1`/bin:$PATH"

  (You will need to source your `~/.bash_profile` after modifying it in order for bash to detect the new path to the svn command.)

* (Windows only:) Make sure `C:\ruby\bin` (or wherever rubygems installs executables for gems) appears in the path before
  `C:\Program Files\Subversion\bin` (or wherever your svn binary is).

  _subwrap_post_install will copy 'c:/ruby/bin/subwrap.cmd' to 'c:/ruby/bin/svn.cmd' so that when you type svn from the command line, it will actually
  run `c:/ruby/bin/svn.cmd`.
 
### Check to see if it's working

You'll know it's working by way of two signs:
* Your `svn` command will be noticeably slower
* When you type svn `help`, it will say:
    You are using subwrap, a replacement/wrapper for the standard svn command.

## Features

#### Changes to existing subcommands:

* **`svn diff`**
   output is in _color_ (requires `colordiff`, see below)
   `svn diff` includes the differences from your *externals* too (consistent with how `svn status` includes them) so that you don't forget to commit those changes too! (pass `--ignore-externals` if you _don't_ want a diff of externals)
* **`svn status`**
   filters out distracting, useless output about externals (don't worry -- it still shows which files were _modified_)
   the flags (?, M, C, etc.) are in *color*!
* **`svn move`** it will let you move multiple source files to a destination directory with a single command

(* You can pass --no-color to disable colors for a single command...useful if you want to pipe the output to another command or something. Eventually maybe we could make this a per-user option via .subwrap?)

#### New subcommands:

* **`svn each_unadded`** (`eu`, `unadded`) -- goes through each unadded (`?`) file reported by `svn status` and asks you what to do with them (add, delete, ignore).

* **`svn revisions`** -- lists all revisions with log messages and lets you browse through them interactively
* **`svn externals`** -- lists all externals
* **`svn edit_externals`** (`ee`)
* **`svn externalize`**
* **`svn set_message`** / `svn get_message` / `svn edit_message` -- shortcuts for accessing `--revprop svn:log`
* **`svn ignore`** -- shortcut for accessing `svn:ignore` property
* **`svn view_commits`** -- gives you output from both `svn log` and from `svn diff` for the given changesets (useful for code reviews)
* **`svn url`** -- prints out the URL of the given working copy path or the curretn working copy
* **`svn repository_root`** -- prints out the root repository URL of the working copy you are in
* **`svn delete_svn`** -- causes the current directory (recursively) to no longer be a working copy

(RDoc question: how do I make the identifiers like Subversion::SvnCommand#externalize into links??)

# Usage / Examples

## `svn each_unadded`

This command is useful for keeping your working copies clean -- getting rid of all those accumulated temp files (or *ignoring* or *adding* them if they're something that _all_ users of this repository should be aware of).

It simply goes through each "unadded" file (each file reporting a status of `?`) reported by `svn status` and asks you what you want to do with them -- *add*, *delete*, or *ignore*.

  > svn each_unadded

  What do you want to do with plugins/database_log4r/doc?
    (shows preview)
  (a)dd, (d)elete, add to svn:(i)ignore property, or [Enter] to do nothing > i
  Ignoring...

  What do you want to do with applications/underlord/db/schema.rb?
    (shows preview)
  (a)dd, (d)elete, add to svn:(i)ignore property, or [Enter] to do nothing > a
  Adding...

  What do you want to do with applications/underlord/vendor/plugins/exception_notification?
    (shows preview)
  (a)dd, (d)elete, add to svn:(i)ignore property, or [Enter] to do nothing > d
  Are you pretty much *SURE* you want to 'rm -rf applications/underlord/vendor/plugins/exception_notification'? (y)es, (n)o > y
  Deleting...

For *files*, it will show a preview of the _contents_ of that file (limited to the first 55 lines); for *directories*, it will show a _directory_ _listing_. By looking at the preview, you should hopefully be able to decide whether you want to _keep_ the file or _junk_ it.

## `svn whats_new` (replacement for `svn update`)

Whereas `svn update` <i>only</i> updates (merges) with the latest changes and shows you which files were updated/etc., `svn whats_new`:
* updates (merges) with the latest changes
* shows you a summary of which files were updated/added/removed/conflict (:todo:)
* shows the commit messages for each change_set [since you last ran this command :todo:]
* shows the actual changes (diffs) that were made for every file in the 

It's a lot like `svn browse` (and in fact shares most of the same code with it), except it's <i>non-interactive</i>, so you just run it and then sit back and watch all the pretty output -- which is a good thing, because doing a diff for each changeset can take a long time...

Tip: When actively working on a project with lots of frequent committers, I like to keep a separate tab open in my terminal where I periodicaly run `svn whats_new`:
* to grab the latest changes from everyone else on the team, and 
* to skim through their changes to see what's changed.

## `svn browse` (revisions browser)

Lets you interactively browse through all revisions of a file/directory/repository (one at a time). For each revision, it will ask you what you want to do with it (view the changeset, edit revision properties, etc.).

Screenshot:
link:include/svn_revisions.png

It's sort of like `svn log | less`, only it's interactive, it's in color, and it's just plain more useful!

You can step through the revisions using the arrow keys or Enter. 

Here are a couple things you might use it for:
* **View the history of a certain file**.
  * Rather than looking at `svn log -v` (which can be _huge_) directly and then manually calculating revision numbers and doing things like `svn diff -r1492:1493` over and over, you can simply start up `svn revisions`, browse to the revision you're interested in using the Up/Down arrow keys, and press D to get a diff for the selected changeset.
* **See what's been committed since the last public release**. So that you can list it in your release notes, for example...
* **Review other people's code**. (There's even a mark-as-reviewed feature*, if you want to keep track of which revisions have been reviewed...)
* **Search for a change you know you've _made_** but just don't remember what revision it was in. (Hint: Use the "grep this changeset" feature.)
* Figure out what the **difference is between two branches**.

Defaults to latest-first, but you can pass it the `--forwards` flag to browse from the other direction (start at the <i>oldest revision</i> and step forwards through time).

(*The mark-as-reviewed feature requires the modification of your repository's pre-revprop-change hook.)

## `svn status`

_Without_ this gem installed (really long):

  ?      gemables/subversion/ruby_subversion.rb
   M     gemables/subversion
  M      gemables/subversion/lib/subversion.rb
  A      gemables/subversion/bin
  A      gemables/subversion/bin/svn
  X      plugins/database_log4r/tasks/shared
  X      plugins/surveys/doc/template
  X      plugins/surveys/tasks/shared
  X      gemables/dev_scripts/tasks/shared
  X      gemables/dev_scripts/lib/subversion

  Performing status on external item at 'plugins/database_log4r/tasks/shared'

  Performing status on external item at 'plugins/surveys/tasks/shared'

  Performing status on external item at 'gemables/subversion/doc_include/template'

  Performing status on external item at 'gemables/dev_scripts/tasks/shared'

  Performing status on external item at 'applications/underlord/vendor/plugins/rails_smith'
  X      applications/underlord/vendor/plugins/rails_smith/tasks/shared
  X      applications/underlord/vendor/plugins/rails_smith/lib/subversion
  X      applications/underlord/vendor/plugins/rails_smith/doc_include/template

  Performing status on external item at 'applications/underlord/vendor/plugins/rails_smith/tasks/shared'
  M      applications/underlord/vendor/plugins/rails_smith/tasks/shared/base.rake

**_With_** this gem installed (_much_ shorter and sweeter):

  ?      gemables/subversion/ruby_subversion.rb
   M     gemables/subversion
  M      gemables/subversion/lib/subversion.rb
  A      gemables/subversion/bin
  A      gemables/subversion/bin/svn
  M      applications/underlord/vendor/plugins/rails_smith/tasks/shared/base.rake

##`svn externalize` / `externals` / `edit_externals`

Shortcut for creating an svn:external...

  your_project/vendor/ > svn externalize http://code.qualitysmith.com/gemables/subwrap --as svn

Between that and externals / edit_externals, that's all you ever really need! (?)

  > svn externals
  /home/tyler/code/plugins/rails_smith/tasks
    * shared                        http://code.qualitysmith.com/gemables/shared_tasks/tasks
  /home/tyler/code/plugins/rails_smith/doc_include
    * template                      http://code.qualitysmith.com/gemables/template/doc/template
  /home/tyler/code/plugins/rails_smith
    * subwrap                   http://code.qualitysmith.com/gemables/subwrap
  
Oops, I externalled it in the wrong place!

  > svn edit_externals
  /home/tyler/code/plugins/rails_smith/tasks
    * shared                        http://code.qualitysmith.com/gemables/shared_tasks/tasks
  Do you want to edit svn:externals for this directory? y/N > [Enter]

  /home/tyler/code/plugins/rails_smith/doc_include
    * template                      http://code.qualitysmith.com/gemables/template/doc/template
  Do you want to edit svn:externals for this directory? y/N > [Enter]

  /home/tyler/code/plugins/rails_smith
    * subwrap                   http://code.qualitysmith.com/gemables/subwrap
  Do you want to edit svn:externals for this directory? y/N > [y]
  (remove that line using your favorite editor (which of course is `vim`), save, quit)

You can also pass a directory name to edit_externals to edit the svn:externals property for that directory:

  > svn edit-externals vendor/plugins

##`svn get_message` / `set_message` / `edit_message`

**Pre-requisite for set_message/edit_message**: Your repository must have a `pre-revprop-change` hook file.

Useful if you made a mistake or forgot something in your commit message and want to edit it... 

For example, maybe you tried to do a multi-line commit message with -m but it didn't interpret your "\n"s as newline characters. Just run svn edit_message and fix it interactively!

  svn get_message -r 2325
is the same as:
  svn propget -r 2325 --revprop svn:log

If you *just* committed it and you want to edit the message for the most-recently committed revision ("head"), there is an even quicker way to do it:

You can do this:
  svn edit_message -r head
or just this:
  svn edit_message

## `svn ignore`

If you want to add '*' to the list of ignored files for a directory, be sure to enclose the argument in single quotes (`'`) so that the shell doesn't expand the `*` symbol for you.

Example:

  svn ignore 'tmp/sessions/*'

## `svn move`

You can now do commands like this:

  svn mv file1 file2 dir
  svn mv dir1/* dir

(The _standard_ `svn` command only accepts a _single_ source and a _single_ destination!)

## `svn commit`

### --skip-notification / --covert

Added a --skip-notification / --covert option which (assuming you have your post-commit hook set up to do this), will suppress the sending out of a commit notification e-mail.

This is useful if you're committing large/binary files that would normally cause the commit mailer to hang. (True, the commit mailer script should really be smart enough not to hang in the first place, but let's assume we don't have the luxury of being able to fix it...)

For this option to have any effect, you will need to set up your repository similar to this:

/var/www/svn/code/hooks/pre-revprop-change

  REPOS="$1"
  REV="$2"
  USER="$3"
  PROPNAME="$4"
  ACTION="$5"

  if [ "$ACTION" = "M" -a "$PROPNAME" = "svn:log" ]; then exit 0; fi
  if [ "$PROPNAME" = "svn:skip_commit_notification_for_next_commit" ]; then exit 0; fi

  echo "Changing revision properties other than those listed in $0 is prohibited" >&2
  exit 1

/var/www/svn/code/hooks/post-commit

  #!/bin/bash

  REPOS="$1"
  REV="$2"

  previous_revision=`expr $REV - 1`
  skip_commit_notification=`svnlook propget $REPOS --revprop svn:skip_commit_notification_for_next_commit -r $previous_revision`

  if [[ $skip_commit_notification == 'true' ]]; then
      # Skipping
  else
      svnnotify \
          --repos-path $REPOS \
          --revision $REV \
          --subject-prefix "[your repository name]" \
          --revision-url 'http://code/?rev=%s' \
          --to code-commit-watchers@yourdomain.com \
          --handler HTML::ColorDiff \
          --subject-cx \
          --with-diff \
          --author-url 'mailto:%s' \
          --footer "Powered by SVN-Notify <http://search.cpan.org/~dwheeler/SVN-Notify-2.62/lib/SVN/Notify.pm>" \
          --max-diff-length 1000
  fi



##Help

You can, of course, get a lits of the custom commands that have been added by using `svn help`. They will be listed at the end.

##Global options

* --no-color (since color is on by default)
* --dry-run  (see what /usr/bin/svn command it _would_ have executed if you weren't just doing a dry run -- useful for debugging if nothing else)
* --print-commands (prints out the /usr/bin/svn commands before executing them)
* --debug    (sets $debug = true)

##Requirement: `colordiff`

`colordiff` is used to colorize `svn diff` commands (+ lines are blue; - lines are red)

Found at:
* http://www.pjhyett.com/articles/2006/06/16/colored-svn-diff
* http://colordiff.sourceforge.net/

Suggestion: change the colors in `/etc/colordiffrc` to be more readable:
  plain=white
  newtext=green
  oldtext=red
  diffstuff=cyan
  cvsstuff=magenta

##A workaround for the `Commit failed; Your file or directory 'some file' is probably out-of-date` problem##

  svn: Commit failed (details follow):
  svn: Your file or directory 'some file' is probably out-of-date
  svn: The version resource does not correspond to the resource within the transaction.  Either the requested version resource is out of date (needs to be updated), or the requested version resource is newer than the transaction root (restart the commit).
  Sending        some file
  (Doesn't actually finish the commit)

I'm still not sure what causes it (I didn't think I was doing anything _that_ out of the ordinary...) or how to _prevent_ it, because it keep happening to me (maybe I'm the only one?)... but I've at least automated the "fix" for this state somewhat.

The only way I've found to resolve this problem is to delete the entire directory and restore it (with svn update).

It must have something to do with something in the .svn directories not matching up the way that svn expects.

Anyway, the `svn fix_out_of_date_commit_state` command attempts to automate most of that process for you.


##Bash command completion

If you want command completion for the svn subcommands (and I don't blame you if you don't -- the default command completion is <i>much faster</i> and already gives you completion for filenames!), just add this line to your `~/.bashrc` :

  complete -C /usr/bin/command_completion_for_subwrap -o default svn

It's really rudimentary right now and could be much improved, but at least it's a start.

##Support for code reviews, commit notification, and continuous integration systems

The `svn revisions` command lets you browse through recent changes to a project or directory and then, for each revision that you review, you can simply press R and it will mark that revision as reviewed.

`svn commit` accepts two custom flags, `--skip-notification / --covert` (don't send commit notification) and `--broken` (tell the continuous integration system to expect failure).

#Other

##Known problems

It doesn't support options that are given in this format:
  --diff-cmd=colordiff
only this format:
  --diff-cmd colordiff
This is a limitation of Console::Command.

Fix: Show the whole thing, including this line:
  Fetching external item into 'glass/rails_backend/vendor/plugins/our_extensions'


This doesn't work:
  svn propget svn:skip_commit_notification_for_next_commit --revprop -r 2498 http://code.qualitysmith.com/ --dry-run
  In execute(). Was about to execute this command via method :exec:
  "/usr/bin/svn propget --revprop -r 2498 http://code.qualitysmith.com/ svn:skip_commit_notification_for_next_commit"

  > svn propget svn:skip_commit_notification_for_next_commit --revprop -r 2498 http://code.qualitysmith.com/
  svn: Either a URL or versioned item is required

Have to do:
  svn propget svn:skip_commit_notification_for_next_commit http://code.qualitysmith.com/applications/profiler_test --revprop -r 2498

or
  > /usr/bin/svn propget svn:skip_commit_notification_for_next_commit --revprop -r 2498 http://code.qualitysmith.com/


### Slowness

Is it slower than just running /usr/bin/svn directly? You betcha it is!

  > time svn foo
  real    0m0.493s

  > time /usr/bin/svn foo
  real    0m0.019s

But... as with most things written in Ruby, it's all more about *productivity* than raw execution speed. _Hopefully_ the productivity gains you get from using this wrapper will more than make up for the 0.5 s extra you have to wait for the svn command. :-) If not, I guess it's not for you.

##To do

Drop dependency on colordiff and use a native ruby colorizer that works on top of standard diff output. That may be necessary to support following change:

Make it do these by default:
  -x [--extensions] arg    : Default: '-u'. When Subversion is invoking an
                             external diff program, ARG is simply passed along
                             to the program. But when Subversion is using its
                             default internal diff implementation, or when
                             Subversion is displaying blame annotations, ARG
                             could be any of the following:
                                -b (--ignore-space-change):
                                   Ignore changes in the amount of white space.
                                -w (--ignore-all-space):
                                   Ignore all white space.
                                --ignore-eol-style:
                                   Ignore changes in EOL style

Calling "Extensions.anything" is stupid. Can't we just merge/extend/include the methods from Extensions into the Subversion module itself?

Say you just did `svn mv base-suffix base-new_suffix`. Now say you want to commit that move without committing anything else in that dir.
You'd think you could just do `svn ci base-*`, but no. That doesn't get base-suffix because it has been removed from the file system (and scheduled for deletion).
Can we make it so a '*' (or any glob) (escaped so shell doesn't get it) actually looks at all files returned by `svn st` (which includes those scheduled for deletion, D) that match that glob rather than all files, rather than the glob that the *shell* would do?

Say you cp'd a file A to B. You make some modifications to it and later decide to add it. Wouldn't it be nice if you could retroactively cause B to inherit the ancestry of A (as if you had svn cp'd it instead of cp'd it to begin with)?
I propose a copy_ancestry_from / imbue_with_ancestry_from command, so that you can do svn copy_ancestry_from B A that does just that.
Then you could also svn rm A and it would be (I think) completely equivalent to having done an svn mv A B in the first place.

svn list_conflicts instead of:
svn st --no-color | grep "^C"

Take the best ideas from these and incorporate:
* /usr/lib/ruby/gems/1.8/gems/rscm-0.5.1/lib/rscm/scm/subversion.rb
* /usr/lib/ruby/gems/1.8/gems/lazysvn-0.1.3/lib/subversion.rb

Possibly switch to LazySvn.

After you save/edit/set an svn:externals, it should try to automatically pretty up the margins/alignment for you.

/usr/lib/ruby/gems/1.8/gems/piston-1.3.3/lib/piston/commands/import.rb has interesting way of parsing output from `svn info`
        my_info = YAML::load(svn(:info, File.join(dir, '..')))
        my_revision = YAML::load(svn(:info, my_info['URL']))['Revision']

Get everything that was on http://wiki.qualitysmith.com/subwrap

###Ideas from TortoiseSvn

When you drag and drop one or more files to a WC directory, it prompts you with a context menu with these options:
* svn move versioned files here
* svn copy versioned files here
* svn copy and rename versioned files here
* svn add files to this WC
* svn export to here
* svn export all to here

###Name ideas

Word ideas to possibly incorporate:
* improved
* enhanced
* wrapper
* color
* plus
* more

* 'subwrap'? Short for "Subversion wrapper". Also, a play on the words sub and wrap -- both of which are also food items.

##Contact me!

If you have any comments, suggestions, or patches, I would love to hear them! You'd be surprised how open I am to considering small or even massive changes to this project.
