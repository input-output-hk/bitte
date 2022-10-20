{
  pkgs,
  lib,
  inputs,
  config,
  ...
}: let
  inherit (lib) mkIf mkOption;
  inherit (lib.types) bool str;

  ziti-pkg = inputs.openziti.packages.x86_64-linux.ziti_latest;
  ziti-controller-pkg = inputs.openziti.packages.x86_64-linux.ziti-controller_latest;
  ziti-cli-functions = inputs.openziti.packages.x86_64-linux.ziti-cli-functions_latest;

  zitiController = "ziti-controller";
  zitiControllerHome = "/var/lib/${zitiController}";
  zitiNetwork = "${config.cluster.name}-zt";
  zitiEdgeController = zitiExternalHostname;
  zitiEdgeControllerRawName = "${zitiNetwork}-edge-controller";
  zitiEdgeRouterRawName = "${zitiNetwork}-edge-router";
  zitiExternalHostname = "zt.${config.cluster.domain}";

  # Config refs:
  #   ziti create config controller --help
  #   https://github.com/openziti/ziti/blob/release-next/ziti/cmd/ziti/cmd/config_templates/controller.yml
  #   https://github.com/openziti/ziti/blob/release-next/etc/ctrl.with.edge.yml
  controllerConfigNix = {
    v = 3;
    db = "${zitiControllerHome}/db/ctrl.db";
    identity = {
      cert = "${zitiControllerHome}/pki/${zitiExternalHostname}-intermediate/certs/${zitiExternalHostname}-client.cert";
      server_cert = "${zitiControllerHome}/pki/${zitiExternalHostname}-intermediate/certs/${zitiExternalHostname}-server.chain.pem";
      key = "${zitiControllerHome}/pki/${zitiExternalHostname}-intermediate/keys/${zitiExternalHostname}-server.key";
      ca = "${zitiControllerHome}/pki/cas.pem";
    };
    ctrl.listener = "tls:0.0.0.0:6262";
    mgmt.listener = "tls:0.0.0.0:10000";
    healthChecks.boltCheck = {
      interval = "30s";
      timeout = "20s";
      initialDelay = "30s";
    };
    edge = {
      api = {
        sessionTimeout = "30m";
        address = "${zitiEdgeController}:1280";
      };
      enrollment = {
        signingCert = {
          cert = "${zitiControllerHome}/pki/${zitiNetwork}-signing-intermediate/certs/${zitiNetwork}-signing-intermediate.cert";
          key = "${zitiControllerHome}/pki/${zitiNetwork}-signing-intermediate/keys/${zitiNetwork}-signing-intermediate.key";
        };
        edgeIdentity.duration = "180m";
        edgeRouter.duration = "180m";
      };
    };
    web = [
      {
        name = "client-management";
        bindPoints = [
          {
            interface = "0.0.0.0:1280";
            address = "${zitiEdgeController}:1280";
          }
        ];
        identity = {
          ca = "${zitiControllerHome}/pki/${zitiExternalHostname}-intermediate/certs/${zitiExternalHostname}-intermediate.cert";
          key = "${zitiControllerHome}/pki/${zitiExternalHostname}-intermediate/keys/${zitiExternalHostname}-server.key";
          server_cert = "${zitiControllerHome}/pki/${zitiExternalHostname}-intermediate/certs/${zitiExternalHostname}-server.chain.pem";
          cert = "${zitiControllerHome}/pki/${zitiExternalHostname}-intermediate/certs/${zitiExternalHostname}-client.cert";
        };
        options = {
          idleTimeout = "5000ms";
          readTimeout = "5000ms";
          writeTimeout = "100000ms";
          minTLSVersion = "TLS1.2";
          maxTLSVersion = "TLS1.3";
        };
        apis = [
          {
            binding = "edge-management";
            options = {};
          }
          {
            binding = "edge-client";
            options = {};
          }
          {
            binding = "fabric";
            options = {};
          }
        ];
      }
    ];
  };

  controllerConfigFile = pkgs.toPrettyJSON "${zitiEdgeController}.yaml" controllerConfigNix;
  cfg = config.services.ziti-controller;
in {
  options.services.ziti-controller = {
    enable = mkOption {
      type = bool;
      default = false;
      description = ''
        Enable the OpenZiti controller service.
      '';
    };

    enableBashIntegration = mkOption {
      type = bool;
      default = true;
      description = ''
        Enable integration of OpenZiti bash completions and sourcing of the Ziti environment.

        NOTE: If multiple OpenZiti services are running on one host, the bash integration
              should be enabled for only one of the services.
      '';
    };

    extraBootstrapPre = mkOption {
      type = str;
      default = "";
      description = ''
        Extra code which will be run at the end of the systemd ExecStartPre block.
      '';
    };

    extraBootstrapPost = mkOption {
      type = str;
      default = "";
      description = ''
        Extra code which will be run at the end of the systemd ExecStartPost block.
      '';
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      step-cli
      ziti-cli-functions
      ziti-controller-pkg
      ziti-pkg
    ];

    programs.bash.interactiveShellInit = mkIf cfg.enableBashIntegration ''
      [ -f ${zitiControllerHome}/${zitiNetwork}.env ] && source ${zitiControllerHome}/${zitiNetwork}.env
    '';

    networking.hosts = {
      "127.0.0.1" = [zitiController zitiEdgeController zitiExternalHostname];
    };

    # Required controller public ports
    networking.firewall.allowedTCPPorts = [1280 6262];

    systemd.services.ziti-controller = {
      wantedBy = ["multi-user.target"];

      startLimitIntervalSec = 0;
      startLimitBurst = 0;

      environment = rec {
        EXTERNAL_DNS = zitiExternalHostname;
        HOME = zitiControllerHome;
        ZITI_BIN_DIR = "${zitiControllerHome}/ziti-bin";
        ZITI_CONTROLLER_RAWNAME = zitiController;
        ZITI_EDGE_CONTROLLER_HOSTNAME = EXTERNAL_DNS;
        ZITI_EDGE_CONTROLLER_PORT = "1280";
        ZITI_EDGE_CONTROLLER_RAWNAME = zitiEdgeControllerRawName;
        ZITI_EDGE_ROUTER_HOSTNAME = EXTERNAL_DNS;
        ZITI_EDGE_ROUTER_PORT = "3022";
        ZITI_EDGE_ROUTER_RAWNAME = zitiEdgeRouterRawName;
        ZITI_HOME = zitiControllerHome;
        ZITI_NETWORK = zitiNetwork;

        # Must be configured in the preStart script below in order to acquire external IP
        # EXTERNAL_IP = "...";
        # ZITI_EDGE_CONTROLLER_IP_OVERRIDE = "...";
        # ZITI_EDGE_ROUTER_IP_OVERRIDE = "...";
      };

      serviceConfig = {
        Restart = "always";
        RestartSec = 5;
        StateDirectory = zitiController;
        WorkingDirectory = zitiControllerHome;
        LimitNOFILE = 65535;

        ExecStartPre = let
          preScript = pkgs.writeShellApplication {
            name = "${zitiController}-preScript.sh";
            runtimeInputs = with pkgs; [dnsutils pwgen ziti-pkg ziti-controller-pkg];
            text = ''
              if ! [ -f .bootstrap-pre-complete ]; then
                # Following env vars must be configured here vs systemd environment in order to acquire external IP
                EXTERNAL_IP=$(dig +short myip.opendns.com @resolver1.opendns.com);
                ZITI_EDGE_CONTROLLER_IP_OVERRIDE="$EXTERNAL_IP";
                ZITI_EDGE_ROUTER_IP_OVERRIDE="$EXTERNAL_IP";
                ZITI_PWD=$(pwgen -s -n 32 -1)
                export EXTERNAL_IP
                export ZITI_EDGE_CONTROLLER_IP_OVERRIDE
                export ZITI_EDGE_ROUTER_IP_OVERRIDE
                export ZITI_PWD

                # shellcheck disable=SC1091
                source ${ziti-cli-functions}/bin/ziti-cli-functions.sh

                # Generate the initial ziti controller environment vars
                generateEnvFile

                # Link the nix pkgs openziti bins to the nix store path.
                # The functions refer to these
                ln -sf ${ziti-pkg}/bin/ziti "$ZITI_BIN_ROOT"/ziti
                ln -sf ${ziti-pkg}/bin/ziti-controller "$ZITI_BIN_ROOT"/ziti-controller

                # Create PoC controller pki
                createPki

                # Finish the cert setup (taken from createControllerConfig fn)
                cat "$ZITI_CTRL_IDENTITY_SERVER_CERT" > "$ZITI_CTRL_IDENTITY_CA"
                cat "$ZITI_SIGNING_CERT" >> "$ZITI_CTRL_IDENTITY_CA"
                echo -e "wrote CA file to: $ZITI_CTRL_IDENTITY_CA"

                # Initialize the database with the admin user:
                ziti-controller edge init ${controllerConfigFile} -u "$ZITI_USER" -p "$ZITI_PWD"

                # Include user defined pre start bootstrap scripting
                ${cfg.extraBootstrapPre}

                touch .bootstrap-pre-complete
              fi
            '';
          };
        in "${preScript}/bin/${zitiController}-preScript.sh";

        ExecStart = let
          script = pkgs.writeShellApplication {
            name = zitiController;
            text = ''
              exec ${ziti-controller-pkg}/bin/${zitiController} run ${controllerConfigFile}
            '';
          };
        in "${script}/bin/${zitiController}";

        ExecStartPost = let
          postScript = pkgs.writeShellApplication {
            name = "${zitiController}-postScript.sh";
            runtimeInputs = with pkgs; [curl ziti-pkg];
            text = ''
              if ! [ -f .bootstrap-post-complete ]; then
                # shellcheck disable=SC1091
                source ${ziti-cli-functions}/bin/ziti-cli-functions.sh

                # shellcheck disable=SC1090
                source "$ZITI_HOME/$ZITI_NETWORK.env"

                while [[ "$(curl -w "%{http_code}" -m 1 -s -k -o /dev/null https://"$ZITI_EDGE_CTRL_ADVERTISED_HOST_PORT"/version)" != "200" ]]; do
                  echo "waiting for https://$ZITI_EDGE_CTRL_ADVERTISED_HOST_PORT"
                  sleep 3
                done

                zitiLogin &> /dev/null
                ziti edge create edge-router-policy all-endpoints-public-routers --edge-router-roles "#public" --identity-roles "#all"
                ziti edge create service-edge-router-policy all-routers-all-services --edge-router-roles "#all" --service-roles "#all"

                # Include user defined pre start bootstrap scripting
                ${cfg.extraBootstrapPost}

                touch .bootstrap-post-complete
              fi
            '';
          };
        in "${postScript}/bin/${zitiController}-postScript.sh";
      };
    };
  };
}
