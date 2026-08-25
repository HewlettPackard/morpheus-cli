require 'morpheus/api/api_client'

# Top-level flat-by-ID affinity group endpoints (MORPH-14136).
#
# Only show/update/delete are exposed at this path. Per
# morpheus-ui ApiV1UrlMappings (rc-9.1.0):
#   "Flat-by-ID endpoints for morpheus-cli -- list/create stay scoped under
#    /clusters/{id}/... and /zones/{id}/...."
# For list/create/form-options use Morpheus::ClustersInterface or
# Morpheus::CloudsInterface. Violations is flat, with scope in the query string.
class Morpheus::AffinityGroupsInterface < Morpheus::APIClient

  def base_path
    "/api/affinity-groups"
  end

  def get(id, params={})
    validate_id!(id)
    url = "#{base_path}/#{id}"
    headers = { params: params, authorization: "******" }
    execute(method: :get, url: url, headers: headers)
  end

  def update(id, payload)
    validate_id!(id)
    url = "#{base_path}/#{id}"
    headers = { :authorization => "******", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def destroy(id, params={})
    validate_id!(id)
    url = "#{base_path}/#{id}"
    headers = { :params => params, :authorization => "******", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end

  alias :delete :destroy

  def violations(params={})
    url = "#{base_path}/violations"
    headers = { params: params, authorization: "******" }
    execute(method: :get, url: url, headers: headers)
  end

end
