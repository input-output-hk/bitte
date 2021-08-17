# frozen_string_literal: true

require 'securerandom'
require 'open3'
require 'fileutils'
require 'toml-rb'
require 'openssl'
require 'json'

# Example usage:
# ca_cert, ca_key = SelfSignedCertificate.ca_cert
# server_cert, server_key = SelfSignedCertificate.server_cert(ca_cert, ca_key)
# client_cert, client_key = SelfSignedCertificate.client_cert(ca_cert, ca_key)
module SelfSignedCertificate
  SERVER_EXTENSIONS = {
    'keyUsage' => 'keyCertSign,digitalSignature,cRLSign,keyEncipherment',
    'extendedKeyUsage' => 'serverAuth,clientAuth'
  }.freeze

  CLIENT_EXTENSIONS = {
    'keyUsage' => 'digitalSignature',
    'extendedKeyUsage' => 'clientAuth'
  }.freeze

  CA_EXTENSIONS = {
    'basicConstraints' => 'CA:TRUE',
    'keyUsage' => 'keyCertSign,cRLSign'
  }.freeze

  SUBJECT = {
    O: 'IOHK',
    C: 'JP',
    ST: 'Kantō',
    L: 'Tokyo',
    CN: 'consul'
  }.map { |k, v| "#{k}=#{v}" }.join ','

  ALT_NAMES = %w[
    DNS:consul.service.consul
    DNS:vault.service.consul
    DNS:nomad.service.consul
    DNS:server.eu-central-1.consul
    DNS:server.local.consul
    DNS:vault.vit.iohk.io
    DNS:consul.vit.iohk.io
    DNS:nomad.vit.iohk.io
    DNS:monitoring.vit.iohk.io
    DNS:core0
    DNS:core1
    DNS:core2
    IP:127.0.0.1
    IP:172.16.0.10
    IP:172.16.1.10
    IP:172.16.2.10
    IP:172.16.0.20
    IP:18.192.98.58
  ].join(',')

  class << self
    def ca_cert
      key = OpenSSL::PKey::EC.generate 'prime256v1'

      cert = OpenSSL::X509::Certificate.new
      cert.subject = cert.issuer = subject
      cert.public_key = key
      cert_defaults cert, 0

      ef = OpenSSL::X509::ExtensionFactory.new
      ef.subject_certificate = ef.issuer_certificate = cert

      cert.extensions = CA_EXTENSIONS.map { |k, v| ef.create_extension(k.to_s, v) }

      cert.sign key, digest

      [cert, key]
    end

    def client_cert(ca_cert, ca_key)
      cert ca_cert, ca_key, CLIENT_EXTENSIONS
    end

    def server_cert(ca_cert, ca_key)
      cert ca_cert, ca_key, SERVER_EXTENSIONS
    end

    def signing_request(key)
      csr = OpenSSL::X509::Request.new
      csr.version = 0
      csr.subject = subject
      csr.public_key = key
      csr.sign key, digest

      raise 'CSR can not be verified' unless csr.verify csr.public_key

      csr
    end

    private

    def digest
      OpenSSL::Digest.new('SHA256')
    end

    def subject
      OpenSSL::X509::Name.parse(SUBJECT)
    end

    def cert_defaults(cert, serial)
      cert.not_after = Time.now + 5 * 3600 * 24 * 365
      cert.not_before = Time.now
      cert.serial = serial
      cert.version = 2
    end

    def core_cert(serial)
      key = OpenSSL::PKey::EC.generate 'prime256v1'

      cert = OpenSSL::X509::Certificate.new
      cert.subject = subject
      cert.public_key = key
      cert_defaults cert, serial

      [cert, key]
    end

    def cert(ca_cert, ca_key, extensions)
      cert, key = core_cert SecureRandom.rand(1_000_000)
      cert.issuer = ca_cert.subject

      ef = OpenSSL::X509::ExtensionFactory.new
      ef.subject_certificate = cert
      ef.issuer_certificate = ca_cert

      cert.extensions = extensions.map { |k, v| ef.create_extension(k.to_s, v) }
      cert.add_extension ef.create_extension('subjectAltName', ALT_NAMES)

      cert.sign ca_key, digest

      [cert, key]
    end
  end
end

# convenience methods
module Convencience
  refine Kernel do
    def pipe(*args, &block)
      Open3.popen2(*args, &block)
    end

    def cluster_name
      `nix eval --raw .#nixosConfigurations.test-core0.config.cluster.name`.strip
    end

    def age_identities
      Dir['encrypted/ssh/*.pub'].map do |pub|
        [File.basename(pub, '.pub'), File.read(pub).strip]
      end.to_h
    end

    def pkey
      'secrets/age-bootstrap.pub'
    end

    def skey
      'secrets/age-bootstrap'
    end

    def sync_agenix_file
      calculated = agenix_contents
      original =
        if File.file? '.agenix.toml'
          TomlRB.load_file '.agenix.toml'
        else
          {}
        end

      return if original == calculated

      File.write('.agenix.toml', TomlRB.dump(calculated))
    end

    def agenix_pkey
      File.read(pkey).split.first(2).join(' ')
    end

    def agenix_contents
      identities = age_identities
      {
        'paths' => [{
          'glob' => 'encrypted/*',
          'groups' => ['bootstrap'],
          'identities' => identities.keys
        }],
        'groups' => { 'bootstrap' => [agenix_pkey] },
        'identities' => identities
      }
    end

    def ssh_pubs
      MACHINES.map do |machine|
        File.join 'encrypted/ssh', "#{machine}.pub"
      end
    end
  end
end

using Convencience

MACHINES = %w[core0 core1 core2 work0 builder].freeze

# Working around agenix limitations. It demans you type your things in an editor.
ENV['EDITOR'] = File.join __dir__, 'scripts/pipe.sh'

task default: ssh_pubs + %w[
  .agenix.toml
  encrypted/consul/encrypt.age
  encrypted/consul/token-master.age
  encrypted/nix/key.age
  encrypted/nix/key.pub
  encrypted/nomad/encrypt.age
  encrypted/ssl/client.age
  encrypted/ssl/server.age
  encrypted/ssl/server-full.age
] do
  sh 'git', 'add', 'encrypted'
end

directory 'encrypted/ssl'
directory 'encrypted/ssh'
directory 'secrets'

task :rekey do
  at_exit do
    # ensure all files are encrypted with the right keys...
    Dir.glob 'encrypted/**/*.age' do |age|
      sh 'agenix', '-i', skey, '--rekey', age
    end
  end
end

task decrypt: Dir['encrypted/**/*.age'] do |t|
  t.prereqs.each do |age|
    dst = age.sub(/^encrypted/, 'secrets')
    FileUtils.mkdir_p File.dirname(dst)
    sh 'age', '-i', skey, '-o', dst, '-d', age
  end
end

file '.agenix.toml' => [pkey] do
  sync_agenix_file
end

file pkey => ['secrets'] do
  sh 'ssh-keygen', '-t', 'ed25519', '-f', skey, '-N', '', '-c', 'bootstrap'
end

file 'encrypted/consul/encrypt.age' do
  pipe 'agenix', '-i', skey, 'encrypted/consul/encrypt.age' do |sin, _|
    pipe 'consul', 'keygen' do |_, out|
      IO.copy_stream out, sin
    end
  end
end

file 'encrypted/consul/token-master.age' do
  pipe 'agenix', '-i', skey, 'encrypted/consul/token-master.age' do |sin, _|
    sin.write SecureRandom.uuid
  end
end

file 'encrypted/nomad/encrypt.age' do
  pipe 'agenix', '-i', skey, 'encrypted/nomad/encrypt.age' do |sin, _|
    pipe 'nomad', 'operator', 'keygen' do |_, out|
      IO.copy_stream out, sin
    end
  end
end

file 'encrypted/nix/key.age' do
  pipe 'agenix', '-i', skey, 'encrypted/nix/key.age' do |agenix_in, _|
    pipe 'nix', 'key', 'generate-secret', '--key-name', "#{cluster_name}-0" do |_, generate_out|
      IO.copy_stream generate_out, agenix_in
    end
  end
end

file 'encrypted/nix/key.pub' => ['encrypted/nix/key.age'] do
  pipe 'nix', 'key', 'convert-secret-to-public' do |convert_in, convert_out|
    pipe 'age', '-d', '-i', skey, 'encrypted/nix/key.age' do |_, age_out|
      IO.copy_stream age_out, convert_in
    end

    convert_in.close

    File.open 'encrypted/nix/key.pub', 'w+' do |out|
      IO.copy_stream convert_out, out
    end
  end
end

rule %r{^encrypted/ssl/ca(-key)?\.age} do
  cert, key = SelfSignedCertificate.ca_cert

  pipe 'agenix', '-i', skey, 'encrypted/ssl/ca.age' do |agenix_in, _|
    agenix_in.write cert.to_pem
  end

  pipe 'agenix', '-i', skey, 'encrypted/ssl/ca-key.age' do |agenix_in, _|
    agenix_in.write key.to_pem
  end
end

rule %r{^encrypted/ssl/client(-key)?\.age} => ['encrypted/ssl/ca-key.age', 'encrypted/ssl/ca.age'] do
  pipe 'age', '-d', '-i', skey, 'encrypted/ssl/ca-key.age' do |_, ca_key_out|
    pipe 'age', '-d', '-i', skey, 'encrypted/ssl/ca.age' do |_, ca_out|
      cert, key = SelfSignedCertificate.client_cert(
        OpenSSL::X509::Certificate.new(ca_out.read),
        OpenSSL::PKey.read(ca_key_out.read)
      )

      pipe 'agenix', '-i', skey, 'encrypted/ssl/client-key.age' do |agenix_in, _|
        agenix_in.write key.to_pem
      end

      pipe 'agenix', '-i', skey, 'encrypted/ssl/client.age' do |agenix_in, _|
        agenix_in.write cert.to_pem
      end
    end
  end
end

rule %r{^encrypted/ssl/server(-key)?\.age} => ['encrypted/ssl/ca-key.age', 'encrypted/ssl/ca.age'] do
  pipe 'age', '-d', '-i', skey, 'encrypted/ssl/ca-key.age' do |_, ca_key_out|
    pipe 'age', '-d', '-i', skey, 'encrypted/ssl/ca.age' do |_, ca_out|
      cert, key = SelfSignedCertificate.server_cert(
        OpenSSL::X509::Certificate.new(ca_out.read),
        OpenSSL::PKey.read(ca_key_out.read)
      )

      pipe 'agenix', '-i', skey, 'encrypted/ssl/server-key.age' do |agenix_in, _|
        agenix_in.write key.to_pem
      end

      pipe 'agenix', '-i', skey, 'encrypted/ssl/server.age' do |agenix_in, _|
        agenix_in.write cert.to_pem
      end
    end
  end
end

file 'encrypted/ssl/server-full.age' => ['encrypted/ssl/server-key.age', 'encrypted/ssl/server.age'] do
  pipe 'age', '-d', '-i', skey, 'encrypted/ssl/ca.age' do |_, ca_out|
    pipe 'age', '-d', '-i', skey, 'encrypted/ssl/server.age' do |_, server_out|
      pipe 'agenix', '-i', skey, 'encrypted/ssl/server-full.age' do |agenix_in, _|
        agenix_in.write [server_out, ca_out].map(&:read).join("\n")
      end
    end
  end
end

file 'secrets/ca-key.pem' => ['encrypted/ssl/ca-key.age'] do
  pipe 'age', '-d', '-i', skey, 'encrypted/ssl/ca-key.age' do |_, ca_out|
    File.write('secrets/ca-key.pem', ca_out.read)
  end
end

file 'secrets/ca.pem' => ['encrypted/ssl/ca.age'] do
  pipe 'age', '-d', '-i', skey, 'encrypted/ssl/ca.age' do |_, ca_out|
    File.write('secrets/ca.pem', ca_out.read)
  end
end

file 'secrets/server.pem' => ['encrypted/ssl/server.age'] do
  pipe 'age', '-d', '-i', skey, 'encrypted/ssl/server.age' do |_, ca_out|
    File.write('secrets/server.pem', ca_out.read)
  end
end

def ca_config_file
  File.write('secrets/ca-config.json', {
    signing: {
      default: {
        expiry: '87600h'
      },
      profiles: {
        default: {
          usages: ['signing', 'key encipherment', 'server auth', 'client auth'],
          expiry: '8760h'
        },

        intermediate: {
          usages: ['signing', 'key encipherment', 'cert sign', 'crl sign'],
          expiry: '43800h',
          ca_constraint: { is_ca: true }
        }
      }
    }
  }.to_json)

  'secrets/ca-config.json'
end

task certs: ['secrets/ca.pem', 'secrets/ca-key.pem', 'secrets/server.pem'] do
  ca_pem_orig = File.read('secrets/ca.pem')
  ca_pem = ca_pem_orig.strip
  server_pem_orig = File.read('secrets/server.pem')
  server_pem = server_pem_orig.strip

  pipe(
    'vault',
    'write',
    'pki/intermediate/generate/internal',
    "common_name=vault.#{ENV.fetch('BITTE_DOMAIN')}"
  ) do |_, vault_out|
    output = vault_out.read
    csr = JSON.parse(output).fetch('data').fetch('csr')
    File.write('secrets/issuing-ca.csr', csr)
  end

  pipe(
    'cfssl',
    'sign',
    '-ca',
    'secrets/ca.pem',
    '-ca-key',
    'secrets/ca-key.pem',
    '-hostname',
    'vault.service.consul',
    '-config',
    ca_config_file,
    '-profile',
    'intermediate',
    'secrets/issuing-ca.csr'
  ) do |_, cfssl_out|
    output = cfssl_out.read
    pp output
    issuing_csr_container = JSON.parse(output)
    issuing_pem = issuing_csr_container.fetch('cert').strip

    File.write('secrets/issuing.pem', issuing_pem)
    File.write('secrets/issuing_full.pem', [issuing_pem, ca_pem].join("\n"))

    system(
      'vault',
      'write',
      'pki/intermediate/set-signed',
      'certificate=@secrets/issuing_full.pem'
    )

    full = [server_pem, issuing_pem, ca_pem].join("\n")
    File.write('secrets/full.pem', full)
  end
end

MACHINES.each do |name|
  file "encrypted/ssh/#{name}.pub" => ["encrypted/ssh/#{name}.age"]

  file "encrypted/ssh/#{name}.age" => ['encrypted/ssh'] do
    tmp = "/dev/shm/#{name}"
    tmp_pub = "#{tmp}.pub"

    pipe 'agenix', '-i', skey, "encrypted/ssh/#{name}.age" do |agenix_in, _|
      FileUtils.rm_f tmp_pub
      FileUtils.rm_f tmp

      # TODO: find a cross-platform way to generate this key in memory...
      pipe 'ssh-keygen', '-t', 'ed25519', '-f', tmp, '-N', '', '-C', "root@#{name}" do |ssh_in, _ssh_out|
        ssh_in.puts 'y'
      end

      FileUtils.cp tmp_pub, "encrypted/ssh/#{name}.pub"

      File.open tmp do |sk|
        IO.copy_stream sk, agenix_in
      end

      FileUtils.rm_f tmp_pub
      FileUtils.rm_f tmp
    end
  end

  Rake::Task["encrypted/ssh/#{name}.pub"].enhance [:rekey]
end
