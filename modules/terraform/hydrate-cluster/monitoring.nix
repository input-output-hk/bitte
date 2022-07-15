{
  lib,
  config,
  ...
}: {
  tf.hydrate-monitoring.configuration = let
    onlyTfDashboards = builtins.length config.services.grafana.provision.dashboards == 0;
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
    assert lib.asserts.assertMsg onlyTfDashboards (lib.warn dashHeader dashNote); {};
}
