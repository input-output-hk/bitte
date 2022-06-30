grafanaUrl: {
  groups = [
    {
      concurrency = 2;
      interval = "30s";
      name = "bitte-loki";
      rules = [
        {
          alert = "HighFail2banRate";
          annotations = {
            dashboard =
              "${grafanaUrl}/explore?orgId=1&left=%7B%22datasource%22:%22Loki%22,%22queries%22:%5B%7B%22refId%22:%22A%22,%22expr%22:%22sum(count_over_time(%7Bsyslog_identifier%3D%5C%22fail2ban.actions%5C%22%7D%5B1h%5D%20%7C%3D%20%5C%22Ban%5C%22))%20%3E%202%22,%22queryType%22:%22range%22,%22editorMode%22:%22code%22%7D%5D,%22range%22:%7B%22from%22:%22now-24h%22,%22to%22:%22now%22%7D%7D";
            description =
              "Fail2ban has observed {{ $value | humanize }} bans over the past hour, which is over the trigger threshold of 100.";
            summary =
              "Fail2ban has observed {{ $value | humanize }} bans over the past hour, which is over the trigger threshold of 100.";
          };
          expr =
            "sum(count_over_time({syslog_identifier=\"fail2ban.actions\"}[1h] |= \"Ban\")) > 100";
          for = "1m";
          labels = { severity = "critical"; };
        }
      ];
    }
  ];
}
