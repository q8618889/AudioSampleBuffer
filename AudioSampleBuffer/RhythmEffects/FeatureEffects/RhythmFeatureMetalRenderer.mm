#import "RhythmFeatureMetalRenderer.h"

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <simd/simd.h>

namespace {
struct FeatureEnvelopeState {
    float intensity = 0.0f;
    float strongMix = 0.0f;
    float beatTime = 0.0f;
    float seed = 0.0f;
    uint32_t beatCount = 0;
    float beatSyncPhase = 0.0f;
    float subBass = 0.0f;
    float transient = 0.0f;
    float harmonic = 0.0f;
    float noise = 0.0f;

    void trigger(float mix) {
        intensity = fmaxf(intensity, 1.55f + 0.75f * mix);
        strongMix = mix;
        beatCount += 1;
        beatTime = 0.0f;
        seed = 0.173f * (float)beatCount + 0.37f * mix;
        beatSyncPhase = fmaxf(beatSyncPhase, 1.8f + 0.5f * mix);
    }

    void tick(float dt) {
        beatTime += dt;
        intensity *= expf(-3.8f * dt);
        if (intensity < 0.03f) intensity = 0.0f;
        beatSyncPhase *= expf(-2.2f * dt);
        if (beatSyncPhase < 0.01f) beatSyncPhase = 0.0f;
    }
};
}

typedef struct {
    vector_float2 position;
    vector_float2 uv;
} RhythmFeatureVertex;

typedef struct {
    vector_float2 resolution;
    float time;
    float intensity;
    float strongMix;
    float beatTime;
    float seed;
    int effectType;
    float beatSyncMix;
    float subBass;
    float transient;
    float harmonic;
    float noise;
} RhythmFeatureUniforms;

@interface RhythmFeatureMetalRenderer () <MTKViewDelegate>

@property (nonatomic, strong) MTKView *metalView;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLLibrary> library;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id<MTLBuffer> vertexBuffer;
@property (nonatomic, strong) id<MTLBuffer> uniformBuffer;
@property (nonatomic, assign) CFTimeInterval elapsedTime;
@property (nonatomic, assign) FeatureEnvelopeState envelopeState;

@end

@implementation RhythmFeatureMetalRenderer

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super init];
    if (self) {
        _effectType = RhythmFeatureEffectTypeGlitch;
        _device = MTLCreateSystemDefaultDevice();
        if (!_device) {
            return nil;
        }

        _metalView = [[MTKView alloc] initWithFrame:frame device:_device];
        _metalView.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
        _metalView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        _metalView.opaque = NO;
        _metalView.backgroundColor = [UIColor clearColor];
        _metalView.userInteractionEnabled = NO;
        _metalView.paused = YES;
        _metalView.enableSetNeedsDisplay = NO;
        _metalView.preferredFramesPerSecond = 60;
        _metalView.delegate = self;
        _metalView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        _commandQueue = [_device newCommandQueue];
        _library = [_device newDefaultLibrary];

        static const RhythmFeatureVertex kQuadVertices[] = {
            {{-1.0f, -1.0f}, {0.0f, 1.0f}},
            {{ 1.0f, -1.0f}, {1.0f, 1.0f}},
            {{-1.0f,  1.0f}, {0.0f, 0.0f}},
            {{ 1.0f,  1.0f}, {1.0f, 0.0f}},
        };
        _vertexBuffer = [_device newBufferWithBytes:kQuadVertices
                                             length:sizeof(kQuadVertices)
                                            options:MTLResourceStorageModeShared];
        _uniformBuffer = [_device newBufferWithLength:sizeof(RhythmFeatureUniforms)
                                              options:MTLResourceStorageModeShared];

        [self setupPipeline];
        [self reset];
    }
    return self;
}

- (UIView *)view {
    return self.metalView;
}

- (void)setupPipeline {
    id<MTLFunction> vertexFunction = [self.library newFunctionWithName:@"rhythmFeatureVertex"];
    id<MTLFunction> fragmentFunction = [self.library newFunctionWithName:@"rhythmFeatureFragment"];
    if (!vertexFunction || !fragmentFunction) {
        return;
    }

    MTLRenderPipelineDescriptor *descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = vertexFunction;
    descriptor.fragmentFunction = fragmentFunction;
    descriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    descriptor.colorAttachments[0].blendingEnabled = YES;
    descriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    descriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    NSError *error = nil;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (error) {
        NSLog(@"❌ RhythmFeatureMetalRenderer pipeline error: %@", error.localizedDescription);
    }
}

- (void)updateFrame:(CGRect)frame {
    self.metalView.frame = frame;
}

- (void)triggerBeatWithStrongMix:(float)strongMix {
    self.envelopeState.trigger(fmaxf(0.0f, fminf(strongMix, 1.0f)));
    self.metalView.hidden = NO;
    self.metalView.paused = NO;
    if (self.beatSyncEnabled) {
        NSLog(@"🎵 FeatureRenderer triggerBeat: beatSyncPhase=%.3f intensity=%.3f strongMix=%.3f paused=%d hidden=%d inHierarchy=%d",
              self.envelopeState.beatSyncPhase, self.envelopeState.intensity,
              strongMix, self.metalView.paused, self.metalView.hidden,
              self.metalView.superview != nil);
    }
}

- (void)triggerWithCategoryFeatures:(AnalyzerCategoryFeatures)features {
    FeatureEnvelopeState state = self.envelopeState;
    state.subBass = fmaxf(0.0f, fminf(features.lowEnergy * 4.0f, 1.0f));
    state.transient = fmaxf(0.0f, fminf(features.transient * 6.0f, 1.0f));
    state.harmonic = fmaxf(0.0f, fminf(features.harmonic * 4.0f, 1.0f));
    state.noise = fmaxf(0.0f, fminf(features.noise * 5.0f, 1.0f));
    self.envelopeState = state;
    float strongMix = 0.60f * state.subBass + 0.40f * state.transient;
    [self triggerBeatWithStrongMix:strongMix];
}

- (void)tickWithDelta:(CFTimeInterval)dt {
    self.elapsedTime += dt;
    self.envelopeState.tick((float)dt);
    BOOL idle = self.beatSyncEnabled
        ? (self.envelopeState.beatSyncPhase < 0.001f)
        : (self.envelopeState.intensity < 0.001f);
    if (idle) {
        self.metalView.paused = YES;
        self.metalView.hidden = YES;
    }
}

- (void)resetEnvelope {
    self.envelopeState = FeatureEnvelopeState{};
    self.metalView.paused = YES;
    self.metalView.hidden = YES;
}

- (void)reset {
    [self resetEnvelope];
    self.elapsedTime = 0.0;
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    (void)view;
    (void)size;
}

- (void)drawInMTKView:(MTKView *)view {
    if (!self.pipelineState || !self.commandQueue) return;
    id<CAMetalDrawable> drawable = view.currentDrawable;
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    if (!drawable || !renderPassDescriptor) return;

    RhythmFeatureUniforms *uniforms = (RhythmFeatureUniforms *)self.uniformBuffer.contents;
    uniforms->resolution = (vector_float2){(float)view.drawableSize.width, (float)view.drawableSize.height};
    uniforms->time = (float)self.elapsedTime;
    uniforms->strongMix = self.envelopeState.strongMix;
    uniforms->beatTime = self.envelopeState.beatTime;
    uniforms->seed = self.envelopeState.seed;
    uniforms->effectType = (int)self.effectType;
    uniforms->subBass = self.envelopeState.subBass;
    uniforms->transient = self.envelopeState.transient;
    uniforms->harmonic = self.envelopeState.harmonic;
    uniforms->noise = self.envelopeState.noise;
    if (self.beatSyncEnabled) {
        float phase = self.envelopeState.beatSyncPhase;
        uniforms->intensity = fmaxf(self.envelopeState.intensity, phase * 2.0f);
        uniforms->beatSyncMix = fminf(phase, 1.0f);
    } else {
        uniforms->intensity = self.envelopeState.intensity;
        uniforms->beatSyncMix = 1.0f;
    }

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.vertexBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [encoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

@end
