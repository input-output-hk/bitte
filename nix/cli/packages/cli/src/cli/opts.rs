use super::subs::SubCommands;
use clap::Parser;

#[derive(Parser)]
#[clap(author, version, about)]
pub struct Bitte {
    #[clap(short, long, parse(from_occurrences), global = true, env = "RUST_LOG")]
    /// set log level: 'unset' is 'warn', '-v' is 'info', '-vv' is 'debug', ...
    verbose: i32,
    #[clap(subcommand)]
    commands: SubCommands,
}
