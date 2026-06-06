require 'morpheus/cli/cli_command'

class Morpheus::Cli::ClientsCommand
	include Morpheus::Cli::CliCommand

  set_command_name :clients
  set_command_description "View and manage Oath Clients"
  register_subcommands :list, :get, :add, :update, :remove

  def initialize()
    #@appliance_name, @appliance_url = Morpheus::Cli::Remote.active_appliance
  end

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @clients_interface = @api_client.clients
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage()
      build_standard_list_options(opts, options)
      opts.footer = "List Oauth Clients."
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @clients_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @clients_interface.dry.list(params)
      return 0
    end
    json_response = @clients_interface.list(params)
    render_response(json_response, options, "clients") do 
      clients = json_response['clients']
      print_h1 "Morpheus Clients", [], options
      print as_pretty_table(clients, client_columns.upcase_keys!, options)
      print reset
      print_results_pagination(json_response)
      print reset,"\n"
    end
  end

  def get(args)
    params = {}
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[client]")
      build_standard_get_options(opts, options)
      opts.footer = "Get details about an oath client.\n" + 
                    "[client] is required. This is the name or id of a client."

    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    id = args[0]
    if id.to_s !~ /\A\d{1,}\Z/
      client = find_client_by_client_id(id)
      return 1 if client.nil?
      id = client['id']
    else
      id = id.to_i
    end
    @clients_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @clients_interface.dry.get(id, params)
      return
    end
    json_response = @clients_interface.get(id, params)
    render_response(json_response, options, 'client') do
      client = json_response['client']
      print_h1 "Client Details", [], options
      print cyan
      print_description_list(client_columns, client)
      print reset,"\n"
    end
  end

  def add(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[clientId] [options]")
      build_option_type_options(opts, options, add_client_option_types)
      build_standard_add_options(opts, options)
      opts.footer = "Add New Oauth Client Record."
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args}\n#{optparse}"
    end
    if args[0]
      options[:options] ||= {}
      options[:options]['clientId'] ||= args[0]
    end
    connect(options)
    begin
       # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'client' => passed_options}) unless passed_options.empty?
      else
        payload = {
          'client' => {
          }
        }
        # allow arbitrary -O options
        payload.deep_merge!({'client' => passed_options}) unless passed_options.empty?
        # prompt for options
        params = Morpheus::Cli::OptionTypes.prompt(add_client_option_types, options[:options], @api_client, options[:params])
        params.booleanize!
        if params['redirectUris'] && params['redirectUris'].is_a?(String)
          params['redirectUris'] = params['redirectUris'].split(',').collect {|it| it.strip}.reject {|it| it.empty?}
        end
        payload.deep_merge!({'client' => params}) unless params.empty?
      end

      @clients_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clients_interface.dry.create(payload)
        return
      end
      json_response = @clients_interface.create(payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        display_name = json_response['client']  ? json_response['client']['clientId'] : ''
        print_green_success "Client #{display_name} added"
        get([json_response['client']['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def update(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[clientId] [options]")
      build_option_type_options(opts, options, update_client_option_types)
      build_standard_update_options(opts, options)
      opts.footer = "Update Oauth Client Record."
    end
    optparse.parse!(args)

    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end

    connect(options)
    begin

      client = find_client_by_name_or_id(args[0])
      return 1 if client.nil?

      # construct payload
      passed_options = options[:options] ? options[:options].reject {|k,v| k.is_a?(Symbol) } : {}
      payload = nil
      if options[:payload]
        payload = options[:payload]
        payload.deep_merge!({'client' => passed_options}) unless passed_options.empty?
      else
        payload = {
          'client' => {
          }
        }
        # allow arbitrary -O options
        payload.deep_merge!({'client' => passed_options}) unless passed_options.empty?
        # prompt for options
        #params = Morpheus::Cli::OptionTypes.no_prompt(update_client_option_types, options[:options], @api_client, options[:params])
        params = passed_options
        params.booleanize!
        if params['redirectUris'] && params['redirectUris'].is_a?(String)
          params['redirectUris'] = params['redirectUris'].split(',').collect {|it| it.strip}.reject {|it| it.empty?}
        end
        if params.empty?
          raise_command_error "Specify at least one option to update.\n#{optparse}"
        end

        payload.deep_merge!({'client' => params}) unless params.empty?
      end
      @clients_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clients_interface.dry.update(client['id'], payload)
        return
      end
      json_response = @clients_interface.update(client['id'], payload)
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        display_name = json_response['client'] ? json_response['client']['clientId'] : ''
        print_green_success "Client #{display_name} updated"
        get([json_response['client']['id']] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end

  def remove(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[clientId]")
      build_common_options(opts, options, [:auto_confirm, :json, :dry_run, :remote])
      opts.footer = "Deletes Oauth Client."
    end
    optparse.parse!(args)

    if args.count != 1
      raise_command_error "wrong number of arguments, expected 1 and got (#{args.count}) #{args}\n#{optparse}"
    end

    connect(options)
    begin
      client = find_client_by_name_or_id(args[0])
      return 1 if client.nil?

      unless options[:yes] || Morpheus::Cli::OptionTypes.confirm("Are you sure you want to delete the client #{client['clientId']}?")
        return 9, "aborted command"
      end
      @clients_interface.setopts(options)
      if options[:dry_run]
        print_dry_run @clients_interface.dry.destroy(client['id'])
        return
      end
      json_response = @clients_interface.destroy(client['id'])
      if options[:json]
        print JSON.pretty_generate(json_response)
        print "\n"
      else
        print_green_success "Client #{client['clientId']} removed"
        # list([] + (options[:remote] ? ["-r",options[:remote]] : []))
      end
      return 0
    rescue RestClient::Exception => e
      print_rest_exception(e, options)
      exit 1
    end
  end


  private
  def find_client_by_name_or_id(val)
    if val.to_s =~ /\A\d{1,}\Z/
      return find_client_by_id(val)
    else
      return find_client_by_client_id(val)
    end
  end

  def find_client_by_id(id)
    raise "#{self.class} has not defined @client_interface" if @clients_interface.nil?
    begin
      json_response = @clients_interface.get(id)
      return json_response['client']
    rescue RestClient::Exception => e
      if e.response && e.response.code == 404
        print_red_alert "Client not found by id #{id}"
      else
        raise e
      end
    end
  end

  def find_client_by_client_id(clientId)
    raise "#{self.class} has not defined @client_interface" if @clients_interface.nil?
    clients = @clients_interface.list()['clients'].select { |client| client['clientId'] == clientId }
    if clients.empty?
      print_red_alert "Client not found by clientId #{clientId}"
      return nil
    elsif clients.size > 1
      print_red_alert "#{clients.size} Clients found by clientId #{clientId}"
      print as_pretty_table(clients, [:id,:clientId], {color:red})
      print reset,"\n"
      return nil
    else
      return clients[0]
    end
  end

  def client_columns
    {
      "ID" => lambda {|it| it['id'] },
      "Client ID" => lambda {|it| it['clientId'] },
      "TTL" => lambda {|it| it['accessTokenValiditySeconds'] },
      "Refresh TTL" => lambda {|it| it['refreshTokenValiditySeconds'] },
      "Redirect URI" => lambda {|client| client['redirectUris'].join(", ")},
      "Requires Consent" => lambda {|it| format_boolean it['requireConsent']}
    }
  end


  def add_client_option_types
    [
      {'fieldName' => 'clientId', 'fieldLabel' => 'Client Id', 'type' => 'text', 'required' => true},
      {'fieldName' => 'clientSecret', 'fieldLabel' => 'Client Secret', 'type' => 'text'},
      {'switch' => 'ttl', 'fieldName' => 'accessTokenValiditySeconds', 'fieldLabel' => 'TTL (Seconds)', 'type' => 'number', 'required' => true,'defaultValue' => 43200, 'description' => 'Access Token Validity Seconds'},
      {'switch' => 'refresh-ttl', 'fieldName' => 'refreshTokenValiditySeconds', 'fieldLabel' => 'Refresh TTL (Seconds)', 'type' => 'number', 'required' => true,'defaultValue' => 43200, 'description' => 'Refresh Token Validity Seconds'},
      {'fieldName' => 'redirectUris', 'fieldLabel' => 'Redirect URI', 'type' => 'text', 'description' => 'Redirect URI(s), use commas to delimit values.'},
      {'fieldName' => 'requireConsent', 'fieldLabel' => 'Requires Consent', 'type' => 'checkbox', 'defaultValue' => false}
    ]
  end

  def update_client_option_types
    option_types = add_client_option_types #.select {|it| ['clientId', 'clientSecret', 'accessTokenValiditySeconds'].include?(it['fieldName']) }
    option_types.each {|it| 
      it.delete('required')
      it.delete('defaultValue')
      it.delete('skipSingleOption')
    }
    option_types
  end
end