# 🔧 Xcode 编译修复步骤

## ✅ 已完成的修复

1. **FLOATING_POINT 定义** - 已在 arch.h 中自动包含 config.h
2. **头文件路径** - 已调整为 speex/ 子目录结构

---

## ⚠️ 需要在 Xcode 中手动操作

### 问题：测试文件引用错误

**错误信息:**
```
testresample2.c Build input file cannot be found
```

**原因:** 测试文件已删除，但 Xcode 项目中仍有引用

### 解决步骤：

#### 1. 打开 Build Phases

1. 在 Xcode 左侧选择项目名 `AudioSampleBuffer`
2. 选择 Target: `AudioSampleBuffer`
3. 点击 **Build Phases** 标签

#### 2. 移除测试文件

在 **Compile Sources** 部分，找到并删除以下文件（点击 `-` 按钮）：

- ❌ `testresample2.c`
- ❌ `testresample.c`
- ❌ `testdenoise.c`
- ❌ `testecho.c`
- ❌ `testjitter.c`
- ❌ `scal.c`

**注意:** 只删除这些测试文件，保留以下核心文件：

- ✅ `preprocess.c`
- ✅ `mdf.c`
- ✅ `resample.c`
- ✅ `kiss_fft.c`
- ✅ `kiss_fftr.c`
- ✅ `fftwrap.c`
- ✅ `filterbank.c`
- ✅ `buffer.c`
- ✅ `jitter.c`
- ✅ `smallft.c`

#### 3. 核心编译文件清单（应该保留的）

确保以下 10 个 .c 文件在 **Compile Sources** 中：

```
SpeexDSP/preprocess.c
SpeexDSP/mdf.c
SpeexDSP/resample.c
SpeexDSP/kiss_fft.c
SpeexDSP/kiss_fftr.c
SpeexDSP/fftwrap.c
SpeexDSP/filterbank.c
SpeexDSP/buffer.c
SpeexDSP/jitter.c
SpeexDSP/smallft.c
```

#### 4. 确认编译设置

**Build Settings** → 搜索 **Other C Flags**，确认包含：

```
-DHAVE_CONFIG_H
-DFLOATING_POINT
-DUSE_KISS_FFT
```

#### 5. 清理并重新编译

1. `Cmd + Shift + K` - Clean Build Folder
2. `Cmd + B` - Build

---

## ✅ 编译成功的标志

编译成功后，你应该看到：

```
Build Succeeded
```

控制台无错误信息。

---

## 📝 最终文件结构

```
AudioSampleBuffer/Karaoke/DSP/
├── SpeexDSP/
│   ├── speex/              ← 公共头文件
│   │   ├── speex_preprocess.h
│   │   ├── speex_echo.h
│   │   ├── speex_resampler.h
│   │   └── speexdsp_*.h
│   ├── preprocess.c        ← 10 个核心源文件
│   ├── mdf.c
│   ├── resample.c
│   ├── kiss_fft.c
│   ├── kiss_fftr.c
│   ├── fftwrap.c
│   ├── filterbank.c
│   ├── buffer.c
│   ├── jitter.c
│   ├── smallft.c
│   ├── config.h            ← 配置文件
│   └── *.h                 ← 内部头文件
├── SpeexDSPBridge.h
└── SpeexDSPBridge.mm
```

---

## 🎯 快速检查命令

如果需要查看当前有哪些 .c 文件：

```bash
cd AudioSampleBuffer/Karaoke/DSP/SpeexDSP
ls *.c
```

应该只列出 10 个文件，不包含任何 test*.c 或 scal.c

---

完成以上步骤后，再次编译应该成功！✨
