# Instrument Truth Config

`AudioSampleBuffer/AI/InstrumentTruthConfig.json` is a lightweight truth mapping
for guitar/bass experiments.

It does not include dataset audio. It tells the app or offline tools how to
interpret mature datasets as reference truth:

- MoisesDB: primary real-song truth for fine-grained stems such as `bass` and
  `guitar`.
- MUSDB18: reliable baseline for `bass`; guitar is not separated and normally
  lives inside `other`.
- Slakh2100: synthetic but clean MIDI/instrument labels, useful for validating
  `electric_bass` and `electric_guitar` taxonomy.

## Why This Exists

The live DSP combo labels can stay around `0.2-0.3` even when a guitar or bass is
soloing. That means the combo label is measuring timbre tendency, not reliable
instrument presence.

This config defines instrument truth as separated stem energy:

```text
ratio_to_mix = stem_rms / max(mix_rms, 1e-9)
presence = smoothstep(ratio_floor, ratio_strong, ratio_to_mix)
         * smoothstep(db_floor, db_strong, stem_rms_dbfs)
```

The app can use the same label names:

- `electric_bass_line` -> 电贝斯线
- `electric_guitar_texture` -> 电吉他纹理
- `distorted_guitar` -> 失真吉他
- `pluck_grain` -> 拨弦颗粒
- `sound_wall` -> 持续音墙

## Embedding

Add `AudioSampleBuffer/AI/InstrumentTruthConfig.json` to the app bundle as a
resource, then load it as JSON. The config is safe to ship by itself; source
datasets and audio files may have non-commercial or academic restrictions.

In the Music Feature Scope, labels backed by this config are highlighted in
amber and show their dataset badge, for example `电贝斯线[Moises/MUSDB/Slakh]`.
The numeric value remains the live detector's raw reading until separated-stem
curves are available.

## Recommended Dataset Order

1. Use MoisesDB when available. It is the best match for real-song guitar/bass
   stem truth.
2. Use MUSDB18 only for bass baseline checks.
3. Use Slakh2100 when you need clean guitar/bass labels without running a source
   separation model.
