# Bootstrap monitoring dashboards and alerts.
#
# Any attributes which need to be passed to .nix declarative alert files for interpolation
# should be defined at the _proto level, typically in: nix/cloud/hydrationProfile.nix.
#
# These attribute declarations for passing should be made to the following options for
# VictoriaMetrics and Loki alerts, respectively:
#
#  services.vmalert.datasources.vm.importAttrs
#  services.vmalert.datasources.loki.importAttrs
#
# An example may be to parameterize alerts with some constants from the constants organelle.
{ self, lib, config, bittelib, terralib, ... }:
let
  inherit (terralib) var;

  cfg = config.services.vmalert.datasources;

  appendSuffix = suffix: name: "${name}${suffix}";

  checkForNameCollision = filenames: lib.pipe filenames [
    (map (filename: lib.last (builtins.split "/" filename)))
    (lib.foldl (acc: check: acc ++ (if (builtins.elem check acc) then throw "Duplicate node name: ${check}" else [ check ])) [])
    (let passThrough = list: filenames; in passThrough)
  ];

  filenameToAttrName = file: lib.pipe file [
    (builtins.split "/")
    lib.last
    (lib.removeSuffix ".nix")
  ];

  lintImport = nvp: let
    allTrue = bool: bool;
    check = checkFn: msg: nvp: if checkFn then nvp else throw msg;
  in lib.pipe nvp [
    (check (nvp.value ? "groups") ''Declarative alert file does not contain "groups" attribute: ${nvp.name}'')

    (check (builtins.isList nvp.value.groups) ''Declarative alert file contains a "groups" attribute that is not a list: ${nvp.name}'')

    (check (if (builtins.length nvp.value.groups) == 0 then (builtins.trace ''WARN: Declarative alert file has no group list items: ${nvp.name}'' true) else true)  "Undefined error")

    (check (lib.all allTrue (map (group: if group ? "name" then true else false) nvp.value.groups))
      ''Declarative alert file has a missing "name" attribute in one of the group list items: ${nvp.name}'')

    (check (lib.all allTrue (map (group: if group ? "rules" then true else false) nvp.value.groups))
      ''Declarative alert file has a missing "rules" attribute in one of the group list items: ${nvp.name}'')

    (check (lib.all allTrue (map (group: builtins.isList group.rules) nvp.value.groups))
      ''Declarative alert file contains a group list item with a "rules" attribute that is not a list: ${nvp.name}'')

    (check (lib.all allTrue (map (group:
      if (builtins.length group.rules) == 0
      then (builtins.trace ''WARN: Declarative alert file has a group list item with no rules: ${nvp.name}'' true)
      else true
    ) nvp.value.groups)) "Undefined error")
  ];

  # Import the alert files, with interpolation, and check minimal alert syntax requirements
  importAndLint = ds: filenames: lib.pipe filenames [
    (map (file: lib.nameValuePair file (import file (cfg.${ds}.importAttrs or {}))))
    (map (nvp: lintImport nvp))
  ];

  nixFiles = dirs: lib.pipe dirs [
    (lib.foldl (acc: dir: acc ++ lib.filesystem.listFilesRecursive dir) [])
    (lib.filter (name: lib.hasSuffix ".nix" name))
  ];

  alertKvResource = ds: name: contents: let
    tfName = bittelib.kv.sanitizeFile name;
  in {
    name = "vmalert_${ds}_${tfName}";
    value = {
      path = "kv/alerts/${ds}/${name}";
      data_json = contents;
      delete_all_versions = true;
    };
  };

  mkAlertKv = ds: dirs: lib.pipe (nixFiles dirs) [
    checkForNameCollision
    (importAndLint ds)
    (map (nvp: { name = filenameToAttrName nvp.name; value = builtins.toJSON nvp.value; }))
    (lib.foldl (acc: v: acc ++ [ (alertKvResource ds v.name v.value) ]) [])
  ];
in {
  tf.hydrate-monitoring.configuration = {
    resource.vault_generic_secret = (lib.listToAttrs (
      mkAlertKv "vm" [ "${self.inputs.bitte}/profiles/monitoring/alerts/vm" "${self}/nix/cloud/alerts/vm" ] ++
      mkAlertKv "loki" [ "${self.inputs.bitte}/profiles/monitoring/alerts/loki" "${self}/nix/cloud/alerts/loki" ]
    ));
  };
}
