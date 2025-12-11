require 'morpheus/api/rest_interface'

class Morpheus::MigrationsInterface < Morpheus::RestInterface

  def base_path
    "/api/migrations"
  end

  def source_clouds(params={}, headers={})
    execute(method: :get, url: "#{base_path}/source-clouds", params: params, headers: headers)
  end

  def target_clouds(params={}, headers={})
    execute(method: :get, url: "#{base_path}/target-clouds", params: params, headers: headers)
  end

  def source_servers(params={}, headers={})
    execute(method: :get, url: "#{base_path}/source-servers", params: params, headers: headers)
  end

  def source_networks(params={}, headers={})
    execute(method: :get, url: "#{base_path}/source-networks", params: params, headers: headers)
  end

  def target_networks(params={}, headers={})
    execute(method: :get, url: "#{base_path}/target-networks", params: params, headers: headers)
  end

  def source_storage(params={}, headers={})
    execute(method: :get, url: "#{base_path}/source-storage", params: params, headers: headers)
  end

  def target_storage(params={}, headers={})
    execute(method: :get, url: "#{base_path}/target-storage", params: params, headers: headers)
  end

  # def target_pools(params={}, headers={})
  #   execute(method: :get, url: "#{base_path}/target-pools", params: params, headers: headers)
  # end

  # def target_groups(params={}, headers={})
  #   execute(method: :get, url: "#{base_path}/target-groups", params: params, headers: headers)
  # end

  def run(id, payload={}, params={}, headers={})
    execute(method: :post, url: "#{base_path}/#{CGI::escape(id.to_s)}/run", params: params, payload: payload, headers: headers)
  end

end
