use serde::{Deserialize, Serialize};
use std::collections::HashMap;

impl std::fmt::Display for Topic {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_fmt(format_args!("{:?}", self))
    }
}

impl std::fmt::Display for NomadEvent {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        if let Some(events) = &self.events {
            for event in events {
                formatter.write_fmt(format_args!("Topic: {}\n", event.topic))?;
                formatter.write_fmt(format_args!("  Namespace: {}\n", event.namespace))?;
                formatter.write_fmt(format_args!("  Key: {}\n", event.key))?;
                formatter.write_fmt(format_args!("  Type: {:?}\n", event.event_type))?;
                formatter.write_fmt(format_args!("  Payload: {}\n", event.payload))?;
            }
        }
        Ok(())
    }
}

impl std::fmt::Display for Payload {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        if let Some(allocation) = &self.allocation {
            formatter.write_fmt(format_args!("\n    JobID: {}\n", allocation.job_id))?;
        };
        if let Some(evaluation) = &self.evaluation {
            formatter.write_fmt(format_args!("\n    JobID: {}\n", evaluation.job_id))?;
        };
        if let Some(job) = &self.job {
            formatter.write_fmt(format_args!("\n    Name: {}\n", job.name))?;
        };
        if let Some(deployment) = &self.deployment {
            formatter.write_fmt(format_args!("\n    JobID: {}\n", deployment.job_id))?;
        };
        Ok(())
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct NomadEvent {
    #[serde(rename = "Index")]
    pub index: Option<i64>,
    #[serde(rename = "Events")]
    pub events: Option<Vec<EventsSortedEvent>>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EventsSortedEvent {
    #[serde(rename = "Topic")]
    pub topic: Topic,
    #[serde(rename = "Type")]
    pub event_type: NomadEventType,
    #[serde(rename = "Key")]
    pub key: String,
    #[serde(rename = "Namespace")]
    pub namespace: String,
    #[serde(rename = "FilterKeys")]
    pub filter_keys: Option<Vec<String>>,
    #[serde(rename = "Index")]
    pub index: i64,
    #[serde(rename = "Payload")]
    pub payload: Payload,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Payload {
    #[serde(rename = "Allocation")]
    pub allocation: Option<Allocation>,
    #[serde(rename = "Evaluation")]
    pub evaluation: Option<Evaluation>,
    #[serde(rename = "Job")]
    pub job: Option<Job>,
    #[serde(rename = "Deployment")]
    pub deployment: Option<Deployment>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Allocation {
    #[serde(rename = "ID")]
    pub id: String,
    #[serde(rename = "Namespace")]
    pub namespace: String,
    #[serde(rename = "EvalID")]
    pub eval_id: String,
    #[serde(rename = "Name")]
    pub name: String,
    #[serde(rename = "NodeID")]
    pub node_id: String,
    #[serde(rename = "NodeName")]
    pub node_name: String,
    #[serde(rename = "JobID")]
    pub job_id: String,
    #[serde(rename = "Job")]
    pub job: Option<serde_json::Value>,
    #[serde(rename = "TaskGroup")]
    pub task_group: String,
    #[serde(rename = "Resources")]
    pub resources: Resources,
    #[serde(rename = "SharedResources")]
    pub shared_resources: Resources,
    #[serde(rename = "TaskResources")]
    pub task_resources: TaskResources,
    #[serde(rename = "AllocatedResources")]
    pub allocated_resources: AllocatedResources,
    #[serde(rename = "Metrics")]
    pub metrics: Metrics,
    #[serde(rename = "DesiredStatus")]
    pub desired_status: DesiredStatus,
    #[serde(rename = "DesiredDescription")]
    pub desired_description: DesiredDescription,
    #[serde(rename = "DesiredTransition")]
    pub desired_transition: DesiredTransition,
    #[serde(rename = "ClientStatus")]
    pub client_status: Status,
    #[serde(rename = "ClientDescription")]
    pub client_description: ClientDescription,
    #[serde(rename = "TaskStates")]
    pub task_states: Option<HashMap<String, TaskState>>,
    #[serde(rename = "AllocStates")]
    pub alloc_states: Option<serde_json::Value>,
    #[serde(rename = "PreviousAllocation")]
    pub previous_allocation: String,
    #[serde(rename = "NextAllocation")]
    pub next_allocation: String,
    #[serde(rename = "DeploymentID")]
    pub deployment_id: String,
    #[serde(rename = "DeploymentStatus")]
    pub deployment_status: Option<DeploymentStatus>,
    #[serde(rename = "RescheduleTracker")]
    pub reschedule_tracker: Option<RescheduleTracker>,
    #[serde(rename = "NetworkStatus")]
    pub network_status: Option<NetworkStatus>,
    #[serde(rename = "FollowupEvalID")]
    pub followup_eval_id: String,
    #[serde(rename = "PreemptedAllocations")]
    pub preempted_allocations: Option<serde_json::Value>,
    #[serde(rename = "PreemptedByAllocation")]
    pub preempted_by_allocation: String,
    #[serde(rename = "CreateIndex")]
    pub create_index: i64,
    #[serde(rename = "ModifyIndex")]
    pub modify_index: i64,
    #[serde(rename = "AllocModifyIndex")]
    pub alloc_modify_index: i64,
    #[serde(rename = "CreateTime")]
    pub create_time: i64,
    #[serde(rename = "ModifyTime")]
    pub modify_time: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TaskState {
    #[serde(rename = "State")]
    pub state: String,
    #[serde(rename = "Failed")]
    pub failed: bool,
    #[serde(rename = "Restarts")]
    pub restarts: i64,
    #[serde(rename = "LastRestart")]
    pub last_restart: String,
    #[serde(rename = "StartedAt")]
    pub started_at: String,
    #[serde(rename = "FinishedAt")]
    pub finished_at: String,
    #[serde(rename = "Events")]
    pub events: Vec<Event>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AllocatedResources {
    #[serde(rename = "Tasks")]
    pub tasks: TaskResources,
    #[serde(rename = "TaskLifecycles")]
    pub task_lifecycles: TaskResources,
    #[serde(rename = "Shared")]
    pub shared: Shared,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Shared {
    #[serde(rename = "Networks")]
    pub networks: Vec<Network>,
    #[serde(rename = "DiskMB")]
    pub disk_mb: i64,
    #[serde(rename = "Ports")]
    pub ports: Option<Vec<Port>>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Network {
    #[serde(rename = "Mode")]
    pub mode: Mode,
    #[serde(rename = "Device")]
    pub device: String,
    #[serde(rename = "CIDR")]
    pub cidr: String,
    #[serde(rename = "IP")]
    pub ip: String,
    #[serde(rename = "MBits")]
    pub m_bits: i64,
    #[serde(rename = "DNS")]
    pub dns: Option<serde_json::Value>,
    #[serde(rename = "ReservedPorts")]
    pub reserved_ports: Option<serde_json::Value>,
    #[serde(rename = "DynamicPorts")]
    pub dynamic_ports: Vec<Port>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Port {
    #[serde(rename = "Label")]
    pub label: String,
    #[serde(rename = "Value")]
    pub value: i64,
    #[serde(rename = "To")]
    pub to: i64,
    #[serde(rename = "HostNetwork")]
    pub host_network: Option<String>,
    #[serde(rename = "HostIP")]
    pub host_ip: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Event {
    #[serde(rename = "Type")]
    pub event_type: String,
    #[serde(rename = "Time")]
    pub time: i64,
    #[serde(rename = "Message")]
    pub message: String,
    #[serde(rename = "DisplayMessage")]
    pub display_message: String,
    #[serde(rename = "Details")]
    pub details: Details,
    #[serde(rename = "FailsTask")]
    pub fails_task: bool,
    #[serde(rename = "RestartReason")]
    pub restart_reason: String,
    #[serde(rename = "SetupError")]
    pub setup_error: String,
    #[serde(rename = "DriverError")]
    pub driver_error: String,
    #[serde(rename = "ExitCode")]
    pub exit_code: i64,
    #[serde(rename = "Signal")]
    pub signal: i64,
    #[serde(rename = "KillTimeout")]
    pub kill_timeout: i64,
    #[serde(rename = "KillError")]
    pub kill_error: String,
    #[serde(rename = "KillReason")]
    pub kill_reason: String,
    #[serde(rename = "StartDelay")]
    pub start_delay: i64,
    #[serde(rename = "DownloadError")]
    pub download_error: String,
    #[serde(rename = "ValidationError")]
    pub validation_error: String,
    #[serde(rename = "DiskLimit")]
    pub disk_limit: i64,
    #[serde(rename = "FailedSibling")]
    pub failed_sibling: String,
    #[serde(rename = "VaultError")]
    pub vault_error: String,
    #[serde(rename = "TaskSignalReason")]
    pub task_signal_reason: String,
    #[serde(rename = "TaskSignal")]
    pub task_signal: String,
    #[serde(rename = "DriverMessage")]
    pub driver_message: String,
    #[serde(rename = "GenericSource")]
    pub generic_source: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Cpu {
    #[serde(rename = "CpuShares")]
    pub cpu_shares: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Memory {
    #[serde(rename = "MemoryMB")]
    pub memory_mb: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Details {
    pub exit_code: Option<String>,
    pub exit_message: Option<String>,
    pub failed_sibling: Option<String>,
    pub fails_task: Option<String>,
    pub image: Option<String>,
    pub kill_timeout: Option<String>,
    pub message: Option<String>,
    pub oom_killed: Option<String>,
    pub restart_reason: Option<String>,
    pub signal: Option<String>,
    pub start_delay: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct DeploymentStatus {
    #[serde(rename = "Healthy")]
    pub healthy: bool,
    #[serde(rename = "Timestamp")]
    pub timestamp: String,
    #[serde(rename = "Canary")]
    pub canary: bool,
    #[serde(rename = "ModifyIndex")]
    pub modify_index: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct DesiredTransition {
    #[serde(rename = "Migrate")]
    pub migrate: Option<serde_json::Value>,
    #[serde(rename = "Reschedule")]
    pub reschedule: Option<bool>,
    #[serde(rename = "ForceReschedule")]
    pub force_reschedule: Option<serde_json::Value>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Metrics {
    #[serde(rename = "NodesEvaluated")]
    pub nodes_evaluated: i64,
    #[serde(rename = "NodesFiltered")]
    pub nodes_filtered: i64,
    #[serde(rename = "NodesAvailable")]
    pub nodes_available: NodesAvailable,
    #[serde(rename = "ClassFiltered")]
    pub class_filtered: Option<serde_json::Value>,
    #[serde(rename = "ConstraintFiltered")]
    pub constraint_filtered: Option<serde_json::Value>,
    #[serde(rename = "NodesExhausted")]
    pub nodes_exhausted: i64,
    #[serde(rename = "ClassExhausted")]
    pub class_exhausted: Option<serde_json::Value>,
    #[serde(rename = "DimensionExhausted")]
    pub dimension_exhausted: Option<DimensionExhausted>,
    #[serde(rename = "QuotaExhausted")]
    pub quota_exhausted: Option<serde_json::Value>,
    #[serde(rename = "Scores")]
    pub scores: Option<serde_json::Value>,
    #[serde(rename = "ScoreMetaData")]
    pub score_meta_data: Vec<ScoreMetaDatum>,
    #[serde(rename = "AllocationTime")]
    pub allocation_time: i64,
    #[serde(rename = "CoalescedFailures")]
    pub coalesced_failures: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct DimensionExhausted {
    pub memory: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct NodesAvailable {
    #[serde(rename = "eu-central-1")]
    pub eu_central_1: i64,
    #[serde(rename = "us-east-2")]
    pub us_east_2: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ScoreMetaDatum {
    #[serde(rename = "NodeID")]
    pub node_id: String,
    #[serde(rename = "Scores")]
    pub scores: Scores,
    #[serde(rename = "NormScore")]
    pub norm_score: f64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Scores {
    pub binpack: f64,
    #[serde(rename = "job-anti-affinity")]
    pub job_anti_affinity: f64,
    #[serde(rename = "node-affinity")]
    pub node_affinity: i64,
    #[serde(rename = "node-reschedule-penalty")]
    pub node_reschedule_penalty: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct NetworkStatus {
    #[serde(rename = "InterfaceName")]
    pub interface_name: String,
    #[serde(rename = "Address")]
    pub address: String,
    #[serde(rename = "DNS")]
    pub dns: Option<Dns>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Dns {
    #[serde(rename = "Servers")]
    pub servers: Vec<Option<serde_json::Value>>,
    #[serde(rename = "Searches")]
    pub searches: Vec<Option<serde_json::Value>>,
    #[serde(rename = "Options")]
    pub options: Vec<Option<serde_json::Value>>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct RescheduleTracker {
    #[serde(rename = "Events")]
    pub events: Vec<RescheduleTrackerEvent>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct RescheduleTrackerEvent {
    #[serde(rename = "RescheduleTime")]
    pub reschedule_time: i64,
    #[serde(rename = "PrevAllocID")]
    pub prev_alloc_id: String,
    #[serde(rename = "PrevNodeID")]
    pub prev_node_id: String,
    #[serde(rename = "Delay")]
    pub delay: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Resources {
    #[serde(alias = "CPU", alias = "Cpu")]
    pub cpu: i64,
    #[serde(rename = "MemoryMB")]
    pub memory_mb: i64,
    #[serde(rename = "DiskMB")]
    pub disk_mb: i64,
    #[serde(rename = "IOPS")]
    pub iops: i64,
    #[serde(rename = "Networks")]
    pub networks: Option<Vec<Network>>,
    #[serde(rename = "Devices")]
    pub devices: Option<serde_json::Value>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TaskResources {
    #[serde(rename = "Cpu")]
    pub explorer_cpu: Option<Cpu>,
    #[serde(rename = "Memory")]
    pub memory: Option<Memory>,
    #[serde(rename = "Networks")]
    pub networks: Option<serde_json::Value>,
    #[serde(rename = "Devices")]
    pub devices: Option<serde_json::Value>,
    #[serde(rename = "CPU")]
    pub cpu: Option<i64>,
    #[serde(rename = "MemoryMB")]
    pub memory_mb: Option<i64>,
    #[serde(rename = "DiskMB")]
    pub disk_mb: Option<i64>,
    #[serde(rename = "IOPS")]
    pub iops: Option<i64>,
    #[serde(rename = "State")]
    pub state: Option<Stat>,
    #[serde(rename = "Failed")]
    pub failed: Option<bool>,
    #[serde(rename = "Restarts")]
    pub restarts: Option<i64>,
    #[serde(rename = "LastRestart")]
    pub last_restart: Option<String>,
    #[serde(rename = "StartedAt")]
    pub started_at: Option<String>,
    #[serde(rename = "FinishedAt")]
    pub finished_at: Option<String>,
    #[serde(rename = "Events")]
    pub events: Option<Vec<Event>>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Deployment {
    #[serde(rename = "ID")]
    pub id: String,
    #[serde(rename = "Namespace")]
    pub namespace: String,
    #[serde(rename = "JobID")]
    pub job_id: String,
    #[serde(rename = "JobVersion")]
    pub job_version: i64,
    #[serde(rename = "JobModifyIndex")]
    pub job_modify_index: i64,
    #[serde(rename = "JobSpecModifyIndex")]
    pub job_spec_modify_index: i64,
    #[serde(rename = "JobCreateIndex")]
    pub job_create_index: i64,
    #[serde(rename = "IsMultiregion")]
    pub is_multiregion: bool,
    #[serde(rename = "TaskGroups")]
    pub task_groups: TaskGroups,
    #[serde(rename = "Status")]
    pub status: DeploymentStatusEnum,
    #[serde(rename = "StatusDescription")]
    pub status_description: DeploymentStatusDescription,
    #[serde(rename = "CreateIndex")]
    pub create_index: i64,
    #[serde(rename = "ModifyIndex")]
    pub modify_index: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TaskGroups {
    pub mantis: Option<MantisClass>,
    pub explorer: Option<MantisClass>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct MantisClass {
    #[serde(rename = "AutoRevert")]
    pub auto_revert: bool,
    #[serde(rename = "AutoPromote")]
    pub auto_promote: bool,
    #[serde(rename = "ProgressDeadline")]
    pub progress_deadline: i64,
    #[serde(rename = "RequireProgressBy")]
    pub require_progress_by: String,
    #[serde(rename = "Promoted")]
    pub promoted: bool,
    #[serde(rename = "PlacedCanaries")]
    pub placed_canaries: Option<serde_json::Value>,
    #[serde(rename = "DesiredCanaries")]
    pub desired_canaries: i64,
    #[serde(rename = "DesiredTotal")]
    pub desired_total: i64,
    #[serde(rename = "PlacedAllocs")]
    pub placed_allocs: i64,
    #[serde(rename = "HealthyAllocs")]
    pub healthy_allocs: i64,
    #[serde(rename = "UnhealthyAllocs")]
    pub unhealthy_allocs: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Evaluation {
    #[serde(rename = "ID")]
    pub id: String,
    #[serde(rename = "Namespace")]
    pub namespace: String,
    #[serde(rename = "Priority")]
    pub priority: i64,
    #[serde(rename = "Type")]
    pub evaluation_type: EvaluationType,
    #[serde(rename = "TriggeredBy")]
    pub triggered_by: TriggeredBy,
    #[serde(rename = "JobID")]
    pub job_id: String,
    #[serde(rename = "JobModifyIndex")]
    pub job_modify_index: i64,
    #[serde(rename = "NodeID")]
    pub node_id: String,
    #[serde(rename = "NodeModifyIndex")]
    pub node_modify_index: i64,
    #[serde(rename = "DeploymentID")]
    pub deployment_id: String,
    #[serde(rename = "Status")]
    pub status: Status,
    #[serde(rename = "StatusDescription")]
    pub status_description: EvaluationStatusDescription,
    #[serde(rename = "Wait")]
    pub wait: i64,
    #[serde(rename = "WaitUntil")]
    pub wait_until: String,
    #[serde(rename = "NextEval")]
    pub next_eval: String,
    #[serde(rename = "PreviousEval")]
    pub previous_eval: String,
    #[serde(rename = "BlockedEval")]
    pub blocked_eval: String,
    #[serde(rename = "FailedTGAllocs")]
    pub failed_tg_allocs: Option<serde_json::Value>,
    #[serde(rename = "ClassEligibility")]
    pub class_eligibility: Option<serde_json::Value>,
    #[serde(rename = "QuotaLimitReached")]
    pub quota_limit_reached: String,
    #[serde(rename = "EscapedComputedClass")]
    pub escaped_computed_class: bool,
    #[serde(rename = "AnnotatePlan")]
    pub annotate_plan: bool,
    #[serde(rename = "QueuedAllocations")]
    pub queued_allocations: Option<QueuedAllocations>,
    #[serde(rename = "LeaderACL")]
    pub leader_acl: String,
    #[serde(rename = "SnapshotIndex")]
    pub snapshot_index: i64,
    #[serde(rename = "CreateIndex")]
    pub create_index: i64,
    #[serde(rename = "ModifyIndex")]
    pub modify_index: i64,
    #[serde(rename = "CreateTime")]
    pub create_time: i64,
    #[serde(rename = "ModifyTime")]
    pub modify_time: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct QueuedAllocations {
    pub mantis: Option<i64>,
    pub explorer: Option<i64>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Job {
    #[serde(rename = "Stop")]
    pub stop: bool,
    #[serde(rename = "Region")]
    pub region: String,
    #[serde(rename = "Namespace")]
    pub namespace: String,
    #[serde(rename = "ID")]
    pub id: String,
    #[serde(rename = "ParentID")]
    pub parent_id: String,
    #[serde(rename = "Name")]
    pub name: String,
    #[serde(rename = "Type")]
    pub job_type: EvaluationType,
    #[serde(rename = "Priority")]
    pub priority: i64,
    #[serde(rename = "AllAtOnce")]
    pub all_at_once: bool,
    #[serde(rename = "Datacenters")]
    pub datacenters: Vec<String>,
    #[serde(rename = "Affinities")]
    pub affinities: Option<Vec<Option<serde_json::Value>>>,
    #[serde(rename = "Constraints")]
    pub constraints: Option<Vec<Option<serde_json::Value>>>,
    #[serde(rename = "Spreads")]
    pub spreads: Option<Vec<Option<serde_json::Value>>>,
    #[serde(rename = "TaskGroups")]
    pub task_groups: Vec<TaskGroup>,
    #[serde(rename = "Update")]
    pub update: Update,
    #[serde(rename = "Multiregion")]
    pub multiregion: Option<serde_json::Value>,
    #[serde(rename = "Periodic")]
    pub periodic: Option<Periodic>,
    #[serde(rename = "ParameterizedJob")]
    pub parameterized_job: Option<serde_json::Value>,
    #[serde(rename = "Dispatched")]
    pub dispatched: bool,
    #[serde(rename = "Payload")]
    pub payload: Option<serde_json::Value>,
    #[serde(rename = "Meta")]
    pub meta: Option<HashMap<String, String>>,
    #[serde(rename = "ConsulToken")]
    pub consul_token: String,
    #[serde(rename = "VaultToken")]
    pub vault_token: String,
    #[serde(rename = "VaultNamespace")]
    pub vault_namespace: String,
    #[serde(rename = "NomadTokenID")]
    pub nomad_token_id: String,
    #[serde(rename = "Status")]
    pub status: Stat,
    #[serde(rename = "StatusDescription")]
    pub status_description: String,
    #[serde(rename = "Stable")]
    pub stable: bool,
    #[serde(rename = "Version")]
    pub version: i64,
    #[serde(rename = "SubmitTime")]
    pub submit_time: i64,
    #[serde(rename = "CreateIndex")]
    pub create_index: i64,
    #[serde(rename = "ModifyIndex")]
    pub modify_index: i64,
    #[serde(rename = "JobModifyIndex")]
    pub job_modify_index: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TaskGroup {
    #[serde(rename = "Name")]
    pub name: String,
    #[serde(rename = "Count")]
    pub count: i64,
    #[serde(rename = "Update")]
    pub update: Update,
    #[serde(rename = "Migrate")]
    pub migrate: Migrate,
    #[serde(rename = "Affinities")]
    pub affinities: Option<Vec<Option<serde_json::Value>>>,
    #[serde(rename = "Constraints")]
    pub constraints: Option<Vec<Option<serde_json::Value>>>,
    #[serde(rename = "Spreads")]
    pub spreads: Option<Vec<Option<serde_json::Value>>>,
    #[serde(rename = "Scaling")]
    pub scaling: Option<serde_json::Value>,
    #[serde(rename = "RestartPolicy")]
    pub restart_policy: RestartPolicy,
    #[serde(rename = "Tasks")]
    pub tasks: Vec<TaskElement>,
    #[serde(rename = "EphemeralDisk")]
    pub ephemeral_disk: EphemeralDisk,
    #[serde(rename = "Meta")]
    pub meta: Option<HashMap<String, String>>,
    #[serde(rename = "ReschedulePolicy")]
    pub reschedule_policy: ReschedulePolicy,
    #[serde(rename = "Networks")]
    pub networks: Vec<Network>,
    #[serde(rename = "Services")]
    pub services: Vec<Service>,
    #[serde(rename = "Volumes")]
    pub volumes: Option<serde_json::Value>,
    #[serde(rename = "ShutdownDelay")]
    pub shutdown_delay: i64,
    #[serde(rename = "StopAfterClientDisconnect")]
    pub stop_after_client_disconnect: Option<serde_json::Value>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Constraint {
    #[serde(rename = "LTarget")]
    pub l_target: String,
    #[serde(rename = "RTarget")]
    pub r_target: String,
    #[serde(rename = "Operand")]
    pub operand: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EphemeralDisk {
    #[serde(rename = "Sticky")]
    pub sticky: bool,
    #[serde(rename = "SizeMB")]
    pub size_mb: i64,
    #[serde(rename = "Migrate")]
    pub migrate: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Migrate {
    #[serde(rename = "MaxParallel")]
    pub max_parallel: i64,
    #[serde(rename = "HealthCheck")]
    pub health_check: HealthCheck,
    #[serde(rename = "MinHealthyTime")]
    pub min_healthy_time: i64,
    #[serde(rename = "HealthyDeadline")]
    pub healthy_deadline: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ReschedulePolicy {
    #[serde(rename = "Attempts")]
    pub attempts: i64,
    #[serde(rename = "Interval")]
    pub interval: i64,
    #[serde(rename = "Delay")]
    pub delay: i64,
    #[serde(rename = "DelayFunction")]
    pub delay_function: DelayFunction,
    #[serde(rename = "MaxDelay")]
    pub max_delay: i64,
    #[serde(rename = "Unlimited")]
    pub unlimited: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct RestartPolicy {
    #[serde(rename = "Attempts")]
    pub attempts: i64,
    #[serde(rename = "Interval")]
    pub interval: i64,
    #[serde(rename = "Delay")]
    pub delay: i64,
    #[serde(rename = "Mode")]
    pub mode: RestartPolicyMode,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Service {
    #[serde(rename = "Name")]
    pub name: String,
    #[serde(rename = "TaskName")]
    pub task_name: String,
    #[serde(rename = "PortLabel")]
    pub port_label: String,
    #[serde(rename = "AddressMode")]
    pub address_mode: AddressMode,
    #[serde(rename = "EnableTagOverride")]
    pub enable_tag_override: bool,
    #[serde(rename = "Tags")]
    pub tags: Vec<String>,
    #[serde(rename = "CanaryTags")]
    pub canary_tags: Option<Vec<String>>,
    #[serde(rename = "Checks")]
    pub checks: Option<Vec<Check>>,
    #[serde(rename = "Connect")]
    pub connect: Option<serde_json::Value>,
    #[serde(rename = "Meta")]
    pub meta: Option<HashMap<String, String>>,
    #[serde(rename = "CanaryMeta")]
    pub canary_meta: Option<HashMap<String, String>>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Check {
    #[serde(rename = "Name")]
    pub name: String,
    #[serde(rename = "Type")]
    pub check_type: Type,
    #[serde(rename = "Command")]
    pub command: String,
    #[serde(rename = "Args")]
    pub args: Option<Vec<String>>,
    #[serde(rename = "Path")]
    pub path: String,
    #[serde(rename = "Protocol")]
    pub protocol: String,
    #[serde(rename = "PortLabel")]
    pub port_label: String,
    #[serde(rename = "Expose")]
    pub expose: bool,
    #[serde(rename = "AddressMode")]
    pub address_mode: Mode,
    #[serde(rename = "Interval")]
    pub interval: i64,
    #[serde(rename = "Timeout")]
    pub timeout: i64,
    #[serde(rename = "InitialStatus")]
    pub initial_status: String,
    #[serde(rename = "TLSSkipVerify")]
    pub tls_skip_verify: bool,
    #[serde(rename = "Method")]
    pub method: String,
    #[serde(rename = "Header")]
    pub header: Option<serde_json::Value>,
    #[serde(rename = "CheckRestart")]
    pub check_restart: CheckRestart,
    #[serde(rename = "GRPCService")]
    pub grpc_service: String,
    #[serde(rename = "GRPCUseTLS")]
    pub grpc_use_tls: bool,
    #[serde(rename = "TaskName")]
    pub task_name: String,
    #[serde(rename = "SuccessBeforePassing")]
    pub success_before_passing: i64,
    #[serde(rename = "FailuresBeforeCritical")]
    pub failures_before_critical: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CheckRestart {
    #[serde(rename = "Limit")]
    pub limit: i64,
    #[serde(rename = "Grace")]
    pub grace: i64,
    #[serde(rename = "IgnoreWarnings")]
    pub ignore_warnings: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Periodic {
    #[serde(rename = "Enabled")]
    pub enabled: bool,
    #[serde(rename = "TimeZone")]
    pub time_zone: String,
    #[serde(rename = "SpecType")]
    pub spec_type: String,
    #[serde(rename = "Spec")]
    pub spec: String,
    #[serde(rename = "ProhibitOverlap")]
    pub prohibit_overlap: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TaskElement {
    #[serde(rename = "Name")]
    pub name: String,
    #[serde(rename = "Driver")]
    pub driver: Driver,
    #[serde(rename = "User")]
    pub user: String,
    #[serde(rename = "Config")]
    pub config: Config,
    #[serde(rename = "Env")]
    pub env: Option<HashMap<String, String>>,
    #[serde(rename = "Services")]
    pub services: Option<serde_json::Value>,
    #[serde(rename = "Vault")]
    pub vault: Option<Vault>,
    #[serde(rename = "Templates")]
    pub templates: Vec<Template>,
    #[serde(rename = "Affinities")]
    pub affinities: Option<Vec<Option<serde_json::Value>>>,
    #[serde(rename = "Constraints")]
    pub constraints: Option<Vec<Option<serde_json::Value>>>,
    #[serde(rename = "Resources")]
    pub resources: Resources,
    #[serde(rename = "RestartPolicy")]
    pub restart_policy: RestartPolicy,
    #[serde(rename = "DispatchPayload")]
    pub dispatch_payload: Option<serde_json::Value>,
    #[serde(rename = "Lifecycle")]
    pub lifecycle: Option<serde_json::Value>,
    #[serde(rename = "Meta")]
    pub meta: Option<serde_json::Value>,
    #[serde(rename = "KillTimeout")]
    pub kill_timeout: i64,
    #[serde(rename = "LogConfig")]
    pub log_config: LogConfig,
    #[serde(rename = "Artifacts")]
    pub artifacts: Option<serde_json::Value>,
    #[serde(rename = "Leader")]
    pub leader: bool,
    #[serde(rename = "ShutdownDelay")]
    pub shutdown_delay: i64,
    #[serde(rename = "VolumeMounts")]
    pub volume_mounts: Option<serde_json::Value>,
    #[serde(rename = "ScalingPolicies")]
    pub scaling_policies: Option<serde_json::Value>,
    #[serde(rename = "KillSignal")]
    pub kill_signal: String,
    #[serde(rename = "Kind")]
    pub kind: String,
    #[serde(rename = "CSIPluginConfig")]
    pub csi_plugin_config: Option<serde_json::Value>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Config {
    pub args: Option<Vec<String>>,
    pub command: Option<String>,
    pub flake: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LogConfig {
    #[serde(rename = "MaxFiles")]
    pub max_files: i64,
    #[serde(rename = "MaxFileSizeMB")]
    pub max_file_size_mb: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Template {
    #[serde(rename = "SourcePath")]
    pub source_path: String,
    #[serde(rename = "DestPath")]
    pub dest_path: String,
    #[serde(rename = "EmbeddedTmpl")]
    pub embedded_tmpl: String,
    #[serde(rename = "ChangeMode")]
    pub change_mode: ChangeMode,
    #[serde(rename = "ChangeSignal")]
    pub change_signal: String,
    #[serde(rename = "Splay")]
    pub splay: i64,
    #[serde(rename = "Perms")]
    pub perms: String,
    #[serde(rename = "LeftDelim")]
    pub left_delim: String,
    #[serde(rename = "RightDelim")]
    pub right_delim: String,
    #[serde(rename = "Envvars")]
    pub envvars: bool,
    #[serde(rename = "VaultGrace")]
    pub vault_grace: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Vault {
    #[serde(rename = "Policies")]
    pub policies: Vec<String>,
    #[serde(rename = "Namespace")]
    pub namespace: String,
    #[serde(rename = "Env")]
    pub env: bool,
    #[serde(rename = "ChangeMode")]
    pub change_mode: ChangeMode,
    #[serde(rename = "ChangeSignal")]
    pub change_signal: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Update {
    #[serde(rename = "Stagger")]
    pub stagger: i64,
    #[serde(rename = "MaxParallel")]
    pub max_parallel: i64,
    #[serde(rename = "HealthCheck")]
    pub health_check: HealthCheck,
    #[serde(rename = "MinHealthyTime")]
    pub min_healthy_time: i64,
    #[serde(rename = "HealthyDeadline")]
    pub healthy_deadline: i64,
    #[serde(rename = "ProgressDeadline")]
    pub progress_deadline: i64,
    #[serde(rename = "AutoRevert")]
    pub auto_revert: bool,
    #[serde(rename = "AutoPromote")]
    pub auto_promote: bool,
    #[serde(rename = "Canary")]
    pub canary: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum NomadEventType {
    AllocationUpdateDesiredStatus,
    AllocationUpdated,
    DeploymentStatusUpdate,
    EvaluationUpdated,
    JobRegistered,
    PlanResult,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum Mode {
    #[serde(rename = "bridge")]
    Bridge,
    #[serde(rename = "host")]
    Host,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum Stat {
    #[serde(rename = "dead")]
    Dead,
    #[serde(rename = "pending")]
    Pending,
    #[serde(rename = "running")]
    Running,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum ClientDescription {
    #[serde(rename = "All tasks have completed")]
    AllTasksHaveCompleted,
    #[serde(rename = "")]
    Empty,
    #[serde(rename = "Failed tasks")]
    FailedTasks,
    #[serde(rename = "No tasks have started")]
    NoTasksHaveStarted,
    #[serde(rename = "Tasks are running")]
    TasksAreRunning,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum Status {
    #[serde(rename = "complete")]
    Complete,
    #[serde(rename = "failed")]
    Failed,
    #[serde(rename = "pending")]
    Pending,
    #[serde(rename = "running")]
    Running,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum DesiredDescription {
    #[serde(rename = "alloc is being updated due to job update")]
    AllocIsBeingUpdatedDueToJobUpdate,
    #[serde(rename = "alloc is lost since its node is down")]
    AllocIsLostSinceItsNodeIsDown,
    #[serde(rename = "alloc not needed due to job update")]
    AllocNotNeededDueToJobUpdate,
    #[serde(rename = "alloc was rescheduled because it failed")]
    AllocWasRescheduledBecauseItFailed,
    #[serde(rename = "")]
    Empty,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum DesiredStatus {
    #[serde(rename = "run")]
    Run,
    #[serde(rename = "stop")]
    Stop,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum DeploymentStatusEnum {
    #[serde(rename = "failed")]
    Failed,
    #[serde(rename = "running")]
    Running,
    #[serde(rename = "successful")]
    Successful,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum DeploymentStatusDescription {
    #[serde(rename = "Deployment completed successfully")]
    DeploymentCompletedSuccessfully,
    #[serde(rename = "Deployment is running")]
    DeploymentIsRunning,
    #[serde(rename = "Failed due to progress deadline")]
    FailedDueToProgressDeadline,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum EvaluationType {
    #[serde(rename = "service")]
    Service,
    #[serde(rename = "batch")]
    Batch,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum EvaluationStatusDescription {
    #[serde(rename = "created for delayed rescheduling")]
    CreatedForDelayedRescheduling,
    #[serde(rename = "")]
    Empty,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum TriggeredBy {
    #[serde(rename = "alloc-failure")]
    AllocFailure,
    #[serde(rename = "deployment-watcher")]
    DeploymentWatcher,
    #[serde(rename = "job-register")]
    JobRegister,
    #[serde(rename = "node-update")]
    NodeUpdate,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum HealthCheck {
    #[serde(rename = "checks")]
    Checks,
    #[serde(rename = "")]
    Empty,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum DelayFunction {
    #[serde(rename = "exponential")]
    Exponential,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum RestartPolicyMode {
    #[serde(rename = "fail")]
    Fail,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum AddressMode {
    #[serde(rename = "auto")]
    Auto,
    #[serde(rename = "host")]
    Host,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum Type {
    #[serde(rename = "http")]
    Http,
    #[serde(rename = "tcp")]
    Tcp,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum Driver {
    #[serde(rename = "exec")]
    Exec,
    #[serde(rename = "docker")]
    Docker,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum ChangeMode {
    #[serde(rename = "noop")]
    Noop,
    #[serde(rename = "signal")]
    Signal,
    #[serde(rename = "restart")]
    Restart,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum Topic {
    Allocation,
    Deployment,
    Evaluation,
    Job,
}
