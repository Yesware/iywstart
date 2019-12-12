# Class that represents a single Repo's run config. You can merge other
# commands/setup steps into it and it will ensure duplicate commands are not
# run. Additionally this will keep track of the running commands and their
# processes.
class RepoRunConfig
  attr_reader :repo, :flags, :replacements, :setup, :setup_test, :commands, :skip_setup

  # @param repo [String] Name of the repository
  # @param flags [Hash] Additional option flags
  # @option flags test [Boolean] Run the commands in test mode? (default false)
  # @option flags smart_update [Boolean] Should we update and setup smartly? (default false)
  # @param replacements [Hash] Placeholders to be replaced with specified values
  # @param setup [Array<String>] Array of setup commands to run
  # @param setup_test [Array<String>] Array of setup commands to run for test
  #   environment
  # @param commands [Array<String>] Array of runtime commands to run
  def initialize(repo, flags, replacements, setup, setup_test, commands)
    @repo = repo
    @flags = flags
    @replacements = replacements
    @setup = build_commands(setup, test?, replacements)
    @setup_test = build_commands(setup_test, test?, replacements)
    @commands = build_commands(commands, test?, replacements)

    set_skip_setup!
  end

  # Merge the commands from another node for this repo with this repo. Only keep
  # commands that are unique.
  def merge!(other_repo_run_config)
    @setup.concat(other_repo_run_config.setup).uniq!
    @setup_test.concat(other_repo_run_config.setup_test).uniq!
    @commands.concat(other_repo_run_config.commands).uniq!
  end

  # Number each command so we can easily navigate through them.
  # @param starting_number [Integer] Starting number for first Command.
  # @return [Integer] The next number after we've numbered our Commands.
  def number_commands(starting_number)
    @commands.each do |command|
      command.number = starting_number
      starting_number = starting_number + 1
    end
    starting_number
  end

  # Checkout/clone the repository.
  def clone_or_update
    if File.directory?(repo)
      if skip_setup
        info "Smart update says #{repo} is good to go, skipping update and setup".bold.green
      else
        info "Updating clone of #{repo}...".bold.green
        system_with_exit "cd #{repo} && git pull"
      end
    else
      info "Cloning #{repo}...".bold.green
      system_with_exit "git clone git@github-yesware:Yesware/#{repo}.git"
    end
  end

  # Run bundle install
  def bundle_install
    unless skip_setup
      if Helpers.ruby_repo?(repo)
        info "Running bundle install for #{repo}...".bold.green
        # Install the version of Bundler referenced in the repo's lockfile.
        # Defaults to 1.15.2 if one can't be found.
        bundler_version = `grep -A 1 \"BUNDLED WITH\" #{repo}/Gemfile.lock | tail -n 1`.strip
        bundler_version = bundler_version.empty? ? '1.15.2' : bundler_version
        system_with_exit "rvm in #{repo} do gem install bundler -v #{bundler_version} -N"
        system_with_exit "rvm in #{repo} do bundle _#{bundler_version}_ install"
      end
    end
  end

  # Create the log directory and touch the two log files whose output we like to
  # tail. This helps ensure the tail command doesn't die right away.
  def setup_for_log_tailing
    info "Setting up log tailing logfiles for #{repo}...".bold.green
    system_with_exit "mkdir -p #{repo}/log"
    system_with_exit "touch #{repo}/log/development.log"
    system_with_exit "touch #{repo}/log/test.log"
  end

  # Run through each of the setup commands. This assumes you've cd'd into the
  # checkout directory (parent of the repo itself).
  def run_setup_commands
    unless skip_setup
      info
      info "Running setup list for #{repo}".bold.green
      info
      (test? ? setup_test : setup).each do |command|
        debug("Running setup cmd for #{repo}: #{command.executable}")
        wrapped_command = if Helpers.ruby_repo?(repo)
                            "rvm in #{repo} do #{command.executable}"
                          else
                            "cd #{repo}; #{command.executable}"
                          end
        system_with_exit wrapped_command
      end
    end
  end

  # Kick off each of the Commands.
  def kickoff_commands
    info
    info "Kicking off commands for #{repo}".bold.green
    info
    commands.each(&:spawn)
  end

  def command_with_replacements(command, replacements)
    str = command
    replacements.each do |k, v|
      str.gsub!('$' + k, v)
    end
    str
  end

  def build_commands(commands, test, replacements)
    (commands || []).map do |command|
      Command.new(repo, command_with_replacements(command, replacements), test)
    end
  end
  private :build_commands

  def test?
    !!@flags[:test]
  end
  private :test?

  def smart_update?
    !!@flags[:smart_update]
  end
  private :smart_update?

  # Determine if we should we skip setup of this repo.  We do this if smart
  # update is enabled and the repo doesn't need updating - either it's on master
  # and up to date with the remote, or not on master (i.e. under development and
  # assumed to be managed manually).  when the repo was previously updated.
  def set_skip_setup!
    @skip_setup = smart_update? &&
                  File.directory?(repo) &&
                  (`git -C #{repo} status | head -1`.chomp != 'On branch master' ||
                   `git -C #{repo} fetch --dry-run 2>&1`.empty?)
  end
  private :set_skip_setup!

  # Helps subtraction of two arrays of RepoRunConfig work correctly. Subtraction happens when
  # adding a new node to avoid relaunching an existing command.
  def eql?(other_config)
    repo == other_config.repo
  end
end
