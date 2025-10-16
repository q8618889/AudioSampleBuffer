#!/usr/bin/env python3
"""
分析 NCM 文件结构
"""

import struct
import sys

def analyze_ncm(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()
    
    offset = 0
    
    # 1. 文件头
    header = data[offset:offset+8]
    print(f"1. 文件头: {header} (应为 CTENFDAM)")
    if header != b'CTENFDAM':
        print("❌ 不是有效的 NCM 文件")
        return
    offset += 10  # 8 + 2
    
    # 2. 密钥长度
    key_length = struct.unpack('<I', data[offset:offset+4])[0]
    print(f"2. 密钥长度: {key_length} 字节")
    offset += 4
    
    # 3. 跳过密钥
    print(f"3. 密钥数据: offset={offset}, length={key_length}")
    offset += key_length
    
    # 4. 元数据长度
    meta_length = struct.unpack('<I', data[offset:offset+4])[0]
    print(f"4. 元数据长度: {meta_length} 字节")
    offset += 4
    
    # 5. 跳过元数据
    if meta_length > 0:
        print(f"5. 元数据: offset={offset}, length={meta_length}")
        offset += meta_length
    
    # 6. CRC (5 字节)
    print(f"6. CRC: offset={offset}, length=5")
    offset += 5
    
    # 7. 图片 - 这里是关键！
    print(f"\n🔍 图片数据分析（关键）:")
    print(f"   当前 offset: {offset} (0x{offset:X})")
    
    # 读取接下来的 8 个字节，看看是什么
    next_8_bytes = data[offset:offset+8]
    print(f"   接下来8字节: {' '.join(f'{b:02X}' for b in next_8_bytes)}")
    
    # 方案1：只有一个 imageSize (4字节)
    image_size_1 = struct.unpack('<I', data[offset:offset+4])[0]
    print(f"\n   方案1 (单个imageSize):")
    print(f"      imageSize = {image_size_1} (0x{image_size_1:X}) 字节")
    audio_offset_1 = offset + 4 + image_size_1
    print(f"      音频数据将从 offset={audio_offset_1} (0x{audio_offset_1:X}) 开始")
    if audio_offset_1 < len(data):
        audio_header_1 = data[audio_offset_1:audio_offset_1+4]
        print(f"      音频头: {' '.join(f'{b:02X}' for b in audio_header_1)}")
    
    # 方案2：两个字段 imageSpace + imageSize (8字节)
    image_space = struct.unpack('<I', data[offset:offset+4])[0]
    image_size_2 = struct.unpack('<I', data[offset+4:offset+8])[0]
    print(f"\n   方案2 (imageSpace + imageSize):")
    print(f"      imageSpace = {image_space} (0x{image_space:X})")
    print(f"      imageSize = {image_size_2} (0x{image_size_2:X})")
    audio_offset_2 = offset + 8 + image_size_2
    print(f"      音频数据将从 offset={audio_offset_2} (0x{audio_offset_2:X}) 开始")
    if audio_offset_2 < len(data):
        audio_header_2 = data[audio_offset_2:audio_offset_2+4]
        print(f"      音频头: {' '.join(f'{b:02X}' for b in audio_header_2)}")
    
    # 方案3：imageSpace, imageSize, 然后跳过 imageSpace
    audio_offset_3 = offset + 8 + max(image_space, image_size_2)
    print(f"\n   方案3 (imageSpace + imageSize, 跳过max):")
    print(f"      跳过 max({image_space}, {image_size_2}) = {max(image_space, image_size_2)}")
    print(f"      音频数据将从 offset={audio_offset_3} (0x{audio_offset_3:X}) 开始")
    if audio_offset_3 < len(data):
        audio_header_3 = data[audio_offset_3:audio_offset_3+4]
        print(f"      音频头: {' '.join(f'{b:02X}' for b in audio_header_3)}")
    
    print(f"\n📊 文件总大小: {len(data)} (0x{len(data):X}) 字节")
    
    # 检查哪个方案正确（通过检测 MP3/FLAC 魔数）
    print(f"\n✅ 正确的方案判断:")
    for i, (offset_val, header) in enumerate([
        (audio_offset_1, audio_header_1 if audio_offset_1 < len(data) else b''),
        (audio_offset_2, audio_header_2 if audio_offset_2 < len(data) else b''),
        (audio_offset_3, audio_header_3 if audio_offset_3 < len(data) else b'')
    ], 1):
        if len(header) >= 3:
            if header[:3] == b'ID3':
                print(f"   方案{i}: ✅ 检测到 MP3 (ID3)")
            elif header[:4] == b'fLaC':
                print(f"   方案{i}: ✅ 检测到 FLAC")
            elif header[0] == 0xFF and (header[1] & 0xE0) == 0xE0:
                print(f"   方案{i}: ✅ 检测到 MP3 (帧同步)")
            else:
                print(f"   方案{i}: ❌ 无法识别格式")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("用法: python3 analyze_ncm.py <ncm文件>")
        sys.exit(1)
    
    analyze_ncm(sys.argv[1])

