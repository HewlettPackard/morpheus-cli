require 'morpheus/api/api_client'
require 'http'
require 'zlib'

class Morpheus::VirtualImagesInterface < Morpheus::APIClient

  def virtual_image_types(options={})
    url = "#{@base_url}/api/virtual-image-types"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    if options.is_a?(Hash)
      headers[:params].merge!(options)
    end
    execute(method: :get, url: url, headers: headers)
  end

  def get(options=nil)
    url = "#{@base_url}/api/virtual-images"
    headers = { params: {}, authorization: "Bearer #{@access_token}" }
    if options.is_a?(Hash)
      headers[:params].merge!(options)
    elsif options.is_a?(Numeric)
      url = "#{@base_url}/api/virtual-images/#{options}"
    elsif options.is_a?(String)
      headers[:params]['name'] = options
    end
    execute(method: :get, url: url, headers: headers)
  end

  def list(params={})
    url = "#{@base_url}/api/virtual-images"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def create(payload)
    url = "#{@base_url}/api/virtual-images"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def update(id, payload)
    url = "#{@base_url}/api/virtual-images/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def convert(id, payload)
    url = "#{@base_url}/api/virtual-images/#{id}/convert"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :post, url: url, headers: headers, payload: payload.to_json)
  end

  def destroy(id, params={})
    url = "#{@base_url}/api/virtual-images/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, params: params, headers: headers)
  end

  # multipart file upload
  # def upload(id, image_file)
  #   url = "#{@base_url}/api/virtual-images/#{id}/upload"
  #   headers = { :params => {}, :authorization => "Bearer #{@access_token}"}
  #   payload = {}
  #   payload[:file] = image_file
  #   payload[:multipart] = true
  #   execute(method: :post, url: url, headers: headers, payload: payload)
  # end

  # no multipart
  def upload(id, image_file, filename=nil, do_gzip=false)
    filename = filename || File.basename(image_file)
    url = "#{@base_url}/api/virtual-images/#{id}/upload"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/octet-stream'}
    headers[:params][:filename] = filename
    payload = image_file
    #execute(method: :post, url: url, headers: headers, payload: payload, timeout: 36000)
    
    # Using http.rb instead of RestClient
    # todo: execute() should support :driver
    
    
    http_opts = {}
    if Morpheus::RestClient.ssl_verification_enabled? == false
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http_opts[:ssl_context] = ctx
      # opts[:verify_ssl] = OpenSSL::SSL::VERIFY_NONE
    end
    
    # start_time = Time.now
    query_params = headers.delete(:params) || {}
    file_size = image_file.size
    if File.blockdev?(image_file)
      file_size = `blockdev --getsz '#{File.absolute_path(image_file)}'`.strip().to_i * 512
    end
    if do_gzip
      # http = http.use(:auto_deflate)
      headers['Content-Encoding'] = 'gzip'
      headers['Content-Type'] = 'application/gzip'
      headers['Content-Length'] = file_size
      #headers['Transfer-Encoding'] = 'Chunked'
      query_params['extractedContentLength'] = file_size
      if @dry_run
        return {method: :post, url: url, headers: headers, params: query_params, payload: payload}
      end
      http = HTTP.headers(headers)
      http_opts[:params] = query_params
      
      rd, wr = IO.pipe
      Thread.new {
         gz = Zlib::GzipWriter.new(wr)
         File.open(payload) do |fp|
           while chunk = fp.read(10 * 1024 * 1024) do
             gz.write chunk
           end
         end
         gz.close
      }
      http_opts[:body] = Morpheus::BodyIO.new(rd)
      response = http.post(url, http_opts)
    else
      if @dry_run
        return {method: :post, url: url, headers: headers, params: query_params, payload: payload}
      end
      headers['Content-Length'] = file_size
      http = HTTP.headers(headers)
      http_opts[:params] = query_params
      http_opts[:body] = payload
      response = http.post(url, http_opts)
    end
    # puts "Took #{Time.now.to_i - start_time.to_i}"
    # return response
    return JSON.parse(response.body.to_s)
  end

  def upload_by_url(id, file_url, filename=nil)
    url = "#{@base_url}/api/virtual-images/#{id}/upload"
    headers = { :params => {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/octet-stream'}
    headers[:params][:url] = file_url
    headers[:params][:filename] = filename if filename
    execute(method: :post, url: url, headers: headers, timeout: 172800)
  end

  def destroy_file(id, filename)
    url = "#{@base_url}/api/virtual-images/#{id}/files"
    #url = "#{@base_url}/api/virtual-images/#{id}/files/#{filename}"
    headers = { params: {}, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    headers[:params][:filename] = filename
    execute(method: :delete, url: url, headers: headers)
  end

  def download_chunked(id, outfile, params={})
    raise "#{self.class}.download_chunked() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/virtual-images/#{id}/download"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    opts = {method: :get, url: url, headers: headers}
    # execute(opts, {parse_json: false})
    if Dir.exist?(outfile)
      raise "outfile is invalid. It is the name of an existing directory: #{outfile}"
    end
    # if @verify_ssl == false
    #   opts[:verify_ssl] = OpenSSL::SSL::VERIFY_NONE
    # end
    if @dry_run
      return opts
    end
    http_response = nil
    File.open(outfile, 'w') {|f|
      block = proc { |response|
        response.read_body do |chunk|
          # writing to #{outfile} ..."
          f.write chunk
        end
      }
      opts[:block_response] = block
      http_response = Morpheus::RestClient.execute(opts)
    }
    return http_response
  end

  def location_base_path(resource_id)
    "/api/virtual-images/#{resource_id}/locations"
  end

  def list_locations(resource_id, params={}, headers={})
    validate_id!(resource_id)
    execute(method: :get, url: "#{location_base_path(resource_id)}", params: params, headers: headers)
  end

  def get_location(resource_id, id, params={}, headers={})
    validate_id!(resource_id)
    validate_id!(id)
    execute(method: :get, url: "#{location_base_path(resource_id)}/#{id}", params: params, headers: headers)
  end

  def destroy_location(resource_id, id, params = {}, headers={})
    validate_id!(resource_id)
    validate_id!(id)
    execute(method: :delete, url: "#{location_base_path(resource_id)}/#{id}", params: params, headers: headers)
  end

end
