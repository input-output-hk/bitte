use crate::bitte::{BitteFind, ClusterHandle};
use crate::deploy_rs::cli as deployCli;
use crate::deploy_rs::cli::Opts as ExtDeployOpts;
use anyhow::Result;
use clap::{ArgMatches, FromArgMatches};
use log::{error, info};
use std::process::{Command, Stdio};

pub async fn deploy(sub: &ArgMatches, cluster: ClusterHandle) -> Result<()> {
    let opts = <super::Deploy as FromArgMatches>::from_arg_matches(sub).unwrap_or_default();
    let cluster = cluster.await??;
    let node_class = sub.get_one::<String>("class").cloned();

    info!("node needles: {:?}", opts.nodes);

    let instances = if opts.clients {
        cluster.nodes.find_clients(node_class)
    } else {
        cluster
            .nodes
            .find_needles(opts.nodes.iter().map(AsRef::as_ref).collect())
    };

    let nixos_configurations: Vec<String> = instances
        .iter()
        .map(|i| i.nixos.clone())
        .collect::<Vec<String>>();
    info!("regenerate secrets for: {:?}", nixos_configurations);

    for nixos_configuration in nixos_configurations {
        let output = Command::new("nix")
            .arg("run")
            .arg(format!(
                ".#nixosConfigurations.'{}'.config.secrets.generateScript",
                nixos_configuration
            ))
            .stderr(Stdio::piped())
            .stdout(Stdio::piped())
            .output()?;

        if !output.status.success() {
            error!(
                "Secret generation on {} failed with exit code {}",
                nixos_configuration,
                output.status.code().unwrap(),
            );
        }
    }

    let targets: Vec<String> = instances
        .iter()
        .map(|i| format!(".#{}@{}:22", i.nixos, i.pub_ip))
        .collect();

    info!("redeploy: {:?}", targets);
    // TODO: disable these options for the general public (target & targets)
    let opts = ExtDeployOpts {
        hostname: None,
        target: None,
        targets: Some(targets),
        flags: opts.flags,
        generic_settings: opts.generic_settings,
    };
    // wait_for_ssh(&instance.pub_ip).await?;
    if let Err(err) = deployCli::run(Some(opts)).await {
        error!("{}", err);
        // NB: if your up for a mass rebuild you are expected to:
        //   - Randomly check on a representative single node before
        //   - Eventually use the dry-run fearure
        //   - Watch the logs closely
        //   - Kill the deployment manually if things appear to go out
        //     of hand
        // std::process::exit(1);
    }
    Ok(())
}
