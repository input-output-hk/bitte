use crate::bitte::{BitteFind, ClusterHandle};
use anyhow::{anyhow, Context, Result};
use clap::ArgMatches;
use log::info;
use std::net::IpAddr;
use std::path::Path;
use std::process::Command;
use std::time::Duration;
use tokio::task::JoinHandle;

pub async fn ssh(sub: &ArgMatches, cluster: ClusterHandle) -> Result<()> {
    let mut args: Vec<String> = sub.get_many("args").unwrap_or_default().cloned().collect();
    let job: Vec<String> = sub.get_many("job").unwrap_or_default().cloned().collect();
    let delay = Duration::from_secs(*sub.get_one::<u64>("delay").unwrap_or(&0));
    let node_class = sub.get_one::<String>("class").cloned();

    let namespace = sub
        .get_one::<String>("namespace")
        .unwrap_or(&"default".to_string())
        .to_owned();

    let ip: IpAddr;

    let cluster = cluster.await??;

    if sub.is_present("all") {
        let nodes = if sub.is_present("clients") {
            cluster.nodes.find_clients(node_class)
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
            cluster.nodes.find_clients(node_class)
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
