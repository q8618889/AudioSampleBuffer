#import "MotionPhotoEditorTypes.h"

static inline CGPoint MotionPhotoCatmullRomPoint(CGPoint p0, CGPoint p1, CGPoint p2, CGPoint p3, CGFloat t) {
    CGFloat t2 = t * t;
    CGFloat t3 = t2 * t;
    CGFloat x = 0.5 * ((2.0 * p1.x) +
                       (-p0.x + p2.x) * t +
                       (2.0 * p0.x - 5.0 * p1.x + 4.0 * p2.x - p3.x) * t2 +
                       (-p0.x + 3.0 * p1.x - 3.0 * p2.x + p3.x) * t3);
    CGFloat y = 0.5 * ((2.0 * p1.y) +
                       (-p0.y + p2.y) * t +
                       (2.0 * p0.y - 5.0 * p1.y + 4.0 * p2.y - p3.y) * t2 +
                       (-p0.y + 3.0 * p1.y - 3.0 * p2.y + p3.y) * t3);
    return CGPointMake(x, y);
}

@implementation MotionPhotoArrow

- (id)copyWithZone:(NSZone *)zone {
    MotionPhotoArrow *copy = [[[self class] allocWithZone:zone] init];
    copy.startPoint = self.startPoint;
    copy.endPoint = self.endPoint;
    copy.intensity = self.intensity;
    copy.controlPoints = [[NSArray alloc] initWithArray:self.controlPoints copyItems:NO];
    return copy;
}

@end

NSArray<NSValue *> *MotionPhotoSmoothedPoints(NSArray<NSValue *> *points, NSUInteger subdivisions) {
    if (points.count <= 2 || subdivisions == 0) {
        return points ?: @[];
    }

    NSMutableArray<NSValue *> *smoothed = [NSMutableArray array];
    [smoothed addObject:points.firstObject];

    for (NSUInteger idx = 0; idx + 1 < points.count; idx++) {
        CGPoint p0 = (idx == 0) ? points[idx].CGPointValue : points[idx - 1].CGPointValue;
        CGPoint p1 = points[idx].CGPointValue;
        CGPoint p2 = points[idx + 1].CGPointValue;
        CGPoint p3 = (idx + 2 < points.count) ? points[idx + 2].CGPointValue : p2;

        for (NSUInteger step = 1; step <= subdivisions; step++) {
            CGFloat t = (CGFloat)step / (CGFloat)subdivisions;
            CGPoint point = MotionPhotoCatmullRomPoint(p0, p1, p2, p3, t);
            [smoothed addObject:[NSValue valueWithCGPoint:point]];
        }
    }

    return smoothed;
}

UIBezierPath *MotionPhotoBezierPathFromPoints(NSArray<NSValue *> *points) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    if (points.count == 0) {
        return path;
    }
    [path moveToPoint:points.firstObject.CGPointValue];
    for (NSUInteger idx = 1; idx < points.count; idx++) {
        [path addLineToPoint:points[idx].CGPointValue];
    }
    return path;
}
