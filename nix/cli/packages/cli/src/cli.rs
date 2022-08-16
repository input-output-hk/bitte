pub mod opts;
pub mod subs;

use crate::types::{BitteFind, ClusterHandle};
use anyhow::{anyhow, Context, Result};
use clap::{App, ArgMatches, FromArgMatches};
use clap_complete::{generate, Generator};
use deploy::cli as deployCli;
use deploy::cli::Opts as ExtDeployOpts;
use log::*;
use prettytable::{cell, format, row, Table};
use std::collections::HashMap;
use std::net::IpAddr;
use std::{env, io, path::Path, process::Command, process::Stdio, time::Duration};
use tokio::task::JoinHandle;

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

pub(crate) async fn ssh(sub: &ArgMatches, cluster: ClusterHandle) -> Result<()> {
    let mut args: Vec<String> = sub.get_many("args").unwrap_or_default().cloned().collect();
    let job: Vec<String> = sub.get_many("job").unwrap_or_default().cloned().collect();
    let delay = Duration::from_secs(*sub.get_one::<u64>("delay").unwrap_or(&0));

    let namespace = sub
        .get_one::<String>("namespace")
        .unwrap_or(&"default".to_string())
        .to_owned();

    let ip: IpAddr;

    let cluster = cluster.await??;

    if sub.is_present("all") {
        let nodes = if sub.is_present("clients") {
            cluster.nodes.find_clients()
        } else {
            cluster.nodes
        };

        let mut iter = nodes.iter().peekable();

        while let Some(node) = iter.next() {
            init_ssh(node.pub_ip, args.clone(), cluster.name.clone()).await?;
            if sub.is_present("delay") && iter.peek().is_some() {
                tokio::time::sleep(delay).await;
            }
        }

        return Ok(());
    } else if sub.is_present("parallel") {
        let nodes = if sub.is_present("clients") {
            cluster.nodes.find_clients()
        } else {
            cluster.nodes
        };

        let mut handles: Vec<JoinHandle<Result<()>>> = Vec::with_capacity(nodes.len());

        for node in nodes.into_iter() {
            let args = args.clone();
            let name = cluster.name.clone();
            let handle = tokio::spawn(async move { init_ssh(node.pub_ip, args, name).await });
            handles.push(handle);
        }

        for handle in handles.into_iter() {
            handle.await??;
        }

        return Ok(());
    } else if sub.is_present("job") {
        let (name, group, index) = (&job[0], &job[1], &job[2]);

        let nodes = cluster.nodes;
        let (node, alloc) = nodes.find_with_job(name, group, index, &namespace.clone())?;
        ip = node.pub_ip;
        if args.is_empty() {
            args.extend(vec![
                "-t".into(),
                format!("cd /var/lib/nomad/alloc/{} && exec $SHELL", alloc.id),
            ]);
        };
    } else {
        let needle = args.first();

        if needle.is_none() {
            return Err(anyhow!("first arg must be a host"));
        }

        let needle = needle.unwrap().clone();
        args = args.drain(1..).collect();

        let nodes = cluster.nodes;
        let node = nodes.find_needle(&needle)?;

        ip = node.pub_ip;
    };

    init_ssh(ip, args, cluster.name).await
}

async fn init_ssh(ip: IpAddr, args: Vec<String>, cluster: String) -> Result<()> {
    let user_host = &*format!("root@{}", ip);
    let mut flags = vec!["-x", "-p", "22"];

    let ssh_key_path = format!("secrets/ssh-{}", cluster);
    let ssh_key = Path::new(&ssh_key_path);
    if ssh_key.is_file() {
        flags.push("-i");
        flags.push(&*ssh_key_path);
    }

    flags.append(&mut vec!["-o", "StrictHostKeyChecking=accept-new"]);

    flags.push(user_host);

    if !args.is_empty() {
        flags.append(&mut args.iter().map(AsRef::as_ref).collect())
    };

    let ssh_args = flags.into_iter();

    let mut cmd = Command::new("ssh");
    let cmd_with_args = cmd.args(ssh_args);
    info!("cmd: {:?}", cmd_with_args);

    cmd.spawn()
        .with_context(|| "ssh command failed")?
        .wait()
        .with_context(|| "ssh command didn't finish?")?;
    Ok(())
}

pub(crate) async fn deploy(sub: &ArgMatches, cluster: ClusterHandle) -> Result<()> {
    let opts = <subs::Deploy as FromArgMatches>::from_arg_matches(sub).unwrap_or_default();
    let cluster = cluster.await??;

    info!("node needles: {:?}", opts.nodes);

    let instances = if opts.clients {
        cluster.nodes.find_clients()
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

pub(crate) async fn info(sub: &ArgMatches, cluster: ClusterHandle) -> Result<()> {
    let json: bool = sub.is_present("json");
    info_print(cluster, json).await?;
    Ok(())
}

async fn info_print(cluster: ClusterHandle, json: bool) -> Result<()> {
    let cluster = cluster.await??;
    if json {
        let stdout = io::stdout();
        let handle = stdout.lock();
        env::set_var("BITTE_INFO_NO_ALLOCS", "");
        serde_json::to_writer_pretty(handle, &cluster)?;
    } else {
        let mut core_nodes_table = Table::new();
        core_nodes_table.set_format(*format::consts::FORMAT_BOX_CHARS);
        core_nodes_table
            .add_row(row![ bc => format!("{} Core Instance", cluster.provider), "Private IP", "Public IP", "Zone"]);

        let mut client_nodes_table_map: HashMap<String, Table> = HashMap::new();

        let mut nodes = cluster.nodes;
        nodes.sort();

        for node in nodes.into_iter() {
            match node.asg {
                Some(asg) => {
                    let name: String = asg.to_string();
                    // TODO extract true client group
                    let group: String = {
                        let suffix = name.split('-').last().unwrap_or_default().to_owned();
                        let i_type = node
                            .node_type
                            .clone()
                            .unwrap_or_default()
                            .split('.')
                            .last()
                            .unwrap_or_default()
                            .to_owned();
                        if suffix == i_type {
                            "".to_string()
                        } else {
                            format!(" ({})", suffix)
                        }
                    };

                    let client_nodes_table =
                        client_nodes_table_map.entry(group.clone()).or_insert({
                            let mut client_nodes_table = Table::new();
                            client_nodes_table.set_format(*format::consts::FORMAT_BOX_CHARS);
                            client_nodes_table.add_row(row![ bc =>
                                format!("{} Instance ID{}", cluster.provider, group),
                                "Private IP",
                                "Public IP",
                                "Zone",
                            ]);
                            client_nodes_table
                        });
                    client_nodes_table.add_row(row![
                        node.id,
                        node.priv_ip,
                        node.pub_ip,
                        node.zone.unwrap_or_default(),
                    ]);
                }
                None => {
                    core_nodes_table.add_row(row![
                        node.name,
                        node.priv_ip,
                        node.pub_ip,
                        node.zone.unwrap_or_default(),
                    ]);
                }
            }
        }
        core_nodes_table.printstd();
        for val in client_nodes_table_map.values() {
            val.printstd();
        }
    }

    Ok(())
}

pub(crate) async fn completions<G: Generator>(gen: G, mut app: App<'_>) {
    let cli = &mut app;
    generate(gen, cli, cli.get_name().to_string(), &mut std::io::stdout())
}
