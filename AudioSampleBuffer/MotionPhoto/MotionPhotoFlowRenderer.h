#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h>
#import <UIKit/UIKit.h>

#import "MotionPhotoEditorTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface MotionPhotoFlowRenderer : NSObject <MTKViewDelegate>

@property (nonatomic, strong, readonly) MTKView *metalView;
@property (nonatomic, assign) CGFloat playbackSpeed;
@property (nonatomic, assign, getter=isPlaying) BOOL playing;

- (instancetype)initWithFrame:(CGRect)frame;
- (void)setSourceImage:(nullable UIImage *)image;
- (void)updateFlowWithMaskImage:(nullable UIImage *)maskImage
                         arrows:(NSArray<MotionPhotoArrow *> *)arrows
                     canvasSize:(CGSize)canvasSize;
- (void)requestRender;

@end

NS_ASSUME_NONNULL_END
