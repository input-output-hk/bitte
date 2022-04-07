use super::subs::SubCommands;
use crate::types::BitteProvider;
use clap::Parser;

#[derive(Parser)]
#[clap(author, version, about)]
pub struct Bitte {
    #[clap(arg_enum, long, env = "BITTE_PROVIDER", ignore_case = true)]
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
    #[clap(short, long, parse(from_occurrences), global = true, env = "RUST_LOG")]
    /// set log level: 'unset' is 'warn', '-v' is 'info', '-vv' is 'debug', ...
    verbose: i32,
    #[clap(subcommand)]
    commands: SubCommands,
}
