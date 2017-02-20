require 'morpheus/api/api_client'

class Morpheus::RolesInterface < Morpheus::APIClient
	
	def initialize(access_token, refresh_token, expires_at = nil, base_url=nil) 
		@access_token = access_token
		@refresh_token = refresh_token
		@base_url = base_url
		@expires_at = expires_at
	end

	def get(account_id, id)
		raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
		url = build_url(account_id, id)
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		execute(method: :get, url: url, headers: headers)
		execute(method: :get, url: url, headers: headers)
	end

	def list(account_id, options={})
		url = build_url(account_id)
		headers = { params: {}, authorization: "Bearer #{@access_token}" }
		headers[:params].merge!(options)
		execute(method: :get, url: url, headers: headers)
	end

	def create(account_id, options)
		url = build_url(account_id)
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		execute(method: :post, url: url, headers: headers, payload: payload.to_json)
	end

	def update(account_id, id, options)
		url = build_url(account_id, id)
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		execute(method: :put, url: url, headers: headers, payload: payload.to_json)
	end

	def destroy(account_id, id)
		url = build_url(account_id, id)
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		execute(method: :delete, url: url, headers: headers)
	end

	def update_permission(account_id, id, options)
		url = build_url(account_id, id) + "/update-permission"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		execute(method: :put, url: url, headers: headers, payload: payload.to_json)
	end

	def update_instance_type(account_id, id, options)
		url = build_url(account_id, id) + "/update-instance-type"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		execute(method: :put, url: url, headers: headers, payload: payload.to_json)
	end

	def update_group(account_id, id, options)
		url = build_url(account_id, id) + "/update-group"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		execute(method: :put, url: url, headers: headers, payload: payload.to_json)
	end

	def update_cloud(account_id, id, options)
		url = build_url(account_id, id) + "/update-cloud"
		headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
		payload = options
		execute(method: :put, url: url, headers: headers, payload: payload.to_json)
	end

	private

	def build_url(account_id=nil, role_id=nil)
		url = "#{@base_url}/api"
		if account_id
			#url += "/accounts/#{account_id}/roles"
			url += "/roles"
		else
			url += "/roles"
		end
		if role_id
			url += "/#{role_id}"
		end
		url
	end

end
