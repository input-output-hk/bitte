use clap::ArgEnum;
use enum_utils::FromStr;
use serde::{Deserialize, Serialize};
use std::fmt::{Display, Formatter};

/// The underlying infrastructure provider for the cluster
#[derive(Debug, Serialize, Deserialize, Copy, Clone, FromStr, ArgEnum)]
#[enumeration(case_insensitive)]
#[allow(clippy::upper_case_acronyms)]
pub enum BitteProvider {
    AWS,
}

impl Default for BitteProvider {
    fn default() -> Self {
        BitteProvider::AWS
    }
}

impl Display for BitteProvider {
    fn fmt(&self, f: &mut Formatter) -> std::fmt::Result {
        let provider = match *self {
            BitteProvider::AWS => "AWS",
        };
        write!(f, "{}", provider)
    }
}
