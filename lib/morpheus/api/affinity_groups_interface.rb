require 'morpheus/api/api_client'

class Morpheus::AffinityGroupsInterface < Morpheus::APIClient

  # MORPH-14136 — CLI wrappers for the affinity-groups REST surface.
  #
  # Listing and creation are cluster-scoped by design; a rule must always
  # be created against a specific cluster (or cloud). Show, update, delete
  # operate on the flat /api/affinity-groups/{id} endpoints so the CLI can
  # take a rule ID directly.

  def list(cluster_id, params={})
    raise "#{self.class}.list() passed a blank cluster_id!" if cluster_id.to_s == ''
    url = "#{@base_url}/api/clusters/#{cluster_id}/affinity-groups"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def get(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/affinity-groups/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create(cluster_id, payload)
    raise "#{self.class}.create() passed a blank cluster_id!" if cluster_id.to_s == ''
    url = "#{@base_url}/api/clusters/#{cluster_id}/affinity-groups"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(id, payload)
    raise "#{self.class}.update() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/affinity-groups/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(id, params={})
    raise "#{self.class}.destroy() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/affinity-groups/#{id}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers}
    execute(opts)
  end

  def form_options(cluster_id, params={})
    raise "#{self.class}.form_options() passed a blank cluster_id!" if cluster_id.to_s == ''
    url = "#{@base_url}/api/clusters/#{cluster_id}/affinity-groups/form-options"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def violations(params={})
    url = "#{@base_url}/api/affinity-groups/violations"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

end
