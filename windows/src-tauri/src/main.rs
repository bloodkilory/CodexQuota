#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
fn main() {
    quotanest_windows::desktop::run();
}
