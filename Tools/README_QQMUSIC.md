# QQ音乐歌词工具使用说明

## 🎯 核心原理解析

### 163MusicLyrics 工具是如何获取 QQ音乐歌词的？

根据对 [163MusicLyrics](https://github.com/jitwxs/163MusicLyrics) 项目的分析，它主要通过以下方式获取歌词：

#### 1. **API 接口逆向**

QQ音乐提供了一些未公开文档化的 API 接口：

```
歌词接口：
- https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg
  参数: songmid=<歌曲ID>&format=json&nobase64=1

搜索接口：
- https://c.y.qq.com/soso/fcgi-bin/client_search_cp
  参数: w=<关键词>&format=json
```

#### 2. **请求流程**

```
用户输入（歌名/ID/链接）
    ↓
解析/搜索获取 songmid
    ↓
请求歌词 API（需要特定请求头）
    ↓
解析 JSON 响应（Base64 解码）
    ↓
提取歌词（LRC 格式）
```

#### 3. **关键技术**

**绕过防爬虫：**
```http
Referer: https://y.qq.com/
User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)
```

**数据解码：**
- API 返回 Base64 编码的歌词
- 解码后得到 LRC 格式文本

**元数据提取：**
- 从 QMC/MGG 解密文件中读取 `songmid`
- 使用 `songmid` 直接获取歌词

## 🔧 本项目实现

### 已创建的工具

1. **QQMusicLyricsAPI.h/m**
   - Objective-C 实现的 API 客户端
   - 支持通过 songmid、songid、歌名搜索
   - 自动从音频文件元数据提取信息

2. **check_qqmusic_metadata.py**
   - Python 脚本，检查音频文件元数据
   - 支持 OGG、MP3、FLAC 等格式
   - 可视化显示 QQ音乐标识

3. **test_qqmusic_lyrics.sh**
   - 一键测试脚本
   - 检查元数据 + 转换文件

## 📖 使用场景

### 场景 1：你有从 MGG 解密的 OGG 文件

```bash
# 1. 检查文件是否包含 QQ音乐元数据
python3 check_qqmusic_metadata.py song.ogg

# 如果输出显示有 songmid，则：
# 2. 转换为 MP3 并保留元数据
ffmpeg -i song.ogg -c:a libmp3lame -q:a 2 -map_metadata 0 song.mp3

# 3. 验证转换结果
python3 check_qqmusic_metadata.py song.mp3
```

### 场景 2：在 iOS 应用中自动获取歌词

```objective-c
// 用户选择了一首歌
NSString *audioPath = @"/path/to/song.mp3";

// 自动识别并获取歌词
[QQMusicLyricsAPI fetchLyricsFromAudioFile:audioPath 
                                completion:^(QQMusicLyrics *lyrics, NSError *error) {
    if (lyrics) {
        // 保存 LRC 文件
        NSString *lrcPath = [[audioPath stringByDeletingPathExtension] 
                             stringByAppendingPathExtension:@"lrc"];
        [lyrics.originalLyrics writeToFile:lrcPath 
                                atomically:YES 
                                  encoding:NSUTF8StringEncoding 
                                     error:nil];
        
        // 显示歌词
        [self.lyricsView loadLyricsFromFile:lrcPath];
    }
}];
```

## 🎵 QQ音乐元数据标识

### OGG 文件（Vorbis Comment）

```
SONGMID=001OyHbk2MSIi4     # 最重要，直接对应歌词
SONGID=102065756           # 备用 ID
TITLE=七里香
ARTIST=周杰伦
ALBUM=七里香
COMMENT=QQMusic           # 来源标识
ENCODER=QQMusic           # 可能存在
```

### MP3 文件（ID3 标签）

转换后的 MP3 会将 Vorbis Comment 映射到 ID3：

```
TIT2 (Title): 七里香
TPE1 (Artist): 周杰伦
TALB (Album): 七里香
COMM (Comment): QQMusic
TXXX:songmid: 001OyHbk2MSIi4    # 自定义标签
```

## ⚠️ 重要提示

### 关于 OGG → MP3 转换

**✅ 正确做法：**
```bash
ffmpeg -i input.ogg \
       -c:a libmp3lame \
       -q:a 2 \
       -map_metadata 0 \
       -id3v2_version 3 \
       output.mp3
```

**❌ 错误做法：**
```bash
ffmpeg -i input.ogg output.mp3  # 会丢失元数据！
```

### 关键参数说明

- `-c:a libmp3lame`: 使用 LAME MP3 编码器
- `-q:a 2`: VBR 质量级别（0-9，2 = 高质量，约 190kbps）
- `-map_metadata 0`: **复制所有元数据**（最重要！）
- `-id3v2_version 3`: 使用 ID3v2.3（兼容性最好）

### 批量转换脚本

```bash
#!/bin/bash
# 批量转换当前目录所有 OGG 文件

for file in *.ogg; do
    if [ -f "$file" ]; then
        output="${file%.ogg}.mp3"
        echo "🔄 转换: $file → $output"
        
        ffmpeg -i "$file" \
               -c:a libmp3lame \
               -q:a 2 \
               -map_metadata 0 \
               -id3v2_version 3 \
               -y \
               "$output" \
               -loglevel error
        
        if [ $? -eq 0 ]; then
            echo "✅ 完成: $output"
        else
            echo "❌ 失败: $file"
        fi
    fi
done

echo "🎉 批量转换完成！"
```

## 🔍 故障排查

### 问题：无法读取 OGG 元数据

**iOS AVFoundation 不支持读取 OGG 的 Vorbis Comment**

解决方案：
1. **推荐：** 先转换为 MP3 再导入项目
2. 高级：使用 `libvorbis` C++ 库直接读取

### 问题：转换后元数据丢失

检查清单：
- [ ] 使用了 `-map_metadata 0` 参数？
- [ ] ffmpeg 版本是否过旧？（建议 4.0+）
- [ ] 原 OGG 文件是否真的有元数据？

验证命令：
```bash
# 查看 OGG 元数据
ffprobe -show_format song.ogg | grep TAG

# 查看 MP3 元数据
ffprobe -show_format song.mp3 | grep TAG
```

### 问题：API 返回错误

| 错误码 | 原因 | 解决方案 |
|--------|------|---------|
| -1 | songmid 为空 | 检查文件元数据 |
| -2 | 无元数据 | 尝试歌名搜索 |
| -3 | 无歌词 | 歌曲确实没有歌词 |
| -404 | 搜索无结果 | 检查歌名拼写 |
| retcode != 0 | API 错误 | 网络问题或限流 |

## 📚 参考资料

- **163MusicLyrics 项目：** https://github.com/jitwxs/163MusicLyrics
- **QQ音乐 API（非官方）：** 逆向工程获得
- **ffmpeg 文档：** https://ffmpeg.org/ffmpeg.html
- **ID3 标签规范：** https://id3.org/
- **Vorbis Comment 规范：** https://xiph.org/vorbis/doc/v-comment.html

## 💡 技巧总结

1. **优先检查元数据** - 使用 `check_qqmusic_metadata.py`
2. **正确转换格式** - 必须加 `-map_metadata 0`
3. **自动化集成** - 在 iOS 应用中自动获取歌词
4. **本地缓存** - 获取一次后保存为 .lrc 文件
5. **错误处理** - API 可能失败，要有降级方案

## 🎉 总结

**你的问题答案：**

1. ✅ **OGG 是否包含歌曲 ID？** 
   - 是的，通常包含 `songmid` 或 `songid`

2. ✅ **转 MP3 后数据还在吗？**
   - 使用正确的 ffmpeg 命令可以保留
   - 关键参数：`-map_metadata 0`

3. ✅ **如何在项目中使用？**
   - 已提供完整的 Objective-C API
   - 可自动识别 QQ音乐文件并获取歌词

**立即开始测试：**
```bash
./Tools/test_qqmusic_lyrics.sh /path/to/your/song.ogg
```

