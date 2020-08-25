{ writeShellScriptBin, writeReferencesToFile, writeText, bash, lib, systemd
, nixFlakes }:
{ name, command, args ? [ ], env ? { }, extraSystemdProperties ? { }
, resources ? { } }:
let
  inherit (builtins) foldl' typeOf attrNames attrValues;
  inherit (lib) flatten pathHasContext isDerivation;

  onlyStringsWithContext = sum: input:
    let type = typeOf input;
    in sum ++ {
      string = if pathHasContext input then [ input ] else [ ];
      list = (foldl' (s: v: s ++ (onlyStringsWithContext [ ] v)) [ ] input);
      set = if isDerivation input then
        [ input ]
      else
        (onlyStringsWithContext [ ] (attrNames input))
        ++ (onlyStringsWithContext [ ] (attrValues input));
    }.${typeOf input} or [ ];

  closure = writeText "${name}-closure" (lib.concatStringsSep "\n"
    (onlyStringsWithContext [ ] [ command args env bash ]));

  references = writeReferencesToFile closure;

  lines = (lib.splitString "\n" (lib.fileContents references));
  cleanLines = lib.remove closure.outPath lines;

  paths = map (line: "${line}:${line}") cleanLines;

  transformAttrs = transformer:
    lib.mapAttrsToList (name: value: "${name}=${transformer value}");

  toSystemd = value:
    if value == true then
      "yes"
    else if value == false then
      "no"
    else
      toString value;

  toSystemdProperties = transformAttrs toSystemd;

  systemdRunFlags = lib.cli.toGNUCommandLineShell { } {
    # unit = "figure-out-a-way-to-name-it-nicely";
    service-type = "exec";
    collect = true;
    scope = true;
    # wait = true;
    pipe = true;
    setenv = transformAttrs toString env;
    property = transformAttrs toSystemd ({
      MemoryMax = "1G";
      # CPUWeight = "50";
      # CPUQuota = "20%";
      # DynamicUser = true;
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

  runner = writeShellScriptBin "systemd-runner" ''
    set -exuo pipefail

    echo "entering ${placeholder "out"}/bin/runner"
    echo "dependencies: ${toString cleanLines}"

    exec ${systemd}/bin/systemd-run \
      --setenv "INVOCATION_ID=$INVOCATION_ID" \
      --setenv "NOMAD_ALLOC_DIR=$NOMAD_ALLOC_DIR" \
      --setenv "NOMAD_ALLOC_ID=$NOMAD_ALLOC_ID" \
      --setenv "NOMAD_ALLOC_INDEX=$NOMAD_ALLOC_INDEX" \
      --setenv "NOMAD_ALLOC_NAME=$NOMAD_ALLOC_NAME" \
      --setenv "NOMAD_CPU_LIMIT=$NOMAD_CPU_LIMIT" \
      --setenv "NOMAD_DC=$NOMAD_DC" \
      --setenv "NOMAD_GROUP_NAME=$NOMAD_GROUP_NAME" \
      --setenv "NOMAD_JOB_NAME=$NOMAD_JOB_NAME" \
      --setenv "NOMAD_MEMORY_LIMIT=$NOMAD_MEMORY_LIMIT" \
      --setenv "NOMAD_NAMESPACE=$NOMAD_NAMESPACE" \
      --setenv "NOMAD_REGION=$NOMAD_REGION" \
      --setenv "NOMAD_SECRETS_DIR=$NOMAD_SECRETS_DIR" \
      --setenv "NOMAD_TASK_DIR=$NOMAD_TASK_DIR" \
      --setenv "NOMAD_TASK_NAME=$NOMAD_TASK_NAME" \
      --setenv "HOME=$NOMAD_TASK_DIR" \
      --property BindPaths="$NOMAD_ALLOC_DIR:$NOMAD_ALLOC_DIR $NOMAD_SECRETS_DIR:$NOMAD_SECRETS_DIR $NOMAD_TASK_DIR:$NOMAD_TASK_DIR" \
      ${systemdRunFlags} --  ${toString command} ${toString args}
  '';
in {
  inherit name env;

  driver = "raw_exec";

  inherit resources;

  config = {
    command = "${bash}/bin/bash";
    args = [
      "-c"
      ''
        set -exuo pipefail
        ${nixFlakes}/bin/nix-store -r ${runner}
        exec ${runner}/bin/systemd-runner
      ''
    ];
  };
}
