#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MotionPhotoEditorMode) {
    MotionPhotoEditorModeMask = 0,
    MotionPhotoEditorModeDirection = 1,
};

typedef NS_ENUM(NSInteger, MotionPhotoBrushMode) {
    MotionPhotoBrushModePaint = 0,
    MotionPhotoBrushModeErase = 1,
};

@interface MotionPhotoArrow : NSObject <NSCopying>

@property (nonatomic, assign) CGPoint startPoint;
@property (nonatomic, assign) CGPoint endPoint;
@property (nonatomic, assign) CGFloat intensity;
@property (nonatomic, copy) NSArray<NSValue *> *controlPoints;

@end

FOUNDATION_EXPORT NSArray<NSValue *> *MotionPhotoSmoothedPoints(NSArray<NSValue *> *points, NSUInteger subdivisions);
FOUNDATION_EXPORT UIBezierPath *MotionPhotoBezierPathFromPoints(NSArray<NSValue *> *points);

NS_ASSUME_NONNULL_END
