require 'morpheus/api/rest_interface'

class Morpheus::StorageVolumesInterface < Morpheus::RestInterface

  def base_path
    "/api/storage-volumes"
  end

  def resize(id,payload)
    url = "#{@base_url}/api/storage-volumes/#{id}/resize"
    headers = { :params => {},:authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  # Transfer ownership of a storage volume to another tenant.
  # The server expects { "storageVolume": { "tenant": { "id": <id> } } }
  # and handles all authorization and business-rule validation.
  def update_tenant(id, payload, params={}, headers={})
    validate_id!(id)
    execute(method: :put, url: "#{base_path}/#{CGI::escape(id.to_s)}", params: params, payload: payload, headers: headers)
  end

end
