require 'morpheus/cli/cli_command'

# This provides commands for authentication 
# This also includes credential management.
class Morpheus::Cli::Doc
  include Morpheus::Cli::CliCommand

  set_command_name :'doc'
  #set_command_name :'access'
  register_subcommands :list
  register_subcommands :get => :swagger
  register_subcommands :download => :download_swagger

  # hidden until doc complete (or close to it)
  set_command_hidden

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def handle(args)
    handle_subcommand(args)
  end

  def connect(options)
    @api_client = establish_remote_appliance_connection(options.merge({:no_prompt => true, :skip_verify_access_token => true, :skip_login => true}))
    @doc_interface = @api_client.doc
  end

  def list(args)
    exit_code, err = 0, nil
    params, options = {}, {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
List documentation links.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    connect(options)
    # construct the api request
    params.merge!(parse_list_options(options))
    # execute the api request
    @doc_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @doc_interface.dry.list(params)
      return 0, nil
    end
    json_response = @doc_interface.list(params)
    render_response(json_response, options, "links") do
      title = "Morpheus Documentation"
      print_h1 title, options
      if json_response['links'].empty?
        print yellow, "No help links found.",reset,"\n"
      else
        columns = {
          "Link Name" => 'name',
          "URL" => 'url',
          "Description" => {display_method:'description', max_width: (options[:wrap] ? nil : 50)}, 
        }
        print as_pretty_table(json_response['links'], columns.upcase_keys!, options)
        # print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return exit_code, err
  end

  def swagger(args)
    exit_code, err = 0, nil
    params, options = {}, {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      opts.on(nil, "--refresh", "Refresh the document. By default the swagger.yml and swagger.json are cached by the server.") do
        params['refresh'] = true
      end
      opts.on('-g', '--generate', "Alias for --refresh") do
        params['refresh'] = true
      end
      build_standard_get_options(opts, options, [], [:csv])
      opts.footer = <<-EOT
Print the Morpheus API Swagger Documentation (openapi).
The default format is JSON. Supports json or yaml.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    connect(options)
    # construct the api request
    params.merge!(parse_list_options(options))
    # for now, always use .json, and just convert to yaml for display on cli side
    openapi_format = options[:yaml] ? "yaml" : "json"
    # params['format'] = openapi_format
    # execute the api request
    @doc_interface.setopts(options)
    if options[:dry_run]
      params['format'] = openapi_format
      print_dry_run @doc_interface.dry.swagger(params)
      return 0, nil
    end
    json_response = @doc_interface.swagger(params)
    # default format is to print header and json
    render_response(json_response, options) do
      title = "Morpheus API swagger.#{openapi_format}"
      print_h1 title, options
      print cyan
      print as_json(json_response, options)
      print reset,"\n"
    end
    return exit_code, err
  end

  def download_swagger(args)
    exit_code, err = 0, nil
    params, options = {}, {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[local-file]")
      # build_standard_get_options(opts, options, [], [:csv,:out])
      opts.on(nil, '--yaml', "YAML Output") do
        options[:yaml] = true
        options[:format] = :yaml
      end
      opts.on(nil, "--refresh", "Refresh the document. By default the swagger.yml and swagger.json are cached by the server.") do
        params['refresh'] = true
      end
      opts.on('-g', '--generate', "Alias for --refresh") do
        params['refresh'] = true
      end
      opts.on( '-f', '--force', "Overwrite existing [local-file] if it exists." ) do
        options[:overwrite] = true
      end
      opts.on( '-p', '--mkdir', "Create missing directories for [local-file] if they do not exist." ) do
        options[:mkdir] = true
      end
      build_common_options(opts, options, [:dry_run, :quiet, :remote])
      opts.footer = <<-EOT
Download the Morpheus API Swagger Documentation (openapi).
[local-file] is required. This is the full local filepath for the downloaded file.
The default format is JSON. Supports json or yaml.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    # parse args
    outfile = args[0]
    if !validate_outfile(outfile, options)
      return 1, "Failed to validate outfile"
    end
    # construct the api request
    params.merge!(parse_list_options(options))
    if outfile.include?(".yml") || outfile.include?(".yaml")
      options[:yaml] = true
    end
    openapi_format = options[:yaml] ? "yaml" : "json"
    params['format'] = openapi_format
    # execute the api request
    @doc_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @doc_interface.dry.download_swagger(outfile, params)
      return 0, nil
    end
    print cyan + "Downloading swagger.#{openapi_format} to #{outfile} ... " if !options[:quiet]
    http_response = @doc_interface.download_swagger(outfile, params)
    if http_response.code.to_i == 200
      print green + "SUCCESS" + reset + "\n" if !options[:quiet]
      return 0, nil
    else
      print red + "ERROR" + reset + " HTTP #{http_response.code}" + "\n" if !options[:quiet]
      if File.exist?(outfile) && File.file?(outfile)
        Morpheus::Logging::DarkPrinter.puts "Deleting bad file download: #{outfile}" if Morpheus::Logging.debug?
        File.delete(outfile)
      end
      return 1, "HTTP #{http_response.code}"
    end
  end

  protected

end
