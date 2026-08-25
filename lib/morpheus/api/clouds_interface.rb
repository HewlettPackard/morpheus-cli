require 'morpheus/api/api_client'

class Morpheus::CloudsInterface < Morpheus::APIClient

  def base_path
    "/api/zones"
  end

  def cloud_types(params={})
    url = "#{@base_url}/api/zone-types"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def cloud_type(params)
    url = "#{@base_url}/api/zone-types"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }

    if params.is_a?(Hash)
      headers[:params].merge!(params)
    elsif params.is_a?(Numeric)
      url = "#{@base_url}/api/zone-types/#{params}"
    elsif params.is_a?(String)
      headers[:params]['name'] = params
    end
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def get(id, params={})
    validate_id!(id)
    url = "#{@base_url}/api/zones/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def list(params={})
    url = "#{@base_url}/api/zones"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create(payload)
    url = "#{@base_url}/api/zones"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(id, payload)
    url = "#{@base_url}/api/zones/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(id, params={})
    url = "#{@base_url}/api/zones/#{id}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers}
    execute(opts)
  end

  def refresh(id, params={}, payload={})
    url = "#{@base_url}/api/zones/#{id}/refresh"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def sync(id, params={}, payload={})
    url = "#{@base_url}/api/zones/#{id}/sync"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def firewall_disable(id)
    url = "#{@base_url}/api/zones/#{id}/security-groups/disable"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts)
  end

  def firewall_enable(id)
    url = "#{@base_url}/api/zones/#{id}/security-groups/enable"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers}
    execute(opts)
  end

  def security_groups(id)
    url = "#{@base_url}/api/zones/#{id}/security-groups"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def apply_security_groups(id, payload)
    url = "#{@base_url}/api/zones/#{id}/security-groups"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def wiki(id, params)
    url = "#{@base_url}/api/zones/#{id}/wiki"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def update_wiki(id, payload)
    url = "#{@base_url}/api/zones/#{id}/wiki"
    headers = {authorization: "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  # NOT json, multipart file upload
  def update_logo(id, logo_file, dark_logo_file=nil)
    url = "#{@base_url}/api/zones/#{id}/update-logo"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}"}
    payload = {}
    # payload["zone"] = {}
    if logo_file
      # payload["zone"]["logo"] = logo_file
      payload["logo"] = logo_file
    end
    if dark_logo_file
      # payload["instanceType"]["darkLogo"] = dark_logo_file
      payload["darkLogo"] = dark_logo_file
    end
    if logo_file.is_a?(File) || dark_logo_file.is_a?(File)
      payload[:multipart] = true
    else
      headers['Content-Type'] = 'application/x-www-form-urlencoded'
    end
    execute(method: :post, url: url, headers: headers, payload: payload)
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
