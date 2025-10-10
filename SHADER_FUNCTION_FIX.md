# 🔧 Metal着色器函数声明修复

## 🐛 问题描述

Metal着色器编译报错：
```
Use of undeclared identifier 'fractalNoise'
```

**原因**: `fractalNoise` 函数在星系着色器中被使用，但函数定义在文件末尾，违反了Metal着色语言的函数声明规则。

## ✅ 修复方案

### 📝 函数声明顺序问题
在Metal着色语言中，函数必须在使用前声明或定义。

**之前的错误结构**:
```metal
// 星系着色器使用了 fractalNoise()
fragment float4 galaxy_fragment(...) {
    float star1 = step(0.995, fractalNoise(starUV1, 2)); // ❌ 未声明
    // ...
}

// 函数定义在最后
float fractalNoise(float2 uv, int octaves) { // 太晚了！
    // ...
}
```

**修复后的正确结构**:
```metal
// 1. 先定义辅助函数
float noise(float2 uv) {
    return fract(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
}

float fractalNoise(float2 uv, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    
    for (int i = 0; i < octaves; i++) {
        value += noise(uv) * amplitude;
        uv *= 2.0;
        amplitude *= 0.5;
    }
    
    return value;
}

// 2. 然后定义使用这些函数的着色器
fragment float4 galaxy_fragment(...) {
    float star1 = step(0.995, fractalNoise(starUV1, 2)); // ✅ 已声明
    // ...
}
```

## 🛠️ 具体修复步骤

### 1. 移动函数定义位置
将 `noise()` 和 `fractalNoise()` 函数从文件末尾移动到文件开头，紧跟结构体定义之后。

### 2. 删除重复定义
删除文件末尾的重复函数定义，避免重复声明错误。

### 3. 组织代码结构
```metal
#include <metal_stdlib>
using namespace metal;

// 结构体定义
struct Vertex { ... };
struct RasterizerData { ... };
struct Uniforms { ... };

// 辅助函数（最重要！）
float noise(float2 uv) { ... }
float fractalNoise(float2 uv, int octaves) { ... }

// 各种着色器函数
vertex RasterizerData neon_vertex(...) { ... }
fragment float4 neon_fragment(...) { ... }
fragment float4 galaxy_fragment(...) { ... } // 现在可以使用 fractalNoise
```

## 🌟 函数说明

### `noise(float2 uv)`
基础噪声函数，生成伪随机值：
```metal
float noise(float2 uv) {
    return fract(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
}
```

### `fractalNoise(float2 uv, int octaves)`
分形噪声函数，用于创建复杂的自然纹理：
```metal
float fractalNoise(float2 uv, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    
    for (int i = 0; i < octaves; i++) {
        value += noise(uv) * amplitude;
        uv *= 2.0;         // 增加频率
        amplitude *= 0.5;   // 减少幅度
    }
    
    return value;
}
```

## 🌌 在星系效果中的应用

分形噪声在星系效果中用于创建：

1. **星星分布** - 自然的星星位置
2. **星云纹理** - 复杂的云状结构  
3. **密度变化** - 真实的天体密度分布

```metal
// 大星星（亮星）
float star1 = step(0.995, fractalNoise(starUV1, 2));

// 中等星星
float star2 = step(0.99, fractalNoise(starUV2, 3));

// 小星星（密集）
float star3 = step(0.985, fractalNoise(starUV3, 4));

// 星云效果
float nebula = fractalNoise(uv * 2.0 + time * 0.05, 4) * 0.3;
```

## ✅ 修复结果

- ✅ **编译成功** - 不再有 `undeclared identifier` 错误
- ✅ **功能正常** - 星系效果的星星和星云正常显示
- ✅ **代码清晰** - 函数组织更加合理
- ✅ **可维护性** - 辅助函数易于查找和修改

现在星系效果可以正常使用分形噪声生成美丽的星空和星云效果了！🌌✨

