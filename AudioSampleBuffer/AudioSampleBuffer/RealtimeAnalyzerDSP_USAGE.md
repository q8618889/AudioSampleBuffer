# RealtimeAnalyzerDSP 参数说明与使用指南

本文档说明 `RealtimeAnalyzerDSP.h` 中各参数含义、默认值、推荐配置和典型调用方式。

## 1. 模块定位

`RealtimeAnalyzerDSP` 是实时音频分析 C 核心，支持两条路径：

- 基础路径：`FFT -> A-weighting -> 80 bands`
- 扩展路径：在基础路径上追加 `HPSS(H/P/R)` 与 4 类特征（Sub-Bass / Transient / Harmonic / Noise）

适合在 iOS 实时回调（`AVAudioEngine tap`）中使用。

---

## 2. 核心数据结构

### `AnalyzerDSPRef`

- DSP 上下文句柄（opaque 指针）
- 通过 `AnalyzerDSP_Create` 创建，`AnalyzerDSP_Destroy` 释放

### `AnalyzerCategoryFeatures`

扩展路径返回的每声道特征：

- `subBass`: 20-60 Hz（来自 H 分量）
- `bass`: 60-120 Hz（来自 H 分量）
- `lowEnergy`: `subBass + bass`
- `transient`: SuperFlux 风格瞬态强度（来自 P 分量）
- `harmonic`: 谐波总能量（H）
- `harmonicPeakRatio`: 谐波峰均比（越大越“线条状”）
- `noise`: 残差/噪声总能量（R）
- `spectralFlatness`: 谱平坦度（0=更谐波，1=更噪声）

---

## 3. API 参数说明

## `AnalyzerDSP_Create(...)`

```c
AnalyzerDSPRef AnalyzerDSP_Create(
    int fftSize,
    int frequencyBands,
    float startFrequency,
    float endFrequency,
    float sampleRate
);
```

- `fftSize`
  - 含义：FFT 窗长
  - 要求：2 的幂
  - 推荐：`4096`（低频分辨率更好）
- `frequencyBands`
  - 含义：输出 band 数量
  - 常用：`80`
- `startFrequency` / `endFrequency`
  - 含义：band 映射频率范围
  - 常用：`50 ~ 18000 Hz`
- `sampleRate`
  - 含义：初始化时用于 A-weighting 的参考采样率
  - 常用：`44100` 或 `48000`

## `AnalyzerDSP_SetSpectrumSmooth(ref, smooth)`

- `smooth` 范围：`0..1`
- 越大越平滑、反应越慢
- 默认：`0.65`
- 推荐：
  - 可视化：`0.6 ~ 0.75`
  - 检测优先：`0.45 ~ 0.60`

## `AnalyzerDSP_SetHPSSParameters(ref, timeMedianLen, freqMedianLen, separationFactor)`

- `timeMedianLen` (`Lh`)
  - 含义：时间方向中值滤波长度（奇数，<=31）
  - 默认：`11`
  - 越大越偏向稳定谐波
- `freqMedianLen` (`Lp`)
  - 含义：频率方向中值滤波长度（奇数，<=31）
  - 默认：`17`
  - 越大越偏向瞬态结构
- `separationFactor` (`beta`)
  - 含义：H/P 分离因子
  - 默认：`1.8`
  - 越大分离越“严格”，R 分量通常会增大

## `AnalyzerDSP_ProcessChannel(...)`

基础路径调用（不返回 H/P/R）：

- `samples`: 当前声道样本指针
- `sampleCount`: 本次新样本数（可小于 `fftSize`，内部滑窗累积）
- `channelIndex`: `0/1`
- `amplitudeLevel`: 输出幅度缩放
- `sampleRate`: 当前实际采样率
- `outBands`: 输出 band 数组（长度 >= `frequencyBands`）

## `AnalyzerDSP_ProcessChannelExtended(...)`

扩展路径调用（返回 H/P/R + 类别特征）：

- `outBands`: 混合谱（兼容旧路径）
- `outHBands`: H 分量 band（可传 `NULL`）
- `outPBands`: P 分量 band（可传 `NULL`）
- `outRBands`: R 分量 band（可传 `NULL`）
- `outCat`: `AnalyzerCategoryFeatures`（可传 `NULL`）

提示：不需要的输出可传 `NULL`，减少无意义的数据搬运。

---

## 4. 推荐配置

## 低功耗模式（默认）

- 调用：`AnalyzerDSP_ProcessChannel`
- 参数：
  - `fftSize=4096`（或 2048）
  - `smooth=0.65`
- 场景：普通可视化、基础节拍驱动

## 高精度模式（HPSS）

- 调用：`AnalyzerDSP_ProcessChannelExtended`
- 参数：
  - `fftSize=4096`
  - `Lh=11, Lp=17, beta=1.8`
- 场景：效果识别、可解释输出（H/P/R 驱动）

---

## 5. 典型调用流程（C 层）

```c
AnalyzerDSPRef dsp = AnalyzerDSP_Create(4096, 80, 50.0f, 18000.0f, 44100.0f);
AnalyzerDSP_SetSpectrumSmooth(dsp, 0.65f);
AnalyzerDSP_SetHPSSParameters(dsp, 11, 17, 1.8f);

float bands[80];
float hBands[80], pBands[80], rBands[80];
AnalyzerCategoryFeatures cat;

// 在音频回调中（每声道）
AnalyzerDSP_ProcessChannelExtended(
    dsp,
    channelSamples,
    sampleCount,      // 可以是 2048，内部会累积到 4096 滑窗
    0,                // channelIndex
    5,                // amplitudeLevel
    44100.0f,         // actual sampleRate
    bands,
    hBands,
    pBands,
    rBands,
    &cat
);

// 用完释放
AnalyzerDSP_Destroy(dsp);
```

---

## 6. 常见问题

- Q: `sampleCount` 必须等于 `fftSize` 吗？
  - A: 不需要。内部已支持滑动窗口累积。

- Q: 什么时候用基础路径，什么时候用扩展路径？
  - A: 只做可视化和低功耗时用基础路径；要 H/P/R 或 4 类可解释特征时用扩展路径。

- Q: `harmonicPeakRatio` 很高表示什么？
  - A: 通常说明谐波结构更集中（更“音高化”）；低值更接近噪声化。

- Q: `spectralFlatness` 能单独判断失真吗？
  - A: 不建议单独使用，建议与 `harmonic/noise/high-band` 联合判定。

---

## 7. EDM 效果实时检测（新增）

本节对应当前项目在 `AudioFeatureExtractor` 中新增的效果输出（面向 SDK 使用侧）。

### 7.1 输出字段（AudioFeatures）

布尔结果：

- `stutterDetected`
- `gateDetected`
- `tremoloDetected`
- `sidechainDetected`
- `filterSweepDetected`
- `autoPanDetected`
- `delayDetected`
- `distortionDetected`（weak detect）

置信度（0..1）：

- `stutterConfidence`
- `gateConfidence`
- `tremoloConfidence`
- `sidechainConfidence`
- `filterSweepConfidence`
- `autoPanConfidence`
- `delayConfidence`
- `distortionConfidence`

HPSS 可解释项：

- `hpssExplainable`
- `harmonicDriven`
- `transientDriven`
- `noiseResidualDriven`

### 7.2 规则来源映射

- `Stutter/Gate`: onset 密度 + 包络周期性（自相关峰）
- `Tremolo/Sidechain`: 包络调制 + 低频能量 + BPM 同步
- `Filter Sweep`: spectral centroid 趋势（斜率）
- `Auto-Pan`: L/R 能量差及其波动
- `Delay`: 包络自相关多峰代理
- `Distortion`: 高频增强（原版）/ harmonic-noise-flatness 联合（HPSS）

### 7.3 原版 vs HPSS/4

## 原版（低功耗）可用

- Stutter/Gate
- Tremolo/Sidechain（基础）
- Filter Sweep
- Auto-Pan
- Delay
- Distortion（弱）

## HPSS/4 增强

- Distortion 更稳：`harmonic + noise + spectralFlatness`
- Sidechain 更准：`subBassEnergy + transientStrength` 组合
- 可解释输出：`harmonicDriven / transientDriven / noiseResidualDriven`

### 7.4 使用建议

- 默认模式：低功耗路径（基础检测全开）
- 高精度模式：开启 HPSS 扩展路径，用于复杂混音、分析解释、离线标注
- 若业务需要“可解释事件”，必须开启 HPSS/4

