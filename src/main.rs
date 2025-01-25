use dirs::*;
use std::env;
use tokio::time::{sleep, Duration};
use tracing_log::log;
use std::error::Error;
use std::time::{SystemTime, UNIX_EPOCH};
use serie::weeble_blockheight_wobble;

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

    // inline async task
    let task_one = tokio::spawn(async {
        log::info!("Task one is started");
        //eprint!("blockheight={}\n", get_blockheight().await.expect("blockheight"));
        log::info!("blockheight={}\n", weeble_blockheight_wobble().await);
        //sleep(Duration::from_secs(1)).await;
        log::info!("Task one is done");
    });

    // inline async task
    let task_two = tokio::spawn(async {
        log::info!("Task two is started");
        log::info!("serie.run().await");
		// if serie run here
		// it cant be called later
		// in the join
        // let _ = serie::run().await;
        log::info!("Task two is done");
    });

    // Await the tasks to complete
    let _ = task_one.await.unwrap();
    let _ = task_two.await.unwrap();
    //
    use tokio::join;
    let (result_one, result_two) = join!(task_hello(), task_world());
    log::info!("{} {}", result_one, result_two); // Output: Hello World
    //let (result_one, result_two) = join!(get_blockheight(), serie_run());
    //println!("{:?} {:?}", result_one, result_two);
    let (result_one, result_two) = join!(weeble_blockheight_wobble(), serie_run());
    log::info!("{:?} {:?}", result_one, result_two);

    Ok(())

    //serie::run()
}
