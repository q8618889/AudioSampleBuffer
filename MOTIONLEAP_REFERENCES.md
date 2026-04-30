# Motionleap Core Feature References

本文件用于记录后续复刻 Motionleap 核心能力时可参考的项目、论文方向与工程落地线索。

目标功能聚焦：

- 静态图片局部区域涂抹
- 为涂抹区域设置运动方向
- 生成循环局部动画
- 后续扩展到锚点、冻结区、羽化、导出视频/GIF

## 1. 结论先记

当前没有找到可确认的 Motionleap 官方开源核心仓库。

后续最可行的参考路线不是寻找“Motionleap clone”名称相似项目，而是组合以下三类资料：

- 算法思路：mask + motion hints + dense flow map + warp animation
- Apple 端工程：iOS / Metal 图像变形、实时渲染、交互输入
- 产品交互：笔刷、箭头、锚点、冻结区、循环播放、导出

## 2. 高优先级参考

### A. Controllable Animation of Fluid Elements in Still Images

- 链接: https://controllable-cinemagraphs.github.io/
- 类型: 研究项目 / 项目页
- 价值:
  - 非常接近 Motionleap 核心逻辑
  - 用户输入可动区域、方向提示、运动速度
  - 系统再生成稠密流场并合成循环动画
- 推荐关注:
  - 用户提示如何转成 dense motion field
  - 区域边界如何平滑过渡
  - 循环动画如何减少跳变
- 对本项目的意义:
  - 这是“涂抹区域 + 设置方向 + 动起来”最值得优先研究的思路

### B. text2cinemagraph

- 链接: https://github.com/text2cinemagraph
- 类型: GitHub 研究代码
- 价值:
  - 明确涉及 cinemagraph / still image animation
  - 可用于理解 flow hints、流场生成、动画合成
- 推荐关注:
  - 输入提示的表达方式
  - 流场或运动先验的组织方式
  - 输出动画的合成方式
- 注意:
  - 更偏研究代码，不是可直接嵌入 iOS App 的现成模块

## 3. 图像运动 / 光流 / 形变参考

### C. depthstillation

- 链接: https://github.com/mattpoggi/depthstillation
- 类型: GitHub 研究代码
- 价值:
  - 帮助理解“由单张静态图构造运动感”的方法
  - 虽不等于 Motionleap，但有利于理解 motion synthesis
- 推荐关注:
  - 如何从单帧构造位移 / 动画先验
  - 如何减少明显伪影

### D. comfyui-optical-flow

- 链接: https://github.com/seanlynch/comfyui-optical-flow
- 类型: GitHub 工具/节点扩展
- 价值:
  - 便于理解 optical flow 的输入输出结构
  - 对后续 shader warp 或 flow map 存储设计有参考意义
- 推荐关注:
  - flow map 数据表达
  - 如何把 flow 应用到图像重映射

## 4. iOS / Metal 工程落地参考

### E. sample-metal

- 链接: https://github.com/dehesa/sample-metal
- 类型: GitHub Metal 示例集合
- 价值:
  - 适合参考 Metal 纹理、采样、pipeline、compute 等基础实现
  - 对把算法思路落到 Apple 端很有帮助
- 推荐关注:
  - 纹理读写
  - compute shader 基础结构
  - render pipeline 组织方式

### F. metal-by-example sample-code

- 链接: https://github.com/metal-by-example/sample-code
- 类型: GitHub Metal 示例
- 价值:
  - 适合作为图像变形、采样、实时参数调节的工程参照
- 推荐关注:
  - 图像坐标与纹理坐标映射
  - GPU 侧参数传递
  - 实时渲染更新

### G. sepconv-ios

- 链接: https://github.com/carlo-/sepconv-ios
- 类型: GitHub iOS + CoreML + Metal 项目
- 价值:
  - 虽然主要做插帧，不是 Motionleap 同类产品
  - 但证明复杂图像时序处理可在 iOS 端较完整落地
- 推荐关注:
  - CoreML 与 Metal 协作模式
  - 图片处理链路在 iOS 上的组织方式

## 5. 产品形态参考

### H. Disflow - Motion Image Editor

- 链接: https://apps.apple.com/us/app/disflow-motion-image-editor/id1461050897
- 类型: 商业竞品参考
- 价值:
  - 不是开源项目，但交互形态与 Motionleap 接近
  - 可用于观察笔刷、箭头、冻结区、回放等产品交互

## 6. 对当前仓库的落地方向

结合当前仓库现状，后续复刻建议优先走本地实时渲染路线，而不是先接训练或大模型生成路线。

原因：

- 现有工程已经具备 iOS 图像显示和 Metal 渲染基础
- 已有多个视觉效果模块，可复用渲染组织方式
- 目标第一阶段更适合做交互式局部动画编辑器

当前仓库里值得复用或对照的模块：

- `AudioSampleBuffer/AudioSampleBuffer/SpectrumView.m`
- `AudioSampleBuffer/VisualEffects/Metal/MetalRenderer.m`
- `AudioSampleBuffer/ViewController+Visuals.m`
- `AudioSampleBuffer/ViewController+Library.m`

## 7. 建议的 MVP 拆分

第一版先做最小闭环：

1. 选择一张图片
2. 在图片上笔刷涂抹出可动区域 mask
3. 为 mask 设置一个主方向向量
4. 在 Metal shader 中对该区域做周期性 UV 偏移
5. 提供强度、速度、羽化参数
6. 支持播放 / 暂停预览

这一版先不追求：

- AI 自动抠图
- 多区域复杂流场编辑
- 遮挡修复
- 高质量导出
- 逼真的前后景分层

## 8. 后续代码模块建议

建议未来新增以下模块：

- `MotionPhotoEditorViewController`
- `MotionBrushMaskView`
- `MotionVectorOverlayView`
- `MotionWarpRenderer`
- `MotionLoopController`
- `MotionProject` 数据模型

## 9. 后续调研关键词

后续如果继续搜资料，可优先用这些关键词：

- `still image animation motion hints`
- `cinemagraph flow hints`
- `image warping vector field metal ios`
- `local motion photo editor`
- `brush mask optical flow animation`

## 10. 一句话判断

复刻 Motionleap 的核心功能是可行的。

真正的难点不在“让它动起来”，而在：

- 边缘过渡自然
- 区域约束稳定
- 循环无跳变
- 交互足够顺手

因此实施顺序建议是：

先做可控的局部 warp MVP，再逐步补锚点、冻结区、羽化与导出能力。
