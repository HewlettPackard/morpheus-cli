require 'json'
require 'uri'
require 'cgi'
require 'morpheus/rest_client'
#require 'morpheus/api/body_io'
# require 'rest-client'

class Morpheus::APIClient

  CLIENT_ID = 'morph-cli' unless defined?(CLIENT_ID)

  # Initialize a new APIClient
  #   client = APIClient.new(url:"https://morpheus.yourcompany.com", verify_ssl:false)
  # This old method signature is being deprecated:
  #   client = APIClient.new(access_token, refresh_token, expires_in, base_url, verify_ssl, options={})
  #
  # def initialize(attrs={}, options={})
  def initialize(access_token, refresh_token=nil,expires_in = nil, base_url=nil, verify_ssl=true, options={})
    self.client_id = CLIENT_ID
    attrs = {}
    if access_token.is_a?(Hash)
      attrs = access_token.clone()
      access_token = attrs[:access_token]
      refresh_token = attrs[:refresh_token]
      base_url = attrs[:url] || attrs[:base_url]
      expires_in = attrs[:expires_in]
      verify_ssl = attrs.key?(:verify_ssl) ? attrs[:verify_ssl] : true
      self.client_id = attrs[:client_id] ? attrs[:client_id] : CLIENT_ID
      if attrs[:client_id]
        self.client_id = attrs[:client_id]
      end
      options = refresh_token.is_a?(Hash) ? refresh_token.clone() : {}
    end
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    if @base_url.to_s.empty?
      raise "#{self.class} initialized without a required option :url"
    end
    @base_url = @base_url.chomp("/")
    # todo: validate URI
    @expires_at = nil
    if expires_in != nil
      @expires_at = Time.now + expires_in
    end
    @dry_run = false
    set_ssl_verification_enabled(verify_ssl)
    setopts(options)
  end

  def url
    @base_url
  end

  def to_s
    "<##{self.class}:#{self.object_id.to_s(8)} @url=#{@base_url} @verify_ssl=#{@verify_ssl} @access_token=#{@access_token ? '************' : nil} @refresh_token=#{@access_token ? '************' : nil} @expires_at=#{@expires_at} @client_id=#{@client_id} @options=#{@options}>"
  end

  def inspect
    to_s
  end

  def dry_run(val=true)
    @dry_run = !!val
    self
  end

  def dry()
    dry_run(true)
  end

  def ssl_verification_enabled?
    @verify_ssl
  end

  def set_ssl_verification_enabled(val)
    @verify_ssl = !!val
  end

  # set this in your interface, eg. to 'application/json'
  # or let it it default to json when payload is present.
  def default_content_type
    nil
  end

  # set default seconds for interface to timeout after
  # or let it use system default? none, it should not timeout by default..
  # I think execute() may use 30 seconds for get by default.
  # and it should remove timeout when method is post, put, or delete
  def default_timeout
    nil
  end

  # Authorization is required, except for a couple commands like Ping and Setup
  def authorization_required?
    true
  end

  # common global options, hooray.
  # this is probably needed for CliCommand too..
  # maybe make this a mixin...

  # need this accessor?
  # def get_options
  #   @options
  # end

  # set common global @options for use with all requests
  # meant for inline use just like dry(), set_options(dry_run:true) can be used in place of dry()
  # @param opts [Hash] globally supported options like :dry_run, :json, :curl, :headers, :timeout, etc
  # Example:
  # Prints curl -XGET .../whoami -H "Bearer" instead of actually request
  # APIClient.new(token).whoami.setopts(curl:true).get({})
  # @return self (APIClient)
  def setopts(new_options)
    @options = new_options
    if @options[:dry_run]
      dry_run(true)
    end
    self
  end

  # with_options sets common global @options for the duration of the block only
  # then returns the options to their prior values
  # @param opts [Hash] globally supported options like :dry_run, :json, :curl, :headers, :timeout, etc
  # @return result of block, usually the a result Hash from client.execute({})
  def withopts(tmp_options, &block)
    @_old_options = @options
    begin
      @options = tmp_options
      result = block.call()
    ensure
      @options = @_old_options
    end
    return result
  end

  alias :set_options :setopts
  alias :with_options :withopts
  # Execute an HTTP request with this client.
  # opts - Hash of options for HTTP Request.
  #   :url - The full url
  #   :method - The default method is :get (GET)
  #   :headers - Hash of headers to include in the request.
  #              eg. {'Content-Type' => 'application/json'}. :params is a special key for query parameters.
  #   :params - query parameters
  #   :payload - The body of the request.
  #   :timeout - A custom timeout in seconds for api requests. The default is 30. todo: separate timeout options
  # options - Hash of common global options that commands parse. eg. :headers, :timeout, :dry_run, :curl, etc
  #   :headers - Extra headers to add. This expects a Hash like {'Content-Type' => 'application/json'}.
  #   :timeout - A custom timeout in seconds for api requests. The default is 30. todo: separate timeout options
  def execute(opts, options={})
    # Morpheus::Logging::DarkPrinter.puts "Morpheus::RestClient.execute(#{opts})" if Morpheus::Logging.debug?
    # ok, always prepend @base_url, let the caller specify it exactly or leave it off.
    # this allows the Interface definition be lazy and not specify the base_url in every call to execute()
      # it will be used though...
    if opts[:url]
      if !opts[:url].include?(@base_url)
        opts[:url] = "#{@base_url}#{opts[:url]}"
      end
    end
    # merge in common global @options
    if @options
      options = options.merge(@options)
    else
      options = options.clone
    end

    # determine HTTP method
    if opts[:method].nil?
      opts[:method] = :get
    else
      # convert to lowercase Symbol like :get, :post, :put, or :delete
      opts[:method] = opts[:method].to_s.downcase.to_sym
    end

    # could validate method here...

    # apply default headers
    opts[:headers] ||= {}

    is_multipart = (opts[:payload].is_a?(Hash) && opts[:payload][:multipart] == true)

    # Authorization: apply our access token
    if authorization_required?
      if @access_token
        if opts[:headers][:authorization].nil? && opts[:headers]['Authorization'].nil?
          opts[:headers][:authorization] = "Bearer #{@access_token}"
        else
          # authorization header has already been set.
        end
      end
    end

    # POST and PUT requests default Content-Type is application/json
    # set Content-Type or pass :form_data => true if you want application/x-www-form-urlencoded
    # or use opts[:payload][:multipart] = true if you need multipart/form-data
    if opts[:method] == :post || opts[:method] == :put
      if opts[:headers]['Content-Type'].nil? && opts[:payload] && is_multipart != true && opts[:form_data] != true
        opts[:headers]['Content-Type'] = (default_content_type || 'application/json')
      end

      # Auto encode payload as JSON, just to be nice
      if opts[:headers]['Content-Type'] == 'application/json' && !opts[:payload].is_a?(String)
        opts[:payload] = opts[:payload].to_json
      end

    end

    # always use custom timeout eg. from --timeout option
    # or use default_timeout for GET requests only.
    if opts[:timeout].nil?
      if options[:timeout]
        opts[:timeout] = options[:timeout].to_f
      elsif default_timeout && opts[:method] == :get
        opts[:timeout] = default_timeout.to_f
      end
    end

    # add extra headers, eg. from --header option
    # headers should be a Hash and not an Array, dont make me split you here!
    if options[:headers]
      opts[:headers] = opts[:headers].merge(options[:headers])
    end

    # this is confusing, but RestClient expects :params inside the headers...?
    # move/copy params to headers.params for simplification.
    # remove this if issues arise
    # if opts[:params] && (opts[:headers][:params].nil? || opts[:headers][:params].empty?)
    #   opts[:headers][:params] = opts.delete(:params) # .delete(:params) maybe?
    # end

    # :command_options for these
    # if options[:curl]
    #   opts[:curl] = options[:curl]
    # end
    # if options.key?(:pretty_json)
    #   opts[:pretty_json] = options[:pretty_json]
    # end
    # if options.key?(:scrub)
    #   opts[:scrub] = options[:scrub]
    # end

    # @verify_ssl is not used atm
    # todo: finish this and use it instead of the global variable RestClient.ssl_verification_enabled?
    # gotta clean up all APIClient subclasses new() methods to support this
    # the CliCommand subclasses should be changed to @foos_interface = @api_client.foos
    # also.. Credentials.new()
    if @verify_ssl == false
      opts[:verify_ssl] = OpenSSL::SSL::VERIFY_NONE
    end

    if @dry_run
      # JD: could return a Request object instead...
      # print_dry_run needs options somehow...
      opts[:command_options] = options # trash this..we got @options with setopts now
      return opts
    end

    # uhh can't use LIST at the moment
    # fix it!
    # if opts[:method] == :list
    #   opts[:method]
    # end

    # Morpheus::Logging::DarkPrinter.puts "Morpheus::RestClient.execute(#{opts})" if Morpheus::Logging.debug?
    # instead, using ::RestClient.log = STDOUT
    response = Morpheus::RestClient.execute(opts)
    if opts[:parse_json] != false && options[:parse_json] != false
      return JSON.parse(response.to_s)
    else
      return response
    end
  end

  def logged_in?
    !!@access_token
  end

  def client_id
    @client_id
  end

  def client_id=(val)
    @client_id = val
  end

  def login(username, password, use_client_id=nil)
    if use_client_id
      self.client_id = use_client_id
    end
    @access_token, @refresh_token, @expires_at = nil, nil, nil
    response = auth.login(username, password, self.client_id)
    @access_token = response['access_token']
    @refresh_token = response['refresh_token']
    if response['expires_in'] != nil
      @expires_at = Time.now + response['expires_in']
    end
    # return response
    return self
  end

  def use_refresh_token(t=nil)
    if t.nil?
      t = @refresh_token
    end
    if t.nil?
      raise "#{self.class} does not currently have a refresh_token"
    end
    response = auth.use_refresh_token(t, self.client_id)
    @access_token = response['access_token']
    @refresh_token = response['refresh_token']
    if response['expires_in'] != nil
      @expires_at = Time.now + response['expires_in']
    end
    @access_token = response['access_token']
    # return response
    return self
  end

  def logout
    @access_token = nil
    @refresh_token = nil
    @expires_at = nil
    return self
  end

  def common_interface_options
    {
      url:           @base_url,
      access_token:  @access_token,
      refresh_token: @refresh_token,
      expires_at:    @expires_at,
      client_id:     @client_id,
      verify_ssl:    @verify_ssl
    }
  end

  def ping
    Morpheus::PingInterface.new(common_interface_options).setopts(@options)
  end

  def setup
    Morpheus::SetupInterface.new(common_interface_options).setopts(@options)
  end

  def auth
    Morpheus::AuthInterface.new({url: @base_url, client_id: @client_id, verify_ssl: @verify_ssl}).setopts(@options)
  end

  def forgot
    Morpheus::ForgotPasswordInterface.new(common_interface_options).setopts(@options)
  end

  def whoami
    Morpheus::WhoamiInterface.new(common_interface_options).setopts(@options)
  end

  def search
    Morpheus::SearchInterface.new(common_interface_options).setopts(@options)
  end

  def user_settings
    Morpheus::UserSettingsInterface.new(common_interface_options).setopts(@options)
  end

  def dashboard
    Morpheus::DashboardInterface.new(common_interface_options).setopts(@options)
  end

  def activity
    Morpheus::ActivityInterface.new(common_interface_options).setopts(@options)
  end

  def options
    Morpheus::OptionsInterface.new(common_interface_options).setopts(@options)
  end

  def groups
    Morpheus::GroupsInterface.new(common_interface_options).setopts(@options)
  end

  def account_groups
    Morpheus::AccountGroupsInterface.new(common_interface_options).setopts(@options)
  end

  def clouds
    Morpheus::CloudsInterface.new(common_interface_options).setopts(@options)
  end

  def cloud_datastores
    Morpheus::CloudDatastoresInterface.new(common_interface_options).setopts(@options)
  end

  def cloud_resource_pools
    Morpheus::CloudResourcePoolsInterface.new(common_interface_options).setopts(@options)
  end

  def resource_pool_groups
    Morpheus::ResourcePoolGroupsInterface.new(common_interface_options).setopts(@options)
  end

  def cloud_folders
    Morpheus::CloudFoldersInterface.new(common_interface_options).setopts(@options)
  end

  def datastores
    Morpheus::DatastoresInterface.new(common_interface_options).setopts(@options)
  end

  def servers
    Morpheus::ServersInterface.new(common_interface_options).setopts(@options)
  end

  def server_devices
    Morpheus::ServerDevicesInterface.new(common_interface_options).setopts(@options)
  end

  def instances
    Morpheus::InstancesInterface.new(common_interface_options).setopts(@options)
  end

  def appliance_settings
    Morpheus::ApplianceSettingsInterface.new(common_interface_options).setopts(@options)
  end

  def provisioning_settings
    Morpheus::ProvisioningSettingsInterface.new(common_interface_options).setopts(@options)
  end

  def provisioning_licenses
    Morpheus::ProvisioningLicensesInterface.new(common_interface_options).setopts(@options)
  end

  def provisioning_license_types
    Morpheus::ProvisioningLicenseTypesInterface.new(common_interface_options).setopts(@options)
  end

  def containers
    Morpheus::ContainersInterface.new(common_interface_options).setopts(@options)
  end

  def instance_types
    Morpheus::InstanceTypesInterface.new(common_interface_options).setopts(@options)
  end

  def integrations
    Morpheus::IntegrationsInterface.new(common_interface_options).setopts(@options)
  end

  def integration_types
    Morpheus::IntegrationTypesInterface.new(common_interface_options).setopts(@options)
  end

  def jobs
    Morpheus::JobsInterface.new(common_interface_options).setopts(@options)
  end

  def server_types
    Morpheus::ServerTypesInterface.new(common_interface_options).setopts(@options)
  end

  def provision_types
    Morpheus::ProvisionTypesInterface.new(common_interface_options).setopts(@options)
  end

  def service_plans
    Morpheus::ServicePlansInterface.new(common_interface_options).setopts(@options)
  end

  def price_sets
    Morpheus::PriceSetsInterface.new(common_interface_options).setopts(@options)
  end

  def prices
    Morpheus::PricesInterface.new(common_interface_options).setopts(@options)
  end

  def load_balancers
    Morpheus::LoadBalancersInterface.new(common_interface_options).setopts(@options)
  end

  def load_balancer_types
    Morpheus::LoadBalancerTypesInterface.new(common_interface_options).setopts(@options)
  end

  def load_balancer_virtual_servers
    Morpheus::LoadBalancerVirtualServersInterface.new(common_interface_options).setopts(@options)
  end

  def load_balancer_pools
    Morpheus::LoadBalancerPoolsInterface.new(common_interface_options).setopts(@options)
  end

  def load_balancer_pools_secondary
    Morpheus::LoadBalancerPoolsSecondaryInterface.new(common_interface_options).setopts(@options)
  end

  def load_balancer_profiles
    Morpheus::LoadBalancerProfilesInterface.new(common_interface_options).setopts(@options)
  end

  def load_balancer_monitors
    Morpheus::LoadBalancerMonitorsInterface.new(common_interface_options).setopts(@options)
  end

  def load_balancer_pool_nodes
    Morpheus::LoadBalancerPoolNodesInterface.new(common_interface_options).setopts(@options)
  end

  def tasks
    Morpheus::TasksInterface.new(common_interface_options).setopts(@options)
  end

  def task_sets
    Morpheus::TaskSetsInterface.new(common_interface_options).setopts(@options)
  end

  def virtual_images
    Morpheus::VirtualImagesInterface.new(common_interface_options).setopts(@options)
  end

  def apps
    Morpheus::AppsInterface.new(common_interface_options).setopts(@options)
  end

  def blueprints
    Morpheus::BlueprintsInterface.new(common_interface_options).setopts(@options)
  end

  def deploy
    Morpheus::DeployInterface.new(common_interface_options).setopts(@options)
  end

  def deployments
    Morpheus::DeploymentsInterface.new(common_interface_options).setopts(@options)
  end

  def security_groups
    Morpheus::SecurityGroupsInterface.new(common_interface_options).setopts(@options)
  end

  def security_group_rules
    Morpheus::SecurityGroupRulesInterface.new(common_interface_options).setopts(@options)
  end

  def clusters
    Morpheus::ClustersInterface.new(common_interface_options).setopts(@options)
  end

  def accounts
    Morpheus::AccountsInterface.new(common_interface_options).setopts(@options)
  end

  def approvals
    Morpheus::ApprovalsInterface.new(common_interface_options).setopts(@options)
  end

  def users
    Morpheus::UsersInterface.new(common_interface_options).setopts(@options)
  end

  def account_users
    Morpheus::AccountUsersInterface.new(common_interface_options).setopts(@options)
  end

  def user_groups
    Morpheus::UserGroupsInterface.new(common_interface_options).setopts(@options)
  end

  def user_sources
    Morpheus::UserSourcesInterface.new(common_interface_options).setopts(@options)
  end

  def logs
    Morpheus::LogsInterface.new(common_interface_options).setopts(@options)
  end

  def roles
    Morpheus::RolesInterface.new(common_interface_options).setopts(@options)
  end

  def key_pairs
    Morpheus::KeyPairsInterface.new(common_interface_options).setopts(@options)
  end

  def certificates
    Morpheus::CertificatesInterface.new(common_interface_options).setopts(@options)
  end

  def certificate_types
    Morpheus::CertificateTypesInterface.new(common_interface_options).setopts(@options)
  end

  def license
    Morpheus::LicenseInterface.new(common_interface_options).setopts(@options)
  end

  def option_types
    Morpheus::OptionTypesInterface.new(common_interface_options).setopts(@options)
  end

  def option_type_lists
    Morpheus::OptionTypeListsInterface.new(common_interface_options).setopts(@options)
  end

  def option_type_forms
    Morpheus::OptionTypeFormsInterface.new(common_interface_options).setopts(@options)
  end

  def scale_thresholds
    Morpheus::ScaleThresholdsInterface.new(common_interface_options).setopts(@options)
  end

  def power_schedules
    Morpheus::PowerSchedulesInterface.new(common_interface_options).setopts(@options)
  end

  def execute_schedules
    Morpheus::ExecuteSchedulesInterface.new(common_interface_options).setopts(@options)
  end

  def monitoring
    Morpheus::MonitoringInterface.new(common_interface_options).setopts(@options)
  end

  # def checks
  #   # Morpheus::MonitoringChecksInterface.new(common_interface_options).setopts(@options)
  #   monitoring.checks
  # end

  # def incidents
  #   # Morpheus::MonitoringIncidentsInterface.new(common_interface_options).setopts(@options)
  #   monitoring.incidents
  # end

  def policies
    Morpheus::PoliciesInterface.new(common_interface_options).setopts(@options)
  end

  def group_policies
    Morpheus::GroupPoliciesInterface.new(common_interface_options).setopts(@options)
  end

  def cloud_policies
    Morpheus::CloudPoliciesInterface.new(common_interface_options).setopts(@options)
  end

  def networks
    Morpheus::NetworksInterface.new(common_interface_options).setopts(@options)
  end

  def network_types
    Morpheus::NetworkTypesInterface.new(common_interface_options).setopts(@options)
  end

  def subnets
    Morpheus::SubnetsInterface.new(common_interface_options).setopts(@options)
  end

  def subnet_types
    Morpheus::SubnetTypesInterface.new(common_interface_options).setopts(@options)
  end

  def network_groups
    Morpheus::NetworkGroupsInterface.new(common_interface_options).setopts(@options)
  end

  def network_pools
    Morpheus::NetworkPoolsInterface.new(common_interface_options).setopts(@options)
  end

  def network_pool_ips
    Morpheus::NetworkPoolIpsInterface.new(common_interface_options).setopts(@options)
  end

  def network_routers
    Morpheus::NetworkRoutersInterface.new(common_interface_options).setopts(@options)
  end

  def network_services
    Morpheus::NetworkServicesInterface.new(common_interface_options).setopts(@options)
  end

  # def network_service_types
  #   Morpheus::NetworkServiceTypesInterface.new(common_interface_options).setopts(@options)
  # end

  def network_security_servers
    Morpheus::NetworkSecurityServersInterface.new(common_interface_options).setopts(@options)
  end

  def network_security_server_types
    Morpheus::NetworkSecurityServerTypesInterface.new(common_interface_options).setopts(@options)
  end

  def network_pool_servers
    Morpheus::NetworkPoolServersInterface.new(common_interface_options).setopts(@options)
  end

  def network_pool_server_types
    Morpheus::NetworkPoolServerTypesInterface.new(common_interface_options).setopts(@options)
  end

  def network_domains
    Morpheus::NetworkDomainsInterface.new(common_interface_options).setopts(@options)
  end

  def network_domain_records
    Morpheus::NetworkDomainRecordsInterface.new(common_interface_options).setopts(@options)
  end

  def network_proxies
    Morpheus::NetworkProxiesInterface.new(common_interface_options).setopts(@options)
  end

  def archive_buckets
    Morpheus::ArchiveBucketsInterface.new(common_interface_options).setopts(@options)
  end

  def archive_files
    Morpheus::ArchiveFilesInterface.new(common_interface_options).setopts(@options)
  end

  def image_builder
    Morpheus::ImageBuilderInterface.new(common_interface_options).setopts(@options)
  end

  def storage_providers
    Morpheus::StorageProvidersInterface.new(common_interface_options).setopts(@options)
  end

  def storage_servers
    Morpheus::StorageServersInterface.new(common_interface_options).setopts(@options)
  end

  def storage_server_types
    Morpheus::StorageServerTypesInterface.new(common_interface_options).setopts(@options)
  end

  def storage_volumes
    Morpheus::StorageVolumesInterface.new(common_interface_options).setopts(@options)
  end

  def storage_volume_types
    Morpheus::StorageVolumeTypesInterface.new(common_interface_options).setopts(@options)
  end

  def storage_datastores
    Morpheus::StorageDatastoresInterface.new(common_interface_options).setopts(@options)
  end

  def library_instance_types
    Morpheus::LibraryInstanceTypesInterface.new(common_interface_options).setopts(@options)
  end

  def library_layouts
    Morpheus::LibraryLayoutsInterface.new(common_interface_options).setopts(@options)
  end

  def library_container_upgrades
    Morpheus::LibraryContainerUpgradesInterface.new(common_interface_options).setopts(@options)
  end

  def library_container_types
    Morpheus::LibraryContainerTypesInterface.new(common_interface_options).setopts(@options)
  end

  def library_container_scripts
    Morpheus::LibraryContainerScriptsInterface.new(common_interface_options).setopts(@options)
  end

  def library_container_templates
    Morpheus::LibraryContainerTemplatesInterface.new(common_interface_options).setopts(@options)
  end

  def library_cluster_layouts
    Morpheus::LibraryClusterLayoutsInterface.new(common_interface_options).setopts(@options)
  end

  def library_cluster_packages
    Morpheus::LibraryClusterPackagesInterface.new(common_interface_options).setopts(@options)
  end

  def library_spec_templates
    Morpheus::LibrarySpecTemplatesInterface.new(common_interface_options).setopts(@options)
  end

  def library_spec_template_types
    Morpheus::LibrarySpecTemplateTypesInterface.new(common_interface_options).setopts(@options)
  end

  def packages
    Morpheus::PackagesInterface.new(common_interface_options).setopts(@options)
  end

  def plugins
    Morpheus::PluginsInterface.new(common_interface_options).setopts(@options)
  end

  def cypher
    Morpheus::CypherInterface.new(common_interface_options).setopts(@options)
  end

  def old_cypher
    Morpheus::OldCypherInterface.new(common_interface_options).setopts(@options)
  end

  def execution_request
    Morpheus::ExecutionRequestInterface.new(common_interface_options).setopts(@options)
  end

  def file_copy_request
    Morpheus::FileCopyRequestInterface.new(common_interface_options).setopts(@options)
  end

  def processes
    Morpheus::ProcessesInterface.new(common_interface_options).setopts(@options)
  end

  def reports
    Morpheus::ReportsInterface.new(common_interface_options).setopts(@options)
  end

  def environments
    Morpheus::EnvironmentsInterface.new(common_interface_options).setopts(@options)
  end

  def backup_settings
    Morpheus::BackupSettingsInterface.new(common_interface_options).setopts(@options)
  end

  def guidance_settings
    Morpheus::GuidanceSettingsInterface.new(common_interface_options).setopts(@options)
  end

  def log_settings
    Morpheus::LogSettingsInterface.new(common_interface_options).setopts(@options)
  end

  def monitoring_settings
    Morpheus::MonitoringSettingsInterface.new(common_interface_options).setopts(@options)
  end

  def whitelabel_settings
    Morpheus::WhitelabelSettingsInterface.new(common_interface_options).setopts(@options)
  end

  def wiki
    Morpheus::WikiInterface.new(common_interface_options).setopts(@options)
  end

  def health
    Morpheus::HealthInterface.new(common_interface_options).setopts(@options)
  end

  def hub
    Morpheus::HubInterface.new(common_interface_options).setopts(@options)
  end

  def audit
    Morpheus::AuditInterface.new(common_interface_options).setopts(@options)
  end

  def budgets
    Morpheus::BudgetsInterface.new(common_interface_options).setopts(@options)
  end

  def invoices
    Morpheus::InvoicesInterface.new(common_interface_options).setopts(@options)
  end

  def invoice_line_items
    Morpheus::InvoiceLineItemsInterface.new(common_interface_options).setopts(@options)
  end

  def guidance
    Morpheus::GuidanceInterface.new(common_interface_options).setopts(@options)
  end

  def projects
    Morpheus::ProjectsInterface.new(common_interface_options).setopts(@options)
  end

  def backups
    Morpheus::BackupsInterface.new(common_interface_options).setopts(@options)
  end

  def backup_jobs
    Morpheus::BackupJobsInterface.new(common_interface_options).setopts(@options)
  end

  def backup_results
    Morpheus::BackupResultsInterface.new(common_interface_options).setopts(@options)
  end

  def backup_restores
    Morpheus::BackupRestoresInterface.new(common_interface_options).setopts(@options)
  end

  def backup_services
    Morpheus::BackupServicesInterface.new(common_interface_options).setopts(@options)
  end

  def backup_service_types
    Morpheus::BackupServiceTypesInterface.new(common_interface_options).setopts(@options)
  end

  def backup_types
    Morpheus::BackupTypesInterface.new(common_interface_options).setopts(@options)
  end

  def catalog_item_types
    Morpheus::CatalogItemTypesInterface.new(common_interface_options).setopts(@options)
  end

  def catalog
    Morpheus::ServiceCatalogInterface.new(common_interface_options).setopts(@options)
  end

  def usage
    Morpheus::UsageInterface.new(common_interface_options).setopts(@options)
  end

  def billing
    Morpheus::BillingInterface.new(common_interface_options).setopts(@options)
  end

  def vdi
    Morpheus::VdiInterface.new(common_interface_options).setopts(@options)
  end

  def vdi_pools
    Morpheus::VdiPoolsInterface.new(common_interface_options).setopts(@options)
  end

  def vdi_allocations
    Morpheus::VdiAllocationsInterface.new(common_interface_options).setopts(@options)
  end

  def vdi_apps
    Morpheus::VdiAppsInterface.new(common_interface_options).setopts(@options)
  end

  def vdi_gateways
    Morpheus::VdiGatewaysInterface.new(common_interface_options).setopts(@options)
  end

  def network_servers
    Morpheus::NetworkServersInterface.new(common_interface_options).setopts(@options)
  end

  def network_server_types
    Morpheus::NetworkServerTypesInterface.new(common_interface_options).setopts(@options)
  end

  def network_server_groups
    Morpheus::NetworkServerGroupsInterface.new(common_interface_options).setopts(@options)
  end

  def network_server_services
    Morpheus::NetworkServerServicesInterface.new(common_interface_options).setopts(@options)
  end

  def network_resource_types
    Morpheus::NetworkResourceTypesInterface.new(common_interface_options).setopts(@options)
  end

  def network_edge_clusters
    Morpheus::NetworkEdgeClustersInterface.new(common_interface_options).setopts(@options)
  end

  def network_dhcp_servers
    Morpheus::NetworkDhcpServersInterface.new(common_interface_options).setopts(@options)
  end

  def network_dhcp_relays
    Morpheus::NetworkDhcpRelaysInterface.new(common_interface_options).setopts(@options)
  end
  
  def network_static_routes
    Morpheus::NetworkStaticRoutesInterface.new(common_interface_options).setopts(@options)
  end

  def snapshots
    Morpheus::SnapshotsInterface.new(common_interface_options).setopts(@options)
  end

  def credentials
    Morpheus::CredentialsInterface.new(common_interface_options).setopts(@options)
  end

  def credential_types
    Morpheus::CredentialTypesInterface.new(common_interface_options).setopts(@options)
  end

  def clients
    Morpheus::ClientsInterface.new(common_interface_options).setopts(@options)
  end

  def security_packages
    Morpheus::SecurityPackagesInterface.new(common_interface_options).setopts(@options)
  end

  def security_package_types
    Morpheus::SecurityPackageTypesInterface.new(common_interface_options).setopts(@options)
  end

  def security_scans
    Morpheus::SecurityScansInterface.new(common_interface_options).setopts(@options)
  end

  def network_floating_ips
    Morpheus::NetworkFloatingIpsInterface.new(common_interface_options).setopts(@options)
  end
  
  def email_templates
    Morpheus::EmailTemplatesInterface.new(common_interface_options).setopts(@options)
  end

  def library_operating_systems
    Morpheus::LibraryOperatingSystemsInterface.new(common_interface_options).setopts(@options)
  end

  def migrations
    Morpheus::MigrationsInterface.new(common_interface_options).setopts(@options)
  end

  def rest(endpoint)
    Morpheus::RestInterface.new(common_interface_options).setopts(@options.merge({base_path: "#{@base_url}/api/#{endpoint}"}))
  end

  def interface(type)
    type = type.to_s.singularize.underscore
    interface_name = type.pluralize
    if !respond_to?(interface_name)
      raise "#{self.class} has not defined an interface method named '#{interface_name}'"
    end
    return send(interface_name)
  end
  alias :get_interface :interface

  # add new interfaces here

  protected

  def validate_id!(id, param_name='id')
    if !(id.is_a?(String) || id.is_a?(Integer))
      raise "#{self.class} passed an invalid #{param_name}! Expected String or Integer and got (#{id.class}) #{id.inspect}"
    elsif id.to_s.strip.empty?
      raise "#{self.class} passed a blank #{param_name}!"
    end
    return true
  end

end
