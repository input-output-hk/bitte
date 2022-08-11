pub mod error;

use aws_sdk_ec2::{
    model::{Filter, Instance, Tag},
    Client as Ec2Client, Region,
};
use clap::{ArgEnum, ArgMatches};
use serde::{de::Deserializer, Deserialize, Serialize};
use std::cmp::Ordering;
use std::collections::hash_set::HashSet;
use std::env;
use std::fmt::{Display, Formatter};
use std::str::FromStr;
use std::sync::Arc;
use std::time::{Duration, SystemTime};

use anyhow::{Context, Result};
use enum_utils::FromStr;
use std::net::{IpAddr, Ipv4Addr};
use uuid::Uuid;

use tokio::task::JoinHandle;

use reqwest::{
    header::{HeaderMap, HeaderValue},
    Client,
};

use error::Error;

use regex::Regex;

#[derive(Serialize, Deserialize)]
pub struct VaultLogin {
    pub request_id: String,
    pub lease_id: String,
    pub renewable: bool,
    pub lease_duration: i64,
    pub auth: Auth,
}

#[derive(Serialize, Deserialize)]
pub struct Auth {
    pub client_token: String,
    pub accessor: String,
    pub policies: Vec<String>,
    pub token_policies: Vec<String>,
    pub metadata: Metadata,
    pub lease_duration: i64,
    pub renewable: bool,
    pub entity_id: String,
    pub token_type: String,
    pub orphan: bool,
}

#[derive(Serialize, Deserialize)]
pub struct Metadata {
    pub org: String,
    pub username: String,
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

#[derive(Debug, Serialize, Deserialize, Copy, Clone, FromStr, ArgEnum)]
#[enumeration(case_insensitive)]
#[allow(clippy::upper_case_acronyms)]
pub enum BitteProvider {
    AWS,
}

impl Display for BitteProvider {
    fn fmt(&self, f: &mut Formatter) -> std::fmt::Result {
        let provider = match *self {
            BitteProvider::AWS => "AWS",
        };
        write!(f, "{}", provider)
    }
}

#[derive(Debug, Serialize, Deserialize, Clone, Default)]
pub struct NomadClient {
    #[serde(rename = "ID")]
    pub id: Uuid,
    pub allocs: Option<NomadAllocs>,
    #[serde(rename = "Address")]
    pub address: Option<IpAddr>,
}

impl NomadClient {
    async fn find_nomad_nodes(client: Arc<Client>, domain: String) -> Result<NomadClients> {
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

#[derive(Debug, Serialize, Deserialize)]
pub struct BitteNode {
    pub id: String,
    pub name: String,
    pub priv_ip: IpAddr,
    pub pub_ip: IpAddr,
    pub nixos: String,
    #[serde(skip_serializing_if = "skip_info")]
    pub nomad_client: Option<NomadClient>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub node_type: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub zone: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub asg: Option<String>,
}

fn skip_info<T>(_: &Option<T>) -> bool {
    env::var("BITTE_INFO_NO_ALLOCS").is_ok()
}

pub trait BitteFind
where
    Self: IntoIterator,
{
    fn find_needle(self, needle: &str) -> Result<Self::Item>;
    fn find_needles(self, needles: Vec<&str>) -> Self;
    fn find_clients(self) -> Self;
    fn find_with_job(
        self,
        name: &str,
        group: &str,
        index: &str,
        namespace: &str,
    ) -> Result<(Self::Item, NomadAlloc)>;
}

impl Ord for BitteNode {
    fn cmp(&self, other: &Self) -> Ordering {
        self.name.cmp(&other.name)
    }
}

impl PartialOrd for BitteNode {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl PartialEq for BitteNode {
    fn eq(&self, other: &Self) -> bool {
        self.name == other.name
    }
}

impl Eq for BitteNode {}

impl BitteFind for BitteNodes {
    fn find_with_job(
        self,
        name: &str,
        group: &str,
        index: &str,
        namespace: &str,
    ) -> Result<(Self::Item, NomadAlloc)> {
        let node = self
            .into_iter()
            .find(|node| {
                let client = &node.nomad_client;
                if client.is_none() {
                    return false;
                };

                let allocs = &client.as_ref().unwrap().allocs;
                if allocs.is_none() || allocs.as_ref().unwrap().is_empty() {
                    return false;
                };

                allocs.as_ref().unwrap().iter().any(|alloc| {
                    alloc.namespace == namespace
                        && alloc.job_id == name
                        && alloc.task_group == group
                        && alloc.index.get() == index.parse().ok()
                        && alloc.status == "running"
                })
            })
            .with_context(|| {
                format!(
                    "{}, {}, {} does not match any running nomad allocations in namespace {}",
                    name, group, index, namespace
                )
            })?;
        let alloc = node
            .nomad_client
            .as_ref()
            .unwrap()
            .allocs
            .as_ref()
            .unwrap()
            .iter()
            .find(|alloc| {
                alloc.namespace == namespace
                    && alloc.job_id == name
                    && alloc.task_group == group
                    && alloc.index.get() == index.parse().ok()
                    && alloc.status == "running"
            })
            .unwrap()
            .clone();
        Ok((node, alloc))
    }

    fn find_needle(self, needle: &str) -> Result<Self::Item> {
        self.into_iter()
            .find(|node| {
                let ip = needle.parse::<IpAddr>().ok();

                node.id == needle
                    || node.name == needle
                    || node
                        .nomad_client
                        .as_ref()
                        .unwrap_or(&Default::default())
                        .id
                        .hyphenated()
                        .to_string()
                        == needle
                    || Some(node.priv_ip) == ip
                    || Some(node.pub_ip) == ip
            })
            .with_context(|| format!("{} does not match any nodes", needle))
    }

    fn find_clients(self) -> Self {
        self.into_iter().filter(|node| node.asg.is_some()).collect()
    }

    fn find_needles(self, needles: Vec<&str>) -> Self {
        self.into_iter()
            .filter(|node| {
                let ips: Vec<Option<IpAddr>> = needles
                    .iter()
                    .map(|needle| needle.parse::<IpAddr>().ok())
                    .collect();

                needles.contains(&&*node.id)
                    || needles.contains(&&*node.name)
                    || needles.contains(
                        &&*node
                            .nomad_client
                            .as_ref()
                            .unwrap_or(&Default::default())
                            .id
                            .hyphenated()
                            .to_string(),
                    )
                    || ips.contains(&Some(node.priv_ip))
                    || ips.contains(&Some(node.pub_ip))
            })
            .collect()
    }
}

impl From<Instance> for BitteNode {
    fn from(instance: Instance) -> Self {
        let tags = instance.tags.unwrap_or_default();
        let empty_tag = Tag::builder().build();

        let nixos = tags
            .iter()
            .find(|tag| tag.key == Some("UID".into()))
            .unwrap_or(&empty_tag)
            .value
            .as_ref();

        let name = tags
            .iter()
            .find(|tag| tag.key == Some("Name".into()))
            .unwrap_or(&empty_tag)
            .value
            .as_ref();

        let asg = tags
            .iter()
            .find(|tag| tag.key == Some("aws:autoscaling:groupName".into()))
            .unwrap_or(&empty_tag)
            .value
            .as_ref();

        let no_ip = IpAddr::V4(Ipv4Addr::new(0, 0, 0, 0));

        let zone = if let Some(p) = instance.placement {
            p.availability_zone
        } else {
            None
        };

        Self {
            id: instance.instance_id.unwrap_or_default(),
            name: match name {
                Some(name) => name.to_owned(),
                None => "".into(),
            },
            priv_ip: IpAddr::from_str(&instance.private_ip_address.unwrap_or_default())
                .unwrap_or(no_ip),
            pub_ip: IpAddr::from_str(&instance.public_ip_address.unwrap_or_default())
                .unwrap_or(no_ip),
            nomad_client: None,
            nixos: match nixos {
                Some(nixos) => nixos.to_owned(),
                None => "".into(),
            },
            node_type: instance.instance_type.map(|s| s.as_str().to_owned()),
            zone,
            asg: asg.map(|asg| asg.to_owned()),
        }
    }
}

impl BitteNode {
    async fn find_nodes(
        provider: BitteProvider,
        name: String,
        allocs: Option<AllocHandle>,
        clients: Option<ClientHandle>,
        args: ArgMatches,
    ) -> Result<BitteNodes> {
        match provider {
            BitteProvider::AWS => {
                let regions: HashSet<String> = {
                    let mut result = args.values_of_t("aws-asg-regions")?;
                    let default = args.value_of_t("aws-region")?;
                    result.push(default);
                    result.into_iter().collect()
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
                            format!("failed to connect to ec2.{}.amazonaws.com", region_str)
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

type NomadClients = Vec<NomadClient>;
type NomadAllocs = Vec<NomadAlloc>;
type BitteNodes = Vec<BitteNode>;
pub type ClusterHandle = JoinHandle<Result<BitteCluster>>;

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
    async fn find_allocs(client: Arc<Client>, domain: String) -> Result<NomadAllocs> {
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

type ClientHandle = JoinHandle<Result<NomadClients>>;
type AllocHandle = JoinHandle<Result<NomadAllocs>>;

impl BitteCluster {
    pub async fn new(args: &ArgMatches, token: Option<Uuid>) -> Result<Self> {
        let name: String = args.value_of_t("name")?;
        let domain: String = args.value_of_t("domain")?;
        let provider: BitteProvider = {
            let provider: String = args.value_of_t("provider")?;
            match provider.parse() {
                Ok(v) => Ok(v),
                Err(_) => Err(Error::Provider { provider }),
            }?
        };

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
