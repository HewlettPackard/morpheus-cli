require 'morpheus/api/api_client'

class Morpheus::TokensInterface < Morpheus::APIClient

  def base_path
    "/api/tokens"
  end

  def list(params={}, headers={})
    execute(method: :get, url: "#{base_path}", params: params, headers: headers)
  end

  def get(id, params={}, headers={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{id}", params: params, headers: headers)
  end

  def create(payload)
    execute(method: :post, url: "#{base_path}", payload: payload)
  end

  def update(id, payload)
    execute(method: :put, url: "#{base_path}/#{id}", params: params, headers: headers)
  end

  def destroy(id, params={})
    validate_id!(id)
    execute(method: :delete, url: "#{base_path}/#{id}", params: params)
  end
  
  def destroy_all(params={})
    execute(method: :delete, url: "#{base_path}", params: params)
  end

  def available_clients(params={})
    execute(method: :get, url: "#{base_path}/api-clients", params: params)
  end

end
