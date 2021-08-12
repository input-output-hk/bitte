{ lib, config, ... }: {
  services.promtail.configuration.scrape_configs = [{
    job_name = "journal";

    journal = {
      json = false;
      labels.job = "systemd-journal";
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
  }];
}
