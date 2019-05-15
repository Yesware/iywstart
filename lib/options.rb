def options
  @options
end

def load_options
  @options = OpenStruct.new
  options.yml_file = File.join(File.dirname(__FILE__), '..', 'ywstart.yml')
  options.run_nodes = []
  options.git_update = true
  options.bundle_install = true
  options.log_to_file = false
  options.except = []
  options.replacements = {}
  options.no_self_update = false
  options.setup_for_log_tailing = true
  options.run_setup_commands = true
  options.smart_update = false
  options.parallelize_setup = false

  OptionParser.new do |opts|
    opts.banner = <<-EOS
      Usage: ywstart [options] where options are specified below.
      ywstart is used to start up multiple jobs out of multiple repositories with the
      goal of getting a running system ready for use (or testing against) without
      having to maintain multiple console windows or remembering which commands need
      to be run out of each.

      Given a list of repositories and commands to run within each, it will ensure
      those repositories are checked out (or update them if they exist), run any
      pre-run commands in them (db:migrate, etc), and then launch and background any
      number of commands out of each repository. All standard out will be interleaved
      into the single console window and will be prefixed by the name of the
      repository where the output came from.

      Options:
    EOS

    opts.on('-v', '--[no-]verbose', 'Run verbosely') do |v|
      $debug = true
    end

    opts.on('--config-file CONFIG_FILE', 'Override default config yml file') do |v|
      options.yml_file = v
    end

    opts.on('-n', '--node NODE',
            'Node to run') do |v|
      options.run_nodes << v
    end

    opts.on('-g', '--no-git', 'Skip git commands for repo') do
      options.git_update = false
    end

    opts.on('-b', '--no-bundler', 'Skip bundler update for repo') do
      options.bundle_install = false
    end

    opts.on('-l', '--log-to-file', 'Redirect command output to a file (ywstart.log)') do
      options.log_to_file = true
    end

    opts.on('-t', '--test', 'Run with RAILS_ENV/RACK_ENV=test') do
      options.test = true
    end

    opts.on('-x', '--except REPO', 'Repo will not be started') do |v|
      options.except << v
    end

    opts.on('-r', '--replace PLACEHOLDER=VALUE', 'Use VALUE for $PLACEHOLDER when running commands') do |replacement|
      (k, v) = replacement.split('=', 2)
      options.replacements[k] = v
    end

    opts.on('-s', '--no-self-update', 'Will not pull latest version of yw-tools, including iywstart itself') do
      options.no_self_update = true
    end

    opts.on(nil, '--non-interactive', 'Run in non-interactive mode (for CI enviroments)') do
      options.non_interactive = true
    end

    opts.on(nil, '--skip-log-tailing-setup', 'Skip the setup for log tailing') do
      options.setup_for_log_tailing = false
    end

    opts.on(nil, '--skip-setup-commands', 'Skip running of the setup commands') do
      options.run_setup_commands = false
    end

    opts.on('-f', '--fast-startup', 'Skip all non-required setup steps') do
      options.git_update = false
      options.bundle_install = false
      options.setup_for_log_tailing = false
      options.run_setup_commands = false
      options.no_self_update = true
    end

    opts.on('-u', '--smart-update', 'Try to be smart and update only what is needed') do
      options.smart_update = true
    end

    opts.on('-p', '--parallelize-setup', 'Parallelize setup commands across repos to speed up startup process') do
      options.parallelize_setup = true
    end
  end.parse!

  options.run_nodes << 'default' unless options.run_nodes.any?
  info("Running nodes #{options.run_nodes} out of file #{options.yml_file}".bold.green)
end