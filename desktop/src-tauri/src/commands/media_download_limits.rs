//! Transfer and decoded-image limits for media downloads.

/// Matches the relay's generic-file upload cap so every accepted upload can be
/// downloaded again.
pub(super) const MAX_DOWNLOAD_BYTES: u64 = 100 * 1024 * 1024;

/// Bounds decoded RGBA buffers independently from the transfer cap.
pub(super) const MAX_CLIPBOARD_IMAGE_BYTES: u64 = 50 * 1024 * 1024;

#[cfg(test)]
mod tests {
    use super::{MAX_CLIPBOARD_IMAGE_BYTES, MAX_DOWNLOAD_BYTES};

    #[test]
    fn download_cap_matches_relay_file_upload_cap() {
        assert_eq!(MAX_DOWNLOAD_BYTES, 104_857_600);
    }

    #[test]
    fn clipboard_image_cap_is_independent_of_download_cap() {
        assert_eq!(MAX_CLIPBOARD_IMAGE_BYTES, 52_428_800);
        const { assert!(MAX_CLIPBOARD_IMAGE_BYTES < MAX_DOWNLOAD_BYTES) };
    }
}
