{
  lib,
  config,
  pkgs,
  ...
}: let
  mkStringOptionType = description:
    lib.mkOption {
      inherit description;
      type = lib.types.str;
    };

  mkOptionalStringOptionType = description:
    lib.mkOption {
      inherit description;
      type = lib.types.nullOr lib.types.str;
      default = null;
    };

  mkAttrsOptionType = description:
    lib.mkOption {
      inherit description;
      type = lib.types.attrs;
    };

  mkProviderOptionType = description:
    lib.mkOption {
      inherit description;
      type = lib.types.enum ["AWS"];
    };

  cfg = config.bitte;

  asgRegionString = asg: let
    asgRegions =
      lib.attrValues
      (lib.mapAttrs (_: v: v.region) asg);
  in
    lib.strings.replaceStrings [" "] [":"]
    (toString asgRegions);
in {
  _file = ./devshellModule.nix;

  options.bitte = {
    cluster = mkStringOptionType "Name of the cluster";
    domain = mkStringOptionType "Cluster root domain";
    namespace = mkOptionalStringOptionType "Cluster main nomad namespace";
    cert = mkOptionalStringOptionType "Certificate to authenticate with nomad, vault & consul";
    provider = mkProviderOptionType "Infrastructure provider";

    aws_region = mkStringOptionType "AWS infrastructure region";
    aws_profile = mkStringOptionType "AWS authentication profile";
    aws_autoscaling_groups = mkAttrsOptionType "AWS auto scaling groups";
  };

  config = {
    # tempfix: remove when merged https://github.com/numtide/devshell/pull/123
    devshell.startup.load_profiles = lib.mkForce (lib.noDepEntry "");

    name = cfg.cluster;

    env =
      [
        {
          name = "BITTE_CLUSTER";
          value = cfg.cluster;
        }
        {
          name = "BITTE_DOMAIN";
          value = cfg.domain;
        }
        {
          name = "BITTE_PROVIDER";
          value = cfg.provider;
        }
        {
          name = "VAULT_ADDR";
          value = "https://vault.${cfg.domain}";
        }
        {
          name = "NOMAD_ADDR";
          value = "https://nomad.${cfg.domain}";
        }
        {
          name = "CONSUL_HTTP_ADDR";
          value = "https://consul.${cfg.domain}";
        }
      ]
      ++ (lib.optionals (cfg.namespace != null)) [
        {
          name = "NOMAD_NAMESPACE";
          value = cfg.namespace;
        }
      ]
      ++ (lib.optionals (cfg.cert != null)) [
        {
          name = "CONSUL_CACERT";
          value = cfg.cert;
        }
        {
          name = "VAULT_CACERT";
          value = cfg.cert;
        }
        {
          name = "NOMAD_CACERT";
          value = cfg.cert;
        }
      ]
      ++ (lib.optionals (cfg.provider == "AWS")) [
        {
          name = "AWS_PROFILE";
          value = cfg.aws_profile;
        }
        {
          name = "AWS_DEFAULT_REGION";
          value = cfg.aws_region;
        }
        {
          name = "AWS_ASG_REGIONS";
          value = asgRegionString cfg.aws_autoscaling_groups;
        }
      ];
  };
}
