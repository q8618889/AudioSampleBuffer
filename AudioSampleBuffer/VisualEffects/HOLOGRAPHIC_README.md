# 全息效果控制系统

## 功能概述

全息效果现在支持基于音乐波动的多维度响应系统，包括整体转动、扩散效果和可视化控制面板。

## 🔥 高潮检测系统

### 多维度检测指标

1. **综合能量响应** - 总体音频强度
2. **低音响应** - 低频段（0-10）增强检测
3. **中音响应** - 中频段（10-40）增强检测
4. **高音响应** - 高频段（40-79）增强检测
5. **峰值响应** - 检测音频峰值时刻

### 响应效果

- **阈值**: 8% 开始响应，35% 达到满值
- **非线性压缩**: 高值时自动压缩，避免刺眼
- **最终范围**: 0.0 - 1.6

## 🌀 音乐驱动效果

### 1. 整体转动
- 基于音乐强度的旋转速度
- 低音增强转动效果
- 可通过控制面板调节速度倍率（0-2倍）

### 2. 扩散/收缩
- 低音驱动的扩散效果
- 高潮时刻的脉冲式扩散
- 可通过控制面板调节幅度（0-2倍）

### 3. 径向频谱条
- 音乐强度影响能量条长度
- 能量流动速度随音乐加速
- 亮度随音乐强度增强

## 🎛️ 控制面板使用

### 显示控制面板

```objc
HolographicControlPanel *controlPanel = [[HolographicControlPanel alloc] initWithFrame:frame];
controlPanel.delegate = self;
[self.view addSubview:controlPanel];
[controlPanel showAnimated:YES];
```

### 实现代理

```objc
#pragma mark - HolographicControlDelegate

- (void)holographicControlDidUpdateSettings:(NSDictionary *)settings {
    // 更新 shader 参数
    float enableRotation = [settings[@"enableRotation"] floatValue];
    float rotationSpeed = [settings[@"rotationSpeed"] floatValue];
    float expansionAmount = [settings[@"expansionAmount"] floatValue];
    
    // 传递给 Metal shader
    // uniforms.customParams.x = enableRotation;
    // uniforms.customParams.y = rotationSpeed;
    // uniforms.customParams.z = expansionAmount;
}
```

### 可控参数

#### 开关控制
- `enableRotation` - 启用音乐驱动转动
- `enableExpansion` - 启用低音扩散效果
- `enableMusicIntensity` - 启用高潮检测
- `enableBassResponse` - 启用低音响应增强
- `enableMidResponse` - 启用中音响应增强
- `enableTrebleResponse` - 启用高音响应增强

#### 滑块控制
- `rotationSpeed` (0.0 - 2.0) - 转动速度倍率
- `expansionAmount` (0.0 - 2.0) - 扩散幅度倍率
- `particleDensity` (0.0 - 2.0) - 粒子密度倍率

## 🎨 视觉效果特点

### 转动效果
- ✅ 随音乐节奏旋转
- ✅ 低音强化转动
- ✅ 高潮时刻加速旋转
- ✅ 平滑过渡，不卡顿

### 扩散效果
- ✅ 低音驱动扩散
- ✅ 脉冲式呼吸效果
- ✅ 音乐强度叠加
- ✅ 自然的收缩-扩散循环

### 音频响应
- ✅ 多维度检测系统
- ✅ 频段独立控制
- ✅ 峰值时刻增强
- ✅ 避免过度刺眼

## 📊 调试建议

1. 使用控制面板实时调整参数
2. 观察不同音乐类型的响应效果
3. 根据音乐风格调整转动和扩散幅度
4. 低音多的音乐可降低扩散幅度
5. 节奏快的音乐可提高转动速度

## 🚀 性能优化

- 使用 Metal GPU 加速
- 高效的音频数据处理
- 优化的旋转和扩散算法
- 智能的响应曲线设计

## 🎯 最佳实践

1. **电子音乐**: 开启所有响应，转动速度 1.5x，扩散幅度 1.2x
2. **古典音乐**: 关闭转动，扩散幅度 0.8x，中音响应为主
3. **摇滚音乐**: 低音响应增强，转动速度 1.0x，扩散幅度 1.5x
4. **轻音乐**: 转动速度 0.5x，扩散幅度 0.6x，减少粒子密度

---

享受梦幻的全息音频可视化体验！🌌✨

