use dirs::*;
use std::env;
use tokio::time::{sleep, Duration};
use tracing_log::log;
use std::error::Error;

async fn get_blockheight() -> Result<String, Box<dyn Error>> {
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

#[tokio::main]
async fn main() -> std::io::Result<()> {
    println!("tokio_multi:simple");
    let cwd = env::current_dir().unwrap();
    let cwd_to_string_lossy: String = String::from(cwd.to_string_lossy());
    log::info!("{}", cwd_to_string_lossy);

   let local_data_dir = data_local_dir();
    log::info!("{}", local_data_dir.expect("REASON").display());
    let task_one = tokio::spawn(async {
        log::info!("Task one is started");
        eprint!("blockheight={}\n", get_blockheight().await.expect("blockheight"));
        sleep(Duration::from_secs(1)).await;
        log::info!("Task one is done");
    });

    let task_two = tokio::spawn(async {
        log::info!("Task two is started");
        log::info!("serie.run().await");
        let _ = serie::run().await;
        log::info!("Task two is done");
    });

    // Await the tasks to complete
    let _ = task_one.await.unwrap();
    let _ = task_two.await.unwrap();
    //let _ = task_one.await.unwrap();
    Ok(())

    //serie::run()
}
