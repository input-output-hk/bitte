use super::BitteFind;
use crate::nomad::alloc::NomadAlloc;
use anyhow::{Context, Result};
use std::net::IpAddr;

impl BitteFind for super::BitteNodes {
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

    fn find_clients(self, node_class: Option<String>) -> Self {
        match node_class {
            Some(class) => self
                .into_iter()
                .filter(|node| match &node.nomad_client {
                    Some(client) => client.node_class.clone().unwrap_or_default() == class,
                    None => false,
                })
                .collect(),
            None => self.into_iter().filter(|node| node.asg.is_some()).collect(),
        }
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
