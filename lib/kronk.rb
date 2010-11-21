require 'rubygems'
require 'plist'
require 'json'
require 'nokogiri'
require 'differ'
require 'httpclient'

class Kronk

  # This gem's version.
  VERSION = '1.0.0'


  require 'kronk/file_response'
  require 'kronk/parser'
  require 'kronk/json_parser'
  require 'kronk/plist_parser'
  require 'kronk/xml_parser'


  # Default config file to load. Defaults to ~/.kronk.
  DEFAULT_CONFIG_FILE = File.expand_path "~/.kronk"


  # Default cache file.
  DEFAULT_CACHE_FILE = File.expand_path "~/.kronk_cache"


  # Default Content-Type header to parser mapping.
  DEFAULT_CONTENT_TYPES = {
    'xml'     => 'XMLParser',
    'json'    => 'JSONParser',
    'js'      => 'JSONParser',
    'plist'   => 'PLISTParser'
  }


  # Default config to use.
  DEFAULT_CONFIG = {
    :content_types => DEFAULT_CONTENT_TYPES,
  }


  ##
  # Read the Kronk config hash.

  def self.config
    @config ||= DEFAULT_CONFIG
  end


  ##
  # Load a config file and apply to Kronk.config.

  def self.load_config filepath=DEFAULT_CONFIG_FILE
    conf          = YAML.load_file DEFAULT_CONFIG_FILE
    content_types = conf.delete :content_types

    conf[:content_types].merge!(content_types) if content_types
    self.config.merge! conf
  end


  ##
  # Make requests, parse the responses and compare the data.
  # If the second argument is omitted or is passed :cache, will
  # attempt to compare with the last made request. If there was no last
  # request will compare against nil.
  #
  # Supports the following options:
  # :data:: Hash/String - the data to pass to the http request
  # :headers:: Hash - extra headers to pass to the request
  # :http_method:: Symbol - the http method to use; defaults to :get
  # :query:: Hash/String - data to append to url query
  # :ignore:: String/Array - defines which data points to exclude
  # :ignore_headers:: Bool/String/Array - defines which headers to exclude
  #
  # Returns an Array with the non-matching attributes:
  #
  #   compare "http://host.com/test.json", :cache
  #   [{'foo' => 'bar'},{'foo' => 'baz'}]

  def self.compare query1, query2=:cache, options={}
  end


  ##
  # Make requests, parse and compare the response strings.
  # If the second argument is omitted or is passed :cache, will
  # attempt to compare with the last made request. If there was no last
  # request will compare against empty string.
  #
  # Supports the following options:
  # :data:: Hash/String - the data to pass to the http request
  # :headers:: Hash - extra headers to pass to the request
  # :http_method:: Symbol - the http method to use; defaults to :get
  # :query:: Hash/String - data to append to url query
  # :ignore_headers:: Bool/String/Array - defines which headers to exclude
  #
  # Returns a standard diff string with the non-matching attributes:
  #
  #   diff "http://host.com/test.json", :cache
  #   '- "foo":"bar"\n+ "foo":"baz"'

  def self.diff query1, query2=:cache, options={}
    str1 = retrieve query1, options
    str2 = retrieve query2, options
    # TODO: remove http headers if specified
    Differ.diff_by_line str2, str1
  end


  ##
  # Returns the value from a url, file, or cache as a String.
  # Options supported are:
  # :data:: Hash/String - the data to pass to the http request
  # :headers:: Hash - extra headers to pass to the request
  # :http_method:: Symbol - the http method to use; defaults to :get
  # :query:: Hash/String - data to append to url query

  def self.retrieve query, options={}
  end


  ##
  # Read http response from a file and return a HTTP::Message instance.

  def self.retrieve_file path, options={}
    path = DEFAULT_CACHE_FILE if path == :cache
    HTTP::Message.new_response File.read(path)
  end


  ##
  # Make an http request to the given uri and return a HTTP::Message instance.
  # Supports the following options:
  # :data:: Hash/String - the data to pass to the http request
  # :headers:: Hash - extra headers to pass to the request
  # :http_method:: Symbol - the http method to use; defaults to :get
  # :query:: Hash/String - data to append to url query

  def self.retrieve_uri uri, options={}
    data        = options[:data]
    headers     = options[:headers]
    http_method = options[:http_method] || :get
    query       = options[:query]

    HTTPClient.new.request http_method, uri, query, data
  end
end
