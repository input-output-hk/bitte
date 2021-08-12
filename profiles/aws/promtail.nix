{ lib, config, ... }: {
  services.promtail.configuration.scrape_configs = [
    {
      ec2_sd_configs = [{ region = config.cluster.region; }];

      job_name = "ec2-logs";

      relabel_configs = [
        {
          action = "replace";
          source_labels = [ "__meta_ec2_tag_Name" ];
          target_label = "name";
        }
        {
          action = "replace";
          source_labels = [ "__meta_ec2_instance_id" ];
          target_label = "instance";
        }
        {
          action = "replace";
          source_labels = [ "__meta_ec2_availability_zone" ];
          target_label = "zone";
        }
        {
          action = "replace";
          replacement = "/var/log/**.log";
          target_label = "__path__";
        }
        {
          regex = "(.*)";
          source_labels = [ "__meta_ec2_private_dns_name" ];
          target_label = "__host__";
        }
      ];
    }
    {
      job_name = "journal";

      journal = {
        json = false;
        labels = {
          job = "systemd-journal";
          region = config.cluster.region;
        };
        max_age = "12h";
        path = "/var/log/journal";
      };

      relabel_configs = [
        {
          source_labels = [ "__journal__systemd_unit" ];
          target_label = "unit";
        }
        {
          source_labels = [ "__journal__hostname" ];
          target_label = "host";
        }
        {
          source_labels = [ "__journal_syslog_identifier" ];
          target_label = "syslog_identifier";
        }
        {
          source_labels = [ "__journal_container_tag" ];
          target_label = "container_tag";
        }
        {
          source_labels = [ "__journal_namespace" ];
          target_label = "namespace";
        }
        {
          source_labels = [ "__journal_container_name" ];
          target_label = "container_name";
        }
        {
          source_labels = [ "__journal_image_name" ];
          target_label = "image_name";
        }
      ];
    }
  ];
}
