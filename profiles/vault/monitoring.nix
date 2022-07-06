{ self, config, lib, pkgs, ... }: let

  Imports = { imports = [
    ./common.nix
  ]; };

  Switches = { };

  Config = {
    services.vault-agent = {
      role = "core";
      templates = {
        "/run/consul-templates/vmalert.log" = {
          contents = ''
            {{ range $kvSubPath := secrets "kv/alerts" -}}
              {{ $alertDatasource := $kvSubPath | trimSuffix "/" -}}
              {{ range $alertTemplate := secrets (printf "kv/alerts/%s" $alertDatasource) -}}
                {{ with secret (printf "kv/alerts/%s/%s" $alertDatasource .) -}}
                  {{ .Data.data
                     | toUnescapedJSONPretty
                     | writeToFile
                       (printf "/var/lib/private/vmalert-%s/alerts/%s.json" $alertDatasource $alertTemplate)
                       "root"
                       "root"
                       "0644"
                  -}}
                  {{ (printf "At %s vault-agent wrote consul-template output declarative alerts to file: /var/lib/vmalert-%s/alerts/%s.json\n"
                    timestamp
                    $alertDatasource
                    $alertTemplate)
                  -}}
                {{- end }}
              {{- end }}
            {{- end -}}
          '';
        };
      };
    };
  };

in Imports // lib.mkMerge [
  Switches
  Config
]
