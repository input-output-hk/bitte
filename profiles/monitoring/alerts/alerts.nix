grafanaUrl: {
  groups =
    (import ./deadmans-snitch.nix grafanaUrl).groups ++
    (import ./victoria-metrics.nix grafanaUrl).groups;
}
