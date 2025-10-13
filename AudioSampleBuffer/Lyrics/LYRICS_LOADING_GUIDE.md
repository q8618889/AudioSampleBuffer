# 智能歌词加载机制使用指南

## 📖 概述

`LyricsManager` 现在支持智能、动态的歌词加载机制，不再需要将所有 LRC 文件预先导入到项目中。系统会自动从多个来源查找和加载歌词。

## 🎯 歌词加载优先级

播放音频文件时，系统会按以下优先级自动查找歌词：

### 1️⃣ Bundle 资源（最高优先级）
- **位置**: 与MP3文件同目录的 `.lrc` 文件
- **用途**: 随应用打包分发的歌词
- **示例**: `AudioSampleBuffer/Audio/周深 - Rubia.lrc`
- **优点**: 离线可用，加载最快

### 2️⃣ 沙盒 Documents 目录
- **位置**: `Documents/Lyrics/歌曲名.lrc`
- **用途**: 动态下载或用户导入的歌词
- **路径**: `~/Library/Application Support/iPhone Simulator/.../Documents/Lyrics/`
- **优点**: 无需重新打包应用，动态更新

### 3️⃣ MP3 ID3 标签
- **位置**: MP3 文件内嵌的 USLT (Unsynchronized Lyrics) 标签
- **用途**: 自带歌词的音频文件
- **优点**: 歌词与音频绑定，不会丢失
- **注意**: 检测到ID3歌词后会自动保存到沙盒，下次加载更快

### 4️⃣ 网易云音乐 API
- **触发条件**: MP3包含网易云音乐ID元数据
- **用途**: 在线动态获取歌词
- **优点**: 自动获取最新歌词
- **注意**: 需要网络连接，获取后会自动保存到沙盒

## 🚀 使用方法

### 基本用法

```objective-c
#import "LyricsManager.h"

// 获取歌词（自动选择最佳来源）
[[LyricsManager sharedManager] fetchLyricsForAudioFile:audioPath 
                                            completion:^(LRCParser *parser, NSError *error) {
    if (parser) {
        NSLog(@"歌词加载成功：%@ 行", @(parser.lyrics.count));
        // 使用 parser 显示歌词
    } else {
        NSLog(@"未找到歌词：%@", error.localizedDescription);
    }
}];
```

### 查看沙盒歌词目录

```objective-c
NSString *lyricsDir = [[LyricsManager sharedManager] lyricsSandboxDirectory];
NSLog(@"歌词目录: %@", lyricsDir);
// 输出: ~/Documents/Lyrics/
```

### 手动保存歌词到沙盒

```objective-c
NSString *lrcContent = @"[00:00.00]歌词内容\n[00:05.00]第二行";
BOOL success = [[LyricsManager sharedManager] saveLyrics:lrcContent 
                                           forAudioFile:audioPath];
```

### 提取 ID3 歌词

```objective-c
NSString *id3Lyrics = [[LyricsManager sharedManager] extractLyricsFromID3:audioPath];
if (id3Lyrics) {
    NSLog(@"发现ID3歌词: %@", id3Lyrics);
}
```

## 🛠️ 工作流程建议

### 方案一：Bundle + 沙盒混合（推荐）

1. **开发阶段**: 将常用歌曲的 LRC 文件放入 `AudioSampleBuffer/Audio/` 目录
2. **运行时**: 新增或更新的歌词自动保存到沙盒
3. **优点**: 基础歌词离线可用，支持动态扩展

### 方案二：完全动态加载

1. **不在项目中放置任何 LRC 文件**
2. **首次播放**: 从 API 或 ID3 自动获取歌词
3. **后续播放**: 从沙盒快速加载
4. **优点**: 应用包体积最小，歌词永远是最新的

### 方案三：手动管理沙盒

1. **使用工具脚本批量处理**:
   ```bash
   # 提取 NCM 歌词并生成 LRC
   python3 ncm_lyrics_extractor.py -d "/path/to/netease/music" -r
   
   # 复制到沙盒（模拟器）
   ./sync_lyrics_to_sandbox.sh
   ```

2. **检查 MP3 是否包含歌词**:
   ```bash
   python3 check_mp3_lyrics.py
   ```

## 📝 日志输出

启用详细日志可以了解歌词加载过程：

```
📖 [歌词] 从Bundle加载: 周深 - Rubia.lrc
📖 [歌词] 从沙盒加载: DOUDOU - 拂过沙的光.lrc
📖 [歌词] 从ID3标签提取: Some Song.mp3
📖 [歌词] 从网易云API获取: 黑豹乐队 - 散，作鸟兽 (ID: 2114743243)
✅ [歌词] 已保存到沙盒: DOUDOU - 拂过沙的光.lrc
📖 [歌词] 从缓存加载: DOUDOU - 拂过沙的光.mp3
⚠️ [歌词] 未找到歌词: Unknown Song.mp3
```

## 🔧 高级功能

### 缓存机制

- 内存缓存最多保存 50 个歌词解析结果
- 首次加载后，相同文件会直接从缓存返回
- 应用重启后缓存清空，但沙盒文件永久保存

### 网易云音乐 ID 提取

系统会自动从 MP3 的元数据中提取网易云音乐 ID：

```objective-c
NSString *musicId = [[LyricsManager sharedManager] extractNeteaseIdFromAudio:audioPath];
if (musicId) {
    // 可用于 API 调用
}
```

## 📁 文件路径示例

### Bundle 路径
```
/Applications/AudioSampleBuffer.app/
  └── Audio/
      ├── 周深 - Rubia.mp3
      └── 周深 - Rubia.lrc  ← Bundle资源
```

### 沙盒路径（模拟器）
```
~/Library/Developer/CoreSimulator/Devices/[DEVICE-ID]/
  data/Containers/Data/Application/[APP-ID]/
    └── Documents/
        └── Lyrics/  ← 沙盒目录
            ├── 周深 - Rubia.lrc
            ├── DOUDOU - 拂过沙的光.lrc
            └── 黑豹乐队 - 散，作鸟兽.lrc
```

### 沙盒路径（真机）
```
/var/mobile/Containers/Data/Application/[APP-ID]/
  └── Documents/
      └── Lyrics/
```

## 🎵 实际应用场景

### 场景 1: 播放打包的歌曲
- 歌词已在 Bundle → 直接加载 ✅
- 离线可用，速度最快

### 场景 2: 播放新下载的歌曲（有ID3歌词）
- 检测到 ID3 歌词 → 提取并缓存到沙盒 ✅
- 下次播放从沙盒加载

### 场景 3: 播放网易云音乐导出的歌曲
- 提取网易云 ID → API 获取歌词 → 保存到沙盒 ✅
- 需要网络，但只需一次

### 场景 4: 用户手动添加歌曲
- 无任何歌词信息 → 返回错误 ⚠️
- 可以手动将 LRC 文件放入沙盒目录

## 💡 最佳实践

### ✅ 推荐做法
- 在项目中保留少量示例歌曲的 LRC 文件
- 让系统自动管理其他歌词到沙盒
- 使用工具脚本批量处理 NCM 文件
- 定期检查沙盒目录清理无用歌词

### ❌ 不推荐
- 将所有 LRC 文件都添加到项目（增加包体积）
- 手动管理每个 LRC 文件的同步
- 依赖单一歌词来源

## 🔍 调试技巧

### 查看沙盒内容（模拟器）
```bash
# 查找应用沙盒
find ~/Library/Developer/CoreSimulator/Devices \
  -name "Documents" -path "*/AudioSampleBuffer*" 2>/dev/null

# 列出歌词文件
ls -lh [SANDBOX_PATH]/Documents/Lyrics/
```

### 清空缓存测试
```bash
# 删除沙盒歌词（测试API调用）
rm -rf [SANDBOX_PATH]/Documents/Lyrics/*
```

## 📚 相关文件

- `LyricsManager.h/m` - 歌词管理器核心实现
- `LRCParser.h/m` - LRC 格式解析器
- `LyricsView.h/m` - 歌词显示视图
- `ncm_lyrics_extractor.py` - NCM 歌词提取工具
- `check_mp3_lyrics.py` - MP3 歌词检查工具
- `batch_extract_lyrics.sh` - 批量处理脚本

## 🎉 总结

新的智能歌词加载机制让你：
- ✅ 无需预先导入所有歌词文件到项目
- ✅ 支持动态下载和更新歌词
- ✅ 自动从多个来源查找歌词
- ✅ 缓存机制提升性能
- ✅ 灵活的沙盒管理

享受更智能的歌词体验！🎵

