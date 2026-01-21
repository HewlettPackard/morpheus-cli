require 'morpheus/api/api_client'

class Morpheus::RolesInterface < Morpheus::APIClient

  def get(account_id, id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = build_url(account_id, id)
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def list(account_id, options={})
    url = build_url(account_id)
    params = {}
    if account_id
      params['tenant'] = account_id
    end

    headers = { params: params, authorization: "Bearer #{@access_token}" }
    headers[:params].merge!(options)
    execute(method: :get, url: url, headers: headers)
  end

  def create(account_id, options, params={})
    url = build_url(account_id)
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    execute(method: :post, url: url, headers: headers, payload: payload.to_json, params: params)
  end

  def update(account_id, id, options, params={})
    url = build_url(account_id, id)
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    execute(method: :put, url: url, headers: headers, payload: payload.to_json, params: params)
  end

  def destroy(account_id, id, params={})
    url = build_url(account_id, id)
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers, params: params)
  end

  def update_permission(account_id, id, options)
    url = build_url(account_id, id) + "/update-permission"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def update_instance_type(account_id, id, options)
    url = build_url(account_id, id) + "/update-instance-type"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def update_blueprint(account_id, id, options)
    url = build_url(account_id, id) + "/update-blueprint"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def update_group(account_id, id, options)
    url = build_url(account_id, id) + "/update-group"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def update_cloud(account_id, id, options)
    url = build_url(account_id, id) + "/update-cloud"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def update_catalog_item_type(account_id, id, options)
    url = build_url(account_id, id) + "/update-catalog-item-type"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def update_persona(account_id, id, options)
    url = build_url(account_id, id) + "/update-persona"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def update_vdi_pool(account_id, id, options)
    url = build_url(account_id, id) + "/update-vdi-pool"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def update_report_type(account_id, id, options)
    url = build_url(account_id, id) + "/update-report-type"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def update_task(account_id, id, options)
    url = build_url(account_id, id) + "/update-task"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def update_task_set(account_id, id, options)
    url = build_url(account_id, id) + "/update-task-set"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def validate(account_id, options, params={})
    url = "#{@base_url}/api/roles/validate"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    payload = options
    execute(method: :post, url: url, headers: headers, payload: payload.to_json, params: params)
  end

  private

  def build_url(account_id=nil, role_id=nil)
    url = "#{@base_url}/api"
    if account_id
      #url += "/accounts/#{account_id}/roles"
      url += "/roles"
    else
      url += "/roles"
    end
    if role_id
      url += "/#{role_id}"
    end
    url
  end

end
