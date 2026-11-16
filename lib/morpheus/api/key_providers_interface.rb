require 'morpheus/api/rest_interface'
require 'tempfile'

class Morpheus::KeyProvidersInterface < Morpheus::RestInterface

  def base_path
    "/api/key-providers"
  end

  def dependents(id, params={}, headers={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{CGI::escape(id.to_s)}/dependents", params: params, headers: headers)
  end

  def promote(id, params={}, headers={})
    validate_id!(id)
    execute(method: :put, url: "#{base_path}/#{CGI::escape(id.to_s)}/promote", params: params, headers: headers)
  end

  def rotate(id, params={}, headers={})
    validate_id!(id)
    execute(method: :put, url: "#{base_path}/#{CGI::escape(id.to_s)}/rotate", params: params, headers: headers)
  end

  def discard_pending_version(id, params={}, headers={})
    validate_id!(id)
    execute(method: :put, url: "#{base_path}/#{CGI::escape(id.to_s)}/versions/discard-pending", params: params, headers: headers)
  end

  def delete_version(id, key_version, params={}, headers={})
    validate_id!(id)
    unless key_version.to_s =~ /\A\d+\z/
      raise "#{self.class}.delete_version() passed an invalid key version!"
    end
    execute(method: :delete, url: "#{base_path}/#{CGI::escape(id.to_s)}/versions/#{CGI::escape(key_version.to_s)}", params: params, headers: headers)
  end

  def export(id, passphrase, outfile, params={}, headers={})
    validate_id!(id)
    raise "#{self.class}.export() passed a blank passphrase!" if passphrase.to_s.empty?
    raise "#{self.class}.export() passed a blank outfile!" if outfile.to_s.empty?

    output_path = File.expand_path(outfile)
    raise "outfile is invalid. It is the name of an existing directory: #{outfile}" if Dir.exist?(output_path)

    opts = {
      method: :post,
      url: "#{base_path}/#{CGI::escape(id.to_s)}/export",
      params: params,
      payload: {'passphrase' => passphrase},
      headers: headers,
      parse_json: false,
      # raw_response raises on HTTP errors and keeps the headers that carry the export ID
      raw_response: true
    }
    return execute(opts) if @dry_run

    response = execute(opts, parse_json: false)
    tempfile = Tempfile.new(['key-provider-export-', '.mkpx'], File.dirname(output_path))
    tempfile.binmode
    File.open(response.file.path, 'rb') { |source| IO.copy_stream(source, tempfile) }
    tempfile.flush
    tempfile.fsync
    tempfile.close
    File.rename(tempfile.path, output_path)
    response
  ensure
    tempfile.close! if tempfile
    response.file.close! if response.respond_to?(:file) && response.file
  end

  def import(local_file, passphrase, fields={}, params={}, headers={})
    raise "#{self.class}.import() passed a blank file!" if local_file.to_s.empty?
    raise "#{self.class}.import() passed a blank passphrase!" if passphrase.to_s.empty?

    payload = fields.each_with_object({}) { |(key, value), result| result[key.to_s] = value }
    payload['file'] = local_file
    payload['passphrase'] = passphrase
    payload[:multipart] = true
    opts = {method: :post, url: "#{base_path}/import", params: params, payload: payload, headers: headers}
    return execute(opts) if @dry_run

    File.open(local_file, 'rb') do |file|
      payload['file'] = file
      execute(opts)
    end
  end

end
