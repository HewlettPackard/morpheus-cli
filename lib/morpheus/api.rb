require 'morpheus/cli/version'
require 'morpheus/cli/errors'
require 'morpheus/rest_client'
require 'morpheus/formatters'
#require 'morpheus/logging'
#require 'term/ansicolor'

# load interfaces
require 'morpheus/api/api_client.rb'
Dir[File.dirname(__FILE__)  + "/api/**/*.rb"].each {|file| require file }
