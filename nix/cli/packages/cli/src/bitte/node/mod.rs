mod find;
mod instance;
mod order;

use super::BitteFind;
use super::BitteProvider;
use crate::nomad::alloc::{AllocHandle, NomadAllocs};
use crate::nomad::client::{ClientHandle, NomadClient};
use anyhow::{Context, Result};
use aws_sdk_ec2::{model::Filter, Client as Ec2Client, Region};
use clap::ArgMatches;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::net::IpAddr;

/// A Collection of Bitte Nodes
pub type BitteNodes = Vec<BitteNode>;

/// Descrition of an individual node in the cluster
#[derive(Debug, Serialize, Deserialize)]
pub struct BitteNode {
    pub id: String,
    pub name: String,
    pub priv_ip: IpAddr,
    pub pub_ip: IpAddr,
    pub nixos: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nomad_client: Option<NomadClient>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub node_type: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub zone: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub asg: Option<String>,
}

impl BitteNode {
    pub async fn find_nodes(
        provider: BitteProvider,
        name: String,
        allocs: Option<AllocHandle>,
        clients: Option<ClientHandle>,
        args: ArgMatches,
    ) -> Result<BitteNodes> {
        match provider {
            BitteProvider::AWS => {
                let regions = {
                    let mut result: HashSet<String> = args
                        .get_many("aws-asg-regions")
                        .unwrap_or_default()
                        .cloned()
                        .collect();
                    let default = args.get_one::<String>("aws-region");
                    if default.is_some() {
                        result.insert(default.unwrap().to_owned());
                    }
                    result
                };

                let mut handles = Vec::with_capacity(regions.len());

                for region_str in regions {
                    let region = Region::new(region_str.clone());
                    let config = aws_config::from_env().region(region).load().await;
                    let client = Ec2Client::new(&config);
                    let request = client.describe_instances().set_filters(Some(vec![
                        Filter::builder()
                            .set_name(Some("tag:Cluster".to_owned()))
                            .set_values(Some(vec![name.to_owned()]))
                            .build(),
                        Filter::builder()
                            .set_name(Some("instance-state-name".to_owned()))
                            .set_values(Some(vec!["running".to_owned()]))
                            .build(),
                    ]));
                    let response = tokio::spawn(async move {
                        request.send().await.with_context(|| {
                            format!(
                                "failed to connect to ec2.{}.amazonaws.com",
                                region_str.to_owned()
                            )
                        })
                    });
                    handles.push(response);
                }

                let mut result: BitteNodes = Vec::new();

                let allocs = if let Some(allocs) = allocs {
                    allocs.await??
                } else {
                    Vec::new()
                };
                let clients = if let Some(clients) = clients {
                    clients.await??
                } else {
                    Vec::new()
                };

                for response in handles.into_iter() {
                    let response = response.await??;
                    let iter = response.reservations.into_iter();
                    let mut nodes: BitteNodes = iter
                        .flat_map(|reservations| {
                            reservations
                                .into_iter()
                                .flat_map(|reservation| reservation.instances.unwrap_or_default())
                        })
                        .map(|instance| {
                            let mut node = BitteNode::from(instance);
                            node.nomad_client = match clients
                                .iter()
                                .find(|client| client.address == Some(node.priv_ip))
                            {
                                Some(client) => {
                                    let mut client = client.to_owned();
                                    client.allocs = {
                                        Some(
                                            allocs
                                                .iter()
                                                .filter(|alloc| alloc.node_id == client.id)
                                                .map(|alloc| alloc.to_owned())
                                                .collect::<NomadAllocs>(),
                                        )
                                    };
                                    Some(client)
                                }
                                None => None,
                            };

                            node
                        })
                        .collect();

                    result.append(&mut nodes);
                }

                Ok(result)
            }
        }
    }
}
