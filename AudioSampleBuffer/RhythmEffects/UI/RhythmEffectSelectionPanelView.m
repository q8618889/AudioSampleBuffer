#import "RhythmEffectSelectionPanelView.h"

#import "RhythmEffectDescriptor.h"

@interface RhythmEffectSelectionPanelView ()

@property (nonatomic, strong) UIView *grabberView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *helperLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *toggleButton;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UIScrollView *optionScrollView;
@property (nonatomic, strong) UIView *parameterPageView;
@property (nonatomic, strong) UILabel *parameterTitleLabel;
@property (nonatomic, strong) UILabel *parameterHintLabel;
@property (nonatomic, strong) NSMutableArray<UIButton *> *optionButtons;
@property (nonatomic, strong) NSMutableArray<UILabel *> *parameterValueLabels;
@property (nonatomic, strong) UISlider *intensitySlider;
@property (nonatomic, strong) UISlider *beatBoostSlider;
@property (nonatomic, strong) UISlider *radiusSlider;
@property (nonatomic, strong) UISlider *speedSlider;
@property (nonatomic, strong) UIView *beatSyncRow;
@property (nonatomic, strong) UILabel *beatSyncLabel;
@property (nonatomic, strong) UISwitch *beatSyncSwitch;
@property (nonatomic, strong) UILabel *beatSyncHintLabel;
@property (nonatomic, strong) NSArray<RhythmEffectDescriptor *> *currentDescriptors;
@property (nonatomic, assign) BOOL rhythmEnabled;
@property (nonatomic, assign) RhythmDispersionEffectType selectedDispersionEffect;
@property (nonatomic, assign) RhythmFeatureEffectType selectedFeatureEffect;
@property (nonatomic, assign) CGFloat transformIntensity;
@property (nonatomic, assign) CGFloat transformBeatBoost;
@property (nonatomic, assign) CGFloat transformRadius;
@property (nonatomic, assign) CGFloat transformSpeed;
@property (nonatomic, assign) BOOL beatSyncEnabled;
@property (nonatomic, assign) BOOL isShowingParameterPage;

@end

@implementation RhythmEffectSelectionPanelView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.07 alpha:0.98];
        self.layer.cornerRadius = 24.0;
        self.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;

        _optionButtons = [NSMutableArray array];
        _parameterValueLabels = [NSMutableArray array];
        _selectedDispersionEffect = RhythmDispersionEffectTypeColorPulse;
        _selectedFeatureEffect = RhythmFeatureEffectTypeDroplet;
        _transformIntensity = 0.72;
        _transformBeatBoost = 0.82;
        _transformRadius = 0.56;
        _transformSpeed = 0.64;

        _grabberView = [[UIView alloc] initWithFrame:CGRectZero];
        _grabberView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.22];
        _grabberView.layer.cornerRadius = 2.5;
        [self addSubview:_grabberView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.text = @"特效";
        _titleLabel.font = [UIFont boldSystemFontOfSize:18];
        _titleLabel.textColor = [UIColor whiteColor];
        [self addSubview:_titleLabel];

        _helperLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _helperLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _helperLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.65];
        _helperLabel.numberOfLines = 2;
        [self addSubview:_helperLabel];

        _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_closeButton setTitle:@"完成" forState:UIControlStateNormal];
        _closeButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [_closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _closeButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
        _closeButton.layer.cornerRadius = 16.0;
        [_closeButton addTarget:self action:@selector(handleCloseTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_closeButton];

        _toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _toggleButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
        [_toggleButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _toggleButton.layer.cornerRadius = 16.0;
        [_toggleButton addTarget:self action:@selector(handleToggleTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_toggleButton];

        _backButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_backButton setTitle:@"返回" forState:UIControlStateNormal];
        _backButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [_backButton setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.92] forState:UIControlStateNormal];
        _backButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
        _backButton.layer.cornerRadius = 16.0;
        _backButton.hidden = YES;
        [_backButton addTarget:self action:@selector(handleBackTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_backButton];

        _modeControl = [[UISegmentedControl alloc] initWithItems:@[@"色散", @"特效"]];
        _modeControl.selectedSegmentIndex = 1;
        _modeControl.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
        _modeControl.selectedSegmentTintColor = [UIColor colorWithRed:0.28 green:0.56 blue:1.0 alpha:1.0];
        [_modeControl setTitleTextAttributes:@{
            NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.86],
            NSFontAttributeName: [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold]
        } forState:UIControlStateNormal];
        [_modeControl setTitleTextAttributes:@{
            NSForegroundColorAttributeName: [UIColor whiteColor],
            NSFontAttributeName: [UIFont systemFontOfSize:12 weight:UIFontWeightBold]
        } forState:UIControlStateSelected];
        [_modeControl addTarget:self action:@selector(handleModeChanged:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:_modeControl];

        _optionScrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
        _optionScrollView.showsHorizontalScrollIndicator = NO;
        _optionScrollView.alwaysBounceHorizontal = YES;
        [self addSubview:_optionScrollView];

        _parameterPageView = [[UIView alloc] initWithFrame:CGRectZero];
        _parameterPageView.hidden = YES;
        [self addSubview:_parameterPageView];

        _parameterTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _parameterTitleLabel.font = [UIFont boldSystemFontOfSize:18];
        _parameterTitleLabel.textColor = [UIColor whiteColor];
        [_parameterPageView addSubview:_parameterTitleLabel];

        _parameterHintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _parameterHintLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _parameterHintLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.62];
        _parameterHintLabel.numberOfLines = 2;
        _parameterHintLabel.text = @"长按进入这里。调强度、冲击、范围和速度，都会直接绑定 beat。";
        [_parameterPageView addSubview:_parameterHintLabel];

        [self buildParameterControls];
        [self reloadOptions];
        [self updateToggleButton];
    }
    return self;
}

- (void)buildParameterControls {
    NSArray<NSString *> *titles = @[@"强度", @"冲击", @"范围", @"速度"];
    NSMutableArray<UISlider *> *sliders = [NSMutableArray array];
    for (NSString *title in titles) {
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.text = title;
        label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        label.textColor = [UIColor colorWithWhite:1.0 alpha:0.84];
        label.tag = 700 + sliders.count;
        [self.parameterPageView addSubview:label];

        UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
        valueLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.68];
        valueLabel.textAlignment = NSTextAlignmentRight;
        [self.parameterPageView addSubview:valueLabel];
        [self.parameterValueLabels addObject:valueLabel];

        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectZero];
        slider.minimumValue = 0.0f;
        slider.maximumValue = 1.0f;
        slider.minimumTrackTintColor = [UIColor colorWithRed:0.28 green:0.56 blue:1.0 alpha:1.0];
        slider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.15];
        [slider addTarget:self action:@selector(handleParameterSliderChanged:) forControlEvents:UIControlEventValueChanged];
        [self.parameterPageView addSubview:slider];
        [sliders addObject:slider];
    }
    self.intensitySlider = sliders[0];
    self.beatBoostSlider = sliders[1];
    self.radiusSlider = sliders[2];
    self.speedSlider = sliders[3];

    _beatSyncRow = [[UIView alloc] initWithFrame:CGRectZero];
    _beatSyncRow.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    _beatSyncRow.layer.cornerRadius = 12.0;
    [self.parameterPageView addSubview:_beatSyncRow];

    _beatSyncLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _beatSyncLabel.text = @"Beat 联动";
    _beatSyncLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    _beatSyncLabel.textColor = [UIColor whiteColor];
    [_beatSyncRow addSubview:_beatSyncLabel];

    _beatSyncHintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _beatSyncHintLabel.text = @"仅在拍点触发，从 0 渐入到配置值";
    _beatSyncHintLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    _beatSyncHintLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.50];
    _beatSyncHintLabel.numberOfLines = 1;
    [_beatSyncRow addSubview:_beatSyncHintLabel];

    _beatSyncSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _beatSyncSwitch.onTintColor = [UIColor colorWithRed:0.94 green:0.51 blue:0.18 alpha:1.0];
    _beatSyncSwitch.transform = CGAffineTransformMakeScale(0.75, 0.75);
    [_beatSyncSwitch addTarget:self action:@selector(handleBeatSyncSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_beatSyncRow addSubview:_beatSyncSwitch];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = self.bounds.size.width;
    self.grabberView.frame = CGRectMake((width - 42.0) * 0.5, 8.0, 42.0, 5.0);

    BOOL editing = self.isShowingParameterPage;
    self.backButton.hidden = !editing;
    self.modeControl.hidden = editing;
    self.optionScrollView.hidden = editing;
    self.parameterPageView.hidden = !editing;

    CGFloat leading = 16.0;
    self.titleLabel.frame = CGRectMake(leading, 24.0, width - 220.0, 24.0);
    self.closeButton.frame = CGRectMake(width - 72.0, 20.0, 56.0, 32.0);
    self.toggleButton.frame = CGRectMake(width - 144.0, 20.0, 64.0, 32.0);
    self.backButton.frame = CGRectMake(leading, 60.0, 56.0, 32.0);

    if (!editing) {
        self.modeControl.frame = CGRectMake(leading, 62.0, width - 32.0, 30.0);
        self.helperLabel.frame = CGRectMake(leading, 100.0, width - 32.0, 32.0);
        self.optionScrollView.frame = CGRectMake(0.0, 140.0, width, self.bounds.size.height - 150.0);

        CGFloat cardW = 118.0;
        CGFloat cardH = MIN(140.0, self.optionScrollView.bounds.size.height - 10.0);
        CGFloat x = 16.0;
        for (UIButton *button in self.optionButtons) {
            button.frame = CGRectMake(x, 0.0, cardW, cardH);
            x += cardW + 12.0;
        }
        self.optionScrollView.contentSize = CGSizeMake(MAX(width, x), self.optionScrollView.bounds.size.height);
    } else {
        self.helperLabel.frame = CGRectMake(80.0, 64.0, width - 160.0, 28.0);
        self.parameterPageView.frame = CGRectMake(0.0, 100.0, width, self.bounds.size.height - 108.0);
        self.parameterTitleLabel.frame = CGRectMake(16.0, 0.0, width - 32.0, 24.0);
        self.parameterHintLabel.frame = CGRectMake(16.0, 30.0, width - 32.0, 34.0);

        CGFloat beatSyncRowH = 52.0;
        self.beatSyncRow.frame = CGRectMake(16.0, 0.0, width - 32.0, beatSyncRowH);
        self.beatSyncLabel.frame = CGRectMake(14.0, 8.0, 120.0, 18.0);
        self.beatSyncHintLabel.frame = CGRectMake(14.0, 28.0, width - 110.0, 16.0);
        CGFloat switchW = 51.0 * 0.75;
        self.beatSyncSwitch.center = CGPointMake(self.beatSyncRow.bounds.size.width - switchW * 0.5 - 10.0,
                                                  beatSyncRowH * 0.5);

        NSArray<UISlider *> *sliders = @[self.intensitySlider, self.beatBoostSlider, self.radiusSlider, self.speedSlider];
        CGFloat availableHeight = MAX(120.0, self.parameterPageView.bounds.size.height);
        CGFloat rowTop = beatSyncRowH + 14.0;
        CGFloat bottomPadding = 10.0;
        CGFloat dynamicRowSpacing = (availableHeight - rowTop - bottomPadding) / sliders.count;
        CGFloat rowSpacing = MAX(36.0, MIN(50.0, dynamicRowSpacing));
        for (NSInteger idx = 0; idx < sliders.count; idx++) {
            UILabel *label = [self.parameterPageView viewWithTag:700 + idx];
            UILabel *valueLabel = self.parameterValueLabels[idx];
            UISlider *slider = sliders[idx];
            CGFloat y = rowTop + idx * rowSpacing;
            label.frame = CGRectMake(16.0, y, 44.0, 18.0);
            valueLabel.frame = CGRectMake(width - 64.0, y, 48.0, 18.0);
            slider.frame = CGRectMake(72.0, y - 4.0, width - 144.0, 26.0);
        }
    }
}

- (void)applyRhythmEnabled:(BOOL)enabled
          dispersionEffect:(RhythmDispersionEffectType)dispersionEffect
               featureEffect:(RhythmFeatureEffectType)featureEffect
          transformIntensity:(CGFloat)transformIntensity
         transformBeatBoost:(CGFloat)transformBeatBoost
             transformRadius:(CGFloat)transformRadius
             transformSpeed:(CGFloat)transformSpeed
           beatSyncEnabled:(BOOL)beatSyncEnabled {
    self.rhythmEnabled = enabled;
    self.selectedDispersionEffect = dispersionEffect;
    self.selectedFeatureEffect = featureEffect;
    self.transformIntensity = transformIntensity;
    self.transformBeatBoost = transformBeatBoost;
    self.transformRadius = transformRadius;
    self.transformSpeed = transformSpeed;
    self.beatSyncEnabled = beatSyncEnabled;
    [self updateToggleButton];
    [self updateSelectionUI];
    [self updateBeatSyncUI];
}

- (void)handleCloseTapped {
    if (self.closeHandler) {
        self.closeHandler();
    }
}

- (void)handleBackTapped {
    self.isShowingParameterPage = NO;
    [self updateSelectionUI];
}

- (void)handleToggleTapped {
    self.rhythmEnabled = !self.rhythmEnabled;
    [self updateToggleButton];
    if (self.toggleEnabledHandler) {
        self.toggleEnabledHandler(self.rhythmEnabled);
    }
}

- (void)handleModeChanged:(UISegmentedControl *)sender {
    (void)sender;
    self.isShowingParameterPage = NO;
    [self reloadOptions];
}

- (void)handleOptionTapped:(UIButton *)sender {
    NSInteger rawValue = sender.tag;
    if (self.modeControl.selectedSegmentIndex == 0) {
        self.selectedDispersionEffect = (RhythmDispersionEffectType)rawValue;
        if (self.dispersionSelectionHandler) {
            self.dispersionSelectionHandler(self.selectedDispersionEffect);
        }
    } else {
        self.selectedFeatureEffect = (RhythmFeatureEffectType)rawValue;
        if (self.featureSelectionHandler) {
            self.featureSelectionHandler(self.selectedFeatureEffect);
        }
    }
    [self updateSelectionUI];
}

- (void)handleOptionLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }
    if (self.modeControl.selectedSegmentIndex != 1) {
        return;
    }
    UIButton *button = (UIButton *)gesture.view;
    if (![button isKindOfClass:[UIButton class]]) {
        return;
    }
    self.selectedFeatureEffect = (RhythmFeatureEffectType)button.tag;
    if (self.featureSelectionHandler) {
        self.featureSelectionHandler(self.selectedFeatureEffect);
    }
    self.isShowingParameterPage = YES;
    [self updateSelectionUI];
}

- (void)handleParameterSliderChanged:(UISlider *)sender {
    (void)sender;
    self.transformIntensity = self.intensitySlider.value;
    self.transformBeatBoost = self.beatBoostSlider.value;
    self.transformRadius = self.radiusSlider.value;
    self.transformSpeed = self.speedSlider.value;
    [self updateParameterUI];
    if (self.featureParameterChangedHandler) {
        self.featureParameterChangedHandler(self.transformIntensity,
                                           self.transformBeatBoost,
                                           self.transformRadius,
                                           self.transformSpeed);
    }
}

- (void)handleBeatSyncSwitchChanged:(UISwitch *)sender {
    self.beatSyncEnabled = sender.isOn;
    [self updateBeatSyncUI];
    if (self.beatSyncChangedHandler) {
        self.beatSyncChangedHandler(self.beatSyncEnabled);
    }
}

- (void)reloadOptions {
    for (UIButton *button in self.optionButtons) {
        [button removeFromSuperview];
    }
    [self.optionButtons removeAllObjects];

    BOOL isDispersion = (self.modeControl.selectedSegmentIndex == 0);
    self.currentDescriptors = isDispersion ? [RhythmEffectDescriptor dispersionDescriptors] : [RhythmEffectDescriptor featureDescriptors];
    self.helperLabel.text = isDispersion ? @"横向滑动选色散。" : @"横向滑动选特效，长按单个特效进入微调。";

    for (RhythmEffectDescriptor *descriptor in self.currentDescriptors) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = descriptor.rawValue;
        button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
        button.layer.cornerRadius = 16.0;
        button.layer.borderWidth = 1.0;
        button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.08].CGColor;
        button.titleLabel.numberOfLines = 3;
        button.titleLabel.textAlignment = NSTextAlignmentLeft;
        button.contentEdgeInsets = UIEdgeInsetsMake(12.0, 12.0, 12.0, 12.0);
        NSString *title = [NSString stringWithFormat:@"%@\n%@", descriptor.title, descriptor.summary];
        [button setTitle:title forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        button.contentVerticalAlignment = UIControlContentVerticalAlignmentTop;
        button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        [button addTarget:self action:@selector(handleOptionTapped:) forControlEvents:UIControlEventTouchUpInside];
        if (!isDispersion) {
            UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleOptionLongPress:)];
            press.minimumPressDuration = 0.35;
            [button addGestureRecognizer:press];
        }
        [self.optionScrollView addSubview:button];
        [self.optionButtons addObject:button];
    }

    [self updateSelectionUI];
}

- (void)updateToggleButton {
    NSString *title = self.rhythmEnabled ? @"已启用" : @"未启用";
    self.toggleButton.backgroundColor = self.rhythmEnabled ?
        [UIColor colorWithRed:0.94 green:0.51 blue:0.18 alpha:1.0] :
        [UIColor colorWithWhite:1.0 alpha:0.10];
    [self.toggleButton setTitle:title forState:UIControlStateNormal];
}

- (void)updateSelectionUI {
    NSInteger selectedRawValue = (self.modeControl.selectedSegmentIndex == 0) ? self.selectedDispersionEffect : self.selectedFeatureEffect;
    for (UIButton *button in self.optionButtons) {
        BOOL selected = (button.tag == selectedRawValue);
        button.backgroundColor = selected ?
            [UIColor colorWithRed:0.20 green:0.45 blue:0.84 alpha:0.92] :
            [UIColor colorWithWhite:1.0 alpha:0.06];
        button.layer.borderColor = (selected ?
            [UIColor colorWithWhite:1.0 alpha:0.26] :
            [UIColor colorWithWhite:1.0 alpha:0.08]).CGColor;
    }
    [self updateParameterUI];
    [self setNeedsLayout];
}

- (void)updateParameterUI {
    self.intensitySlider.value = self.transformIntensity;
    self.beatBoostSlider.value = self.transformBeatBoost;
    self.radiusSlider.value = self.transformRadius;
    self.speedSlider.value = self.transformSpeed;

    NSString *effectName = @"特效微调";
    for (RhythmEffectDescriptor *descriptor in [RhythmEffectDescriptor featureDescriptors]) {
        if (descriptor.rawValue == self.selectedFeatureEffect) {
            effectName = descriptor.title;
            break;
        }
    }
    self.parameterTitleLabel.text = effectName;

    NSArray<NSNumber *> *values = @[
        @(self.transformIntensity),
        @(self.transformBeatBoost),
        @(self.transformRadius),
        @(self.transformSpeed),
    ];
    for (NSInteger idx = 0; idx < values.count; idx++) {
        self.parameterValueLabels[idx].text = [NSString stringWithFormat:@"%.2f", values[idx].doubleValue];
    }

    [self updateBeatSyncUI];
}

- (void)updateBeatSyncUI {
    self.beatSyncSwitch.on = self.beatSyncEnabled;
    self.beatSyncRow.backgroundColor = self.beatSyncEnabled ?
        [UIColor colorWithRed:0.94 green:0.51 blue:0.18 alpha:0.15] :
        [UIColor colorWithWhite:1.0 alpha:0.06];
    self.beatSyncLabel.textColor = self.beatSyncEnabled ?
        [UIColor colorWithRed:0.94 green:0.51 blue:0.18 alpha:1.0] :
        [UIColor whiteColor];
}

@end
