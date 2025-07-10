require 'morpheus/api/api_client'

class Morpheus::ClustersInterface < Morpheus::APIClient

  def base_path
    "/api/clusters"
  end

  def list(params={})
    url = base_path
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def get(params={})
    url = base_path
    headers = { params: {}, authorization: "Bearer #{@access_token}" }

    if params.is_a?(Hash)
      headers[:params].merge!(params)
    elsif params.is_a?(Numeric)
      url = "#{base_path}/#{params}"
    elsif params.is_a?(String)
      headers[:params]['name'] = params
    end
    execute(method: :get, url: url, headers: headers)
  end

  def create(payload)
    url = base_path
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def update(id, payload)
    url = "#{base_path}/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def destroy(id, params={})
    url = "#{base_path}/#{id}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end

  alias :delete :destroy

  def cluster_types(params={})
    url = "#{@base_url}/api/cluster-types"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def update_permissions(id, payload)
    url = "#{base_path}/#{id}/permissions"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def list_jobs(id, params={})
    url = "#{base_path}/#{id}/jobs"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def destroy_job(id, job_id=nil, params={}, payload={})
    url = nil
    if job_id.is_a?(Array)
      url = "#{base_path}/#{id}/jobs"
      params['jobId'] = job_id
    elsif job_id.is_a?(Numeric) || job_id.is_a?(String)
      url = "#{base_path}/#{id}/jobs/#{job_id}"
    else
      raise "passed a bad volume_id: #{job_id || '(none)'}" # lazy
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers, payload: payload.to_json)
  end

  def list_masters(id, params={})
    url = "#{base_path}/#{id}/masters"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def list_workers(id, params={})
    url = "#{base_path}/#{id}/workers"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def destroy_worker(id, worker_id, params={})
    url = "#{base_path}/#{id}/servers/#{worker_id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :delete, url: url, headers: headers)
  end

  def update_worker_count(id, params={})
    url = "#{base_path}/#{id}/worker-count"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :put, url: url, headers: headers)
  end

  def get_upgrade_versions(id, params={})
    url = "#{base_path}/#{id}/upgrade-cluster"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def do_cluster_upgrade(id, params={})
    url = "#{base_path}/#{id}/upgrade-cluster"
    headers = { params: params, authorization: "Bearer #{@access_token}", 'Content-Type' => 'application/json'  }
    execute(method: :post, url: url, headers: headers)
  end

  def list_services(id, params={})
    url = "#{base_path}/#{id}/services"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  # this supports multiple ids
  def destroy_service(id, service_id=nil, params={}, payload={})
    url = nil
    if service_id.is_a?(Array)
      url = "#{base_path}/#{id}/services"
      params['serviceId'] = service_id
    elsif service_id.is_a?(Numeric) || service_id.is_a?(String)
      url = "#{base_path}/#{id}/services/#{service_id}"
    else
      raise "passed a bad volume_id: #{service_id || '(none)'}" # lazy
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers, payload: payload.to_json)
  end

  def add_server(id, payload)
    url = "#{base_path}/#{id}/servers"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def list_volumes(id, params={})
    url = "#{base_path}/#{id}/volumes"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  # this supports multiple ids
  def destroy_volume(id, volume_id=nil, params={}, payload={})
    url = nil
    if volume_id.is_a?(Array)
      url = "#{base_path}/#{id}/volumes"
      params['volumeId'] = volume_id
    elsif volume_id.is_a?(Numeric) || volume_id.is_a?(String)
      url = "#{base_path}/#{id}/volumes/#{volume_id}"
    else
      raise "passed a bad volume_id: #{volume_id || '(none)'}" # lazy
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers, payload: payload.to_json)
  end

  alias :delete_volume :destroy_volume

  def list_namespaces(id, params={})
    url = "#{base_path}/#{id}/namespaces"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def get_namespace(id, namespace_id, params={})
    url = "#{base_path}/#{id}/namespaces/#{namespace_id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def create_namespace(id, payload)
    url = "#{base_path}/#{id}/namespaces"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def update_namespace(id, namespace_id, payload)
    url = "#{base_path}/#{id}/namespaces/#{namespace_id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def destroy_namespace(id, namespace_id, params={})
    url = "#{base_path}/#{id}/namespaces/#{namespace_id}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end
  
  alias :delete_namespace :destroy_namespace

  def list_containers(id, params={})
    url = "#{base_path}/#{id}/containers"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def restart_container(id, container_id, params={})
    url = "#{base_path}/#{id}/containers/#{container_id}/restart"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :put, url: url, headers: headers)
  end

  def destroy_container(id, container_id, params={})
    if container_id.is_a?(Array)
      url = "#{base_path}/#{id}/containers"
      params['containerId'] = container_id
    elsif container_id.is_a?(Numeric) || container_id.is_a?(String)
      url = "#{base_path}/#{id}/containers/#{container_id}"
    else
      raise "passed a bad container_id: #{container_id || '(none)'}" # lazy
    end
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :delete, url: url, headers: headers)
  end

  def list_container_groups(id, resource_type, params={})
    url = "#{base_path}/#{id}/#{resource_type}s"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def get_container_group(cluster_id, resource_type, id, params={})
    url = "#{base_path}/#{cluster_id}/#{resource_type}s/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def restart_container_group(id, container_group_id, resource_type, params={})
    url = "#{base_path}/#{id}/#{resource_type}s/#{container_group_id}/restart"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :put, url: url, headers: headers)
  end

  def destroy_container_group(id, container_group_id, resource_type, params={})
    if container_group_id.is_a?(Array)
      url = "#{base_path}/#{id}/#{resource_type}s"
      params['containerGroupId'] = container_group_id
    elsif container_group_id.is_a?(Numeric) || container_group_id.is_a?(String)
      url = "#{base_path}/#{id}/#{resource_type}s/#{container_group_id}"
    else
      raise "passed a bad container_group_id: #{container_group_id || '(none)'}" # lazy
    end
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :delete, url: url, headers: headers)
  end

  def list_datastores(id, params={})
    url = "#{base_path}/#{id}/datastores"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def get_datastore(id, datastore_id, params={})
    url = "#{base_path}/#{id}/datastores/#{datastore_id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def create_datastore(id, payload)
    url = "#{base_path}/#{id}/data-stores"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def update_datastore(id, datastore_id, payload)
    url = "#{base_path}/#{id}/datastores/#{datastore_id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def destroy_datastore(id, datastore_id, params={})
    url = "#{base_path}/#{id}/datastores/#{datastore_id}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end

  def wiki(id, params)
    url = "#{@base_url}/api/clusters/#{id}/wiki"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def update_wiki(id, payload)
    url = "#{@base_url}/api/clusters/#{id}/wiki"
    headers = {authorization: "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def api_config(id, params={})
    url = "#{base_path}/#{id}/api-config"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def history(id, params={})
    url = "#{@base_url}/api/clusters/#{id}/history"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def history_details(id, process_id, params={})
    url = "#{@base_url}/api/clusters/#{id}/history/#{process_id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def history_event_details(id, process_event_id, params={})
    url = "#{@base_url}/api/clusters/#{id}/history/events/#{process_event_id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end


  def apply_template(id, payload={})
    url = "#{@base_url}/api/clusters/#{id}/apply-template"
    
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def refresh(id)
    url = "#{@base_url}/api/clusters/#{id}/refresh"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def list_resources(id, resources, params={})
    url = "#{base_path}/#{id}/#{resources}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def load_balancer_port(params={})
    url = "#{@base_url}/api/clusters/load-balancer-port"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    headers[:params].merge!(params)

    execute(method: :get, url: url, headers: headers)
  end

  def list_affinity_groups(id, params={})
    url = "#{base_path}/#{id}/affinity-groups"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def get_affinity_group(id, affinity_group_id, params={})
    url = "#{base_path}/#{id}/affinity-groups/#{affinity_group_id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def create_affinity_group(id, payload)
    url = "#{base_path}/#{id}/affinity-groups"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def update_affinity_group(id, affinity_group_id, payload)
    url = "#{base_path}/#{id}/affinity-groups/#{affinity_group_id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def destroy_affinity_group(id, affinity_group_id, params={})
    url = "#{base_path}/#{id}/affinity-groups/#{affinity_group_id}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end
  
end
