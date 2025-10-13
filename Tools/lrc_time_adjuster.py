#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
LRC歌词时间调整工具

用于调整LRC文件中所有歌词的时间戳，解决歌词不同步的问题
"""

import sys
import re
import argparse


def parse_time(time_str):
    """解析时间标签，返回秒数"""
    # 格式: [mm:ss.xx]
    match = re.match(r'\[(\d+):(\d+)\.(\d+)\]', time_str)
    if match:
        minutes = int(match.group(1))
        seconds = int(match.group(2))
        centiseconds = int(match.group(3))
        return minutes * 60 + seconds + centiseconds / 100.0
    return None


def format_time(seconds):
    """将秒数格式化为LRC时间标签"""
    if seconds < 0:
        seconds = 0
    
    minutes = int(seconds // 60)
    secs = int(seconds % 60)
    centiseconds = int((seconds - int(seconds)) * 100)
    
    return f"[{minutes:02d}:{secs:02d}.{centiseconds:02d}]"


def adjust_lrc_time(input_file, output_file, offset_ms):
    """
    调整LRC文件的时间
    
    Args:
        input_file: 输入LRC文件路径
        output_file: 输出LRC文件路径
        offset_ms: 时间偏移（毫秒），正数=延后，负数=提前
    """
    offset_sec = offset_ms / 1000.0
    
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        
        adjusted_lines = []
        adjusted_count = 0
        
        for line in lines:
            # 查找时间标签
            time_tags = re.findall(r'\[\d+:\d+\.\d+\]', line)
            
            if time_tags:
                # 有时间标签的行
                new_line = line
                
                for time_tag in time_tags:
                    # 解析时间
                    original_time = parse_time(time_tag)
                    if original_time is not None:
                        # 调整时间
                        new_time = original_time + offset_sec
                        new_tag = format_time(new_time)
                        
                        # 替换标签
                        new_line = new_line.replace(time_tag, new_tag, 1)
                        adjusted_count += 1
                
                adjusted_lines.append(new_line)
            else:
                # 元数据行或空行，不修改
                adjusted_lines.append(line)
        
        # 写入输出文件
        with open(output_file, 'w', encoding='utf-8') as f:
            f.writelines(adjusted_lines)
        
        print(f"✅ 成功调整歌词时间")
        print(f"   输入文件: {input_file}")
        print(f"   输出文件: {output_file}")
        print(f"   时间偏移: {offset_ms:+d} 毫秒 ({offset_sec:+.2f} 秒)")
        print(f"   调整条数: {adjusted_count} 个时间标签")
        
        return True
        
    except FileNotFoundError:
        print(f"❌ 错误: 文件不存在 - {input_file}")
        return False
    except Exception as e:
        print(f"❌ 错误: {e}")
        return False


def preview_adjustment(input_file, offset_ms, lines_to_show=5):
    """预览调整后的效果"""
    offset_sec = offset_ms / 1000.0
    
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        
        print(f"\n预览调整效果（前{lines_to_show}行）:")
        print(f"时间偏移: {offset_ms:+d} 毫秒 ({offset_sec:+.2f} 秒)")
        print("=" * 70)
        
        shown = 0
        for line in lines:
            time_tags = re.findall(r'\[\d+:\d+\.\d+\]', line)
            
            if time_tags and shown < lines_to_show:
                # 显示原始和调整后的对比
                print(f"\n原始: {line.strip()}")
                
                new_line = line
                for time_tag in time_tags:
                    original_time = parse_time(time_tag)
                    if original_time is not None:
                        new_time = original_time + offset_sec
                        new_tag = format_time(new_time)
                        new_line = new_line.replace(time_tag, new_tag, 1)
                
                print(f"调整: {new_line.strip()}")
                shown += 1
                
                if shown >= lines_to_show:
                    break
        
        print("=" * 70)
        
    except Exception as e:
        print(f"❌ 错误: {e}")


def main():
    parser = argparse.ArgumentParser(
        description='LRC歌词时间调整工具',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
示例:
  # 延后500毫秒（歌词显示太早）
  python3 lrc_time_adjuster.py -i song.lrc -o song_adjusted.lrc -t +500
  
  # 提前300毫秒（歌词显示太晚）
  python3 lrc_time_adjuster.py -i song.lrc -o song_adjusted.lrc -t -300
  
  # 预览调整效果
  python3 lrc_time_adjuster.py -i song.lrc -t -500 --preview
  
  # 直接覆盖原文件
  python3 lrc_time_adjuster.py -i song.lrc -t +200 --overwrite
        '''
    )
    
    parser.add_argument('-i', '--input', required=True, help='输入LRC文件路径')
    parser.add_argument('-o', '--output', help='输出LRC文件路径（不指定则需要--overwrite）')
    parser.add_argument('-t', '--time', type=int, required=True, 
                       help='时间偏移（毫秒），正数=延后，负数=提前')
    parser.add_argument('--preview', action='store_true', help='仅预览，不保存')
    parser.add_argument('--overwrite', action='store_true', help='覆盖原文件')
    
    args = parser.parse_args()
    
    # 预览模式
    if args.preview:
        preview_adjustment(args.input, args.time)
        return
    
    # 确定输出文件
    if args.overwrite:
        output_file = args.input
        print("⚠️  警告: 将覆盖原文件")
    elif args.output:
        output_file = args.output
    else:
        print("❌ 错误: 必须指定 -o/--output 或使用 --overwrite")
        sys.exit(1)
    
    # 执行调整
    if adjust_lrc_time(args.input, output_file, args.time):
        print("\n✨ 完成！现在可以播放测试歌词同步效果了。")
    else:
        sys.exit(1)


if __name__ == '__main__':
    main()

