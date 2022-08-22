pub mod deploy;
pub mod info;
pub mod ssh;

pub use self::deploy::deploy;
pub use info::info;
pub use ssh::ssh;

use crate::cli::opts::{Globals, Nomad};
use crate::deploy_rs::data as deployData;
use crate::deploy_rs::settings as deploySettings;
use clap::Parser;
use clap_complete::Shell;

#[derive(Parser)]
pub enum SubCommands {
    Info(Info),
    Ssh(Ssh),
    Deploy(Deploy),
    Completions(Completions),
}

#[derive(Parser)]
/// Show information about instances and auto-scaling groups
pub struct Info {
    #[clap(flatten)]
    globals: Globals,
    #[clap(short, long)]
    /// output as JSON
    json: bool,
    #[clap(flatten)]
    nomad: Nomad,
}

#[derive(Parser, Default)]
/// Deploy core and client nodes
pub struct Deploy {
    #[clap(flatten)]
    globals: Globals,
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

    #[clap(flatten)]
    nomad: Nomad,

    #[clap(long, short = 'o',  requires_all = &["nomad", "clients"])]
    /// the Nomad node class to filter clients against
    class: Option<String>,
}
#[derive(Parser)]
/// Generate completions for the given shell
pub struct Completions {
    // Shell to generate completions for
    #[clap(long, value_enum, value_name = "SHELL", value_parser = clap::value_parser!(Shell))]
    shell: Shell,
}

#[derive(Parser)]
/// SSH to instances
pub struct Ssh {
    #[clap(flatten)]
    globals: Globals,
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
    #[clap(long, short, env = "NOMAD_NAMESPACE")]
    /// Nomad namespace to search for jobs with `-j`
    namespace: Option<String>,
    #[clap(flatten)]
    nomad: Nomad,
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
    #[clap(long, short = 'l', requires = "multi")]
    /// for '-a' or '-p': execute commands only on Nomad clients
    clients: bool,
    #[clap(long, short = 'o',  requires_all = &["nomad", "clients"])]
    /// the Nomad node class to filter clients against
    class: Option<String>,
    #[clap(long, short, requires = "all")]
    /// for '-a': seconds to delay between commands
    delay: Option<usize>,
    #[clap(multiple_values = true)]
    /// arguments to ssh
    args: Option<String>,
}
