require 'morpheus/cli/cli_command'

class Morpheus::Cli::BenchmarkCommand
  include Morpheus::Cli::CliCommand
  set_command_name :'benchmark'

  register_subcommand :on, "Enable global benchmarking."
  register_subcommand :off, "Disable global benchmarking."
  register_subcommand :on?, "Print the value of the global benchmark setting. Exit 0 if on."
  register_subcommand :off?, "Print the value of the global benchmark setting. Exit 0 if off."
  register_subcommand :start, "Start recording a benchmark."
  register_subcommand :stop, "Stop recording a benchmark."
  register_subcommand :status, "Print status of benchmark."
  register_subcommand :exec, :execute, "Benchmark a specified command or expression."

  # this would be cool, we should store all benchmarking results in memory or on disk =o
  # register_subcommands :list, :get, :put, :remove

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    # no connection needed
  end

  def handle(args)
    handle_subcommand(args)
  end

  def on(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("")
      build_common_options(opts, options, [:quiet])
      opts.footer = <<-EOT
#{subcommand_description}
This behaves the same as if you were to add the -B switch to every command.
EOT
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got #{args.count} #{args.join(' ')}\n#{optparse}"
      return 1
    end
    benchmark_was_enabled = Morpheus::Benchmarking.enabled
    Morpheus::Benchmarking.enabled = true
    my_terminal.benchmarking = Morpheus::Benchmarking.enabled
    unless options[:quiet]
      # if benchmark_was_enabled == false
      #   Morpheus::Logging::DarkPrinter.puts "benchmark enabled" if Morpheus::Logging.debug?
      # end
      puts "#{cyan}benchmark: #{green}on#{reset}"
    end
    return 0 
  end

  def off(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("")
      build_common_options(opts, options, [:quiet])
      opts.footer = <<-EOT
#{subcommand_description}
The default state for this setting is off.
EOT
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got #{args.count} #{args.join(' ')}\n#{optparse}"
      return 1
    end
    benchmark_was_enabled = Morpheus::Benchmarking.enabled
    Morpheus::Benchmarking.enabled = false
    my_terminal.benchmarking = Morpheus::Benchmarking.enabled
    unless options[:quiet]
      # if benchmark_was_enabled == true
      #   Morpheus::Logging::DarkPrinter.puts "benchmark disabled" if Morpheus::Logging.debug?
      # end
      puts "#{cyan}benchmark: #{dark}off#{reset}"
    end
    return 0 
  end

  def on?(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("")
      build_common_options(opts, options, [:quiet])
      opts.footer = <<-EOT
#{subcommand_description}
Exit 0 if on.
EOT
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got #{args.count} #{args.join(' ')}\n#{optparse}"
      return 1
    end
    if Morpheus::Benchmarking.enabled?
      puts "#{cyan}benchmark: #{green}on#{reset}" unless options[:quiet]
    else
      puts "#{cyan}benchmark: #{dark}off#{reset}" unless options[:quiet]
    end
    return Morpheus::Benchmarking.enabled? ? 0 : 1
  end

  def off?(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("")
      build_common_options(opts, options, [:quiet])
      opts.footer = <<-EOT
#{subcommand_description}
Exit 0 if off.
EOT
    end
    optparse.parse!(args)
    connect(options)
    if args.count != 0
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got #{args.count} #{args.join(' ')}\n#{optparse}"
      return 1
    end
    unless options[:quiet]
      if Morpheus::Benchmarking.enabled?
        puts "#{cyan}benchmark: #{green}on#{reset}"
      else
        puts "#{cyan}benchmark: #{dark}off#{reset}"
      end
    end
    return Morpheus::Benchmarking.enabled? ? 1 : 0
  end

  def start(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:quiet])
      opts.footer = <<-EOT
#{subcommand_description}
[name] is required. This is just a name for the routine.
This allows you to record how long it takes to run a series of commands.
Just run `benchmark stop` when you are finished.
EOT
    end
    optparse.parse!(args)
    connect(options)
    # if args.count < 1
    #   print_error Morpheus::Terminal.angry_prompt
    #   puts_error  "wrong number of arguments, expected 1-N and got #{args.count} #{args.join(' ')}\n#{optparse}"
    #   return 1
    # end
    benchmark_name = nil
    if !args.empty?
      benchmark_name = args.join(' ')
    end
    benchmark_record = Morpheus::Benchmarking.start(benchmark_name)
    unless options[:quiet]
      if benchmark_record.name
        print_green_success "Started benchmark '#{benchmark_record.name}'"
      else
        print_green_success "Started benchmark"
      end
    end
    # record this record so it can be stopped later without knowing (or remembering) the name

    return 0 
  end

  def stop(args)
    options = {}
    params = {}
    benchmark_exit_code = nil
    benchmark_err = nil
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      opts.on('--exit CODE', String, "Exit code to end benchmark with. Default is 0 to indicate success.") do |val| # default should my_terminal.last_exit_code
        benchmark_exit_code = val.to_i
      end
      opts.on('--error ERROR', String, "Error message to include with a benchmark that failed.") do |val|
        benchmark_err = val
      end
      build_common_options(opts, options, [:quiet])
      opts.footer = <<-EOT
#{subcommand_description}
[name] is optional. This is the name of the benchmark to stop. 
The last benchmark is used by default.
EOT
    end
    optparse.parse!(args)
    connect(options)
    # if args.count < 1
    #   print_error Morpheus::Terminal.angry_prompt
    #   puts_error  "wrong number of arguments, expected 1-N and got #{args.count} #{args.join(' ')}\n#{optparse}"
    #   return 1
    # end
    # benchmark_name = args.join(' ')
    # benchmark_record = Morpheus::Benchmarking.stop(benchmark_name)

    benchmark_name = nil
    benchmark_record = nil
    if args.empty?
      # stop the last one..
      benchmark_record = Morpheus::Benchmarking.last
      if benchmark_record.nil?
        print_error red,"Benchmark not found",reset,"\n"
        return 1
      end
    else
      benchmark_name = args.join(' ')
      benchmark_record = Morpheus::Benchmarking.lookup(benchmark_name)
      if benchmark_record.nil?
        print_error red,"Benchmark not found by name '#{benchmark_name}'",reset,"\n"
        return 1
      end
    end
    if benchmark_record.start_time == nil || benchmark_record.end_time != nil
      if benchmark_record.name
        print_error red,"Benchmark '#{benchmark_record.name}' is not running",reset,"\n"
      else
        print_error red,"Benchmark is not running",reset,"\n"
      end
      return 1
    end
    benchmark_record.stop(benchmark_exit_code || 0, benchmark_err)
    unless options[:quiet]
      if benchmark_record.name
        print_green_success "Stopped benchmark '#{benchmark_record.name}'"
      else
        print_green_success "Stopped benchmark"
      end
    end
    # always print benchmark info
    Morpheus::Logging::DarkPrinter.puts(cyan + dark + benchmark_record.msg)
    return 0 
  end

  def status(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      build_common_options(opts, options, [:quiet])
      opts.footer = <<-EOT
#{subcommand_description}
[name] is optional. This is the name of the benchmark to inspect.
The last benchmark is used by default.
EOT
    end
    optparse.parse!(args)
    connect(options)
    # if args.count < 1
    #   print_error Morpheus::Terminal.angry_prompt
    #   puts_error  "wrong number of arguments, expected 1-N and got #{args.count} #{args.join(' ')}\n#{optparse}"
    #   return 1
    # end
    # benchmark_name = args.join(' ')
    # benchmark_record = Morpheus::Benchmarking.stop(benchmark_name)

    benchmark_name = nil
    benchmark_record = nil
    if args.empty?
      # stop the last one..
      benchmark_record = Morpheus::Benchmarking.last
      if benchmark_record.nil?
        print_error red,"No benchmark is running",reset,"\n"
        return 1
      end
    else
      benchmark_name = args.join(' ')
      benchmark_record = Morpheus::Benchmarking.lookup(benchmark_name)
      if benchmark_record.nil?
        print_error red,"Benchmark not found by name '#{benchmark_name}'",reset,"\n"
        return 1
      end
    end
    
    unless options[:quiet]
      Morpheus::Logging::DarkPrinter.puts(cyan + dark + benchmark_record.msg)
    end
    return 0 
  end

  def execute(args)
    n = 1
    benchmark_name = nil
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[command...]")
      opts.on('-n', '--iterations NUMBER', Integer, "Number of iterations to run. The default is 1.") do |val|
        if val.to_i > 1
          n = val.to_i
        end
      end
      opts.on('--name NAME', String, "Name for the benchmark. Default is the command itself.") do |val|
        benchmark_name = val
      end
      build_common_options(opts, options, [:quiet])
      opts.footer = <<-EOT
#{subcommand_description}
[command] is required. This is the command to execute
EOT
    end
    optparse.parse!(args)
    connect(options)
    if args.count < 1
      print_error Morpheus::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 1-N and got #{args.count} #{args.join(' ')}\n#{optparse}"
      return 1
    end
    
    exit_code = 0
    out = ""

    original_stdout = nil
    begin
      # --quiet actually unhooks stdout for this command
      if options[:quiet]
        original_stdout = my_terminal.stdout
        my_terminal.set_stdout(Morpheus::Terminal::Blackhole.new)
      end
    
      cmd = args.join(' ')
      benchmark_name ||= cmd

    
      if n == 1
        start_benchmark(benchmark_name)
        # exit_code, err = my_terminal.execute(cmd)
        cmd_result = Morpheus::Cli::CliRegistry.exec_expression(cmd)
        exit_code, err = Morpheus::Cli::CliRegistry.parse_command_result(cmd_result)
        benchmark_record = stop_benchmark(exit_code, err)
        # Morpheus::Logging::DarkPrinter.puts(cyan + dark + benchmark_record.msg) if benchmark_record
        # return 0
        if original_stdout
          my_terminal.set_stdout(original_stdout)
          original_stdout = nil
        end
        out = ""
        # <benchmark name or command>
        out << "#{benchmark_name.ljust(30, ' ')}"
        # exit: 0
        exit_code = benchmark_record.exit_code
        if benchmark_record.exit_code && benchmark_record.exit_code != 0
          out << "\texit: #{benchmark_record.exit_code.to_s.ljust(2, ' ')}"
          out << "\terror: #{benchmark_record.error.to_s.ljust(12, ' ')}"
        else
          out << "\texit: 0 "
        end
        total_time_str = "#{benchmark_record.duration.round((benchmark_record.duration > 0.002) ? 3 : 6)} s"
        out << "\t #{total_time_str.ljust(9, ' ')}"
      else
        benchmark_records = []
        n.times do |iteration_index|
          start_benchmark(benchmark_name)
          # exit_code, err = my_terminal.execute(cmd)
          cmd_result = Morpheus::Cli::CliRegistry.exec_expression(cmd)
          exit_code, err = Morpheus::Cli::CliRegistry.parse_command_result(cmd_result)
          benchmark_record = stop_benchmark(exit_code, err)
          Morpheus::Logging::DarkPrinter.puts(cyan + dark + benchmark_record.msg) if Morpheus::Logging.debug?
          benchmark_records << benchmark_record
        end
        if original_stdout
          my_terminal.set_stdout(original_stdout)
          original_stdout = nil
        end
        # calc total and mean and print it
        # all_durations = benchmark_records.collect {|benchmark_record| benchmark_record.duration }
        # total_duration = all_durations.inject(0.0) {|acc, i| acc + i }
        # avg_duration = total_duration / all_durations.size
        # total_time_str = "#{total_duration.round((total_duration > 0.002) ? 3 : 6)} s"
        # avg_time_str = "#{avg_duration.round((total_duration > 0.002) ? 3 : 6)} s"

        all_durations = []
        stats = {total: 0, avg: nil, min: nil, max: nil}
        benchmark_records.each do |benchmark_record| 
          duration = benchmark_record.duration
          if duration
            all_durations << duration
            stats[:total] += duration
            if stats[:min].nil? || stats[:min] > duration
              stats[:min] = duration
            end
            if stats[:max].nil? || stats[:max] < duration
              stats[:max] = duration
            end
          end
        end
        if all_durations.size > 0
          stats[:avg] = stats[:total].to_f / all_durations.size
        end

        total_time_str = "#{stats[:total].round((stats[:total] > 0.002) ? 3 : 6)} s"
        min_time_str = stats[:min] ? "#{stats[:min].round((stats[:min] > 0.002) ? 3 : 6)} s" : ""
        max_time_str = stats[:max] ? "#{stats[:max].round((stats[:max] > 0.002) ? 3 : 6)} s" : ""
        avg_time_str = stats[:avg] ? "#{stats[:avg].round((stats[:avg] > 0.002) ? 3 : 6)} s" : ""

        out = ""
        # <benchmark name or command>
        out << "#{benchmark_name.ljust(30, ' ')}"
        # exit: 0
        bad_benchmark = benchmark_records.find {|benchmark_record| benchmark_record.exit_code && benchmark_record.exit_code != 0 }
        if bad_benchmark
          exit_code = bad_benchmark.exit_code.to_i
          out << "\texit: #{bad_benchmark.exit_code.to_s.ljust(2, ' ')}"
          out << "\terror: #{bad_benchmark.error.to_s.ljust(12, ' ')}"
        else
          out << "\texit: 0 "
        end

        out << "\tn: #{n.to_s.ljust(4, ' ')}"
        out << "\ttotal: #{total_time_str.ljust(9, ' ')}"
        out << "\tmin: #{min_time_str.ljust(9, ' ')}"
        out << "\tmax: #{max_time_str.ljust(9, ' ')}"
        out << "\tavg: #{avg_time_str.ljust(9, ' ')}"


        # if bad_benchmark
        #   print_error red,out,reset,"\n"
        #   return 1
        # else
        #   print cyan,out,reset,"\n"
        #   return 0
        # end
      end
      if exit_code == 0
        print cyan,out,reset,"\n"
        return 0
      else
        print_error red,out,reset,"\n"
        return exit_code
      end
    rescue => ex
      raise ex
      #raise_command_error "benchmark exec failed with error: #{ex}"
      #puts_error "benchmark exec failed with error: #{ex}"
      #return 1
    ensure
      if original_stdout
        my_terminal.set_stdout(original_stdout)
        original_stdout = nil
      end
    end
  end

end
