pub mod node;
pub mod provider;

use super::nomad::{alloc::NomadAlloc, client::NomadClient};
use anyhow::Result;
use clap::ArgMatches;
use node::BitteNode;
use node::BitteNodes;
pub use provider::BitteProvider;
use reqwest::{
    header::{HeaderMap, HeaderValue},
    Client,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::Duration;
use std::time::SystemTime;
use tokio::task::JoinHandle;
use uuid::Uuid;

pub type ClusterHandle = JoinHandle<Result<BitteCluster>>;

pub trait BitteFind
where
    Self: IntoIterator,
{
    fn find_needle(self, needle: &str) -> Result<Self::Item>;
    fn find_needles(self, needles: Vec<&str>) -> Self;
    fn find_clients(self, node_class: Option<String>) -> Self;
    fn find_with_job(
        self,
        name: &str,
        group: &str,
        index: &str,
        namespace: &str,
    ) -> Result<(Self::Item, NomadAlloc)>;
}

/// A description of a Bitte cluster and its nodes
#[derive(Debug, Serialize, Deserialize)]
pub struct BitteCluster {
    pub name: String,
    pub nodes: BitteNodes,
    pub domain: String,
    pub provider: BitteProvider,
    #[serde(skip)]
    pub nomad_api_client: Option<Arc<Client>>,
    pub ttl: SystemTime,
}

impl BitteCluster {
    pub async fn new(args: &ArgMatches, token: Option<Uuid>) -> Result<Self> {
        let name = args.get_one::<String>("name").unwrap().to_owned();
        let domain = args.get_one::<String>("domain").unwrap().to_owned();
        let provider: BitteProvider = args
            .get_one::<BitteProvider>("provider")
            .unwrap()
            .to_owned();

        let nomad_api_client = match token {
            Some(token) => {
                let mut token = HeaderValue::from_str(&token.to_string())?;
                token.set_sensitive(true);
                let mut headers = HeaderMap::new();
                headers.insert("X-Nomad-Token", token);
                Some(Arc::new(
                    Client::builder()
                        .default_headers(headers)
                        .gzip(true)
                        .build()?,
                ))
            }
            None => None,
        };

        let nodes = if let Some(client) = &nomad_api_client {
            let allocs = tokio::spawn(NomadAlloc::find_allocs(
                Arc::clone(client),
                domain.to_owned(),
            ));

            let client_nodes = tokio::spawn(NomadClient::find_nomad_nodes(
                Arc::clone(client),
                domain.to_owned(),
            ));

            tokio::spawn(BitteNode::find_nodes(
                provider,
                name.to_owned(),
                Some(allocs),
                Some(client_nodes),
                args.clone(),
            ))
            .await??
        } else {
            tokio::spawn(BitteNode::find_nodes(
                provider,
                name.to_owned(),
                None,
                None,
                args.clone(),
            ))
            .await??
        };

        let cluster = Self {
            name,
            domain,
            provider,
            nomad_api_client,
            nodes,
            ttl: SystemTime::now()
                .checked_add(Duration::from_secs(300))
                .unwrap(),
        };

        Ok(cluster)
    }

    #[inline(always)]
    pub fn init(args: ArgMatches, token: Option<Uuid>) -> ClusterHandle {
        tokio::spawn(async move { BitteCluster::new(&args, token).await })
    }
}
