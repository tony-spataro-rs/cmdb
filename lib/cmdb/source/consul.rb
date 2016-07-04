# encoding: utf-8
require 'base64'
require 'net/http'
require 'open-uri'

module CMDB
  class Source::Consul < Source::Network
    # Regular expression to match array values
    ARRAY_VALUE = /^\[(.*)\]$/

    # Get a single key from consul
    def get(key)
      key = dot_to_slash(key)
      response = http_get path_to(key)
      case response
      when Array
        item = response.first
        process_value(Base64.decode64(item['Value']))
      when 404
        nil
      else
        raise CMDB:Error.new("Unexpected consul response #{value.inspect}")
      end
    end

    # Set a single key in consul.
    def set(key, value)
      key = dot_to_slash(key)
      http_put path_to(key), value
    end

    # Iterate through all keys in this source.
    # @return [Integer] number of key/value pairs that were yielded
    def each_pair(&_block)
      all = http_get path_to('/'), query:'recurse'
      unless all.is_a?(Array)
        raise CMDB:Error.new("Unexpected consul response #{all.inspect}")
      end

      all.each do |item|
        dotted_prefix = @prefix.split('/').join('.')
        dotted_key = item['Key'].split('/').join('.')
        key = dotted_prefix == '' ? dotted_key : dotted_key.split("#{dotted_prefix}.").last
        value = process_value(Base64.decode64(item['Value']))
        yield(key, value)
      end

      all.size
    end

    private

    # Given a key's relative path, return its absolute REST path in the consul
    # kv, including any prefix that was specified at startup.
    def path_to(key)
      p = '/v1/kv'
      p << prefix unless prefix.empty?
      p << key
      p
    end
  end
end