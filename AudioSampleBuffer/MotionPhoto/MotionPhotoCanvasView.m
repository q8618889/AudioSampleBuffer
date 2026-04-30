#import "MotionPhotoCanvasView.h"

@interface MotionPhotoCanvasView () <UIGestureRecognizerDelegate>

@property (nonatomic, strong, nullable) UIBezierPath *activePath;
@property (nonatomic, strong) NSMutableArray<NSValue *> *activeArrowPoints;
@property (nonatomic, assign) CGPoint dragStartPoint;
@property (nonatomic, assign) CGPoint dragCurrentPoint;
@property (nonatomic, assign) BOOL didMove;
@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;
@property (nonatomic, strong) UITapGestureRecognizer *tapGesture;

@end

@implementation MotionPhotoCanvasView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.multipleTouchEnabled = NO;
        self.contentMode = UIViewContentModeRedraw;
        _brushSize = 34.0;
        _selectedArrowIndex = NSNotFound;
        _arrows = @[];
        _showsOverlay = YES;
        _activeArrowPoints = [NSMutableArray array];

        _panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        _panGesture.minimumNumberOfTouches = 1;
        _panGesture.maximumNumberOfTouches = 1;
        _panGesture.delegate = self;
        _panGesture.cancelsTouchesInView = NO;
        [self addGestureRecognizer:_panGesture];

        _tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        _tapGesture.delegate = self;
        _tapGesture.cancelsTouchesInView = NO;
        [_tapGesture requireGestureRecognizerToFail:_panGesture];
        [self addGestureRecognizer:_tapGesture];
    }
    return self;
}

- (void)setMaskPreviewImage:(UIImage *)maskPreviewImage {
    _maskPreviewImage = maskPreviewImage;
    [self setNeedsDisplay];
}

- (void)setArrows:(NSArray<MotionPhotoArrow *> *)arrows {
    _arrows = [arrows copy];
    [self setNeedsDisplay];
}

- (void)setSelectedArrowIndex:(NSInteger)selectedArrowIndex {
    _selectedArrowIndex = selectedArrowIndex;
    [self setNeedsDisplay];
}

- (void)setEditorMode:(MotionPhotoEditorMode)editorMode {
    _editorMode = editorMode;
    self.activePath = nil;
    self.didMove = NO;
    [self setNeedsDisplay];
}

- (void)setShowsOverlay:(BOOL)showsOverlay {
    _showsOverlay = showsOverlay;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];

    if (!self.showsOverlay) {
        return;
    }

    if (self.maskPreviewImage) {
        [self.maskPreviewImage drawInRect:self.bounds];
    }

    if (self.activePath && self.editorMode == MotionPhotoEditorModeMask) {
        UIColor *previewColor = (self.brushMode == MotionPhotoBrushModeErase)
            ? [UIColor colorWithWhite:1.0 alpha:0.18]
            : [UIColor colorWithRed:1.0 green:0.68 blue:0.24 alpha:0.38];
        [previewColor setStroke];
        self.activePath.lineWidth = self.brushSize;
        self.activePath.lineCapStyle = kCGLineCapRound;
        self.activePath.lineJoinStyle = kCGLineJoinRound;
        [self.activePath stroke];
    }

    [self.arrows enumerateObjectsUsingBlock:^(MotionPhotoArrow * _Nonnull arrow, NSUInteger idx, BOOL * _Nonnull stop) {
        [self drawArrow:arrow selected:((NSInteger)idx == self.selectedArrowIndex) preview:NO];
    }];

    if (self.editorMode == MotionPhotoEditorModeDirection && self.didMove) {
        MotionPhotoArrow *previewArrow = [[MotionPhotoArrow alloc] init];
        previewArrow.controlPoints = self.activeArrowPoints.copy;
        previewArrow.startPoint = self.activeArrowPoints.firstObject.CGPointValue;
        previewArrow.endPoint = self.activeArrowPoints.lastObject.CGPointValue;
        [self drawArrow:previewArrow selected:YES preview:YES];
    }
}

- (void)drawArrow:(MotionPhotoArrow *)arrow selected:(BOOL)selected preview:(BOOL)preview {
    UIColor *strokeColor = selected
        ? [UIColor colorWithRed:1.0 green:0.82 blue:0.36 alpha:1.0]
        : [UIColor colorWithWhite:1.0 alpha:(preview ? 0.92 : 0.98)];

    NSArray<NSValue *> *rawPoints = arrow.controlPoints.count > 1 ? arrow.controlPoints : @[[NSValue valueWithCGPoint:arrow.startPoint], [NSValue valueWithCGPoint:arrow.endPoint]];
    NSArray<NSValue *> *points = MotionPhotoSmoothedPoints(rawPoints, 8);
    UIBezierPath *shaft = MotionPhotoBezierPathFromPoints(points);
    shaft.lineWidth = selected ? 4.0 : 3.0;
    shaft.lineCapStyle = kCGLineCapRound;
    CGFloat dashPattern[] = {9.0, 7.0};
    [shaft setLineDash:dashPattern count:2 phase:0.0];
    [strokeColor setStroke];
    [shaft stroke];

    CGPoint tailAnchor = points.count >= 2 ? points[points.count - 2].CGPointValue : arrow.startPoint;
    CGPoint headAnchor = points.lastObject.CGPointValue;
    CGFloat dx = headAnchor.x - tailAnchor.x;
    CGFloat dy = headAnchor.y - tailAnchor.y;
    CGFloat length = MAX(hypot(dx, dy), 0.001);
    CGFloat ux = dx / length;
    CGFloat uy = dy / length;
    CGFloat headLength = 14.0;
    CGFloat wing = 8.0;
    CGPoint p1 = CGPointMake(headAnchor.x - ux * headLength - uy * wing,
                             headAnchor.y - uy * headLength + ux * wing);
    CGPoint p2 = CGPointMake(headAnchor.x - ux * headLength + uy * wing,
                             headAnchor.y - uy * headLength - ux * wing);

    UIBezierPath *head = [UIBezierPath bezierPath];
    [head moveToPoint:headAnchor];
    [head addLineToPoint:p1];
    [head moveToPoint:headAnchor];
    [head addLineToPoint:p2];
    head.lineWidth = shaft.lineWidth;
    head.lineCapStyle = kCGLineCapRound;
    [head stroke];

    if (!preview) {
        CGFloat radius = 14.0;
        CGPoint startAnchor = points.firstObject.CGPointValue;
        CGRect circleRect = CGRectMake(startAnchor.x - radius,
                                       startAnchor.y - radius,
                                       radius * 2.0,
                                       radius * 2.0);
        UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:circleRect];
        [[UIColor colorWithWhite:1.0 alpha:0.95] setFill];
        [circle fill];
        [[UIColor colorWithWhite:0.1 alpha:1.0] setStroke];
        circle.lineWidth = 1.5;
        [circle stroke];

        UIBezierPath *cross = [UIBezierPath bezierPath];
        [cross moveToPoint:CGPointMake(CGRectGetMinX(circleRect) + 9.0, CGRectGetMinY(circleRect) + 9.0)];
        [cross addLineToPoint:CGPointMake(CGRectGetMaxX(circleRect) - 9.0, CGRectGetMaxY(circleRect) - 9.0)];
        [cross moveToPoint:CGPointMake(CGRectGetMinX(circleRect) + 9.0, CGRectGetMaxY(circleRect) - 9.0)];
        [cross addLineToPoint:CGPointMake(CGRectGetMaxX(circleRect) - 9.0, CGRectGetMinY(circleRect) + 9.0)];
        cross.lineWidth = 1.6;
        [[UIColor colorWithWhite:0.12 alpha:1.0] setStroke];
        [cross stroke];
    }
}

- (NSInteger)arrowIndexNearPoint:(CGPoint)point {
    __block NSInteger foundIndex = NSNotFound;
    [self.arrows enumerateObjectsUsingBlock:^(MotionPhotoArrow * _Nonnull arrow, NSUInteger idx, BOOL * _Nonnull stop) {
        CGFloat distance = hypot(point.x - arrow.startPoint.x, point.y - arrow.startPoint.y);
        if (distance <= 22.0) {
            foundIndex = (NSInteger)idx;
            *stop = YES;
        }
    }];
    return foundIndex;
}

- (void)handleTap:(UITapGestureRecognizer *)gesture {
    if (self.editorMode != MotionPhotoEditorModeDirection || gesture.state != UIGestureRecognizerStateEnded) {
        return;
    }
    NSInteger index = [self arrowIndexNearPoint:[gesture locationInView:self]];
    if (index != NSNotFound && self.directionSelectHandler) {
        self.directionSelectHandler(index);
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self];

    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.dragStartPoint = point;
        self.dragCurrentPoint = point;
        self.didMove = NO;
        [self.activeArrowPoints removeAllObjects];

        if (self.editorMode == MotionPhotoEditorModeDirection) {
            NSInteger index = [self arrowIndexNearPoint:point];
            if (index != NSNotFound) {
                if (self.directionSelectHandler) {
                    self.directionSelectHandler(index);
                }
                gesture.enabled = NO;
                gesture.enabled = YES;
                return;
            }
        }

        if (self.interactionStateHandler) {
            self.interactionStateHandler(YES);
        }

        if (self.editorMode == MotionPhotoEditorModeMask) {
            UIBezierPath *path = [UIBezierPath bezierPath];
            [path moveToPoint:point];
            self.activePath = path;
        } else {
            [self.activeArrowPoints addObject:[NSValue valueWithCGPoint:point]];
        }
        [self setNeedsDisplay];
        return;
    }

    if (gesture.state == UIGestureRecognizerStateChanged) {
        self.dragCurrentPoint = point;
        self.didMove = YES;
        if (self.editorMode == MotionPhotoEditorModeMask) {
            [self.activePath addLineToPoint:point];
        } else {
            CGPoint previousPoint = self.activeArrowPoints.lastObject.CGPointValue;
            if (hypot(point.x - previousPoint.x, point.y - previousPoint.y) >= 6.0) {
                [self.activeArrowPoints addObject:[NSValue valueWithCGPoint:point]];
            } else if (self.activeArrowPoints.count > 0) {
                self.activeArrowPoints[self.activeArrowPoints.count - 1] = [NSValue valueWithCGPoint:point];
            }
        }
        [self setNeedsDisplay];
        return;
    }

    if (gesture.state == UIGestureRecognizerStateEnded ||
        gesture.state == UIGestureRecognizerStateCancelled ||
        gesture.state == UIGestureRecognizerStateFailed) {
        self.dragCurrentPoint = point;
        if (!CGPointEqualToPoint(self.dragStartPoint, point)) {
            self.didMove = YES;
        }
        [self finishInteraction];
    }
}

- (void)finishInteraction {
    if (self.editorMode == MotionPhotoEditorModeMask) {
        if (self.activePath && self.maskStrokeHandler) {
            self.maskStrokeHandler(self.activePath, self.brushSize, self.brushMode == MotionPhotoBrushModeErase);
        }
        self.activePath = nil;
    } else if (self.didMove) {
        CGFloat distance = hypot(self.dragCurrentPoint.x - self.dragStartPoint.x,
                                 self.dragCurrentPoint.y - self.dragStartPoint.y);
        if (distance >= 18.0 && self.directionCreateHandler) {
            if (self.activeArrowPoints.count == 0) {
                [self.activeArrowPoints addObject:[NSValue valueWithCGPoint:self.dragStartPoint]];
                [self.activeArrowPoints addObject:[NSValue valueWithCGPoint:self.dragCurrentPoint]];
            } else if (!CGPointEqualToPoint(self.activeArrowPoints.lastObject.CGPointValue, self.dragCurrentPoint)) {
                [self.activeArrowPoints addObject:[NSValue valueWithCGPoint:self.dragCurrentPoint]];
            }
            self.directionCreateHandler(self.activeArrowPoints.copy);
        }
    }

    self.didMove = NO;
    [self.activeArrowPoints removeAllObjects];
    if (self.interactionStateHandler) {
        self.interactionStateHandler(NO);
    }
    [self setNeedsDisplay];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.tapGesture) {
        return self.editorMode == MotionPhotoEditorModeDirection;
    }
    return YES;
}

@end
