require 'morpheus/cli/cli_command'

class Morpheus::Cli::ClusterTypes
  include Morpheus::Cli::CliCommand

  set_command_description "View cluster types."
  set_command_name :'cluster-types'
  register_subcommands :list, :get
  

  # This is a hidden command, documenting clusters list-types and clusters get-type
  set_command_hidden

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @clusters_interface = @api_client.clusters
  end
  
  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options = {}
    params = {}
    optparse = Morpheus::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} clusters list-types [search]"
      #opts.banner = subcommand_usage("[search]")
      # opts.on('--optionTypes [true|false]', String, "Include optionTypes in the response. Default is false.") do |val|
      #   params['optionTypes'] = (val.to_s == '' || val.to_s == 'on' || val.to_s == 'true')
      # end
      build_standard_list_options(opts, options)
      opts.footer = "List cluster types."
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, count:0)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    params.merge!(parse_list_options(options))
    @clusters_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @clusters_interface.dry.cluster_types(params)
      return
    end
    json_response = @clusters_interface.cluster_types(params)
    render_response(json_response, options, "clusterTypes") do
      cluster_types = json_response["clusterTypes"]
      print_h1 "Morpheus Cluster Types", parse_list_subtitles(options), options
      if cluster_types.empty?
        print cyan,"No cluster types found.",reset,"\n"
      else
        list_columns = {
          "ID" => 'id',
          "NAME" => 'name',
          "CODE" => 'code',
          "DESCRIPTION" => lambda {|it| truncate_string(it['description'], options[:wrap] ? nil : 100) },
        }
        print as_pretty_table(cluster_types, list_columns, options)
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
      opts.banner = "Usage: #{prog_name} clusters get-type [type] "
      # opts.banner = subcommand_usage("[type]")
      # opts.on('--optionTypes [true|false]', String, "Include optionTypes in the response. Default is true.") do |val|
      #   params['optionTypes'] = (val.to_s == '' || val.to_s == 'on' || val.to_s == 'true')
      # end
      build_standard_get_options(opts, options)
      opts.footer = <<-EOT
Get details about a specific cluster type.
[type] is required. This is the name or id of a cluster type.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, min:1)
    id = args.join(" ")
    connect(options)
    params.merge!(parse_query_options(options))
    cluster_type = nil
    
    # /api/cluster-types/$id does not exist, this loads them all.
    # todo: fix api to support /api/cluster-types/$id
    cluster_type = find_cluster_type_by_name_or_id(id)
    if cluster_type.nil?
      raise_command_error("cluster type not found for name or id '#{id}'") if cluster_type.nil?
    end
    id = cluster_type['id']
    # /api/cluster-types does not return optionTypes by default, use ?optionTypes=true
    @clusters_interface.setopts(options)
    if options[:dry_run]
      # print_dry_run @clusters_interface.dry.get_type(id, params)
      print_dry_run @clusters_interface.dry.cluster_types(params)
      return
    end
    # json_response = @clusters_interface.get(id, params)
    # cluster_type = json_response[cluster_type_object_key]
    json_response = cluster_type
    render_response(json_response, options) do
      print_h1 "Cluster Type Details", [], options
      print cyan
      show_columns = list_columns = {
          "ID" => 'id',
          "Name" => 'name',
          "Code" => 'code',
          "Description" => 'description',
        }
      print_description_list(show_columns, cluster_type)

      if cluster_type['optionTypes'] && cluster_type['optionTypes'].size > 0
        print_h2 "Configuration Options"
        opt_columns = [
          # {"ID" => lambda {|it| it['id'] } },
          {"FIELD NAME" => lambda {|it| (it['fieldContext'] && it['fieldContext'] != 'domain') ? [it['fieldContext'], it['fieldName']].join('.') : it['fieldName']  } },
          {"FIELD LABEL" => lambda {|it| it['fieldLabel'] } },
          {"TYPE" => lambda {|it| it['type'] } },
          {"DEFAULT" => lambda {|it| it['defaultValue'] } },
          {"REQUIRED" => lambda {|it| format_boolean it['required'] } },
          # {"DESCRIPTION" => lambda {|it| it['description'] }, # do it!
        ]
        print as_pretty_table(cluster_type['optionTypes'], opt_columns)
      else
        # print cyan,"No option types found for this cluster type.","\n",reset
      end

      controller_types = cluster_type['controllerTypes'] || []
      if controller_types && controller_types.size > 0
        print_h2 "Controller Types"
        print as_pretty_table(controller_types, [:name, :code], options)
      else
        # print cyan,"No worker types found for this cluster type.","\n",reset
      end

      worker_types = cluster_type['workerTypes'] || []
      if worker_types && worker_types.size > 0
        print_h2 "Worker Types"
        print as_pretty_table(worker_types, [:name, :code], options)
      else
        # print cyan,"No worker types found for this cluster type.","\n",reset
      end

      print reset,"\n"
    end
    return 0, nil
  end

  protected

  def find_cluster_type_by_name_or_id(val)
    (val.to_s =~ /\A\d{1,}\Z/) ? find_cluster_type_by_id(val) : find_cluster_type_by_name(val)
  end

  def find_cluster_type_by_id(id)
    get_cluster_types.find { |it| it['id'] == id.to_i }
  end

  def find_cluster_type_by_name(name)
    get_cluster_types.find { |it| it['name'].downcase == name.downcase || it['code'].downcase == name.downcase }
  end

  def cluster_types_for_dropdown
    get_cluster_types.collect {|it| {'id' => it['id'], 'name' => it['name'], 'code' => it['code'], 'value' => it['code']} }
  end

  def get_cluster_types(refresh=false)
    if !@cluster_types || refresh
      @cluster_types = @clusters_interface.cluster_types()['clusterTypes']
    end
    @cluster_types
  end
end