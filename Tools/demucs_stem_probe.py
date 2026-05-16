#!/usr/bin/env python3
"""
Offline stem probe for instrument-label experiments.

Pipeline:
1. Optionally run Demucs htdemucs_6s on an input audio file.
2. Find bass/guitar stems.
3. Export global and frame-level RMS/spectral metrics for calibration.

Install example:
    python3 -m pip install -U demucs soundfile numpy

Usage example:
    python3 Tools/demucs_stem_probe.py "song.mp3" --out build/stem_probe
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import shutil
import subprocess
import sys
import wave
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple


TARGET_STEMS = ("bass", "guitar")
np = None
sf = None


def load_analysis_dependencies() -> None:
    global np, sf
    try:
        import numpy as numpy_module
    except ImportError as exc:
        raise SystemExit(
            "Missing dependency: numpy. Install with:\n"
            "  python3 -m pip install -U numpy demucs soundfile"
        ) from exc

    try:
        import soundfile as soundfile_module
    except ImportError:
        soundfile_module = None

    np = numpy_module
    sf = soundfile_module


def dbfs(value: float) -> float:
    return 20.0 * math.log10(max(value, 1e-12))


def sanitize_track_name(audio_path: Path) -> str:
    return audio_path.stem


def run_demucs(audio_path: Path, out_dir: Path, model: str) -> Path:
    demucs_bin = shutil.which("demucs")
    if demucs_bin:
        cmd = [demucs_bin, "-n", model, "-o", str(out_dir), str(audio_path)]
    else:
        cmd = [sys.executable, "-m", "demucs", "-n", model, "-o", str(out_dir), str(audio_path)]

    print("Running:", " ".join(cmd))
    subprocess.run(cmd, check=True)
    return out_dir / model / sanitize_track_name(audio_path)


def read_audio(path: Path) -> Tuple[int, np.ndarray]:
    if sf is not None:
        data, sample_rate = sf.read(str(path), always_2d=True, dtype="float32")
        mono = data.mean(axis=1)
        return sample_rate, mono.astype(np.float32, copy=False)

    if path.suffix.lower() != ".wav":
        raise RuntimeError("Install soundfile to read non-WAV files.")

    sample_rate, data = read_pcm_wav(path)
    mono = data.mean(axis=1)
    return sample_rate, mono.astype(np.float32, copy=False)


def read_pcm_wav(path: Path) -> Tuple[int, np.ndarray]:
    with wave.open(str(path), "rb") as wav:
        channels = wav.getnchannels()
        sample_rate = wav.getframerate()
        sample_width = wav.getsampwidth()
        frames = wav.readframes(wav.getnframes())

    if sample_width == 1:
        raw = np.frombuffer(frames, dtype=np.uint8).astype(np.float32)
        audio = (raw - 128.0) / 128.0
    elif sample_width == 2:
        audio = np.frombuffer(frames, dtype="<i2").astype(np.float32) / 32768.0
    elif sample_width == 3:
        raw = np.frombuffer(frames, dtype=np.uint8).reshape(-1, 3)
        values = (raw[:, 0].astype(np.int32) |
                  (raw[:, 1].astype(np.int32) << 8) |
                  (raw[:, 2].astype(np.int32) << 16))
        values = np.where(values & 0x800000, values | ~0xFFFFFF, values)
        audio = values.astype(np.float32) / 8388608.0
    elif sample_width == 4:
        audio = np.frombuffer(frames, dtype="<i4").astype(np.float32) / 2147483648.0
    else:
        raise RuntimeError(f"Unsupported WAV sample width: {sample_width}")

    return sample_rate, audio.reshape(-1, channels)


def band_energies(frame: np.ndarray, sample_rate: int) -> Dict[str, float]:
    if frame.size == 0:
        return {
            "low_rms": 0.0,
            "low_mid_rms": 0.0,
            "mid_rms": 0.0,
            "high_rms": 0.0,
            "centroid_hz": 0.0,
        }

    windowed = frame * np.hanning(frame.size)
    spectrum = np.abs(np.fft.rfft(windowed))
    freqs = np.fft.rfftfreq(frame.size, 1.0 / sample_rate)
    power = spectrum * spectrum
    if power.size > 2:
        power[1:-1] *= 2.0
    total_power = float(power.sum())

    def band_rms(lo: float, hi: float) -> float:
        mask = (freqs >= lo) & (freqs < hi)
        if not np.any(mask):
            return 0.0
        return float(math.sqrt(float(power[mask].sum())) / max(frame.size, 1))

    centroid = float((freqs * power).sum() / max(total_power, 1e-12))
    return {
        "low_rms": band_rms(20.0, 120.0),
        "low_mid_rms": band_rms(120.0, 500.0),
        "mid_rms": band_rms(500.0, 4000.0),
        "high_rms": band_rms(4000.0, min(16000.0, sample_rate / 2.0)),
        "centroid_hz": centroid,
    }


def global_metrics(audio: np.ndarray, sample_rate: int) -> Dict[str, float]:
    rms = float(np.sqrt(np.mean(audio * audio))) if audio.size else 0.0
    peak = float(np.max(np.abs(audio))) if audio.size else 0.0
    bands = band_energies(audio[: min(audio.size, sample_rate * 30)], sample_rate)
    return {
        "duration_sec": float(audio.size / sample_rate) if sample_rate else 0.0,
        "rms": rms,
        "rms_dbfs": dbfs(rms),
        "peak": peak,
        "peak_dbfs": dbfs(peak),
        "crest_db": dbfs(peak) - dbfs(rms) if rms > 0.0 else 0.0,
        **bands,
    }


def iter_frames(audio: np.ndarray, frame_size: int, hop_size: int) -> Iterable[Tuple[int, np.ndarray]]:
    if audio.size < frame_size:
        padded = np.zeros(frame_size, dtype=np.float32)
        padded[: audio.size] = audio
        yield 0, padded
        return

    for start in range(0, audio.size - frame_size + 1, hop_size):
        yield start, audio[start : start + frame_size]


def analyze_stem(
    stem_name: str,
    stem_audio: np.ndarray,
    mix_audio: Optional[np.ndarray],
    sample_rate: int,
    frame_ms: float,
    hop_ms: float,
) -> Tuple[Dict[str, float], List[Dict[str, float]]]:
    frame_size = max(256, int(sample_rate * frame_ms / 1000.0))
    hop_size = max(128, int(sample_rate * hop_ms / 1000.0))
    summary = global_metrics(stem_audio, sample_rate)
    rows: List[Dict[str, float]] = []

    for start, frame in iter_frames(stem_audio, frame_size, hop_size):
        rms = float(np.sqrt(np.mean(frame * frame))) if frame.size else 0.0
        row = {
            "stem": stem_name,
            "time_sec": float(start / sample_rate),
            "rms": rms,
            "rms_dbfs": dbfs(rms),
        }
        row.update(band_energies(frame, sample_rate))

        if mix_audio is not None and mix_audio.size:
            mix_frame = np.zeros(frame_size, dtype=np.float32)
            available = max(0, min(frame_size, mix_audio.size - start))
            if available > 0:
                mix_frame[:available] = mix_audio[start : start + available]
            mix_rms = float(np.sqrt(np.mean(mix_frame * mix_frame))) if mix_frame.size else 0.0
            row["mix_rms"] = mix_rms
            row["ratio_to_mix"] = rms / max(mix_rms, 1e-9)
            row["ratio_to_mix_db"] = dbfs(row["ratio_to_mix"])
        rows.append(row)

    return summary, rows


def find_stem_file(separated_dir: Path, stem: str) -> Optional[Path]:
    candidates = [
        separated_dir / f"{stem}.wav",
        separated_dir / f"{stem}.flac",
        separated_dir / f"{stem}.mp3",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    matches = sorted(separated_dir.rglob(f"{stem}.*"))
    return matches[0] if matches else None


def write_csv(path: Path, rows: List[Dict[str, float]]) -> None:
    fieldnames = [
        "stem",
        "time_sec",
        "rms",
        "rms_dbfs",
        "mix_rms",
        "ratio_to_mix",
        "ratio_to_mix_db",
        "low_rms",
        "low_mid_rms",
        "mid_rms",
        "high_rms",
        "centroid_hz",
    ]
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run Demucs and analyze bass/guitar stem energy.")
    parser.add_argument("audio", type=Path, nargs="?", help="Input audio file. Can be omitted only with --separated-dir.")
    parser.add_argument("--out", type=Path, default=Path("build/stem_probe"), help="Output directory.")
    parser.add_argument("--model", default="htdemucs_6s", help="Demucs model name.")
    parser.add_argument("--separated-dir", type=Path, help="Existing Demucs track directory containing bass.wav/guitar.wav.")
    parser.add_argument("--skip-demucs", action="store_true", help="Analyze existing separated files only.")
    parser.add_argument("--frame-ms", type=float, default=100.0, help="Analysis frame size in ms.")
    parser.add_argument("--hop-ms", type=float, default=50.0, help="Analysis hop size in ms.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    load_analysis_dependencies()
    out_dir = args.out.expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    audio_path = args.audio.expanduser().resolve() if args.audio else None

    if args.separated_dir:
        separated_dir = args.separated_dir.expanduser().resolve()
    elif args.skip_demucs:
        if audio_path is None:
            raise SystemExit("--skip-demucs without --separated-dir requires an input audio path.")
        separated_dir = out_dir / args.model / sanitize_track_name(audio_path)
    else:
        if audio_path is None:
            raise SystemExit("An input audio path is required unless --separated-dir is provided.")
        separated_dir = run_demucs(audio_path, out_dir, args.model)

    if not separated_dir.exists():
        raise SystemExit(f"Separated directory not found: {separated_dir}")

    mix_audio = None
    mix_sample_rate = None
    if audio_path and audio_path.exists():
        try:
            mix_sample_rate, mix_audio = read_audio(audio_path)
        except Exception as exc:
            print(f"Warning: could not read mix for ratio metrics: {exc}")

    summaries: Dict[str, Dict[str, float]] = {}
    all_rows: List[Dict[str, float]] = []

    for stem in TARGET_STEMS:
        stem_file = find_stem_file(separated_dir, stem)
        if not stem_file:
            print(f"Warning: missing stem: {stem}")
            continue

        sample_rate, stem_audio = read_audio(stem_file)
        if mix_sample_rate and mix_sample_rate != sample_rate:
            print(f"Warning: mix sample rate {mix_sample_rate} != {stem} sample rate {sample_rate}; ratio timing may drift.")

        summary, rows = analyze_stem(stem, stem_audio, mix_audio, sample_rate, args.frame_ms, args.hop_ms)
        summary["path"] = str(stem_file)
        summary["sample_rate"] = sample_rate
        summaries[stem] = summary
        all_rows.extend(rows)

    summary_path = out_dir / "summary.json"
    frames_path = out_dir / "frames.csv"
    summary_path.write_text(json.dumps(summaries, indent=2, ensure_ascii=False), encoding="utf-8")
    write_csv(frames_path, all_rows)

    print(f"Wrote {summary_path}")
    print(f"Wrote {frames_path}")
    for stem, summary in summaries.items():
        print(f"{stem:>6}: rms={summary['rms']:.5f} ({summary['rms_dbfs']:.1f} dBFS), peak={summary['peak']:.5f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
