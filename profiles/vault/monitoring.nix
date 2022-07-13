{ self, config, lib, pkgs, ... }: let

  Imports = { imports = [
    ./common.nix
  ]; };

  Switches = { };

  Config = let
    agentCommand = namePrefix: targetDirs: let
      script = pkgs.writeShellApplication {
        runtimeInputs = with pkgs; [ bash coreutils fd ripgrep ];
        name = "${namePrefix}-cleanup.sh";
        text = ''
          set -x

          if [ -s /run/consul-templates/${namePrefix}.log ]; then
            fd --type file . \
              ${targetDirs} \
              --exec bash -c \
              "
                rg --quiet {} /run/consul-templates/${namePrefix}.log ||
                {
                   rm {}
                   echo \"At $(date -u "+%FT%TZ") vault-agent command removed file: {}\" \
                     >> /run/consul-templates/${namePrefix}-removed.log
                }
              "
          fi
        '';
      };
    in "${script}/bin/${namePrefix}-cleanup.sh";
    # Vault has deprecated use of `command` in the template stanza, but a bug
    # prevents us from moving to the `exec` statement until resolved:
    # Ref: https://github.com/hashicorp/vault/issues/16230
    # in { command = [ "${script}/bin/${namePrefix}.sh" ]; };
  in {
    services.vault-agent = {
      role = "core";
      templates = {
        "/run/consul-templates/vmalerts.log" = {
          contents = ''
            {{ range $kvSubPath := secrets "kv/system/alerts" -}}
              {{ $alertDatasource := $kvSubPath | trimSuffix "/" -}}
              {{ range $alertTemplate := secrets (printf "kv/system/alerts/%s" $alertDatasource) -}}
                {{ with secret (printf "kv/system/alerts/%s/%s" $alertDatasource $alertTemplate) -}}
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
          command = agentCommand "vmalerts" "/var/lib/vmalert-loki /var/lib/vmalert-vm";
        };
        "/run/consul-templates/dashboards.log" = {
          contents = ''
            {{ range $dashboard := secrets "kv/system/dashboards" -}}
              {{ with secret (printf "kv/system/dashboards/%s" $dashboard) -}}
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
          command = agentCommand "dashboards" "/var/lib/grafana/dashboards";
        };
      };
    };
  };

in Imports // lib.mkMerge [
  Switches
  Config
]
