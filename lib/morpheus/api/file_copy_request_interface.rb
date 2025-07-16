require 'morpheus/api/api_client'

class Morpheus::FileCopyRequestInterface < Morpheus::APIClient

  def get(id, params={})
    raise "#{self.class}.get() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/file-copy-request/#{id}"
    headers = { :params => params, authorization: "Bearer #{@access_token}"}
    opts = {method: :get, url: url, headers: headers}
    execute(opts)
  end

  def create(local_file, params={})
    # puts "upload_file #{local_file} to destination #{destination}"
    if !local_file.kind_of?(File)
      local_file = File.new(local_file, 'rb')
    end
    url = "#{@base_url}/api/file-copy-request/execute"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/octet-stream'}
    headers[:params][:filename] = File.basename(local_file)
    payload = local_file
    headers['Content-Length'] = local_file.size # File.size(local_file)
    execute(method: :post, url: url, headers: headers, payload: payload)
  end

  def add(local_file, params={})
    # puts "upload_file #{local_file} to destination #{destination}"
    if !local_file.kind_of?(File)
      local_file = File.new(local_file, 'rb')
    end
    url = "#{@base_url}/api/file-copy-request/add"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/octet-stream'}
    headers[:params][:filename] = File.basename(local_file)
    payload = local_file
    headers['Content-Length'] = local_file.size # File.size(local_file)
    execute(method: :post, url: url, headers: headers, payload: payload)
  end

  def execute_against_lease(id, local_file, params)
    # puts "upload_file #{local_file} to destination #{destination}"
    if !local_file.kind_of?(File)
      local_file = File.new(local_file, 'rb')
    end
    url = "#{@base_url}/api/file-copy-request/lease/#{CGI::escape(id)}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/octet-stream'}
    headers[:params][:filename] = File.basename(local_file)
    payload = local_file
    headers['Content-Length'] = local_file.size # File.size(local_file)
    execute(method: :post, url: url, headers: headers, payload: payload)
  end

  def download_file_chunked(id, outfile, params={})
    raise "#{self.class}.download_file() passed a blank id!" if id.to_s == ''
    url = "#{@base_url}/api/file-copy-request/download/#{CGI::escape(id)}"
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

end
