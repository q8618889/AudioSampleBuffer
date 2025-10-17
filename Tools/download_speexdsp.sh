#!/bin/bash
#
# SpeexDSP 下载和集成脚本
# 用法: ./download_speexdsp.sh
#

set -e  # 遇到错误立即退出

echo "🚀 开始下载和集成 SpeexDSP..."

# 配置
SPEEXDSP_VERSION="1.2.1"
SPEEXDSP_URL="https://gitlab.xiph.org/xiph/speexdsp/-/archive/SpeexDSP-${SPEEXDSP_VERSION}/speexdsp-SpeexDSP-${SPEEXDSP_VERSION}.tar.gz"
PROJECT_DIR="../AudioSampleBuffer/Karaoke/DSP/SpeexDSP"
TMP_DIR="/tmp/speexdsp_download"

echo "📦 版本: ${SPEEXDSP_VERSION}"
echo "📂 目标目录: ${PROJECT_DIR}"

# 创建临时目录
mkdir -p "${TMP_DIR}"
cd "${TMP_DIR}"

# 下载源码
echo ""
echo "⬇️  下载 SpeexDSP 源码..."
if [ -f "speexdsp.tar.gz" ]; then
    echo "   已存在，跳过下载"
else
    curl -L "${SPEEXDSP_URL}" -o speexdsp.tar.gz
    echo "   ✅ 下载完成"
fi

# 解压
echo ""
echo "📦 解压源码..."
tar -xzf speexdsp.tar.gz
EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "speexdsp-*" | head -n 1)
echo "   ✅ 解压完成: ${EXTRACTED_DIR}"

# 创建项目目录
echo ""
echo "📁 创建项目目录..."
mkdir -p "${PROJECT_DIR}"

# 复制必要的头文件
echo ""
echo "📄 复制头文件..."
cp "${EXTRACTED_DIR}/include/speex/speex_preprocess.h" "${PROJECT_DIR}/"
cp "${EXTRACTED_DIR}/include/speex/speex_echo.h" "${PROJECT_DIR}/"
cp "${EXTRACTED_DIR}/include/speex/speex_resampler.h" "${PROJECT_DIR}/"
cp "${EXTRACTED_DIR}/include/speex/speexdsp_types.h" "${PROJECT_DIR}/"
cp "${EXTRACTED_DIR}/include/speex/speexdsp_config_types.h.in" "${PROJECT_DIR}/speexdsp_config_types.h"

# 修改配置文件（替换@SIZE16@等宏）
sed -i '' 's/@SIZE16@/int16_t/g' "${PROJECT_DIR}/speexdsp_config_types.h"
sed -i '' 's/@USIZE16@/uint16_t/g' "${PROJECT_DIR}/speexdsp_config_types.h"
sed -i '' 's/@SIZE32@/int32_t/g' "${PROJECT_DIR}/speexdsp_config_types.h"
sed -i '' 's/@USIZE32@/uint32_t/g' "${PROJECT_DIR}/speexdsp_config_types.h"

echo "   ✅ 头文件已复制"

# 复制核心实现文件
echo ""
echo "💾 复制实现文件..."
IMPL_FILES=(
    "preprocess.c"
    "speex_echo.c"
    "resample.c"
    "filterbank.c"
    "fftwrap.c"
    "kiss_fft.c"
    "kiss_fftr.c"
    "mdf.c"
)

for file in "${IMPL_FILES[@]}"; do
    if [ -f "${EXTRACTED_DIR}/libspeexdsp/${file}" ]; then
        cp "${EXTRACTED_DIR}/libspeexdsp/${file}" "${PROJECT_DIR}/"
        echo "   ✅ ${file}"
    else
        echo "   ⚠️  未找到: ${file}"
    fi
done

# 复制内部头文件
echo ""
echo "📄 复制内部头文件..."
HEADER_FILES=(
    "arch.h"
    "filterbank.h"
    "fixed_generic.h"
    "kiss_fft.h"
    "kiss_fftr.h"
    "pseudofloat.h"
    "fftwrap.h"
    "_kiss_fft_guts.h"
    "os_support.h"
    "smallft.h"
)

for file in "${HEADER_FILES[@]}"; do
    if [ -f "${EXTRACTED_DIR}/libspeexdsp/${file}" ]; then
        cp "${EXTRACTED_DIR}/libspeexdsp/${file}" "${PROJECT_DIR}/"
        echo "   ✅ ${file}"
    fi
done

# 创建配置头文件
echo ""
echo "⚙️  创建配置文件..."
cat > "${PROJECT_DIR}/config.h" << 'EOF'
/* SpeexDSP iOS/macOS 配置文件 */
#ifndef CONFIG_H
#define CONFIG_H

#define FLOATING_POINT 1
#define USE_KISS_FFT 1
#define EXPORT __attribute__((visibility("default")))

/* 采样率转换 */
#define RESAMPLE_FULL_SINC_TABLE 1

/* 禁用不需要的功能 */
#define DISABLE_WIDEBAND 0
#define DISABLE_VBR 0

#endif /* CONFIG_H */
EOF
echo "   ✅ config.h 已创建"

# 清理
echo ""
echo "🧹 清理临时文件..."
cd ..
rm -rf "${TMP_DIR}"
echo "   ✅ 清理完成"

# 统计
echo ""
echo "📊 集成统计:"
echo "   头文件: $(find "${PROJECT_DIR}" -name "*.h" | wc -l) 个"
echo "   实现文件: $(find "${PROJECT_DIR}" -name "*.c" | wc -l) 个"

echo ""
echo "✅ SpeexDSP 下载和集成完成！"
echo ""
echo "📝 后续步骤:"
echo "   1. 将 ${PROJECT_DIR} 添加到 Xcode 项目"
echo "   2. 在 SpeexDSPBridge.mm 中取消注释"
echo "   3. 测试编译和运行"
echo ""
