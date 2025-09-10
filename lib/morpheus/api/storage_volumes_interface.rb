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

end
