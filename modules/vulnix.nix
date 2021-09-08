{ config, pkgs, lib, ... }:

let
  cfg = config.services.vulnix;
  whitelistFormat = pkgs.formats.toml {};
in {
  options.services.vulnix = with lib; {
    enable = mkEnableOption "Vulnix scan";

    package = mkOption {
      type = types.package;
      default = pkgs.vulnix;
      defaultText = "pkgs.vulnix";
      description = "The Vulnix distribution to use.";
    };

    scanRequisites = mkEnableOption "scan of transitive closures" // {
      default = true;
    };

    scanSystem = mkEnableOption "scan of the current system" // {
      default = true;
    };

    scanGcRoots = mkEnableOption "scan of all active GC roots";

    scanNomadJobs = {
      enable = mkEnableOption "scan of all active Nomad jobs";
      namespaces = mkOption {
        type = with types; listOf str;
        default =
          let nss = builtins.attrNames config.services.nomad.namespaces; in
          nss ++ lib.optional (nss == []) "*";
        description = "Nomad namespaces to scan jobs in.";
      };
    };

    whitelists = mkOption {
      type = types.listOf whitelistFormat.type;
      default = [];
      description = "Whitelists to respect.";
    };

    paths = mkOption {
      type = with types; listOf str;
      default = [];
      description = "Paths to scan.";
    };

    extraOpts = mkOption {
      type = with types; listOf str;
      default = [];
      description = ''
        Extra options to pass to Vulnix. See the README:
        <link xlink:href="https://github.com/flyingcircusio/vulnix/blob/master/README.rst"/>
        or <command>vulnix --help</command> for more information.
      '';
    };

    sink = mkOption {
      type = types.path;
      description = ''
        Program that processes the result of each scan. It receives the vulnix output on stdin.
        When receiving the result of nomad job scans the environment variables
        <envar>NOMAD_JOB_NAMESPACE</envar>, <envar>NOMAD_JOB_ID</envar>,
        <envar>NOMAD_JOB_TASKGROUP_NAME</envar>, and <envar>NOMAD_JOB_TASK_NAME</envar> are set.
      '';
    };

    sshKey = mkOption {
      type = types.path;
      description = "The SSH key to use for private Git repos.";
    };

    netrcFile = mkOption {
      type = types.path;
      description = "The netrc file to use for private Git repos.";
    };
  };

  config.systemd = let
    inherit (config.cluster) domain;
  in lib.mkIf cfg.enable {
    services.vulnix = {
      description = "Vulnix scan";

      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        CacheDirectory = "vulnix";
        StateDirectory = "vulnix";
      } // lib.optionalAttrs cfg.scanNomadJobs.enable {
        Type = "simple";
        Restart = "on-failure";
        LoadCredential = [
          (assert config.services.vault-agent-core.enable; "vault-token:/run/keys/vault-token")
          "ssh:${cfg.sshKey}"
          "netrc:${cfg.netrcFile}"
        ];
      };

      startLimitIntervalSec = 20;
      startLimitBurst = 10;

      environment = lib.mkIf cfg.scanNomadJobs.enable {
        VAULT_ADDR = "https://vault.${domain}";
        NOMAD_ADDR = "https://nomad.${domain}";
        VAULT_CACERT = "/etc/ssl/certs/${domain}-full.pem";
      };

      path = with pkgs; [ cfg.package vault-bin curl jq nixFlakes gitMinimal ];

      script = ''
        set -o pipefail

        function scan {
          vulnix ${lib.cli.toGNUCommandLineShell {} (with cfg; {
            json = true;
            requisites = scanRequisites;
            no-requisites = !scanRequisites;
            whitelist = map (lib.flip lib.pipe [
              (whitelistFormat.generate "vulnix-whitelist.toml")
              (drv: "${drv}")
            ]) whitelists;
          })} \
            --cache-dir $CACHE_DIRECTORY \
            ${lib.concatStringsSep " " cfg.extraOpts} "$@" \
          || case $? in
            # XXX adapt this after action on https://github.com/flyingcircusio/vulnix/issues/79
            0 ) ;; # no vulnerabilities found
            1 ) ;; # only whitelisted vulnerabilities found
            2 ) ;; # vulnerabilities found
            * ) exit $? ;; # unexpected
          esac
        }

        scan ${lib.cli.toGNUCommandLineShell {} (with cfg; {
          system = scanSystem;
          gc-roots = scanGcRoots;
        })} \
          -- ${lib.escapeShellArgs cfg.paths} \
        | ${cfg.sink}
      '' + lib.optionalString cfg.scanNomadJobs.enable ''
        export VAULT_TOKEN=$(< $CREDENTIALS_DIRECTORY/vault-token)
        NOMAD_TOKEN=$(vault read -field secret_id nomad/creds/admin)
        sleep 5s # let nomad token be propagated to come into effect

        [[ -f $STATE_DIRECTORY/index ]] || {
          printf '%d' 0 > $STATE_DIRECTORY/index
        }

        # TODO If the NOMAD_TOKEN expires the service would probably exit uncleanly and restart. Make it a clean restart.

        function stream {
          <<< X-Nomad-Token:"$NOMAD_TOKEN" \
          curl -H @- \
            --no-progress-meter \
            --cacert /etc/ssl/certs/${domain}-ca.pem \
            -NG "$NOMAD_ADDR"/v1/event/stream \
            --data-urlencode namespace="$1" \
            --data-urlencode topic=Job \
            --data-urlencode index=$(< $STATE_DIRECTORY/index) \
          | jq --unbuffered -rc 'select(length > 0) | {"index": .Index} as $out | .Events[] | select(.Type == "EvaluationUpdated").Payload.Job | $out * {"namespace": .Namespace, "job": .ID} as $out | .TaskGroups[] | $out * {"taskgroup": .Name} as $out | .Tasks[] | $out * {"task": .Name, "flake": .Config.flake}' \
          | while read -r job; do
            <<< "$job" jq -rc .flake \
            | XDG_CACHE_HOME=$CACHE_DIRECTORY \
              GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh -i $CREDENTIALS_DIRECTORY/ssh" \
              xargs -L 1 \
              nix --netrc-file $CREDENTIALS_DIRECTORY/netrc show-derivation \
            | jq --unbuffered -r keys[] \
            | while read -r drv; do
              scan -- "$drv" \
              | NOMAD_JOB_NAMESPACE=$(<<< "$job" jq -rj .namespace) \
                NOMAD_JOB_ID=$(<<< "$job" jq -rj .job) \
                NOMAD_JOB_TASKGROUP_NAME=$(<<< "$job" jq -rj .taskgroup) \
                NOMAD_JOB_TASK_NAME=$(<<< "$job" jq -rj .task) \
                ${cfg.sink}
            done
            <<< "$job" jq -r .index > $STATE_DIRECTORY/index
          done
        }
        ${lib.concatMapStringsSep "\n" (ns:
          "stream ${lib.escapeShellArg ns} &"
        ) cfg.scanNomadJobs.namespaces}
        wait

        exit 1
      '';

      wantedBy = [ "multi-user.target" ];
    };
  };
}
