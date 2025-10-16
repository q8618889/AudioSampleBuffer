#!/usr/bin/env python3
"""
直接使用 Python 实现 NCM 解密，验证算法
基于 taurusxin/ncmdump 逻辑
"""

import struct
import sys
from Crypto.Cipher import AES
import base64
import json

# 核心密钥
CORE_KEY = bytes([
    0x68, 0x7A, 0x48, 0x52, 0x41, 0x6D, 0x73, 0x6F,
    0x35, 0x6B, 0x49, 0x6E, 0x62, 0x61, 0x78, 0x57
])

# 元数据密钥
META_KEY = bytes([
    0x23, 0x31, 0x34, 0x6C, 0x6A, 0x6B, 0x5F, 0x21,
    0x5C, 0x5D, 0x26, 0x30, 0x55, 0x3C, 0x27, 0x28
])

def aes_ecb_decrypt(data, key):
    """AES ECB 解密"""
    cipher = AES.new(key, AES.MODE_ECB)
    return cipher.decrypt(data)

def decrypt_ncm(input_path):
    """解密 NCM 文件"""
    with open(input_path, 'rb') as f:
        data = f.read()
    
    offset = 0
    
    # 1. 检查文件头
    if data[offset:offset+8] != b'CTENFDAM':
        print("❌ 不是有效的 NCM 文件")
        return None
    offset += 10
    
    # 2. 解密密钥
    key_length = struct.unpack('<I', data[offset:offset+4])[0]
    offset += 4
    
    key_data = bytearray(data[offset:offset+key_length])
    offset += key_length
    
    # XOR 0x64
    for i in range(len(key_data)):
        key_data[i] ^= 0x64
    
    # AES 解密
    decrypted_key = aes_ecb_decrypt(bytes(key_data), CORE_KEY)
    
    print(f"📝 密钥解密详情:")
    print(f"   加密密钥长度: {len(key_data)}")
    print(f"   解密后长度: {len(decrypted_key)}")
    print(f"   前32字节: {decrypted_key[:32]}")
    
    # 去掉 "neteasecloudmusic" 前缀
    decrypted_key = decrypted_key[17:]
    
    print(f"   去除前缀后长度: {len(decrypted_key)}")
    print(f"   最后1字节 (padding): {decrypted_key[-1]}")
    
    # ⚠️ 不去除 PKCS7 填充！根据原始实现，这里不应该去除填充
    # padding = decrypted_key[-1]
    # if padding <= 16:
    #     decrypted_key = decrypted_key[:-padding]
    
    print(f"✅ 解密密钥长度: {len(decrypted_key)}")
    print(f"   密钥前16字节: {' '.join(f'{b:02X}' for b in decrypted_key[:16])}")
    
    # 3. 生成 RC4 密钥盒
    key_box = list(range(256))
    j = 0
    for i in range(256):
        j = (j + key_box[i] + decrypted_key[i % len(decrypted_key)]) & 0xFF
        key_box[i], key_box[j] = key_box[j], key_box[i]
    
    print(f"   密钥盒前8个值: {' '.join(f'{k:02X}' for k in key_box[:8])}")
    
    # 4. 解密元数据（可选）
    meta_length = struct.unpack('<I', data[offset:offset+4])[0]
    offset += 4
    
    detected_format = 'mp3'
    
    if meta_length > 0:
        meta_data = bytearray(data[offset:offset+meta_length])
        offset += meta_length
        
        # XOR 0x63
        for i in range(len(meta_data)):
            meta_data[i] ^= 0x63
        
        # 去掉前缀
        if len(meta_data) > 22:
            meta_data = meta_data[22:]
            
            # Base64 解码
            try:
                decoded_meta = base64.b64decode(meta_data)
                decrypted_meta = aes_ecb_decrypt(decoded_meta, META_KEY)
                
                # 去除填充
                padding = decrypted_meta[-1]
                if padding <= 16:
                    decrypted_meta = decrypted_meta[:-padding]
                
                # 解析 JSON
                json_str = decrypted_meta.decode('utf-8')
                if json_str.startswith('music:'):
                    json_str = json_str[6:]
                    metadata = json.loads(json_str)
                    
                    print(f"\n📀 歌曲信息:")
                    print(f"   歌名: {metadata.get('musicName', '未知')}")
                    if 'artist' in metadata:
                        artists = [a[0] for a in metadata['artist'] if a]
                        print(f"   艺术家: {', '.join(artists)}")
                    if 'format' in metadata:
                        detected_format = metadata['format']
                        print(f"   格式: {detected_format}")
            except:
                pass
    
    # 5. 跳过 CRC
    offset += 5
    
    # 6. 跳过封面
    image_size = struct.unpack('<I', data[offset:offset+4])[0]
    offset += 4
    
    print(f"\n📷 封面信息:")
    print(f"   封面大小: {image_size} 字节")
    print(f"   封面偏移: {offset} (0x{offset:X})")
    
    offset += image_size
    
    # 7. 解密音频数据
    print(f"\n🎵 音频数据:")
    print(f"   起始偏移: {offset} (0x{offset:X})")
    print(f"   剩余数据: {len(data) - offset} 字节")
    
    audio_data = bytearray(data[offset:])
    
    # RC4-like 解密
    for i in range(len(audio_data)):
        idx1 = (i + 1) & 0xFF
        idx2 = (key_box[idx1] + key_box[(key_box[idx1] + idx1) & 0xFF]) & 0xFF
        k = key_box[idx2]
        audio_data[i] ^= k
    
    # 检查文件头
    print(f"\n🔍 解密后文件头:")
    print(f"   前16字节: {' '.join(f'{b:02X}' for b in audio_data[:16])}")
    
    if audio_data[:4] == b'fLaC':
        print(f"   ✅ 检测到 FLAC 格式")
        detected_format = 'flac'
    elif audio_data[:3] == b'ID3':
        print(f"   ✅ 检测到 MP3 (ID3v2)")
        detected_format = 'mp3'
    elif audio_data[0] == 0xFF and (audio_data[1] & 0xE0) == 0xE0:
        print(f"   ✅ 检测到 MP3 (帧同步)")
        detected_format = 'mp3'
    else:
        print(f"   ⚠️  无法识别格式，可能解密失败")
    
    # 保存
    output_path = input_path.rsplit('.', 1)[0] + f'_python.{detected_format}'
    with open(output_path, 'wb') as f:
        f.write(audio_data)
    
    print(f"\n✅ 输出文件: {output_path}")
    print(f"   大小: {len(audio_data) / 1024 / 1024:.2f} MB")
    
    return output_path

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("用法: python3 test_decryption_raw.py <ncm文件>")
        sys.exit(1)
    
    decrypt_ncm(sys.argv[1])

