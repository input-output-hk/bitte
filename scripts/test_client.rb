# frozen_string_literal: true

require 'socket'
require 'openssl'

context = OpenSSL::SSL::SSLContext.new
context.cert = OpenSSL::X509::Certificate.new File.read('secrets/ssl/client.age')
context.key = OpenSSL::PKey.read File.read('secrets/ssl/client-key.age')
# context.cert = OpenSSL::X509::Certificate.new File.read('secrets/ssl/cert.age')
# context.key = OpenSSL::PKey.read File.read('secrets/ssl/ca-key.age')

context.ca_file = 'secrets/ssl/ca.age'
context.verify_mode = OpenSSL::SSL::VERIFY_PEER

tcp_socket = TCPSocket.new 'localhost', 5000
ssl_client = OpenSSL::SSL::SSLSocket.new tcp_socket, context
ssl_client.sync_close = true
ssl_client.connect

ssl_client.puts 'hello server!'
puts ssl_client.gets

ssl_client.close
