#!/usr/bin/env python3
"""
调试 NCM 解密 - 打印每一步的详细信息
"""

import struct
import sys
from Crypto.Cipher import AES
from Crypto.Util.Padding import unpad

CORE_KEY = bytes.fromhex('687A4852416D736F356B496E62617857')
META_KEY = bytes.fromhex('2331346C6A6B5F215C5D2630553C2728')

def debug_ncm(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()
    
    offset = 0
    
    # 1. 文件头
    assert data[offset:offset+8] == b'CTENFDAM'
    offset += 10
    
    # 2. 密钥
    key_length = struct.unpack('<I', data[offset:offset+4])[0]
    offset += 4
    
    key_data = bytearray(data[offset:offset+key_length])
    offset += key_length
    
    # XOR 0x64
    for i in range(len(key_data)):
        key_data[i] ^= 0x64
    
    # AES 解密
    cipher = AES.new(CORE_KEY, AES.MODE_ECB)
    decrypted_key = unpad(cipher.decrypt(bytes(key_data)), 16)[17:]
    
    print(f"解密密钥长度: {len(decrypted_key)}")
    print(f"密钥前16字节: {' '.join(f'{b:02X}' for b in decrypted_key[:16])}")
    
    # 3. 生成密钥盒
    S = bytearray(range(256))
    j = 0
    for i in range(256):
        j = (j + S[i] + decrypted_key[i % len(decrypted_key)]) & 0xFF
        S[i], S[j] = S[j], S[i]
    
    print(f"密钥盒前8个: {' '.join(f'{s:02X}' for s in S[:8])}")
    
    # 4. 跳过元数据
    meta_length = struct.unpack('<I', data[offset:offset+4])[0]
    offset += 4
    offset += meta_length
    
    # 5. 跳过 CRC
    offset += 5
    
    # 6. 图片
    image_space = struct.unpack('<I', data[offset:offset+4])[0]
    offset += 4
    image_size = struct.unpack('<I', data[offset:offset+4])[0]
    offset += 4
    
    print(f"\n图片信息:")
    print(f"  imageSpace = {image_space}")
    print(f"  imageSize = {image_size}")
    print(f"  当前 offset = {offset}")
    
    offset += image_size
    offset += (image_space - image_size)
    
    print(f"  跳过图片后 offset = {offset} (0x{offset:X})")
    
    # 7. 生成密钥流
    stream = [S[(S[i] + S[(i + S[i]) & 0xFF]) & 0xFF] for i in range(256)]
    
    print(f"\n密钥流前16个: {' '.join(f'{s:02X}' for s in stream[:16])}")
    
    # 8. 解密音频数据（前64字节）
    audio_data = data[offset:offset+64]
    
    print(f"\n加密音频前16字节: {' '.join(f'{b:02X}' for b in audio_data[:16])}")
    
    # 使用密钥流解密（从第2个字节开始）
    decrypted = bytearray()
    for i in range(len(audio_data)):
        k = stream[(i + 1) % 256]
        decrypted.append(audio_data[i] ^ k)
    
    print(f"解密音频前16字节: {' '.join(f'{b:02X}' for b in decrypted[:16])}")
    
    # 检查
    if decrypted[:3] == b'ID3':
        print("\n✅ 成功！检测到 ID3 标签")
    elif decrypted[0] == 0xFF and (decrypted[1] & 0xE0) == 0xE0:
        print("\n✅ 成功！检测到 MP3 帧同步")
    elif decrypted[:4] == b'fLaC':
        print("\n✅ 成功！检测到 FLAC")
    else:
        print("\n❌ 失败！无法识别格式")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("用法: python3 debug_ncm.py <ncm文件>")
        sys.exit(1)
    
    debug_ncm(sys.argv[1])

