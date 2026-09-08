use std::process::Stdio;

use offline_audio::engine::converter::convert_from_stdin;
use offline_audio::engine::models::ContentKind;
use tokio::io::AsyncWriteExt;

// Real ffmpeg integration smoke test. Skipped if ffmpeg is unavailable.
#[tokio::test]
async fn ffmpeg_streams_wav_to_opus() {
    if which::which("ffmpeg").is_err() {
        eprintln!("skipping: ffmpeg not installed");
        return;
    }
    let out = std::env::temp_dir().join(format!("oaa_int_{}.opus", std::process::id()));
    let mut ff = convert_from_stdin(&ContentKind::Music, &out, &Default::default()).unwrap();
    let mut child = ff
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let mut stdin = child.stdin.take().unwrap();
    stdin.write_all(&test_wav()).await.unwrap();
    drop(stdin);
    let out_buf = child.wait_with_output().await.unwrap();
    assert!(
        out_buf.status.success(),
        "ffmpeg failed: {}",
        String::from_utf8_lossy(&out_buf.stderr)
    );
    let size = std::fs::metadata(&out).map(|m| m.len()).unwrap_or(0);
    assert!(size > 0, "opus output empty");
    std::fs::remove_file(&out).ok();
}

fn test_wav() -> Vec<u8> {
    let sample_rate = 8000u32;
    let seconds = 1u32;
    let n = sample_rate * seconds;
    let mut data: Vec<u8> = Vec::with_capacity((44 + n * 2) as usize);
    data.extend_from_slice(b"RIFF");
    data.extend_from_slice(&((n * 2 + 36) as i32).to_le_bytes());
    data.extend_from_slice(b"WAVE");
    data.extend_from_slice(b"fmt ");
    data.extend_from_slice(&16i32.to_le_bytes());
    data.extend_from_slice(&1i16.to_le_bytes());
    data.extend_from_slice(&1i16.to_le_bytes());
    data.extend_from_slice(&sample_rate.to_le_bytes());
    data.extend_from_slice(&(sample_rate * 2).to_le_bytes());
    data.extend_from_slice(&2i16.to_le_bytes());
    data.extend_from_slice(&16i16.to_le_bytes());
    data.extend_from_slice(b"data");
    data.extend_from_slice(&(n * 2).to_le_bytes());
    for i in 0..n {
        let s = ((i as f32 / sample_rate as f32) * std::f32::consts::TAU * 440.0).sin() as i16;
        data.extend_from_slice(&s.to_le_bytes());
    }
    data
}
