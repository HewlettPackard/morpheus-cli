require 'optparse'
require 'morpheus/logging'
require 'morpheus/cli/cli_command'

class Morpheus::Cli::ManCommand
  include Morpheus::Cli::CliCommand
  set_command_name :man
  set_command_hidden

  # this should be read only anyway...
  @@default_editor = "less" # ENV['EDITOR']

  def handle(args)
    options = {}
    regenerate = false
    editor = @@default_editor
    open_as_link = false # true please
    goto_wiki = false
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: morpheus man"
      opts.on('-w','--wiki', "Open the morpheus-cli wiki instead of the local man page") do
        goto_wiki = true
      end
      opts.on('-e','--editor EDITOR', "Specify which program to open the manual with. Default is '#{editor}'.") do |val|
        editor = val
        open_as_link = false
      end
      opts.on('-g','--generate', "Regenerate the manual file") do
        regenerate = true
      end
      opts.on('-o','--out FILE', "Write manual file to a custom location") do |val|
        options[:outfile] = val
      end
      opts.on('--overwrite', '--overwrite', "Overwrite output file if it already exists.") do |val|
        options[:overwrite] = true
      end
      opts.on('-q','--quiet', "Do not open manual, for use with the -g option.") do
        options[:quiet] = true
      end
      #build_common_options(opts, options, [:quiet])
      # disable ANSI coloring
      opts.on('-C','--nocolor', "Disable ANSI coloring") do
        Term::ANSIColor::coloring = false
      end

      opts.on('-V','--debug', "Print extra output for debugging. ") do
        Morpheus::Logging.set_log_level(Morpheus::Logging::Logger::DEBUG)
        ::RestClient.log = Morpheus::Logging.debug? ? Morpheus::Logging::DarkPrinter.instance : nil
      end
      opts.on('-h', '--help', "Print this help" ) do
        puts opts
        exit
      end
      opts.footer = <<-EOT
Open the morpheus manual located at #{Morpheus::Cli::ManCommand.man_file_path}
The -g option can be used to regenerate the file.
The --out FILE option be used to write the manual file to a custom location.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    if goto_wiki
      link = "https://github.com/gomorpheus/morpheus-cli/wiki/CLI-Manual"
      if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
        system "start #{link}"
      elsif RbConfig::CONFIG['host_os'] =~ /darwin/
        system "open #{link}"
      elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
        system "xdg-open #{link}"
      end
      return 0, nil
    end

    fn = Morpheus::Cli::ManCommand.man_file_path
    if options[:outfile]
      regenerate = true
      fn = File.expand_path(options[:outfile])
      if File.directory?(fn)
        # if you give me a directory, could still work and use the default filename
        # fn = File.join(fn, "CLI-Manual-#{Morpheus::Cli::VERSION}.md")
        # raise_command_error "outfile is invalid. It is the name of an existing directory: #{fn}"
        print_error "#{red}Output file '#{fn}' is invalid.#{reset}\n"
        print_error "#{red}It is the name of an existing directory.#{reset}\n"
        return 1
      end
      if File.exists?(fn) && options[:overwrite] != true
        print_error "#{red}Output file '#{fn}' already exists.#{reset}\n"
        print_error "#{red}Use --overwrite to overwrite the existing file.#{reset}\n"
        return 1
      end
    end
    exit_code, err = 0, nil
    if regenerate || !File.exists?(fn)
      #Morpheus::Logging::DarkPrinter.puts "generating manual #{fn} ..." if Morpheus::Logging.debug? && !options[:quiet]
      exit_code, err = Morpheus::Cli::ManCommand.generate_manual(options)
    end
    
    if options[:quiet]
      return exit_code, err
    end
    
    Morpheus::Logging::DarkPrinter.puts "opening manual file #{fn}" if Morpheus::Logging.debug? && !options[:quiet]
    
    if open_as_link # not used atm
      link = "file://#{fn}"
      if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
        system "start #{link}"
      elsif RbConfig::CONFIG['host_os'] =~ /darwin/
        system "open #{link}"
      elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
        system "xdg-open #{link}"
      end
      return 0, nil
    else
      if editor
        if !system_command_available?(editor)
          raise_command_error "The editor program '#{editor}' is not available on your system."
          # puts_error "#{red}The editor program '#{editor}' is not available on your system.#{reset}"
          # return 1
        end        
        system("#{editor} #{fn}")
      else
        raise_command_error "Tell me how to open the manual file #{fn}. Try -e emacs or run export EDITOR=emacs"
        return 1
      end
    end

    return 0, nil
  end

  # determine if system command is available
  # uses *nix's `which` command.
  # Prevents using dangerous commands rm,mv,passwd
  # todo: support for Windows and PowerShell
  def system_command_available?(cmd)
    has_it = false
    begin
      cmd = cmd.strip.gsub("'",'')
      system("which '#{cmd}' > /dev/null 2>&1")
      has_it = $?.success?
    rescue => e
      raise e
    end
    return has_it
  end

  def self.man_file_path
    File.join(Morpheus::Cli.home_directory, "CLI-Manual-#{Morpheus::Cli::VERSION}.md")
  end

  # def self.save_manual(fn, content)
  #   # fn = man_file_path()
  #   if !Dir.exists?(File.dirname(fn))
  #     FileUtils.mkdir_p(File.dirname(fn))
  #   end
  #   Morpheus::Logging::DarkPrinter.puts "saving manual to #{fn}" if Morpheus::Logging.debug?
  #   File.open(fn, 'w') {|f| f.write content.to_s } #Store
  #   FileUtils.chmod(0600, fn)
  # end

  def self.generate_manual(options={})
    # todo: use pandoc or something else to convert the CLI-Manual.md to a man page
    # and install it, so the os command `man morpheus` will work too.
    fn = man_file_path()
    if options[:outfile]
      fn = File.expand_path(options[:outfile])
      if File.exists?(fn) && options[:overwrite] != true
        print_error "#{red}Output file '#{options[:outfile]}' already exists.#{reset}\n"
        print_error "#{red}Use --overwrite to overwrite the existing file.#{reset}\n"
        return 1, "output file already exists"
      end
    end
    if !Dir.exists?(File.dirname(fn))
      FileUtils.mkdir_p(File.dirname(fn))
    end
    Morpheus::Logging::DarkPrinter.puts "generating manual #{fn}" if Morpheus::Logging.debug? && !options[:quiet]

    File.open(fn, 'w') {|f| f.write("") } # clear file
    FileUtils.chmod(0600, fn)

    manpage = File.new(fn, 'w')
    # previous_stdout = $stdout
    # previous_stdout = STDOUT
    # $stdout = manpage
    begin

      manpage.print <<-ENDTEXT
#{prog_name} v#{Morpheus::Cli::VERSION}

## NAME

    morpheus - the command line interface for interacting with the Morpheus appliance

## SYNOPSIS

    morpheus [command] [<args>] [options]

## DESCRIPTION

    Morpheus CLI

    This is a command line interface for managing a Morpheus Appliance.
    All communication with the remote appliance is done via the Morpheus API.

    Use the command `#{prog_name} remote add` to connect to your Morpheus appliance.

    To learn more, visit https://github.com/gomorpheus/morpheus-cli/wiki/Getting-Started

    To learn more about the Morpheus Appliance, visit https://www.morpheusdata.com

    To learn more about the Morpheus API, visit https://apidocs.morpheusdata.com

## GLOBAL OPTIONS

    There are several global options available.

    -v, --version                    Print the version.
        --noprofile                  Do not read and execute the personal initialization script .morpheus_profile
    -C, --nocolor                    Disable ANSI coloring
    -V, --debug                      Print extra output for debugging. 
    -h, --help                       Print this help

## COMMON OPTIONS

    There are many common options that are supported by a most commands.

    -O, --option OPTION              Option value in the format -O var="value" (deprecated soon in favor of first class options)
    -N, --no-prompt                  Skip prompts. Use default values for all optional fields.
        --payload FILE               Payload from a local JSON or YAML file, skip all prompting
        --payload-dir DIRECTORY      Payload from a local directory containing 1-N JSON or YAML files, skip all prompting
        --payload-json JSON          Payload JSON, skip all prompting
        --payload-yaml YAML          Payload YAML, skip all prompting
    -j, --json                       JSON Output
    -d, --dry-run                    Dry Run, print the API request instead of executing it
        --curl                       Dry Run to output API request as a curl command.
        --scrub                      Mask secrets in output, such as the Authorization header. For use with --curl and --dry-run.
    -r, --remote REMOTE              Remote name. The current remote is used by default.
        --remote-url URL             Remote url. This allows adhoc requests instead of using a configured remote.
    -T, --token TOKEN                Access token for authentication with --remote. Saved credentials are used by default.
    -U, --username USERNAME          Username for authentication.
    -P, --password PASSWORD          Password for authentication.
    -I, --insecure                   Allow insecure HTTPS communication.  i.e. bad SSL certificate.
    -H, --header HEADER              Additional HTTP header to include with requests.
        --timeout SECONDS            Timeout for api requests. Default is typically 30 seconds.
    -y, --yes                        Auto Confirm
    -q, --quiet                      No Output, do not print to stdout

## MORPHEUS COMMANDS

    The morpheus executable is divided into commands.
    Each morpheus command may have 0-N sub-commands that it supports. 
    Commands generally map to the functionality provided in the Morpheus UI.
       
    You can get help for any morpheus command by using the -h option.

    The available commands and their options are documented below.
ENDTEXT
      
      terminal = Morpheus::Terminal.new($stdin, manpage)
      Morpheus::Logging::DarkPrinter.puts "appending command help `#{prog_name} --help`" if Morpheus::Logging.debug? && !options[:quiet]

      manpage.print "\n"
      manpage.print "## morpheus\n"
      manpage.print "\n"
      manpage.print "```\n"
      exit_code, err = terminal.execute("--help")
      manpage.print "```\n"
      manpage.print "\n"
      # output help for every command (that is not hidden)
      Morpheus::Cli::CliRegistry.all.keys.sort.each do |cmd|
        cmd_klass = Morpheus::Cli::CliRegistry.instance.get(cmd)
        cmd_instance = cmd_klass.new
        Morpheus::Logging::DarkPrinter.puts "appending command help `#{prog_name} #{cmd} --help`" if Morpheus::Logging.debug? && !options[:quiet]
        #help_cmd = "morpheus #{cmd} --help"
        #help_output = `#{help_cmd}`
        manpage.print "\n"
        manpage.print "### morpheus #{cmd}\n"
        manpage.print "\n"
        manpage.print "```\n"
        begin
          cmd_instance.handle(["--help"])
        rescue SystemExit => err
          raise err unless err.success?
        end
        manpage.print "```\n"
        # subcommands = cmd_klass.subcommands
        subcommands = cmd_klass.visible_subcommands
        if subcommands && subcommands.size > 0
          subcommands.sort.each do |subcommand, subcommand_method|
            Morpheus::Logging::DarkPrinter.puts "appending command help `#{prog_name} #{cmd} #{subcommand} --help`" if Morpheus::Logging.debug? && !options[:quiet]
            manpage.print "\n"
            manpage.print "#### morpheus #{cmd} #{subcommand}\n"
            manpage.print "\n"
            manpage.print "```\n"
            begin
              cmd_instance.handle([subcommand, "--help"])
            rescue SystemExit => err
              raise err unless err.success?
            end
            manpage.print "```\n"
            # manpage.print "\n"
          end
        end
        manpage.print "\n"
      end

      manpage.print <<-ENDTEXT

## ENVIRONMENT VARIABLES

Morpheus has only one environment variable that it uses.

### MORPHEUS_CLI_HOME

The **MORPHEUS_CLI_HOME** variable is where morpheus CLI stores its configuration files.
This can be set to allow a single system user to maintain many different configurations
If the directory does not exist, morpheus will attempt to create it.

The default home directory is **$HOME/.morpheus**

To see how this works, run the following:

```shell
MORPHEUS_CLI_HOME=~/.morpheus_test morpheus shell
```

Now, in your new morpheus shell, you can see that it is a fresh environment.
There are no remote appliances configured.

```shell
morpheus> remote list

Morpheus Appliances
==================

You have no appliances configured. See the `#{prog_name} remote add` command.

```

You can use this to create isolated environments (sandboxes), within which to execute your morpheus commands.

```shell
export MORPHEUS_CLI_HOME=~/morpheus_test
morpheus remote add demo https://demo-morpheus --insecure
morpheus instances list
```

Morpheus saves the remote appliance information, including api access tokens, 
to the CLI home directory. These files are saved with file permissions **6000**.
So, only one system user should be allowed to execute morpheus with that home directory.
See [Configuration](#Configuration) for more information on the files morpheus reads and writes.

## CONFIGURATION

Morpheus reads and writes several configuration files within the $MORPHEUS_CLI_HOME directory.

**Note:** These files are maintained by the program. It is not recommended for you to manipulate them.

### appliances file

The `appliances` YAML file contains a list of known appliances, keyed by name.

Example:
```yaml
:qa:
  :host: https://qa-morpheus
:production:
  :host: https://production-morpheus
```

### credentials file

The `.morpheus/credentials` YAML file contains access tokens for each known appliance.

### groups file

The `.morpheus/groups` YAML file contains the active group information for each known appliance.


## Startup scripts

When Morpheus starts, it executes the commands in a couple of dot files.

These scripts are written in morpheus commands, not bash, so they can only execute morpheus commands and aliases. 

### .morpheus_profile file

It looks for `$MORPHEUS_CLI_HOME/.morpheus_profile`, and reads and executes it (if it exists). 

This may be inhibited by using the `--noprofile` option.

### .morpheusrc file

When started as an interactive shell with the `#{prog_name} shell` command,
Morpheus reads and executes `$MORPHEUS_CLI_HOME/.morpheusrc` (if it exists). This may be inhibited by using the `--norc` option. 

An example startup script might look like this:

```
# .morpheusrc

set-prompt "%cyan%username%reset@%magenta%remote %cyanmorpheus> %reset"
version
remote current
echo "Welcome back %username"
echo

```

ENDTEXT

    ensure
      manpage.close if manpage
      # $stdout = previous_stdout if previous_stdout
      # this is needed to re-establish instance with STDOUT, STDIN
      terminal = Morpheus::Terminal.new()
    end

    return 0, nil
  end

end
