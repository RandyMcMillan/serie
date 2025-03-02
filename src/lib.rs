pub mod color;
pub mod config;
pub mod git;
pub mod graph;
pub mod protocol;

mod app;
mod check;
mod event;
mod external;
mod keybind;
mod view;
mod widget;

use std::path::Path;
use dirs::*;
use std::env;
use tokio::time::{sleep, Duration};
use tracing_log::log;
use std::error::Error;
use std::time::{SystemTime, UNIX_EPOCH};

use app::App;
use clap::{Parser, ValueEnum};
use graph::GraphImageManager;

/// Serie - A rich git commit graph in your terminal, like magic 📚
#[derive(Parser)]
#[command(version)]
struct Args {
    /// Image protocol to render graph
    #[arg(short, long, value_name = "TYPE", default_value = "auto")]
    protocol: ImageProtocolType,

    /// Commit ordering algorithm
    #[arg(short, long, value_name = "TYPE", default_value = "chrono")]
    order: CommitOrderType,

    /// Commit graph image cell width
    #[arg(short, long, value_name = "TYPE", default_value = "p2p")]
    graph_width: Option<GraphWidthType>,

    /// Preload all graph images
    #[arg(long, default_value = "false")]
    preload: bool,
}

#[derive(Debug, Clone, ValueEnum)]
enum ImageProtocolType {
    Auto,
    Iterm,
    Kitty,
    P2p,
}

impl From<ImageProtocolType> for protocol::ImageProtocol {
    fn from(protocol: ImageProtocolType) -> Self {
        match protocol {
            ImageProtocolType::Auto => protocol::auto_detect(),
            ImageProtocolType::Iterm => protocol::ImageProtocol::Iterm2,
            ImageProtocolType::Kitty => protocol::ImageProtocol::Kitty,
            ImageProtocolType::P2p => protocol::ImageProtocol::P2p,
        }
    }
}

#[derive(Debug, Clone, ValueEnum)]
enum CommitOrderType {
    Chrono,
    Topo,
}

impl From<CommitOrderType> for git::SortCommit {
    fn from(order: CommitOrderType) -> Self {
        match order {
            CommitOrderType::Chrono => git::SortCommit::Chronological,
            CommitOrderType::Topo => git::SortCommit::Topological,
        }
    }
}

#[derive(Debug, Clone, ValueEnum)]
enum GraphWidthType {
    Double,
    Single,
	P2p,
}

impl From<GraphWidthType> for graph::CellWidthType {
    fn from(width: GraphWidthType) -> Self {
        match width {
            GraphWidthType::Double => graph::CellWidthType::Double,
            GraphWidthType::Single => graph::CellWidthType::Single,
            GraphWidthType::P2p => graph::CellWidthType::Single,
        }
    }
}

pub async fn run() -> std::io::Result<()> {
    color_eyre::install().unwrap();
    let args = Args::parse();
    let (ui_config, graph_config, key_bind_patch) = config::load();
    let key_bind = keybind::KeyBind::new(key_bind_patch);

    let color_set = color::ColorSet::new(&graph_config.color);
    let image_protocol = args.protocol.into();

    let repository = git::Repository::load(Path::new("."), args.order.into());

    let graph = graph::calc_graph(&repository);

    let cell_width_type =
        check::decide_cell_width_type(&graph, args.graph_width.map(|w| w.into()))?;

    let graph_image_manager = GraphImageManager::new(
        &graph,
        &color_set,
        cell_width_type,
        image_protocol,
        args.preload,
    );

    let mut terminal = ratatui::init();

    let (tx, rx) = event::init();

    let mut app = App::new(
        &repository,
        graph_image_manager,
        &graph,
        &key_bind,
        &ui_config,
        &color_set,
        cell_width_type,
        image_protocol,
        tx,
    );
    let ret = app.run(&mut terminal, rx);

    ratatui::restore();
    ret
}

pub async fn get_blockheight() -> Result<String, Box<dyn Error>> {
    let client = reqwest::Client::builder()
        .build()
        .expect("should be able to build reqwest client");
    let blockheight = client
        .get("https://mempool.space/api/blocks/tip/height")
        .send()
        .await?;
    log::debug!("mempool.space status: {}", blockheight.status());
    if blockheight.status() != reqwest::StatusCode::OK {
        log::debug!("didn't get OK status: {}", blockheight.status());
        Ok(String::from(">>>>>"))
    } else {
        let blockheight = blockheight.text().await?;
        log::debug!("{}", blockheight);
        Ok(blockheight)
    }
}

pub async fn weeble_blockheight_wobble() -> String {

    let blockheight = get_blockheight().await;

    let now = SystemTime::now();
    let since_the_epoch = now
        .duration_since(UNIX_EPOCH)
        .expect("Time went backwards"); // Handle potential errors

    let blockheight_u64: u64 = blockheight.unwrap().parse().unwrap_or(0);
    let seconds = since_the_epoch.as_secs();
    let weeble = seconds / blockheight_u64;
    let wobble = seconds % blockheight_u64;

    String::from(format!("{:?}/{:?}/{:?}", weeble, blockheight_u64, wobble))
}
