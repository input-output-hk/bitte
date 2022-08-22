pub mod opts;
pub mod subs;

use clap::App;
use clap_complete::{generate, Generator};
use std::env;

pub fn init_log(level: u64) {
    let level = match level {
        0 => "warn",
        1 => "info",
        2 => "debug",
        _ => "trace",
    };
    env::set_var("RUST_LOG", &level);
    pretty_env_logger::init()
}

pub(crate) async fn completions<G: Generator>(gen: G, mut app: App<'_>) {
    let cli = &mut app;
    generate(gen, cli, cli.get_name().to_string(), &mut std::io::stdout())
}
