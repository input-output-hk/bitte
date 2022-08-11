use anyhow::{Context, Result};
use clap::{AppSettings, ArgSettings, Parser};
use deploy::data as deployData;
use deploy::settings as deploySettings;
use uuid::Uuid;

#[derive(Parser)]
pub enum SubCommands {
    Info(Info),
    Ssh(Ssh),
    Deploy(Deploy),
    #[clap(setting = AppSettings::Hidden)]
    Completions(Completions),
}

#[derive(Parser)]
/// Show information about instances and auto-scaling groups
pub struct Info {
    #[clap(short, long)]
    /// output as JSON
    json: bool,
}

#[derive(Parser, Default)]
/// Deploy core and client nodes
pub struct Deploy {
    #[clap(long, short = 'l')]
    /// (re-)deploy all client nodes
    pub clients: bool,
    #[clap(flatten)]
    pub flags: deployData::Flags,

    #[clap(flatten)]
    pub generic_settings: deploySettings::GenericSettings,
    /// nodes to deploy; takes one or more needles to match against:
    /// private & public ip, node name and aws client id
    pub nodes: Vec<String>,
}

#[derive(Parser)]
/// SSH to instances
pub struct Ssh {
    #[clap(
        short,
        long,
        requires_all = &["nomad", "namespace"],
        number_of_values = 3,
        value_names = &["JOB", "GROUP", "INDEX"],
    )]
    /// specify client by: job, group, alloc_index;
    /// this will also 'cd' to the alloc dir if <ARGS> is empty
    job: Option<String>,
    #[clap(
        long,
        value_name = "TOKEN",
        env = "NOMAD_TOKEN",
        parse(try_from_str = token_context),
        setting = ArgSettings::HideEnvValues
    )]
    /// for '-j': The Nomad token used to query node information
    nomad: Option<Uuid>,
    #[clap(
        long,
        short,
        group = "multi",
        conflicts_with = "job",
        requires = "args"
    )]
    /// run <ARGS> on all nodes
    all: bool,
    #[clap(
        long,
        short,
        group = "multi",
        conflicts_with_all = &["all", "job"],
        requires = "args"
    )]
    /// run <ARGS> on nodes in parallel
    parallel: bool,
    #[clap(long, short, env = "NOMAD_NAMESPACE")]
    /// for '-j': specify nomad namespace to search for <JOB>
    namespace: Option<String>,
    #[clap(long, short = 'l', requires = "multi")]
    /// for '-a' or '-p': execute commands only on Nomad clients
    clients: bool,
    #[clap(long, short, requires = "all")]
    /// for '-a': seconds to delay between commands
    delay: Option<usize>,
    #[clap(multiple_values = true)]
    /// arguments to ssh
    args: Option<String>,
}

#[derive(Parser)]
#[clap(alias = "comp")]
/// Generate CLI completions
pub struct Completions {
    #[clap(subcommand)]
    shells: Shells,
}

#[derive(Parser)]
pub enum Shells {
    Bash,
    Zsh,
    Fish,
}

fn token_context(string: &str) -> Result<Uuid> {
    Uuid::parse_str(string).with_context(|| format!("'{}' is not a valid UUID", string))
}
