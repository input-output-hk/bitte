use crate::bitte::BitteNode;
use aws_sdk_ec2::model::{Instance, Tag};
use std::net::{IpAddr, Ipv4Addr};
use std::str::FromStr;

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
