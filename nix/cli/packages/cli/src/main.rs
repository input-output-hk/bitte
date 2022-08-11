mod cli;
mod types;
mod utils;

use anyhow::Result;
use clap::{App, IntoApp};
use cli::opts::Bitte;
use types::BitteCluster;
use uuid::Uuid;

#[tokio::main]
async fn main() -> Result<()> {
    let _toml = include_str!("../Cargo.toml");

    let app: App = <Bitte as IntoApp>::into_app();

    let matches = app.clone().get_matches();

    let run = |init_log: bool, token| {
        if init_log {
            cli::init_log(matches.occurrences_of("verbose"))
        };
        BitteCluster::init(matches.clone(), token)
    };

    match matches.subcommand() {
        Some(("deploy", sub)) => cli::deploy(sub, run(false, None)).await?,
        Some(("info", sub)) => cli::info(sub, run(true, None)).await?,
        Some(("ssh", sub)) => {
            let token: Option<Uuid> = if sub.is_present("job") {
                sub.value_of_t("nomad").ok()
            } else {
                None
            };
            cli::ssh(sub, run(true, token)).await?
        }
        Some(("completions", sub)) => cli::completions(sub, app).await?,
        _ => (),
    }
    Ok(())
}
