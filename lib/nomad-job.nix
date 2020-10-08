{ name, config, lib, ... }:
let
  cfg = config.job;
  inherit (lib) mkOption mkEnableOption attrValues;
  inherit (lib.types)
    nullOr submodule str enum ints listOf attrsOf attrs bool coercedTo float
    port unspecified;

  nullMap = f: input: if input == null then null else map f input;

  mapPeriodic = input:
    if input == null then
      null
    else {
      Spec = input.cron;
      TimeZone = input.timeZone;
      Enabled = true;
      SpecType = "cron";
      ProhibitOverlap = input.prohibitOverlap;
    };

  mapArtifacts = nullMap (value: {
    GetterSource = value.source;
    RelativeDest = value.destination;
    GetterOptions = value.options;
  });

  mapTemplates = nullMap (value: {
    DestPath = value.destination or null;
    EmbeddedTmpl = value.data or "";
    SourcePath = value.source or null;
    Envvars = value.env or false;
    ChangeMode = value.changeMode or "restart";
  });

  mapConstraints = nullMap (value: {
    LTarget = value.attribute;
    RTarget = value.value;
    Operand = value.operator;
  });

  mapAffinities =
    nullMap (value: (mapConstraints value) // { Weight = value.weight; });

  mapSpreads = nullMap (value: {
    Attribute = value.attribute;
    SpreadTarget = value.target;
    Weight = value.weight;
  });

  mapSpreadTarget = nullMap (value: {
    Value = value.value;
    Percent = value.percent;
  });

  mkSpreadOption = mkOption {
    type = nullOr (listOf spreadType);
    default = null;
    apply = mapSpreads;
    description = ''
      The spread stanza allows operators to increase the failure tolerance
      of their applications by specifying a node attribute that allocations
      should be spread over.
      This allows operators to spread allocations over attributes such as
      datacenter, availability zone, or even rack in a physical datacenter.
      By default, when using spread the scheduler will attempt to place
      allocations equally among the available values of the given target.
      https://www.nomadproject.io/docs/job-specification/spread
    '';
  };

  mkMigrateOption = mkOption {
    type = nullOr migrateType;
    default = null;
    description = ''
      Specifies the group strategy for migrating off of draining nodes.
      Only service jobs with a count greater than 1 support migrate
      stanzas.
    '';
  };

  pp = v: __trace (__toJSON v) v;

  toNanoseconds = input:
    let
      groups = __match "^([0-9]+)(h|m|s)$" input;
      num = __fromJSON (__elemAt groups 0);
      kind = __elemAt groups 1;
    in if kind == "h" then
      num * 3600000000000
    else if kind == "m" then
      num * 60000000000
    else if kind == "s" then
      num * 1000000000
    else
      throw ''needs to be one of "h", "m", or "s"'';

  nanoseconds = coercedTo str toNanoseconds ints.unsigned;

  serviceType = attrsOf (submodule ({ name, ... }: {
    options = {
      name = mkOption {
        type = str;
        default = name;
      };

      portLabel = mkOption {
        type = nullOr str;
        default = null;
      };

      tags = mkOption {
        type = listOf str;
        default = [ ];
      };

      meta = mkOption {
        type = attrsOf str;
        default = { };
      };

      checks = mkOption {
        default = null;
        type = nullOr (listOf (submodule {
          options = {
            name = mkOption {
              type = str;
              default = "alive";
            };

            portLabel = mkOption {
              type = nullOr str;
              default = null;
            };

            path = mkOption {
              type = nullOr str;
              default = null;
            };

            type = mkOption {
              type = enum [ "script" "tcp" "http" ];
              default = "tcp";
            };

            interval = mkOption {
              type = nanoseconds;
              default = "10s";
            };

            timeout = mkOption {
              type = nanoseconds;
              default = "2s";
            };

            task = mkOption {
              type = str;
              default = name;
            };

            command = mkOption {
              type = nullOr str;
              default = null;
            };

            args = mkOption {
              type = nullOr (listOf str);
              default = null;
            };

            checkRestart = mkOption {
              default = null;
              type = nullOr (submodule {
                options = {
                  limit = mkOption {
                    type = nullOr ints.positive;
                    default = null;
                  };

                  grace = mkOption {
                    type = nullOr nanoseconds;
                    default = null;
                  };

                  ignoreWarnings = mkOption {
                    type = nullOr bool;
                    default = null;
                  };
                };
              });
            };
          };
        }));
      };

      connect = mkOption {
        default = null;
        type = nullOr (submodule {
          options = {
            sidecarService = mkOption {
              default = null;
              type = nullOr (submodule {
                options = {
                  proxy = mkOption {
                    default = null;
                    type = nullOr (submodule {
                      options = {
                        config = mkOption {
                          default = null;
                          type = nullOr (submodule {
                            options = {
                              protocol = mkOption {
                                type =
                                  nullOr (enum [ "tcp" "http" "http2" "grpc" ]);
                                default = null;
                              };
                            };
                          });
                        };

                        upstreams = mkOption {
                          type = listOf (submodule {
                            options = {
                              destinationName = mkOption { type = str; };

                              localBindPort = mkOption { type = port; };
                            };
                          });
                        };
                      };
                    });
                  };
                };
              });
            };
          };
        });
      };
    };
  }));

  taskGroupType = submodule ({ name, ... }: {
    options = {
      name = mkOption {
        type = str;
        default = name;
      };

      tasks = mkOption {
        type = attrsOf taskType;
        default = { };
        description = "";
        apply = attrValues;
      };

      constraints = mkOption {
        type = nullOr (listOf constraintType);
        default = null;
        apply = mapConstraints;
        description = ''
          A list to define additional constraints where a job can be run.
        '';
      };

      affinities = mkOption {
        type = nullOr (listOf affinityType);
        default = null;
        apply = mapAffinities;
        description = ''
          Affinities allow operators to express placement preferences.
          https://www.nomadproject.io/docs/job-specification/affinity
        '';
      };

      spreads = mkSpreadOption;

      count = mkOption {
        type = ints.unsigned;
        default = 1;
        description = ''
          Specifies the number of the task groups that should be running under
          this group.
        '';
      };

      ephemeralDisk = mkOption {
        type = nullOr ephemeralDiskType;
        default = null;
        description = ''
          Specifies the ephemeral disk requirements of the group.
          Ephemeral disks can be marked as sticky and support live data migrations.
        '';
      };

      networks = mkOption {
        type = nullOr (listOf networkType);
        default = null;
      };

      meta = mkOption {
        type = nullOr (attrsOf str);
        default = null;
        description = ''
          A key-value map that annotates the Consul service with user-defined
          metadata. String interpolation is supported in meta.
        '';
      };

      migrate = mkMigrateOption;

      # reschedule (Reschedule: nil) - Allows to specify a rescheduling strategy. Nomad will then attempt to schedule the task on another node if any of the group allocation statuses become "failed".

      restartPolicy = mkOption {
        type = nullOr restartPolicyType;
        default = null;
        description = ''
          Specifies the restart policy for all tasks in this group.
          If omitted, a default policy exists for each job type, which can be found in the restart stanza documentation.
        '';
      };

      services = mkOption {
        apply = attrValues;
        type = serviceType;
        default = { };
      };

      shutdownDelay = mkOption {
        type = nullOr nanoseconds;
        default = null;
        description = ''
          Specifies the duration to wait when stopping a group's tasks.
          The delay occurs between Consul deregistration and sending each task a shutdown signal.
          Ideally, services would fail healthchecks once they receive a shutdown signal.
          Alternatively shutdownDelay may be set to give in flight requests time to complete before shutting down.
          A group level shutdownDelay will run regardless if there are any defined group services.
          In addition, tasks may have their own shutdownDelay which waits between deregistering task services and stopping the task.
        '';
      };

      update = mkOption {
        default = null;
        type = nullOr (submodule {
          options = {
            maxParallel = mkOption {
              type = ints.positive;
              default = 1;
            };
          };
        });
      };

      vault = mkOption {
        type = nullOr (submodule {
          options = {
            policies = mkOption {
              type = listOf str;
              default = [ ];
            };
          };
        });
        default = null;
        description = ''
          Specifies the set of Vault policies required by all tasks in this group.
          Overrides a vault block set at the job level.
        '';
      };


      reschedulePolicy = mkOption {
        type = nullOr reschedulePolicyType;
        default = null;
        description = ''
          The reschedule stanza specifies the group's rescheduling strategy. If
          specified at the job level, the configuration will apply to all
          groups within the job. If the reschedule stanza is present on both
          the job and the group, they are merged with the group stanza taking
          the highest precedence and then the job.
          Nomad will attempt to schedule the task on another node if any of its
          allocation statuses become "failed". It prefers to create a
          replacement allocation on a node that hasn't previously been used.
          https://www.nomadproject.io/docs/job-specification/reschedule/
        '';
      };

      # stop_after_client_disconnect (string: "") - Specifies a duration after which a Nomad client that cannot communicate with the servers will stop allocations based on this task group. By default, a client will not stop an allocation until explicitly told to by a server. A client that fails to heartbeat to a server within the hearbeat_grace window and any allocations running on it will be marked "lost" and Nomad will schedule replacement allocations. However, these replaced allocations will continue to run on the non-responsive client; an operator may desire that these replaced allocations are also stopped in this case — for example, allocations requiring exclusive access to an external resource. When specified, the Nomad client will stop them after this duration. The Nomad client process must be running for this to occur.

      # task (Task: <required>) - Specifies one or more tasks to run within this group. This can be specified multiple times, to add a task as part of the group.

      # volume (Volume: nil) - Specifies the volumes that are required by tasks within the group.
    };
  });

  networkType = submodule {
    options = {
      mode = mkOption {
        type = str;
        default = "bridge";
      };
    };
  };

  restartPolicyType = submodule {
    options = {
      attempts = mkOption {
        type = nullOr ints.positive;
        default = null;
        description = ''
          Specifies the number of restarts allowed in the configured interval.
          Defaults vary by job type.
          https://www.nomadproject.io/docs/job-specification/restart/
        '';
      };

      interval = mkOption {
        type = nullOr nanoseconds;
        default = null;
        description = ''
          Specifies the duration which begins when the first task starts and ensures that only attempts number of restarts happens within it.
          If more than attempts number of failures happen, behavior is controlled by mode.
          This is specified using a label suffix like "30s" or "1h".
          Defaults vary by job type.
          https://www.nomadproject.io/docs/job-specification/restart/
        '';
      };

      delay = mkOption {
        type = nanoseconds;
        default = "15s";
        description = ''
          Specifies the duration to wait before restarting a task.
          This is specified using a label suffix like "30s" or "1h".
          A random jitter of up to 25% is added to the delay.
          https://www.nomadproject.io/docs/job-specification/restart/
        '';
      };

      mode = mkOption {
        type = enum [ "delay" "fail" ];
        default = "fail";
        description = ''
          Controls the behavior when the task fails more than attempts times in
          an interval.
          https://www.nomadproject.io/docs/job-specification/restart/
        '';
      };
    };
  };

  ephemeralDiskType = submodule {
    options = {
      migrate = mkEnableOption
        "Specifies that the Nomad client should make a best-effort attempt to migrate the data from a remote machine if placement cannot be made on the original node. During data migration, the task will block starting until the data migration has completed. Value is a boolean and the default is false.";

      sizeMB = mkOption {
        type = ints.positive;
        default = 300;
        description = ''
          Specifies the size of the ephemeral disk in MB. Default is 300.
        '';
      };

      sticky = mkEnableOption ''
        Specifies that Nomad should make a best-effort attempt to place the updated allocation on the same machine. This will move the local/ and alloc/data directories to the new allocation. Value is a boolean and the default is false.
      '';
    };
  };

  migrateType = submodule {
    options = {
      healthCheck = mkOption {
        type = enum [ "checks" "task_states" ];
        default = "checks";
        description = ''
          One of checks or task_states. Indicates how task health should be
          determined: either via Consul health checks or whether the task was
          able to run successfully.

          checks:
            Specifies that the allocation should be considered healthy when all of its
            tasks are running and their associated checks are healthy, and unhealthy if
            any of the tasks fail or not all checks become healthy. This is a superset of
            "task_states" mode.

          task_states:
            Specifies that the allocation should be considered healthy when all its tasks
            are running and unhealthy if tasks fail.
        '';
      };

      maxParallel = mkOption {
        type = ints.positive;
        default = 1;
        description = ''
          Specifies the number of allocations within a task group that can be
          updated at the same time. The task groups themselves are updated in
          parallel.
        '';
      };

      minHealthyTime = mkOption {
        type = nanoseconds;
        default = "10s";
        description = ''
          Specifies the minimum time the allocation must be in the healthy state before
          it is marked as healthy and unblocks further allocations from being updated.
          This is specified using a label suffix like "30s" or "15m".
        '';
      };

      healthyDeadline = mkOption {
        type = nanoseconds;
        default = "5m";
        description = ''
          Specifies the deadline in which the allocation must be marked as healthy after
          which the allocation is automatically transitioned to unhealthy.
          This is specified using a label suffix like "2m" or "1h".
        '';
      };
    };
  };

  artifactType = submodule {
    options = {
      source = mkOption {
        type = str;
        description = ''
          The path to the artifact to download.
          https://www.nomadproject.io/api-docs/json-jobs/#artifact
        '';
      };
      destination = mkOption {
        type = nullOr str;
        default = null;
        description = ''
          An optional path to download the artifact into relative to the root of the task's directory.
          If omitted, it will default to local/.
          https://www.nomadproject.io/api-docs/json-jobs/#artifact
        '';
      };
      options = mkOption {
        type = nullOr (attrsOf str);
        default = null;
        description = ''
          A map[string]string block of options for go-getter. Full documentation of supported options are available here. An example is given below:
          https://www.nomadproject.io/api-docs/json-jobs/#artifact
        '';
      };
    };
  };

  templateType = submodule ({ name, ... }: {
    options = {
      data = mkOption {
        type = nullOr str;
        default = null;
        description = ''
          Specifies the raw template to execute.
          One of source or data must be specified, but not both.
          This is useful for smaller templates, but we recommend using source for larger templates.
        '';
      };

      destination = mkOption {
        type = nullOr str;
        default = null;
        description = ''
          Specifies the location where the resulting template should be
          rendered, relative to the task directory.
        '';
      };

      source = mkOption {
        type = nullOr str;
        default = null;
        description = ''
          Specifies the path to the template to be rendered. One of source or
          data must be specified, but not both. This source can optionally be
          fetched using an artifact resource. This template must exist on the
          machine prior to starting the task; it is not possible to reference a
          template inside of a Docker container, for example.
        '';
      };

      env = mkOption {
        type = bool;
        default = false;
        description = ''
          Specifies the template should be read back as environment variables
          for the task.
        '';
      };

      changeMode = mkOption {
        type = nullOr (enum [ "restart" "signal" "noop" ]);
        default = "restart";
        description = ''
          Specifies the behavior Nomad should take if the rendered template
          changes. Nomad will always write the new contents of the template to
          the specified destination. The possible values below describe Nomad's
          action after writing the template to disk.
        '';
      };
    };
  });

  taskType = submodule ({ name, ... }: {
    options = {
      artifacts = mkOption {
        type = nullOr (listOf artifactType);
        default = null;
        apply = mapArtifacts;
        description = ''
          Nomad downloads artifacts using go-getter. The go-getter library
          allows downloading of artifacts from various sources using a URL as
          the input source. The key-value pairs given in the options block map
          directly to parameters appended to the supplied source URL. These are
          then used by go-getter to appropriately download the artifact.
          go-getter also has a CLI tool to validate its URL and can be used to
          check if the Nomad artifact is valid.
        '';
      };

      templates = mkOption {
        type = nullOr (listOf templateType);
        default = null;
        apply = mapTemplates;
        description = ''
          The template block instantiates an instance of a template renderer.
          This creates a convenient way to ship configuration files that are
          populated from environment variables, Consul data, Vault secrets, or
          just general configurations within a Nomad task.
        '';
      };

      config = mkOption {
        type = attrs;
        default = { };
        description = ''
          Specifies the driver configuration, which is passed directly to the
          driver to start the task.
          The details of configurations are specific to each driver, so please
          see specific driver documentation for more information.
          https://www.nomadproject.io/docs/drivers
        '';
      };

      driver = mkOption {
        type = str;
        description = ''
          Specifies the task driver that should be used to run the task.
          See the driver documentation for what is available.
          Examples include docker, qemu, java and exec.
          https://www.nomadproject.io/docs/drivers
        '';
      };

      name = mkOption {
        type = str;
        default = name;
      };

      env = mkOption {
        type = nullOr (attrsOf str);
        default = null;
        description = ''
          Specifies environment variables that will be passed to the running process.
        '';
      };

      constraints = mkOption {
        type = nullOr (listOf constraintType);
        default = null;
        apply = mapConstraints;
        description = ''
          A list to define additional constraints where a job can be run.
        '';
      };

      shutdownDelay = mkOption {
        type = nanoseconds;
        default = 0;
        description = ''
          Specifies the duration to wait when stopping a group's tasks.
          The delay occurs between Consul deregistration and sending each task a shutdown signal.
          Ideally, services would fail healthchecks once they receive a shutdown signal.
          Alternatively shutdownDelay may be set to give in flight requests time to complete before shutting down.
          A group level shutdownDelay will run regardless if there are any defined group services.
          In addition, tasks may have their own shutdownDelay which waits between deregistering task services and stopping the task.
        '';
      };

      killSignal = mkOption {
        type = str;
        default = "";
        description = ''
          Specifies a configurable kill signal for a task, where the default is
          SIGINT. Note that this is only supported for drivers which accept
          sending signals (currently docker, exec, raw_exec, and java drivers).
        '';
      };

      resources = mkOption {
        default = null;
        type = nullOr (submodule {
          options = {
            cpu = mkOption {
              type = ints.positive;
              default = 100;
            };

            memoryMB = mkOption {
              type = ints.positive;
              default = 300;
            };

            networks = mkOption {
              default = null;
              type = unspecified;
            };
          };
        });
      };

      user = mkOption {
        type = str;
        default = "";
        description = ''
          Set the user that will run the task. It defaults to the same user the
          Nomad client is being run as. This can only be set on Linux
          platforms.
        '';
      };

      vault = mkOption {
        type = nullOr (submodule {
          options = {
            policies = mkOption {
              type = listOf str;
              default = [ ];
            };
          };
        });
        default = null;
        description = ''
          Specifies the set of Vault policies required by all tasks in this group.
          Overrides a vault block set at the job level.
        '';
      };

      services = mkOption {
        apply = attrValues;
        type = serviceType;
        default = { };
      };

      restartPolicy = mkOption {
        type = nullOr restartPolicyType;
        default = null;
        description = ''
          The restart stanza configures a tasks's behavior on task failure.
          Restarts happen on the client that is running the task.
        '';
      };
    };
  });

  periodicType = submodule {
    options = {
      timeZone = mkOption {
        type = nullOr str;
        description = ''
          Specifies the time zone to evaluate the next launch interval against.
          This is useful when wanting to account for day light savings in various time zones.
          The time zone must be parsable by Golang's LoadLocation.
          The default is UTC.
          https://golang.org/pkg/time/#LoadLocation
        '';
      };

      cron = mkOption {
        type = nullOr str;
        description = ''
          A cron expression configuring the interval the job is launched at.
          Supports predefined expressions such as "@daily" and "@weekly".
          See here for full documentation of supported cron specs and the
          predefined expressions.
          https://github.com/gorhill/cronexpr#implementation
        '';
      };

      prohibitOverlap = mkEnableOption ''
        Can be set to true to enforce that the periodic job doesn't spawn a new
        instance of the job if any of the previous jobs are still running.
        It is defaults to false.
      '';
    };
  };

  constraintType = submodule {
    options = {
      attribute = mkOption {
        type = str;
        default = "";
      };

      operator = mkOption {
        type = str;
        enum = [
          "regexp"
          "set_contains"
          "distinct_hosts"
          "distinct_property"
          "="
          "=="
          "is"
          "!="
          "not"
          ">"
          ">="
          "<"
          "<="
          "version"
          "semver"
          "is_set"
          "is_not_set"
        ];
        default = "=";
      };

      value = mkOption {
        type = str;
        default = "";
      };
    };
  };

  affinityType = submodule {
    options = {
      attribute = mkOption {
        type = str;
        default = "";
      };

      operator = mkOption {
        type = str;
        enum = [
          "regexp"
          "set_contains_all"
          "set_contains"
          "set_contains_any"
          "="
          "=="
          "is"
          "!="
          "not"
          ">"
          ">="
          "<"
          "<="
          "version"
        ];
        default = "=";
      };

      value = mkOption {
        type = str;
        default = "";
      };

      weight = mkOption {
        type = ints.between - 100 100;
        default = 50;
      };
    };
  };

  spreadTargetType = submodule {
    options = {
      value = mkOption {
        type = str;
        default = "";
        description = ''
          The value of a specific target attribute, like "dc1" for ''${node.datacenter}.
        '';
      };

      percent = mkOption {
        type = ints.unsigned;
        default = 0;
        description = ''
          Desired percentage of allocations for this attribute value.
          The sum of all spread target percentages must add up to 100.
        '';
      };
    };
  };

  spreadType = submodule {
    options = {
      attribute = mkOption {
        type = str;
        default = "";
        description = ''
          Specifies the name or reference of the attribute to use.
          This can be any of the Nomad interpolated values.
        '';
      };

      target = mkOption {
        type = spreadTargetType;
        default = { };
        apply = mapSpreadTarget;
        description = ''
          Specifies one or more target percentages for each value of the
          attribute in the spread stanza.
          If this is omitted, Nomad will spread allocations evenly across all
          values of the attribute.
        '';
      };

      weight = mkOption {
        type = ints.between 0 100;
        default = 0;
        description = ''
          Specifies a weight for the spread stanza.
          The weight is used during scoring and must be an integer between 0 to
          100.
          Weights can be used when there is more than one spread or affinity
          stanza to express relative preference across them.
        '';
      };
    };
  };

  parameterizedJobType = submodule {
    options = {
      metaOptional = mkOption {
        type = listOf str;
        default = [ ];
        description = ''
          Specifies the set of metadata keys that may be provided when dispatching against the job.
        '';
      };

      metaRequired = mkOption {
        type = listOf str;
        default = [ ];
        description = ''
          Specifies the set of metadata keys that must be provided when dispatching against the job.
        '';
      };

      payload = mkOption {
        type = enum [ "optional" "required" "forbidden" ];
        default = "optional";
        description = ''
          Specifies the requirement of providing a payload when dispatching
          against the parameterized job. The maximum size of a payload is 16 KiB.
        '';
      };
    };
  };

  updateType = submodule {
    options = {
      healthCheck = mkOption {
        type = enum [ "checks" "task_states" "manual" ];
        default = "checks";
        description = ''
          Specifies the mechanism in which allocations health is determined.
          The potential values are:

          checks:
            Specifies that the allocation should be considered healthy when all of its
            tasks are running and their associated checks are healthy, and unhealthy if
            any of the tasks fail or not all checks become healthy. This is a superset of
            "task_states" mode.

          task_states:
            Specifies that the allocation should be considered healthy when all its tasks
            are running and unhealthy if tasks fail.

          manual:
            Specifies that Nomad should not automatically determine health and that the
            operator will specify allocation health using the HTTP API.
        '';
      };

      maxParallel = mkOption {
        type = ints.positive;
        default = 1;
        description = ''
          Specifies the number of allocations within a task group that can be
          updated at the same time. The task groups themselves are updated in
          parallel.
        '';
      };

      minHealthyTime = mkOption {
        type = nanoseconds;
        default = "10s";
        description = ''
          Specifies the minimum time the allocation must be in the healthy state before
          it is marked as healthy and unblocks further allocations from being updated.
          This is specified using a label suffix like "30s" or "15m".
        '';
      };

      healthyDeadline = mkOption {
        type = nanoseconds;
        default = "5m";
        description = ''
          Specifies the deadline in which the allocation must be marked as healthy after
          which the allocation is automatically transitioned to unhealthy.
          This is specified using a label suffix like "2m" or "1h".
        '';
      };

      progressDeadline = mkOption {
        type = nanoseconds;
        default = "10m";
        description = ''
          Specifies the deadline in which an allocation must be marked as
          healthy. The deadline begins when the first allocation for the
          deployment is created and is reset whenever an allocation as part of
          the deployment transitions to a healthy state. If no allocation
          transitions to the healthy state before the progress deadline, the
          deployment is marked as failed. If the progressDeadline is set to 0,
          the first allocation to be marked as unhealthy causes the deployment
          to fail. This is specified using a label suffix like "2m" or "1h".
        '';
      };

      autoRevert = mkEnableOption ''
        Specifies if the job should auto-revert to the last stable job on deployment failure.
        A job is marked as stable if all the allocations as part of its deployment were marked healthy.
      '';

      autoPromote = mkEnableOption ''
        Specifies if the job should auto-promote to the canary version when all
        canaries become healthy during a deployment. Defaults to false which
        means canaries must be manually updated with the nomad deployment promote
        command.
      '';

      canary = mkOption {
        type = ints.unsigned;
        default = 0;
        description = ''
          Specifies that changes to the job that would result in destructive
          updates should create the specified number of canaries without
          stopping any previous allocations. Once the operator determines the
          canaries are healthy, they can be promoted which unblocks a rolling
          update of the remaining allocations at a rate of max_parallel.
        '';
      };

      stagger = mkOption {
        type = nanoseconds;
        default = "30s";
        description = ''
          Specifies the delay between each set of maxParallel updates when
          updating system jobs. This setting no longer applies to service jobs
          which use deployments.
        '';
      };
    };
  };

  reschedulePolicyType = submodule {
    options = {
      attempts = mkOption {
        type = nullOr ints.unsigned;
        default = null;
        description = ''
          Specifies the number of reschedule attempts allowed in the configured
          interval. Defaults vary by job type.
        '';
      };

      interval = mkOption {
        type = nullOr nanoseconds;
        default = null;
        description = ''
          Specifies the sliding window which begins when the first reschedule
          attempt starts and ensures that only attempts number of reschedule
          happen within it. If more than attempts number of failures happen with
          this interval, Nomad will not reschedule any more.
        '';
      };

      delay = mkOption {
        type = nullOr nanoseconds;
        default = null;
        description = ''
          Specifies the duration to wait before attempting to reschedule a failed
          task. This is specified using a label suffix like "30s" or "1h".
        '';
      };

      delayFunction = mkOption {
        type = enum [ "constant" "exponential" "fibonacci" ];
        default = "constant";
        description = ''
          Specifies the function that is used to calculate subsequent reschedule
          delays. The initial delay is specified by the delay parameter.
        '';
      };

      maxDelay = mkOption {
        type = nullOr nanoseconds;
        default = null;
        description = ''
          MaxDelay is an upper bound on the delay beyond which it will not
          increase. This parameter is used when DelayFunction is exponential or
          fibonacci, and is ignored when constant delay is used.
        '';
      };

      unlimited = mkOption {
        type = nullOr bool;
        default = null;
        description = ''
          Enables unlimited reschedule attempts. If this is set to true the
          attempts and interval fields are not used.
        '';
      };
    };
  };
in {
  options = {
    affinities = mkOption {
      type = nullOr (listOf affinityType);
      default = null;
      apply = mapAffinities;
      description = ''
        Affinities allow operators to express placement preferences.
        https://www.nomadproject.io/docs/job-specification/affinity
      '';
    };

    allAtOnce = mkOption {
      type = nullOr bool;
      default = null;
      description = ''
        Controls whether the scheduler can make partial placements if
        optimistic scheduling resulted in an oversubscribed node.
        This does not control whether all allocations for the job, where all
        would be the desired count for each task group, must be placed
        atomically.
        This should only be used for special circumstances.
      '';
    };

    constraints = mkOption {
      type = nullOr (listOf constraintType);
      default = null;
      apply = mapConstraints;
      description = ''
        A list to define additional constraints where a job can be run.
        https://www.nomadproject.io/docs/job-specification/constraint
      '';
    };

    datacenters = mkOption {
      type = listOf str;
      description = ''
        A list of datacenters in the region which are eligible for task placement.
        This must be provided, and does not have a default.
      '';
    };

    id = mkOption {
      type = str;
      default = config.name;
    };

    meta = mkOption {
      type = nullOr (attrsOf str);
      default = null;
      description = ''
        A key-value map that annotates the Consul service with user-defined
        metadata. String interpolation is supported in meta.
      '';
    };

    migrate = mkMigrateOption;

    name = mkOption {
      type = str;
      default = name;
    };

    namespace = mkOption {
      type = nullOr str;
      default = null;
      description = ''
        The namespace to execute the job in, defaults to "default".
        Values other than default are not allowed in non-Enterprise versions of Nomad.
      '';
    };

    parameterizedJob = mkOption {
      type = nullOr parameterizedJobType;
      default = null;
      description = ''
        Specifies the job as a parameterized job such that it can be
        dispatched against.
      '';
    };

    periodic = mkOption {
      type = nullOr periodicType;
      default = null;
      apply = mapPeriodic;
      description = ''
        allows the job to be scheduled at fixed times, dates or intervals.
        The periodic expression is always evaluated in the UTC timezone to
        ensure consistent evaluation when Nomad Servers span multiple time
        zones.
      '';
    };

    priority = mkOption {
      type = nullOr (ints.between 1 100);
      default = null;
      description = ''
        Specifies the job priority which is used to prioritize scheduling and
        access to resources. Must be between 1 and 100 inclusively, and
        defaults to 50.
      '';
    };

    region = mkOption {
      type = nullOr str;
      default = null;
      description = ''
        The region to run the job in, defaults to "global".
      '';
    };

    reschedulePolicy = mkOption {
      type = nullOr reschedulePolicyType;
      default = null;
      description = ''
        The reschedule stanza specifies the group's rescheduling strategy. If
        specified at the job level, the configuration will apply to all
        groups within the job. If the reschedule stanza is present on both
        the job and the group, they are merged with the group stanza taking
        the highest precedence and then the job.
        Nomad will attempt to schedule the task on another node if any of its
        allocation statuses become "failed". It prefers to create a
        replacement allocation on a node that hasn't previously been used.
        https://www.nomadproject.io/docs/job-specification/reschedule/
      '';
    };

    spreads = mkSpreadOption;

    taskGroups = mkOption {
      type = attrsOf taskGroupType;
      default = { };
      apply = attrValues;
      description = ''
        Specifies the start of a group of tasks.
        This can be provided multiple times to define additional groups.
      '';
    };

    type = mkOption {
      type = enum [ "service" "system" "batch" ];
      default = "service";
      description = ''
        Specifies the Nomad scheduler to use.
        Nomad provides the service, system and batch schedulers.
        https://www.nomadproject.io/docs/schedulers/
      '';
    };

    update = mkOption {
      type = nullOr updateType;
      default = null;
      description = ''
        Specifies the group's update strategy.
        The update strategy is used to control things like rolling upgrades
        and canary deployments.
        If omitted, rolling updates and canaries are disabled.
        If specified at the job level, the configuration will apply to all
        groups within the job.
        If multiple update stanzas are specified, they are merged with the
        group stanza taking the highest precedence and then the job.
      '';
    };
  };
}
