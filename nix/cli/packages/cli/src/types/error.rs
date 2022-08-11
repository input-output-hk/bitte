#[derive(thiserror::Error, Debug)]
#[error(transparent)]
pub enum Error {
    #[error("timeout elapsed")]
    Timeout(#[from] tokio::time::error::Elapsed),
    #[error("connection with {0} failed")]
    ConnectionFailed(#[from] std::io::Error),
    #[error("environment variable")]
    EnvVar(#[from] std::env::VarError),
    #[error("error parsing json")]
    Serde(#[from] serde_json::Error),
    #[error("error parsing netrc file")]
    Netrc(netrc_rs::Error),
    #[error("current BITTE_PROVIDER is not valid: {provider}")]
    Provider { provider: String },
}

// NOTE netrc_rs doesn't impl StdError so can't simply `#[from]`
impl From<netrc_rs::Error> for Error {
    fn from(error: netrc_rs::Error) -> Self {
        Error::Netrc(error)
    }
}
