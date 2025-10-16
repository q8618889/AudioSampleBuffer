#!/bin/bash

# 测试 NCM 解密算法（基于 taurusxin/ncmdump）
# 该脚本测试更新后的 AudioFileFormats.m 实现

echo "=========================================="
echo "  NCM 解密算法测试"
echo "  基于 taurusxin/ncmdump 最新实现"
echo "=========================================="
echo ""

# 检查是否有 NCM 文件
NCM_FILES=$(find ../AudioSampleBuffer/Audio -name "*.ncm" 2>/dev/null | head -5)

if [ -z "$NCM_FILES" ]; then
    echo "❌ 未找到 NCM 测试文件"
    echo ""
    echo "请将 NCM 测试文件放入以下目录："
    echo "  ../AudioSampleBuffer/Audio/"
    echo ""
    exit 1
fi

echo "找到以下 NCM 文件："
echo "$NCM_FILES" | nl
echo ""

# 编译测试程序
echo "📦 编译测试程序..."
cd "$(dirname "$0")"

clang -framework Foundation -framework Security \
    -o /tmp/ncm_test \
    test_ncm_decryptor.m \
    ../AudioSampleBuffer/AudioFileFormats.m \
    -I../AudioSampleBuffer \
    2>&1 | grep -v "warning"

if [ $? -ne 0 ]; then
    echo "❌ 编译失败"
    exit 1
fi

echo "✅ 编译成功"
echo ""

# 测试每个文件
TEST_COUNT=0
SUCCESS_COUNT=0

while IFS= read -r ncm_file; do
    if [ -z "$ncm_file" ]; then
        continue
    fi
    
    TEST_COUNT=$((TEST_COUNT + 1))
    echo "=========================================="
    echo "测试 #$TEST_COUNT"
    echo "=========================================="
    
    /tmp/ncm_test "$ncm_file"
    
    if [ $? -eq 0 ]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    fi
    
    echo ""
done <<< "$NCM_FILES"

# 清理
rm -f /tmp/ncm_test

echo "=========================================="
echo "📊 测试结果统计"
echo "=========================================="
echo "成功: $SUCCESS_COUNT / $TEST_COUNT"
echo ""

if [ $SUCCESS_COUNT -eq $TEST_COUNT ]; then
    echo "✅ 所有测试通过！"
    exit 0
else
    echo "⚠️  部分测试失败"
    exit 1
fi

