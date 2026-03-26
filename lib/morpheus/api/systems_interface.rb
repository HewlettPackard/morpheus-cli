require 'morpheus/api/rest_interface'

class Morpheus::SystemsInterface < Morpheus::RestInterface

  def base_path
    "/api/infrastructure/systems"
  end

  def save_uninitialized(payload, params={}, headers={})
    execute(method: :post, url: "#{base_path}/uninitialized", params: params, payload: payload, headers: headers)
  end

  def initialize_system(id, payload={}, params={}, headers={})
    validate_id!(id)
    execute(method: :put, url: "#{base_path}/#{CGI::escape(id.to_s)}/initialize", params: params, payload: payload, headers: headers)
  end

end
