# Class to multiplex output from a launched run_config. Supports silencing of
# the output so other output can take over the terminal output.
class Multiplexer
  attr_reader :run_config, :silence
  attr_accessor :filter_regex

  def initialize(run_config, log_file = nil)
    @silence = false
    @run_config = run_config
    if log_file
      silence!
      @write_to = File.open(log_file, 'a+')
    end
  end

  def silence!
    @silence = true
  end

  def unsilence!
    @silence = false
  end

  def toggle!
    @silence = !@silence
  end

  def start
    @thread = Thread.new do
      begin
        # Multiplex output into single terminal window
        while true do
          num_read = run_config.map do |config|
            stdouts = config.commands.select do |command|
              command.alive?
            end.map(&:stdout)
            ready = IO.select(stdouts, nil, nil, 0)
            readable = ready && ready[0]
            next 0 if !readable

            readable.each do |r|
              begin
                if line = r.gets
                  output = "[#{config.repo}] - #{line}"

                  next if filter_regex && !(output =~ filter_regex)

                  puts output unless silence
                  if @write_to
                    @write_to.write(output)
                    @write_to.flush
                  end
                end
              rescue ArgumentError => ex
                puts "regex filter error: #{ex.inspect}. Log: #{output}"
              rescue Errno::EIO
                # ignore Errno::EIO: Input/output error @ io_fillbuf
              end
            end
            # return how many items were read
            readable.length
          end
          # If we read something do not sleep. If nothing was ready to be read,
          # give the CPU a breather.
          sum = num_read.inject(0, :+)
          sleep($multiplexer_sleep_time) if sum == 0
        end
      rescue => e
        puts "Failure on Multiplexer thread: #{e.inspect}, #{e.backtrace}"
      end
    end
  end

  def stop
    @thread.exit
  end
  private :stop

  def restart_with(run_config)
    stop
    @run_config = run_config
    start
  end
end
