use std::{
    fs,
    io::{BufRead, BufReader},
    process::{Command, Stdio},
    sync::{Arc, Mutex},
    thread,
};

use serde::{Deserialize, Serialize};
use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::TrayIconBuilder,
    AppHandle, Manager, WebviewUrl, WebviewWindowBuilder,
};

const DEFAULT_MAC: &str = "3c:6a:9d:2d:2e:68";
const KEYLIGHT_PORT: u16 = 9123;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Settings {
    pub keylight_mac: String,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            keylight_mac: DEFAULT_MAC.to_string(),
        }
    }
}

#[derive(Clone)]
struct AppState {
    keylight_mac: String,
    keylight_ip: Option<String>,
    light_on: bool,
    auto_mode: bool,
    camera_active: bool,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            keylight_mac: DEFAULT_MAC.to_string(),
            keylight_ip: None,
            light_on: false,
            auto_mode: true,
            camera_active: false,
        }
    }
}

type SharedState = Arc<Mutex<AppState>>;

fn settings_path(app: &AppHandle) -> Option<std::path::PathBuf> {
    app.path().app_config_dir().ok().map(|p| p.join("settings.json"))
}

fn load_settings(app: &AppHandle) -> Settings {
    settings_path(app)
        .and_then(|p| fs::read_to_string(p).ok())
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

fn persist_settings(app: &AppHandle, settings: &Settings) {
    if let Some(path) = settings_path(app) {
        if let Some(parent) = path.parent() {
            let _ = fs::create_dir_all(parent);
        }
        if let Ok(json) = serde_json::to_string_pretty(settings) {
            let _ = fs::write(path, json);
        }
    }
}

fn discover_keylight(mac: &str) -> Option<String> {
    let output = Command::new("arp").arg("-an").output().ok()?;
    let text = String::from_utf8_lossy(&output.stdout);

    for line in text.lines() {
        if line.to_lowercase().contains(&mac.to_lowercase()) {
            let ip = line.split('(').nth(1)?.split(')').next()?.to_string();
            if !ip.is_empty() && ip != "incomplete" {
                return Some(ip);
            }
        }
    }
    None
}

fn set_light(ip: &str, on: bool) {
    let url = format!("http://{}:{}/elgato/lights", ip, KEYLIGHT_PORT);
    let body = if on {
        r#"{"numberOfLights":1,"lights":[{"on":1}]}"#
    } else {
        r#"{"numberOfLights":1,"lights":[{"on":0}]}"#
    };
    let _ = reqwest::blocking::Client::new()
        .put(&url)
        .header("Content-Type", "application/json")
        .body(body)
        .send();
}

fn build_menu(app: &AppHandle, state: &AppState) -> tauri::Result<Menu<tauri::Wry>> {
    let connection_label = match &state.keylight_ip {
        Some(ip) => format!("Key Light: {}", ip),
        None => "Key Light: Not Found".to_string(),
    };
    let cam_label = if state.camera_active {
        "Camera: Active"
    } else {
        "Camera: Inactive"
    };
    let light_label = if state.light_on { "Light: ON" } else { "Light: OFF" };
    let auto_label = if state.auto_mode {
        "Auto Mode: ON  ✓"
    } else {
        "Auto Mode: OFF"
    };
    let toggle_label = if state.light_on { "Turn Light Off" } else { "Turn Light On" };
    let manual_enabled = state.keylight_ip.is_some();

    Menu::with_items(
        app,
        &[
            &MenuItem::with_id(app, "connection", connection_label, false, None::<&str>)?,
            &MenuItem::with_id(app, "cam_status", cam_label, false, None::<&str>)?,
            &MenuItem::with_id(app, "light_status", light_label, false, None::<&str>)?,
            &PredefinedMenuItem::separator(app)?,
            &MenuItem::with_id(app, "auto_mode", auto_label, true, None::<&str>)?,
            &MenuItem::with_id(app, "toggle_light", toggle_label, manual_enabled, None::<&str>)?,
            &PredefinedMenuItem::separator(app)?,
            &MenuItem::with_id(app, "settings", "Settings...", true, None::<&str>)?,
            &PredefinedMenuItem::separator(app)?,
            &MenuItem::with_id(app, "rediscover", "Rediscover Key Light", true, None::<&str>)?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::quit(app, None)?,
        ],
    )
}

fn update_tray(app: &AppHandle, state: &SharedState) {
    let snapshot = state.lock().unwrap().clone();
    if let Some(tray) = app.tray_by_id("main") {
        if let Ok(menu) = build_menu(app, &snapshot) {
            let _ = tray.set_menu(Some(menu));
        }
    }
}

fn open_settings_window(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("settings") {
        let _ = win.show();
        let _ = win.set_focus();
    } else {
        let _ = WebviewWindowBuilder::new(app, "settings", WebviewUrl::App("settings.html".into()))
            .title("KeyGlow Settings")
            .inner_size(440.0, 200.0)
            .resizable(false)
            .center()
            .build();
    }
}

fn start_camera_monitor(state: SharedState, app: AppHandle) {
    thread::spawn(move || {
        let mut child = match Command::new("log")
            .args([
                "stream",
                "--predicate",
                r#"subsystem == "com.apple.UVCExtension" AND category == "device""#,
            ])
            .stdout(Stdio::piped())
            .spawn()
        {
            Ok(c) => c,
            Err(e) => {
                eprintln!("[KeyGlow] Failed to start log stream: {}", e);
                return;
            }
        };

        let stdout = child.stdout.take().unwrap();
        let reader = BufReader::new(stdout);

        for line in reader.lines().flatten() {
            let camera_on = if line.contains("Start Stream") {
                true
            } else if line.contains("Stop Stream") {
                false
            } else {
                continue;
            };

            let (auto_mode, keylight_ip, current_light_on) = {
                let mut s = state.lock().unwrap();
                s.camera_active = camera_on;
                (s.auto_mode, s.keylight_ip.clone(), s.light_on)
            };

            if auto_mode {
                if let Some(ip) = keylight_ip {
                    if camera_on != current_light_on {
                        set_light(&ip, camera_on);
                        state.lock().unwrap().light_on = camera_on;
                        update_tray(&app, &state);
                    }
                }
            } else {
                update_tray(&app, &state);
            }
        }
    });
}

#[tauri::command]
fn get_settings(state: tauri::State<SharedState>) -> Settings {
    let s = state.lock().unwrap();
    Settings {
        keylight_mac: s.keylight_mac.clone(),
    }
}

#[tauri::command]
fn save_settings(app: AppHandle, state: tauri::State<SharedState>, mac: String) {
    persist_settings(&app, &Settings { keylight_mac: mac.clone() });
    let ip = discover_keylight(&mac);
    {
        let mut s = state.lock().unwrap();
        s.keylight_mac = mac;
        s.keylight_ip = ip;
    }
    update_tray(&app, state.inner());
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let state: SharedState = Arc::new(Mutex::new(AppState::default()));

    tauri::Builder::default()
        .manage(state.clone())
        .invoke_handler(tauri::generate_handler![get_settings, save_settings])
        .setup({
            let state = state.clone();
            move |app| {
                #[cfg(target_os = "macos")]
                app.set_activation_policy(tauri::ActivationPolicy::Accessory);

                // Load persisted settings
                let saved = load_settings(app.handle());
                {
                    let mut s = state.lock().unwrap();
                    s.keylight_mac = saved.keylight_mac.clone();
                }

                // Discover Key Light on startup
                {
                    let mut s = state.lock().unwrap();
                    s.keylight_ip = discover_keylight(&s.keylight_mac.clone());
                    if let Some(ref ip) = s.keylight_ip {
                        println!("[KeyGlow] Found Key Light at {}", ip);
                    } else {
                        println!("[KeyGlow] Key Light not found — use Rediscover or check Settings");
                    }
                }

                let initial_menu = build_menu(app.handle(), &state.lock().unwrap())?;

                TrayIconBuilder::with_id("main")
                    .icon(app.default_window_icon().unwrap().clone())
                    .icon_as_template(true)
                    .menu(&initial_menu)
                    .show_menu_on_left_click(true)
                    .on_menu_event({
                        let state = state.clone();
                        move |app, event| match event.id.as_ref() {
                            "auto_mode" => {
                                let mut s = state.lock().unwrap();
                                s.auto_mode = !s.auto_mode;
                                drop(s);
                                update_tray(app, &state);
                            }
                            "toggle_light" => {
                                let (ip, current_on) = {
                                    let s = state.lock().unwrap();
                                    (s.keylight_ip.clone(), s.light_on)
                                };
                                if let Some(ip) = ip {
                                    let new_on = !current_on;
                                    set_light(&ip, new_on);
                                    state.lock().unwrap().light_on = new_on;
                                    update_tray(app, &state);
                                }
                            }
                            "settings" => open_settings_window(app),
                            "rediscover" => {
                                let mac = state.lock().unwrap().keylight_mac.clone();
                                let ip = discover_keylight(&mac);
                                state.lock().unwrap().keylight_ip = ip;
                                update_tray(app, &state);
                            }
                            _ => {}
                        }
                    })
                    .build(app)?;

                start_camera_monitor(state.clone(), app.handle().clone());

                Ok(())
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
