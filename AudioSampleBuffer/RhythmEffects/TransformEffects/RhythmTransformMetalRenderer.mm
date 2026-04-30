#import "RhythmTransformMetalRenderer.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <simd/simd.h>

namespace {
struct TransformEnvelopeState {
    float pulse = 0.0f;
    float strongMix = 0.0f;
    float beatTime = 10.0f;
    uint32_t beatCount = 0;
    float beatSyncPhase = 0.0f;

    void trigger(float mix, float beatBoost) {
        pulse = fmaxf(pulse, 0.55f + beatBoost * 0.95f + mix * 0.45f);
        strongMix = mix;
        beatTime = 0.0f;
        beatCount += 1;
        beatSyncPhase = fmaxf(beatSyncPhase, 1.6f + 0.5f * mix);
    }

    void tick(float dt) {
        beatTime += dt;
        pulse *= expf(-3.1f * dt);
        if (pulse < 0.01f) pulse = 0.0f;
        beatSyncPhase *= expf(-2.2f * dt);
        if (beatSyncPhase < 0.01f) beatSyncPhase = 0.0f;
    }
};
}

typedef struct {
    vector_float2 position;
    vector_float2 uv;
} RhythmTransformVertex;

typedef struct {
    vector_float2 resolution;
    vector_float2 videoSize;
    float time;
    float baseIntensity;
    float beatPulse;
    float beatTime;
    float strongMix;
    float radius;
    float speed;
    int effectType;
    float beatSyncMix;
} RhythmTransformUniforms;

@interface RhythmTransformMetalRenderer () <MTKViewDelegate>

@property (nonatomic, strong) MTKView *metalView;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLLibrary> library;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id<MTLBuffer> vertexBuffer;
@property (nonatomic, strong) id<MTLBuffer> uniformBuffer;
@property (nonatomic, assign) CVMetalTextureCacheRef textureCache;
@property (nonatomic, weak, nullable) AVPlayer *player;
@property (nonatomic, strong, nullable) AVPlayerItem *currentItem;
@property (nonatomic, strong, nullable) AVPlayerItemVideoOutput *videoOutput;
@property (nonatomic, assign) CGSize currentVideoSize;
@property (nonatomic, assign) CFTimeInterval elapsedTime;
@property (nonatomic, assign) TransformEnvelopeState envelopeState;

@end

@implementation RhythmTransformMetalRenderer

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super init];
    if (self) {
        _device = MTLCreateSystemDefaultDevice();
        if (!_device) {
            return nil;
        }

        _effectType = RhythmFeatureEffectTypeDroplet;
        _baseIntensity = 0.72;
        _beatBoost = 0.82;
        _radius = 0.56;
        _speed = 0.64;
        _currentVideoSize = CGSizeZero;

        _metalView = [[MTKView alloc] initWithFrame:frame device:_device];
        _metalView.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
        _metalView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        _metalView.framebufferOnly = NO;
        _metalView.paused = YES;
        _metalView.enableSetNeedsDisplay = NO;
        _metalView.preferredFramesPerSecond = 60;
        _metalView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _metalView.delegate = self;

        _commandQueue = [_device newCommandQueue];
        _library = [_device newDefaultLibrary];

        static const RhythmTransformVertex kVertices[] = {
            {{-1.0f, -1.0f}, {0.0f, 1.0f}},
            {{ 1.0f, -1.0f}, {1.0f, 1.0f}},
            {{-1.0f,  1.0f}, {0.0f, 0.0f}},
            {{ 1.0f,  1.0f}, {1.0f, 0.0f}},
        };
        _vertexBuffer = [_device newBufferWithBytes:kVertices length:sizeof(kVertices) options:MTLResourceStorageModeShared];
        _uniformBuffer = [_device newBufferWithLength:sizeof(RhythmTransformUniforms) options:MTLResourceStorageModeShared];

        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, _device, nil, &_textureCache);
        [self setupPipeline];
        [self reset];
    }
    return self;
}

- (void)dealloc {
    _metalView.delegate = nil;
    _metalView.paused = YES;
    [self detachVideoOutput];
    if (_textureCache) {
        CVMetalTextureCacheFlush(_textureCache, 0);
        CFRelease(_textureCache);
        _textureCache = nil;
    }
}

- (UIView *)view {
    return self.metalView;
}

- (void)setupPipeline {
    id<MTLFunction> vertexFunction = [self.library newFunctionWithName:@"rhythmTransformVertex"];
    id<MTLFunction> fragmentFunction = [self.library newFunctionWithName:@"rhythmTransformFragment"];
    if (!vertexFunction || !fragmentFunction) {
        return;
    }

    MTLRenderPipelineDescriptor *descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = vertexFunction;
    descriptor.fragmentFunction = fragmentFunction;
    descriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;

    NSError *error = nil;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (error) {
        NSLog(@"❌ RhythmTransformMetalRenderer pipeline error: %@", error.localizedDescription);
    }
}

- (void)attachToPlayer:(AVPlayer *)player {
    self.player = player;
    self.metalView.paused = (player == nil);
    [self syncVideoOutput];
}

- (void)updateFrame:(CGRect)frame {
    self.metalView.frame = frame;
}

- (void)triggerBeatWithStrongMix:(float)strongMix {
    _envelopeState.trigger(fmaxf(0.0f, fminf(strongMix, 1.0f)), (float)self.beatBoost);
    self.metalView.paused = NO;
    if (self.beatSyncEnabled) {
        NSLog(@"🎵 TransformRenderer triggerBeat: beatSyncPhase=%.3f pulse=%.3f strongMix=%.3f paused=%d inHierarchy=%d hasPlayer=%d",
              _envelopeState.beatSyncPhase, _envelopeState.pulse,
              strongMix, self.metalView.paused, self.metalView.superview != nil,
              self.player != nil);
    }
}

- (void)tickWithDelta:(CFTimeInterval)dt {
    self.elapsedTime += dt;
    _envelopeState.tick((float)dt);
    [self syncVideoOutput];
    if (_envelopeState.pulse < 0.001f && self.player == nil) {
        self.metalView.paused = YES;
    }
}

- (void)resetEnvelope {
    _envelopeState = TransformEnvelopeState{};
}

- (void)reset {
    [self resetEnvelope];
    self.elapsedTime = 0.0;
    self.metalView.paused = YES;
    [self detachVideoOutput];
}

- (AVPlayerItemVideoOutput *)buildVideoOutput {
    NSDictionary *attributes = @{
        (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (NSString *)kCVPixelBufferMetalCompatibilityKey: @YES,
    };
    return [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:attributes];
}

- (void)detachVideoOutput {
    if (self.currentItem && self.videoOutput) {
        [self.currentItem removeOutput:self.videoOutput];
    }
    self.videoOutput = nil;
    self.currentItem = nil;
    self.currentVideoSize = CGSizeZero;
    if (self.textureCache) {
        CVMetalTextureCacheFlush(self.textureCache, 0);
    }
}

- (void)syncVideoOutput {
    AVPlayerItem *item = self.player.currentItem;
    if (!item) {
        [self detachVideoOutput];
        return;
    }
    if (item == self.currentItem && self.videoOutput) {
        return;
    }
    [self detachVideoOutput];
    self.currentItem = item;
    self.videoOutput = [self buildVideoOutput];
    [item addOutput:self.videoOutput];
}

- (nullable id<MTLTexture>)currentVideoTextureForView:(MTKView *)view {
    [self syncVideoOutput];
    if (!self.videoOutput || !self.currentItem) {
        return nil;
    }

    CMTime itemTime = [self.videoOutput itemTimeForHostTime:CACurrentMediaTime()];
    CVPixelBufferRef pixelBuffer = [self.videoOutput copyPixelBufferForItemTime:itemTime itemTimeForDisplay:nil];
    if (!pixelBuffer) {
        return nil;
    }

    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    self.currentVideoSize = CGSizeMake((CGFloat)width, (CGFloat)height);

    CVMetalTextureRef metalTexture = nil;
    CVReturn status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                self.textureCache,
                                                                pixelBuffer,
                                                                nil,
                                                                MTLPixelFormatBGRA8Unorm,
                                                                width,
                                                                height,
                                                                0,
                                                                &metalTexture);
    CFRelease(pixelBuffer);
    if (status != kCVReturnSuccess || !metalTexture) {
        return nil;
    }

    id<MTLTexture> texture = CVMetalTextureGetTexture(metalTexture);
    CFRelease(metalTexture);
    return texture;
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    (void)view;
    (void)size;
}

- (void)drawInMTKView:(MTKView *)view {
    if (!self.pipelineState || !self.commandQueue) {
        return;
    }

    id<CAMetalDrawable> drawable = view.currentDrawable;
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    id<MTLTexture> videoTexture = [self currentVideoTextureForView:view];
    if (!drawable || !renderPassDescriptor || !videoTexture) {
        return;
    }

    RhythmTransformUniforms *uniforms = (RhythmTransformUniforms *)self.uniformBuffer.contents;
    uniforms->resolution = (vector_float2){(float)view.drawableSize.width, (float)view.drawableSize.height};
    uniforms->videoSize = (vector_float2){(float)self.currentVideoSize.width, (float)self.currentVideoSize.height};
    uniforms->time = (float)self.elapsedTime;
    uniforms->baseIntensity = (float)self.baseIntensity;
    uniforms->beatPulse = self.envelopeState.pulse;
    if (self.beatSyncEnabled) {
        float phase = self.envelopeState.beatSyncPhase;
        uniforms->beatSyncMix = fminf(phase, 1.0f);
        uniforms->beatPulse = fmaxf(self.envelopeState.pulse, phase * 1.2f);
        if (phase > 0.1f) {
            static int __drawLogCount = 0;
            if (__drawLogCount < 8) {
                NSLog(@"🎵 TransformRenderer draw: beatSyncMix=%.3f beatPulse=%.3f phase=%.3f baseI=%.3f effectType=%d",
                      uniforms->beatSyncMix, uniforms->beatPulse, phase,
                      uniforms->baseIntensity, (int)self.effectType);
                __drawLogCount++;
            }
        }
    } else {
        uniforms->beatSyncMix = 1.0f;
    }
    uniforms->beatTime = self.envelopeState.beatTime;
    uniforms->strongMix = self.envelopeState.strongMix;
    uniforms->radius = (float)self.radius;
    uniforms->speed = (float)self.speed;
    uniforms->effectType = (int)self.effectType;

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.vertexBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentTexture:videoTexture atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [encoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

@end
