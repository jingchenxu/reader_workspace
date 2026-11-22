#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
mod desktop;
use desktop::*;
use rusqlite::types::ValueRef;
use rusqlite::{Connection, OpenFlags};
use serde_json::{Map, Value};
use std::path::PathBuf;
use tauri::Manager;

fn library(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    Ok(app
        .path()
        .config_dir()
        .map_err(|e| e.to_string())?
        .join("epub-reader"))
}
#[tauri::command]
fn app_path(app: tauri::AppHandle) -> Result<String, String> {
    app.path()
        .resource_dir()
        .map(|p| p.to_string_lossy().into_owned())
        .map_err(|e| e.to_string())
}
#[tauri::command]
fn library_path(app: tauri::AppHandle) -> Result<String, String> {
    Ok(library(&app)?.to_string_lossy().into_owned())
}
fn connection(app: &tauri::AppHandle, write: bool) -> Result<Connection, String> {
    let path = library(app)?.join("db/epub_reader.db");
    Connection::open_with_flags(
        path,
        if write {
            OpenFlags::SQLITE_OPEN_READ_WRITE
        } else {
            OpenFlags::SQLITE_OPEN_READ_ONLY
        },
    )
    .map_err(|e| e.to_string())
}
#[tauri::command]
fn records(app: tauri::AppHandle, kind: String, id: Option<i64>) -> Result<Vec<Value>, String> {
    let conn = connection(&app, false)?;
    let sql=match kind.as_str(){
        "books"=>"SELECT * FROM books WHERE ?1 IS NULL OR category_id=?1 ORDER BY last_read_at DESC, added_at DESC",
        "categories"=>"SELECT * FROM categories WHERE ?1 IS NULL ORDER BY created_at",
        "progress"=>"SELECT * FROM reading_progress WHERE book_id=?1",
        "bookmarks"=>"SELECT * FROM bookmarks WHERE book_id=?1 ORDER BY created_at DESC",
        "annotations"=>"SELECT * FROM annotations WHERE book_id=?1 ORDER BY created_at DESC",
        _=>return Err("Unknown collection".into())
    };
    let mut stmt = conn.prepare(sql).map_err(|e| e.to_string())?;
    let names: Vec<String> = stmt.column_names().iter().map(|n| n.to_string()).collect();
    let rows = stmt
        .query_map([id], |r| {
            let mut obj = Map::new();
            for (i, name) in names.iter().enumerate() {
                let v = match r.get_ref(i)? {
                    ValueRef::Integer(n) => Value::from(n),
                    ValueRef::Real(n) => Value::from(n),
                    ValueRef::Text(s) => Value::from(String::from_utf8_lossy(s).as_ref()),
                    _ => Value::Null,
                };
                obj.insert(name.clone(), v);
            }
            Ok(Value::Object(obj))
        })
        .map_err(|e| e.to_string())?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())
}
#[tauri::command]
fn save_progress(
    app: tauri::AppHandle,
    id: i64,
    cfi: String,
    page: Option<i64>,
    percentage: Option<f64>,
) -> Result<(), String> {
    let mut conn = connection(&app, true)?;
    let tx = conn.transaction().map_err(|e| e.to_string())?;
    tx.execute("INSERT INTO reading_progress(book_id,cfi,page,percentage) VALUES(?,?,?,?) ON CONFLICT(book_id) DO UPDATE SET cfi=excluded.cfi,page=excluded.page,percentage=excluded.percentage,updated_at=CURRENT_TIMESTAMP",rusqlite::params![id,cfi,page,percentage]).map_err(|e|e.to_string())?;
    tx.execute(
        "UPDATE books SET last_read_at=CURRENT_TIMESTAMP WHERE id=?",
        [id],
    )
    .map_err(|e| e.to_string())?;
    tx.commit().map_err(|e| e.to_string())
}
#[tauri::command]
fn add_bookmark(
    app: tauri::AppHandle,
    book_id: i64,
    cfi: String,
    title: String,
    note: Option<String>,
) -> Result<i64, String> {
    let conn = connection(&app, true)?;
    conn.execute(
        "INSERT INTO bookmarks(book_id,cfi,title,note) VALUES(?,?,?,?)",
        rusqlite::params![book_id, cfi, title, note],
    )
    .map_err(|e| e.to_string())?;
    Ok(conn.last_insert_rowid())
}
#[tauri::command]
fn delete_bookmark(app: tauri::AppHandle, id: i64) -> Result<(), String> {
    connection(&app, true)?
        .execute("DELETE FROM bookmarks WHERE id=?", [id])
        .map_err(|e| e.to_string())?;
    Ok(())
}
#[tauri::command]
fn save_annotation(
    app: tauri::AppHandle,
    book_id: i64,
    cfi: String,
    selected_text: String,
    annotation: String,
    color: String,
) -> Result<i64, String> {
    let conn = connection(&app, true)?;
    conn.execute(
        "INSERT INTO annotations(book_id,cfi,selected_text,annotation,color) VALUES(?,?,?,?,?)",
        rusqlite::params![book_id, cfi, selected_text, annotation, color],
    )
    .map_err(|e| e.to_string())?;
    Ok(conn.last_insert_rowid())
}
fn main() {
    tauri::Builder::default()
        .setup(|app| {
            if let Some(window) = app.get_webview_window("main") {
                match_window_bounds(&window)?;
            }
            initialize(app.handle()).map_err(std::io::Error::other)?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            app_path,
            library_path,
            records,
            save_progress,
            add_bookmark,
            delete_bookmark,
            save_annotation,
            desktop_action,
            open_reader,
            import_book,
            export_file,
            choose_directory
        ])
        .run(tauri::generate_context!())
        .expect("Failed to launch reader");
}
