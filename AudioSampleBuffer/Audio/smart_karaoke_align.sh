#!/bin/bash
# ===============================================
# 🎧 智能卡拉OK逐字 LRC 生成器 v5.3
# 自动匹配 .mp3 + 同名 .lrc 文件，生成逐字 LRC
# ===============================================

PYTHON="/opt/homebrew/bin/python3.11"

# 设置 UTF-8 编码
export PYTHONIOENCODING=UTF-8

# 创建 Python 转换脚本
convert_py="/tmp/convert_to_enhanced_lrc_$$.py"
cat > "$convert_py" << 'EOF'
import sys, json, re

def clean_lrc_text(text):
    """清理 LRC 格式文本，提取纯歌词"""
    # 移除时间标签 [00:00.00]
    text = re.sub(r'\[\d+:\d+\.\d+\]', '', text)
    # 移除常见的元数据标签
    text = re.sub(r'作词\s*[:：].*', '', text)
    text = re.sub(r'作曲\s*[:：].*', '', text)
    text = re.sub(r'编曲\s*[:：].*', '', text)
    text = re.sub(r'演唱\s*[:：].*', '', text)
    text = re.sub(r'制作人\s*[:：].*', '', text)
    return text.strip()

def to_lrc(json_file, output_file):
    with open(json_file, 'r', encoding='utf-8') as f:
        data = json.load(f)

    lrc_lines = []
    for fragment in data['fragments']:
        start_time = float(fragment['begin'])
        # 获取文本并清理
        raw_text = fragment.get('lines', [fragment.get('text','')])[0]
        text = clean_lrc_text(raw_text)
        
        if not text.strip():
            continue
            
        words = list(text)
        per_word_time = (float(fragment['end']) - start_time) / max(len(words),1)
        line = "[{:.2f}]".format(start_time)
        current_time = 0.0
        for w in words:
            line += "<{:.2f}>{}".format(current_time, w)
            current_time += per_word_time
        lrc_lines.append(line)

    with open(output_file, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lrc_lines))
    
    print("✅ 成功生成: {} (共 {} 行)".format(output_file, len(lrc_lines)))

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python convert_to_enhanced_lrc.py input.json output.lrc")
        sys.exit(1)
    to_lrc(sys.argv[1], sys.argv[2])
EOF

echo "🎵 开始批量处理..."
echo "================================"

processed=0
skipped=0
failed=0

for audio in *.mp3; do
    [ -f "$audio" ] || continue
    base="${audio%.mp3}"
    text_file="$base.txt"
    lrc_input="$base.lrc"

    # 检查是否已经有 enhanced.lrc
    enhanced_lrc="$base.enhanced.lrc"
    if [ -f "$enhanced_lrc" ]; then
        echo "⏭️  已存在，跳过: $enhanced_lrc"
        ((skipped++))
        continue
    fi

    # 优先使用 .lrc 文件，否则使用 .txt
    if [ -f "$lrc_input" ]; then
        text_file="$lrc_input"
    elif [ ! -f "$text_file" ]; then
        echo "⚠️  未找到对应文本或 LRC 文件: $base"
        ((skipped++))
        continue
    fi

    echo ""
    echo "🎶 处理: $audio + $text_file"

    json_file="$base.json"

    # 检测语言（简单判断：如果文件名包含中文字符则用 zh，否则用 en）
    if echo "$audio" | LC_ALL=C grep -q '[^[:print:]]'; then
        lang="zh"
    else
        lang="en"
    fi

    # aeneas 对齐生成 JSON（减少输出）
    if $PYTHON -m aeneas.tools.execute_task \
        "$audio" "$text_file" \
        "task_language=$lang|is_text_type=plain|os_task_file_format=json" \
        "$json_file" > /dev/null 2>&1; then
        
        # JSON -> 逐字 LRC
        if $PYTHON "$convert_py" "$json_file" "$enhanced_lrc" 2>&1; then
            # 清理临时 JSON 文件
            rm -f "$json_file"
            ((processed++))
        else
            echo "❌ 转换失败: $json_file"
            ((failed++))
        fi
    else
        echo "❌ 对齐失败: $audio"
        ((failed++))
    fi
done

# 清理 Python 脚本
rm -f "$convert_py"

echo ""
echo "================================"
echo "🎉 处理完成！"
echo "   ✅ 成功: $processed 个"
echo "   ⏭️  跳过: $skipped 个"
echo "   ❌ 失败: $failed 个"
