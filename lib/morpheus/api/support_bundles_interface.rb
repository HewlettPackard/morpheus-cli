require 'morpheus/api/rest_interface'

class Morpheus::SupportBundlesInterface < Morpheus::RestInterface

  def base_path
    "/api/support-bundles"
  end

  # Download uses chunked streaming to write directly to a file.
  # Follows the same pattern as file_copy_request_interface.rb#download_file_chunked.
  def download(id, outfile, params={})
    raise "#{self.class}.download() passed a blank id!" if id.to_s == ''
    url = "#{base_path}/#{CGI::escape(id.to_s)}/download"
    headers = { params: params }
    opts = {method: :get, url: url, headers: headers, parse_json: false}
    if Dir.exist?(outfile)
      raise "outfile is invalid. It is the name of an existing directory: #{outfile}"
    end
    if @dry_run
      return execute(opts)
    end
    http_response = nil
    begin
      File.open(outfile, 'w') {|f|
        block = proc { |response|
          response.read_body do |chunk|
            f.write chunk
          end
        }
        opts[:block_response] = block
        http_response = execute(opts)
      }
    rescue
      if File.exist?(outfile) && File.file?(outfile)
        File.delete(outfile)
      end
      raise
    end
    return http_response
  end

end
