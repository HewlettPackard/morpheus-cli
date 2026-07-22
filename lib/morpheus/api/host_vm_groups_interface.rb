require 'morpheus/api/api_client'

class Morpheus::HostVmGroupsInterface < Morpheus::APIClient

  # MORPH-14136 — CLI wrappers for the host-vm-groups REST surface.
  # Same shape as AffinityGroupsInterface: list/create are cluster-scoped;
  # get/update/destroy take a flat id.

  def list(cluster_id, params={})
    raise "#{self.class}.list() passed a blank cluster_id!" if cluster_id.to_s == ''
    url = "#{@base_url}/api/clusters/#{cluster_id}/host-vm-groups"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def get(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/host-vm-groups/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create(cluster_id, payload)
    raise "#{self.class}.create() passed a blank cluster_id!" if cluster_id.to_s == ''
    url = "#{@base_url}/api/clusters/#{cluster_id}/host-vm-groups"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :post, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def update(id, payload)
    raise "#{self.class}.update() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/host-vm-groups/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :put, url: url, headers: headers, payload: payload.to_json}
    execute(opts)
  end

  def destroy(id, params={})
    raise "#{self.class}.destroy() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/host-vm-groups/#{id}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    opts = {method: :delete, url: url, headers: headers}
    execute(opts)
  end

  def form_options(cluster_id, params={})
    raise "#{self.class}.form_options() passed a blank cluster_id!" if cluster_id.to_s == ''
    url = "#{@base_url}/api/clusters/#{cluster_id}/host-vm-groups/form-options"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

end
