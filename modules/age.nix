{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.age;

  # This pin has a 20 recipient limit
  # Ref:
  #  https://github.com/FiloSottile/age/issues/139
  # ageBin = "${pkgs.age}/bin/age";
  ageBin = "${pkgs.rage}/bin/rage";

  users = config.users.users;

  identities =
    builtins.concatStringsSep " " (map (path: "-i ${path}") cfg.sshKeyPaths);
  installSecret = secretType: ''
    echo "decrypting ${secretType.file} to ${secretType.path}..."

    TMP_FILE="${secretType.path}.tmp"
    TMP_FILE2="${secretType.path}.tmp2"

    mkdir -p $(dirname ${secretType.path})
    (
      umask u=r,g=,o=
      LANG=${config.i18n.defaultLocale} ${ageBin} --decrypt ${identities} -o "$TMP_FILE" "${secretType.file}"
      src="$TMP_FILE"
      out="$TMP_FILE2"
      ${secretType.script}
      mv "$out" "$src"
    )
    chmod ${secretType.mode} "$TMP_FILE"
    chown ${secretType.owner}:${secretType.group} "$TMP_FILE"
    mv -f "$TMP_FILE" '${secretType.path}'
  '';

  isRootSecret = st:
    (st.owner == "root" || st.owner == "0")
    && (st.group == "root" || st.group == "0");
  isNotRootSecret = st: !(isRootSecret st);

  rootOwnedSecrets =
    builtins.filter isRootSecret (builtins.attrValues cfg.secrets);
  installRootOwnedSecrets = builtins.concatStringsSep "\n"
    ([ "echo '[agenix] decrypting root secrets...'" ]
      ++ (map installSecret rootOwnedSecrets));

  nonRootSecrets =
    builtins.filter isNotRootSecret (builtins.attrValues cfg.secrets);
  installNonRootSecrets = builtins.concatStringsSep "\n"
    ([ "echo '[agenix] decrypting non-root secrets...'" ]
      ++ (map installSecret nonRootSecrets));

  secretType = types.submodule ({ config, name, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
        description = ''
          Name of the file used in /run/secrets
        '';
      };

      file = mkOption {
        type = types.path;
        description = ''
          Age file the secret is loaded from.
        '';
      };

      path = mkOption {
        type = types.str;
        default = "/run/secrets/${config.name}";
        description = ''
          Path where the decrypted secret is installed.
        '';
      };

      script = mkOption {
        type = types.str;
        default = "mv $src $out";
        description = ''
          script to run on the encrypted file to transform it.
        '';
      };

      mode = mkOption {
        type = types.str;
        default = "0400";
        description = ''
          Permissions mode of the in octal.
        '';
      };

      owner = mkOption {
        type = types.str;
        default = "0";
        description = ''
          User of the file.
        '';
      };

      group = mkOption {
        type = types.str;
        default = users.${config.owner}.group or "0";
        description = ''
          Group of the file.
        '';
      };
    };
  });
in
{
  options.age = {
    encryptedRoot = lib.mkOption { type = types.path; };

    secrets = mkOption {
      type = types.attrsOf secretType;
      default = { };
      description = ''
        Attrset of secrets.
      '';
    };

    sshKeyPaths = mkOption {
      type = types.listOf types.path;
      default =
        if config.services.openssh.enable then
          map (e: e.path)
            (lib.filter (e: e.type == "ed25519") config.services.openssh.hostKeys)
        else
          [ ];
      description = ''
        Path to SSH keys to be used as identities in age decryption.
      '';
    };
  };
  config = mkIf (cfg.secrets != { }) {
    assertions = [{
      assertion = cfg.sshKeyPaths != [ ];
      message = "age.sshKeyPaths must be set.";
    }];

    # Secrets with root owner and group can be installed before users
    # exist. This allows user password files to be encrypted.
    system.activationScripts.agenixRoot =
      stringAfter [ ] installRootOwnedSecrets;
    system.activationScripts.users.deps = [ "agenixRoot" ];

    # Other secrets need to wait for users and groups to exist.
    system.activationScripts.agenix =
      stringAfter [ "users" "groups" ] installNonRootSecrets;
  };
}
