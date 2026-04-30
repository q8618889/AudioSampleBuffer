#import "MotionPhotoFlowRenderer.h"

#import <CoreImage/CoreImage.h>
#import <simd/simd.h>

typedef struct {
    vector_float2 phase;
    vector_float2 amplitude;
} MotionPhotoUniforms;

@interface MotionPhotoFlowRenderer ()

@property (nonatomic, strong) MTKView *metalView;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id<MTLSamplerState> samplerState;
@property (nonatomic, strong) id<MTLBuffer> uniformBuffer;
@property (nonatomic, strong, nullable) id<MTLTexture> sourceTexture;
@property (nonatomic, strong, nullable) id<MTLTexture> flowTexture;
@property (nonatomic, strong, nullable) id<MTLTexture> maskTexture;
@property (nonatomic, strong, nullable) UIImage *sourceImage;
@property (nonatomic, assign) CFTimeInterval startTime;

@end

@implementation MotionPhotoFlowRenderer

- (NSArray<NSValue *> *)imageSpacePointsForArrow:(MotionPhotoArrow *)arrow scale:(CGPoint)scale {
    NSArray<NSValue *> *points = arrow.controlPoints.count > 1
        ? arrow.controlPoints
        : @[[NSValue valueWithCGPoint:arrow.startPoint], [NSValue valueWithCGPoint:arrow.endPoint]];
    points = MotionPhotoSmoothedPoints(points, 8);
    NSMutableArray<NSValue *> *mapped = [NSMutableArray arrayWithCapacity:points.count];
    for (NSValue *value in points) {
        CGPoint point = value.CGPointValue;
        [mapped addObject:[NSValue valueWithCGPoint:CGPointMake(point.x * scale.x, point.y * scale.y)]];
    }
    return mapped;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super init];
    if (self) {
        _device = MTLCreateSystemDefaultDevice();
        _metalView = [[MTKView alloc] initWithFrame:frame device:_device];
        _metalView.delegate = self;
        _metalView.enableSetNeedsDisplay = YES;
        _metalView.paused = YES;
        _metalView.preferredFramesPerSecond = 30;
        _metalView.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
        _metalView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        _metalView.framebufferOnly = NO;
        _metalView.opaque = YES;

        _commandQueue = [_device newCommandQueue];
        _uniformBuffer = [_device newBufferWithLength:sizeof(MotionPhotoUniforms)
                                              options:MTLResourceStorageModeShared];
        _playbackSpeed = 1.0;
        _startTime = CACurrentMediaTime();

        [self buildPipeline];
        [self buildSampler];
    }
    return self;
}

- (void)buildPipeline {
    id<MTLLibrary> library = [self.device newDefaultLibrary];
    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"motionPhotoVertexShader"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"motionPhotoFragmentShader"];
    if (!vertexFunction || !fragmentFunction) {
        return;
    }

    MTLRenderPipelineDescriptor *descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = vertexFunction;
    descriptor.fragmentFunction = fragmentFunction;
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    NSError *error = nil;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (error) {
        NSLog(@"MotionPhoto pipeline error: %@", error.localizedDescription);
    }
}

- (void)buildSampler {
    MTLSamplerDescriptor *descriptor = [[MTLSamplerDescriptor alloc] init];
    descriptor.minFilter = MTLSamplerMinMagFilterLinear;
    descriptor.magFilter = MTLSamplerMinMagFilterLinear;
    descriptor.sAddressMode = MTLSamplerAddressModeClampToEdge;
    descriptor.tAddressMode = MTLSamplerAddressModeClampToEdge;
    self.samplerState = [self.device newSamplerStateWithDescriptor:descriptor];
}

- (void)setSourceImage:(UIImage *)image {
    _sourceImage = image;
    self.sourceTexture = [self textureFromImage:image];
    if (!image) {
        self.maskTexture = nil;
        self.flowTexture = nil;
    }
    [self requestRender];
}

- (void)setPlaying:(BOOL)playing {
    _playing = playing;
    self.startTime = CACurrentMediaTime();
    self.metalView.paused = !playing;
    if (!playing) {
        [self requestRender];
    }
}

- (void)setPlaybackSpeed:(CGFloat)playbackSpeed {
    _playbackSpeed = MAX(0.05, playbackSpeed);
    if (!self.isPlaying) {
        [self requestRender];
    }
}

- (void)requestRender {
    [self.metalView draw];
}

- (void)updateFlowWithMaskImage:(UIImage *)maskImage
                         arrows:(NSArray<MotionPhotoArrow *> *)arrows
                     canvasSize:(CGSize)canvasSize {
    if (!self.sourceImage) {
        self.maskTexture = nil;
        self.flowTexture = nil;
        return;
    }

    UIImage *preparedMask = [self preparedMaskImageFrom:maskImage targetSize:self.sourceImage.size];
    self.maskTexture = [self grayscaleTextureFromImage:preparedMask];

    if (!preparedMask || arrows.count == 0 || canvasSize.width < 1.0 || canvasSize.height < 1.0) {
        self.flowTexture = [self zeroFlowTextureForSize:self.sourceImage.size];
        [self requestRender];
        return;
    }

    CGSize imageSize = self.sourceImage.size;
    CGPoint scale = CGPointMake(imageSize.width / canvasSize.width, imageSize.height / canvasSize.height);
    NSUInteger width = (NSUInteger)lrint(imageSize.width);
    NSUInteger height = (NSUInteger)lrint(imageSize.height);
    NSUInteger count = width * height;

    NSData *maskData = [self grayscaleDataFromImage:preparedMask size:imageSize];
    const uint8_t *maskBytes = maskData.bytes;
    if (!maskBytes) {
        self.flowTexture = [self zeroFlowTextureForSize:self.sourceImage.size];
        [self requestRender];
        return;
    }

    NSMutableData *flowData = [NSMutableData dataWithLength:count * sizeof(vector_float4)];
    vector_float4 *flowPixels = flowData.mutableBytes;
    CGFloat longestEdge = MAX(imageSize.width, imageSize.height);

    for (NSUInteger y = 0; y < height; y++) {
        for (NSUInteger x = 0; x < width; x++) {
            NSUInteger idx = y * width + x;
            float maskAlpha = maskBytes[idx] / 255.0f;
            if (maskAlpha <= 0.001f) {
                flowPixels[idx] = (vector_float4){0, 0, 0, 1};
                continue;
            }

            CGPoint point = CGPointMake((CGFloat)x + 0.5, (CGFloat)y + 0.5);
            double weightedX = 0.0;
            double weightedY = 0.0;
            double weightSum = 0.0;

            for (MotionPhotoArrow *arrow in arrows) {
                NSArray<NSValue *> *imagePoints = [self imageSpacePointsForArrow:arrow scale:scale];
                CGFloat totalLength = 0.0;
                for (NSUInteger segmentIndex = 1; segmentIndex < imagePoints.count; segmentIndex++) {
                    CGPoint start = imagePoints[segmentIndex - 1].CGPointValue;
                    CGPoint end = imagePoints[segmentIndex].CGPointValue;
                    totalLength += hypot(end.x - start.x, end.y - start.y);
                }
                totalLength = MAX(totalLength, 1.0);

                CGFloat traversedLength = 0.0;
                for (NSUInteger segmentIndex = 1; segmentIndex < imagePoints.count; segmentIndex++) {
                    CGPoint start = imagePoints[segmentIndex - 1].CGPointValue;
                    CGPoint end = imagePoints[segmentIndex].CGPointValue;
                    CGFloat dx = end.x - start.x;
                    CGFloat dy = end.y - start.y;
                    CGFloat len = MAX(hypot(dx, dy), 1.0);
                    CGFloat invLen = 1.0 / len;
                    CGFloat dirX = dx * invLen;
                    CGFloat dirY = dy * invLen;

                    CGFloat segLenSquared = MAX(dx * dx + dy * dy, 1.0);
                    CGFloat t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / segLenSquared;
                    t = MIN(MAX(t, 0.0), 1.0);
                    CGPoint nearest = CGPointMake(start.x + dx * t, start.y + dy * t);
                    CGFloat distX = point.x - nearest.x;
                    CGFloat distY = point.y - nearest.y;
                    CGFloat distSquared = distX * distX + distY * distY;
                    CGFloat sigma = MAX(20.0, len * 0.42);
                    CGFloat pathProgress = (traversedLength + len * t) / totalLength;
                    CGFloat axial = 0.68 + 0.32 * sin((CGFloat)M_PI * pathProgress);
                    CGFloat weight = exp(-(distSquared / (2.0 * sigma * sigma))) * axial;
                    if (weight >= 0.0001) {
                        CGFloat magnitude = MIN(MAX((totalLength / longestEdge) * 0.72, 0.035), 0.18) * MAX(arrow.intensity, 0.4);
                        weightedX += dirX * magnitude * weight;
                        weightedY += dirY * magnitude * weight;
                        weightSum += weight;
                    }
                    traversedLength += len;
                }
            }

            if (weightSum <= 0.0001) {
                flowPixels[idx] = (vector_float4){0, 0, maskAlpha, 1};
                continue;
            }

            float flowX = (float)(weightedX / weightSum) * maskAlpha;
            float flowY = (float)(weightedY / weightSum) * maskAlpha;
            flowPixels[idx] = (vector_float4){flowX, flowY, maskAlpha, 1};
        }
    }

    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                                                                           width:width
                                                                                          height:height
                                                                                       mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> texture = [self.device newTextureWithDescriptor:descriptor];
    [texture replaceRegion:MTLRegionMake2D(0, 0, width, height)
               mipmapLevel:0
                 withBytes:flowPixels
               bytesPerRow:width * sizeof(vector_float4)];
    self.flowTexture = texture;
    [self requestRender];
}

- (UIImage *)preparedMaskImageFrom:(UIImage *)maskImage targetSize:(CGSize)targetSize {
    if (!maskImage || targetSize.width < 1.0 || targetSize.height < 1.0) {
        return nil;
    }

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = NO;
    format.scale = 1.0;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:targetSize format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        [maskImage drawInRect:CGRectMake(0.0, 0.0, targetSize.width, targetSize.height)];
    }];
}

- (NSData *)grayscaleDataFromImage:(UIImage *)image size:(CGSize)size {
    if (!image || size.width < 1.0 || size.height < 1.0) {
        return nil;
    }

    NSUInteger width = (NSUInteger)lrint(size.width);
    NSUInteger height = (NSUInteger)lrint(size.height);
    NSMutableData *data = [NSMutableData dataWithLength:width * height];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
    CGContextRef context = CGBitmapContextCreate(data.mutableBytes,
                                                 width,
                                                 height,
                                                 8,
                                                 width,
                                                 colorSpace,
                                                 (CGBitmapInfo)kCGImageAlphaNone);
    CGColorSpaceRelease(colorSpace);
    if (!context) {
        return nil;
    }

    CGContextDrawImage(context, CGRectMake(0.0, 0.0, width, height), image.CGImage);
    CGContextRelease(context);
    return data;
}

- (id<MTLTexture>)textureFromImage:(UIImage *)image {
    if (!image || !image.CGImage) {
        return nil;
    }
    MTKTextureLoader *loader = [[MTKTextureLoader alloc] initWithDevice:self.device];
    NSError *error = nil;
    id<MTLTexture> texture = [loader newTextureWithCGImage:image.CGImage
                                                   options:@{ MTKTextureLoaderOptionSRGB : @NO }
                                                     error:&error];
    if (error) {
        NSLog(@"MotionPhoto source texture error: %@", error.localizedDescription);
    }
    return texture;
}

- (id<MTLTexture>)grayscaleTextureFromImage:(UIImage *)image {
    if (!image) {
        return nil;
    }
    CGSize size = image.size;
    NSData *data = [self grayscaleDataFromImage:image size:size];
    if (!data) {
        return nil;
    }

    NSUInteger width = (NSUInteger)lrint(size.width);
    NSUInteger height = (NSUInteger)lrint(size.height);
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                                                                                           width:width
                                                                                          height:height
                                                                                       mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> texture = [self.device newTextureWithDescriptor:descriptor];
    [texture replaceRegion:MTLRegionMake2D(0, 0, width, height)
               mipmapLevel:0
                 withBytes:data.bytes
               bytesPerRow:width];
    return texture;
}

- (id<MTLTexture>)zeroFlowTextureForSize:(CGSize)size {
    NSUInteger width = (NSUInteger)MAX(lrint(size.width), 1);
    NSUInteger height = (NSUInteger)MAX(lrint(size.height), 1);
    NSMutableData *data = [NSMutableData dataWithLength:width * height * sizeof(vector_float4)];
    vector_float4 *flowPixels = data.mutableBytes;
    NSUInteger count = width * height;
    for (NSUInteger idx = 0; idx < count; idx++) {
        flowPixels[idx] = (vector_float4){0, 0, 0, 1};
    }

    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float
                                                                                           width:width
                                                                                          height:height
                                                                                       mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> texture = [self.device newTextureWithDescriptor:descriptor];
    [texture replaceRegion:MTLRegionMake2D(0, 0, width, height)
               mipmapLevel:0
                 withBytes:flowPixels
               bytesPerRow:width * sizeof(vector_float4)];
    return texture;
}

#pragma mark - MTKViewDelegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
}

- (void)drawInMTKView:(MTKView *)view {
    id<CAMetalDrawable> drawable = view.currentDrawable;
    MTLRenderPassDescriptor *passDescriptor = view.currentRenderPassDescriptor;
    if (!drawable || !passDescriptor || !self.pipelineState || !self.sourceTexture) {
        return;
    }

    MotionPhotoUniforms *uniforms = self.uniformBuffer.contents;
    CFTimeInterval elapsed = self.isPlaying ? (CACurrentMediaTime() - self.startTime) : 0.0;
    uniforms->phase = (vector_float2){(float)(elapsed * self.playbackSpeed * 0.42), 0.0f};
    uniforms->amplitude = (vector_float2){1.0f, 0.0f};

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:passDescriptor];
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setFragmentTexture:self.sourceTexture atIndex:0];
    [encoder setFragmentTexture:self.flowTexture atIndex:1];
    [encoder setFragmentTexture:self.maskTexture atIndex:2];
    [encoder setFragmentSamplerState:self.samplerState atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [encoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

@end
