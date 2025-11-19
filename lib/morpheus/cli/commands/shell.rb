require 'morpheus/cli/cli_command'
require "shellwords"
require "readline"

#class Morpheus::Cli::Shell < Morpheus::Terminal
class Morpheus::Cli::Shell
  include Morpheus::Cli::CliCommand

  @@instance = nil

  def self.has_instance?
    defined?(@@instance) && @@instance
  end

  def self.instance
    @@instance ||= reload_instance
  end

  def self.reload_instance
    @@instance = self.new
  end

  def self.insecure
    !!(defined?(@@insecure) && @@insecure == true)
  end

  attr_accessor :prompt #, :angry_prompt

  def initialize()
    @@instance = self
    reinitialize()
  end

  def reinitialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
    @current_remote = ::Morpheus::Cli::Remote.load_active_remote()
    if @current_remote
      @appliance_name, @appliance_url = @current_remote[:name], @current_remote[:host]
      # @current_username = @current_remote[:username] || '(anonymous)'
      @current_username = @current_remote[:username] || ''
    else
      @appliance_name, @appliance_url = nil, nil
      @current_username = nil
    end
    #connect()
    #raise "one shell only" if @@instance
    @@instance = self
    recalculate_prompt()
    recalculate_auto_complete_commands()
  end

  # def connect(opts)
  #   @api_client = establish_remote_appliance_connection(opts)
  # end

  def recalculate_prompt()
    # custom prompts.. this is overkill and perhaps a silly thing..
    # Example usage:
    # MORPHEUS_PS1="[%remote] %cyan %username morph> " morpheus shell --debug
    #@prompt = Morpheus::Terminal.instance.prompt.to_s #.dup
    @prompt = my_terminal.prompt

    variable_map = Morpheus::Cli::Echo.variable_map
    # variable_map = {
    #   '%cyan' => cyan, '%magenta' => magenta, '%red' => red, '%mgreen' => green, '%yellow' => yellow, '%dark' => dark, '%reset' => reset,
    #   '%remote' => @appliance_name.to_s, '%remote_url' => @appliance_url.to_s, 
    #   '%username' => @current_username.to_s
    # }
    @calculated_prompt = @prompt.to_s.dup
    variable_map.each do |k, v|
      @calculated_prompt.gsub!(k.to_s, v.to_s)
    end
    # cleanup empty brackets caused by var value
    @calculated_prompt = @calculated_prompt.gsub("[]", "").gsub("<>", "").gsub("{}", "")
    #@calculated_prompt = @calculated_prompt.strip
    # @calculated_prompt = "#{@calculated_prompt}#{reset} "
    @calculated_prompt
  end

  def recalculate_auto_complete_commands
    @morpheus_commands = Morpheus::Cli::CliRegistry.all.keys.reject {|k| [:shell].include?(k) }
    @shell_commands = [:clear, :history, :reload, :help, :exit]
    @shell_command_descriptions = {
      :clear => "Clear terminal output and move cursor to the top", 
      :history => "View morpheus shell command history", 
      :reload => "Reload the shell, can be useful when developing", 
      :help => "Print this help", 
      :exit => "Exit the morpheus shell"
    }
    @alias_commands = Morpheus::Cli::CliRegistry.all_aliases.keys
    @exploded_commands = []
    Morpheus::Cli::CliRegistry.all.each do |cmd, klass|
      @exploded_commands << cmd.to_s
      #subcommands = klass.subcommands rescue []
      subcommands = klass.visible_subcommands rescue []
      subcommands.keys.each do |sub_cmd|
        @exploded_commands << "#{cmd} #{sub_cmd}"
      end
    end
    @auto_complete_commands = (@exploded_commands + @shell_commands + @alias_commands).collect {|it| it.to_s }
    @auto_complete = proc do |s|
      command_list = @auto_complete_commands
      result = command_list.grep(/^#{Regexp.escape(s)}/)
      if result.nil? || result.empty?
        Readline::FILENAME_COMPLETION_PROC.call(s) rescue []
      else
        result
      end
    end
  end

  def handle(args)
    @clean_shell_mode = false
    @execute_mode = false
    @execute_mode_command = nil
    @norc = false
    @temporary_shell_mode = false
    @temporary_home_directory = nil
    @original_home_directory = nil
    usage = "Usage: morpheus #{command_name}"
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = usage
      # change to a temporary home directory, delete it afterwards.
      opts.on('-e','--exec EXPRESSION', "Execute the command expression and exit. Expression can be a single morpheus command or several by using parenthesis and operators (, ), &&, ||, and ;") do |val|
        @execute_mode = true
        @execute_mode_command = val
      end
      opts.on('--norc','--norc', "Do not read and execute the personal initialization script .morpheusrc") do
        @norc = true
      end
      opts.on('-I','--insecure', "Allow for insecure HTTPS communication i.e. bad SSL certificate") do |val|
        @@insecure = true
        Morpheus::RestClient.enable_ssl_verification = false
      end
      opts.on('-Z','--temporary', "Temporary shell. Use a temporary shell with the current remote configuration, credentials and history loaded. Temporary shells do not save changes to remote configuration changes and command history.") do
        @temporary_shell_mode = true
      end
      opts.on('-z','--clean', "Clean shell. Use a temporary shell without any remote configuration, credentials or command history loaded.") do
        @temporary_shell_mode = true
        @clean_shell_mode = true
      end
      opts.on('-C','--nocolor', "Disable ANSI coloring") do
        Term::ANSIColor::coloring = false
      end
      opts.on('-V','--debug', "Print extra output for debugging.") do
        Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
        ::RestClient.log = Morpheus::Logging.debug? ? Morpheus::Logging::DarkPrinter.instance : nil
      end
      opts.on('-B','--benchmark', "Print benchmark time after each command is finished" ) do
        Morpheus::Benchmarking.enabled = true
        my_terminal.benchmarking = Morpheus::Benchmarking.enabled
      end
      opts.on( '-h', '--help', "Print this help" ) do
        puts opts
        exit
      end
    end
    optparse.parse!(args)

    # is this a temporary/temporary_shell shell?
    # this works just by changing the cli home directory and updating appliances
    if @temporary_shell_mode
      #Morpheus::Logging::DarkPrinter.puts "temporary shell started" if Morpheus::Logging.debug?
      # for now, always use the original home directory
      # or else this will just keep growing deeper and deeper.
      @parent_shell_directories ||= []
      @parent_shell_directories << my_terminal.home_directory
      @previous_home_directory = @parent_shell_directories.last
      @original_home_directory ||= @previous_home_directory
      
      #@norc = true # perhaps?
      # instead of using TMPDIR, create tmp shell directory inside $MORPHEUS_CLI_HOME/tmp
      # should chown these files too..
      #tmpdir = ENV['MORPHEUS_CLI_TMPDIR'] || ENV['TMPDIR'] || ENV['TMP']
      tmpdir = ENV['MORPHEUS_CLI_TMPDIR']
      if !tmpdir
        tmpdir = File.join(@original_home_directory, "tmp")
      end
      if !File.exist?(tmpdir)
        # Morpheus::Logging::DarkPrinter.puts "creating tmpdir #{tmpdir}" if Morpheus::Logging.debug?
        FileUtils.mkdir_p(tmpdir)
      end
      # this won't not happen since we mkdir above
      if !File.exist?(tmpdir)
        raise_command_error "Temporary directory not found. Use environment variable MORPHEUS_CLI_TMPDIR"
      end
      # change to a temporary home directory
      @temporary_home_directory = File.join(tmpdir, "tmpshell-#{rand().to_s[2..7]}")
      
      #if !File.exist?(@temporary_home_directory)
        Morpheus::Logging::DarkPrinter.puts "starting temporary shell at #{@temporary_home_directory}" if Morpheus::Logging.debug?
        FileUtils.mkdir_p(@temporary_home_directory)
      # end
      

      my_terminal.set_home_directory(@temporary_home_directory)


      # wow..this already has cached list of Remote.appliances
      # this is kinda nice though..keep it for now, 
      #Morpheus::Cli::Remote.load_appliance_file
      if @clean_shell_mode == true
        # clean shell means no loading of remotes, aliases, history
        # @norc = true
        # todo: avoid writing files here and just work in memory for temporary shell
        Morpheus::Cli::Remote.save_appliances({})
      else
        # keep remotes and credentials and activity or history
        # this is done just by copying configuration files to the tmp home dir
        # 
        # should use Morpheus::Cli::DotFile.morpheus_profile_filename
        # and # should use Morpheus::Cli::DotFile.morpheus_profile_filename
        # this already got run though.. this temporary mode should work for any terminal command,
        # not just in shell
        # .morpheus_profile has aliases
        # this has already been loaded, probably should reload it...
        if File.exist?(File.join(@previous_home_directory, ".morpheus_profile"))
          FileUtils.cp(File.join(@previous_home_directory, ".morpheus_profile"), File.join(@temporary_home_directory, ".morpheus_profile"))
        end
        if @norc != true
          if File.exist?(File.join(@previous_home_directory, ".morpheusrc"))
            FileUtils.cp(File.join(@previous_home_directory, ".morpheusrc"), File.join(@temporary_home_directory, ".morpheusrc"))
          end
        end
        if File.exist?(File.join(@previous_home_directory, "appliances"))
          FileUtils.cp(File.join(@previous_home_directory, "appliances"), File.join(@temporary_home_directory, "appliances"))
        end
        if File.exist?(File.join(@previous_home_directory, "credentials"))
          FileUtils.cp(File.join(@previous_home_directory, "credentials"), File.join(@temporary_home_directory, "credentials"))
        end
        if File.exist?(File.join(@previous_home_directory, "groups"))
          FileUtils.cp(File.join(@previous_home_directory, "groups"), File.join(@temporary_home_directory, "groups"))
        end
        # stay logged in
        # maybe have a different option for removing just credentials, and command history..
        Morpheus::Cli::Remote.appliances.each do |app_name, app|
          #app[:username] = "(anonymous)"
          #app[:status] = "fresh"
          #app[:authenticated] = false
          # app.delete(:active) # keep remote active..
          #app.delete(:username)
          #app.delete(:last_login_at)
          #app.delete(:last_logout_at)
          # app[:last_logout_at] = Time.now.to_i
          # keep last_success and last check
          #app.delete(:last_success_at)
          #app.delete(:last_check)
          #app.delete(:username)
        end

        # Morpheus::Cli::Remote.save_appliances(new_remote_config)
        # Morpheus::Cli::Remote.clear_active_appliance
        # Morpheus::Cli::Credentials.clear_saved_credentials(@appliance_name)
        # Morpheus::Cli::Credentials.load_saved_credentials
        # Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).load_saved_credentials()
      end
    end

    @history_logger ||= load_history_logger rescue nil
    @history_logger.info "shell started" if @history_logger
    load_history_from_log_file()


    # execute startup script
    if !@norc
      if File.exist?(Morpheus::Cli::DotFile.morpheusrc_filename)
        @history_logger.info("load source #{Morpheus::Cli::DotFile.morpheusrc_filename}") if @history_logger
        Morpheus::Cli::DotFile.new(Morpheus::Cli::DotFile.morpheusrc_filename).execute()
      end
    end

    reinitialize()
    # recalculate_prompt()
    # recalculate_auto_complete_commands()

    result = nil
    if @execute_mode_command
      # execute a single command and exit
      result = execute(@execute_mode_command)
    else
      # interactive prompt
      result = 0
      @exit_now_please = false
      while !@exit_now_please do
        #Readline.input = my_terminal.stdin
        #Readline.input = $stdin
        Readline.completion_append_character = " "
        Readline.completion_proc = @auto_complete
        Readline.basic_word_break_characters = ""
        #Readline.basic_word_break_characters = "\t\n\"\‘`@$><=;|&{( "
        input = Readline.readline(@calculated_prompt, true).to_s
        input = input.strip

        result = execute(input)
        print reset
      end
    end
    
    # temporary_shell_mode, cover our tracks
    if @temporary_home_directory
      if @temporary_home_directory.include?("tmpshell")
        begin
          FileUtils.remove_dir(@temporary_home_directory, true)
          Morpheus::Logging::DarkPrinter.puts "cleaning up temporary shell at #{@temporary_home_directory}" if Morpheus::Logging.debug?
        rescue
        end
      end
      parent_shell_directory = @parent_shell_directories ? @parent_shell_directories.pop : nil
      if parent_shell_directory
        # switch terminal shell back to parent shell.  
        # should just be forking instead of all this...
        my_terminal.set_home_directory(parent_shell_directory)
        if @original_home_directory && @original_home_directory == parent_shell_directory
          # back to original shell, not temporary, right? 
          # todo: probably need to reload shell here?
          @temporary_home_directory = nil
        else
          # back to another temporary shell
          # todo: probably need to reload shell here?
          @temporary_home_directory = parent_shell_directory
        end
      else
        # there was no parent, this would be weird since temporary_home_directory was true..
      end
    end
    return result
  end

  # execute the input as an expression. 
  # provides support for operators '(', ')', '&&', '||', ';'
  # logs entire input as one command in shell history
  # logging is skipped for certain commands: exit, !,  !!
  def execute(input)
    unless input.strip.empty? || input.strip[0] == "!"
      log_history_command(input.strip)
    end

    #Morpheus::Logging::DarkPrinter.puts "Shell command: #{input}"
    input = input.to_s.strip

    # allow pasting in commands that have 'morpheus ' prefix
    if input[0..(prog_name.size)] == "#{prog_name} "
      input = input[(prog_name.size + 1)..-1] || ""
    end
    if !input.empty?

      if input == 'exit'
        #print cyan,"Goodbye\n",reset
        #@history_logger.info "exit" if @history_logger
        @exit_now_please = true
        return 0
        #exit 0
      elsif input == 'help'
        out = ""
        if @temporary_shell_mode
          out << "You are in a (temporary) morpheus shell\n"
        else
          out << "You are in a morpheus shell.\n"
        end
        out <<  "See the available commands below.\n"

        out << "\nCommands:\n"
        # commands = @morpheus_commands + @shell_commands
        # @morpheus_commands.sort.each {|cmd|
        #   out <<  "\t#{cmd.to_s}\n"
        # }
        sorted_commands = Morpheus::Cli::CliRegistry.all.values.sort { |x,y| x.command_name.to_s <=> y.command_name.to_s }
        sorted_commands.each {|cmd|
          # JD: not ready to show description yet, gotta finish filling in every command first
          # maybe change 'View and manage' to something more concise like 'Manage'
          # out << "\t#{cmd.command_name.to_s.ljust(28, ' ')} #{cmd.command_description}\n"
          out << "\t#{cmd.command_name.to_s}\n"
        }
        #puts "\n"
        out <<  "\nShell Commands:\n"
        @shell_commands.each {|cmd|
          # out << "\t#{cmd.to_s.ljust(28, ' ')} #{@shell_command_descriptions ? @shell_command_descriptions[cmd] : ''}\n"
          out <<  "\t#{cmd.to_s}\n"
        }
        out << "\n"
        out << "For more information, see https://clidocs.morpheusdata.com"
        out << "\n"
        print out
        return 0
      elsif input =~ /^\s*#/
        Morpheus::Logging::DarkPrinter.puts "ignored comment: #{input}" if Morpheus::Logging.debug?
        return 0
      elsif input == 'clear'
        print "\e[H\e[2J"
        return 0
      elsif input == 'reload' || input == 'reload!'
        # clear registry
        Morpheus::Cli::CliRegistry.instance.flush
        # reload code
        Morpheus::Cli.reload!
        # execute startup scripts
        if File.exist?(Morpheus::Cli::DotFile.morpheus_profile_filename)
          Morpheus::Cli::DotFile.new(Morpheus::Cli::DotFile.morpheus_profile_filename).execute()
        end
        if File.exist?(Morpheus::Cli::DotFile.morpheusrc_filename)
          Morpheus::Cli::DotFile.new(Morpheus::Cli::DotFile.morpheusrc_filename).execute()
        end
        # recalculate shell environment
        reinitialize()

        Morpheus::Logging::DarkPrinter.puts "shell has been reloaded" if Morpheus::Logging.debug?
        return 0
      elsif input == '!!'
        cmd_number = @history.keys[-1]
        input = @history[cmd_number]
        if !input
          puts "There is no previous command"
          return false
        end
        return execute(input)
      elsif input =~ /^\!.+/
        cmd_number = input.sub("!", "").to_i
        if cmd_number != 0
          old_input = @history[cmd_number]
          if !old_input
            puts "Command not found by number #{cmd_number}"
            return 0
          end
          #puts "executing history command: (#{cmd_number}) #{old_input}"
          # log_history_command(old_input)
          # remove this from readline, and replace it with the old command
          Readline::HISTORY.pop
          Readline::HISTORY << old_input
          return execute(old_input)
        end

      elsif input == "insecure"
        Morpheus::RestClient.enable_ssl_verification = false
        return 0

      elsif ["hello","hi","hey","hola"].include?(input.strip.downcase)
        user_msg = input.strip.downcase
        # need a logged_in? method already damnit
        wallet = Morpheus::Cli::Credentials.new(@appliance_name, @appliance_url).load_saved_credentials
        help_msg = case user_msg
        when "hola"
          "¿como puedo ayudarte? tratar #{cyan}help#{reset}"
        else
          "how may I #{cyan}help#{reset} you?"
        end
        greeting = "#{user_msg.capitalize}#{wallet ? (' '+green+wallet['username'].to_s+reset) : ''}, #{help_msg}#{reset}"
        puts greeting
        return 0
      elsif input.strip =~ /^shell\s*/
        # just allow shell to fall through
        # we should reload the configs and history file after the sub shell process terminates though.
        # actually, that looks like it is working just fine already...?
        print cyan,"starting a subshell",reset,"\n"
      elsif input =~ /^\.\s/
        # dot alias for source <file>
        log_history_command(input)
        return Morpheus::Cli::SourceCommand.new.handle(input.split[1..-1])
      end
      exit_code, err = 0, nil
      begin
        argv = Shellwords.shellsplit(input)
        cmd_name = argv[0]
        cmd_args = argv[1..-1]
        # crap hack, naming conflicts can occur with aliases
        @return_to_log_level = ["log-level","debug"].include?(cmd_name) ? nil : Morpheus::Logging.log_level
        @return_to_coloring = ["coloring"].include?(cmd_name) ? nil : Term::ANSIColor::coloring?
        @return_to_benchmarking = ["benchmark"].include?(cmd_name) ? nil : Morpheus::Benchmarking.enabled?
        
        #if Morpheus::Cli::CliRegistry.has_command?(cmd_name) || Morpheus::Cli::CliRegistry.has_alias?(cmd_name)
          #log_history_command(input)
          # start a benchmark, unless the command is benchmark of course
          if my_terminal.benchmarking || cmd_args.include?("-B") || cmd_args.include?("--benchmark")
            if cmd_name != 'benchmark' # jd: this does not work still 2 of them printed.. fix it!
              # benchmark_name = "morpheus " + argv.reject {|it| it == '-B' || it == '--benchmark' }.join(' ')
              benchmark_name = argv.reject {|it| it == '-B' || it == '--benchmark' }.join(' ')
              start_benchmark(benchmark_name)
            end
          end
          exit_code, err = Morpheus::Cli::CliRegistry.exec_expression(input)
          benchmark_record = stop_benchmark(exit_code, err) # if benchmarking?
          Morpheus::Logging::DarkPrinter.puts(cyan + dark + benchmark_record.msg) if benchmark_record
        # else
        #   puts_error "#{Morpheus::Terminal.angry_prompt}'#{cmd_name}' is not recognized. Use 'help' to see the list of available commands."
        #   @history_logger.warn "Unrecognized Command #{cmd_name}" if @history_logger
        #   exit_code, err = -1, "Command not recognized"
        # end
      rescue Interrupt
        # user pressed ^C to interrupt a command
        @history_logger.warn "shell interrupt" if @history_logger
        print "\nInterrupt. aborting command '#{input}'\n"
        exit_code, err = 9, "aborted command"
      rescue SystemExit => cmdexit
        # nothing to do, assume the command that exited printed an error already
        # print "\n"
        if cmdexit.success?
          exit_code, err = cmdexit.status, nil
        else
          exit_code, err = cmdexit.status, "Command exited early."
        end
      rescue => e
        # some other type of failure..
        @history_logger.error "#{e.message}" if @history_logger
        exit_code, err = Morpheus::Cli::ErrorHandler.new(my_terminal.stderr).handle_error(e) # lol
        
      ensure
        if @return_to_log_level
          Morpheus::Logging.set_log_level(@return_to_log_level)
          ::RestClient.log = Morpheus::Logging.debug? ? Morpheus::Logging::DarkPrinter.instance : nil
          @return_to_log_level = nil
        end
        if @return_to_coloring != nil
          Term::ANSIColor::coloring = @return_to_coloring
          @return_to_coloring = nil
        end
        if @return_to_benchmarking != nil
          Morpheus::Benchmarking.enabled = @return_to_benchmarking
          my_terminal.benchmarking = Morpheus::Benchmarking.enabled
          @return_to_benchmarking = nil
        end
      end

      return exit_code, err
    end

  end

  # wha this?
  def get_prompt

    # print cyan,"morpheus > ",reset
    # input = $stdin.gets.chomp!

    input = ''
    while char=$stdin.getch do
      if char == '\n'
        print "\r\n"
        puts "executing..."
        break
      end
      print char
      input << char
    end
    return input
  end

  def history_file_path
    File.join(Morpheus::Cli.home_directory, "shell_history")
  end

  def load_history_logger
    file_path = history_file_path
    if !Dir.exist?(File.dirname(file_path))
      FileUtils.mkdir_p(File.dirname(file_path))
    end
    if !File.exist?(file_path)
      FileUtils.touch(file_path)
      FileUtils.chmod(0600, file_path)
    end
    logger = Logger.new(file_path)
    # logger.formatter = proc do |severity, datetime, progname, msg|
    #   "#{msg}\n"
    # end
    return logger
  end

  def load_history_from_log_file
    
    # @history ||= {}
    # @last_command_number ||= 0
    @history = {}
    @last_command_number = 0

    begin
      file_path = history_file_path
      # if !Dir.exist?(File.dirname(file_path))
      #   FileUtils.mkdir_p(File.dirname(file_path))
      # end
      # if !File.exist?(file_path)
      #   FileUtils.touch(file_path)
      #   FileUtils.chmod(0600, file_path)
      # end

      File.open(file_path).each_line do |line|
        # this is pretty goofy, but this looks for the format: (cmd $command_number) $command_string
        matches = line.match(/\(cmd (\d+)\) (.+)/)
        if matches && matches.size == 3
          cmd_number = matches[1].to_i
          cmd = matches[2]

          if cmd_number > @last_command_number
            @last_command_number = cmd_number
          end
          @history[cmd_number] = cmd

          # for Ctrl+R history searching
          Readline::HISTORY << cmd
        end
      end unless !File.exist?(file_path)
    rescue => e
      # raise e
      puts_error "failed to load history from log: #{e}"
      @history ||= {}
    end
    return @history
  end

  def log_history_command(cmd)
    load_history_from_log_file if !@history
    #todo: a fast log_history_command, that doesnt need to load the file..
    #@history ||= {}
    #@last_command_number ||= 0
    previous_cmd = @history[@last_command_number]
    # skip logging consecutive history commands.
    if previous_cmd && previous_cmd =~ /history/ && previous_cmd == cmd
      return @last_command_number
    end
    @last_command_number += 1
    @history[@last_command_number] = cmd
    if @history_logger
      @history_logger.info "#{@current_username}@#{@appliance_name} -- : (cmd #{@last_command_number}) #{cmd}"
    end
    return @last_command_number
  end

  def last_command
    if @history && @last_command_number
      @history[@last_command_number]
    else
      nil
    end
  end
  
  # load_history_commands paginates and sorts the command history
  # the most recent 25 are returned by default.
  # @return Hash like {:commands => [], :command_count => total}
  def load_history_commands(options={})
    phrase = options[:phrase]
    #sort_key = options[:sort] ? options[:sort].to_sym : nil
    #direction = options[:direction] # default sort is reversed to get newest first
    offset = options[:offset].to_i > 0 ? options[:offset].to_i : 0
    max = options[:max].to_i > 0 ? options[:max].to_i : 25
    
    if !@history
      load_history_from_log_file
    end
    
    
    # collect records as [{:number => 1, :command => "instances list"}, etc]
    history_records = []
    history_count = 0

    # only go so far back in command history, 1 million commands
    # this could be a large object...need to index our shell_history file lol
    # todo: this max needs to be done in load_history_from_log_file()
    history_keys = @history.keys.last(1000000).reverse
    # filter by phrase
    if phrase
      history_keys = history_keys.select {|k| (@history[k] && @history[k].include?(phrase)) || k.to_s == phrase }
    end
    # no offset, just max
    history_records = history_keys.first(max).collect { |k| {number: k, command: @history[k]} }
    command_count = history_keys.size

    meta = {size:history_records.size, total:command_count.to_i, max:max, offset:offset}
    return {commands: history_records, command_count: command_count, meta: meta}
  end

  def print_history(options={})
    history_result = load_history_commands(options)
    history_records = history_result[:commands]
    command_count = history_result[:command_count]
    if history_records.size == 0
      if options[:phrase]
        print cyan,"0 commands found matching '#{options[:phrase]}'.",reset,"\n"
      else
        print cyan,"0 commands found.",reset,"\n"
      end
    else
      print cyan
      # by default show old->new as the shell history should bash history
      history_records.reverse! unless options[:direction] == "desc"
      history_records.each do |history_record|
        puts "#{history_record[:number].to_s.rjust(3, ' ')}  #{history_record[:command]}"
      end
      if options[:show_pagination]
        pagination_msg = options[:phrase] ? "Viewing most recent %{size} of %{total} commands matching '#{options[:phrase]}'" : "Viewing most recent %{size} of %{total} commands"
        print_results_pagination(history_result[:meta], {:message =>pagination_msg})
        print reset, "\n"
      else
        print reset
      end
    end
    #print "\n"
    return 0
  end

  def history_commands_count()
    load_history_from_log_file if !@history
    @history.keys.size
  end

  def flush_history(n=nil)
    # todo: support only flushing last n commands
      file_path = history_file_path
      if File.exist?(file_path)
        File.truncate(file_path, 0)
      end
      @history = {}
      @last_command_number = 0
      @history_logger = load_history_logger
      print green, "Command history flushed", reset, "\n"
      return 0
  end
end
