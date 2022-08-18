mod bitte;
mod cli;
mod nomad;

use anyhow::Result;
use bitte::BitteCluster;
use clap::{App, ArgMatches, IntoApp};
use clap_complete::Shell;
use cli::opts::Bitte;
use cli::subs;
use uuid::Uuid;

use deploy as deploy_rs;

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
        Some(("deploy", sub)) => subs::deploy(sub, run(sub, false)).await?,
        Some(("info", sub)) => subs::info(sub, run(sub, true)).await?,
        Some(("ssh", sub)) => subs::ssh(sub, run(sub, true)).await?,
        Some(("completions", sub)) => {
            if let Some(shell) = sub.get_one::<Shell>("shell").copied() {
                cli::completions(shell, app).await;
            }
        }

        _ => (),
    }

    Ok(())
}
