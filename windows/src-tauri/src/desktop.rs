use crate::{
    cc_switch, codex, deepseek,
    models::AppError,
    service::{Data, Preferences, Service, Snapshot},
    updates,
};
use std::{
    path::PathBuf,
    sync::{Arc, Mutex},
    time::Duration,
};
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Manager, WebviewWindow, WindowEvent,
};
use tauri_plugin_autostart::ManagerExt;
#[derive(Clone)]
struct Backend {
    service: Arc<Mutex<Service>>,
    work: Arc<tokio::sync::Notify>,
    update_work: Arc<tokio::sync::Mutex<()>>,
    home: PathBuf,
    preferences: PathBuf,
    demo: bool,
}
impl Backend {
    fn snapshot(&self) -> Snapshot {
        self.service.lock().unwrap().snapshot()
    }
    fn save(&self, preferences: &Preferences) -> Result<(), AppError> {
        let dir = self
            .preferences
            .parent()
            .ok_or_else(|| AppError::new("preferences_write"))?;
        std::fs::create_dir_all(dir).map_err(|_| AppError::new("preferences_write"))?;
        let temp = self.preferences.with_extension("tmp");
        std::fs::write(
            &temp,
            serde_json::to_vec(preferences).map_err(|_| AppError::new("preferences_write"))?,
        )
        .map_err(|_| AppError::new("preferences_write"))?;
        std::fs::rename(temp, &self.preferences).map_err(|_| AppError::new("preferences_write"))
    }
}
fn demo_data(source: &str) -> Data {
    if source == "codex" {
        Data::Quota(crate::models::parse_codex(&serde_json::json!({"rateLimits":{"planType":"Plus","primary":{"usedPercent":24,"windowDurationMins":300},"secondary":{"usedPercent":38,"windowDurationMins":10080}}})).unwrap())
    } else {
        Data::Balance(crate::models::parse_balance(&serde_json::json!({"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"18.60","granted_balance":"3.60","topped_up_balance":"15.00"}]})).unwrap())
    }
}
async fn poll(backend: Backend, app: tauri::AppHandle) {
    // One global transfer at a time, even if the user switches sources repeatedly.
    let Some(request) = backend.service.lock().unwrap().begin() else {
        return;
    };
    let source = request.source.clone();
    let result = if backend.demo {
        Ok(demo_data(&source))
    } else if source == "codex" {
        codex::fetch(&backend.home).await.map(Data::Quota)
    } else if let Some(id) = source.strip_prefix("api:") {
        let directory = PathBuf::from(&request.directory);
        match cc_switch::resolve(&directory, id) {
            Ok(credential) => {
                {
                    let mut service = backend.service.lock().unwrap();
                    if !service.current(&request) {
                        return;
                    }
                    if service
                        .credential_generation
                        .as_ref()
                        .is_some_and(|g| g != &credential.generation)
                    {
                        service.credentials_changed();
                    }
                    service.credential_generation = Some(credential.generation.clone());
                }
                let value = deepseek::fetch(&credential).await;
                match cc_switch::resolve(&directory, id) {
                    Ok(current) if current.generation == credential.generation => {
                        value.map(Data::Balance)
                    }
                    Err(error) if error.code == "source_busy" => Err(error),
                    _ => {
                        let mut service = backend.service.lock().unwrap();
                        if service.current(&request) {
                            service.credentials_changed();
                        }
                        Err(AppError::new("source_changed"))
                    }
                }
            }
            Err(error) => {
                let mut service = backend.service.lock().unwrap();
                if service.current(&request) && error.code != "source_busy" {
                    service.credentials_changed();
                }
                Err(error)
            }
        }
    } else {
        Err(AppError::new("unsupported_source"))
    };
    let mut service = backend.service.lock().unwrap();
    if service.finish(request, result) {
        if let Some(tray) = app.tray_by_id("quota") {
            let state = &service.state;
            let amount = match &state.reading.data {
                Some(Data::Balance(w)) => w
                    .first()
                    .map(|w| format!("{} {}", w.currency, w.total))
                    .unwrap_or_else(|| "—".into()),
                Some(Data::Quota(q)) => q
                    .windows
                    .first()
                    .and_then(|w| w.remaining)
                    .map(|n| format!("{n:.0}%"))
                    .unwrap_or_else(|| "—".into()),
                None => "—".into(),
            };
            let _ = tray.set_tooltip(Some(format!(
                "QuotaNest · {amount}{}",
                if state.reading.error.is_some() {
                    " · !"
                } else {
                    ""
                }
            )));
        }
    }
}
fn start_poll(backend: &Backend, _app: &tauri::AppHandle) {
    backend.work.notify_one();
}
#[tauri::command]
fn snapshot(backend: tauri::State<'_, Backend>) -> Snapshot {
    backend.snapshot()
}
#[tauri::command]
fn refresh(backend: tauri::State<'_, Backend>, app: tauri::AppHandle) {
    start_poll(&backend, &app);
}
#[tauri::command]
fn select_source(
    source: String,
    backend: tauri::State<'_, Backend>,
    app: tauri::AppHandle,
) -> Result<Snapshot, AppError> {
    let mut service = backend.service.lock().unwrap();
    service.select(&source)?;
    if backend.demo {
        service.state.reading.data = Some(demo_data(&source));
        service.state.reading.updated = Some(crate::models::now());
    }
    if !backend.demo {
        backend.save(&service.state.preferences)?;
    }
    let snapshot = service.snapshot();
    drop(service);
    start_poll(&backend, &app);
    Ok(snapshot)
}
#[tauri::command]
fn discover(directory: String, backend: tauri::State<'_, Backend>) -> Result<Snapshot, AppError> {
    let mut service = backend.service.lock().unwrap();
    if backend.demo {
        return Ok(service.snapshot());
    }
    match cc_switch::discover(&PathBuf::from(&directory)) {
        Ok(connections) => {
            if service.state.preferences.directory != directory {
                let source = service.state.preferences.source.clone();
                service.select("codex")?;
                service.state.preferences.source = source;
            }
            service.state.preferences.directory = directory;
            service.state.connections = connections;
            service.state.discovery_error = None;
            if service.state.preferences.source != "codex"
                && !service.state.connections.iter().any(|c| {
                    c.supported && format!("api:{}", c.id) == service.state.preferences.source
                })
            {
                service.credentials_changed();
            }
            backend.save(&service.state.preferences)?;
        }
        Err(error) => {
            if error.code != "source_busy" && service.state.preferences.source != "codex" {
                service.credentials_changed();
            }
            service.state.discovery_error = Some(error);
        }
    }
    Ok(service.snapshot())
}
#[tauri::command]
fn save_preferences(
    preferences: Preferences,
    backend: tauri::State<'_, Backend>,
    app: tauri::AppHandle,
) -> Result<Snapshot, AppError> {
    if !["system", "en", "zh"].contains(&preferences.language.as_str())
        || preferences.directory.len() > 32768
    {
        return Err(AppError::new("preferences_write"));
    }
    let mut service = backend.service.lock().unwrap();
    let mut next = service.state.preferences.clone();
    next.language = preferences.language;
    next.autostart = preferences.autostart;
    // Directory changes are applied only through explicit discovery; not by a language save.
    if !backend.demo {
        let autolaunch = app.autolaunch();
        let result = if next.autostart {
            autolaunch.enable()
        } else {
            autolaunch.disable()
        };
        result.map_err(|_| AppError::new("autostart_failed"))?;
        backend.save(&next)?;
    }
    service.state.preferences = next;
    Ok(service.snapshot())
}
#[tauri::command]
async fn check_update(backend: tauri::State<'_, Backend>) -> Result<(), AppError> {
    let Ok(_work) = backend.update_work.try_lock() else {
        return Ok(());
    };
    backend.service.lock().unwrap().state.update_status = "checking".into();
    let result = if backend.demo {
        Ok(None)
    } else {
        updates::check().await
    };
    let mut service = backend.service.lock().unwrap();
    match result {
        Ok(update) => {
            service.state.update_status = if update.is_some() {
                "availableUpdate"
            } else {
                "current"
            }
            .into();
            service.state.update = update;
        }
        Err(_) => service.state.update_status = "update_failed".into(),
    }
    Ok(())
}
#[tauri::command]
async fn install_update(
    backend: tauri::State<'_, Backend>,
    app: tauri::AppHandle,
) -> Result<(), AppError> {
    let Ok(_work) = backend.update_work.try_lock() else {
        return Ok(());
    };
    if backend.demo {
        return Err(AppError::new("invalid_update"));
    }
    let update = backend
        .service
        .lock()
        .unwrap()
        .state
        .update
        .clone()
        .ok_or_else(|| AppError::new("invalid_update"))?;
    backend.service.lock().unwrap().state.update_status = "downloading".into();
    let directory = backend.preferences.parent().unwrap().join("Updates");
    let result = async {
        let installer = updates::stage(&update, &directory).await?;
        #[cfg(windows)]
        {
            std::process::Command::new(installer)
                .spawn()
                .map_err(|_| AppError::new("update_download"))?;
            app.exit(0);
        }
        #[cfg(not(windows))]
        {
            let _ = (installer, app);
            return Err(AppError::new("invalid_update"));
        }
        #[allow(unreachable_code)]
        Ok(())
    }
    .await;
    if let Err(ref e) = result {
        backend.service.lock().unwrap().state.update_status = e.code.clone();
    }
    result
}
#[tauri::command]
fn quit(app: tauri::AppHandle) {
    app.exit(0);
}
fn show(window: &WebviewWindow) {
    let _ = window.show();
    let _ = window.unminimize();
    let _ = window.set_focus();
}
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app,_,_|{if let Some(window)=app.get_webview_window("main"){show(&window);}}))
        .plugin(tauri_plugin_autostart::init(tauri_plugin_autostart::MacosLauncher::LaunchAgent,Some(vec!["--background"])))
        .invoke_handler(tauri::generate_handler![snapshot,refresh,select_source,discover,save_preferences,check_update,install_update,quit])
        .setup(|app|{
            let home=std::env::var_os(if cfg!(windows){"USERPROFILE"}else{"HOME"}).map(PathBuf::from).ok_or("home missing")?;
            let preferences=app.path().app_config_dir()?.join("preferences.json");
            let demo=std::env::args().any(|a|a=="--demo");
            let mut prefs=if demo{Preferences::defaults(&home)}else{std::fs::read(&preferences).ok().and_then(|b|serde_json::from_slice::<Preferences>(&b).ok()).unwrap_or_else(||Preferences::defaults(&home))};
            if !demo {prefs.autostart=app.autolaunch().is_enabled().unwrap_or(prefs.autostart);}
            let mut service=Service::new(prefs);
            if demo {
                service.state.connections=vec![cc_switch::Connection{id:"claude|demo".into(),name:"DeepSeek".into(),harness:"claude".into(),origin:"https://api.deepseek.com".into(),supported:true}];
                service.select("api:claude|demo")?;service.state.reading.data=Some(demo_data("api:claude|demo"));service.state.reading.updated=Some(crate::models::now());
            }else if service.state.preferences.source!="codex" {
                match cc_switch::discover(&PathBuf::from(&service.state.preferences.directory)){Ok(c)=>service.state.connections=c,Err(e)=>service.state.discovery_error=Some(e)}
            }
            let backend=Backend{service:Arc::new(Mutex::new(service)),work:Arc::new(tokio::sync::Notify::new()),update_work:Arc::new(tokio::sync::Mutex::new(())),home,preferences,demo};
            app.manage(backend.clone());
            let open=MenuItem::with_id(app,"open","Open QuotaNest",true,None::<&str>)?;
            let refresh=MenuItem::with_id(app,"refresh","Refresh / 刷新",true,None::<&str>)?;
            let quit=MenuItem::with_id(app,"quit","Quit / 退出",true,None::<&str>)?;
            let menu=Menu::with_items(app,&[&open,&refresh,&quit])?;
            let window=app.get_webview_window("main").ok_or("window missing")?;
            let menu_backend=backend.clone();
            TrayIconBuilder::with_id("quota").icon(app.default_window_icon().ok_or("icon missing")?.clone()).tooltip("QuotaNest").menu(&menu).show_menu_on_left_click(false)
                .on_menu_event(move|app,event|match event.id.as_ref(){"open"=>{if let Some(w)=app.get_webview_window("main"){show(&w);}},"refresh"=>start_poll(&menu_backend,app),"quit"=>app.exit(0),_=>{}})
                .on_tray_icon_event(|tray,event|{if let TrayIconEvent::Click{button:MouseButton::Left,button_state:MouseButtonState::Up,..}=event{if let Some(window)=tray.app_handle().get_webview_window("main"){show(&window);}}}).build(app)?;
            let hide=window.clone();window.on_window_event(move|event|{if let WindowEvent::CloseRequested{api,..}=event{api.prevent_close();let _=hide.hide();}});
            if std::env::args().any(|a|a=="--background"){let _=window.hide();}
            let handle=app.handle().clone();
            start_poll(&backend,&handle);
            let check_backend=backend.clone();
            if !demo {tauri::async_runtime::spawn(async move{let result=updates::check().await;let mut s=check_backend.service.lock().unwrap();match result{Ok(u)=>{s.state.update_status=if u.is_some(){"availableUpdate"}else{"current"}.into();s.state.update=u;},Err(_)=>s.state.update_status="update_failed".into()}});}
            tauri::async_runtime::spawn(async move{loop{tokio::select!{_=backend.work.notified()=>{},_=tokio::time::sleep(Duration::from_secs(60))=>{}};poll(backend.clone(),handle.clone()).await;}});
            Ok(())
        }).run(tauri::generate_context!()).expect("QuotaNest could not start");
}
