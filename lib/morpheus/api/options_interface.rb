require 'morpheus/api/api_client'

class Morpheus::OptionsInterface < Morpheus::APIClient

  def options_for_type(option_type, params={})
    options_for_source(option_type['optionSource'], params, option_type['optionSourceType'])
  end

  def options_for_source(source,params = {}, option_source_type=nil)
    url = "#{@base_url}/api/options/#{source}"
    if option_source_type
      url = "#{@base_url}/api/options/#{option_source_type}/#{source}"
    end
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers, timeout: 180)
  end
end
