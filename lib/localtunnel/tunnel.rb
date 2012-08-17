require 'rubygems'
require 'net/ssh'
require 'net/ssh/gateway'
require 'net/http'
require 'uri'
require 'json'

require 'localtunnel/net_ssh_gateway_patch'

module LocalTunnel; end

class LocalTunnel::Tunnel

  SHELL_HOOK_FILE = "./.localtunnel_callback"

  attr_accessor :port, :key, :host

  def initialize(port, key, host=nil, user=nil)
    @port = port
    @key  = key
    @host = host
    @user = user
  end

  def register_tunnel(key=@key)
    url = URI.parse("http://open.localtunnel.com/")
    if key
      resp = JSON.parse(Net::HTTP.post_form(url, {"key" => key}).body)
    else
      resp = JSON.parse(Net::HTTP.get(url))
    end
    if resp.has_key? 'error'
      puts "   [Error] #{resp['error']}"
      exit
    end
    @host = resp['host'].split(':').first
    @tunnel = resp
    return resp
  rescue
    puts "   [Error] Unable to register tunnel. Perhaps service is down?"
    exit
  end

  def start_tunnel(options={})

    port = @port
    tunnel = options || @tunnel
    user = tunnel['user'] || @user

    through_port = (tunnel['through_port'] || 2222).to_i
    gateway = Net::SSH::Gateway.new(@host, user, :auth_methods => %w{ publickey })
    gateway.open_remote(port.to_i, '127.0.0.1', through_port) do |rp,rh|
      puts "   " << tunnel['banner'] if tunnel.has_key? 'banner'
      if File.exists?(File.expand_path(SHELL_HOOK_FILE))
        system "#{File.expand_path(SHELL_HOOK_FILE)} ""#{tunnel['host']}"""
        if !$?.success?
          puts "   An error occurred executing the callback hook #{SHELL_HOOK_FILE}"
          puts "   (Make sure it is executable)"
        end
      end
      puts "   Port #{port} is now publicly accessible from http://#{@host}:#{through_port} ..."
      begin
        sleep 1 while true
      rescue Interrupt
        gateway.close_remote(rp, rh)
        exit
      end
    end
  rescue Net::SSH::AuthenticationFailed
    possible_key = Dir[File.expand_path('~/.ssh/*.pub')].first
    puts "   Failed to authenticate. If this is your first tunnel, you need to"
    puts "   upload a public key using the -k option. Try this:\n\n"
    puts "   localtunnel -k #{possible_key ? possible_key : '~/path/to/key.pub'} #{port}\n\n"
    puts "   Don't have a key? Check out http://bit.ly/createsshkey"
    exit
  end
end
