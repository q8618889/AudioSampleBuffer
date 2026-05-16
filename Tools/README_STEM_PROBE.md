# Demucs Stem Probe

Offline experiment pipeline for checking whether separated `bass` / `guitar`
stems can provide better reference values than hand-made DSP combinations.

## Install

Use a local virtualenv if possible:

```bash
python3 -m venv .venv-demucs
source .venv-demucs/bin/activate
python3 -m pip install -U pip
python3 -m pip install -U demucs soundfile numpy
```

Demucs will download the selected model on first run.
`soundfile` is recommended for robust audio loading. Without it, the probe can
still analyze ordinary PCM WAV stems via Python's standard library.

## Run Separation And Analysis

```bash
python3 Tools/demucs_stem_probe.py "/path/to/song.mp3" --out build/stem_probe
```

Default model is `htdemucs_6s`, which can output `bass` and `guitar` stems.

Outputs:

- `build/stem_probe/htdemucs_6s/<track>/bass.wav`
- `build/stem_probe/htdemucs_6s/<track>/guitar.wav`
- `build/stem_probe/summary.json`
- `build/stem_probe/frames.csv`

## Analyze Existing Demucs Output

```bash
python3 Tools/demucs_stem_probe.py "/path/to/song.mp3" \
  --skip-demucs \
  --separated-dir "build/stem_probe/htdemucs_6s/song"
```

## Metrics

`summary.json` contains global metrics per stem:

- `rms`, `rms_dbfs`
- `peak`, `peak_dbfs`
- `crest_db`
- low / low-mid / mid / high band RMS
- spectral centroid

`frames.csv` contains frame-level values:

- `time_sec`
- stem `rms`, `rms_dbfs`
- `ratio_to_mix`
- band RMS and centroid

Use `frames.csv` as the reference curve when comparing against the app's live
feature labels. If a guitar solo has a stable `guitar` stem RMS but the live
combo label remains around 0.2-0.3, the combo label is not measuring instrument
presence reliably enough.
