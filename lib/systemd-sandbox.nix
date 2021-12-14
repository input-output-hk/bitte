{ writeShellScript, writeReferencesToFile, writeText, bash, lib, systemd
, systemd-runner, nixFlakes, cacert, gawk, coreutils }:
{ name, command, args ? [ ], env ? { }, extraSystemdProperties ? { }
, resources ? { }, templates ? [ ], artifacts ? [ ], vault ? null
, restartPolicy ? null, services ? { }, extraEnvironmentVariables ? [ ]
, volumeMounts ? { }, mountPaths ? { } }:
let
  inherit (builtins) foldl' typeOf attrNames attrValues;

  standardEnvironmentVariables = [ "INVOCATION_ID" ];

  onlyStringsWithContext = sum: input:
    let type = typeOf input;
    in sum ++ {
      string = if lib.pathHasContext input then [ input ] else [ ];
      list = foldl' (s: v: s ++ (onlyStringsWithContext [ ] v)) [ ] input;
      set = if lib.isDerivation input then
        [ input ]
      else
        (onlyStringsWithContext [ ] (attrNames input))
        ++ (onlyStringsWithContext [ ] (attrValues input));
    }.${typeOf input} or [ ];

  closure = writeText "${name}-closure" (lib.concatStringsSep "\n"
    (onlyStringsWithContext [ ] [ command args env bash ]));

  references = writeReferencesToFile closure;

  lines = lib.splitString "\n" (lib.fileContents references);
  cleanLines = lib.remove closure.outPath lines;

  paths = map (line: "${line}:${line}") cleanLines;

  transformAttrs = transformer:
    lib.mapAttrsToList (name: value: "${name}=${transformer value}");

  toSystemd = value:
    if value then "yes" else if !value then "no" else toString value;

  toSystemdProperties = transformAttrs toSystemd;

  systemdRunFlags = lib.cli.toGNUCommandLineShell { } {
    # unit = "figure-out-a-way-to-name-it-nicely";
    collect = true;
    wait = true;
    pty = true;
    setenv = transformAttrs toString env;
    property = transformAttrs toSystemd ({
      MemoryMax = "${toString (resources.memoryMB or 1024)}M";
      # CPUWeight = "50";
      # CPUQuota = "20%";
      User = "nobody";
      Group = "nogroup";
      KillMode = "mixed";
      PrivateDevices = true;
      ProtectSystem = true;
      PrivateMounts = true;
      PrivateUsers = true;
      PrivateTmp = true;
      MountAPIVFS = true;
      # RootDirectory = "/tmp/run";
      BindReadOnlyPaths = paths;
      TemporaryFileSystem = "/nix/store:ro";
      ProtectHome = true;
      # MemoryDenyWriteExecute = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
    } // extraSystemdProperties);
  };

  hasMounts = (builtins.length (builtins.attrNames mountPaths)) > 0;
  mount = lib.optionalString hasMounts ''
    export NOMAD_MOUNT_TASK="${
      builtins.concatStringsSep " "
      (lib.mapAttrsToList (key: value: "${key}:${value}") mountPaths)
    }"
  '';

  # NOMAD_ALLOC_DIR

  runner = writeShellScript "systemd-runner" ''
    set -exuo pipefail

    export PATH="$PATH:${lib.makeBinPath [ systemd systemd-runner ]}"

    echo "entering ${placeholder "out"}/bin/runner"
    echo "dependencies: ${toString cleanLines}"

    ${mount}

    exec systemd-runner \
      ${
        lib.concatStringsSep "\n" (map (e: ''--setenv "${e}=''$${e}" \'')
          (standardEnvironmentVariables ++ extraEnvironmentVariables))
      }
      ${systemdRunFlags} -- ${toString command} ${toString args}
  '';
in {
  inherit name env;

  driver = "raw_exec";

  inherit resources templates artifacts vault services restartPolicy
    volumeMounts;

  config = {
    command = "${bash}/bin/bash";
    args = [
      "-c"
      ''
        set -exuo pipefail
        /run/current-system/sw/bin/nix-store -r ${runner}

        exec ${runner} | ${coreutils}/bin/tee >(${systemd}/bin/systemd-cat -t "${name}")
      ''
    ];
  };
}
