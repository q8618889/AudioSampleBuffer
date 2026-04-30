#import "MotionPhotoEditorViewController.h"

#import <CoreImage/CoreImage.h>
#import <PhotosUI/PhotosUI.h>

#import "MotionPhotoCanvasView.h"
#import "MotionPhotoEditorTypes.h"
#import "MotionPhotoFlowRenderer.h"

static NSString * const MotionPhotoEditorTitle = @"Motionleap";

typedef struct {
    CGMutablePathRef path;
    CGPoint scale;
} MotionPhotoPathTransformContext;

static void MotionPhotoAppendScaledPathElement(void *info, const CGPathElement *element) {
    MotionPhotoPathTransformContext *context = (MotionPhotoPathTransformContext *)info;
    CGPoint scale = context->scale;
    CGPoint p0 = CGPointZero;
    CGPoint p1 = CGPointZero;
    CGPoint p2 = CGPointZero;

    switch (element->type) {
        case kCGPathElementMoveToPoint:
            p0 = CGPointMake(element->points[0].x * scale.x, element->points[0].y * scale.y);
            CGPathMoveToPoint(context->path, NULL, p0.x, p0.y);
            break;
        case kCGPathElementAddLineToPoint:
            p0 = CGPointMake(element->points[0].x * scale.x, element->points[0].y * scale.y);
            CGPathAddLineToPoint(context->path, NULL, p0.x, p0.y);
            break;
        case kCGPathElementAddQuadCurveToPoint:
            p0 = CGPointMake(element->points[0].x * scale.x, element->points[0].y * scale.y);
            p1 = CGPointMake(element->points[1].x * scale.x, element->points[1].y * scale.y);
            CGPathAddQuadCurveToPoint(context->path, NULL, p0.x, p0.y, p1.x, p1.y);
            break;
        case kCGPathElementAddCurveToPoint:
            p0 = CGPointMake(element->points[0].x * scale.x, element->points[0].y * scale.y);
            p1 = CGPointMake(element->points[1].x * scale.x, element->points[1].y * scale.y);
            p2 = CGPointMake(element->points[2].x * scale.x, element->points[2].y * scale.y);
            CGPathAddCurveToPoint(context->path, NULL, p0.x, p0.y, p1.x, p1.y, p2.x, p2.y);
            break;
        case kCGPathElementCloseSubpath:
            CGPathCloseSubpath(context->path);
            break;
    }
}

@interface MotionPhotoEditorViewController () <PHPickerViewControllerDelegate, UIScrollViewDelegate>

@property (nonatomic, strong) UIView *topBarView;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UIButton *importButton;
@property (nonatomic, strong) UIButton *exportButton;
@property (nonatomic, strong) UILabel *titleLabel;

@property (nonatomic, strong) UIScrollView *canvasScrollView;
@property (nonatomic, strong) UIView *canvasContentView;
@property (nonatomic, strong) MotionPhotoFlowRenderer *flowRenderer;
@property (nonatomic, strong) MotionPhotoCanvasView *canvasView;

@property (nonatomic, strong) UIView *rightToolbar;
@property (nonatomic, strong) UIButton *brushButton;
@property (nonatomic, strong) UIButton *eraserButton;
@property (nonatomic, strong) UIButton *deleteButton;

@property (nonatomic, strong) UIView *bottomPanel;
@property (nonatomic, strong) UIButton *maskModeButton;
@property (nonatomic, strong) UIButton *directionModeButton;
@property (nonatomic, strong) UIButton *undoButton;
@property (nonatomic, strong) UIButton *redoButton;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UISlider *speedSlider;

@property (nonatomic, strong, nullable) UIImage *sourceImage;
@property (nonatomic, strong, nullable) UIImage *maskImage;
@property (nonatomic, strong) NSMutableArray<MotionPhotoArrow *> *arrows;
@property (nonatomic, assign) NSInteger selectedArrowIndex;

@property (nonatomic, strong) NSMutableArray<NSDictionary *> *undoStack;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *redoStack;

@property (nonatomic, assign) MotionPhotoEditorMode editorMode;
@property (nonatomic, assign) MotionPhotoBrushMode brushMode;
@property (nonatomic, assign) BOOL needsResetZoom;

@end

@implementation MotionPhotoEditorViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    self.arrows = [NSMutableArray array];
    self.undoStack = [NSMutableArray array];
    self.redoStack = [NSMutableArray array];
    self.selectedArrowIndex = NSNotFound;
    self.editorMode = MotionPhotoEditorModeMask;
    self.brushMode = MotionPhotoBrushModePaint;
    self.needsResetZoom = YES;

    [self buildInterface];
    [self bindCanvasCallbacks];
    [self refreshUI];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    CGFloat safeTop = 0.0;
    CGFloat safeBottom = 0.0;
    if (@available(iOS 11.0, *)) {
        safeTop = self.view.safeAreaInsets.top;
        safeBottom = self.view.safeAreaInsets.bottom;
    }

    CGFloat topBarHeight = 68.0;
    self.topBarView.frame = CGRectMake(0.0, 0.0, width, safeTop + topBarHeight);
    CGFloat topY = safeTop + 10.0;
    self.backButton.frame = CGRectMake(12.0, topY, 40.0, 40.0);
    self.importButton.frame = CGRectMake(58.0, topY, 40.0, 40.0);
    self.titleLabel.frame = CGRectMake(110.0, topY, width - 220.0, 40.0);
    self.exportButton.frame = CGRectMake(width - 110.0, topY, 98.0, 40.0);

    CGFloat bottomPanelHeight = 164.0 + safeBottom;
    self.bottomPanel.frame = CGRectMake(0.0, height - bottomPanelHeight, width, bottomPanelHeight);

    CGFloat rightToolbarWidth = 58.0;
    CGFloat canvasTop = CGRectGetMaxY(self.topBarView.frame) + 8.0;
    CGFloat canvasBottom = CGRectGetMinY(self.bottomPanel.frame) - 8.0;
    CGFloat canvasHeight = MAX(180.0, canvasBottom - canvasTop);
    self.rightToolbar.frame = CGRectMake(width - rightToolbarWidth, canvasTop, rightToolbarWidth, canvasHeight);
    CGFloat toolButtonSize = 44.0;
    self.brushButton.frame = CGRectMake(7.0, canvasHeight - toolButtonSize * 2.0 - 18.0, toolButtonSize, toolButtonSize);
    self.eraserButton.frame = CGRectMake(7.0, canvasHeight - toolButtonSize - 10.0, toolButtonSize, toolButtonSize);
    self.deleteButton.frame = CGRectMake(7.0, canvasHeight - toolButtonSize - 10.0, toolButtonSize, toolButtonSize);

    CGFloat canvasWidth = width - rightToolbarWidth - 20.0;
    self.canvasScrollView.frame = CGRectMake(10.0, canvasTop, canvasWidth, canvasHeight);

    CGSize imageSize = self.sourceImage ? self.sourceImage.size : CGSizeMake(900.0, 1400.0);
    CGFloat fitScale = MIN(canvasWidth / MAX(imageSize.width, 1.0), canvasHeight / MAX(imageSize.height, 1.0));
    CGSize fittedSize = CGSizeMake(MAX(floor(imageSize.width * fitScale), 1.0),
                                   MAX(floor(imageSize.height * fitScale), 1.0));
    self.canvasContentView.frame = CGRectMake(0.0, 0.0, fittedSize.width, fittedSize.height);
    self.flowRenderer.metalView.frame = self.canvasContentView.bounds;
    self.canvasView.frame = self.canvasContentView.bounds;
    self.canvasScrollView.contentSize = fittedSize;
    [self centerCanvasContent];

    self.canvasScrollView.minimumZoomScale = 1.0;
    self.canvasScrollView.maximumZoomScale = 4.5;
    if (self.needsResetZoom) {
        self.canvasScrollView.zoomScale = 1.0;
        self.needsResetZoom = NO;
    }

    self.speedSlider.frame = CGRectMake(82.0, 10.0, width - 164.0, 30.0);
    self.undoButton.frame = CGRectMake(14.0, 58.0, 44.0, 44.0);
    self.redoButton.frame = CGRectMake(62.0, 58.0, 44.0, 44.0);
    self.playButton.frame = CGRectMake(width - 58.0, 58.0, 44.0, 44.0);
    self.maskModeButton.frame = CGRectMake(width * 0.5 - 110.0, 104.0, 92.0, 44.0);
    self.directionModeButton.frame = CGRectMake(width * 0.5 + 18.0, 104.0, 92.0, 44.0);

    CGFloat renderScale = self.view.window.screen.scale ?: self.view.contentScaleFactor;
    self.flowRenderer.metalView.drawableSize = CGSizeMake(fittedSize.width * renderScale,
                                                          fittedSize.height * renderScale);
    [self refreshUI];
}

- (void)buildInterface {
    self.navigationController.navigationBarHidden = YES;

    self.topBarView = [[UIView alloc] init];
    self.topBarView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    [self.view addSubview:self.topBarView];

    self.backButton = [self iconButtonWithSystemName:@"chevron.left"];
    [self.backButton addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBarView addSubview:self.backButton];

    self.importButton = [self iconButtonWithSystemName:@"photo.on.rectangle.angled"];
    [self.importButton addTarget:self action:@selector(importTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBarView addSubview:self.importButton];

    self.exportButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.exportButton.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1.0];
    self.exportButton.layer.cornerRadius = 20.0;
    self.exportButton.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    [self.exportButton setTitle:@"导出" forState:UIControlStateNormal];
    [self.exportButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    if (@available(iOS 13.0, *)) {
        [self.exportButton setImage:[UIImage systemImageNamed:@"square.and.arrow.up"] forState:UIControlStateNormal];
        self.exportButton.tintColor = [UIColor whiteColor];
        self.exportButton.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
        self.exportButton.imageEdgeInsets = UIEdgeInsetsMake(0.0, -6.0, 0.0, 0.0);
    }
    [self.exportButton addTarget:self action:@selector(exportTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBarView addSubview:self.exportButton];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = MotionPhotoEditorTitle;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.font = [UIFont boldSystemFontOfSize:22.0];
    self.titleLabel.textColor = [UIColor colorWithRed:1.0 green:0.63 blue:0.27 alpha:1.0];
    [self.topBarView addSubview:self.titleLabel];

    self.canvasScrollView = [[UIScrollView alloc] init];
    self.canvasScrollView.delegate = self;
    self.canvasScrollView.showsVerticalScrollIndicator = NO;
    self.canvasScrollView.showsHorizontalScrollIndicator = NO;
    self.canvasScrollView.bouncesZoom = YES;
    self.canvasScrollView.delaysContentTouches = NO;
    self.canvasScrollView.canCancelContentTouches = YES;
    self.canvasScrollView.panGestureRecognizer.minimumNumberOfTouches = 2;
    [self.view addSubview:self.canvasScrollView];

    self.canvasContentView = [[UIView alloc] init];
    self.canvasContentView.clipsToBounds = YES;
    self.canvasContentView.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    [self.canvasScrollView addSubview:self.canvasContentView];

    self.flowRenderer = [[MotionPhotoFlowRenderer alloc] initWithFrame:CGRectZero];
    [self.canvasContentView addSubview:self.flowRenderer.metalView];

    self.canvasView = [[MotionPhotoCanvasView alloc] initWithFrame:CGRectZero];
    [self.canvasContentView addSubview:self.canvasView];

    self.rightToolbar = [[UIView alloc] init];
    self.rightToolbar.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.rightToolbar];

    self.brushButton = [self verticalToolButtonWithSystemName:@"paintbrush.fill"];
    [self.brushButton addTarget:self action:@selector(brushTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.rightToolbar addSubview:self.brushButton];

    self.eraserButton = [self verticalToolButtonWithSystemName:@"eraser.fill"];
    [self.eraserButton addTarget:self action:@selector(eraserTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.rightToolbar addSubview:self.eraserButton];

    self.deleteButton = [self verticalToolButtonWithSystemName:@"trash.fill"];
    [self.deleteButton addTarget:self action:@selector(deleteArrowTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.rightToolbar addSubview:self.deleteButton];

    self.bottomPanel = [[UIView alloc] init];
    self.bottomPanel.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1.0];
    [self.view addSubview:self.bottomPanel];

    self.speedSlider = [[UISlider alloc] init];
    self.speedSlider.minimumValue = 0.0f;
    self.speedSlider.maximumValue = 1.0f;
    self.speedSlider.value = 0.34f;
    self.speedSlider.minimumTrackTintColor = [UIColor colorWithRed:1.0 green:0.54 blue:0.19 alpha:1.0];
    self.speedSlider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    [self.speedSlider addTarget:self action:@selector(speedSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.bottomPanel addSubview:self.speedSlider];

    self.undoButton = [self iconButtonWithSystemName:@"arrow.uturn.backward"];
    [self.undoButton addTarget:self action:@selector(undoTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomPanel addSubview:self.undoButton];

    self.redoButton = [self iconButtonWithSystemName:@"arrow.uturn.forward"];
    [self.redoButton addTarget:self action:@selector(redoTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomPanel addSubview:self.redoButton];

    self.playButton = [self iconButtonWithSystemName:@"play.fill"];
    [self.playButton addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomPanel addSubview:self.playButton];

    self.maskModeButton = [self modeButtonWithTitle:@"选择" systemName:@"paintbrush"];
    [self.maskModeButton addTarget:self action:@selector(maskModeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomPanel addSubview:self.maskModeButton];

    self.directionModeButton = [self modeButtonWithTitle:@"方向" systemName:@"arrow.down.left.and.arrow.up.right"];
    [self.directionModeButton addTarget:self action:@selector(directionModeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomPanel addSubview:self.directionModeButton];
}

- (void)bindCanvasCallbacks {
    __weak typeof(self) weakSelf = self;
    self.canvasView.maskStrokeHandler = ^(UIBezierPath *path, CGFloat brushSize, BOOL erasing) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf applyMaskStroke:path brushSize:brushSize erasing:erasing];
    };
    self.canvasView.directionCreateHandler = ^(NSArray<NSValue *> *points) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf createArrowFromPoints:points];
    };
    self.canvasView.directionSelectHandler = ^(NSInteger index) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.selectedArrowIndex = index;
        [strongSelf refreshUI];
    };
    self.canvasView.interactionStateHandler = ^(BOOL active) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.canvasScrollView.panGestureRecognizer.enabled = !active;
        strongSelf.canvasScrollView.pinchGestureRecognizer.enabled = !active;
    };
}

#pragma mark - UI Actions

- (void)backTapped {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)importTapped {
    if (@available(iOS 14.0, *)) {
        PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
        config.filter = [PHPickerFilter imagesFilter];
        config.selectionLimit = 1;
        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    }
}

- (void)exportTapped {
    [self showAlertWithTitle:@"MVP 阶段" message:@"先把蒙层 + 划线流动预览跑稳，导出下一步再接。"];
}

- (void)brushTapped {
    self.brushMode = MotionPhotoBrushModePaint;
    [self refreshUI];
}

- (void)eraserTapped {
    self.brushMode = MotionPhotoBrushModeErase;
    [self refreshUI];
}

- (void)deleteArrowTapped {
    if (self.selectedArrowIndex == NSNotFound || self.selectedArrowIndex >= (NSInteger)self.arrows.count) {
        return;
    }
    [self pushUndoSnapshot];
    [self.arrows removeObjectAtIndex:self.selectedArrowIndex];
    self.selectedArrowIndex = NSNotFound;
    [self.redoStack removeAllObjects];
    [self syncRendererAndOverlay];
}

- (void)maskModeTapped {
    self.editorMode = MotionPhotoEditorModeMask;
    [self refreshUI];
}

- (void)directionModeTapped {
    self.editorMode = MotionPhotoEditorModeDirection;
    [self refreshUI];
}

- (void)undoTapped {
    NSDictionary *snapshot = self.undoStack.lastObject;
    if (!snapshot) {
        return;
    }
    [self.undoStack removeLastObject];
    [self.redoStack addObject:[self currentSnapshot]];
    [self restoreSnapshot:snapshot];
}

- (void)redoTapped {
    NSDictionary *snapshot = self.redoStack.lastObject;
    if (!snapshot) {
        return;
    }
    [self.redoStack removeLastObject];
    [self.undoStack addObject:[self currentSnapshot]];
    [self restoreSnapshot:snapshot];
}

- (void)playTapped {
    self.flowRenderer.playing = !self.flowRenderer.isPlaying;
    [self refreshUI];
}

- (void)speedSliderChanged:(UISlider *)sender {
    self.flowRenderer.playbackSpeed = 0.35 + sender.value * 1.95;
}

#pragma mark - State

- (void)applyMaskStroke:(UIBezierPath *)path brushSize:(CGFloat)brushSize erasing:(BOOL)erasing {
    if (!self.sourceImage || self.canvasView.bounds.size.width < 1.0 || self.canvasView.bounds.size.height < 1.0) {
        return;
    }

    [self pushUndoSnapshot];

    CGSize size = self.canvasView.bounds.size;
    UIImage *previousMask = self.maskImage;
    UIBezierPath *canvasPath = [path copy];
    canvasPath.lineWidth = brushSize;
    canvasPath.lineCapStyle = kCGLineCapRound;
    canvasPath.lineJoinStyle = kCGLineJoinRound;

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = NO;
    format.scale = 1.0;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    self.maskImage = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        [previousMask drawAtPoint:CGPointZero];
        CGContextRef cg = context.CGContext;
        CGContextSetBlendMode(cg, erasing ? kCGBlendModeClear : kCGBlendModeNormal);
        [[UIColor whiteColor] setStroke];
        [canvasPath stroke];
    }];

    [self.redoStack removeAllObjects];
    [self syncRendererAndOverlay];
}

- (void)createArrowFromPoints:(NSArray<NSValue *> *)points {
    if (!self.sourceImage) {
        return;
    }
    if (points.count < 2) {
        return;
    }
    CGFloat distance = 0.0;
    for (NSUInteger idx = 1; idx < points.count; idx++) {
        CGPoint a = points[idx - 1].CGPointValue;
        CGPoint b = points[idx].CGPointValue;
        distance += hypot(b.x - a.x, b.y - a.y);
    }
    if (distance < 18.0) {
        return;
    }

    [self pushUndoSnapshot];

    MotionPhotoArrow *arrow = [[MotionPhotoArrow alloc] init];
    arrow.startPoint = points.firstObject.CGPointValue;
    arrow.endPoint = points.lastObject.CGPointValue;
    arrow.controlPoints = points.copy;
    arrow.intensity = MIN(MAX(distance / 120.0, 0.45), 1.8);
    [self.arrows addObject:arrow];
    self.selectedArrowIndex = self.arrows.count - 1;
    [self.redoStack removeAllObjects];
    [self syncRendererAndOverlay];
}

- (void)syncRendererAndOverlay {
    self.canvasView.maskPreviewImage = [self maskPreviewImage];
    self.canvasView.arrows = self.arrows.copy;
    self.canvasView.selectedArrowIndex = self.selectedArrowIndex;
    [self.flowRenderer updateFlowWithMaskImage:self.maskImage
                                        arrows:self.arrows.copy
                                    canvasSize:self.canvasView.bounds.size];
    [self refreshUI];
}

- (void)refreshUI {
    BOOL showsOverlay = !self.flowRenderer.isPlaying;
    self.canvasView.editorMode = self.editorMode;
    self.canvasView.brushMode = self.brushMode;
    self.canvasView.brushSize = [self currentBrushSize];
    self.canvasView.showsOverlay = showsOverlay;
    self.canvasView.maskPreviewImage = showsOverlay ? [self maskPreviewImage] : nil;
    self.canvasView.arrows = showsOverlay ? self.arrows.copy : @[];
    self.canvasView.selectedArrowIndex = showsOverlay ? self.selectedArrowIndex : NSNotFound;

    BOOL isMaskMode = self.editorMode == MotionPhotoEditorModeMask;
    self.brushButton.hidden = !isMaskMode;
    self.eraserButton.hidden = !isMaskMode;
    self.deleteButton.hidden = isMaskMode;

    self.brushButton.backgroundColor = (isMaskMode && self.brushMode == MotionPhotoBrushModePaint)
        ? [UIColor colorWithRed:1.0 green:0.54 blue:0.19 alpha:1.0]
        : [UIColor colorWithWhite:0.10 alpha:1.0];
    self.eraserButton.backgroundColor = (isMaskMode && self.brushMode == MotionPhotoBrushModeErase)
        ? [UIColor colorWithRed:1.0 green:0.54 blue:0.19 alpha:1.0]
        : [UIColor colorWithWhite:0.10 alpha:1.0];
    self.deleteButton.backgroundColor = (!isMaskMode && self.selectedArrowIndex != NSNotFound)
        ? [UIColor colorWithRed:0.82 green:0.28 blue:0.20 alpha:1.0]
        : [UIColor colorWithWhite:0.10 alpha:1.0];

    UIColor *activeColor = [UIColor colorWithRed:1.0 green:0.54 blue:0.19 alpha:1.0];
    UIColor *inactiveColor = [UIColor colorWithWhite:0.70 alpha:1.0];
    [self.maskModeButton setTitleColor:isMaskMode ? activeColor : inactiveColor forState:UIControlStateNormal];
    [self.directionModeButton setTitleColor:isMaskMode ? inactiveColor : activeColor forState:UIControlStateNormal];
    self.maskModeButton.tintColor = isMaskMode ? activeColor : inactiveColor;
    self.directionModeButton.tintColor = isMaskMode ? inactiveColor : activeColor;

    NSString *playName = self.flowRenderer.isPlaying ? @"pause.fill" : @"play.fill";
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold];
        [self.playButton setImage:[UIImage systemImageNamed:playName withConfiguration:config] forState:UIControlStateNormal];
    }

    self.flowRenderer.playbackSpeed = 0.35 + self.speedSlider.value * 1.95;
    [self.flowRenderer requestRender];
}

#pragma mark - Snapshot

- (NSDictionary *)currentSnapshot {
    NSMutableArray<MotionPhotoArrow *> *arrowCopies = [NSMutableArray arrayWithCapacity:self.arrows.count];
    for (MotionPhotoArrow *arrow in self.arrows) {
        [arrowCopies addObject:[arrow copy]];
    }
    return @{
        @"maskImage": self.maskImage ?: [NSNull null],
        @"arrows": arrowCopies,
        @"selectedArrowIndex": @(self.selectedArrowIndex)
    };
}

- (void)pushUndoSnapshot {
    [self.undoStack addObject:[self currentSnapshot]];
}

- (void)restoreSnapshot:(NSDictionary *)snapshot {
    id maskValue = snapshot[@"maskImage"];
    self.maskImage = [maskValue isKindOfClass:[UIImage class]] ? maskValue : nil;
    NSArray *savedArrows = snapshot[@"arrows"];
    [self.arrows removeAllObjects];
    for (MotionPhotoArrow *arrow in savedArrows) {
        [self.arrows addObject:[arrow copy]];
    }
    self.selectedArrowIndex = [snapshot[@"selectedArrowIndex"] integerValue];
    [self syncRendererAndOverlay];
}

#pragma mark - Helpers

- (void)setEditorImage:(UIImage *)image {
    self.sourceImage = image;
    self.maskImage = nil;
    [self.arrows removeAllObjects];
    [self.undoStack removeAllObjects];
    [self.redoStack removeAllObjects];
    self.selectedArrowIndex = NSNotFound;
    self.needsResetZoom = YES;
    self.flowRenderer.playing = NO;
    [self.flowRenderer setSourceImage:image];
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [self syncRendererAndOverlay];
}

- (UIImage *)preparedImageForImport:(UIImage *)image {
    CGFloat maxEdge = MAX(image.size.width, image.size.height);
    CGFloat scale = 1.0;
    if (maxEdge > 1440.0) {
        scale = 1440.0 / maxEdge;
    }
    CGSize size = CGSizeMake(MAX(round(image.size.width * scale), 1.0),
                             MAX(round(image.size.height * scale), 1.0));
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = YES;
    format.scale = 1.0;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        [image drawInRect:CGRectMake(0.0, 0.0, size.width, size.height)];
    }];
}

- (CGPoint)canvasToImageScale {
    CGSize canvasSize = self.canvasView.bounds.size;
    CGSize imageSize = self.sourceImage.size;
    if (canvasSize.width < 1.0 || canvasSize.height < 1.0) {
        return CGPointMake(1.0, 1.0);
    }
    return CGPointMake(imageSize.width / canvasSize.width, imageSize.height / canvasSize.height);
}

- (CGFloat)currentBrushSize {
    CGFloat zoomScale = MAX(self.canvasScrollView.zoomScale, 1.0);
    return MAX(8.0, 34.0 / zoomScale);
}

- (UIImage *)maskPreviewImage {
    if (!self.maskImage || self.canvasView.bounds.size.width < 2.0 || self.canvasView.bounds.size.height < 2.0) {
        return nil;
    }

    CGSize previewSize = self.canvasView.bounds.size;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = NO;
    format.scale = 1.0;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:previewSize format:format];
    UIImage *scaledMask = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        [self.maskImage drawInRect:CGRectMake(0.0, 0.0, previewSize.width, previewSize.height)];
    }];

    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        CGRect rect = CGRectMake(0.0, 0.0, previewSize.width, previewSize.height);
        CGContextRef cg = context.CGContext;

        CGContextSaveGState(cg);
        [[UIColor colorWithRed:1.0 green:0.74 blue:0.18 alpha:0.42] setFill];
        UIRectFill(rect);
        [scaledMask drawInRect:rect blendMode:kCGBlendModeDestinationIn alpha:1.0];
        CGContextRestoreGState(cg);

        CGContextSaveGState(cg);
        [[UIColor colorWithRed:1.0 green:0.88 blue:0.42 alpha:0.12] setFill];
        UIRectFill(rect);
        [scaledMask drawInRect:rect blendMode:kCGBlendModeDestinationIn alpha:1.0];
        CGContextRestoreGState(cg);
    }];
}

- (void)centerCanvasContent {
    CGFloat offsetX = MAX((self.canvasScrollView.bounds.size.width - self.canvasScrollView.contentSize.width) * 0.5, 0.0);
    CGFloat offsetY = MAX((self.canvasScrollView.bounds.size.height - self.canvasScrollView.contentSize.height) * 0.5, 0.0);
    self.canvasContentView.center = CGPointMake(self.canvasScrollView.contentSize.width * 0.5 + offsetX,
                                                self.canvasScrollView.contentSize.height * 0.5 + offsetY);
}

- (UIButton *)iconButtonWithSystemName:(NSString *)systemName {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = [UIColor clearColor];
    button.tintColor = [UIColor whiteColor];
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightMedium];
        [button setImage:[UIImage systemImageNamed:systemName withConfiguration:config] forState:UIControlStateNormal];
    }
    return button;
}

- (UIButton *)verticalToolButtonWithSystemName:(NSString *)systemName {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    button.layer.cornerRadius = 10.0;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.08].CGColor;
    button.tintColor = [UIColor whiteColor];
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:21 weight:UIImageSymbolWeightSemibold];
        [button setImage:[UIImage systemImageNamed:systemName withConfiguration:config] forState:UIControlStateNormal];
    }
    return button;
}

- (UIButton *)modeButtonWithTitle:(NSString *)title systemName:(NSString *)systemName {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = [UIColor clearColor];
    button.tintColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    button.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:0.75 alpha:1.0] forState:UIControlStateNormal];
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular];
        UIImage *image = [UIImage systemImageNamed:systemName withConfiguration:config];
        [button setImage:image forState:UIControlStateNormal];
        button.imageEdgeInsets = UIEdgeInsetsMake(-14.0, 22.0, 12.0, -22.0);
        button.titleEdgeInsets = UIEdgeInsetsMake(24.0, -18.0, -4.0, 0.0);
    }
    return button;
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.canvasContentView;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    [self centerCanvasContent];
    self.canvasView.brushSize = [self currentBrushSize];
}

#pragma mark - PHPickerViewControllerDelegate

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14.0)) {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result) {
        return;
    }

    NSItemProvider *provider = result.itemProvider;
    if (![provider canLoadObjectOfClass:[UIImage class]]) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    [provider loadObjectOfClass:[UIImage class] completionHandler:^(UIImage * _Nullable image, NSError * _Nullable error) {
        if (!image || error) {
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            UIImage *prepared = [strongSelf preparedImageForImport:image];
            [strongSelf setEditorImage:prepared];
        });
    }];
}

@end
