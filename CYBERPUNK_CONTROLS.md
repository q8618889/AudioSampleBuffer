# 赛博朋克效果控制参数说明

## 🎛️ 新增功能

为赛博朋克效果添加了两个可控参数，方便调试和优化体验：

### 1. 高能效果开关 (`enableClimaxEffect`)
- **功能**：控制是否启用高潮特效（金色/橙色能量爆发）
- **默认值**：`YES` （开启）
- **效果**：
  - `YES`：启用高能效果，音乐高潮时显示特殊动画
  - `NO`：关闭高能效果，即使音乐高潮也不显示

### 2. 调试条显示开关 (`showDebugBars`)
- **功能**：控制是否显示红绿蓝黄音频强度条
- **默认值**：`NO` （隐藏）
- **效果**：
  - `YES`：显示屏幕中央的调试强度条（红色=低音，绿色=中音，蓝色=高音，黄色=isClimax）
  - `NO`：隐藏调试条，正常观看效果

---

## 📝 使用方法

### 方法 1: 通过 CyberPunkRenderer 直接控制

```objective-c
// 获取赛博朋克渲染器实例
CyberPunkRenderer *cyberpunkRenderer = (CyberPunkRenderer *)visualEffectManager.currentRenderer;

// 关闭高能效果
cyberpunkRenderer.enableClimaxEffect = NO;

// 显示调试条
cyberpunkRenderer.showDebugBars = YES;
```

### 方法 2: 在 VisualEffectManager 中添加便捷方法

可以在 `VisualEffectManager` 中添加以下方法：

```objective-c
// VisualEffectManager.h
- (void)setCyberpunkEnableClimaxEffect:(BOOL)enable;
- (void)setCyberpunkShowDebugBars:(BOOL)show;

// VisualEffectManager.m
- (void)setCyberpunkEnableClimaxEffect:(BOOL)enable {
    if ([self.currentRenderer isKindOfClass:[CyberPunkRenderer class]]) {
        CyberPunkRenderer *renderer = (CyberPunkRenderer *)self.currentRenderer;
        renderer.enableClimaxEffect = enable;
    }
}

- (void)setCyberpunkShowDebugBars:(BOOL)show {
    if ([self.currentRenderer isKindOfClass:[CyberPunkRenderer class]]) {
        CyberPunkRenderer *renderer = (CyberPunkRenderer *)self.currentRenderer;
        renderer.showDebugBars = show;
    }
}
```

### 方法 3: 在 ViewController 中添加 UI 控制

```objective-c
// 添加 UISwitch 控件
UISwitch *climaxEffectSwitch = [[UISwitch alloc] init];
[climaxEffectSwitch addTarget:self action:@selector(climaxEffectSwitchChanged:) forControlEvents:UIControlEventValueChanged];
climaxEffectSwitch.on = YES; // 默认开启

UISwitch *debugBarsSwitch = [[UISwitch alloc] init];
[debugBarsSwitch addTarget:self action:@selector(debugBarsSwitchChanged:) forControlEvents:UIControlEventValueChanged];
debugBarsSwitch.on = NO; // 默认隐藏

// 响应方法
- (void)climaxEffectSwitchChanged:(UISwitch *)sender {
    [self.visualEffectManager setCyberpunkEnableClimaxEffect:sender.on];
}

- (void)debugBarsSwitchChanged:(UISwitch *)sender {
    [self.visualEffectManager setCyberpunkShowDebugBars:sender.on];
}
```

---

## 🎨 使用场景

### 场景1：调试音频响应
```objective-c
// 显示调试条，查看音频数据是否正常
cyberpunkRenderer.showDebugBars = YES;
```
**观察**：
- 🔴 红条（低音）：有鼓点/贝斯时应该跳动
- 🟢 绿条（中音）：有人声/吉他时应该增长
- 🔵 蓝条（高音）：有镲片/高频音时应该显示
- 🟨 黄条（高潮）：音乐激烈段落时增长

### 场景2：降低刺眼程度
```objective-c
// 如果觉得高能效果太刺眼，可以暂时关闭
cyberpunkRenderer.enableClimaxEffect = NO;
```
**效果**：保留所有基础赛博朋克效果，仅关闭高能爆发动画

### 场景3：正常观看
```objective-c
// 隐藏调试条，完整体验效果
cyberpunkRenderer.enableClimaxEffect = YES;
cyberpunkRenderer.showDebugBars = NO;
```

---

## 🔧 技术实现

### Shader层（Shaders.metal）
```metal
// 控制参数从 uniforms.cyberpunkControls 读取
float enableClimaxEffect = uniforms.cyberpunkControls.x; // 0.0=关闭, 1.0=开启
float showDebugBars = uniforms.cyberpunkControls.y;      // 0.0=隐藏, 1.0=显示

// 应用高能效果开关
if (enableClimaxEffect < 0.5) {
    isClimax = 0.0; // 关闭时强制为0
}

// 应用调试条显示开关
if (showDebugBars > 0.5) {
    // 显示红绿蓝黄强度条
}
```

### 渲染器层（MetalRenderer.m）
```objective-c
// CyberPunkRenderer 属性
@property (nonatomic, assign) BOOL enableClimaxEffect;
@property (nonatomic, assign) BOOL showDebugBars;

// 在 updateUniforms 中传递给 shader
uniforms->cyberpunkControls = (vector_float4){
    cyberpunkRenderer.enableClimaxEffect ? 1.0f : 0.0f,
    cyberpunkRenderer.showDebugBars ? 1.0f : 0.0f,
    0.0f, // reserved1
    0.0f  // reserved2
};
```

---

## ⚠️ 注意事项

1. **实时生效**：修改属性后立即生效，无需重启渲染器
2. **仅对赛博朋克有效**：这两个控制只对 `CyberPunkRenderer` 有效
3. **线程安全**：属性修改在主线程进行
4. **默认值**：
   - `enableClimaxEffect = YES` （默认开启，提供完整体验）
   - `showDebugBars = NO` （默认隐藏，避免干扰观看）

---

## 🎯 推荐设置

| 场景 | enableClimaxEffect | showDebugBars | 说明 |
|-----|-------------------|---------------|------|
| **正常观看** | YES | NO | 完整体验，无干扰 |
| **调试音频** | YES | YES | 查看音频数据流动 |
| **降低刺眼** | NO | NO | 保留基础效果，去除爆发 |
| **开发测试** | YES | YES | 完整功能 + 数据可视化 |

---

## 📞 问题反馈

如果遇到问题或有改进建议，可以：
1. 检查 `CyberPunkRenderer` 是否正确初始化
2. 确认当前激活的渲染器类型
3. 使用 `showDebugBars = YES` 查看音频数据是否正常

---

**最后更新**: 2025-10-10
**版本**: v1.0

