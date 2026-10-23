#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
fn main() {
    if std::env::args().any(|a| a == "--demo") {
        eprintln!("QuotaNest demo: native entry");
    }
    quotanest_windows::desktop::run();
}
