#!usr/bin/env crystal
# frozen_string_literal: true

# A little wrapper that forwards environment variables if they don't include
# any invalid characters.

exit unless ENV["NOMAD_TASK_DIR"]?

allowed = {
  "HOME" => ENV["NOMAD_TASK_DIR"]
}

ENV.each do |key, value|
  allowed[key] = value if key =~ /^NOMAD[a-zA-Z0-9_]+$/
end

bind = %w[NOMAD_ALLOC_DIR NOMAD_SECRETS_DIR NOMAD_TASK_DIR]
bindpaths = bind.map { |key| "#{ENV[key]}:#{ENV[key]}" }

args = [
  "--property", %(BindPaths=#{bindpaths.join(" ")})
]

allowed.each do |key, value|
  args << "--setenv" << "#{key}=#{value}"
end

Process.exec(
  "systemd-run", args: args + ARGV, input: STDIN, output: STDOUT, error: STDERR
)
