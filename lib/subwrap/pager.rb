# http://nex-3.com/posts/73-git-style-automatic-paging-in-ruby

def run_pager
  return if PLATFORM =~ /win32/
  return unless STDOUT.tty?

  read, write = IO.pipe

  unless Kernel.fork # Child process
    STDOUT.reopen(write)
    STDERR.reopen(write) if STDERR.tty?
    read.close
    write.close
    return
  end

  # Parent process, become pager
  STDIN.reopen(read)
  read.close
  write.close

  ENV['LESS'] = 'FSRX' # Don't page if the input is short enough

  Kernel.select [STDIN] # Wait until we have input before we start the pager
  pager = ENV['PAGER'] || 'less'
  exec pager rescue exec "/bin/sh", "-c", pager
end


