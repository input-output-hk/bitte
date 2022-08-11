use crate::types::BitteProvider;
use clap::Parser;

#[derive(Parser)]
struct Provider {
    #[clap(arg_enum)]
    name: BitteProvider,
}
