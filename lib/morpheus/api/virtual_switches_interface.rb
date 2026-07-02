require 'morpheus/api/rest_interface'

class Morpheus::VirtualSwitchesInterface < Morpheus::RestInterface

  def base_path
    "/api/virtual-switches"
  end

end
