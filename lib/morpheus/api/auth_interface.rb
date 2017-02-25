require 'morpheus/api/api_client'

class Morpheus::AuthInterface < Morpheus::APIClient

	attr_reader :access_token

	def initialize(base_url, access_token=nil)
		@base_url = base_url
		@access_token = access_token
	end

	def login(username, password)
		@access_token = nil
		url = "#{@base_url}/oauth/token"
		params = {grant_type: 'password', scope:'write', client_id: 'morph-cli', username: username}
		payload = {password: password}
		opts = {method: :post, url: url, headers:{ params: params}, payload: payload, timeout: 10}
		response = execute(opts)
		return response if @dry_run
		@access_token = response['access_token']
		return response
	end

	def logout()
		if @access_token
			# todo: expire the token
		end
		raise "#{self}.logout() is not yet implemented"
	end
end
