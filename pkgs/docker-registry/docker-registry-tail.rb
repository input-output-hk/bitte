require 'open3'
require 'set'
require 'optparse'

OPTIONS = {
  delay: 5,
  delete_tag: false,
  dry_run: false,
  script: 'docker-registry-repair',
  service: 'docker-registry.service',
  since: '-1h',
}

op = OptionParser.new do |parser|
  parser.banner = 'Usage: docker-registry-tail [options]'

  parser.on '--repair-path PATH', "the repair script path to utilize; defaults to: #{OPTIONS[:script]}" do |v|
    OPTIONS[:script] = v
  end

  parser.on '-s', '--since LOOKBACK', "the lookback period for journal history; defaults to: #{OPTIONS[:since]}" do |v|
    OPTIONS[:since] = v
  end

  parser.on '-u', '--service SERVICE', "the systemd service to tail; defaults to: #{OPTIONS[:service]}" do |v|
    OPTIONS[:service] = v
  end

  parser.on '-t', '--delay SEC', Integer, "the time delay in seconds between repair spawn jobs; defaults to: #{OPTIONS[:delay]}" do |v|
    OPTIONS[:delay] = v
  end

  parser.on '-d', '--dry-run [FLAG]', TrueClass, 'avoid deleting anything' do |v|
    OPTIONS[:dry_run] = v.nil? ? true : v
  end

  parser.on '--delete-tag [FLAG]', TrueClass, 'also delete all tag references' do |v|
    OPTIONS[:delete_tag] = v.nil? ? true : v
  end
end

op.parse!

def dry_run?; OPTIONS[:dry_run] end
def delete_tag?; OPTIONS[:delete_tag] end
def delay; OPTIONS[:delay] end
def script; OPTIONS[:script] end
def service; OPTIONS[:service] end
def since; OPTIONS[:since] end

# Check back in systemd log history, and follow all newly pushed images
Open3.popen2e('journalctl', '-S', since, '-f', '-u', service, '-g', '"PUT /v2/.+/manifests') do |_, out|
  out.each_line do |line|
    %r!/v2/(?<repo>[^/\s]+)/manifests/(?<tag>[^/\s]+)! =~ line
    next unless repo && tag
    system(script, '--repo', repo, '--tag', tag, '--dry-run', dry_run? ? "true" : "false", '--delete-tag', delete_tag? ? "true" : "false")
    sleep delay
  end
end
