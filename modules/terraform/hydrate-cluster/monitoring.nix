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

  allTrue = bool: bool;

  checkForNameCollision = filenames: lib.pipe filenames [
    (map (filename: lib.last (builtins.split "/" filename)))
    (lib.foldl (acc: check: acc ++ (if (builtins.elem check acc) then throw "Duplicate node name: ${check}" else [ check ])) [])
    (let passThrough = list: filenames; in passThrough)
  ];

  filenameToAttrName = suffix: file: lib.pipe file [
    (builtins.split "/")
    lib.last
    (lib.removeSuffix suffix)
  ];

  lintImport = nvp: let
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
  importAndLintAlerts = ds: filenames: lib.pipe filenames [
    (map (file: lib.nameValuePair file (import file (cfg.${ds}.importAttrs or {}))))
    (map (nvp: lintImport nvp))
  ];

  filterFiles = suffix: dirs: lib.pipe dirs [
    (lib.foldl (acc: dir: acc ++ lib.filesystem.listFilesRecursive dir) [])
    (lib.filter (name: lib.hasSuffix suffix name))
  ];

  alertKvResource = ds: name: path: let
    tfName = bittelib.kv.normalizeTfName name;
  in {
    name = "vmalert_${ds}_${tfName}";
    value = {
      path = "kv/alerts/${ds}/${name}";
      data_json = var ''file("${path}")'';
      delete_all_versions = true;
    };
  };

  dashKvResource = name: path: let
    tfName = bittelib.kv.normalizeTfName name;
  in {
    name = "grafana_dashboard_${tfName}";
    value = {
      path = "kv/dashboards/${name}";
      data_json = var ''file("${path}")'';
      delete_all_versions = true;
    };
  };

  mkAlertKv = ds: dirs: lib.pipe (filterFiles ".nix" dirs) [
    checkForNameCollision
    (importAndLintAlerts ds)
    (map (nvp: rec { name = filenameToAttrName ".nix" nvp.name; value = builtins.toFile "${name}.json" (builtins.toJSON nvp.value); }))
    (lib.foldl (acc: v: acc ++ [ (alertKvResource ds v.name v.value) ]) [])
  ];

  mkDashKv = dirs: lib.pipe (filterFiles ".json" dirs) [
    checkForNameCollision
    (map (file: lib.nameValuePair (filenameToAttrName ".json" file) file))
    (lib.foldl (acc: v: acc ++ [ (dashKvResource v.name v.value) ]) [])
  ];
in {
  tf.hydrate-monitoring.configuration = let
    tipVmCheck = _: if (cfg ? "vm" && cfg.vm ? "importAttrs") then _ else (builtins.trace tipVmMsg _);
    tipLokiCheck = _: if (cfg ? "loki" && cfg.loki ? "importAttrs") then _ else (builtins.trace tipLokiMsg _);
    dashCheck = _: builtins.length config.services.grafana.provision.dashboards == 0;
    onlyTfDashboards = lib.pipe null [
      dashCheck
      tipVmCheck
      tipLokiCheck
    ];
    tipVmMsg = ''
      TIP:
      Victoriametrics alert interpolation can be acheived by setting: services.vmalert.datasources.vm.importAttrs
      This is declared at the _proto level, typically in nix/cloud/hydrationProfile.nix.
    '';
    tipLokiMsg = ''
      TIP:
      Loki alert interpolation can be acheived by setting: services.vmalert.datasources.loki.importAttrs
      This is declared at the _proto level, typically in nix/cloud/hydrationProfile.nix.
    '';
    dashHeader = "Extra grafana provisioning dashboard declaration detected";
    dashNote = ''
      FAIL

      A legacy grafana provisioning dashboard declaration has been detected.
      This is no longer required now that alerts and dashboards are populated
      through terraform hydrate-monitoring.  Please remove the legacy declaration
      as it will otherwise cause a duplication of dashboards in grafana.

      The code to be removed is defined at the _proto level,
      typically in: nix/cloud/hydrationProfile.nix.

      It will be a nix block appearing similar to the following:

      services.grafana.provision.dashboards = [
        {
          name = "$CLUSTER_PROVISIONING_NAME";
          options.path = ./dashboards;
        }
      ];
    '';
  in
    assert lib.asserts.assertMsg onlyTfDashboards (lib.warn dashHeader dashNote);
  {
    resource.vault_generic_secret = (lib.listToAttrs (
      mkAlertKv "vm" [ "${self.inputs.bitte}/profiles/monitoring/alerts/vm" "${self}/nix/cloud/alerts/vm" ] ++
      mkAlertKv "loki" [ "${self.inputs.bitte}/profiles/monitoring/alerts/loki" "${self}/nix/cloud/alerts/loki" ]
    )) // (lib.listToAttrs (
      mkDashKv [ "${self.inputs.bitte}/profiles/monitoring/dashboards" "${self}/nix/cloud/dashboards" ]
    ));
  };
}
