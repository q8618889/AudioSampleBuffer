//
//  MetalRenderer.m
//  AudioSampleBuffer
//
//  Metal高性能渲染器实现
//

#import "MetalRenderer.h"
#import <simd/simd.h>

// 顶点结构体
typedef struct {
    vector_float2 position;
    vector_float4 color;
    vector_float2 texCoord;
} Vertex;

// 统一缓冲区结构体
typedef struct {
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 modelViewMatrix;
    vector_float4 time;
    vector_float4 resolution;
    vector_float4 audioData[80]; // 频谱数据
    vector_float4 galaxyParams1; // 星系参数1: (coreIntensity, edgeIntensity, rotationSpeed, glowRadius)
    vector_float4 galaxyParams2; // 星系参数2: (colorShiftSpeed, nebulaIntensity, pulseStrength, audioSensitivity)
    vector_float4 galaxyParams3; // 星系参数3: (starDensity, spiralArms, colorTheme, reserved)
    vector_float4 cyberpunkControls; // 赛博朋克控制: (enableClimaxEffect, showDebugBars, enableGrid, backgroundMode)
    vector_float4 cyberpunkFrequencyControls; // 赛博朋克频段控制: (enableBass, enableMid, enableTreble, reserved)
    vector_float4 cyberpunkBackgroundParams; // 赛博朋克背景参数: (solidColorR, solidColorG, solidColorB, intensity)
} Uniforms;

@interface BaseMetalRenderer ()
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) MTKView *metalView;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLLibrary> defaultLibrary;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id<MTLBuffer> uniformBuffer;
@property (nonatomic, assign) NSTimeInterval startTime;
@end

@implementation BaseMetalRenderer

- (instancetype)initWithMetalView:(MTKView *)metalView {
    if (self = [super init]) {
        _metalView = metalView;
        _device = metalView.device ?: MTLCreateSystemDefaultDevice();
        
        if (!_device) {
            NSLog(@"❌ Metal不受支持");
            return nil;
        }
        
        _commandQueue = [_device newCommandQueue];
        _defaultLibrary = [_device newDefaultLibrary];
        _renderParameters = [NSMutableDictionary dictionary];
        _startTime = CACurrentMediaTime();
        
        [self setupMetal];
        [self setupPipeline];
    }
    return self;
}

- (void)setupMetal {
    self.metalView.device = self.device;
    self.metalView.delegate = self;
    self.metalView.preferredFramesPerSecond = 60;
    self.metalView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.metalView.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    
    // 创建统一缓冲区
    self.uniformBuffer = [self.device newBufferWithLength:sizeof(Uniforms) 
                                                  options:MTLResourceStorageModeShared];
}

- (void)setupPipeline {
    // 子类需要重写此方法
}

- (void)updateSpectrumData:(NSArray<NSNumber *> *)spectrumData {
    // 防御性检查并copy数组，避免传入的数组在使用时被修改
    if (spectrumData && [spectrumData isKindOfClass:[NSArray class]]) {
        self.currentSpectrumData = [spectrumData copy];
    } else {
        self.currentSpectrumData = nil;
    }
}

- (void)setRenderParameters:(NSDictionary *)parameters {
    [self.renderParameters addEntriesFromDictionary:parameters];
}

- (void)startRendering {
    self.isRendering = YES;
    self.metalView.paused = NO;
}

- (void)stopRendering {
    self.isRendering = NO;
    self.metalView.paused = YES;
}

- (void)pauseRendering {
    self.metalView.paused = YES;
}

- (void)resumeRendering {
    self.metalView.paused = NO;
}

#pragma mark - MTKViewDelegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    // 处理尺寸变化
}

- (void)drawInMTKView:(MTKView *)view {
    if (!self.isRendering) return;
    
    NSTimeInterval currentTime = CACurrentMediaTime() - self.startTime;
    
    // 更新统一缓冲区
    [self updateUniforms:currentTime];
    
    // 创建命令缓冲区
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    commandBuffer.label = @"VisualEffect";
    
    // 获取渲染通道描述符
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    if (renderPassDescriptor) {
        // 创建渲染编码器
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"VisualEffectEncoder";
        
        // 编码渲染命令
        [self encodeRenderCommands:renderEncoder];
        
        [renderEncoder endEncoding];
        
        // 呈现drawable
        [commandBuffer presentDrawable:view.currentDrawable];
    }
    
    // 提交命令缓冲区
    [commandBuffer commit];
    
    // 通知代理
    if ([self.delegate respondsToSelector:@selector(metalRenderer:didFinishFrame:)]) {
        [self.delegate metalRenderer:self didFinishFrame:currentTime];
    }
}

- (void)updateUniforms:(NSTimeInterval)time {
    Uniforms *uniforms = (Uniforms *)[self.uniformBuffer contents];
    
    // 更新时间
    uniforms->time = (vector_float4){time, sin(time), cos(time), time * 0.5};
    
    // 更新分辨率 - 使用实际容器的宽高比来计算特效缩放
    CGSize drawableSize = self.metalView.drawableSize;
    
    // 如果有设置实际容器尺寸，使用它来计算宽高比
    // 否则使用Metal视图自己的尺寸（向后兼容）
    float aspectRatio;
    if (self.actualContainerSize.width > 0 && self.actualContainerSize.height > 0) {
        aspectRatio = self.actualContainerSize.width / self.actualContainerSize.height;
    } else {
        CGSize viewSize = self.metalView.frame.size;
        aspectRatio = viewSize.width / viewSize.height;
    }
    
    // resolution: (drawableWidth, drawableHeight, aspectRatio, pixelScale)
    uniforms->resolution = (vector_float4){drawableSize.width, drawableSize.height, aspectRatio, 1.0};
    
    // 调试日志（输出前几帧以便观察）
    static int frameCounter = 0;
    if (frameCounter < 3) {
        NSLog(@"📐 [帧%d] 分辨率设置:", frameCounter);
        NSLog(@"   Metal视图尺寸: %.0f x %.0f (正方形)", self.metalView.frame.size.width, self.metalView.frame.size.height);
        NSLog(@"   实际容器尺寸: %.0f x %.0f", self.actualContainerSize.width, self.actualContainerSize.height);
        NSLog(@"   绘制尺寸: %.0f x %.0f", drawableSize.width, drawableSize.height);
        NSLog(@"   宽高比: %.4f %@ (用于特效缩放)", aspectRatio, aspectRatio > 1.0 ? @"(横屏)" : @"(竖屏)");
        frameCounter++;
    }
    
    // 更新频谱数据 - 使用本地副本防止多线程问题
    NSArray<NSNumber *> *spectrumData = self.currentSpectrumData;
    if (spectrumData && spectrumData.count > 0) {
        NSUInteger count = MIN(spectrumData.count, 80);
        for (NSUInteger i = 0; i < count; i++) {
            NSNumber *number = spectrumData[i];
            // 防御性检查：确保数组元素不是nil
            if (number && [number isKindOfClass:[NSNumber class]]) {
                float value = [number floatValue];
                // 确保值是有效的（不是NaN或无穷大）
                if (!isnan(value) && !isinf(value)) {
                    uniforms->audioData[i] = (vector_float4){value, value * value, sqrt(fabs(value)), i / 80.0};
                } else {
                    uniforms->audioData[i] = (vector_float4){0.0, 0.0, 0.0, i / 80.0};
                }
            } else {
                uniforms->audioData[i] = (vector_float4){0.0, 0.0, 0.0, i / 80.0};
            }
        }
    }
    
    // 更新星系参数（如果是星系渲染器）
    if ([self isKindOfClass:[GalaxyRenderer class]]) {
        [self updateGalaxyUniforms:uniforms];
    }
    
    // 更新赛博朋克参数（如果是赛博朋克渲染器）
    if ([self isKindOfClass:[CyberPunkRenderer class]]) {
        [self updateCyberpunkUniforms:uniforms];
    }
    
    // 更新投影矩阵
    // float aspect = size.width / size.height; // 暂时未使用
    uniforms->projectionMatrix = matrix_identity_float4x4;
    uniforms->modelViewMatrix = matrix_identity_float4x4;
}

// 更新星系参数的方法（在子类中重写）
- (void)updateGalaxyUniforms:(Uniforms *)uniforms {
    // 默认实现，子类重写
}

// 更新赛博朋克参数的方法（在子类中重写）
- (void)updateCyberpunkUniforms:(Uniforms *)uniforms {
    // 默认实现，子类重写
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    // 子类需要重写此方法
}

#pragma mark - 辅助方法

- (id<MTLBuffer>)createBufferWithData:(const void *)data length:(NSUInteger)length {
    return [self.device newBufferWithBytes:data length:length options:MTLResourceStorageModeShared];
}

- (id<MTLTexture>)createTextureWithWidth:(NSUInteger)width height:(NSUInteger)height {
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                          width:width
                                                                                         height:height
                                                                                      mipmapped:NO];
    return [self.device newTextureWithDescriptor:descriptor];
}

@end

#pragma mark - 具体渲染器实现

@implementation NeonGlowRenderer

- (void)setupPipeline {
    // 创建霓虹发光效果的渲染管线
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"NeonGlow";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"neon_fragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    // 配置MSAA采样 - 匹配MTKView的设置
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    
    // 配置深度缓冲格式
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建霓虹发光管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    
    // 绘制全屏四边形
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation Waveform3DRenderer

- (void)setupPipeline {
    // 创建3D波形效果的渲染管线 - 使用通用顶点着色器
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"Waveform3D";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"waveform3d_fragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    // 配置MSAA采样 - 匹配MTKView的设置
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    
    // 配置深度缓冲格式
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建3D波形管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    
    // 绘制全屏四边形
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation FluidSimulationRenderer

- (void)setupPipeline {
    // 创建流体模拟效果的渲染管线
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"FluidSimulation";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"fluid_fragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    // 配置MSAA采样 - 匹配MTKView的设置
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    
    // 配置深度缓冲格式
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建流体模拟管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
    
    // 设置性能优化参数
    [self setupPerformanceOptimizations];
}

- (void)setupPerformanceOptimizations {
    // 根据设备性能调整渲染参数
    NSString *deviceName = self.device.name;
    NSMutableDictionary *params = [self.renderParameters mutableCopy] ?: [NSMutableDictionary dictionary];
    
    if ([deviceName containsString:@"A17"] || [deviceName containsString:@"A16"]) {
        // 高端设备 - 使用更高质量设置
        params[@"fluidQuality"] = @(1.0);
        params[@"particleCount"] = @(16);
        params[@"densityIterations"] = @(8);
        NSLog(@"🌊 流体模拟: 高端设备，使用高质量设置");
        
    } else if ([deviceName containsString:@"A15"] || [deviceName containsString:@"A14"]) {
        // 中端设备 - 平衡设置
        params[@"fluidQuality"] = @(0.8);
        params[@"particleCount"] = @(12);
        params[@"densityIterations"] = @(6);
        NSLog(@"🌊 流体模拟: 中端设备，使用平衡设置");
        
    } else {
        // 低端设备 - 性能优先
        params[@"fluidQuality"] = @(0.6);
        params[@"particleCount"] = @(8);
        params[@"densityIterations"] = @(4);
        NSLog(@"🌊 流体模拟: 低端设备，使用性能优化设置");
    }
    
    [self setRenderParameters:params];
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    
    // 绘制全屏四边形
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation QuantumFieldRenderer

- (void)setupPipeline {
    // 创建量子场效果的渲染管线
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"QuantumField";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"quantum_fragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    // 配置MSAA采样 - 匹配MTKView的设置
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    
    // 配置深度缓冲格式
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建量子场管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    
    // 绘制全屏四边形
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation HolographicRenderer

- (void)setupPipeline {
    // 创建全息效果的渲染管线
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"Holographic";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"holographic_fragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    // 配置MSAA采样 - 匹配MTKView的设置
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    
    // 配置深度缓冲格式
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建全息效果管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    
    // 绘制全屏四边形
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation CyberPunkRenderer

- (void)setupPipeline {
    // 创建赛博朋克效果的渲染管线
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"CyberPunk";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"cyberpunk_fragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    // 配置MSAA采样 - 匹配MTKView的设置
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    
    // 配置深度缓冲格式
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建赛博朋克管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
}

- (void)updateCyberpunkUniforms:(Uniforms *)uniforms {
    // 从渲染参数中获取赛博朋克设置
    NSDictionary *params = self.renderParameters;
    
    // 赛博朋克控制: (enableClimaxEffect, showDebugBars, enableGrid, backgroundMode)
    float enableClimaxEffect = [params[@"enableClimaxEffect"] floatValue];
    float showDebugBars = [params[@"showDebugBars"] floatValue];
    float enableGrid = [params[@"enableGrid"] floatValue];
    float backgroundMode = [params[@"backgroundMode"] floatValue];
    uniforms->cyberpunkControls = (vector_float4){enableClimaxEffect, showDebugBars, enableGrid, backgroundMode};
    
    // 赛博朋克频段控制: (enableBass, enableMid, enableTreble, reserved)
    float enableBassEffect = [params[@"enableBassEffect"] floatValue];
    float enableMidEffect = [params[@"enableMidEffect"] floatValue];
    float enableTrebleEffect = [params[@"enableTrebleEffect"] floatValue];
    uniforms->cyberpunkFrequencyControls = (vector_float4){enableBassEffect, enableMidEffect, enableTrebleEffect, 0.0f};
    
    // 赛博朋克背景参数: (solidColorR, solidColorG, solidColorB, intensity)
    float solidColorR = [params[@"solidColorR"] floatValue];
    float solidColorG = [params[@"solidColorG"] floatValue];
    float solidColorB = [params[@"solidColorB"] floatValue];
    float backgroundIntensity = [params[@"backgroundIntensity"] floatValue];
    uniforms->cyberpunkBackgroundParams = (vector_float4){solidColorR, solidColorG, solidColorB, backgroundIntensity};
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    
    // 绘制全屏四边形
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation GalaxyRenderer

- (void)setupPipeline {
    // 创建星系效果的渲染管线
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"Galaxy";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"galaxy_fragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    // 配置MSAA采样 - 匹配MTKView的设置
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    
    // 配置深度缓冲格式
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建星系管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
}

- (void)updateGalaxyUniforms:(Uniforms *)uniforms {
    // 从渲染参数中获取星系设置
    NSDictionary *params = self.renderParameters;
    
    // 星系参数1: (coreIntensity, edgeIntensity, rotationSpeed, glowRadius)
    float coreIntensity = [params[@"coreIntensity"] floatValue] ?: 2.0f;
    float edgeIntensity = [params[@"edgeIntensity"] floatValue] ?: 1.0f;
    float rotationSpeed = [params[@"rotationSpeed"] floatValue] ?: 0.5f;
    float glowRadius = [params[@"glowRadius"] floatValue] ?: 0.3f;
    uniforms->galaxyParams1 = (vector_float4){coreIntensity, edgeIntensity, rotationSpeed, glowRadius};
    
    // 星系参数2: (colorShiftSpeed, nebulaIntensity, pulseStrength, audioSensitivity)
    float colorShiftSpeed = [params[@"colorShiftSpeed"] floatValue] ?: 1.0f;
    float nebulaIntensity = [params[@"nebulaIntensity"] floatValue] ?: 0.3f;
    float pulseStrength = [params[@"pulseStrength"] floatValue] ?: 0.1f;
    float audioSensitivity = [params[@"audioSensitivity"] floatValue] ?: 1.5f;
    uniforms->galaxyParams2 = (vector_float4){colorShiftSpeed, nebulaIntensity, pulseStrength, audioSensitivity};
    
    // 星系参数3: (starDensity, spiralArms, colorTheme, reserved)
    float starDensity = [params[@"starDensity"] floatValue] ?: 0.7f;
    float spiralArms = [params[@"spiralArms"] floatValue] ?: 2.0f;
    float colorTheme = [params[@"colorTheme"] floatValue] ?: 0.0f;
    uniforms->galaxyParams3 = (vector_float4){starDensity, spiralArms, colorTheme, 0.0f};
    
    NSLog(@"🌌 更新星系参数: 核心亮度=%.2f, 边缘亮度=%.2f, 旋转速度=%.2f, 颜色主题=%.0f", 
          coreIntensity, edgeIntensity, rotationSpeed, colorTheme);
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    
    // 绘制全屏四边形
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation LiquidMetalRenderer

- (void)setupPipeline {
    // 创建液态金属效果的渲染管线（使用流体模拟着色器）
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"LiquidMetal";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"fluid_fragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    // 配置MSAA采样 - 匹配MTKView的设置
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    
    // 配置深度缓冲格式
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建液态金属管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    
    // 绘制全屏四边形
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation LightningRenderer

- (void)setupPipeline {
    // 创建闪电雷暴效果的渲染管线
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"Lightning";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"lightning_fragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    // 配置MSAA采样 - 匹配MTKView的设置
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    
    // 配置深度缓冲格式
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建闪电雷暴管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    
    // 绘制全屏四边形
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation DefaultEffectRenderer

- (void)setupPipeline {
    // 创建默认效果的渲染管线（使用霓虹效果）
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"Default";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"neon_fragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    // 配置MSAA采样 - 匹配MTKView的设置
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    
    // 配置深度缓冲格式
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建默认效果管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    
    // 绘制全屏四边形
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

#pragma mark - 渲染器工厂

@implementation MetalRendererFactory

+ (instancetype)sharedFactory {
    static MetalRendererFactory *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MetalRendererFactory alloc] init];
    });
    return instance;
}

- (id<MetalRenderer>)createRendererForEffect:(VisualEffectType)effectType 
                                   metalView:(MTKView *)metalView {
    switch (effectType) {
        case VisualEffectTypeNeonGlow:
            return [[NeonGlowRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectType3DWaveform:
            return [[Waveform3DRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectTypeFluidSimulation:
            return [[FluidSimulationRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectTypeQuantumField:
            return [[QuantumFieldRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectTypeHolographic:
            return [[HolographicRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectTypeCyberPunk:
            return [[CyberPunkRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectTypeGalaxy:
            return [[GalaxyRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectTypeLiquidMetal:
            return [[LiquidMetalRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectTypeLightning:
            return [[LightningRenderer alloc] initWithMetalView:metalView];
            
        default:
            return [[DefaultEffectRenderer alloc] initWithMetalView:metalView];
    }
}

+ (BOOL)isMetalSupported {
    return MTLCreateSystemDefaultDevice() != nil;
}

+ (NSDictionary *)recommendedSettingsForDevice:(id<MTLDevice>)device {
    // 根据设备性能返回推荐设置
    NSString *deviceName = device.name;
    
    if ([deviceName containsString:@"A17"] || [deviceName containsString:@"A16"]) {
        // 高端设备
        return @{
            @"preferredFramesPerSecond": @(120),
            @"enableComplexEffects": @(YES),
            @"particleCount": @(10000),
            @"textureQuality": @"high"
        };
    } else if ([deviceName containsString:@"A15"] || [deviceName containsString:@"A14"]) {
        // 中端设备
        return @{
            @"preferredFramesPerSecond": @(60),
            @"enableComplexEffects": @(YES),
            @"particleCount": @(5000),
            @"textureQuality": @"medium"
        };
    } else {
        // 低端设备
        return @{
            @"preferredFramesPerSecond": @(30),
            @"enableComplexEffects": @(NO),
            @"particleCount": @(1000),
            @"textureQuality": @"low"
        };
    }
}

@end
