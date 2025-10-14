#!/bin/bash
# ===============================================
# 🎧 智能卡拉OK逐字 LRC 生成器 v5.2
# 自动匹配 .mp3 + 同名 .lrc 文件，生成逐字 LRC
# ===============================================

PYTHON="/opt/homebrew/bin/python3.11"

convert_script=$(cat << 'EOF'
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
    
    print(f"✅ 成功生成: {output_file} (共 {len(lrc_lines)} 行)")

if __name__ == "__main__":
    if len(sys.argv)!=3:
        print("Usage: python convert_to_enhanced_lrc.py input.json output.lrc")
        sys.exit(1)
    to_lrc(sys.argv[1], sys.argv[2])
EOF
)

convert_py=$(mktemp /tmp/convert_to_enhanced_lrc_XXXX.py)
echo "$convert_script" > "$convert_py"

for audio in *.mp3; do
    [ -f "$audio" ] || continue
    base="${audio%.mp3}"
    text_file="$base.txt"
    lrc_input="$base.lrc"

    if [ -f "$lrc_input" ]; then
        text_file="$lrc_input"
    elif [ ! -f "$text_file" ]; then
        echo "⚠️ 未找到对应文本或 LRC 文件: $base"
        continue
    fi

    echo "🎶 处理: $audio + $text_file"

    json_file="$base.json"
    lrc_file="$base.enhanced.lrc"

    # aeneas 对齐生成 JSON
    $PYTHON -m aeneas.tools.execute_task \
        "$audio" "$text_file" "task_language=zh|is_text_type=plain|os_task_file_format=json" "$json_file" --verbose

    # JSON -> 逐字 LRC
    $PYTHON "$convert_py" "$json_file" "$lrc_file"

    echo "✅ 已生成逐字 LRC: $lrc_file"
done

rm -f "$convert_py"

echo "🎉 全部处理完成！"

