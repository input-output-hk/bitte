{ ... }: {
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
              ''{{ $externalURL }}/explore?left={"datasource":"Loki","queries":[{"datasource":"Loki","expr":"sum(count_over_time({syslog_identifier=\"fail2ban.actions\"}[1h] |= \"Ban\")) > 100","refId":"A"}],"range":{"from":"now-1h","to":"now"}}&orgId=1'';
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
