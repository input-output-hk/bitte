mod cli;
mod types;
mod utils;

use anyhow::Result;
use clap::{App, ArgMatches, IntoApp};
use clap_complete::Shell;
use cli::opts::Bitte;
use types::BitteCluster;
use uuid::Uuid;

#[tokio::main]
async fn main() -> Result<()> {
    let _toml = include_str!("../Cargo.toml");

    let app: App = <Bitte as IntoApp>::into_app();

    let matches = app.clone().get_matches();

    let run = |sub: &ArgMatches, init_log: bool| {
        if init_log {
            cli::init_log(matches.occurrences_of("verbose"))
        };
        let token = sub.get_one::<Uuid>("nomad").copied();
        BitteCluster::init(sub.clone(), token)
    };

    match matches.subcommand() {
        Some(("deploy", sub)) => cli::deploy(sub, run(sub, false)).await?,
        Some(("info", sub)) => cli::info(sub, run(sub, true)).await?,
        Some(("ssh", sub)) => cli::ssh(sub, run(sub, true)).await?,
        Some(("completions", sub)) => {
            if let Some(shell) = sub.get_one::<Shell>("shell").copied() {
                cli::completions(shell, app).await;
            }
        }

        _ => (),
    }

    Ok(())
}
