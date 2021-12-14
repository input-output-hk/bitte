{ name, config, lib, ... }:
let
  cfg = config.job;

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

  mapNetworks = nullMap (value: {
    Mode = value.mode;
    DNS = value.dns;

    ReservedPorts = let
      reserved = lib.filterAttrs (k: v: v.static or null != null) value.ports;
    in lib.mapAttrsToList (k: v: {
      Label = k;
      Value = v.static;
      To = v.to;
      HostNetwork = v.hostNetwork;
    }) reserved;

    DynamicPorts = let
      dynamic = lib.filterAttrs (k: v: v.static or null == null) value.ports;
    in lib.mapAttrsToList (k: v: {
      Label = k;
      To = v.to;
      HostNetwork = v.hostNetwork;
    }) dynamic;
  });

  mapVolumeMounts = nullMap (value: {
    Volume = value.volume;
    inherit (value) destination;
    ReadOnly = value.readOnly;
    PropagationMode = value.propagationMode;
  });

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
    ChangeSignal = value.changeSignal or "";
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

  mkSpreadOption = lib.mkOption {
    type = with lib.types; nullOr (listOf spreadType);
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

  mkMigrateOption = lib.mkOption {
    type = with lib.types; nullOr migrateType;
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
      name = lib.mkOption {
        type = with lib.types; str;
        default = name;
      };

      portLabel = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
      };

      tags = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
      };

      meta = lib.mkOption {
        type = with lib.types; attrsOf str;
        default = { };
      };

      task = lib.mkOption {
        type = with lib.types; str;
        default = "";
      };

      addressMode = lib.mkOption {
        type = with lib.types; str;
        default = "auto";
      };

      checks = lib.mkOption {
        default = null;
        type = with lib.types;
          nullOr (listOf (submodule {
            options = {
              name = lib.mkOption {
                type = with lib.types; str;
                default = "alive";
              };

              portLabel = lib.mkOption {
                type = with lib.types; nullOr str;
                default = null;
              };

              path = lib.mkOption {
                type = with lib.types; nullOr str;
                default = null;
              };

              type = lib.mkOption {
                type = with lib.types; enum [ "script" "tcp" "http" ];
                default = "tcp";
              };

              interval = lib.mkOption {
                type = with lib.types; nanoseconds;
                default = "10s";
              };

              timeout = lib.mkOption {
                type = with lib.types; nanoseconds;
                default = "2s";
              };

              task = lib.mkOption {
                type = with lib.types; str;
                default = name;
              };

              command = lib.mkOption {
                type = with lib.types; nullOr str;
                default = null;
              };

              args = lib.mkOption {
                type = with lib.types; nullOr (listOf str);
                default = null;
              };

              checkRestart = lib.mkOption {
                default = null;
                type = with lib.types;
                  nullOr (submodule {
                    options = {
                      limit = lib.mkOption {
                        type = with lib.types; nullOr ints.positive;
                        default = null;
                      };

                      grace = lib.mkOption {
                        type = with lib.types; nullOr nanoseconds;
                        default = null;
                      };

                      ignoreWarnings = lib.mkOption {
                        type = with lib.types; nullOr bool;
                        default = null;
                      };
                    };
                  });
              };
            };
          }));
      };

      connect = lib.mkOption {
        default = null;
        type = with lib.types;
          nullOr (submodule {
            options = {
              sidecarService = lib.mkOption {
                default = null;
                type = with lib.types;
                  nullOr (submodule {
                    options = {
                      proxy = lib.mkOption {
                        default = null;
                        type = with lib.types;
                          nullOr (submodule {
                            options = {
                              config = lib.mkOption {
                                default = null;
                                type = with lib.types;
                                  nullOr (submodule {
                                    options = {
                                      protocol = lib.mkOption {
                                        type = nullOr (enum [
                                          "tcp"
                                          "http"
                                          "http2"
                                          "grpc"
                                        ]);
                                        default = null;
                                      };
                                    };
                                  });
                              };

                              upstreams = lib.mkOption {
                                type = with lib.types;
                                  listOf (submodule {
                                    options = {
                                      destinationName = lib.mkOption {
                                        type = with lib.types; str;
                                      };

                                      localBindPort = lib.mkOption {
                                        type = with lib.types; port;
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
          });
      };
    };
  }));

  volumeMountType = submodule ({ name, ... }: {
    options = {
      volume = lib.mkOption {
        type = with lib.types; str;
        default = name;
      };

      destination = lib.mkOption { type = with lib.types; str; };

      readOnly = lib.mkOption {
        type = with lib.types; bool;
        default = true;
      };

      propagationMode = lib.mkOption {
        type = with lib.types;
          enum [ "host-to-task" "private" "bidirectional" ];
        default = "private";
      };
    };
  });

  volumeType = submodule ({ name, ... }: {
    options = {
      name = lib.mkOption {
        type = with lib.types; str;
        default = name;
      };

      type = lib.mkOption {
        type = with lib.types; nullOr (enum [ "host" "csi" ]);
        default = null;
        description = ''
          Specifies the type of a given volume. The valid volume types are "host" and "csi".
        '';
      };

      source = lib.mkOption {
        type = with lib.types; str;
        default = null;
        description = ''
          Specifies the type of a given volume. The valid volume types are "host" and "csi".
        '';
      };

      readOnly = lib.mkOption {
        type = with lib.types; bool;
        default = false;
        description = ''
          Specifies that the group only requires read only access to a volume
          and is used as the default value for the volumeMount -> readOnly
          configuration.
          This value is also used for validating hostVolume ACLs and for
          scheduling when a matching hostVolume requires readOnly usage.
        '';
      };

      mountOptions = lib.mkOption {
        default = null;

        description = ''
          Options for mounting CSI volumes that have the file-system attachment
          mode. These options override the mount_options field from volume
          registration. Consult the documentation for your storage provider and
          CSI plugin as to whether these options are required or necessary.
        '';

        type = with lib.types;
          nullOr (submodule {
            options = {
              fsType = lib.mkOption {
                type = with lib.types; nullOr str;
                default = null;
                description = ''file system type (ex. "ext4")'';
              };
              mountFlags = lib.mkOption {
                type = with lib.types; nullOr str;
                default = null;
                description = ''the flags passed to mount (ex. "ro,noatime")'';
              };
            };
          });
      };
    };
  });

  taskGroupType = submodule ({ name, ... }: {
    options = {
      name = lib.mkOption {
        type = with lib.types; str;
        default = name;
      };

      tasks = lib.mkOption {
        type = with lib.types; attrsOf taskType;
        default = { };
        description = "";
        apply = lib.attrValues;
      };

      constraints = lib.mkOption {
        type = with lib.types; nullOr (listOf constraintType);
        default = null;
        apply = mapConstraints;
        description = ''
          A list to define additional constraints where a job can be run.
        '';
      };

      affinities = lib.mkOption {
        type = with lib.types; nullOr (listOf affinityType);
        default = null;
        apply = mapAffinities;
        description = ''
          Affinities allow operators to express placement preferences.
          https://www.nomadproject.io/docs/job-specification/affinity
        '';
      };

      spreads = mkSpreadOption;

      count = lib.mkOption {
        type = with lib.types; ints.unsigned;
        default = 1;
        description = ''
          Specifies the number of the task groups that should be running under
          this group.
        '';
      };

      ephemeralDisk = lib.mkOption {
        type = with lib.types; nullOr ephemeralDiskType;
        default = null;
        description = ''
          Specifies the ephemeral disk requirements of the group.
          Ephemeral disks can be marked as sticky and support live data migrations.
        '';
      };

      networks = lib.mkOption {
        type = with lib.types; nullOr (listOf networkType);
        default = null;
        apply = mapNetworks;
      };

      meta = lib.mkOption {
        type = with lib.types; nullOr (attrsOf str);
        default = null;
        description = ''
          A key-value map that annotates the Consul service with user-defined
          metadata. String interpolation is supported in meta.
        '';
      };

      migrate = mkMigrateOption;

      # reschedule (Reschedule: nil) - Allows to specify a rescheduling strategy. Nomad will then attempt to schedule the task on another node if any of the group allocation statuses become "failed".

      restartPolicy = lib.mkOption {
        type = with lib.types; nullOr restartPolicyType;
        default = null;
        description = ''
          Specifies the restart policy for all tasks in this group.
          If omitted, a default policy exists for each job type, which can be found in the restart stanza documentation.
        '';
      };

      services = lib.mkOption {
        apply = lib.attrValues;
        type = with lib.types; serviceType;
        default = { };
      };

      shutdownDelay = lib.mkOption {
        type = with lib.types; nullOr nanoseconds;
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

      update = lib.mkOption {
        default = null;
        type = with lib.types;
          nullOr (submodule {
            options = {
              maxParallel = lib.mkOption {
                type = with lib.types; ints.positive;
                default = 1;
              };
            };
          });
      };

      vault = lib.mkOption {
        type = with lib.types; vaultType;
        default = null;
        description = ''
          Specifies the set of Vault policies required by all tasks in this group.
          Overrides a vault block set at the job level.
        '';
      };

      reschedulePolicy = lib.mkOption {
        type = with lib.types; nullOr reschedulePolicyType;
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

      volumes = lib.mkOption {
        type = with lib.types; attrsOf volumeType;
        default = { };
        description = ''
          Allows the group to specify that it requires a given volume from the cluster.
          The key is the name of the volume as it will be exposed to task configuration.
        '';
      };
    };
  });

  networkType = submodule {
    options = {
      mode = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description = ''
          none: Task group will have an isolated network without any network
          interfaces.

          bridge: Task group will have an isolated network namespace with an
          interface that is bridged with the host. Note that bridge networking
          is only currently supported for the docker, exec, raw_exec, and java
          task drivers.

          host: Each task will join the host network namespace and a shared
          network namespace is not created. This matches the current behavior
          in Nomad 0.9.

          cni/<cni network name>: Task group will have an isolated network
          namespace with the network configured by CNI.
        '';
      };

      ports = lib.mkOption {
        default = { };
        type = with lib.types;
          attrsOf (submodule ({ name, ... }: {
            options = {
              label = lib.mkOption {
                type = with lib.types; str;
                description = ''
                  Label is the key for HCL port stanzas: port "foo" {}
                '';
              };

              static = lib.mkOption {
                type = with lib.types; nullOr port;
                default = null;
                description = ''
                  Specifies the static TCP/UDP port to allocate. If omitted, a
                  dynamic port is chosen. We do not recommend using static ports,
                  except for system or specialized jobs like load balancers.
                '';
              };

              to = lib.mkOption {
                type = with lib.types; nullOr int;
                default = null;
                description = ''
                  Applicable when using "bridge" mode to configure port to map to
                  inside the task's network namespace. -1 sets the mapped port
                  equal to the dynamic port allocated by the scheduler.  The
                  NOMAD_PORT_<label> environment variable will contain the to
                  value.
                '';
              };

              hostNetwork = lib.mkOption {
                type = with lib.types; nullOr str;
                default = null;
                description = ''
                  Designates the host network name to use when allocating the
                  port.  When port mapping the host port will only forward
                  traffic to the matched host network address.
                '';
              };
            };
          }));
      };

      dns = {
        servers = lib.mkOption {
          type = with lib.types; nullOr (listOf str);
          default = null;
          description =
            "Sets the DNS nameservers the allocation uses for name resolution.";
        };

        searches = lib.mkOption {
          type = with lib.types; nullOr (listOf str);
          default = null;
          description = "Sets the search list for hostname lookup";
        };

        options = lib.mkOption {
          type = with lib.types; nullOr (listOf str);
          default = null;
          description = "Sets internal resolver variables.";
        };
      };
    };
  };

  vaultType = nullOr (submodule {
    options = {
      policies = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
        description = ''
          Specifies the set of Vault policies that the task requires. The Nomad
          client will retrieve a Vault token that is limited to those policies.
        '';
      };

      changeMode = lib.mkOption {
        type = with lib.types; enum [ "noop" "restart" "signal" ];
        default = "restart";
        description = ''
          Specifies the behavior Nomad should take if the Vault token changes.
        '';
      };

      changeSignal = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description = ''
          Specifies the signal to send to the task as a string like "SIGUSR1"
          or "SIGINT". This option is required if the changeMode is signal.
        '';
      };

      env = lib.mkOption {
        type = with lib.types; bool;
        default = true;
        description = ''
          Specifies if the VAULT_TOKEN and VAULT_NAMESPACE environment
          variables should be set when starting the task.
        '';
      };

      namespace = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description = ''
          Specifies the Vault Namespace to use for the task. The Nomad client
          will retrieve a Vault token that is scoped to this particular
          namespace.
        '';
      };
    };
  });

  restartPolicyType = submodule {
    options = {
      attempts = lib.mkOption {
        type = with lib.types; nullOr ints.positive;
        default = null;
        description = ''
          Specifies the number of restarts allowed in the configured interval.
          Defaults vary by job type.
          https://www.nomadproject.io/docs/job-specification/restart/
        '';
      };

      interval = lib.mkOption {
        type = with lib.types; nullOr nanoseconds;
        default = null;
        description = ''
          Specifies the duration which begins when the first task starts and ensures that only attempts number of restarts happens within it.
          If more than attempts number of failures happen, behavior is controlled by mode.
          This is specified using a label suffix like "30s" or "1h".
          Defaults vary by job type.
          https://www.nomadproject.io/docs/job-specification/restart/
        '';
      };

      delay = lib.mkOption {
        type = with lib.types; nanoseconds;
        default = "15s";
        description = ''
          Specifies the duration to wait before restarting a task.
          This is specified using a label suffix like "30s" or "1h".
          A random jitter of up to 25% is added to the delay.
          https://www.nomadproject.io/docs/job-specification/restart/
        '';
      };

      mode = lib.mkOption {
        type = with lib.types; enum [ "delay" "fail" ];
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
      migrate = lib.mkEnableOption
        "Specifies that the Nomad client should make a best-effort attempt to migrate the data from a remote machine if placement cannot be made on the original node. During data migration, the task will block starting until the data migration has completed. Value is a boolean and the default is false.";

      sizeMB = lib.mkOption {
        type = with lib.types; ints.positive;
        default = 300;
        description = ''
          Specifies the size of the ephemeral disk in MB. Default is 300.
        '';
      };

      sticky = lib.mkEnableOption ''
        Specifies that Nomad should make a best-effort attempt to place the updated allocation on the same machine. This will move the local/ and alloc/data directories to the new allocation. Value is a boolean and the default is false.
      '';
    };
  };

  migrateType = submodule {
    options = {
      healthCheck = lib.mkOption {
        type = with lib.types; enum [ "checks" "task_states" ];
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

      maxParallel = lib.mkOption {
        type = with lib.types; ints.positive;
        default = 1;
        description = ''
          Specifies the number of allocations within a task group that can be
          updated at the same time. The task groups themselves are updated in
          parallel.
        '';
      };

      minHealthyTime = lib.mkOption {
        type = with lib.types; nanoseconds;
        default = "10s";
        description = ''
          Specifies the minimum time the allocation must be in the healthy state before
          it is marked as healthy and unblocks further allocations from being updated.
          This is specified using a label suffix like "30s" or "15m".
        '';
      };

      healthyDeadline = lib.mkOption {
        type = with lib.types; nanoseconds;
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
      source = lib.mkOption {
        type = with lib.types; str;
        description = ''
          The path to the artifact to download.
          https://www.nomadproject.io/api-docs/json-jobs/#artifact
        '';
      };
      destination = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        description = ''
          An optional path to download the artifact into relative to the root of the task's directory.
          If omitted, it will default to local/.
          https://www.nomadproject.io/api-docs/json-jobs/#artifact
        '';
      };
      options = lib.mkOption {
        type = with lib.types; nullOr (attrsOf str);
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
      data = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        description = ''
          Specifies the raw template to execute.
          One of source or data must be specified, but not both.
          This is useful for smaller templates, but we recommend using source for larger templates.
        '';
      };

      destination = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        description = ''
          Specifies the location where the resulting template should be
          rendered, relative to the task directory.
        '';
      };

      source = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        description = ''
          Specifies the path to the template to be rendered. One of source or
          data must be specified, but not both. This source can optionally be
          fetched using an artifact resource. This template must exist on the
          machine prior to starting the task; it is not possible to reference a
          template inside of a Docker container, for example.
        '';
      };

      env = lib.mkOption {
        type = with lib.types; bool;
        default = false;
        description = ''
          Specifies the template should be read back as environment variables
          for the task.
        '';
      };

      changeMode = lib.mkOption {
        type = with lib.types; nullOr (enum [ "restart" "signal" "noop" ]);
        default = "restart";
        description = ''
          Specifies the behavior Nomad should take if the rendered template
          changes. Nomad will always write the new contents of the template to
          the specified destination. The possible values below describe Nomad's
          action after writing the template to disk.
        '';
      };

      changeSignal = lib.mkOption {
        type =
          nullOr (enum [ "SIGHUP" "SIGINT" "SIGUSR1" "SIGUSR2" "SIGTERM" ]);
        default = null;
        description = ''
          Specifies the signal to send to the task as a string like "SIGUSR1" or "SIGINT". This option is required if the ChangeMode is signal.
        '';
      };

      splay = lib.mkOption {
        type = with lib.types; nanoseconds;
        default = "5s";
        description = ''
          Specifies a random amount of time to wait between 0 ms and the given
          splay value before invoking the change mode. This is specified using
          a label suffix like "30s" or "1h", and is often used to prevent a
          thundering herd problem where all task instances restart at the same
          time.
        '';
      };
    };
  });

  lifecycleType = submodule {
    options = {
      hook = lib.mkOption {
        type = with lib.types;
          nullOr (enum [ "prestart" "poststart" "poststop" ]);
        default = null;
      };

      sidecar = lib.mkOption {
        type = with lib.types; nullOr bool;
        default = null;
      };
    };
  };

  taskType = submodule ({ name, ... }: {
    options = {
      volumeMounts = lib.mkOption {
        type = with lib.types; attrsOf volumeMountType;
        apply = lib.attrValues;
        default = { };
      };

      artifacts = lib.mkOption {
        type = with lib.types; nullOr (listOf artifactType);
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

      lifecycle = lib.mkOption {
        type = with lib.types; lifecycleType;
        default = { };
      };

      templates = lib.mkOption {
        type = with lib.types; nullOr (listOf templateType);
        default = null;
        apply = mapTemplates;
        description = ''
          The template block instantiates an instance of a template renderer.
          This creates a convenient way to ship configuration files that are
          populated from environment variables, Consul data, Vault secrets, or
          just general configurations within a Nomad task.
        '';
      };

      config = lib.mkOption {
        type = with lib.types; attrs;
        default = { };
        description = ''
          Specifies the driver configuration, which is passed directly to the
          driver to start the task.
          The details of configurations are specific to each driver, so please
          see specific driver documentation for more information.
          https://www.nomadproject.io/docs/drivers
        '';
      };

      driver = lib.mkOption {
        type = with lib.types; str;
        description = ''
          Specifies the task driver that should be used to run the task.
          See the driver documentation for what is available.
          Examples include docker, qemu, java and exec.
          https://www.nomadproject.io/docs/drivers
        '';
      };

      name = lib.mkOption {
        type = with lib.types; str;
        default = name;
      };

      env = lib.mkOption {
        type = with lib.types; nullOr (attrsOf str);
        default = null;
        description = ''
          Specifies environment variables that will be passed to the running process.
        '';
      };

      constraints = lib.mkOption {
        type = with lib.types; nullOr (listOf constraintType);
        default = null;
        apply = mapConstraints;
        description = ''
          A list to define additional constraints where a job can be run.
        '';
      };

      shutdownDelay = lib.mkOption {
        type = with lib.types; nanoseconds;
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

      killSignal = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description = ''
          Specifies a configurable kill signal for a task, where the default is
          SIGINT. Note that this is only supported for drivers which accept
          sending signals (currently docker, exec, raw_exec, and java drivers).
        '';
      };

      resources = lib.mkOption {
        default = null;
        type = with lib.types;
          nullOr (submodule {
            options = {
              cpu = lib.mkOption {
                type = with lib.types; ints.positive;
                default = 100;
              };

              memoryMB = lib.mkOption {
                type = with lib.types; ints.positive;
                default = 300;
              };

              networks = lib.mkOption {
                type = with lib.types; nullOr (listOf networkType);
                default = null;
                apply = mapNetworks;
              };
            };
          });
      };

      user = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description = ''
          Set the user that will run the task. It defaults to the same user the
          Nomad client is being run as. This can only be set on Linux
          platforms.
        '';
      };

      vault = lib.mkOption {
        type = with lib.types; vaultType;
        default = null;
        description = ''
          Specifies the set of Vault policies required by all tasks in this group.
          Overrides a vault block set at the job level.
        '';
      };

      services = lib.mkOption {
        apply = lib.attrValues;
        type = with lib.types; serviceType;
        default = { };
      };

      restartPolicy = lib.mkOption {
        type = with lib.types; nullOr restartPolicyType;
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
      timeZone = lib.mkOption {
        type = with lib.types; nullOr str;
        description = ''
          Specifies the time zone to evaluate the next launch interval against.
          This is useful when wanting to account for day light savings in various time zones.
          The time zone must be parsable by Golang's LoadLocation.
          The default is UTC.
          https://golang.org/pkg/time/#LoadLocation
        '';
      };

      cron = lib.mkOption {
        type = with lib.types; nullOr str;
        description = ''
          A cron expression configuring the interval the job is launched at.
          Supports predefined expressions such as "@daily" and "@weekly".
          See here for full documentation of supported cron specs and the
          predefined expressions.
          https://github.com/gorhill/cronexpr#implementation
        '';
      };

      prohibitOverlap = lib.mkEnableOption ''
        Can be set to true to enforce that the periodic job doesn't spawn a new
        instance of the job if any of the previous jobs are still running.
        It is defaults to false.
      '';
    };
  };

  constraintType = submodule {
    options = {
      attribute = lib.mkOption {
        type = with lib.types; str;
        default = "";
      };

      operator = lib.mkOption {
        type = with lib.types;
          enum [
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

      value = lib.mkOption {
        type = with lib.types; str;
        default = "";
      };
    };
  };

  affinityType = submodule {
    options = {
      attribute = lib.mkOption {
        type = with lib.types; str;
        default = "";
      };

      operator = lib.mkOption {
        type = with lib.types; str;
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

      value = lib.mkOption {
        type = with lib.types; str;
        default = "";
      };

      weight = lib.mkOption {
        type = with lib.types; ints.between - 100 100;
        default = 50;
      };
    };
  };

  spreadTargetType = submodule {
    options = {
      value = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description = ''
          The value of a specific target attribute, like "dc1" for ''${node.datacenter}.
        '';
      };

      percent = lib.mkOption {
        type = with lib.types; ints.unsigned;
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
      attribute = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description = ''
          Specifies the name or reference of the attribute to use.
          This can be any of the Nomad interpolated values.
        '';
      };

      target = lib.mkOption {
        type = with lib.types; nullOr (listOf spreadTargetType);
        default = null;
        apply = mapSpreadTarget;
        description = ''
          Specifies one or more target percentages for each value of the
          attribute in the spread stanza.
          If this is omitted, Nomad will spread allocations evenly across all
          values of the attribute.
        '';
      };

      weight = lib.mkOption {
        type = with lib.types; ints.between 0 100;
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
      metaOptional = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
        description = ''
          Specifies the set of metadata keys that may be provided when dispatching against the job.
        '';
      };

      metaRequired = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
        description = ''
          Specifies the set of metadata keys that must be provided when dispatching against the job.
        '';
      };

      payload = lib.mkOption {
        type = with lib.types; enum [ "optional" "required" "forbidden" ];
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
      healthCheck = lib.mkOption {
        type = with lib.types; enum [ "checks" "task_states" "manual" ];
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

      maxParallel = lib.mkOption {
        type = with lib.types; ints.positive;
        default = 1;
        description = ''
          Specifies the number of allocations within a task group that can be
          updated at the same time. The task groups themselves are updated in
          parallel.
        '';
      };

      minHealthyTime = lib.mkOption {
        type = with lib.types; nanoseconds;
        default = "10s";
        description = ''
          Specifies the minimum time the allocation must be in the healthy state before
          it is marked as healthy and unblocks further allocations from being updated.
          This is specified using a label suffix like "30s" or "15m".
        '';
      };

      healthyDeadline = lib.mkOption {
        type = with lib.types; nanoseconds;
        default = "5m";
        description = ''
          Specifies the deadline in which the allocation must be marked as healthy after
          which the allocation is automatically transitioned to unhealthy.
          This is specified using a label suffix like "2m" or "1h".
        '';
      };

      progressDeadline = lib.mkOption {
        type = with lib.types; nanoseconds;
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

      autoRevert = lib.mkEnableOption ''
        Specifies if the job should auto-revert to the last stable job on deployment failure.
        A job is marked as stable if all the allocations as part of its deployment were marked healthy.
      '';

      autoPromote = lib.mkEnableOption ''
        Specifies if the job should auto-promote to the canary version when all
        canaries become healthy during a deployment. Defaults to false which
        means canaries must be manually updated with the nomad deployment promote
        command.
      '';

      canary = lib.mkOption {
        type = with lib.types; ints.unsigned;
        default = 0;
        description = ''
          Specifies that changes to the job that would result in destructive
          updates should create the specified number of canaries without
          stopping any previous allocations. Once the operator determines the
          canaries are healthy, they can be promoted which unblocks a rolling
          update of the remaining allocations at a rate of max_parallel.
        '';
      };

      stagger = lib.mkOption {
        type = with lib.types; nanoseconds;
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
      attempts = lib.mkOption {
        type = with lib.types; nullOr ints.unsigned;
        default = null;
        description = ''
          Specifies the number of reschedule attempts allowed in the configured
          interval. Defaults vary by job type.
        '';
      };

      interval = lib.mkOption {
        type = with lib.types; nullOr nanoseconds;
        default = null;
        description = ''
          Specifies the sliding window which begins when the first reschedule
          attempt starts and ensures that only attempts number of reschedule
          happen within it. If more than attempts number of failures happen with
          this interval, Nomad will not reschedule any more.
        '';
      };

      delay = lib.mkOption {
        type = with lib.types; nullOr nanoseconds;
        default = null;
        description = ''
          Specifies the duration to wait before attempting to reschedule a failed
          task. This is specified using a label suffix like "30s" or "1h".
        '';
      };

      delayFunction = lib.mkOption {
        type = with lib.types; enum [ "constant" "exponential" "fibonacci" ];
        default = "constant";
        description = ''
          Specifies the function that is used to calculate subsequent reschedule
          delays. The initial delay is specified by the delay parameter.
        '';
      };

      maxDelay = lib.mkOption {
        type = with lib.types; nullOr nanoseconds;
        default = null;
        description = ''
          MaxDelay is an upper bound on the delay beyond which it will not
          increase. This parameter is used when DelayFunction is exponential or
          fibonacci, and is ignored when constant delay is used.
        '';
      };

      unlimited = lib.mkOption {
        type = with lib.types; nullOr bool;
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
    affinities = lib.mkOption {
      type = with lib.types; nullOr (listOf affinityType);
      default = null;
      apply = mapAffinities;
      description = ''
        Affinities allow operators to express placement preferences.
        https://www.nomadproject.io/docs/job-specification/affinity
      '';
    };

    allAtOnce = lib.mkOption {
      type = with lib.types; nullOr bool;
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

    constraints = lib.mkOption {
      type = with lib.types; nullOr (listOf constraintType);
      default = null;
      apply = mapConstraints;
      description = ''
        A list to define additional constraints where a job can be run.
        https://www.nomadproject.io/docs/job-specification/constraint
      '';
    };

    datacenters = lib.mkOption {
      type = with lib.types; listOf str;
      description = ''
        A list of datacenters in the region which are eligible for task placement.
        This must be provided, and does not have a default.
      '';
    };

    id = lib.mkOption {
      type = with lib.types; str;
      default = config.name;
    };

    meta = lib.mkOption {
      type = with lib.types; nullOr (attrsOf str);
      default = null;
      description = ''
        A key-value map that annotates the Consul service with user-defined
        metadata. String interpolation is supported in meta.
      '';
    };

    migrate = mkMigrateOption;

    name = lib.mkOption {
      type = with lib.types; str;
      default = name;
    };

    namespace = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      description = ''
        The namespace to execute the job in, defaults to "default".
        Values other than default are not allowed in non-Enterprise versions of Nomad.
      '';
    };

    parameterizedJob = lib.mkOption {
      type = with lib.types; nullOr parameterizedJobType;
      default = null;
      description = ''
        Specifies the job as a parameterized job such that it can be
        dispatched against.
      '';
    };

    periodic = lib.mkOption {
      type = with lib.types; nullOr periodicType;
      default = null;
      apply = mapPeriodic;
      description = ''
        allows the job to be scheduled at fixed times, dates or intervals.
        The periodic expression is always evaluated in the UTC timezone to
        ensure consistent evaluation when Nomad Servers span multiple time
        zones.
      '';
    };

    priority = lib.mkOption {
      type = with lib.types; nullOr (ints.between 1 100);
      default = null;
      description = ''
        Specifies the job priority which is used to prioritize scheduling and
        access to resources. Must be between 1 and 100 inclusively, and
        defaults to 50.
      '';
    };

    region = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      description = ''
        The region to run the job in, defaults to "global".
      '';
    };

    reschedulePolicy = lib.mkOption {
      type = with lib.types; nullOr reschedulePolicyType;
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

    taskGroups = lib.mkOption {
      type = with lib.types; attrsOf taskGroupType;
      default = { };
      apply = lib.attrValues;
      description = ''
        Specifies the start of a group of tasks.
        This can be provided multiple times to define additional groups.
      '';
    };

    type = lib.mkOption {
      type = with lib.types; enum [ "service" "system" "batch" ];
      default = "service";
      description = ''
        Specifies the Nomad scheduler to use.
        Nomad provides the service, system and batch schedulers.
        https://www.nomadproject.io/docs/schedulers/
      '';
    };

    update = lib.mkOption {
      type = with lib.types; nullOr updateType;
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
