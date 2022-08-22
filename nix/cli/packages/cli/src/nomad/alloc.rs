use anyhow::{Context, Result};
use regex::Regex;
use reqwest::Client;
use serde::{de::Deserializer, Deserialize, Serialize};
use std::sync::Arc;
use tokio::task::JoinHandle;
use uuid::Uuid;

pub type AllocHandle = JoinHandle<Result<NomadAllocs>>;

/// Information about a Nomad allocation placed in the cluster.
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct NomadAlloc {
    #[serde(rename = "ID")]
    pub id: Uuid,
    #[serde(rename = "JobID")]
    pub job_id: String,
    #[serde(rename = "Namespace")]
    pub namespace: String,
    #[serde(rename = "TaskGroup")]
    pub task_group: String,
    #[serde(rename = "ClientStatus")]
    pub status: String,
    #[serde(
        rename(deserialize = "Name", serialize = "Index"),
        deserialize_with = "pull_index"
    )]
    #[serde(alias = "Index")]
    pub index: AllocIndex,
    #[serde(rename = "NodeID")]
    pub node_id: Uuid,
}

impl NomadAlloc {
    pub async fn find_allocs(client: Arc<Client>, domain: String) -> Result<NomadAllocs> {
        let url = format!("https://nomad.{}/v1/allocations", domain);
        let allocs = client
            .get(&url)
            .query(&[("namespace", "*"), ("task_states", "false")])
            .send()
            .await
            .with_context(|| format!("failed to query: {}", &url))?
            .json::<NomadAllocs>()
            .await
            .with_context(|| format!("failed to decode response from: {}", &url))?;
        Ok(allocs)
    }
}

/// Collection of Nomad allocations.
pub type NomadAllocs = Vec<NomadAlloc>;

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(untagged)]
pub enum AllocIndex {
    Int(u32),
    String(String),
}

impl AllocIndex {
    pub fn get(&self) -> Option<u32> {
        match self {
            Self::Int(i) => Some(*i),
            Self::String(_) => None,
        }
    }
}

fn pull_index<'de, D>(deserializer: D) -> Result<AllocIndex, D::Error>
where
    D: Deserializer<'de>,
{
    let buf = AllocIndex::deserialize(deserializer)?;

    match buf {
        AllocIndex::Int(i) => Ok(AllocIndex::Int(i)),
        AllocIndex::String(s) => {
            let search = Regex::new("[0-9]*\\]$").unwrap().find(&s).unwrap().as_str();

            let index = &search[0..search.len() - 1];
            let index: u32 = index.parse().unwrap();

            Ok(AllocIndex::Int(index))
        }
    }
}
