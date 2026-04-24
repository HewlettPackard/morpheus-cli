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

  def validate_system(id, params={}, headers={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{CGI::escape(id.to_s)}/validate", params: params, headers: headers)
  end

  def list_compute_server_update_definitions(system_id, server_id, params={}, headers={})
    execute(method: :get, url: "#{base_path}/#{CGI::escape(system_id.to_s)}/servers/#{CGI::escape(server_id.to_s)}/update-definitions", params: params, headers: headers)
  end

  def apply_compute_server_update_definition(system_id, server_id, update_definition_id, payload={}, params={}, headers={})
    execute(method: :post, url: "#{base_path}/#{CGI::escape(system_id.to_s)}/servers/#{CGI::escape(server_id.to_s)}/update-definitions/#{CGI::escape(update_definition_id.to_s)}", params: params, payload: payload, headers: headers)
  end

  def list_storage_server_update_definitions(system_id, server_id, params={}, headers={})
    execute(method: :get, url: "#{base_path}/#{CGI::escape(system_id.to_s)}/storage-servers/#{CGI::escape(server_id.to_s)}/update-definitions", params: params, headers: headers)
  end

  def apply_storage_server_update_definition(system_id, server_id, update_definition_id, payload={}, params={}, headers={})
    execute(method: :post, url: "#{base_path}/#{CGI::escape(system_id.to_s)}/storage-servers/#{CGI::escape(server_id.to_s)}/update-definitions/#{CGI::escape(update_definition_id.to_s)}", params: params, payload: payload, headers: headers)
  end

  def list_network_server_update_definitions(system_id, server_id, params={}, headers={})
    execute(method: :get, url: "#{base_path}/#{CGI::escape(system_id.to_s)}/network-servers/#{CGI::escape(server_id.to_s)}/update-definitions", params: params, headers: headers)
  end

  def apply_network_server_update_definition(system_id, server_id, update_definition_id, payload={}, params={}, headers={})
    execute(method: :post, url: "#{base_path}/#{CGI::escape(system_id.to_s)}/network-servers/#{CGI::escape(server_id.to_s)}/update-definitions/#{CGI::escape(update_definition_id.to_s)}", params: params, payload: payload, headers: headers)
  end

end
