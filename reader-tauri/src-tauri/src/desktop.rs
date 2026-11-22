use super::{connection, library};
use base64::{engine::general_purpose::STANDARD, Engine};
use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    fs,
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
};
use tauri::{AppHandle, Manager, WebviewUrl, WebviewWindowBuilder};

type Result<T> = std::result::Result<T, String>;
fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}

pub fn initialize(app: &AppHandle) -> Result<()> {
    let root = library(app)?;
    fs::create_dir_all(root.join("db")).map_err(err)?;
    let mut db = Connection::open(root.join("db/epub_reader.db")).map_err(err)?;
    db.busy_timeout(std::time::Duration::from_secs(5))
        .map_err(err)?;
    db.execute_batch("PRAGMA journal_mode=WAL").map_err(err)?;
    let tx = db.transaction().map_err(err)?;
    tx.execute_batch(include_str!("schema.sql")).map_err(err)?;
    for (name, spec) in [
        ("file_hash", "TEXT"),
        (
            "category_id",
            "INTEGER REFERENCES categories(id) ON DELETE SET NULL",
        ),
    ] {
        let present: bool = tx
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM pragma_table_info('books') WHERE name=?)",
                [name],
                |r| r.get(0),
            )
            .map_err(err)?;
        if !present {
            tx.execute_batch(&format!("ALTER TABLE books ADD COLUMN {name} {spec}"))
                .map_err(err)?;
        }
    }
    tx.execute_batch("CREATE INDEX IF NOT EXISTS idx_books_file_hash ON books(file_hash); CREATE INDEX IF NOT EXISTS idx_reading_progress_book_id ON reading_progress(book_id)").map_err(err)?;
    tx.commit().map_err(err)?;
    retry_cleanup(&mut db, &root)?;
    let mut missing = db
        .prepare("SELECT id,book_path FROM books WHERE file_hash IS NULL OR file_hash=''")
        .map_err(err)?;
    let books = missing
        .query_map([], |row| {
            Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?))
        })
        .map_err(err)?;
    for book in books {
        let (id, relative) = book.map_err(err)?;
        if let Ok(path) = managed(&root, &relative) {
            let mut digest = Sha256::new();
            // An unavailable legacy EPUB must not prevent the rest of the library opening.
            let Ok(mut file) = fs::File::open(path) else {
                continue;
            };
            if std::io::copy(&mut file, &mut digest).is_err() {
                continue;
            }
            db.execute(
                "UPDATE books SET file_hash=? WHERE id=? AND (file_hash IS NULL OR file_hash='')",
                params![format!("{:x}", digest.finalize()), id],
            )
            .map_err(err)?;
        }
    }
    Ok(())
}
fn managed(root: &Path, relative: &str) -> Result<PathBuf> {
    let path = root.join(relative).canonicalize().map_err(err)?;
    if !path.starts_with(root.join("upload").canonicalize().map_err(err)?) {
        return Err("无效的书库路径".into());
    }
    Ok(path)
}
// Keep failed file removals durable and serialize cleanup against re-imports.
fn retry_cleanup(db: &mut Connection, root: &Path) -> Result<()> {
    let tx = db
        .transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)
        .map_err(err)?;
    let mut stmt = tx
        .prepare("SELECT path FROM pending_file_cleanup")
        .map_err(err)?;
    let pending = stmt
        .query_map([], |r| r.get::<_, String>(0))
        .map_err(err)?
        .collect::<rusqlite::Result<Vec<_>>>()
        .map_err(err)?;
    drop(stmt);
    for path in pending {
        let used:bool=tx.query_row("SELECT EXISTS(SELECT 1 FROM books WHERE replace(book_path,char(92),'/')=replace(?1,char(92),'/') COLLATE NOCASE OR replace(cover_path,char(92),'/')=replace(?1,char(92),'/') COLLATE NOCASE)",[&path],|r|r.get(0)).map_err(err)?;
        if !used {
            match fs::symlink_metadata(root.join(&path)) {
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                Ok(_) => {
                    let Ok(_) = managed(root, &path) else {
                        continue;
                    };
                    if fs::remove_file(root.join(&path)).is_err() {
                        continue;
                    }
                }
                Err(_) => continue,
            }
        }
        tx.execute("DELETE FROM pending_file_cleanup WHERE path=?", [path])
            .map_err(err)?;
    }
    tx.commit().map_err(err)
}
fn size(path: &Path) -> u64 {
    match fs::symlink_metadata(path) {
        Ok(m) if m.is_dir() => fs::read_dir(path)
            .into_iter()
            .flatten()
            .flatten()
            .map(|e| size(&e.path()))
            .sum(),
        Ok(m) if m.is_file() => m.len(),
        _ => 0,
    }
}
#[tauri::command]
pub fn desktop_action(app: AppHandle, action: String, data: Value) -> Result<Value> {
    let root = library(&app)?;
    let mut db = connection(&app, true)?;
    db.execute_batch("PRAGMA foreign_keys=ON").map_err(err)?;
    let id = data.get("id").and_then(Value::as_i64);
    let name = data["name"].as_str().unwrap_or("").trim();
    let color = data["color"].as_str().unwrap_or("#667eea");
    match action.as_str() {
        "addCategory" => {
            db.execute(
                "INSERT INTO categories(name,color) VALUES(?,?)",
                params![name, color],
            )
            .map_err(err)?;
            Ok(json!({"id":db.last_insert_rowid(),"name":name,"color":color}))
        }
        "updateCategory" => {
            if name.is_empty() {
                return Err("分类名称不能为空".into());
            }
            let n = db
                .execute(
                    "UPDATE categories SET name=?,color=? WHERE id=?",
                    params![name, color, id],
                )
                .map_err(err)?;
            Ok(json!({"success":n>0,"category":{"id":id,"name":name,"color":color}}))
        }
        "deleteCategory" => {
            let tx = db.transaction().map_err(err)?;
            tx.execute(
                "UPDATE books SET category_id=NULL WHERE category_id=?",
                [id],
            )
            .map_err(err)?;
            let n = tx
                .execute("DELETE FROM categories WHERE id=?", [id])
                .map_err(err)?;
            tx.commit().map_err(err)?;
            Ok(json!({"success":n>0}))
        }
        "updateBookCategory" => Ok(json!(
            db.execute(
                "UPDATE books SET category_id=? WHERE id=?",
                params![data["categoryId"].as_i64(), id]
            )
            .map_err(err)?
                > 0
        )),
        "deleteAnnotation" => Ok(json!(
            db.execute("DELETE FROM annotations WHERE id=?", [id])
                .map_err(err)?
                > 0
        )),
        "deleteBook" | "deleteBookCompletely" => {
            let tx = db
                .transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)
                .map_err(err)?;
            if action == "deleteBookCompletely" {
                tx.execute("INSERT OR IGNORE INTO pending_file_cleanup(path) SELECT book_path FROM books WHERE id=?1 UNION SELECT cover_path FROM books WHERE id=?1 AND cover_path IS NOT NULL AND cover_path!=''",[id]).map_err(err)?;
            }
            let removed = tx
                .execute("DELETE FROM books WHERE id=?", [id])
                .map_err(err)?;
            tx.commit().map_err(err)?;
            if action == "deleteBook" {
                return Ok(json!(removed > 0));
            }
            retry_cleanup(&mut db, &root)?;
            Ok(json!({"success":removed>0}))
        }
        "readBookFile" => {
            let p = data["bookPath"].as_str().ok_or("缺少文件路径")?;
            let known: bool = db
                .query_row(
                    "SELECT EXISTS(SELECT 1 FROM books WHERE book_path=?)",
                    [p],
                    |r| r.get(0),
                )
                .map_err(err)?;
            if !known {
                return Err("书籍不存在".into());
            }
            let path = managed(&root, p)?;
            let bytes = fs::read(&path).map_err(err)?;
            Ok(
                json!({"success":true,"base64":STANDARD.encode(&bytes),"fileName":path.file_name().unwrap().to_string_lossy(),"size":bytes.len()}),
            )
        }
        "getStorageInfo" => Ok(
            json!({"savePath":root,"booksSize":size(&root.join("upload")),"diskFree":fs2::available_space(&root).map_err(err)?,"cacheSize":size(&root.join("db"))}),
        ),
        "clearCache" => {
            let wal = root.join("db/epub_reader.db-wal");
            let before = size(&wal);
            let busy: i64 = db
                .query_row("PRAGMA wal_checkpoint(TRUNCATE)", [], |r| r.get(0))
                .map_err(err)?;
            Ok(json!({"success":busy==0,"clearedSize":before.saturating_sub(size(&wal))}))
        }
        _ => Err("未知操作".into()),
    }
}

// Electron BrowserWindow sizes include the native frame; Tauri's set_size uses the client area.
pub fn match_window_bounds(window: &tauri::WebviewWindow) -> tauri::Result<()> {
    let scale = window.scale_factor()?;
    let outer = window.outer_size()?;
    let inner = window.inner_size()?;
    let width = (1200.0 * scale).round() as u32;
    let height = (800.0 * scale).round() as u32;
    window.set_size(tauri::PhysicalSize::new(
        width.saturating_sub(outer.width.saturating_sub(inner.width)),
        height.saturating_sub(outer.height.saturating_sub(inner.height)),
    ))
}
#[tauri::command]
pub async fn open_reader(app: AppHandle, id: i64) -> Result<bool> {
    let db = connection(&app, false)?;
    let (title, path): (String, String) = db
        .query_row("SELECT title,book_path FROM books WHERE id=?", [id], |r| {
            Ok((r.get(0)?, r.get(1)?))
        })
        .map_err(err)?;
    let mut url = app
        .get_webview_window("main")
        .ok_or("未找到书架窗口")?
        .url()
        .map_err(err)?;
    url.set_query(None);
    url.query_pairs_mut()
        .append_pair("bookId", &id.to_string())
        .append_pair("bookTitle", &title)
        .append_pair("bookPath", &path);
    static SERIAL: AtomicU64 = AtomicU64::new(0);
    let window = WebviewWindowBuilder::new(
        &app,
        format!("reader-{}", SERIAL.fetch_add(1, Ordering::Relaxed)),
        WebviewUrl::External(url),
    )
    .title(title)
    .inner_size(1200., 800.)
    .build()
    .map_err(err)?;
    match_window_bounds(&window).map_err(err)?;
    Ok(true)
}
#[tauri::command]
pub async fn choose_directory() -> Result<Value> {
    Ok(
        match rfd::AsyncFileDialog::new()
            .set_title("选择文件保存位置")
            .pick_folder()
            .await
        {
            Some(f) => json!({"success":true,"path":f.path()}),
            None => json!({"success":false}),
        },
    )
}
#[tauri::command]
pub async fn export_file(app: AppHandle, id: i64, notes: Option<String>) -> Result<Value> {
    let (title, relative): (String, String) = connection(&app, false)?
        .query_row("SELECT title,book_path FROM books WHERE id=?", [id], |r| {
            Ok((r.get(0)?, r.get(1)?))
        })
        .map_err(err)?;
    let title = title.replace(['/', '\\', ':', '*', '?', '"', '<', '>', '|'], "_");
    let dialog = rfd::AsyncFileDialog::new();
    let dialog = if notes.is_some() {
        dialog
            .add_filter("Text Files", &["txt"])
            .set_file_name(format!("{title}_笔记.txt"))
    } else {
        dialog
            .add_filter("EPUB Files", &["epub"])
            .set_file_name(format!("{title}.epub"))
    };
    let Some(file) = dialog.save_file().await else {
        return Ok(json!({"success":false,"error":"Cancelled"}));
    };
    // Stage exports in the destination directory, including exports onto the source file.
    let parent = file.path().parent().ok_or("导出目录不存在")?;
    let mut tmp = tempfile::NamedTempFile::new_in(parent).map_err(err)?;
    if let Some(text) = notes {
        std::io::Write::write_all(tmp.as_file_mut(), text.as_bytes()).map_err(err)?;
    } else {
        let mut source = fs::File::open(managed(&library(&app)?, &relative)?).map_err(err)?;
        std::io::copy(&mut source, tmp.as_file_mut()).map_err(err)?;
    }
    tmp.as_file().sync_all().map_err(err)?;
    tmp.persist(file.path()).map_err(err)?;
    Ok(json!({"success":true,"path":file.path()}))
}
#[tauri::command]
pub async fn import_book(
    app: AppHandle,
    metadata: Value,
    content: String,
    cover: Option<String>,
    extension: Option<String>,
) -> Result<Value> {
    let bytes = STANDARD.decode(content).map_err(err)?;
    let hash = format!("{:x}", Sha256::digest(&bytes));
    let mut db = connection(&app, true)?;
    let tx = db
        .transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)
        .map_err(err)?;
    let existing: Option<i64> = tx
        .query_row("SELECT id FROM books WHERE file_hash=?", [&hash], |r| {
            r.get(0)
        })
        .optional()
        .map_err(err)?;
    if let Some(id) = existing {
        return Ok(json!({"existing":true,"id":id}));
    }
    let root = library(&app)?;
    // TempPath removes both files on early return. Unique names also isolate concurrent imports.
    let stage =
        |directory: &str, suffix: &str, data: &[u8]| -> Result<(String, tempfile::TempPath)> {
            let dir = root.join(directory);
            fs::create_dir_all(&dir).map_err(err)?;
            let mut file = tempfile::Builder::new()
                .prefix("book_")
                .suffix(suffix)
                .tempfile_in(dir)
                .map_err(err)?;
            std::io::Write::write_all(file.as_file_mut(), data).map_err(err)?;
            file.as_file().sync_all().map_err(err)?;
            let path = file.into_temp_path();
            let relative = format!(
                "{directory}/{}",
                path.file_name().ok_or("缺少文件名")?.to_string_lossy()
            );
            Ok((relative, path))
        };
    let (relative, mut book_file) = stage("upload/books", ".epub", &bytes)?;
    let ext = extension.as_deref().unwrap_or("");
    let cover_file = match cover {
        Some(data) if matches!(ext, "png" | "jpg" | "gif" | "webp" | "svg") => Some(stage(
            "upload/covers",
            &format!(".{ext}"),
            &STANDARD.decode(data).map_err(err)?,
        )?),
        _ => None,
    };
    let cover_path = cover_file.as_ref().map(|(name, _)| name);
    let field = |key: &str| metadata.get(key).and_then(Value::as_str);
    tx.execute("INSERT INTO books(title,author,publisher,isbn,pub_date,language,description,cover_path,book_path,file_hash) VALUES(?,?,?,?,?,?,?,?,?,?)",params![field("title"),field("author"),field("publisher"),field("isbn"),field("pubDate"),field("language"),field("description"),cover_path,relative,hash]).map_err(err)?;
    let id = tx.last_insert_rowid();
    tx.commit().map_err(err)?;
    book_file.disable_cleanup(true);
    if let Some((_, mut file)) = cover_file {
        file.disable_cleanup(true);
    }
    Ok(json!({"existing":false,"id":id}))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn pending_cleanup_preserves_shared_books_and_retries_failures() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        fs::create_dir_all(root.join("upload/locked")).unwrap();
        fs::write(root.join("upload/shared"), b"book").unwrap();
        fs::write(root.join("upload/removed"), b"remove").unwrap();
        let mut db = Connection::open_in_memory().unwrap();
        db.execute_batch(include_str!("schema.sql")).unwrap();
        db.execute(
            "INSERT INTO books(title,book_path) VALUES('shared','upload/shared')",
            [],
        )
        .unwrap();
        for path in [
            "upload/shared",
            "upload/removed",
            "upload/locked",
            "upload/missing",
        ] {
            db.execute("INSERT INTO pending_file_cleanup VALUES(?)", [path])
                .unwrap();
        }
        retry_cleanup(&mut db, root).unwrap();
        assert!(root.join("upload/shared").exists());
        assert!(!root.join("upload/removed").exists());
        assert_eq!(
            db.query_row("SELECT path FROM pending_file_cleanup", [], |r| r
                .get::<_, String>(0))
                .unwrap(),
            "upload/locked"
        );
        fs::remove_dir(root.join("upload/locked")).unwrap();
        fs::write(root.join("upload/locked"), b"retry").unwrap();
        retry_cleanup(&mut db, root).unwrap();
        assert!(!root.join("upload/locked").exists());
    }
}
