{ self, config, lib, pkgs, ... }: let

  Imports = { imports = [
    ./common.nix
  ]; };

  Switches = { };

  Config = {
    services.vault-agent = {
      role = "core";
      templates = {
        "/run/consul-templates/vmalerts.log" = {
          contents = ''
            {{ range $kvSubPath := secrets "kv/alerts" -}}
              {{ $alertDatasource := $kvSubPath | trimSuffix "/" -}}
              {{ range $alertTemplate := secrets (printf "kv/alerts/%s" $alertDatasource) -}}
                {{ with secret (printf "kv/alerts/%s/%s" $alertDatasource $alertTemplate) -}}
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
        "/run/consul-templates/dashboards.log" = {
          contents = ''
            {{ range $dashboard := secrets "kv/dashboards" -}}
              {{ with secret (printf "kv/dashboards/%s" $dashboard) -}}
                {{ .Data.data
                   | toUnescapedJSONPretty
                   | writeToFile
                     (printf "/var/lib/grafana/dashboards/%s.json" $dashboard)
                     "grafana"
                     "grafana"
                     "0644"
                -}}
                {{ (printf "At %s vault-agent wrote consul-template output declarative dashboard to file: /var/lib/grafana/dashboards/%s.json\n"
                  timestamp
                  $dashboard)
                -}}
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
