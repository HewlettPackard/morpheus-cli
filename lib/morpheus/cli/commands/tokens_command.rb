require 'morpheus/cli/cli_command'

# This provides commands for authentication 
# This also includes credential management.
class Morpheus::Cli::TokensCommand
  include Morpheus::Cli::CliCommand

  set_command_name :'tokens'
  set_command_description "View and manage API access tokens."
  register_subcommands :list, :get, :add, :remove, :remove_all

  def initialize()
    # @appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @tokens_interface = @api_client.tokens
  end
  
  def handle(args)
    handle_subcommand(args)
  end
  
  def list(args)
    options = {}
    params = {}
    ref_ids = []
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[search]")
      build_standard_list_options(opts, options)
      opts.on("--client-id CLIENT", "Filter by Client ID. eg. morph-api, morph-cli") do |val|
        params['clientId'] = val.to_s
      end
      opts.on("--name TOKEN", "Filter by name") do |val|
        params['name'] = val.to_s
      end
      opts.on("--value TOKEN", "Filter by access token value") do |val|
        params['token'] = val.to_s
      end
      opts.footer = "List API access tokens."
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @tokens_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @tokens_interface.dry.list(params)
      return
    end
    json_response = @tokens_interface.list(params)
    tokens = json_response['tokens']
    render_response(json_response, options, 'tokens') do
      print_h1 "Morpheus API Tokens", parse_list_subtitles(options), options
      if tokens.empty?
        print yellow,"No tokens found.",reset,"\n"
      else
        columns = token_columns.select {|k,v| 
          ["ID", "Name", "Client ID", "Username", "Access Token", "TTL"].include?(k)
        }.upcase_keys!
        print as_pretty_table(tokens, columns, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    return 0, nil
  end
  
  def get(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific token.
[token] is required. This is the id or name or value of the token.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    connect(options)
    id_list = parse_id_list(args).collect do |id|
      if id.to_s =~ /\A\d{1,}\Z/
        id
      else
        # Looking for a token by secret value? eg. "93cb5548-********""
        if id.to_s =~ /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
          token = find_token_by_token(id)
          if token
            token['id']
          else
            return 1, "Token not found for '#{id[0..8]}********'"
          end
        else
          token = find_token_by_name(id)
          if token
            token['id']
          else
            return 1, "Token not found for '#{id}'"
          end
        end
      end
    end
    return run_command_for_each_arg(id_list) do |id|
      _get(id, params, options)
    end
  end

  def _get(id, params, options)
    @tokens_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @tokens_interface.dry.get(id, params)
      return
    end
    json_response = @tokens_interface.get(id, params)
    render_response(json_response, options, 'token') do
      token = json_response['token']
      print_h1 "Token Details", [], options
      print cyan
      print_description_list(token_columns, token)
      print reset,"\n"
    end
    return 0, nil
  end

  def add(args)
    options = {}
    params = {}

    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[name]")
      # opts.on("--client-id CLIENT", "Client ID. eg. morph-api, morph-cli") do |val|
      #   params['clientId'] = val.to_s
      # end
      build_option_type_options(opts, options, add_token_option_types)
      build_standard_add_options(opts, options)
      opts.footer = <<-EOT
Create a new token
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:0, max:1)
    connect(options)
    if args[0]
      options[:options]['name'] = args[0]
    end
    payload = {}
    if options[:payload]
      payload = options[:payload]
      payload.deep_merge!({'token' => parse_passed_options(options)})
    else
      payload.deep_merge!({'token' => parse_passed_options(options)})
      v_prompt = Morpheus::Cli::OptionTypes.prompt(add_token_option_types, options[:options], @api_client, options[:params])
      params.deep_merge!(v_prompt)
      payload['token'].deep_merge!(params)
    end
    @tokens_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @tokens_interface.dry.create(payload)
      return 0, nil
    end
    json_response = @tokens_interface.create(payload)
    token = json_response['token']
    render_response(json_response, options, 'token') do
      print_green_success "Created token #{token['id']}"
      print_green_success "Access Token: #{token['accessToken']}"
      print_green_success "Refresh Token: #{token['refreshToken']}"
      return _get(token["id"], {}, options)
    end
    return 0, nil
  end

  def remove(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id list]")
      opts.on("--client-id CLIENT", "Filter by Client ID. eg. morph-api, morph-cli") do |val|
        params['clientId'] = val.to_s
      end
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete a token.
[id] is required. This is the id of a token.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    token = find_token_by_name_or_id(args[0])
    return 1, "Token not found" if token.nil?
    parse_options(options, params)
    confirm!("Are you sure you want to delete the token ID: #{token['id']} Value: #{token['maskedAccessToken']}?", options)
    execute_api(@tokens_interface, :destroy, [token['id']], options) do |json_response|
      print_green_success "Removed token #{token['maskedAccessToken']}"
    end
  end

  def remove_all(args)
    client_id = nil
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[id]")
      opts.on("--client-id CLIENT", "Delete all tokens for a specific Client ID. eg. morph-api, morph-cli") do |val|
        client_id = val.to_s
      end
      build_standard_remove_options(opts, options)
      opts.footer = <<-EOT
Delete many tokens at once.
[id list] is required. This is the list of token ids to be deleted
This command supports using --client-id CLIENT option instead of [id list]
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse)
    connect(options)
    id_list = parse_id_list(args)

    if client_id
      confirm!("Are you sure you want to perform this bulk delete tokens '#{client_id}'?", options)
      params['clientId'] = client_id
      execute_api(@tokens_interface, :destroy_all, [params], options) do |json_response|
        print_green_success "Removed all your tokens for client #{client_id}"
      end
    elsif id_list && !id_list.empty?
      confirm!("Are you sure you want to perform this bulk delete of #{id_list.size} tokens?", options)
      params['id'] = id_list
      execute_api(@tokens_interface, :destroy_all, [params], options) do |json_response|
        print_green_success "Removed #{id_list.size} tokens"
      end
    else
      raise_command_error "Bulk delete requires a list of ids"
    end
  end

  protected

  def token_columns
    {
      "ID" => lambda {|it| it['id'] },
      "Name" => lambda {|it| it['name'] },
      "Client ID" => lambda {|it| it['clientId'] },
      "Username" => lambda {|it| it['username'] },
      "Access Token" => lambda {|it| it['maskedAccessToken'] },
      "Scope" => lambda {|it| it['scope'] },
      "Refresh Token" => lambda {|it| it['maskedRefreshToken'] },
      "TTL" => lambda {|it| 
        if it['expiration']
          expires_on = parse_time(it['expiration'])
          if expires_on && expires_on < Time.now
            "Expired"
          else
            it['expiration'] ? (format_duration(it['expiration']) rescue '') : '' 
          end
        end
      },
      "Expiration" => lambda {|it| format_local_dt(it['expiration']) },
    }
  end

  def add_token_option_types
    [
      {'fieldName' => 'name', 'fieldLabel' => 'Name', 'type' => 'text', 'description' => "Optional display name for this access token"},
      {'fieldName' => 'clientId', 'fieldLabel' => 'Client ID', 'type' => 'select', 'optionSource' => 'clients', 'required' => true, 'defaultValue' => 'morph-api'},
    ]
  end

  def find_token_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_token_by_id(val)
    else
      return find_token_by_name(val)
    end
  end

  def find_token_by_id(id)
    begin
      json_response = @tokens_interface.get(id.to_i)
      return json_response['token']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Token not found by id '#{id}'"
      else
        raise e
      end
    end
  end

  def find_token_by_name(name)
    json_response = @tokens_interface.list({name: name.to_s})
    tokens = json_response['tokens']
    if tokens.empty?
      print_red_alert "Token not found by name '#{name}'"
      return nil
    elsif tokens.size > 1
      print_red_alert "#{tokens.size} tokens found matching '#{name}'"
      puts_error as_pretty_table(tokens, [:id, :name], {color:red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return tokens[0]
    end
  end

  def find_token_by_token(value)
    json_response = @tokens_interface.list({token: value.to_s})
    tokens = json_response['tokens']
    if tokens.empty?
      print_red_alert "Token not found"
      return nil
    elsif tokens.size > 1
      print_red_alert "#{tokens.size} tokens found matching '#{value}'"
      puts_error as_pretty_table(tokens, [:id, :'accessToken'], {color:red})
      print_red_alert "Try using ID instead"
      print reset,"\n"
      return nil
    else
      return tokens[0]
    end
  end

end
