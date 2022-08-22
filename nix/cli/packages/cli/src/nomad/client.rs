use super::alloc::NomadAllocs;
use anyhow::{Context, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::net::IpAddr;
use std::sync::Arc;
use tokio::task::JoinHandle;
use uuid::Uuid;

pub type ClientHandle = JoinHandle<Result<NomadClients>>;

/// Information about a Nomad Client in the cluster.
#[derive(Debug, Serialize, Deserialize, Clone, Default)]
pub struct NomadClient {
    #[serde(rename = "ID")]
    pub id: Uuid,
    pub allocs: Option<NomadAllocs>,
    #[serde(rename = "Address")]
    pub address: Option<IpAddr>,
    #[serde(rename = "NodeClass")]
    pub node_class: Option<String>,
}

/// Collection of Nomad clients
pub type NomadClients = Vec<NomadClient>;

impl NomadClient {
    pub async fn find_nomad_nodes(client: Arc<Client>, domain: String) -> Result<NomadClients> {
        let url = format!("https://nomad.{}/v1/nodes", domain);
        let nodes = client
            .get(&url)
            .send()
            .await
            .with_context(|| format!("failed to query: {}", &url))?
            .json::<NomadClients>()
            .await
            .with_context(|| format!("failed to decode response from: {}", &url))?;
        Ok(nodes)
    }
}
