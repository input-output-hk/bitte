{ lib, config, ... }:
let
  inherit (builtins) mapAttrs;
  inherit (lib)
    mapAttrsToList concatStringsSep mkOption optionalString listToAttrs remove
    flip;
  inherit (lib.types) submodule str attrsOf ints enum bool nullOr either listOf;
  inherit (config.cluster) domain;

  optStr = cond: value:
    let notEmpty = (cond != null) && (cond != { }) && (cond != [ ]);
    in optionalString notEmpty value;

  backends = let
    mapBackend = (name: opt: ''
      backend ${name}
        balance ${opt.balance}
        ${opt.extraConfig}
        default-server ${
          concatStringsSep " "
          (remove "" (mapAttrsToList (n: v: v) opt.default-server))
        }
        ${
          optStr opt.server (concatStringsSep "\n  "
            (flip mapAttrsToList opt.server (serverName: serverOpt:
              "server ${serverName} ${serverOpt.fqdn}")))
        }
        ${
          optStr opt.server-template ''
            server-template ${opt.server-template.prefix} ${
              toString opt.server-template.count
            } ${opt.server-template.fqdn}
          ''
        }
    '');
  in concatStringsSep "\n"
  (mapAttrsToList mapBackend config.services.haproxy.backend);

  resolvers = let
    mapResolver = (name: res: ''
      resolvers ${name}
        ${optStr res.nameserver "nameserver ${res.nameserver}"}
        ${
          optStr res.accepted_payload_size
          "accepted_payload_size ${toString res.accepted_payload_size}"
        }
        ${optStr res.hold "hold ${res.hold}"}
    '');
  in concatStringsSep "\n"
  (mapAttrsToList mapResolver config.services.haproxy.resolvers);

  frontends = let
    mapFrontend = (name: fro: ''
      frontend ${name}
        bind ${fro.bind}
        ${fro.extraConfig}
    '');
  in concatStringsSep "\n"
  (mapAttrsToList mapFrontend config.services.haproxy.frontend);

  timeoutOption = mkOption {
    default = { };
    type = submodule {
      options = {
        connect = mkOption {
          type = ints.positive;
          default = 5000;
        };

        check = mkOption {
          type = ints.positive;
          default = 5000;
        };

        client = mkOption {
          type = ints.positive;
          default = 30000;
        };

        server = mkOption {
          type = ints.positive;
          default = 30000;
        };
      };
    };
  };
in {
  options = {
    services.haproxy = {
      resolvers = mkOption {
        default = { };
        type = attrsOf (submodule {
          options = {
            nameserver = mkOption {
              type = nullOr str;
              default = null;
            };
            accepted_payload_size = mkOption {
              type = nullOr ints.positive;
              default = null;
            };
            hold = mkOption {
              type = nullOr str;
              default = null;
            };
          };
        });
      };

      frontend = mkOption {
        default = { };
        type = attrsOf (submodule {
          options = {
            bind = mkOption { type = str; };
            timeout = timeoutOption;
            extraConfig = mkOption {
              type = str;
              default = "";
            };
          };
        });
      };

      backend = mkOption {
        default = { };
        type = attrsOf (submodule {
          options = {
            balance = mkOption {
              type = str;
              default = "leastconn";
            };

            extraConfig = mkOption {
              type = str;
              default = "";
            };

            server = mkOption {
              default = { };
              type = attrsOf
                (submodule { options = { fqdn = mkOption { type = str; }; }; });
            };

            default-server = mkOption {
              type = nullOr (submodule {
                options = {
                  ca-file = mkOption {
                    type = nullOr str;
                    default = null;
                    apply = v: if v != null then "ca-file ${v}" else "";
                  };

                  proto = mkOption {
                    type = nullOr str;
                    default = null;
                    apply = v: if v != null then "proto ${v}" else "";
                  };

                  option = mkOption {
                    type = nullOr (attrsOf bool);
                    default = null;
                    apply = v:
                      if v != null then
                        concatStringsSep " "
                        (mapAttrsToList (name: value: "option ${name}") v)
                      else
                        "";
                  };

                  check = mkOption {
                    default = true;
                    type = nullOr bool;
                    apply = v: if v == true then "check" else "";
                  };

                  check-ssl = mkOption {
                    default = false;
                    type = nullOr bool;
                    apply = v: if v == true then "check-ssl" else "";
                  };

                  maxconn = mkOption {
                    default = 20;
                    type = nullOr ints.positive;
                    apply = v:
                      if v != null then "maxconn ${toString v}" else "";
                  };

                  resolve-opts = mkOption {
                    default = null;
                    type = nullOr (listOf str);
                    apply = v:
                      if v != null then
                        "resolve-opts ${concatStringsSep "," v}"
                      else
                        "";
                  };

                  resolve-prefer = mkOption {
                    default = null;
                    type = nullOr (enum [ "ipv6" "ipv4" ]);
                    apply = v: if v != null then "resolve-prefer ${v}" else "";
                  };

                  resolvers = mkOption {
                    default = null;
                    type = nullOr (listOf str);
                    apply = v:
                      if v != null then
                        "resolvers ${concatStringsSep "," v}"
                      else
                        "";
                  };

                  ssl = mkOption {
                    default = null;
                    type = nullOr bool;
                    apply = v: if v == true then "ssl" else "";
                  };

                  verify = mkOption {
                    type = nullOr (enum [ "none" "required" ]);
                    default = null;
                    apply = v: if v != null then "verify ${v}" else "";
                  };
                };
              });
            };

            server-template = mkOption {
              default = null;
              type = nullOr (submodule {
                options = {
                  prefix = mkOption { type = str; };

                  count = mkOption {
                    type = ints.positive;
                    default = 1;
                  };

                  fqdn = mkOption { type = str; };
                };
              });
            };
          };
        });
      };
    };
  };

  config = {
    services.haproxy = {
      config = ''
        global
          log /dev/log local0 info
          tune.ssl.default-dh-param 2048

        defaults
          log global
          mode http
          option httplog
          option dontlognull
          option forwardfor
          option http-server-close
          timeout connect 5000ms
          timeout check 5000ms
          timeout client 30000ms
          timeout server 30000ms
          default-server init-addr none

        ${resolvers}

        ${frontends}

        ${backends}
      '';
    };
  };
}
