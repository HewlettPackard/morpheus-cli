require 'morpheus/api/rest_interface'

class Morpheus::SystemsInterface < Morpheus::RestInterface

  def base_path
    "/api/infrastructure/systems"
  end

end
