#import <UIKit/UIKit.h>

#import "MotionPhotoEditorTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface MotionPhotoCanvasView : UIView

@property (nonatomic, assign) MotionPhotoEditorMode editorMode;
@property (nonatomic, assign) MotionPhotoBrushMode brushMode;
@property (nonatomic, assign) CGFloat brushSize;
@property (nonatomic, assign) BOOL showsOverlay;
@property (nonatomic, strong, nullable) UIImage *maskPreviewImage;
@property (nonatomic, copy) NSArray<MotionPhotoArrow *> *arrows;
@property (nonatomic, assign) NSInteger selectedArrowIndex;

@property (nonatomic, copy, nullable) void (^maskStrokeHandler)(UIBezierPath *path, CGFloat brushSize, BOOL erasing);
@property (nonatomic, copy, nullable) void (^directionCreateHandler)(NSArray<NSValue *> *points);
@property (nonatomic, copy, nullable) void (^directionSelectHandler)(NSInteger index);
@property (nonatomic, copy, nullable) void (^interactionStateHandler)(BOOL active);

@end

NS_ASSUME_NONNULL_END
