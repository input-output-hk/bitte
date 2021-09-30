// INFORMATION:
//
// This file acts as a CUE type schema for nomad JSON job submission in bitte end use repos.
// This ensures that JSON jobs created by CUE conform to Nomads JSON job spec found at:
//
//   https://www.nomadproject.io/api-docs/json-jobs
//
// Not all valid Nomad JSON job options may be included here yet; this file can be extended as needed.
// If expected Nomad job properties are still not appearing in deployed jobs, check that bitte-cli
// is allowing the expected JSON through the [de]serialization parsing.
//
// In bitte end use repos, this file normally lives at:
//
//   schemas/nomad/types.cue
//
package types

import (
	"time"
	"list"
)

// The #json block defines the final JSON structure and values types.
#json: {
	Job: {
		Namespace:   string
		ID:          Name
		Name:        string
		Type:        "service" | "system" | "batch"
		Priority:    uint
		Datacenters: list.MinItems(1)
		TaskGroups: [...TaskGroup]
		Affinities: [...Affinity]
		Constraints: [...Constraint]
		Spreads: [...Spread]
		ConsulToken: *null | string
		VaultToken:  *null | string
		Vault:       *null | #json.Vault
		Update:      *null | #json.Update
		Migrate:     *null | #json.Migrate
		Periodic:    *null | #json.Periodic
	}

	Affinity: {
		LTarget: string
		RTarget: string
		Operand: "regexp" | "set_contains_all" | "set_contains" | "set_contains_any" | "=" | "==" | "is" | "!=" | "not" | ">" | ">=" | "<" | "<=" | "version"
		Weight:  uint & !=0 & >=-100 & <=100
	}

	Constraint: {
		LTarget: string | *null
		RTarget: string
		Operand: "regexp" | "set_contains" | "distinct_hosts" | "distinct_property" | "=" | "==" | "is" | "!=" | "not" | ">" | ">=" | "<" | "<="
	}

	Spread: {
		Attribute: string
		Weight:    uint & >=-100 & <=100 | *null
		SpreadTarget: [...SpreadTargetElem]
	}

	SpreadTargetElem: {
		Value:   string
		Percent: uint & >=0 & <=100 | *null
	}

	RestartPolicy: {
		Attempts: uint
		Interval: uint
		Delay:    uint
		Mode:     "delay" | "fail"
	}

	Volume: {
		Name:         string
		Type:         *null | "host" | "csi"
		Source:       string
		ReadOnly:     bool | *false
		MountOptions: *null | {
			FsType:     *null | string
			mountFlags: *null | string
		}
	}

	ReschedulePolicy: {
		Attempts:      *null | uint
		DelayFunction: *null | "constant" | "exponential" | "fibonacci"
		Delay:         *null | uint & >=time.ParseDuration("5s")
		Interval:      *null | uint
		MaxDelay:      *null | uint
		Unlimited:     *null | bool
	}

	Migrate: {
		HealthCheck:     *"checks" | "task_states"
		HealthyDeadline: uint | *500000000000
		MaxParallel:     uint | *1
		MinHealthyTime:  uint | *10000000000
	}

	Periodic: {
		Enabled:         bool | *false
		TimeZone:        string | *"UTC"
		SpecType:        "cron"
		Spec:            string
		ProhibitOverlap: bool | *false
	}

	Update: {
		AutoPromote:      bool | *false
		AutoRevert:       bool | *false
		Canary:           uint | *0
		HealthCheck:      *"checks" | "task_states" | "manual"
		HealthyDeadline:  uint | *null
		MaxParallel:      uint | *1
		MinHealthyTime:   uint | *null
		ProgressDeadline: uint | *null
		Stagger:          uint | *null
	}

	TaskGroup: {
		Affinities: [...Affinity]
		Constraints: [...Constraint]
		Spreads: [...Spread]
		Count: int & >0 | *1
		Meta: [string]: string
		Name:          string
		RestartPolicy: *null | #json.RestartPolicy
		Services: [...Service]
		ShutdownDelay: uint | *0
		Tasks: [...Task]
		Volumes: [string]: #json.Volume
		ReschedulePolicy: #json.ReschedulePolicy
		EphemeralDisk:    *null | {
			Migrate: bool
			SizeMB:  uint
			Sticky:  bool
		}
		Migrate: *null | #json.Migrate
		Update:  *null | #json.Update
		Networks: [...#json.Network]
		StopAfterClientDisconnect: *null | uint
		Scaling:                   null
		Vault:                     *null | #json.Vault
	}

	Dns: {
		servers: *null | [...string]
	}

	Port: {
		Label:       string
		Value:       uint | *null // used for static ports
		To:          uint | *null
		HostNetwork: string | *""
	}

	Network: {
		Mode:          *"host" | "bridge"
		Device:        string | *""
		CIDR:          string | *""
		IP:            string | *""
		DNS:           *null | #json.Dns
		ReservedPorts: *null | [...#json.Port]
		DynamicPorts:  *null | [...#json.Port]
		MBits:         null
	}

	ServiceCheck: {
		AddressMode:            "alloc" | "driver" | "host"
		Args:                   [...string] | *null
		CheckRestart:           #json.CheckRestart
		Command:                string | *""
		Expose:                 bool | *false
		FailuresBeforeCritical: uint | *0
		Id:                     string | *""
		InitialStatus:          string | *""
		Interval:               uint | *10000000000
		Method:                 string | *""
		Name:                   string | *""
		Path:                   string | *""
		PortLabel:              string
		Protocol:               string | *""
		SuccessBeforePassing:   uint | *0
		TaskName:               string | *""
		Timeout:                uint
		TLSSkipVerify:          bool | *false
		OnUpdate:               *"" | "require_healthy" | "ignore_warnings" | "ignore"
		Type:                   "http" | "tcp" | "script" | "grpc"
		Body:                   string | *null
		Header: [string]: [...string]
	}

	CheckRestart: *null | {
		Limit:          uint | *0
		Grace:          uint | *10000000000
		IgnoreWarnings: bool | *false
	}

	Lifecycle: {
		Hook:    "prestart" | "poststart" | "poststop"
		Sidecar: bool | *null
	}

	LogConfig: *null | {
		MaxFiles:      uint & >0
		MaxFileSizeMB: uint & >0
	}

	Expose: {
		Path:          string
		Protocol:      *"http" | "http2"
		ListenerPort:  string
		LocalPathPort: uint
	}

	Upstreams: {
		Datacenter:       string
		DestinationName:  string
		LocalBindAddress: string
		LocalBindPort:    uint
		MeshGateway:      null
	}

	Proxy: *null | {
		Config:              *null | {[string]: string}
		ExposeConfig:        *null | {Path: [...#json.Expose]}
		LocalServiceAddress: string
		LocalServicePort:    uint
		Upstreams:           *null | [...#json.Upstreams]
	}

	SidecarService: *null | {
		DisableDefaultTCPCheck: bool | *false
		Port:                   string
		Proxy:                  #json.Proxy
		Tags:                   null
	}

	SidecarTask: *null | {
		Config: #stanza.taskConfig & {#driver: Driver}
		Driver: "docker"
		Env: [string]: string
		Name: string
		User: string
	}

	Connect: *null | {
		Gateway:        null
		Native:         bool | *false
		SidecarService: #json.SidecarService
		SidecarTask:    #json.SidecarTask
	}

	Service: {
		Id:   string | *""
		Name: string
		Tags: [...string]
		CanaryTags:        [...string] | *[]
		EnableTagOverride: bool | *false
		PortLabel:         string
		AddressMode:       "alloc" | "auto" | "driver" | "host"
		Checks: [...ServiceCheck]
		CheckRestart: #json.CheckRestart
		Connect:      #json.Connect
		Meta: [string]: string
		TaskName: string | *""
	}

	Task: {
		Name:   string
		Driver: "exec" | "docker" | "nspawn"
		Config: #stanza.taskConfig & {#driver: Driver}
		Constraints: [...Constraint]
		Affinities: [...Affinity]
		Env: [string]: string
		Services: [...Service]
		Resources: {
			CPU:      uint & >=100 | *100
			MemoryMB: uint & >=32 | *300
			DiskMB:   *null | uint
		}
		Meta: {}
		RestartPolicy: *null | #json.RestartPolicy
		ShutdownDelay: uint | *0
		User:          string | *""
		Lifecycle:     *null | #json.Lifecycle
		KillTimeout:   *null | uint
		LogConfig:     #json.LogConfig
		Artifacts: [...#json.Artifact]
		Templates: [...#json.Template]
		DispatchPayload: null
		VolumeMounts: [...#json.VolumeMount]
		Leader:          bool | *false
		KillSignal:      string
		ScalingPolicies: null
		Vault:           *null | #json.Vault
	}

	VolumeMount: {
		Destination:     string
		PropagationMode: string
		ReadOnly:        bool
		Volume:          string
	}

	Artifact: {
		GetterSource: string
		GetterOptions: [string]: string
		GetterHeaders: [string]: string
		GetterMode:   *"any" | "file" | "dir"
		RelativeDest: string
	}

	Template: {
		SourcePath:   string | *""
		DestPath:     string
		EmbeddedTmpl: string
		ChangeMode:   *"restart" | "noop" | "signal"
		ChangeSignal: string | *""
		Splay:        uint | *5000000000
		Perms:        *"0644" | =~"^[0-7]{4}$"
		LeftDelim:    string
		RightDelim:   string
		Envvars:      bool
	}

	Vault: {
		ChangeMode:   "noop" | *"restart" | "signal"
		ChangeSignal: string | *""
		Env:          bool | *true
		Namespace:    string | *""
		Policies:     list.MinItems(1)
	}
}

#dockerUrlPath: =~"^([0-9a-zA-Z-.]+/)+[0-9a-zA-Z-@]+:[0-9a-zA-Z-.]+$"
#duration:      =~"^[1-9]\\d*[hms]$"
#gitRevision:   =~"^[a-f0-9]{40}$"
#flake:         =~"^(?:github|git\\+ssh|git):(?:[0-9a-zA-Z_-]+/)+[0-9a-zA-Z_-]+(?:\\?rev=[0-9a-fA-F]{40})?#[0-9a-zA-Z_-]+"

// The #toJson block is evaluated from deploy.cue during rendering of the namespace jobs.
// #job and #jobName are passed to #toJson during this evaluation.
// #toJson evaluation is constrained by the #json.Job block defined at the start of this file.
#toJson: #json.Job & {
	#job:        #stanza.job
	#jobName:    string
	Name:        #jobName
	Datacenters: #job.datacenters
	Namespace:   #job.namespace
	Type:        #job.type
	Priority:    #job.priority

	if #job.update != null {
		let u = #job.update
		Update: {
			AutoPromote:      u.auto_promote
			AutoRevert:       u.auto_revert
			Canary:           u.canary
			HealthCheck:      u.health_check
			HealthyDeadline:  time.ParseDuration(u.healthy_deadline)
			MaxParallel:      u.max_parallel
			MinHealthyTime:   time.ParseDuration(u.min_healthy_time)
			ProgressDeadline: time.ParseDuration(u.progress_deadline)
			Stagger:          time.ParseDuration(u.stagger)
		}
	}

	if #job.migrate != null {
		let m = #job.migrate
		Migrate: {
			HealthCheck:     m.health_check
			HealthyDeadline: m.healthy_deadline
			MaxParallel:     m.max_parallel
			MinHealthyTime:  m.min_healthy_time
		}
	}

	if #job.periodic != null {
		let p = #job.periodic
		Periodic: {
			Enabled:         true
			TimeZone:        p.time_zone
			Spec:            p.cron
			ProhibitOverlap: p.prohibit_overlap
		}
	}

	if #job.vault != null {
		Vault: {
			ChangeMode:   #job.vault.change_mode
			ChangeSignal: #job.vault.change_signal
			Env:          #job.vault.env
			Namespace:    #job.vault.namespace
			Policies:     #job.vault.policies
		}
	}

	Affinities: [ for a in #job.affinities {
		LTarget: a.attribute
		RTarget: a.value
		Operand: a.operator
		Weight:  a.weight
	}]

	Constraints: [ for c in #job.constraints {
		LTarget: c.attribute
		RTarget: c.value
		Operand: c.operator
	}]

	Spreads: [ for s in #job.spreads {
		Attribute: s.attribute
		Weight:    s.weight
		SpreadTarget: [ for t in s.target {
			Value:   t.value
			Percent: t.percent
		}]
	}]

	TaskGroups: [ for tgName, tg in #job.group {
		Name: tgName

		Count: tg.count

		Affinities: [ for a in tg.affinities {
			LTarget: a.attribute
			RTarget: a.value
			Operand: a.operator
			Weight:  a.weight
		}]

		Constraints: [ for c in tg.constraints {
			LTarget: c.attribute
			RTarget: c.value
			Operand: c.operator
		}]

		Spreads: [ for s in tg.spreads {
			Attribute: s.attribute
			Weight:    s.weight
			SpreadTarget: [ for t in s.target {
				Value:   t.value
				Percent: t.percent
			}]
		}]

		if tg.reschedule != null {
			ReschedulePolicy: {
				Attempts:      tg.reschedule.attempts
				DelayFunction: tg.reschedule.delay_function
				if tg.reschedule.delay != _|_ {
					Delay: time.ParseDuration(tg.reschedule.delay)
				}
				if tg.reschedule.interval != _|_ {
					Interval: time.ParseDuration(tg.reschedule.interval)
				}
				if tg.reschedule.max_delay != _|_ {
					MaxDelay: time.ParseDuration(tg.reschedule.max_delay)
				}
				Unlimited: tg.reschedule.unlimited
			}
		}

		if tg.ephemeral_disk != null {
			EphemeralDisk: {
				SizeMB:  tg.ephemeral_disk.size
				Migrate: tg.ephemeral_disk.migrate
				Sticky:  tg.ephemeral_disk.sticky
			}
		}

		if tg.restart != null {
			RestartPolicy: {
				Interval: time.ParseDuration(tg.restart.interval)
				Attempts: tg.restart.attempts
				Delay:    time.ParseDuration(tg.restart.delay)
				Mode:     tg.restart.mode
			}
		}

		// only one network can be specified at group level, and we never use
		// deprecated task level ones.
		if tg.network != null {
			Networks: [{
				Mode: tg.network.mode
				DNS:  tg.network.dns
				ReservedPorts: [
					for nName, nValue in tg.network.port if nValue.static != null {
						Label:       nName
						Value:       nValue.static
						To:          nValue.to
						HostNetwork: nValue.host_network
					}]
				DynamicPorts: [
					for nName, nValue in tg.network.port if nValue.static == null {
						Label:       nName
						Value:       nValue.static
						To:          nValue.to
						HostNetwork: nValue.host_network
					}]
			}]
		}

		Services: [ for sName, s in tg.service {
			Name:        sName
			TaskName:    s.task
			Tags:        s.tags
			AddressMode: s.address_mode
			if s.check_restart != null {
				CheckRestart: {
					Limit:          s.check_restart.limit
					Grace:          time.ParseDuration(s.check_restart.grace)
					IgnoreWarnings: s.check_restart.ignore_warnings
				}
			}
			Checks: [ for cName, c in s.check {
				{
					AddressMode: c.address_mode
					Type:        c.type
					PortLabel:   c.port
					Command:     c.command
					Args:        c.args
					TaskName:    c.task
					Expose:      c.expose
					Interval:    time.ParseDuration(c.interval)
					if c.type == "http" {
						Path:     c.path
						Method:   c.method
						Protocol: c.protocol
					}
					Timeout:                time.ParseDuration(c.timeout)
					SuccessBeforePassing:   c.success_before_passing
					FailuresBeforeCritical: c.failures_before_critical
					TLSSkipVerify:          c.tls_skip_verify
					OnUpdate:               c.on_update
					InitialStatus:          c.initial_status
					Header:                 c.header
					Body:                   c.body
					if c.check_restart != null {
						CheckRestart: {
							Limit:          c.check_restart.limit
							Grace:          time.ParseDuration(c.check_restart.grace)
							IgnoreWarnings: c.check_restart.ignore_warnings
						}
					}
				}
			}]
			if s.connect != null {
				Connect: {
					Gateway: s.connect.gateway
					Native:  s.connect.native
					if s.connect.sidecar_service != null {
						SidecarService: {
							DisableDefaultTCPCheck: s.connect.sidecar_service.disable_default_tcp_check
							Port:                   s.connect.sidecar_service.port
							if s.connect.sidecar_service.proxy != null {
								let proxy = s.connect.sidecar_service.proxy
								Proxy: {
									Config: proxy.config
									if proxy.expose != null {
										ExposeConfig: Path: [ for e in proxy.expose.path {
											{
												Path:          e.path
												Protocol:      e.protocol
												ListenerPort:  e.listener_port
												LocalPathPort: e.local_path_port
											}
										}]
									}
									LocalServiceAddress: proxy.local_service_address
									LocalServicePort:    proxy.local_service_port
									if proxy.upstreams != null {
										Upstreams: [ for u in proxy.upstreams {
											{
												Datacenter:       u.datacenter
												DestinationName:  u.destination_name
												LocalBindAddress: u.local_bind_address
												LocalBindPort:    u.local_bind_port
												MeshGateway:      u.mesh_gateway
											}
										}]
									}
								}
							}
							Tags: s.connect.sidecar_service.tags
						}
					}
					if s.connect.sidecar_task != null {
						SidecarTask: {
							Name:   s.connect.sidecar_task.name
							Driver: s.connect.sidecar_task.driver
							User:   s.connect.sidecar_task.user
							Config: s.connect.sidecar_task.config
							Env:    s.connect.sidecar_task.env
						}
					}
				}
			}
			PortLabel: s.port
			Meta:      s.meta
		}]

		Tasks: [ for tName, t in tg.task {
			Name:       tName
			Driver:     t.driver
			Config:     t.config
			Env:        t.env
			KillSignal: t.kill_signal
			if t.kill_timeout != null {
				KillTimeout: time.ParseDuration(t.kill_timeout)
			}

			Affinities: [ for a in t.affinities {
				LTarget: a.attribute
				RTarget: a.value
				Operand: a.operator
				Weight:  a.weight
			}]

			Constraints: [ for c in t.constraints {
				LTarget: c.attribute
				RTarget: c.value
				Operand: c.operator
			}]

			if t.logs != null {
				LogConfig: {
					MaxFiles:      t.logs.max_files
					MaxFileSizeMB: t.logs.max_file_size
				}
			}

			if t.restart != null {
				RestartPolicy: {
					Interval: time.ParseDuration(t.restart.interval)
					Attempts: t.restart.attempts
					Delay:    time.ParseDuration(t.restart.delay)
					Mode:     t.restart.mode
				}
			}

			if t.lifecycle != null {
				Lifecycle: {
					Hook:    t.lifecycle.hook
					Sidecar: t.lifecycle.sidecar
				}
			}

			Resources: {
				CPU:      t.resources.cpu
				MemoryMB: t.resources.memory
			}

			Leader: t.leader

			Templates: [ for tplName, tpl in t.template {
				DestPath:     tplName
				EmbeddedTmpl: tpl.data
				SourcePath:   tpl.source
				Envvars:      tpl.env
				ChangeMode:   tpl.change_mode
				ChangeSignal: tpl.change_signal
				Perms:        tpl.perms
				LeftDelim:    tpl.left_delimiter
				RightDelim:   tpl.right_delimiter
			}]

			Artifacts: [ for artName, art in t.artifact {
				GetterHeaders: art.headers
				GetterMode:    art.mode
				GetterOptions: art.options
				GetterSource:  art.source
				RelativeDest:  artName
			}]

			if t.vault != null {
				Vault: {
					ChangeMode:   t.vault.change_mode
					ChangeSignal: t.vault.change_signal
					Env:          t.vault.env
					Namespace:    t.vault.namespace
					Policies:     t.vault.policies
				}
			}

			VolumeMounts: [ for volName, vol in t.volume_mount {
				Destination:     vol.destination
				PropagationMode: "private"
				ReadOnly:        vol.read_only
				Volume:          volName
			}]
		}]

		if tg.vault != null {
			Vault: {
				ChangeMode:   tg.vault.change_mode
				ChangeSignal: tg.vault.change_signal
				Env:          tg.vault.env
				Namespace:    tg.vault.namespace
				Policies:     tg.vault.policies
			}
		}

		for volName, vol in tg.volume {
			Volumes: "\(volName)": {
				Name:     volName
				Type:     vol.type
				Source:   vol.source
				ReadOnly: vol.read_only
				if vol.type == "csi" {
					MountOptions: {
						FsType:     vol.mount_options.fs_type
						mountFlags: vol.mount_options.mount_flags
					}
				}
			}
		}
	}]
}

// Definitions for stanzas referenced throughout this file
#stanza: {
	job: {
		datacenters: list.MinItems(1)
		namespace:   string
		type:        "batch" | *"service" | "system"
		affinities: [...#stanza.affinity]
		constraints: [...#stanza.constraint]
		spreads: [...#stanza.spread]
		group: [string]: #stanza.group & {#type: type}
		update:   #stanza.update | *null
		vault:    #stanza.vault | *null
		priority: uint | *50
		periodic: #stanza.periodic | *null
		migrate:  #stanza.migrate | *null
	}

	migrate: {
		health_check:     *"checks" | "task_states"
		healthy_deadline: uint | *500000000000
		max_parallel:     uint | *1
		min_healthy_time: uint | *10000000000
	}

	periodic: {
		time_zone:        string | *"UTC"
		prohibit_overlap: bool | *false
		cron:             string
	}

	affinity: {
		LTarget: string | *null
		RTarget: string
		Operand: "regexp" | "set_contains_all" | "set_contains" | "set_contains_any" | *"=" | "==" | "is" | "!=" | "not" | ">" | ">=" | "<" | "<=" | "version"
		Weight:  uint & !=0 & >=-100 & <=100
	}

	constraint: {
		attribute: string | *null
		value:     string
		operator:  *"=" | "!=" | ">" | ">=" | "<" | "<=" | "distinct_hosts" | "distinct_property" | "regexp" | "set_contains" | "version" | "semver" | "is_set" | "is_not_set"
	}

	spread: {
		attribute: string | *null
		weight:    uint & >=-100 & <=100 | *null
		target: [...#stanza.targetElem]
	}

	targetElem: {
		value:   string | *null
		percent: uint & >=0 & <=100 | *null
	}

	ephemeral_disk: *null | {
		size:    uint & >0
		migrate: bool | *false
		sticky:  bool | *false
	}

	group: {
		#type: "service" | "batch" | "system"
		affinities: [...#stanza.affinity]
		constraints: [...#stanza.constraint]
		spreads: [...#stanza.spread]
		ephemeral_disk: #stanza.ephemeral_disk
		network:        *null | #stanza.network
		service: [string]: #stanza.service
		task: [string]:    #stanza.task
		count: uint | *1
		volume: [string]: #stanza.volume
		vault:          *null | #stanza.vault
		restart:        *null | #stanza.restart
		restart_policy: *null | #stanza.restart
		reschedule:     #stanza.reschedule & {#type: #type}
	}

	reschedule: {
		#type: "batch" | *"service" | "system"

		if #type == "batch" {
			attempts:       uint | *1
			delay:          #duration | *"5s"
			delay_function: *"constant" | "exponential" | "fibonacci"
			interval:       #duration | *"24h"
			unlimited:      bool | *false
		}

		if #type == "service" || #type == "system" {
			interval:       #duration | *"0m"
			attempts:       uint | *0
			delay:          #duration | *"30s"
			delay_function: "constant" | *"exponential" | "fibonacci"
			max_delay:      #duration | *"1h"
			// if unlimited is true, interval and attempts are ignored
			unlimited: bool | *true
		}
	}

	network: {
		mode: "host" | "bridge"
		dns:  *null | {
			servers: [...string]
		}
		port: [string]: {
			static:       *null | uint
			to:           *null | uint
			host_network: *"" | string
		}
	}

	check_restart: *null | {
		limit:           uint
		grace:           #duration
		ignore_warnings: bool | *false
	}

	service: {
		check_restart: #stanza.check_restart | *null
		port:          string
		address_mode:  "alloc" | "driver" | *"auto" | "host"
		tags: [...string]
		task: string | *""
		check: [string]: #stanza.check
		meta: [string]:  string
		connect: #stanza.connect
	}

	expose: {
		path:            string
		protocol:        *"http" | "http2"
		listener_port:   string
		local_path_port: uint
	}

	upstreams: {
		datacenter:         *"" | string
		destination_name:   *"" | string
		local_bind_address: *"" | string
		local_bind_port:    uint
		mesh_gateway:       null
	}

	proxy: *null | {
		config:                *null | {[string]: string}
		expose:                *null | {path: [...#stanza.expose]}
		local_service_address: string | *"127.0.0.1"
		local_service_port:    uint | *0
		upstreams:             *null | [...#stanza.upstreams]
	}

	sidecar_service: *null | {
		disable_default_tcp_check: bool | *false
		port:                      *"" | string
		proxy:                     #stanza.proxy
		tags:                      null
	}

	sidecar_task: *null | {
		name:   *"" | string
		driver: *"" | "docker"
		user:   *"" | string
		config: *null | dockerConfig
		env: [string]: string
	}

	connect: *null | {
		gateway:         null
		native:          bool | *false
		sidecar_service: #stanza.sidecar_service
		sidecar_task:    #stanza.sidecar_task
	}

	check: {
		address_mode:  "alloc" | "driver" | *"host"
		type:          "http" | "tcp" | "script" | "grpc"
		command:       string | *""
		args:          [...string] | *null
		task:          string | *""
		expose:        bool | *false
		port:          string
		interval:      #duration
		timeout:       #duration
		check_restart: #stanza.check_restart | *null
		header: [string]: [...string]
		body:                     string | *null
		initial_status:           "passing" | "warning" | "critical" | *""
		success_before_passing:   uint | *0
		failures_before_critical: uint | *0
		tls_skip_verify:          bool | *false
		on_update:                *"" | "require_healthy" | "ignore_warnings" | "ignore"

		if type == "http" {
			method:   *"GET" | "POST"
			path:     string
			protocol: *"http" | "https"
		}

		if type != "http" {
			method:   ""
			path:     ""
			protocol: ""
		}
	}

	taskConfig: dockerConfig | execConfig

	execConfig: {
		flake:   string
		command: string
		args: [...string]
	}

	#label: [string]: string

	dockerMount: {
		type:     *"bind" | "volume" | "tmpfs"
		target:   string
		source:   string
		readonly: *true | bool
		bind_options: {
			propagation: "rshared"
		}
	}

	dockerConfig: {
		image:   *null | string
		command: *null | string
		args: [...string]
		cap_add:     *null | [...string]
		entrypoint:  *null | [...string]
		force_pull:  *null | bool
		interactive: *null | bool
		ipc_mode:    *null | string
		labels: [...#label]
		logging: dockerConfigLogging
		mount:   *null | [...#stanza.dockerMount]
		ports: [...string]
		sysctl: *null | [ {[string]: string}]
	}

	dockerConfigLogging: {
		type: "journald"
		config: [...dockerConfigLoggingConfig]
	}

	dockerConfigLoggingConfig: {
		tag:    string
		labels: string
	}

	lifecycle: {
		hook:    "prestart" | "poststart" | "poststop"
		sidecar: *null | bool
	}

	logs: {
		max_files:     uint & >0
		max_file_size: uint & >0
	}

	task: {
		affinities: [...#stanza.affinity]
		constraints: [...#stanza.constraint]

		artifact: [Destination=_]: {
			destination: Destination
			headers: [string]: string
			mode: *"any" | "file" | "dir"
			options: [string]: string
			source: string
		}

		if driver == "docker" {
			config: #stanza.dockerConfig
		}

		if driver == "exec" {
			config: #stanza.execConfig
		}

		driver: "exec" | "docker" | "nspawn"

		env: [string]: string

		kill_signal: string | *"SIGINT"
		if driver == "docker" {
			kill_signal: "SIGTERM"
		}

		kill_timeout: *null | #duration

		lifecycle: *null | #stanza.lifecycle

		logs: *null | #stanza.logs

		resources: {
			cpu:    uint & >=100
			memory: uint & >=32
		}

		template: [Destination=_]: {
			destination:     Destination
			data:            *"" | string
			source:          *"" | string
			env:             bool | *false
			change_mode:     *"restart" | "noop" | "signal"
			change_signal:   *"" | string
			perms:           *"0644" | =~"^[0-7]{4}$"
			left_delimiter:  string | *"{{"
			right_delimiter: string | *"}}"
			splay:           #duration | *"3s"
		}

		vault: *null | #stanza.vault
		volume_mount: [string]: #stanza.volume_mount
		restart:        *null | #stanza.restart
		restart_policy: *null | #stanza.restart
		leader:         bool | *false
	}

	restart: {
		interval: #duration
		attempts: uint
		delay:    #duration
		mode:     "delay" | "fail"
	}

	update: {
		auto_promote:      bool | *false
		auto_revert:       bool | *false
		canary:            uint | *0
		health_check:      *"checks" | "task_states" | "manual"
		healthy_deadline:  #duration | *"5m"
		max_parallel:      uint | *1
		min_healthy_time:  #duration | *"10s"
		progress_deadline: #duration | *"10m"
		stagger:           #duration | *"30s"
	}

	vault: {
		change_mode:   "noop" | *"restart" | "signal"
		change_signal: string | *""
		env:           bool | *true
		namespace:     string | *""
		policies: [...string]
	}

	volume: {
		type:      "host" | "csi"
		source:    string
		read_only: bool | *false
		if type == "csi" {
			mount_options: {
				fs_type:     *null | string
				mount_flags: *null | string
			}
		}
	}

	volume_mount: {
		// Specifies the group volume that the mount is going to access.
		volume: string | *""

		// Specifies where the volume should be mounted inside the task's
		// allocation.
		destination: string | *""

		// When a group volume is writeable, you may specify that it is read_only
		// on a per mount level using the read_only option here.
		read_only: bool | *false
	}
}
