use super::subs::SubCommands;
use crate::types::BitteProvider;
use clap::{ArgSettings, Parser};
use uuid::Uuid;

#[derive(Parser)]
#[clap(author, version, about)]
pub struct Bitte {
    #[clap(short, long, parse(from_occurrences), global = true, env = "RUST_LOG")]
    /// set log level: 'unset' is 'warn', '-v' is 'info', '-vv' is 'debug', ...
    verbose: i32,
    #[clap(subcommand)]
    commands: SubCommands,
}

#[derive(Parser, Default)]
pub struct Globals {
    #[clap(arg_enum, long, env = "BITTE_PROVIDER", ignore_case = true, value_parser = clap::value_parser!(BitteProvider))]
    /// The cluster infrastructure provider
    provider: BitteProvider,
    #[clap(long, env = "BITTE_DOMAIN", value_name = "NAME")]
    /// The public domain of the cluster
    domain: String,
    #[clap(long = "cluster", env = "BITTE_CLUSTER", value_name = "TITLE")]
    /// The unique name of the cluster
    name: String,
    #[clap(
        long,
        env = "AWS_DEFAULT_REGION",
        value_name = "REGION",
        required_if_eq("provider", "AWS")
    )]
    /// The default AWS region
    aws_region: Option<String>,
    #[clap(
        long,
        env = "AWS_ASG_REGIONS",
        value_name = "REGIONS",
        required_if_eq("provider", "AWS"),
        value_delimiter(':'),
        require_delimiter = true
    )]
    /// Regions containing Nomad clients
    aws_asg_regions: Option<Vec<String>>,
}

#[derive(Parser, Default)]
pub struct Nomad {
    #[clap(
        long,
        value_name = "TOKEN",
        env = "NOMAD_TOKEN",
        value_parser = clap::value_parser!(Uuid),
        setting = ArgSettings::HideEnvValues
    )]
    /// The Nomad token used to query node information
    nomad: Option<Uuid>,
}
