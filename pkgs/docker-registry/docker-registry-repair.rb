require 'digest/sha2'
require 'json'
require 'fileutils'
require 'optparse'

OPTIONS = {
  delete_tag: false,
  dry_run: false,
  registry: '/var/lib/docker-registry/docker/registry/v2',
  repo: nil,
  tag: nil,
}

op = OptionParser.new do |parser|
  parser.banner = 'Usage: docker-registry-repair [options]'

  parser.on '-d', '--dry-run [FLAG]', TrueClass, 'avoid deleting anything' do |v|
    OPTIONS[:dry_run] = v.nil? ? true : v
  end

  parser.on '-r', '--repo REPO', 'repository part of the image name, like `cardano-public-documentation`' do |v|
    OPTIONS[:repo] = v
  end

  parser.on '-t', '--tag TAG', 'tag of the image, the part after the `:`' do |v|
    OPTIONS[:tag] = v
  end

  parser.on '--delete-tag [FLAG]', TrueClass, 'also delete all tag references' do |v|
    OPTIONS[:delete_tag] = v.nil? ? true : v
  end

  parser.on '--registry-path PATH', "the registry path, defaults to: #{OPTIONS[:registry]}" do |v|
    OPTIONS[:registry] = v
  end
end

op.parse!

def dry_run?; OPTIONS[:dry_run] end
def delete_tag?; OPTIONS[:delete_tag] end
def repo; OPTIONS[:repo] end
def tag; OPTIONS[:tag] end
def registry; OPTIONS[:registry] end
def prefix(hash) hash[/sha256:(..)/, 1] end
def suffix(hash) hash[/sha256:(.*)/, 1] end
def blob(hash) "#{registry}/blobs/sha256/#{prefix(hash)}/#{suffix(hash)}/data" end

def rm(path)
  puts "removing #{path}"
  FileUtils.rm_rf(path) unless dry_run?
end

def remove_layers(hash)
  `redis-cli --raw keys '*#{hash}*'`.each_line do |key|
    key.strip!
    puts "removing #{key} from redis"
    system('redis-cli', 'del', key) unless dry_run?
  end

  Dir.glob("#{registry}/repositories/*/_layers/sha256/#{hash}") do |layer_file|
    rm(layer_file)
  end

  Dir.glob("#{registry}/repositories/*/_manifests/revisions/sha256/#{hash}") do |revision_file|
    rm(revision_file)
  end

  Dir.glob("#{registry}/repositories/*/_manifests/tags/*/index/sha256/#{hash}") do |index_file|
    rm(index_file)
  end
end

def repair(desired)
  blob_path = blob(desired)

  unless File.file?(blob_path)
    puts "missing file for #{blob_path}"
    remove_layers(desired)
    return
  end

  actual = Digest::SHA256.file(blob_path).hexdigest
  return if desired == "sha256:#{actual}"

  remove_layers(desired)
  puts "removing #{blob(desired)}"
  system('redis-cli', 'del', "blobs::sha256:#{desired}")
  rm(blob(desired))
end

puts "verifying #{repo}:#{tag}"
puts "--dry-run is enabled, will not actually delete anything" if dry_run?

link = "#{registry}/repositories/#{repo}/_manifests/tags/#{tag}/current/link"
unless File.file?(link)
  puts "#{link} is missing, cannot read manifest"
end

link_hash = File.read(link).strip
manifest = JSON.parse(File.read(blob(link_hash)))

repair manifest['config']['digest']

manifest['layers'].each do |layer|
  repair layer['digest']
end

# The following code may actually be needed in more serious cases
exit unless delete_tag?

remove_layers(link_hash)

puts "removing #{link}"
rm("#{registry}/repositories/#{repo}/_manifests/tags/#{tag}")
