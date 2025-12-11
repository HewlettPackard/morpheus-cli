# Routes is a module to provide a way to look up routes in the Morpheus UI.
# Examples:
#   Routes.lookup("users") == "/admin/users"
#   Routes.lookup("instances") == "/provisioning/instances"
#
#   puts "All routes", Morpheus::Routes.routes
#
module Morpheus::Routes

  # A static site map for the Morpheus UI.
  # todo: move to YAML or load from api
  SITE_MAP = {
    operations: {
      dashboard: {},
      reports: {},
      analytics: {},
      guidance: {},
      wiki: {},
      budgets: {},
      invoices: {},
      usage: {},
      approvals: {},
      activity: {},
      alarms: {},
    },
    provisioning: {
      instances: {},
      apps: {},
      catalog: {},
      jobs: {},
      executions: {},
      code: {
        respositories: {},
        deployments: {},
        # integrations: {}, # Integrations
      },
    },
    library: {
      automation: [
        "#!tasks",
        "#!workflows",
        "#!thresholds",
        "#!power-schedules",
        "#!execute-schedules",
      ],
      blueprints: [
        "#instance-types",
        "#!instance-type-layouts",
        "#!container-types",
        "#!app-templates", # App Blueprints (blueprints)
        "#!catalog-items",
        "#!compute-type-layouts", # Cluster Layouts
        "#!compute-type-packages", # Cluster Packages
      ],
      :'virtual-images' => {},
      options: [
        "#!forms", # Forms
        "#!option-types", # Inputs
        "#!option-type-lists", # Option Lists
      ],
      templates: [
        "#!specs",
        "#!files",
        "#!scripts",
        "#!security-specs",
      ],
      services: {}, # Integrations

    },
    infrastructure: {
      groups: {},
      clouds: {},
      clusters: {},
      servers: {}, # Hosts (still used for loading by id)
      inventory: [ # Compute
        "#!hosts",
        "#!virtual-machines",
        "#!containers",
        "#!resources",
        "#!bare-metal",
      ],
      networks: {},
      :'load-balancers' => {},
      storage: {
        buckets: {},  
        shares: {},  # File Shares
        volumes: {},  
        :'data-stores' => {}, # ugh, should be datastores
        servers: {}, # Storage Servers
      },
      trust: [
        "#!credentials",
        "#!certificates",
        "#!keypairs",
        "#!services",
      ],
      boot: [
        "#!mappings",
        "#!boot-menus",
        "#!answerfiles",
        "#!boot-images",
        "#!macs",
      ],
    },
    backups: {
      list: {},
      show: {},
      jobs: {},
      history: [
        "#!restores",
      ],
      services: {}
    },
    monitoring: {
      status: {},
      logs: {},
      apps: {},
      checks: {},
      groups: {},
      incidents: {},
      contacts: {},
      :'alert-rules' => {}, 
    },
    tools: {
      cypher: {},
      archives: {
        buckets: {},
      },
      :'image-builder' => {},
      :migrations => {},
      :vdi => {},
    },
    admin: {
      accounts: {}, # Tenants
      :'service-plans' => [
        "#!prices",
        "#!pricesets"
      ],
      roles: {},
      users: {},
      :'user-groups' => {},
      integrations: {},
      policies: {},
      health: ["logs"],
      settings: [
        "#!appliance",
        "#!whitelabel",
        "provisioning",
        "monitoring",
        "backups",
        "logs",
        "#!guidance",
        "environments",
        "software-licenses",
        "#!license",
        "#!utilities"
      ],
    },
    :'user-settings' => {}, # User Settings (Profile)
  } unless defined?(SITE_MAP)

  # A list of routes generated from the site map and cached
  @@routes = nil
  
  # @return an array of well known Morpheus UI routes.
  def self.routes
    if !@@routes
      @@routes = build_routes(SITE_MAP)
    end
    return @@routes
  end

  # lookup a route in the morpheus UI
  # @param path [String] The input to lookup a route for eg. "dashboard"
  # @param id [String] ID indicates the show route is needed for a resource for  cases where it varies ie. backups
  # @return full path like "/operations/dashboard"
  def self.lookup(path, id=nil)
    path = path.to_s
    if path.start_with?("/")
      # absolute path is being looked up
      return path
    else
      # todo: make this smarter, regex, case insensitive, etc
      # find the one with smallest match index

      # map well known aliases
      case(path.dasherize.pluralize)
      # when "forms"
      #   path = "/library/options/#!forms"
      when "inputs"
        path = "/library/options/#!option-types"
      when "option-lists"
        path = "/library/options/#!option-type-lists"
      when "backups"
        path = id ? "/backups/show" : "/backups/list"
      when "backup-jobs"
        path = "/backups/jobs"
      when "backup-results"
        path = "/backups/history"
      when "backup-restores", "restores"
        path = "/backups/history/#!restores"
      when "servers","hosts","vms","virtual-machines"
        # actually should be "/infrastructure/inventory" unless id is passed, show route uses /servers though
        path = "/infrastructure/servers"
      when "computes", "inventories"
        path = "/infrastructure/inventory"
      when "tenants"
        path = "/admin/accounts"
      when "appliance-settings"
        path = "/admin/settings/#!appliance"
      when "whitelabel-settings"
        path = "/admin/settings/#!whitelabel"
      when "provisioning-settings"
        path = "/admin/settings/#!provisioning"
      when "monitoring-settings","monitor-settings"
        path = "/admin/settings/monitoring"
      when "backup-settings"
        path = "/admin/settings/backups"
      when "log-settings"
        path = "/admin/settings/logs"
      when "guidance-settings"
        path = "/admin/settings/#!guidance"
      when "environments"
        path = "/admin/settings/environments"
      when "software-licenses"
        path = "/admin/settings/software-licenses"
      when "license","licenses"
        path = "/admin/settings/#!license"
      end
      # todo: this is weird, fix it so "view license matches license before software-licenses without needing the above alias..
      # dasherize path and attempt to match the plural first
      plural_path = path.pluralize
      paths = [path.dasherize]
      if plural_path != path
        paths.unshift(plural_path.dasherize)
      end

      best_route = nil
      #best_index = nil
      best_prefix_words = nil
      paths.each do |p|
        if best_route.nil?
          self.routes.each do |it|
            match_index = it.index(p)
            if match_index
              prefix_route = match_index == 0 ? "" : it[0..(match_index-1)]
              prefix_words = prefix_route.split("/")
              #if best_index.nil? || match_index < best_index
              if best_prefix_words.nil? || prefix_words.size < best_prefix_words.size
                best_route = it
                #best_index = match_index
                best_prefix_words = prefix_words
              end
            end
          end
        end
      end
      if best_route
        return best_route
      else
        # no match found
        return nil
      end
    end
    
  end

  protected 

  # build_routes constructs an array of routes (paths) 
  # This traversing the route map recursively and appends paths to output
  # @params route_map [Hash] map of routes
  # @params context [String] the current content
  # @params output [Array] the list of route paths being constructed for return
  # @return array like ["/operations", "/operations/dashboard", "/admin", "/etc"]
  def self.build_routes(route_map, context="", output = nil)
    if output.nil?
      output = []
    end
    route_map.each do |k,v|
      leaf_path = "#{context}/#{k}"
      output << leaf_path
      if v.is_a?(Hash)
        build_routes(v, leaf_path, output)
      elsif v.is_a?(Array)
        v.each do |obj|
          if obj.is_a?(Hash)
            build_routes(obj, leaf_path, output)
          elsif obj.is_a?(Symbol) || obj.is_a?(String)
            # route leaf type not handled
            output << "#{leaf_path}/#{obj}"
          else
            # route leaf type not handled
          end
        end
      else
        # route leaf type not handled
      end
    end
    return output
  end

  
end
