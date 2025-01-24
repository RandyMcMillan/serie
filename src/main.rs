use dirs::*;
use std::env;
use tokio::time::{sleep, Duration};
#[tokio::main]
async fn main() -> std::io::Result<()> {
    println!("tokio_multi:simple");
    let cwd = env::current_dir().unwrap();
    let cwd_to_string_lossy: String = String::from(cwd.to_string_lossy());
    println!("{}", cwd_to_string_lossy);

   let local_data_dir = data_local_dir();
    println!("{}", local_data_dir.expect("REASON").display());
    let task_one = tokio::spawn(async {
        println!("Task one is started");
        sleep(Duration::from_secs(10)).await;
        println!("Task one is done");
    });

    let task_two = tokio::spawn(async {
        println!("serie.run().await");
        let _ = serie::run().await;
        sleep(Duration::from_secs(1)).await;
        println!("Task two is done");
    });

    // Await the tasks to complete
    //let _ = task_one.await.unwrap();
    let _ = task_two.await.unwrap();
    let _ = task_one.await.unwrap();
    Ok(())

    //serie::run()
}
