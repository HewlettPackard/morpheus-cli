#require 'morpheus/cli' #todo: remove circular require...
require 'morpheus/benchmarking'
require 'morpheus/logging'
require 'morpheus/rest_client'
require 'morpheus/cli/cli_registry'
require 'morpheus/cli/dot_file'
require 'morpheus/cli/error_handler'
require 'morpheus/cli/expression_parser'
require 'morpheus/cli/option_parser'
require 'morpheus/cli/version'
require 'term/ansicolor'

module Morpheus
  
  # Terminal is a class for executing morpheus commands
  # The default IO is STDIN, STDOUT, STDERR
  # The default home directory is $HOME/.morpheus
  #
  # ==== Example Usage
  #
  #    require 'morpheus/terminal'
  #
  #    # Write output to STDOUT is the default behavior
  #
  #    terminal = Morpheus::Terminal.new
  #    exit_code, err = terminal.execute("instances list -m 10")
  #    assert exit_code == 0
  #    assert err == nil
  #
  #    # Write command output to a file instead
  #    terminal = Morpheus::Terminal.new(stdout: File.new("morpheus-terminal.log", "w+"))
  #    terminal.execute("version")
  #    terminal.execute("instances list")
  #    terminal.execute("apps list")
  #
  #    # Overwrite file with output of a command
  #    terminal = Morpheus::Terminal.new(stdout: File.new("instance23.json", "w"))
  #    terminal.execute("instances get 23 --json")
  #    puts "Instance 23 Details: ", File.read("instance23.json")
  #
  class Terminal
    include Morpheus::Benchmarking::HasBenchmarking
    # todo: this can be combined with Cli::Shell

    class Blackhole # < File

      def initialize(*args)
        # we shouldn't actually need a File tho.. but Readline wants one
        # File.open(Morpheus::Cli.windows? ? 'NUL:' : '/dev/null', 'w')
      end

      def accrete_data(*mgs)
        # Singularity.push(*msgs)
        return nil
      end
      alias :print :accrete_data
      alias :puts :accrete_data
      alias :'<<' :accrete_data
      alias :write :accrete_data
      alias :write :accrete_data
      # alias :gets :do_nothing
    end

    # DEFAULT_TERMINAL_WIDTH = 80

    def self.default_color
      Term::ANSIColor.cyan
    end

    def self.prompt
      if !defined?(@prompt) || @prompt.nil?
        if ENV['MORPHEUS_PS1']
          @prompt = ENV['MORPHEUS_PS1'].dup
        else
          #ENV['MORPHEUS_PS1'] = "#{Term::ANSIColor.cyan}morpheus>#{Term::ANSIColor.reset} "
          @prompt = "#{Term::ANSIColor.cyan}morpheus>#{Term::ANSIColor.reset} "
        end
      end
      @prompt
    end

    def self.prompt=(v)
      @prompt = v
    end

    def self.angry_prompt
      "#{Term::ANSIColor.red}morpheus:#{Term::ANSIColor.reset} "
    end

    def self.custom_prompt
      #export MORPHEUS_PS1='\[\e[1;32m\]\u@\h:\w${text}$\[\e[m\] '
    end

    # def self.benchmarking=(v)
    #   @benchmarking = !!v
    # end

    # the global Morpheus::Terminal instance
    # This should go away, but it needed for now...
    def self.instance
      @morphterm ||= self.new({})
    end

    # hack alert! This should go away, but is needed for now...
    def self.new(*args)
      obj = super(*args)
      @morphterm = obj
      obj
    end

    attr_accessor :prompt #, :angry_prompt
    attr_accessor :benchmarking
    attr_reader :stdin, :stdout, :stderr, :home_directory


    # Create a new instance of Morpheus::Terminal
    # @param stdin  [IO] Default is STDIN
    # @param stdout [IO] Default is STDOUT
    # @param stderr [IO] Default is STDERR
    # @param [IO] stderr
    # @stderr = stderr
    def initialize(stdin=$stdin,stdout=$stdout, stderr=$stderr, homedir=nil)
      attrs = {}
      if stdin.is_a?(Hash)
        attrs = stdin.clone()
        stdin = attrs[:stdin] || $stdin
        stdout = attrs[:stdout] || $stdout
        stderr = attrs[:stderr] || $stderr
        homedir = attrs[:homedir] || attrs[:home] || attrs[:home_directory]
      end
      # establish IO
      # @stdin, @stdout, @stderr = stdin, stdout, stderr
      set_stdin(stdin)
      set_stdout(stdout)
      set_stderr(stderr)
      
      # establish home directory
      use_homedir = homedir || ENV['MORPHEUS_CLI_HOME'] || File.join(Dir.home, ".morpheus")
      set_home_directory(use_homedir)
      
      # use colors by default
      set_coloring($stdout.isatty) #rescue nil
      # Term::ANSIColor::coloring = STDOUT.isatty
      # @coloring = Term::ANSIColor::coloring?

      # startup script
      if File.exist? Morpheus::Cli::DotFile.morpheus_profile_filename
        @profile_dot_file = Morpheus::Cli::DotFile.new(Morpheus::Cli::DotFile.morpheus_profile_filename)
      else
        @profile_dot_file = nil
      end
      
      # the string to prompt for input with
      @prompt ||= Morpheus::Terminal.prompt
      @angry_prompt ||= Morpheus::Terminal.angry_prompt
    end

    def to_s
      "<##{self.class}:#{self.object_id.to_s(8)} @stdin=#{@stdin} @stdout=#{@base_url} @stderr=#{@stderr} @home=#{@home_directory} @prompt=#{@prompt} >"
    end

    def inspect
      to_s
    end

    # execute .morpheus_profile startup script
    def execute_profile_script(rerun=false)
      if @profile_dot_file
        if rerun || !@profile_dot_file_has_run
          @profile_dot_file_has_run = true
          return @profile_dot_file.execute() # todo: pass io in here
        else
          return false # already run
        end
      else
        return nil
      end
    end

    def set_stdin(io)
      # if io.nil? || io == 'blackhole' || io == '/dev/null'
      #   @stdout = Morpheus::Terminal::Blackhole.new
      # else
      #   @stdout = io
      # end
      @stdin = io
    end

    def set_stdout(io)
      if io.nil? || io == 'blackhole' || io == '/dev/null'
        @stdout = Morpheus::Terminal::Blackhole.new
      else
        @stdout = io
      end
      @stdout
    end

    def set_stderr(io)
      if io.nil? || io == 'blackhole' || io == '/dev/null'
        @stderr = Morpheus::Terminal::Blackhole.new
      else
        @stderr = io
      end
      @stderr
    end

    def with_pipes(opts, &block)
      originals = {} #{stdout: stdout, stderr: stderr, stdin: stdin}
      if opts[:stdout]
        originals[:stdout] = stdout
        set_stdout(opts[:stdout])
      end
      if opts[:stderr]
        originals[:stderr] = stderr
        set_stderr(opts[:stderr])
      end
      if opts[:stdin]
        originals[:stdin] = stdin
        set_stdin(opts[:stdin])
      end
      begin
        yield
      ensure
        set_stdout(originals[:stdout]) if originals[:stdout]
        set_stderr(originals[:stderr]) if originals[:stderr]
        set_stdin(originals[:stdin]) if originals[:stdin]
      end
    end

    def with_stdout(io, &block)
      with_pipes(stdout:io, &block)
    end

    def with_stderr(io, &block)
      with_pipes(stderr:io, &block)
    end

    def with_stdout_and_stderr(io, &block)
      with_pipes(stdout:io, stderr:io, &block)
    end

    def with_stdin(io, &block)
      with_pipes(stdin:io, &block)
    end

    def home_directory=(homedir)
      set_home_directory(homedir)
    end

    def set_home_directory(homedir)
      full_homedir = File.expand_path(homedir)
      # if !Dir.exist?(full_homedir)
      #   print_red_alert "Directory not found: #{full_homedir}"
      #   exit 1
      # end
      @home_directory = full_homedir
      
      # todo: deprecate this
      Morpheus::Cli.home_directory = full_homedir

      @home_directory
    end

    # def coloring=(v)
    #   set_coloring(enabled)
    # end

    def set_coloring(enabled)
      @coloring = !!enabled
      Term::ANSIColor::coloring = @coloring
      coloring?
    end

    def coloring?
      @coloring == true
    end

    # alias :'coloring=' :set_coloring

    def usage
      out = "Usage: morpheus [command] [options]\n"
      # just for printing help. todo: start using this. maybe in class Cli::MainCommand
      # maybe OptionParser's recover() instance method will do the trick
      optparse = Morpheus::Cli::OptionParser.new do|opts|
        opts.banner = "Options:" # hack alert
        opts.on('-e','--exec EXPRESSION', "Execute the command(s) expression. This is an alternative to passing [command] [options]") do |val|
          @execute_mode = true
          @execute_mode_command = val
        end
        opts.on('--noprofile','--noprofile', "Do not read and execute the personal initialization script .morpheus_profile") do
          @noprofile = true
        end
        # todo: make these work
        # opts.on('--home','--home', "Morpheus client home directory, where configuration files are located. The default is MORPHEUS_CLI_HOME or HOME/.morpheus") do |val|
        #   @use_home_directory = val
        #   set_home_directory(@use_home_directory)
        #   # that it? all done...
        # end
        # opts.on('-Z','--temporary', "Temporary shell. Use a temporary shell with the current remote configuration, credentials and commands loaded. Configuration changes and command history will not be saved.") do
        #   @noprofile = true
        #   @temporary_shell_mode = true
        # end
        # opts.on('-z','--clean', "Clean shell. Use a temporary shell without any remote configuration, credentials or command history loaded.") do
        #   @noprofile = true
        #   @temporary_shell_mode = true
        #   @clean_shell_mode = true
        # end
        opts.on('-C','--nocolor', "Disable ANSI coloring") do
          @coloring = false
          Term::ANSIColor::coloring = false
        end
        opts.on('-B','--benchmark', "Print benchmark time after the command is finished.") do
          @benchmarking = true
          #Morpheus::Benchmarking.enabled = true
        end
        opts.on('-V','--debug', "Print extra output for debugging.") do |json|
          @terminal_log_level = Morpheus::Logging::Logger::DEBUG
          Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
          # if !options[:quiet]
          ::RestClient.log = Morpheus::Logging.debug? ? Morpheus::Logging::DarkPrinter.instance : nil
        end
        opts.on('-v','--version', "Print the version.") do
          @stdout.puts Morpheus::Cli::VERSION
          # exit
        end
        opts.on( '-h', '--help', "Print this help" ) do
          @stdout.puts opts
          # exit
        end
      end
      out << "Commands:\n"
      sorted_commands = Morpheus::Cli::CliRegistry.all.values.sort { |x,y| x.command_name.to_s <=> y.command_name.to_s }
      sorted_commands.each {|cmd|
        # JD: not ready to show description yet, gotta finish filling in every command first
        # maybe change 'View and manage' to something more concise like 'Manage'
        # out << "\t#{cmd.command_name.to_s.ljust(28, ' ')} #{cmd.command_description}\n"
        out << "\t#{cmd.command_name.to_s}\n"
      }
      # out << "Options:\n"
      out << optparse.to_s
      out << "\n"
      out << "For more information, see https://clidocs.morpheusdata.com"
      out << "\n"
      out
    end

    def prompt
      @prompt # ||= Morpheus::Terminal.default_prompt
    end

    def prompt=(str)
      @prompt = str
    end

    def angry_prompt
      @angry_prompt ||= Morpheus::Terminal.angry_prompt
    end

# protected

    def execute(input)
      exit_code = 0
      err = nil
      args = nil
      if input.is_a? String
        args = Shellwords.shellsplit(input)
      elsif input.is_a?(Array)
        args = input.dup
      else
        raise "terminal execute() expects a String to be split or an Array of String arguments and instead got (#{args.class}) #{args}"
      end

      # include Term::ANSIColor # tempting

      # short circuit version switch
      if args.length == 1
        if args[0] == '-v' || args[0] == '--version'
          @stdout.puts Morpheus::Cli::VERSION
          return 0, nil
        end
      end

      # looking for global help?
      if args.length == 1
        if args[0] == '-h' || args[0] == '--help' || args[0] == 'help'
          @stdout.puts usage
          return 0, nil
        end
      end
      
      # process global options

      # raise log level right away
      if args.find {|it| it == '-V' || it == '--debug'}
        @terminal_log_level = Morpheus::Logging::Logger::DEBUG
        Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
        ::RestClient.log = Morpheus::Logging.debug? ? Morpheus::Logging::DarkPrinter.instance : nil
      end

      # start benchmark right away?
      # if args.find {|it| it == '-B' || it == '--benchmark'}
      #   #start_benchmark(args.join(' '))
      #   @benchmarking = true
      # end

      # ok, execute the command (or alias)
      result = nil
      begin
        
        # todo: no, this needs to be supported as --home for every darn command..
        # add it to CliCommand build_common_options()
        # use custom home directory from --home
        # todo: this should happen in initialize..
        # @use_home_directory
        # need to get index, and delete both the switch and the arg after it
        homedir = false
        home_switch_index = args.index {|it| it == '--home' }
        if args.find {|it| it == '--home' }
          deleted_option = args.delete_at(home_switch_index)
          home_dir = args.delete_at(home_switch_index)
          @use_home_directory = home_dir
          #puts "Setting home directory to #{@use_home_directory}"
          set_home_directory(@use_home_directory)
          # re-initialize some variables
          # startup script
          if File.exist? Morpheus::Cli::DotFile.morpheus_profile_filename
            @profile_dot_file = Morpheus::Cli::DotFile.new(Morpheus::Cli::DotFile.morpheus_profile_filename)
          else
            @profile_dot_file = nil
          end
        end

        # execute startup script .morpheus_profile  unless --noprofile is passed
        # todo: this should happen in initialize..
        noprofile = false
        if args.find {|it| it == '--noprofile' }
          noprofile = true
          args.delete_if {|it| it == '--noprofile' }
        end

        
        if @profile_dot_file && !@profile_dot_file_has_run
          if !noprofile && File.exist?(@profile_dot_file.filename)
            execute_profile_script()
          end
        end

        # execute startup script .morpheus_profile  unless --noprofile is passed
        # todo: this should happen in initialize..
        @execute_mode = false
        @execute_mode_command = nil
        args.size.times do |i|
          if args[i] == '-e' || args[i] == '--exec'
            @execute_mode = true
            # delete switch and value (command)
            deleted_option = args.delete_at(i)
            @execute_mode_command = args.delete_at(i)
            if @execute_mode_command.nil?
              raise ::OptionParser::MissingArgument.new(deleted_option)
              #@stderr.puts "#{@angry_prompt}missing argument: #{deleted_option}."
              #@stderr.puts "No command given, here's some help:"
              #@stderr.print usage
              return 1
            end
            break
          end
        end

        if @execute_mode_command
          # execute a single command and exit
          result = Morpheus::Cli::CliRegistry.exec_expression(@execute_mode_command)
          @execute_mode_command = nil
        else
          # not enough arguments?
          if args.count == 0
            @stderr.puts "#{@angry_prompt}[command] argument is required."
            #@stderr.puts "No command given, here's some help:"
            @stderr.print usage
            return 1, nil # CommandError.new("morpheus requires a command")
          end
          
          cmd_name, *cmd_args = args

          formatted_cmd = args.collect {|arg| arg.include?(' ') ? "\"#{arg}\"" : "#{arg}" }.join(" ")

          # unknown command?
          # all commands should be registered commands or aliases
          # ahh, but it could support expressions (), use -e for that ..
          # if !(Morpheus::Cli::CliRegistry.has_command?(cmd_name) || Morpheus::Cli::CliRegistry.has_alias?(cmd_name))
          #   @stderr.puts "#{@angry_prompt}'#{cmd_name}' is not recognized"
          #   #@stderr.puts usage
          #   return 127, nil
          # end

          if (defined?(@benchmarking) && @benchmarking) || args.include?('-B') || args.include?('--benchmark')
            benchmark_name = "morpheus #{formatted_cmd}"
            benchmark_name.sub!(' -B', '')
            benchmark_name.sub!(' --benchmark', '')
            #benchmark_name << " -B"
            start_benchmark(benchmark_name)
          end
          # shell is a Singleton command class
          if args[0] == "shell"
            require 'morpheus/cli/commands/shell'
            result = Morpheus::Cli::Shell.instance.handle(args[1..-1])
          else
            #result = Morpheus::Cli::CliRegistry.exec_expression(formatted_cmd)
            result = Morpheus::Cli::CliRegistry.exec(args[0], args[1..-1])
          end
        end
        exit_code, err = Morpheus::Cli::CliRegistry.parse_command_result(result)
      rescue => e
        exit_code, err = Morpheus::Cli::ErrorHandler.new(@stderr).handle_error(e)
      ensure
        # should always try to stop it
        # if @benchmarking
          benchmark_record = stop_benchmark(exit_code, err)
          Morpheus::Logging::DarkPrinter.puts(Term::ANSIColor.cyan + Term::ANSIColor.dark + benchmark_record.msg) if benchmark_record
        # end
      end

      return exit_code, err

    end

  end
end

