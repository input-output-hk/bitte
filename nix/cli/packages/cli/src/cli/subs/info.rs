use crate::bitte::ClusterHandle;
use anyhow::Result;
use clap::ArgMatches;
use prettytable::{cell, format, row, Table};
use std::collections::HashMap;
use std::io;

pub async fn info(sub: &ArgMatches, cluster: ClusterHandle) -> Result<()> {
    let json: bool = sub.is_present("json");
    info_print(cluster, json).await?;
    Ok(())
}
async fn info_print(cluster: ClusterHandle, json: bool) -> Result<()> {
    let cluster = cluster.await??;
    if json {
        let stdout = io::stdout();
        let handle = stdout.lock();
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
                Some(_) => {
                    let group: String = {
                        match node.nomad_client {
                            Some(client) => match client.node_class {
                                Some(class) => format!(" ({})", class),
                                None => "".to_string(),
                            },
                            None => "".to_string(),
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
