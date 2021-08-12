# frozen_string_literal: true

require 'openssl'
require 'socket'

require './cert'

ca_cert = OpenSSL::X509::Certificate.new(File.read('secrets/ssl/ca.age'))
server_cert = OpenSSL::X509::Certificate.new(File.read('secrets/ssl/server.age'))
server_key = OpenSSL::PKey.read File.read('secrets/ssl/server-key.age')

context = OpenSSL::SSL::SSLContext.new
context.cert = server_cert
context.key = server_key

tcp_server = TCPServer.new 5000
ssl_server = OpenSSL::SSL::SSLServer.new tcp_server, context

ssl_connection = ssl_server.accept

data = ssl_connection.gets

response = "I got #{data.dump}"
puts response

ssl_connection.puts "I got #{data.dump}"
ssl_connection.close
