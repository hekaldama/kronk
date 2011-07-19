class Kronk

  ##
  # Performs HTTP requests or retrieves HTTP responses
  # from a file or IO instance.

  class Request

    # Generic Request exception.
    class Exception < ::Exception; end

    # Raised when the URI was not resolvable.
    class NotFoundError < Exception; end

    # Raised when HTTP times out.
    class TimeoutError < Exception; end



    ##
    # Creates a query string from data.

    def self.build_query data, param=nil
      return data.to_s unless param || Hash === data

      case data
      when Array
        out = data.map do |value|
          key = "#{param}[]"
          build_query value, key
        end

        out.join "&"

      when Hash
        out = data.map do |key, value|
          key = param.nil? ? key : "#{param}[#{key}]"
          build_query value, key
        end

        out.join "&"

      else
        "#{param}=#{data}"
      end
    end


    ##
    # Build the URI to use for the request from the given uri or
    # path and options.

    def self.build_uri uri, options={}
      suffix = options[:uri_suffix]

      uri = "http://#{uri}"   unless uri.to_s =~ %r{^(\w+://|/)}
      uri = "#{uri}#{suffix}" if suffix
      uri = URI.parse uri unless URI === uri
      uri = URI.parse(Kronk.config[:default_host]) + uri unless uri.host

      if options[:query]
        query = build_query options[:query]
        uri.query = [uri.query, query].compact.join "&"
      end

      uri
    end


    ##
    # Parses a raw HTTP request string into a Kronk::Request instance.

    def self.parse str
    end


    ##
    # Parses a nested query. Stolen from Rack.

    def self.parse_nested_query qs, d=nil
      params = {}
      d ||= "&;"

      (qs || '').split(%r{[#{d}] *}n).each do |p|
        k, v = CGI.unescape(p).split('=', 2)
        normalize_params(params, k, v)
      end

      params
    end


    ##
    # Stolen from Rack.

    def self.normalize_params params, name, v=nil
      name =~ %r(\A[\[\]]*([^\[\]]+)\]*)
      k = $1 || ''
      after = $' || ''

      return if k.empty?

      if after == ""
        params[k] = v

      elsif after == "[]"
        params[k] ||= []
        raise TypeError,
          "expected Array (got #{params[k].class.name}) for param `#{k}'" unless
            params[k].is_a?(Array)

        params[k] << v

      elsif after =~ %r(^\[\]\[([^\[\]]+)\]$) || after =~ %r(^\[\](.+)$)
        child_key = $1
        params[k] ||= []
        raise TypeError,
          "expected Array (got #{params[k].class.name}) for param `#{k}'" unless
            params[k].is_a?(Array)

        if params[k].last.is_a?(Hash) && !params[k].last.key?(child_key)
          normalize_params(params[k].last, child_key, v)
        else
          params[k] << normalize_params({}, child_key, v)
        end

      else
        params[k] ||= {}
        raise TypeError,
          "expected Hash (got #{params[k].class.name}) for param `#{k}'" unless
            params[k].is_a?(Hash)

        params[k] = normalize_params(params[k], after, v)
      end

      return params
    end


    attr_accessor :auth, :body, :follow_redirects, :headers,
                  :response, :timeout

    attr_reader :http_method, :uri, :use_cookies, :user_agent


    def initialize uri, options={}
      @HTTP = Net::HTTP
      @auth = options[:auth]
      @body = self.class.build_query options[:data] if options[:data]

      @response = nil
      @_req     = nil
      @_res     = nil

      @follow_redirects = options[:follow_redirects]

      @headers = options[:headers] || {}
      @timeout = options[:timeout] || Kronk.config[:timeout]

      self.uri = uri

      self.user_agent ||= options[:user_agent]

      self.http_method = options[:http_method] || (@body ? "POST" : "GET")

      self.use_cookies = options.has_key?(:no_cookies) ?
                          Kronk.config[:use_cookies] : !options[:no_cookies]

      if Hash === options[:proxy]
        self.use_proxy options[:proxy][:address], options[:proxy]
      else
        self.use_proxy options[:proxy]
      end
    end


    ##
    # Assigns the cookie string.

    def cookie= cookie_str
      @headers['Cookie'] = cookie_str if @use_cookies
    end


    ##
    # Assigns the http method.

    def http_method= new_verb
      @http_method = new_verb.to_s.upcase
    end


    ##
    # Assign the use of a proxy.
    # The proxy_opts arg can be a uri String or a Hash with the :address key
    # and optional :username and :password keys.

    def use_proxy addr, opts={}
      return @HTTP = Net::HTTP unless addr

      host, port = addr.split ":"
      port ||= opts[:port] || 8080

      user = opts[:username]
      pass = opts[:password]

      Kronk::Cmd.verbose "Using proxy #{addr}\n" if host

      @HTTP = Net::HTTP::Proxy host, port, user, pass
    end


    ##
    # Assign the uri and io based on if the uri is a file, io, or url.

    def uri= new_uri
      @uri = self.class.build_uri uri
    end


    ##
    # Decide whether to use cookies or not.

    def use_cookies= bool
      if bool && (!@headers['Cookie'] || @headers['Cookie'].empty?)
        cookie = Kronk.cookie_jar.get_cookie_header @uri.to_s
        @headers['Cookie'] = cookie unless cookie.empty?

      else
        @headers.delete 'Cookie'
      end

      @use_cookies = bool
    end


    ##
    # Assign a new User Agent

    def user_agent= new_ua
      @user_agent = new_ua && Kronk.config[:user_agents][new_ua.to_s] ||
                      new_ua || Kronk.config[:user_agents]['kronk']
    end


    ##
    # Check if this is an SSL request.

    def ssl?
      @uri.scheme == "https"
    end


    ##
    # Assign whether to use ssl or not.

    def ssl= bool
      @uri.scheme = bool ? "https" : "http"
    end


    ##
    # Retrieve this requests' response.
    # Will perform redirects as needed up to the number of @follow_redirect.

    def retrieve
      @_req = @HTTP.new @uri.host, @uri.port
      @_req.read_timeout = @timeout

      elapsed_time = nil
      socket       = nil
      socket_io    = nil

      @_res = @_req.start do |http|
        socket = http.instance_variable_get "@socket"
        socket.debug_output = socket_io = StringIO.new

        req = VanillaRequest.new @http_method, @uri.request_uri, @headers

        req.basic_auth @auth[:username], @auth[:password] if
          @auth && @auth[:username]

        Kronk::Cmd.verbose "Retrieving URL:  #{uri}\n"

        start_time = Time.now
        res = http.request req, data
        elapsed_time = Time.now - start_time

        res
      end

      Kronk.cookie_jar.set_cookies_from_headers @uri.to_s, @_res.to_hash if
        self.use_cookies

      @response = Response.from_net_http_io socket_io
      @response.time    = elapsed_time
      @response.request = self

      @response
    end


    ##
    # Returns the raw HTTP request String.

    def to_s
    end


    ##
    # Allow any http method to be sent

    class VanillaRequest
      def self.new method, path, initheader=nil
        klass = Class.new Net::HTTPRequest
        klass.const_set "METHOD", method.to_s.upcase
        klass.const_set "REQUEST_HAS_BODY", true
        klass.const_set "RESPONSE_HAS_BODY", true

        klass.new path, initheader
      end
    end
  end
end