require 'morpheus/api/api_client'

class Morpheus::InstancesInterface < Morpheus::APIClient

  def base_path
    "/api/instances"
  end

  def list(params={}, headers={})
    execute(method: :get, url: "#{base_path}", params: params, headers: headers)
  end

  def get(id, params={}, headers={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{id}", params: params, headers: headers)
  end

  def get_envs(id, params={})
    url = "#{@base_url}/api/instances/#{id}/envs"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create_env(id, payload={})
    url = "#{@base_url}/api/instances/#{id}/envs"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def del_env(id, name)
    url = "#{@base_url}/api/instances/#{id}/envs/#{name}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers}
    execute(opts)
  end

  def create(payload)
    url = "#{@base_url}/api/instances"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(id, payload)
    url = "#{@base_url}/api/instances/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(id, params = {})
    url = "#{@base_url}/api/instances/#{id}"
    headers = {:params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers}
    execute(opts)
  end

  def extend_shutdown(id, params={}, payload={}, headers={})
    execute(method: :put, url: "#{base_path}/#{id}/extend-shutdown", params: params, payload: payload, headers: headers)
  end

  def extend_expiration(id, params={}, payload={}, headers={})
    execute(method: :put, url: "#{base_path}/#{id}/extend-expiration", params: params, payload: payload, headers: headers)
  end

  def cancel_shutdown(id, params={}, payload={}, headers={})
    execute(method: :put, url: "#{base_path}/#{id}/cancel-shutdown", params: params, payload: payload, headers: headers)
  end

  def cancel_expiration(id, params={}, payload={}, headers={})
    execute(method: :put, url: "#{base_path}/#{id}/cancel-expiration", params: params, payload: payload, headers: headers)
  end

  def cancel_removal(id, params={}, payload={}, headers={})
    execute(method: :put, url: "#{base_path}/#{id}/cancel-removal", params: params, payload: payload, headers: headers)
  end

  def stop(id, params={})
    url = "#{@base_url}/api/instances/#{id}/stop"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts)
  end

  def start(id, params={})
    url = "#{@base_url}/api/instances/#{id}/start"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts)
  end

  def restart(id, params={})
    url = "#{@base_url}/api/instances/#{id}/restart"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts)
  end

  def suspend(id, params={})
    url = "#{@base_url}/api/instances/suspend"
    if id.is_a?(Array)
      params['ids'] = id
    else
      url = "#{@base_url}/api/instances/#{id}/suspend"
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts)
  end

  def eject(id, params={})
    url = "#{@base_url}/api/instances/eject"
    if id.is_a?(Array)
      params['ids'] = id
    else
      url = "#{@base_url}/api/instances/#{id}/eject"
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts)
  end

  def available_actions(id)
    url, params = "", {}
    if id.is_a?(Array)
      url = "#{@base_url}/api/instances/actions"
      params = {ids: id}
    else
      url = "#{@base_url}/api/instances/#{id}/actions"
      params = {}
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def action(id, action_code, resource_pool_id=nil, payload={})
    url, params = "", {}
    if id.is_a?(Array)
      url = "#{@base_url}/api/instances/action"
      params = {ids: id, code: action_code}
    else
      url = "#{@base_url}/api/instances/#{id}/action"
      params = {code: action_code}
    end
    unless resource_pool_id
      params['resource_pool_id'] = resource_pool_id
    end
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def volumes(id)
    url = "#{@base_url}/api/instances/#{id}/volumes"
    headers = { :params => {},:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def resize(id,payload)
    url = "#{@base_url}/api/instances/#{id}/resize"
    headers = { :params => {},:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers,payload: payload.to_json}
    execute(opts)
  end

  def workflow(id,task_set_id,payload)
    url = "#{@base_url}/api/instances/#{id}/workflow"
    headers = { :params => {:workflowId => task_set_id},:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers,payload: payload.to_json}
    execute(opts)
  end

  def backup(id, payload={})
    url = "#{@base_url}/api/instances/#{id}/backup"
    headers = {:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def backups(id, params)
    url = "#{@base_url}/api/instances/#{id}/backups"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def clone(id, payload)
    url = "#{@base_url}/api/instances/#{id}/clone"
    headers = {:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def clone_image(id, payload)
    url = "#{@base_url}/api/instances/#{id}/clone-image"
    headers = {:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def lock(id, payload)
    url = "#{@base_url}/api/instances/#{id}/lock"
    headers = {:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def unlock(id, payload)
    url = "#{@base_url}/api/instances/#{id}/unlock"
    headers = {:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def firewall_disable(id)
    url = "#{@base_url}/api/instances/#{id}/security-groups/disable"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts)
  end

  def firewall_enable(id)
    url = "#{@base_url}/api/instances/#{id}/security-groups/enable"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts)
  end

  def security_groups(id)
    url = "#{@base_url}/api/instances/#{id}/security-groups"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def apply_security_groups(id, payload)
    url = "#{@base_url}/api/instances/#{id}/security-groups"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end
  
  def snapshot(id, payload={})
    url = "#{@base_url}/api/instances/#{id}/snapshot"
    headers = {:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def snapshots(instance_id, params={})
    url = "#{@base_url}/api/instances/#{instance_id}/snapshots"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def import_snapshot(id, params={}, payload={})
    url = "#{@base_url}/api/instances/#{id}/import-snapshot"
    headers = {:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def revert_to_snapshot(id, snapshot_id, payload={})
    url = "#{@base_url}/api/instances/#{id}/revert-snapshot/#{snapshot_id}"
    headers = {:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def remove_all_container_snapshots(id, container_id, payload={})
    url = "#{@base_url}/api/instances/#{id}/delete-container-snapshots/#{container_id}"
    headers = {:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def remove_all_instance_snapshots(id, payload={})
    url = "#{@base_url}/api/instances/#{id}/delete-all-snapshots"
    headers = {:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def create_linked_clone(id, snapshot_id, payload={})
    url = "#{@base_url}/api/instances/#{id}/linked-clone/#{snapshot_id}"
    headers = {:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def service_plans(params={})
    url = "#{@base_url}/api/instances/service-plans"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def containers(instance_id, params={})
    url = "#{@base_url}/api/instances/#{instance_id}/containers"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def threshold(id, params={})
    url = "#{@base_url}/api/instances/#{id}/threshold"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def update_threshold(id, payload)
    url = "#{@base_url}/api/instances/#{id}/threshold"
    headers = {authorization: "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def list_schedules(id, params={}, headers={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{id}/schedules", params: params, headers: headers)
  end

  def get_schedule(id, schedule_id, params={}, headers={})
    validate_id!(id) && validate_id!(schedule_id, 'schedule_id')
    execute(method: :get, url: "#{base_path}/#{id}/schedules/#{schedule_id}", params: params, headers: headers)
  end

  def create_schedule(id, payload, params={}, headers={})
    validate_id!(id)
    execute(method: :post, url: "#{base_path}/#{id}/schedules", params: params, payload: payload, headers: headers)
  end

  def update_schedule(id, schedule_id, payload, params={}, headers={})
    validate_id!(id) && validate_id!(schedule_id, 'schedule_id')
    execute(method: :put, url: "#{base_path}/#{id}/schedules/#{schedule_id}", params: params, payload: payload, headers: headers)
  end

  def destroy_schedule(id, schedule_id, params = {}, headers={})
    validate_id!(id) && validate_id!(schedule_id, 'schedule_id')
    execute(method: :delete, url: "#{base_path}/#{id}/schedules/#{schedule_id}", params: params, headers: headers)
  end

  def update_load_balancer(id, payload)
    url = "#{@base_url}/api/instances/#{id}/load-balancer"
    headers = {authorization: "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def remove_load_balancer(id, payload={})
    url = "#{@base_url}/api/instances/#{id}/load-balancer"
    headers = {authorization: "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def history(id, params={})
    url = "#{@base_url}/api/instances/#{id}/history"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def history_details(id, process_id, params={})
    url = "#{@base_url}/api/instances/#{id}/history/#{process_id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def history_event_details(id, process_event_id, params={})
    url = "#{@base_url}/api/instances/#{id}/history/events/#{process_event_id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def wiki(id, params)
    url = "#{@base_url}/api/instances/#{id}/wiki"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def update_wiki(id, payload)
    url = "#{@base_url}/api/instances/#{id}/wiki"
    headers = {authorization: "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update_network_label(network_id, instance_id, payload)
    url = "#{@base_url}/api/instances/#{instance_id}/networkInterfaces/#{network_id}"
    headers = {authorization: "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def deploys(id, params)
    # todo: make this plural??
    execute(method: :get, url: "/api/instances/#{id}/deploy", params: params)
  end

  def refresh(id, params, payload)
    url = "#{@base_url}/api/instances/#{id}/refresh"
    headers = {:params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def prepare_apply(id, params={})
    url = "#{@base_url}/api/instances/#{id}/prepare-apply"
    headers = {:params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def validate_apply(id, params, payload)
    url = "#{@base_url}/api/instances/#{id}/validate-apply"
    headers = {:params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def apply(id, params, payload)
    url = "#{@base_url}/api/instances/#{id}/apply"
    headers = {:params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def state(id, params={})
    url = "#{@base_url}/api/instances/#{id}/state"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def remove_from_control(ids, params={})
    url = "#{@base_url}/api/instances/remove-from-control"
    payload = { ids: ids }
    headers = { :params => params,:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

end
