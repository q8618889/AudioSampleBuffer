# 🎵 歌词工具使用指南

## 📦 工具列表

### 1. ncm_lyrics_extractor.py - NCM歌词提取器

**功能：**
- ✅ 从NCM文件中提取歌词和元数据
- ✅ 从网易云音乐API下载歌词
- ✅ 批量处理整个文件夹
- ✅ 自动生成LRC文件

### 2. check_mp3_lyrics.py - MP3歌词检查工具 🆕

**功能：**
- ✅ 检查MP3文件是否包含嵌入的ID3歌词
- ✅ 显示歌词预览
- ✅ 批量扫描目录
- ✅ 统计歌词覆盖率

### 3. batch_extract_lyrics.sh - 批量处理脚本

**功能：**
- ✅ 一键批量提取NCM歌词
- ✅ 自动复制到项目Audio目录
- ✅ 智能匹配MP3文件
- ✅ 彩色输出，进度清晰

### 4. lrc_time_adjuster.py - 歌词时间轴调整器

**功能：**
- ✅ 调整LRC文件的时间偏移
- ✅ 支持正负偏移
- ✅ 批量处理
- ✅ 保留元数据标签

---

## 🚀 快速开始

### 步骤1：安装依赖

```bash
# 安装Python依赖库
pip3 install pycryptodome requests
```

### 步骤2：使用工具

#### 方式A：处理单个NCM文件 ⭐推荐

```bash
cd /Users/lzz/Downloads/AudioSampleBuffer-main/Tools

# 处理NCM文件，自动生成同名LRC文件
python3 ncm_lyrics_extractor.py -f "/Users/lzz/Music/网易云音乐/DOUDOU - 春夏秋冬（Live in 昆明 20231210）.ncm"
```

#### 方式B：批量处理整个文件夹 🔥强烈推荐

```bash
# 批量处理网易云音乐文件夹中的所有NCM文件
python3 ncm_lyrics_extractor.py -d "/Users/lzz/Music/网易云音乐"

# 递归处理包括子文件夹
python3 ncm_lyrics_extractor.py -d "/Users/lzz/Music/网易云音乐" -r
```

#### 方式C：根据歌曲ID直接下载

```bash
# 下载并保存到文件
python3 ncm_lyrics_extractor.py --id 1234567890 -o "歌词.lrc"

# 只查看歌词内容（不保存）
python3 ncm_lyrics_extractor.py --id 1234567890
```

---

## 📖 详细说明

### NCM文件处理流程

1. **解析NCM文件** → 提取歌曲ID和元数据
2. **从网易云API下载歌词** → 获取LRC格式歌词
3. **保存LRC文件** → 生成与NCM同名的.lrc文件

### 输出示例

```
处理文件: DOUDOU - 春夏秋冬（Live in 昆明 20231210）.ncm
  歌曲: 春夏秋冬（Live in 昆明 20231210）
  艺术家: DOUDOU
  专辑: 春夏秋冬
  网易云ID: 2068634619
  正在下载歌词...
  ✓ 歌词已保存: DOUDOU - 春夏秋冬（Live in 昆明 20231210）.lrc

完成! 成功: 1/1
```

---

## 🎯 解决你的问题

### 问题1：歌词加载失败

**原因：** 你的音频文件在 `AudioSampleBuffer/Audio/` 目录，但是LRC文件不存在

**解决方案：**

```bash
# 1. 批量处理你的网易云音乐文件夹
python3 ncm_lyrics_extractor.py -d "/Users/lzz/Music/网易云音乐"

# 2. 将生成的LRC文件复制到项目中
cp "/Users/lzz/Music/网易云音乐/"*.lrc "/Users/lzz/Downloads/AudioSampleBuffer-main/AudioSampleBuffer/Audio/"
```

### 问题2：MP3文件没有对应的LRC

**方案A：如果你有NCM源文件**

```bash
# 从NCM文件中提取歌词
python3 ncm_lyrics_extractor.py -f "歌曲.ncm"

# 将生成的.lrc文件重命名为与.mp3相同的文件名
```

**方案B：如果你知道歌曲ID**

在网易云音乐网页版中打开歌曲，URL中的数字就是歌曲ID：
```
https://music.163.com/#/song?id=1234567890
                                ^^^^^^^^^^
                                这就是ID
```

然后下载歌词：
```bash
python3 ncm_lyrics_extractor.py --id 1234567890 -o "歌名.lrc"
```

**方案C：搜索歌曲获取ID**

访问网易云音乐搜索你的歌曲，从URL中获取ID

---

## 🔧 高级用法

### 批量转换并整理

创建一个批处理脚本：

```bash
#!/bin/bash
# batch_lyrics.sh

# 批量处理NCM文件
python3 ncm_lyrics_extractor.py -d "/Users/lzz/Music/网易云音乐" -r

# 复制所有LRC文件到项目
find "/Users/lzz/Music/网易云音乐" -name "*.lrc" -exec cp {} "/Users/lzz/Downloads/AudioSampleBuffer-main/AudioSampleBuffer/Audio/" \;

echo "完成！所有歌词已复制到项目中"
```

### 为现有MP3文件匹配LRC

如果你的MP3文件是从NCM转换来的，文件名应该相同，直接复制LRC即可：

```bash
# 查找并复制匹配的LRC文件
cd /Users/lzz/Music/网易云音乐
for mp3 in /Users/lzz/Downloads/AudioSampleBuffer-main/AudioSampleBuffer/Audio/*.mp3; do
    basename="${mp3%.mp3}"
    lrc="${basename}.lrc"
    if [ -f "$lrc" ]; then
        cp "$lrc" "/Users/lzz/Downloads/AudioSampleBuffer-main/AudioSampleBuffer/Audio/"
        echo "复制: $(basename "$lrc")"
    fi
done
```

---

## 📋 常见问题

### Q: ModuleNotFoundError: No module named 'Crypto'

**A:** 安装依赖：
```bash
pip3 install pycryptodome requests
```

### Q: 下载歌词失败，提示"该歌曲暂无歌词"

**A:** 
- 部分纯音乐没有歌词
- 检查歌曲ID是否正确
- 尝试在网易云音乐网页版查看是否有歌词

### Q: NCM文件解析失败

**A:**
- 确保文件是完整的NCM文件
- 检查文件是否损坏
- 使用最新版本的网易云音乐客户端下载

### Q: 如何获取歌曲ID？

**A:** 三种方法：
1. 从NCM文件中提取（使用本工具）
2. 从网易云音乐分享链接中获取
3. 在网易云音乐网页版搜索歌曲，查看URL

---

## 🔍 检查MP3是否包含歌词 🆕

在处理NCM之前，先检查MP3文件是否已经包含歌词：

```bash
# 检查项目中的所有MP3文件
python3 check_mp3_lyrics.py

# 检查指定目录
python3 check_mp3_lyrics.py -d "/Users/lzz/Music/网易云音乐"

# 检查单个文件
python3 check_mp3_lyrics.py -f "周深 - Rubia.mp3"
```

**输出示例：**
```
🎵 MP3歌词检查工具
============================================================

✅ Song with lyrics.mp3
   语言: eng
   描述: Lyrics
   歌词预览: [00:00.00]Hello world...

❌ Song without lyrics.mp3 - 无歌词

============================================================
📊 统计结果:
   总文件数: 43
   包含歌词: 2
   无歌词: 41
```

**使用场景：**
- ✅ 了解哪些MP3已经有歌词，无需从NCM提取
- ✅ 验证歌词嵌入是否成功
- ✅ 发现可以直接使用的歌词资源

---

## 🎁 一键批量处理脚本

创建这个脚本快速处理所有文件：

```bash
#!/bin/bash
# quick_lyrics.sh

echo "🎵 开始批量获取歌词..."

# 1. 处理NCM文件
echo "1️⃣ 处理NCM文件..."
python3 ncm_lyrics_extractor.py -d "/Users/lzz/Music/网易云音乐" -r

# 2. 复制LRC到项目
echo "2️⃣ 复制歌词文件..."
find "/Users/lzz/Music/网易云音乐" -name "*.lrc" -exec cp {} "/Users/lzz/Downloads/AudioSampleBuffer-main/AudioSampleBuffer/Audio/" \;

# 3. 统计
lrc_count=$(ls -1 /Users/lzz/Downloads/AudioSampleBuffer-main/AudioSampleBuffer/Audio/*.lrc 2>/dev/null | wc -l)
echo "✅ 完成！共 $lrc_count 个歌词文件"

echo ""
echo "现在可以在Xcode中运行项目测试歌词功能了！"
```

使用方法：
```bash
chmod +x quick_lyrics.sh
./quick_lyrics.sh
```

---

## 💡 提示

1. **首次使用**：先用一个NCM文件测试，确保工具正常工作
2. **批量处理**：可能需要一些时间，请耐心等待
3. **网络连接**：需要连接网易云音乐API，确保网络畅通
4. **文件名匹配**：LRC文件名必须与MP3完全相同（除了扩展名）

---

## 🎉 现在开始吧！

```bash
# 快速测试
cd /Users/lzz/Downloads/AudioSampleBuffer-main/Tools
python3 ncm_lyrics_extractor.py -f "/Users/lzz/Music/网易云音乐/DOUDOU - 春夏秋冬（Live in 昆明 20231210）.ncm"
```

如果成功，你会看到生成了 `.lrc` 文件！🎵✨

