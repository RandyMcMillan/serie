use dirs::*;
use std::env;
use tokio::time::{sleep, Duration};
use tracing_log::log;
use std::error::Error;
use std::time::{SystemTime, UNIX_EPOCH};

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

async fn weeble_blockheight_wobble() -> String {

	let blockheight = get_blockheight().await;

    let now = SystemTime::now();
    let since_the_epoch = now
        .duration_since(UNIX_EPOCH)
        .expect("Time went backwards"); // Handle potential errors

	let blockheight_u64: u64 = blockheight.unwrap().parse().unwrap();
    let seconds = since_the_epoch.as_secs();
    let weeble = seconds / blockheight_u64;
    let wobble = seconds % blockheight_u64;

    String::from(format!("{:?}/{:?}/{:?}", weeble, blockheight_u64, wobble))
}

async fn task_hello() -> &'static str {
    "Hello"
}

async fn task_world() -> &'static str {
    "World"
}

async fn serie_run(){
        let _ = serie::run().await;
}

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let cwd = env::current_dir().unwrap();
    let cwd_to_string_lossy: String = String::from(cwd.to_string_lossy());
    log::info!("{}", cwd_to_string_lossy);

   let local_data_dir = data_local_dir();
    log::info!("{}", local_data_dir.expect("REASON").display());
    let task_one = tokio::spawn(async {
        log::info!("Task one is started");
        //eprint!("blockheight={}\n", get_blockheight().await.expect("blockheight"));
        eprint!("blockheight={}\n", weeble_blockheight_wobble().await);
        sleep(Duration::from_secs(1)).await;
        log::info!("Task one is done");
    });

    let task_two = tokio::spawn(async {
        log::info!("Task two is started");
        log::info!("serie.run().await");
//        let _ = serie::run().await;
        log::info!("Task two is done");
    });

	use tokio::join;
	//let (result_one, result_two) = join!(task_hello(), task_world());
	//println!("{} {}", result_one, result_two); // Output: Hello World
	let (result_one, result_two) = join!(get_blockheight(), serie_run());
	println!("{:?} {:?}", result_one, result_two); // Output: Hello World
    // Await the tasks to complete
    //let _ = task_one.await.unwrap();
    //let _ = task_two.await.unwrap();
    Ok(())

    //serie::run()
}
