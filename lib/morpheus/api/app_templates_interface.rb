require 'morpheus/api/api_client'

class Morpheus::AppTemplatesInterface < Morpheus::APIClient
  def initialize(access_token, refresh_token,expires_at = nil, base_url=nil) 
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    @expires_at = expires_at
  end

  def get(id)
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/app-templates/#{id}"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def list(params={})
    url = "#{@base_url}/api/app-templates"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def create(payload)
    url = "#{@base_url}/api/app-templates"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def update(id, payload)
    url = "#{@base_url}/api/app-templates/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  # multipart image upload
  def save_image(id, image_file, params={})
    url = "#{@base_url}/api/app-templates/#{id}/image"
    headers = { :params => params, :authorization => "Bearer #{@access_token}"}
    payload = {}
    payload[:templateImage] = image_file
    payload[:multipart] = true
    execute(method: :post, url: url, headers: headers, payload: payload)
  end

  def duplicate(id, payload)
    url = "#{@base_url}/api/app-templates/#{id}/duplicate"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def destroy(id)
    url = "#{@base_url}/api/app-templates/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end

  def list_tiers(params={})
    url = "#{@base_url}/api/app-templates/tiers"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

end
