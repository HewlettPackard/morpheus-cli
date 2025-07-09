require 'morpheus/api/api_client'

class Morpheus::ServersInterface < Morpheus::APIClient

  def base_path
    "/api/servers"
  end

  def list(params={}, headers={})
    execute(method: :get, url: "#{base_path}", params: params, headers: headers)
  end

  def get(id, params={}, headers={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{id}", params: params, headers: headers)
  end

  def create(options)
    url = "#{@base_url}/api/servers"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(serverId, options)
    url = "#{@base_url}/api/servers/#{serverId}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def stop(serverId,payload = {}, params={})
    url = "#{@base_url}/api/servers/stop"
    if serverId.is_a?(Array)
      params['ids'] = serverId
    else
      url = "#{@base_url}/api/servers/#{serverId}/stop"
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def start(serverId,payload = {}, params = {})
    url = "#{@base_url}/api/servers/start"
    if serverId.is_a?(Array)
      params['ids'] = serverId
    else
      url = "#{@base_url}/api/servers/#{serverId}/start"
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def restart(serverId,payload = {}, params = {})
    url = "#{@base_url}/api/servers/#{serverId}/restart"

    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def make_managed(serverId,payload = {})
    url = "#{@base_url}/api/servers/#{serverId}/install-agent"
    #url = "#{@base_url}/api/servers/#{serverId}/make-managed" # added in 4.1
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def upgrade(serverId,payload = {})
    url = "#{@base_url}/api/servers/#{serverId}/upgrade"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def reprovision(serverId,payload = {})
    url = "#{@base_url}/api/servers/#{serverId}/reprovision"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def reinitialize(serverId,payload = {})
    url = "#{@base_url}/api/servers/#{serverId}/reinitialize"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def assign_account(serverId,payload = {})
    url = "#{@base_url}/api/servers/#{serverId}/assign-account"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def workflow(id,task_set_id,payload)
    url = "#{@base_url}/api/servers/#{id}/workflow"
    headers = { :params => {:workflowId => task_set_id},:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(id, params={})
    url = "#{@base_url}/api/servers/#{id}"
    headers = { :params => params,:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers}
    execute(opts)
  end

  def service_plans(params)
    url = "#{@base_url}/api/servers/service-plans"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def service_plan(options)
    url = "#{@base_url}/api/service-plans"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }

    if options.is_a?(Hash)
      headers[:params].merge!(options)
    elsif options.is_a?(Numeric)
      url = "#{url}/#{options}"
    elsif options.is_a?(String)
      headers[:params]['name'] = options
    end
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def volumes(id)
    url = "#{@base_url}/api/servers/#{id}/volumes"
    headers = { :params => {},:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def resize(id,payload)
    url = "#{@base_url}/api/servers/#{id}/resize"
    headers = { :params => {},:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def wiki(id, params)
    url = "#{@base_url}/api/servers/#{id}/wiki"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def update_wiki(id, payload)
    url = "#{@base_url}/api/servers/#{id}/wiki"
    headers = {authorization: "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end
  
  def snapshots(id, params={})
    url = "#{@base_url}/api/servers/#{id}/snapshots"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def software(id, params={})
    url = "#{@base_url}/api/servers/#{id}/software"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def software_sync(id, payload={}, params={})
    url = "#{@base_url}/api/servers/#{id}/software/sync"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :put, url: url, headers: headers}
    execute(opts)
  end

  def update_network_label(network_id, server_id, payload)
    url = "#{@base_url}/api/servers/#{server_id}/networkInterfaces/#{network_id}"
    headers = {authorization: "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def maintenance(serverId, payload = {}, params = {})
    url = "#{@base_url}/api/servers/#{serverId}/maintenance"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def leave_maintenance(serverId, payload = {}, params = {})
    url = "#{@base_url}/api/servers/#{serverId}/leave-maintenance"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def placement(serverId, payload = {}, params = {})
    url = "#{@base_url}/api/servers/#{serverId}/placement"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def snapshot(serverId, payload = {}, params = {})
    url = "#{@base_url}/api/servers/#{serverId}/snapshot"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end


end
