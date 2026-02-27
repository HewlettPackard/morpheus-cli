require 'morpheus/api/rest_interface'

class Morpheus::SystemTypesInterface < Morpheus::RestInterface

  def base_path
    "/api/infrastructure/system-types"
  end

  def list_layouts(type_id, params = {})
    execute(method: :get, url: "#{base_path}/#{type_id}/layouts", params: params)
  end

end
