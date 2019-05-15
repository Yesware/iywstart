# Represents a single command to be launched within a repository. This is used
# to represent both forked commands (long running) as well as setup commands
# that we run once and wait for them.
class Command
  attr_reader :repo, :command, :test, :process
  attr_accessor :number

  def initialize(repo, command, test)
    @repo = repo
    @command = command
    @test = test
  end

  def hash
    command.hash
  end

  def ==(other)
    other.respond_to?(:command) && other.command == command
  end
  alias_method :eql?, :==

  def prepared_command
    @prepared_command ||= command.start_with?('rake ') ? "bundle exec #{command}" : command
  end
  private :prepared_command

  # What is the executable we should run.
  def executable
    if test
      if prepared_command.include?('rails s')
        "#{prepared_command} -e test"
      else
        "env RAILS_ENV=test RACK_ENV=test #{prepared_command}"
      end
    else
      command
    end
  end

  def spawn
    info "Repo (#{repo}) Command: #{executable}"
    # An alternative to supporting logging silencing, would be to run the output through awk to
    # preface all lines with the repo:
    # <cmd> | awk '{print "[#{repo}] - $0"; fflush(); }
    wrapped_command = if Helpers.ruby_repo?(repo)
                        "rvm in #{repo} do #{executable}"
                      else
                        "cd #{repo}; #{executable}"
                      end
    stdout, stdin, pid = PTY.spawn(wrapped_command)
    debug "PID: #{pid}"
    @process = YwProc.new(stdin, stdout, pid)
  end

  def stop
    debug("Repo(#{repo}), killing process trees for #{process.pid}")
    terminate_processes([process.pid])
  end

  def restart
    stop
    spawn
  end

  def alive?
    is_alive?(process.pid)
  end

  def stdout
    process.stdout
  end
end
