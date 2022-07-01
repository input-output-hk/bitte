{ ... }: {
  groups = [
    {
      name = "bitte-deadmanssnitch";
      rules = [{
        alert = "DeadMansSnitch";
        expr = "vector(1)";
        labels = { severity = "critical"; };
        annotations = {
          summary = "Alerting DeadMansSnitch.";
          description =
            "This is a DeadMansSnitch meant to ensure that the entire alerting pipeline is functional.";
        };
      }];
    }
  ];
}
