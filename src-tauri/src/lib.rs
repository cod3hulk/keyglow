use std::{
    io::{BufRead, BufReader},
    process::{Command, Stdio},
    sync::{Arc, Mutex},
    thread,
};

use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::TrayIconBuilder,
    AppHandle,
};

const KEYLIGHT_MAC: &str = "3c:6a:9d:2d:2e:68";
const KEYLIGHT_PORT: u16 = 9123;

#[derive(Clone, Default)]
struct AppState {
    keylight_ip: Option<String>,
    light_on: bool,
    auto_mode: bool,
    camera_active: bool,
}

type SharedState = Arc<Mutex<AppState>>;

fn discover_keylight() -> Option<String> {
    let output = Command::new("arp").arg("-an").output().ok()?;
    let text = String::from_utf8_lossy(&output.stdout);

    for line in text.lines() {
        if line.to_lowercase().contains(KEYLIGHT_MAC) {
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
    let light_label = if state.light_on {
        "Light: ON"
    } else {
        "Light: OFF"
    };
    let auto_label = if state.auto_mode {
        "Auto Mode: ON  ✓"
    } else {
        "Auto Mode: OFF"
    };
    let toggle_label = if state.light_on {
        "Turn Light Off"
    } else {
        "Turn Light On"
    };
    let manual_enabled = state.keylight_ip.is_some();

    Menu::with_items(
        app,
        &[
            &MenuItem::with_id(app, "connection", connection_label, false, None::<&str>)?,
            &MenuItem::with_id(app, "cam_status", cam_label, false, None::<&str>)?,
            &MenuItem::with_id(app, "light_status", light_label, false, None::<&str>)?,
            &PredefinedMenuItem::separator(app)?,
            &MenuItem::with_id(app, "auto_mode", auto_label, true, None::<&str>)?,
            &MenuItem::with_id(
                app,
                "toggle_light",
                toggle_label,
                manual_enabled,
                None::<&str>,
            )?,
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

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let state: SharedState = Arc::new(Mutex::new(AppState {
        auto_mode: true,
        ..Default::default()
    }));

    tauri::Builder::default()
        .setup({
            let state = state.clone();
            move |app| {
                #[cfg(target_os = "macos")]
                app.set_activation_policy(tauri::ActivationPolicy::Accessory);

                // Discover Key Light on startup
                {
                    let mut s = state.lock().unwrap();
                    s.keylight_ip = discover_keylight();
                    if let Some(ref ip) = s.keylight_ip {
                        println!("[KeyGlow] Found Key Light at {}", ip);
                    } else {
                        println!("[KeyGlow] Key Light not found — will retry on Rediscover");
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
                            "rediscover" => {
                                let ip = discover_keylight();
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
