use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use tauri::{
    ipc::{InvokeBody, Request},
    State,
};

use crate::app_state::AppState;

use super::{
    media::{upload_media_bytes_inner, BlobDescriptor},
    media_upload_progress::{
        begin_media_upload, cancel_media_upload as cancel_registered_media_upload,
        finish_media_upload,
    },
};

/// Upload raw bytes directly (for paste and drag-drop).
///
/// The renderer already has the bytes in memory from the clipboard/drag event.
/// If the bytes are a video, they're written to a temp file, transcoded via
/// ffmpeg, and the transcoded output is uploaded instead.
#[tauri::command]
pub async fn upload_media_bytes(
    data: Vec<u8>,
    filename: Option<String>,
    progress_id: Option<String>,
    app: tauri::AppHandle,
    state: State<'_, AppState>,
) -> Result<BlobDescriptor, String> {
    let cancellation = begin_media_upload(progress_id.as_deref());
    let result = upload_media_bytes_inner(
        data,
        filename,
        progress_id.clone(),
        app,
        state,
        cancellation.as_ref(),
    )
    .await;
    finish_media_upload(progress_id.as_deref());
    result
}

fn decode_raw_upload_header(value: &str) -> Result<String, String> {
    let bytes = URL_SAFE_NO_PAD
        .decode(value)
        .map_err(|error| format!("invalid raw upload header: {error}"))?;
    String::from_utf8(bytes).map_err(|error| format!("invalid raw upload header text: {error}"))
}

fn optional_raw_upload_header(request: &Request<'_>, name: &str) -> Result<Option<String>, String> {
    request
        .headers()
        .get(name)
        .map(|value| {
            value
                .to_str()
                .map_err(|error| format!("invalid {name} header: {error}"))
                .and_then(decode_raw_upload_header)
        })
        .transpose()
}

/// Cancel the native upload associated with a background progress ID.
#[tauri::command]
pub fn cancel_media_upload(progress_id: String) {
    cancel_registered_media_upload(&progress_id);
}

/// Release the renderer's ownership after its upload promise settles.
#[tauri::command]
pub fn release_media_upload(progress_id: String) {
    finish_media_upload(Some(&progress_id));
}

/// Recover raw bytes from a JSON IPC body.
///
/// The renderer sends the file as a byte body, but if the webview's IPC
/// transport degrades from the custom protocol (raw-capable) to the
/// postMessage fallback — a sticky downgrade that happens after a single
/// custom-protocol failure, e.g. AV/VPN interception of `ipc.localhost` —
/// the same payload arrives JSON-serialized as a number array. Accept that
/// shape so uploads keep working on the degraded transport; the raw fast
/// path is untouched while it works.
fn bytes_from_json_body(value: &serde_json::Value) -> Result<Vec<u8>, String> {
    let serde_json::Value::Array(items) = value else {
        return Err("raw upload requires a byte body".to_string());
    };
    let mut data = Vec::with_capacity(items.len());
    for item in items {
        let byte = item
            .as_u64()
            .filter(|n| *n <= u64::from(u8::MAX))
            .ok_or("raw upload body is not a byte array")?;
        data.push(byte as u8);
    }
    Ok(data)
}

/// Upload raw IPC bytes without expanding a large browser File into JSON.
#[tauri::command]
pub async fn upload_media_bytes_raw(
    request: Request<'_>,
    app: tauri::AppHandle,
    state: State<'_, AppState>,
) -> Result<BlobDescriptor, String> {
    let data = match request.body() {
        InvokeBody::Raw(data) => data.clone(),
        InvokeBody::Json(value) => bytes_from_json_body(value)?,
    };
    let filename = optional_raw_upload_header(&request, "x-buzz-filename")?;
    let progress_id = optional_raw_upload_header(&request, "x-buzz-progress-id")?;

    let cancellation = begin_media_upload(progress_id.as_deref());
    let result = upload_media_bytes_inner(
        data,
        filename,
        progress_id.clone(),
        app,
        state,
        cancellation.as_ref(),
    )
    .await;
    finish_media_upload(progress_id.as_deref());
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_decode_raw_upload_header_preserves_unicode() {
        let encoded = URL_SAFE_NO_PAD.encode("clip 🎬.mp4");
        assert_eq!(decode_raw_upload_header(&encoded).unwrap(), "clip 🎬.mp4");
    }

    #[test]
    fn test_bytes_from_json_body_recovers_byte_array() {
        let value = serde_json::json!([7, 255, 0, 128]);
        assert_eq!(bytes_from_json_body(&value).unwrap(), vec![7, 255, 0, 128]);
    }

    #[test]
    fn test_bytes_from_json_body_rejects_non_byte_numbers() {
        assert!(bytes_from_json_body(&serde_json::json!([7, 256])).is_err());
        assert!(bytes_from_json_body(&serde_json::json!([7, -1])).is_err());
    }

    #[test]
    fn test_bytes_from_json_body_rejects_non_array_bodies() {
        assert!(bytes_from_json_body(&serde_json::json!({"data": [1]})).is_err());
        assert!(bytes_from_json_body(&serde_json::json!(null)).is_err());
    }
}
