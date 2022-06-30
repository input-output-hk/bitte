grafanaUrl: {
  groups = [
    {
      name = "bitte-victoriametrics-health";
      rules = [
        {
          alert = "TooManyRestarts";
          annotations = {
            description =
              "Job {{ $labels.job }} has restarted more than twice in the last 15 minutes. It might be crashlooping.";
            summary =
              "{{ $labels.job }} too many restarts (instance {{ $labels.instance }})";
          };
          expr = ''
            changes(process_start_time_seconds{job=~"victoriametrics|vmagent|vmalert"}[15m]) > 2'';
          labels = { severity = "critical"; };
        }
        {
          alert = "ServiceDown";
          annotations = {
            description =
              "{{ $labels.instance }} of job {{ $labels.job }} has been down for more than 2 minutes.";
            summary =
              "Service {{ $labels.job }} is down on {{ $labels.instance }}";
          };
          expr = ''up{job=~"victoriametrics|vmagent|vmalert"} == 0'';
          for = "2m";
          labels = { severity = "critical"; };
        }
        {
          alert = "ProcessNearFDLimits";
          annotations = {
            description =
              "Exhausting OS file descriptors limit can cause severe degradation of the process. Consider to increase the limit as fast as possible.";
            summary = ''
              Number of free file descriptors is less than 100 for "{{ $labels.job }}"("{{ $labels.instance }}") for the last 5m'';
          };
          expr = "(process_max_fds - process_open_fds) < 100";
          for = "5m";
          labels = { severity = "critical"; };
        }
        {
          alert = "TooHighMemoryUsage";
          annotations = {
            description =
              "Too high memory usage may result into multiple issues such as OOMs or degraded performance. Consider to either increase available memory or decrease the load on the process.";
            summary = ''
              It is more than 90% of memory used by "{{ $labels.job }}"("{{ $labels.instance }}") during the last 5m'';
          };
          expr =
            "(process_resident_memory_anon_bytes / vm_available_memory_bytes) > 0.9";
          for = "5m";
          labels = { severity = "critical"; };
        }
      ];
    }
    {
      concurrency = 2;
      interval = "30s";
      name = "bitte-victoriametrics-standalone";
      rules = [
        {
          alert = "DiskRunsOutOfSpaceIn3Days";
          annotations = {
            dashboard =
              "${grafanaUrl}/d/wNf0q_kZk?viewPanel=73&var-instance={{ $labels.instance }}";
            description = ''
              Taking into account current ingestion rate, free disk space will be enough only for {{ $value | humanizeDuration }} on instance {{ $labels.instance }}.
               Consider to limit the ingestion rate, decrease retention or scale the disk space if possible.'';
            summary =
              "Instance {{ $labels.instance }} will run out of disk space soon";
          };
          expr = ''
            vm_free_disk_space_bytes / ignoring(path)
            (
               (
                rate(vm_rows_added_to_storage_total[1d]) -
                ignoring(type) rate(vm_deduplicated_samples_total{type="merge"}[1d])
               )
              * scalar(
                sum(vm_data_size_bytes{type!="indexdb"}) /
                sum(vm_rows{type!="indexdb"})
               )
            ) < 3 * 24 * 3600
          '';
          for = "30m";
          labels = { severity = "critical"; };
        }
        {
          alert = "DiskRunsOutOfSpace";
          annotations = {
            dashboard =
              "${grafanaUrl}/d/wNf0q_kZk?viewPanel=53&var-instance={{ $labels.instance }}";
            description = ''
              Disk utilisation on instance {{ $labels.instance }} is more than 80%.
               Having less than 20% of free disk space could cripple merges processes and overall performance. Consider to limit the ingestion rate, decrease retention or scale the disk space if possible.'';
            summary =
              "Instance {{ $labels.instance }} will run out of disk space soon";
          };
          expr = ''
            sum(vm_data_size_bytes) by(instance) /
            (
             sum(vm_free_disk_space_bytes) by(instance) +
             sum(vm_data_size_bytes) by(instance)
            ) > 0.8
          '';
          for = "30m";
          labels = { severity = "critical"; };
        }
        {
          alert = "RequestErrorsToAPI";
          annotations = {
            dashboard =
              "${grafanaUrl}/d/wNf0q_kZk?viewPanel=35&var-instance={{ $labels.instance }}";
            description =
              "Requests to path {{ $labels.path }} are receiving errors. Please verify if clients are sending correct requests.";
            summary =
              "Too many errors served for path {{ $labels.path }} (instance {{ $labels.instance }})";
          };
          expr = "increase(vm_http_request_errors_total[5m]) > 0";
          for = "15m";
          labels = { severity = "warning"; };
        }
        {
          alert = "ConcurrentFlushesHitTheLimit";
          annotations = {
            dashboard =
              "${grafanaUrl}/d/wNf0q_kZk?viewPanel=59&var-instance={{ $labels.instance }}";
            description = ''
              The limit of concurrent flushes on instance {{ $labels.instance }} is equal to number of CPUs.
               When VictoriaMetrics constantly hits the limit it means that storage is overloaded and requires more CPU.'';
            summary =
              "VictoriaMetrics on instance {{ $labels.instance }} is constantly hitting concurrent flushes limit";
          };
          expr =
            "avg_over_time(vm_concurrent_addrows_current[1m]) >= vm_concurrent_addrows_capacity";
          for = "15m";
          labels = { severity = "warning"; };
        }
        {
          alert = "TooManyLogs";
          annotations = {
            dashboard =
              "${grafanaUrl}/d/wNf0q_kZk?viewPanel=67&var-instance={{ $labels.instance }}";
            description = ''
              Logging rate for job "{{ $labels.job }}" ({{ $labels.instance }}) is {{ $value }} for last 15m.
               Worth to check logs for specific error messages.'';
            summary = ''
              Too many logs printed for job "{{ $labels.job }}" ({{ $labels.instance }})'';
          };
          expr = ''
            sum(increase(vm_log_messages_total{level!="info"}[5m])) by (job, instance) > 0'';
          for = "15m";
          labels = { severity = "warning"; };
        }
        {
          alert = "RowsRejectedOnIngestion";
          annotations = {
            dashboard =
              "${grafanaUrl}/d/wNf0q_kZk?viewPanel=58&var-instance={{ $labels.instance }}";
            description = ''
              VM is rejecting to ingest rows on "{{ $labels.instance }}" due to the following reason: "{{ $labels.reason }}"'';
            summary = ''
              Some rows are rejected on "{{ $labels.instance }}" on ingestion attempt'';
          };
          expr =
            "sum(rate(vm_rows_ignored_total[5m])) by (instance, reason) > 0";
          for = "15m";
          labels = { severity = "warning"; };
        }
        {
          alert = "TooHighChurnRate";
          annotations = {
            dashboard =
              "${grafanaUrl}/d/wNf0q_kZk?viewPanel=66&var-instance={{ $labels.instance }}";
            description = ''
              VM constantly creates new time series on "{{ $labels.instance }}".
               This effect is known as Churn Rate.
               High Churn Rate tightly connected with database performance and may result in unexpected OOM's or slow queries.'';
            summary = ''
              Churn rate is more than 10% on "{{ $labels.instance }}" for the last 15m'';
          };
          expr = ''
            (
               sum(rate(vm_new_timeseries_created_total[5m])) by(instance)
               /
               sum(rate(vm_rows_inserted_total[5m])) by (instance)
             ) > 0.1
          '';
          for = "15m";
          labels = { severity = "warning"; };
        }
        {
          alert = "TooHighChurnRate24h";
          annotations = {
            dashboard =
              "${grafanaUrl}/d/wNf0q_kZk?viewPanel=66&var-instance={{ $labels.instance }}";
            description = ''
              The number of created new time series over last 24h is 3x times higher than current number of active series on "{{ $labels.instance }}".
               This effect is known as Churn Rate.
               High Churn Rate tightly connected with database performance and may result in unexpected OOM's or slow queries.'';
            summary = ''
              Too high number of new series on "{{ $labels.instance }}" created over last 24h'';
          };
          expr = ''
            sum(increase(vm_new_timeseries_created_total[24h])) by(instance)
            >
            (sum(vm_cache_entries{type="storage/hour_metric_ids"}) by(instance) * 3)
          '';
          for = "15m";
          labels = { severity = "warning"; };
        }
        {
          alert = "TooHighSlowInsertsRate";
          annotations = {
            dashboard =
              "${grafanaUrl}/d/wNf0q_kZk?viewPanel=68&var-instance={{ $labels.instance }}";
            description = ''
              High rate of slow inserts on "{{ $labels.instance }}" may be a sign of resource exhaustion for the current load. It is likely more RAM is needed for optimal handling of the current number of active time series.'';
            summary = ''
              Percentage of slow inserts is more than 50% on "{{ $labels.instance }}" for the last 15m'';
          };
          expr = ''
            (
               sum(rate(vm_slow_row_inserts_total[5m])) by(instance)
               /
               sum(rate(vm_rows_inserted_total[5m])) by (instance)
             ) > 0.5
          '';
          for = "15m";
          labels = { severity = "warning"; };
        }
        {
          alert = "LabelsLimitExceededOnIngestion";
          annotations = {
            description = ''
              VictoriaMetrics limits the number of labels per each metric with `-maxLabelsPerTimeseries` command-line flag.
               This prevents from ingesting metrics with too many labels. Please verify that `-maxLabelsPerTimeseries` is configured correctly or that clients which send these metrics aren't misbehaving.'';
            summary =
              "Metrics ingested in ({{ $labels.instance }}) are exceeding labels limit";
          };
          expr =
            "sum(increase(vm_metrics_with_dropped_labels_total[5m])) by (instance) > 0";
          for = "15m";
          labels = { severity = "warning"; };
        }
      ];
    }
    {
      concurrency = 2;
      interval = "30s";
      name = "bitte-vmagent";
      rules = [
        {
          alert = "PersistentQueueIsDroppingData";
          annotations = {
            dashboard =
              "${grafanaUrl}/d/G7Z9GzMGz?viewPanel=49&var-instance={{ $labels.instance }}";
            description =
              "Vmagent dropped {{ $value | humanize1024 }} from persistent queue on instance {{ $labels.instance }} for the last 10m.";
            summary =
              "Instance {{ $labels.instance }} is dropping data from persistent queue";
          };
          expr =
            "sum(increase(vm_persistentqueue_bytes_dropped_total[5m])) by (job, instance) > 0";
          for = "10m";
          labels = { severity = "critical"; };
        }
        {
          alert = "TooManyScrapeErrors";
          annotations = {
            dashboard =
              "${grafanaUrl}/d/G7Z9GzMGz?viewPanel=31&var-instance={{ $labels.instance }}";
            summary = ''
              Job "{{ $labels.job }}" on instance {{ $labels.instance }} fails to scrape targets for last 15m'';
          };
          expr =
            "sum(increase(vm_promscrape_scrapes_failed_total[5m])) by (job, instance) > 0";
          for = "15m";
          labels = { severity = "warning"; };
        }
        {
          alert = "TooManyWriteErrors";
          annotations = {
            dashboard =
              "${grafanaUrl}/d/G7Z9GzMGz?viewPanel=77&var-instance={{ $labels.instance }}";
            summary = ''
              Job "{{ $labels.job }}" on instance {{ $labels.instance }} responds with errors to write requests for last 15m.'';
          };
          expr = ''
            (sum(increase(vm_ingestserver_request_errors_total[5m])) by (job, instance)
            +
            sum(increase(vmagent_http_request_errors_total[5m])) by (job, instance)) > 0
          '';
          for = "15m";
          labels = { severity = "warning"; };
        }
        {
          alert = "TooManyRemoteWriteErrors";
          annotations = {
            dashboard =
              "${grafanaUrl}/d/G7Z9GzMGz?viewPanel=61&var-instance={{ $labels.instance }}";
            description = ''
              Vmagent fails to push data via remote write protocol to destination "{{ $labels.url }}"
               Ensure that destination is up and reachable.'';
            summary = ''
              Job "{{ $labels.job }}" on instance {{ $labels.instance }} fails to push to remote storage'';
          };
          expr =
            "sum(rate(vmagent_remotewrite_retries_count_total[5m])) by(job, instance, url) > 0";
          for = "15m";
          labels = { severity = "warning"; };
        }
        {
          alert = "RemoteWriteConnectionIsSaturated";
          annotations = {
            dashboard =
              "${grafanaUrl}/d/G7Z9GzMGz?viewPanel=84&var-instance={{ $labels.instance }}";
            description = ''
              The remote write connection between vmagent "{{ $labels.job }}" (instance {{ $labels.instance }}) and destination "{{ $labels.url }}" is saturated by more than 90% and vmagent won't be able to keep up.
               This usually means that `-remoteWrite.queues` command-line flag must be increased in order to increase the number of connections per each remote storage.'';
            summary = ''
              Remote write connection from "{{ $labels.job }}" (instance {{ $labels.instance }}) to {{ $labels.url }} is saturated'';
          };
          expr =
            "rate(vmagent_remotewrite_send_duration_seconds_total[5m]) > 0.9";
          for = "15m";
          labels = { severity = "warning"; };
        }
        {
          alert = "SeriesLimitHourReached";
          annotations = {
            description =
              "Max series limit set via -remoteWrite.maxHourlySeries flag is close to reaching the max value. Then samples for new time series will be dropped instead of sending them to remote storage systems.";
            summary =
              "Instance {{ $labels.instance }} reached 90% of the limit";
          };
          expr =
            "(vmagent_hourly_series_limit_current_series / vmagent_hourly_series_limit_max_series) > 0.9";
          labels = { severity = "critical"; };
        }
        {
          alert = "SeriesLimitDayReached";
          annotations = {
            description =
              "Max series limit set via -remoteWrite.maxDailySeries flag is close to reaching the max value. Then samples for new time series will be dropped instead of sending them to remote storage systems.";
            summary =
              "Instance {{ $labels.instance }} reached 90% of the limit";
          };
          expr =
            "(vmagent_daily_series_limit_current_series / vmagent_daily_series_limit_max_series) > 0.9";
          labels = { severity = "critical"; };
        }
      ];
    }
  ];
}
