//
//  ViewController.m
//  AudioSampleBuffer
//
//  Created by gt on 2022/9/7.
//

#import "ViewController.h"
#import "AudioPlayCell.h"
#import "AudioSpectrumPlayer.h"
#import "SpectrumView.h"
#import "TTi.h"
#import "AnimationCoordinator.h"
#import "VisualEffectManager.h"
#import "GalaxyControlPanel.h"
#import <AVFoundation/AVFoundation.h>

@interface ViewController ()<CAAnimationDelegate,UITableViewDelegate, UITableViewDataSource, AudioSpectrumPlayerDelegate, VisualEffectManagerDelegate, GalaxyControlDelegate>
{
    BOOL enterBackground;
    NSInteger index;
    CAShapeLayer *backLayers;
    UIImageView * imageView ;
}
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *audioArray;
@property (nonatomic, strong) AudioSpectrumPlayer *player;
@property (nonatomic, strong) SpectrumView *spectrumView;


@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) NSInteger iu;
@property (nonatomic, assign) UIBezierPath *circlePath;
@property(nonatomic,strong)CALayer * xlayer;
@property(nonatomic,strong)CAEmitterLayer *leafEmitter;

// 新的动画系统
@property (nonatomic, strong) AnimationCoordinator *animationCoordinator;

// 高端视觉效果系统
@property (nonatomic, strong) VisualEffectManager *visualEffectManager;
@property (nonatomic, strong) UIButton *effectSelectorButton;
@property (nonatomic, strong) GalaxyControlPanel *galaxyControlPanel;
@property (nonatomic, strong) UIButton *galaxyControlButton;

// 🎛️ 赛博朋克控制
@property (nonatomic, strong) UIButton *cyberpunkControlButton;
@property (nonatomic, strong) UISwitch *climaxEffectSwitch;
@property (nonatomic, strong) UISwitch *debugBarsSwitch;
@property (nonatomic, strong) UIView *cyberpunkControlPanel;

// 🎨 频段特效开关
@property (nonatomic, strong) UISwitch *bassEffectSwitch;
@property (nonatomic, strong) UISwitch *midEffectSwitch;
@property (nonatomic, strong) UISwitch *trebleEffectSwitch;

@end

@implementation ViewController
- (void)hadEnterBackGround{
    NSLog(@"进入后台");
    enterBackground =  YES;
    [self.animationCoordinator applicationDidEnterBackground];
}

- (void)hadEnterForeGround{
    NSLog(@"回到app");
    enterBackground = NO;
    [self.animationCoordinator applicationDidBecomeActive];
    [self.visualEffectManager resumeRendering];
}

- (void)setupVisualEffectSystem {
    // 创建视觉效果管理器
    self.visualEffectManager = [[VisualEffectManager alloc] initWithContainerView:self.view];
    self.visualEffectManager.delegate = self;
    
    // 设置默认效果
    [self.visualEffectManager setCurrentEffect:VisualEffectTypeNeonGlow animated:NO];
}

- (void)setupEffectControls {
    // 创建特效选择按钮
    self.effectSelectorButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.effectSelectorButton setTitle:@"🎨 特效" forState:UIControlStateNormal];
    [self.effectSelectorButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.effectSelectorButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.effectSelectorButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.3 alpha:0.9];
    self.effectSelectorButton.layer.cornerRadius = 25;
    self.effectSelectorButton.layer.borderWidth = 1.0;
    self.effectSelectorButton.layer.borderColor = [UIColor whiteColor].CGColor;
    self.effectSelectorButton.frame = CGRectMake(20, 50, 80, 50);
    
    // 添加阴影效果，增强可见性
    self.effectSelectorButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.effectSelectorButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.effectSelectorButton.layer.shadowOpacity = 0.8;
    self.effectSelectorButton.layer.shadowRadius = 4;
    
    [self.effectSelectorButton addTarget:self 
                                  action:@selector(effectSelectorButtonTapped:) 
                        forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:self.effectSelectorButton];
    
    // 添加快捷切换按钮
    [self createQuickEffectButtons];
    
    // 确保控制按钮在最上层
    [self bringControlButtonsToFront];
}

- (void)createQuickEffectButtons {
    NSArray *quickEffects = @[
        @{@"title": @"🌈", @"effect": @(VisualEffectTypeNeonGlow)},
        @{@"title": @"🌊", @"effect": @(VisualEffectType3DWaveform)},
        @{@"title": @"💫", @"effect": @(VisualEffectTypeQuantumField)},
        @{@"title": @"🔮", @"effect": @(VisualEffectTypeHolographic)},
        @{@"title": @"⚡", @"effect": @(VisualEffectTypeCyberPunk)},
        @{@"title": @"🌌", @"effect": @(VisualEffectTypeGalaxy)}
    ];
    
    for (NSInteger i = 0; i < quickEffects.count; i++) {
        NSDictionary *effectInfo = quickEffects[i];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        
        [button setTitle:effectInfo[@"title"] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:20];
        button.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.2 alpha:0.9];
        button.layer.cornerRadius = 20;
        button.layer.borderWidth = 1.0;
        button.layer.borderColor = [UIColor whiteColor].CGColor;
        button.tag = [effectInfo[@"effect"] integerValue];
        
        // 添加阴影效果，增强可见性
        button.layer.shadowColor = [UIColor blackColor].CGColor;
        button.layer.shadowOffset = CGSizeMake(0, 2);
        button.layer.shadowOpacity = 0.8;
        button.layer.shadowRadius = 3;
        
        // 计算位置（右侧垂直排列）
        CGFloat buttonSize = 40;
        CGFloat spacing = 10;
        CGFloat startY = 120;
        button.frame = CGRectMake(self.view.bounds.size.width - buttonSize - 20, 
                                 startY + i * (buttonSize + spacing), 
                                 buttonSize, buttonSize);
        
        [button addTarget:self 
                   action:@selector(quickEffectButtonTapped:) 
         forControlEvents:UIControlEventTouchUpInside];
        
        [self.view addSubview:button];
    }
    
    // 添加星系控制按钮
    [self createGalaxyControlButton];
    
    // 🎛️ 添加赛博朋克控制按钮
    [self createCyberpunkControlButton];
}

- (void)createGalaxyControlButton {
    self.galaxyControlButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.galaxyControlButton setTitle:@"🌌⚙️" forState:UIControlStateNormal];
    self.galaxyControlButton.titleLabel.font = [UIFont systemFontOfSize:16];
    self.galaxyControlButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.1 blue:0.3 alpha:0.9];
    self.galaxyControlButton.layer.cornerRadius = 25;
    self.galaxyControlButton.layer.borderWidth = 1.0;
    self.galaxyControlButton.layer.borderColor = [UIColor whiteColor].CGColor;
    self.galaxyControlButton.frame = CGRectMake(110, 50, 80, 50);
    
    // 添加阴影效果，增强可见性
    self.galaxyControlButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.galaxyControlButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.galaxyControlButton.layer.shadowOpacity = 0.8;
    self.galaxyControlButton.layer.shadowRadius = 4;
    
    [self.galaxyControlButton addTarget:self 
                                 action:@selector(galaxyControlButtonTapped:) 
                       forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:self.galaxyControlButton];
}

// 🎛️ 创建赛博朋克控制按钮
- (void)createCyberpunkControlButton {
    self.cyberpunkControlButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.cyberpunkControlButton setTitle:@"⚡⚙️" forState:UIControlStateNormal];
    self.cyberpunkControlButton.titleLabel.font = [UIFont systemFontOfSize:16];
    self.cyberpunkControlButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.8 alpha:0.9];
    self.cyberpunkControlButton.layer.cornerRadius = 25;
    self.cyberpunkControlButton.layer.borderWidth = 1.0;
    self.cyberpunkControlButton.layer.borderColor = [UIColor whiteColor].CGColor;
    self.cyberpunkControlButton.frame = CGRectMake(200, 50, 80, 50);
    
    // 添加阴影效果，增强可见性
    self.cyberpunkControlButton.layer.shadowColor = [UIColor cyanColor].CGColor;
    self.cyberpunkControlButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.cyberpunkControlButton.layer.shadowOpacity = 0.8;
    self.cyberpunkControlButton.layer.shadowRadius = 4;
    
    [self.cyberpunkControlButton addTarget:self 
                                    action:@selector(cyberpunkControlButtonTapped:) 
                          forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:self.cyberpunkControlButton];
}

- (void)bringControlButtonsToFront {
    // 将所有控制按钮提到最前面
    [self.view bringSubviewToFront:self.effectSelectorButton];
    [self.view bringSubviewToFront:self.galaxyControlButton];
    [self.view bringSubviewToFront:self.cyberpunkControlButton];
    
    // 将所有快捷按钮也提到前面
    for (UIView *subview in self.view.subviews) {
        if ([subview isKindOfClass:[UIButton class]] && 
            subview != self.effectSelectorButton && 
            subview != self.galaxyControlButton &&
            subview != self.cyberpunkControlButton &&
            subview.tag >= 0 && subview.tag < VisualEffectTypeCount) {
            [self.view bringSubviewToFront:subview];
        }
    }
}
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:YES];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 初始化动画协调器
    self.animationCoordinator = [[AnimationCoordinator alloc] initWithContainerView:self.view];
    
    // 初始化高端视觉效果系统
    [self setupVisualEffectSystem];
    
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(hadEnterBackGround) name:UIApplicationDidEnterBackgroundNotification object:nil];
    
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(hadEnterForeGround) name:UIApplicationDidBecomeActiveNotification object:nil];
    
    self.view.backgroundColor = [UIColor blackColor];
    
    [self setupBackgroundLayers];
    [self setupImageView];
    [self setupParticleSystem];
    [self configInit];
    [self createMusic];
    
    // 启动所有动画
    [self.animationCoordinator startAllAnimations];
    
    // 最后创建控制按钮，确保在最上层
    [self setupEffectControls];
}

- (void)setupBackgroundLayers {
    // 移除音乐封面周围的圆弧，保持界面简洁
    // 原来的圆环代码已被注释掉
    
    /*
    float centerX = self.view.center.x;
    float centerY = self.view.center.y;
    
    // 创建背景圆环 - 已移除
    CAShapeLayer *backLayer = [self createBackgroundRingWithCenter:CGPointMake(centerX, centerY) 
                                                            radius:100 
                                                         lineWidth:10 
                                                        startAngle:0.2*M_PI 
                                                          endAngle:1.5*M_PI];
    
    backLayers = [self createBackgroundRingWithCenter:CGPointMake(centerX, centerY) 
                                               radius:89 
                                            lineWidth:5 
                                           startAngle:0.3*M_PI 
                                             endAngle:1.5*M_PI];
    backLayers.strokeColor = [UIColor colorWithRed:arc4random()%255/255.0 
                                             green:arc4random()%255/255.0 
                                              blue:arc4random()%255/255.0 
                                             alpha:1.0].CGColor;
    
    // 创建渐变色图层
    [self setupGradientLayerWithMask:backLayer];
    
    // 为背景图层添加旋转动画
    [self.animationCoordinator.rotationManager addRotationAnimationToLayer:backLayer 
                                                              withRotations:6.0 
                                                                   duration:25.0 
                                                               rotationType:RotationTypeCounterClockwise];
    
    [self.animationCoordinator.rotationManager addRotationAnimationToLayer:backLayers 
                                                              withRotations:6.0 
                                                                   duration:10.0 
                                                               rotationType:RotationTypeClockwise];
    */
    
    NSLog(@"🎵 音乐封面周围的圆弧已被移除，界面更加简洁");
}

- (CAShapeLayer *)createBackgroundRingWithCenter:(CGPoint)center 
                                           radius:(CGFloat)radius 
                                        lineWidth:(CGFloat)lineWidth 
                                       startAngle:(CGFloat)startAngle 
                                         endAngle:(CGFloat)endAngle {
    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:center 
                                                        radius:radius 
                                                    startAngle:startAngle 
                                                      endAngle:endAngle 
                                                     clockwise:YES];
    
    CAShapeLayer *layer = [CAShapeLayer layer];
    layer.frame = self.view.bounds;
    layer.fillColor = [[UIColor clearColor] CGColor];
    layer.strokeColor = [UIColor colorWithRed:50.0/255.0f green:50.0/255.0f blue:50.0/255.0f alpha:1].CGColor;
    layer.lineWidth = lineWidth;
    layer.path = [path CGPath];
    layer.strokeEnd = 1;
    layer.lineCap = @"round";
    
    [self.view.layer addSublayer:layer];
    return layer;
}

- (void)setupGradientLayerWithMask:(CAShapeLayer *)maskLayer {
    self.gradientLayer = [CAGradientLayer layer];
    self.gradientLayer.frame = self.view.bounds;
    self.gradientLayer.position = self.view.center;
    self.gradientLayer.cornerRadius = 5;
    [self.gradientLayer setStartPoint:CGPointMake(0.0, 0.5)];
    [self.gradientLayer setEndPoint:CGPointMake(1.0, 0.5)];
    [self.gradientLayer setMask:maskLayer];
    
    [self.view.layer addSublayer:self.gradientLayer];
    
    // 设置渐变动画管理器
    [self.animationCoordinator setupGradientLayer:self.gradientLayer];
    


}

- (void)setupImageView {
    [self configInit];
    
    imageView = [[UIImageView alloc]init];
    imageView.frame = CGRectMake(0, 0, 170, 170);
    NSURL *fileUrl = [[NSBundle mainBundle] URLForResource:self.audioArray[index] withExtension:nil];
    imageView.image = [self musicImageWithMusicURL:fileUrl];
    imageView.layer.cornerRadius = imageView.frame.size.height/2.0;
    imageView.clipsToBounds = YES;
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    imageView.center = self.view.center;
    [self.view addSubview:imageView];
    
    // 使用动画管理器添加旋转动画
    [self.animationCoordinator addRotationViews:@[imageView] 
                                      rotations:@[@(6.0)] 
                                      durations:@[@(120.0)] 
                                  rotationTypes:@[@(RotationTypeCounterClockwise)]];

    
    [self.view addSubview:[self buildTableHeadView]];
    
    // 确保控制按钮在tableView之上
    [self bringControlButtonsToFront];
}

- (void)setupParticleSystem {
    // 创建粒子容器
    UIView *bvView = [[UIView alloc] init];
    bvView.frame = CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height);
    [self.view addSubview:bvView];
    
    self.xlayer = [[CALayer alloc] init];
    self.xlayer.frame = CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height);
    [bvView.layer addSublayer:self.xlayer];
    
    // 设置粒子动画管理器
    [self.animationCoordinator setupParticleContainerLayer:self.xlayer];
    [self.animationCoordinator.particleManager setEmitterPosition:self.view.center];
    [self.animationCoordinator.particleManager setEmitterSize:self.view.bounds.size];
    
    // 设置当前音频的粒子图像
    if (self.audioArray.count > 0) {
        NSURL *fileUrl = [[NSBundle mainBundle] URLForResource:self.audioArray[index] withExtension:nil];
        UIImage *image = [self musicImageWithMusicURL:fileUrl];
        if (image) {
            [self.animationCoordinator updateParticleImage:image];
        }
    }

    
    
}

// 这些方法现在由GradientAnimationManager处理，保留空实现以防其他地方调用
- (void)performAnimation {
    // 已移至GradientAnimationManager
}

- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)flag {
    // 已移至GradientAnimationManager
}

- (void)createMusic {
    [self configInit];
    [self buildUI];
}
- (void)configInit {
    self.title = @"播放";
    
    // 如果数组已经有数据，说明已经初始化过了，直接返回
    if (self.audioArray.count > 0) {
        return;
    }
    
    NSArray *pathArray = [[NSBundle mainBundle] pathsForResourcesOfType:@"mp3" inDirectory:nil];
    for (int i = 0; i < pathArray.count; i ++) {
        NSString *audioName = [[pathArray[i] componentsSeparatedByString:@"/"] lastObject];
        [self.audioArray addObject:audioName];
    }
}

- (void)buildUI {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 64, self.view.frame.size.width, self.view.frame.size.height - 64) style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.tableHeaderView = [[UIView alloc]initWithFrame:CGRectMake(0, 100, self.view.frame.size.width, self.view.frame.size.height)];
    self.tableView.tableFooterView = [UIView new];
    self.tableView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.tableView];
    
    // 确保控制按钮在tableView之上
    [self bringControlButtonsToFront];
}

- (UIView *)buildTableHeadView {
    self.spectrumView = [[SpectrumView alloc] initWithFrame:CGRectMake(0, 25, self.view.frame.size.width, self.view.frame.size.height)];
    self.spectrumView.backgroundColor = [UIColor clearColor];
    
    // 设置频谱视图到视觉效果管理器，用于在Metal特效时暂停
    [self.visualEffectManager setOriginalSpectrumView:self.spectrumView];
    
    return self.spectrumView;
}

#pragma mark - UITableView
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.audioArray.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 60;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    AudioPlayCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cellID"];
    if (!cell) {
        cell = [[AudioPlayCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cellID"];
    }
    cell.nameLabel.text = self.audioArray[indexPath.row];
    cell.playBtn.hidden = YES;
    cell.playBlock = ^(BOOL isPlaying) {
        if (isPlaying) {
            [self.player stop];
        } else {
            [self.player playWithFileName:self.audioArray[indexPath.row]];
        }
    };
    
    return cell;
}
-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    index = indexPath.row;
    [self updateAudioSelection];
    [self.player playWithFileName:self.audioArray[indexPath.row]];
}

- (void)updateAudioSelection {
    // 更新背景圆环颜色
    if (backLayers) {
        backLayers.strokeColor = [UIColor colorWithRed:arc4random()%255/255.0 
                                                 green:arc4random()%255/255.0 
                                                  blue:arc4random()%255/255.0 
                                                 alpha:1.0].CGColor;
    }
    
    // 更新封面图像
    NSURL *fileUrl = [[NSBundle mainBundle] URLForResource:self.audioArray[index] withExtension:nil];
    UIImage *image = [self musicImageWithMusicURL:fileUrl];
    if (image) {
        imageView.image = image;
        // 更新粒子图像
        [self.animationCoordinator updateParticleImage:image];
    }
}
#pragma mark - AudioSpectrumPlayerDelegate
- (void)playerDidGenerateSpectrum:(nonnull NSArray *)spectrums {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplicationState state = [UIApplication sharedApplication].applicationState;
        if (state == UIApplicationStateBackground){
            return;
        }
        
        // 更新频谱视图
        [self.spectrumView updateSpectra:spectrums withStype:ADSpectraStyleRound];
        
        // 更新频谱动画（如果需要的话）
        if (self.animationCoordinator.spectrumManager) {
            [self.animationCoordinator updateSpectrumAnimations:spectrums];
        }
        
        // 更新高端视觉效果
        if (spectrums.count > 0) {
            NSArray *firstChannelData = spectrums.firstObject;
            [self.visualEffectManager updateSpectrumData:firstChannelData];
        }
    });
}
-(void)didFinishPlay
{
    index++;
    if (index >= self.audioArray.count)
    {
        index = 0;
    }
    [self updateAudioSelection];
    [self.player playWithFileName:self.audioArray[index]];
}
- (NSMutableArray *)audioArray {
    if (!_audioArray) {
        _audioArray = [NSMutableArray new];
    }
    return _audioArray;
}

- (AudioSpectrumPlayer *)player {
    if (!_player) {
        _player = [[AudioSpectrumPlayer alloc] init];
        _player.delegate = self;
    }
    return _player;
}
#pragma mark- 文件处理
- (UIImage*)musicImageWithMusicURL:(NSURL*)url {
    
    NSData*data =nil;
    
    // 初始化媒体文件
    
    AVURLAsset*mp3Asset = [AVURLAsset URLAssetWithURL:url options:nil];

    // 读取文件中的数据
    
    for(NSString*format in [mp3Asset availableMetadataFormats]) {
        
        for(AVMetadataItem*metadataItem in[mp3Asset metadataForFormat:format]) {
            //artwork这个key对应的value里面存的就是封面缩略图，其它key可以取出其它摘要信息，例如title - 标题
            
            if([metadataItem.commonKey isEqualToString:@"artwork"]) {
                
                data = [metadataItem.value copyWithZone:nil];
                
                break;
            }
        }
    }
    if(!data) {
        // 如果音乐没有图片，就返回默认图片
        return nil;//[UIImage imageNamed:@"default"];
        
    }
    
    return[UIImage imageWithData:data];
    
}

-(void)setImageAudio
{
    NSMutableArray *array = [NSMutableArray array];//CAEmitterCell数组，存放不同的CAEmitterCell，我这里准备了四张不同形态的叶子图片。
    for (int i = 1; i<9; i++) {
        //            NSString *imageName = [NSString stringWithFormat:@"WechatIMG3－%d",i];
        
        CAEmitterCell *leafCell = [CAEmitterCell emitterCell];
        leafCell.birthRate = 0.5;//粒子产生速度
        leafCell.lifetime =10;//粒子存活时间r
        
        leafCell.velocity = 1;//初始速度
        leafCell.velocityRange = 5;//初始速度的差值区间，所以初始速度为5~15，后面属性range算法相同
        
        leafCell.yAcceleration = 20;//y轴方向的加速度，落叶下飘只需要y轴正向加速度。
        leafCell.zAcceleration = 20;//y轴方向的加速度，落叶下飘只需要y轴正向加速度。
        
        leafCell.spin = 0.25;//粒子旋转速度
        leafCell.spinRange = 5;//粒子旋转速度范围
        
        leafCell.emissionRange = M_PI;//粒子发射角度范围
        
        //        leafCell.contents = (id)[[UIImage imageNamed:imageName] CGImage];//粒子图片
        NSURL *fileUrl = [[NSBundle mainBundle] URLForResource:self.audioArray[index] withExtension:nil];
        leafCell.contents = (id)[[self musicImageWithMusicURL:fileUrl] CGImage];//粒子图片
        leafCell.color = [UIColor whiteColor].CGColor;
        leafCell.scale = 0.03;//缩放比例
        leafCell.scaleRange = 0.03;//缩放比例
        
        leafCell.alphaSpeed = -0.22;
        leafCell.alphaRange = -0.8;
        
        [array addObject:leafCell];
    }
    
    self.leafEmitter.emitterCells = array;//设置粒子组
}

#pragma mark - 特效控制按钮事件

- (void)effectSelectorButtonTapped:(UIButton *)sender {
    [self.visualEffectManager showEffectSelector];
}

- (void)galaxyControlButtonTapped:(UIButton *)sender {
    if (!self.galaxyControlPanel) {
        self.galaxyControlPanel = [[GalaxyControlPanel alloc] initWithFrame:CGRectMake(20, 100, 
                                                                                       self.view.bounds.size.width - 40, 
                                                                                       self.view.bounds.size.height - 200)];
        self.galaxyControlPanel.delegate = self;
        [self.view addSubview:self.galaxyControlPanel];
    }
    
    [self.galaxyControlPanel showAnimated:YES];
}

// 🎛️ 赛博朋克控制按钮点击
- (void)cyberpunkControlButtonTapped:(UIButton *)sender {
    if (!self.cyberpunkControlPanel) {
        [self createCyberpunkControlPanel];
    }
    
    // 切换显示/隐藏
    if (self.cyberpunkControlPanel.alpha == 0) {
        [self showCyberpunkControlPanel];
    } else {
        [self hideCyberpunkControlPanel];
    }
}

// 创建赛博朋克控制面板
- (void)createCyberpunkControlPanel {
    CGFloat panelWidth = 280;
    CGFloat panelHeight = 380;  // 增加高度以容纳5个开关
    CGFloat padding = 20;
    
    self.cyberpunkControlPanel = [[UIView alloc] initWithFrame:CGRectMake(
        self.view.bounds.size.width - panelWidth - padding,
        120,
        panelWidth,
        panelHeight
    )];
    
    self.cyberpunkControlPanel.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.15 alpha:0.95];
    self.cyberpunkControlPanel.layer.cornerRadius = 15;
    self.cyberpunkControlPanel.layer.borderWidth = 2;
    self.cyberpunkControlPanel.layer.borderColor = [UIColor cyanColor].CGColor;
    self.cyberpunkControlPanel.layer.shadowColor = [UIColor cyanColor].CGColor;
    self.cyberpunkControlPanel.layer.shadowOffset = CGSizeMake(0, 0);
    self.cyberpunkControlPanel.layer.shadowRadius = 10;
    self.cyberpunkControlPanel.layer.shadowOpacity = 0.6;
    self.cyberpunkControlPanel.alpha = 0;
    
    CGFloat currentY = 15;
    CGFloat rowHeight = 50;
    
    // 标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, currentY, panelWidth, 30)];
    titleLabel.text = @"⚡ 赛博朋克控制";
    titleLabel.textColor = [UIColor cyanColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.cyberpunkControlPanel addSubview:titleLabel];
    currentY += 45;
    
    // 🎨 频段特效分组标题
    UILabel *frequencyLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, currentY, panelWidth - 40, 25)];
    frequencyLabel.text = @"🎨 频段特效";
    frequencyLabel.textColor = [UIColor colorWithRed:0.5 green:0.9 blue:0.9 alpha:1.0];
    frequencyLabel.font = [UIFont boldSystemFontOfSize:14];
    [self.cyberpunkControlPanel addSubview:frequencyLabel];
    currentY += 30;
    
    // 低音特效开关（红色）
    UILabel *bassLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, currentY, 160, 30)];
    bassLabel.text = @"🔴 低音特效";
    bassLabel.textColor = [UIColor whiteColor];
    bassLabel.font = [UIFont systemFontOfSize:15];
    [self.cyberpunkControlPanel addSubview:bassLabel];
    
    self.bassEffectSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(panelWidth - 70, currentY, 51, 31)];
    self.bassEffectSwitch.on = [self.visualEffectManager getCyberpunkEnableBassEffect];
    self.bassEffectSwitch.onTintColor = [UIColor redColor];
    [self.bassEffectSwitch addTarget:self 
                              action:@selector(bassEffectSwitchChanged:) 
                    forControlEvents:UIControlEventValueChanged];
    [self.cyberpunkControlPanel addSubview:self.bassEffectSwitch];
    currentY += rowHeight;
    
    // 中音特效开关（绿色）
    UILabel *midLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, currentY, 160, 30)];
    midLabel.text = @"🟢 中音特效";
    midLabel.textColor = [UIColor whiteColor];
    midLabel.font = [UIFont systemFontOfSize:15];
    [self.cyberpunkControlPanel addSubview:midLabel];
    
    self.midEffectSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(panelWidth - 70, currentY, 51, 31)];
    self.midEffectSwitch.on = [self.visualEffectManager getCyberpunkEnableMidEffect];
    self.midEffectSwitch.onTintColor = [UIColor greenColor];
    [self.midEffectSwitch addTarget:self 
                             action:@selector(midEffectSwitchChanged:) 
                   forControlEvents:UIControlEventValueChanged];
    [self.cyberpunkControlPanel addSubview:self.midEffectSwitch];
    currentY += rowHeight;
    
    // 高音特效开关（蓝色）
    UILabel *trebleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, currentY, 160, 30)];
    trebleLabel.text = @"🔵 高音特效";
    trebleLabel.textColor = [UIColor whiteColor];
    trebleLabel.font = [UIFont systemFontOfSize:15];
    [self.cyberpunkControlPanel addSubview:trebleLabel];
    
    self.trebleEffectSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(panelWidth - 70, currentY, 51, 31)];
    self.trebleEffectSwitch.on = [self.visualEffectManager getCyberpunkEnableTrebleEffect];
    self.trebleEffectSwitch.onTintColor = [UIColor blueColor];
    [self.trebleEffectSwitch addTarget:self 
                                action:@selector(trebleEffectSwitchChanged:) 
                      forControlEvents:UIControlEventValueChanged];
    [self.cyberpunkControlPanel addSubview:self.trebleEffectSwitch];
    currentY += rowHeight + 10;
    
    // 分隔线
    UIView *separatorLine = [[UIView alloc] initWithFrame:CGRectMake(20, currentY, panelWidth - 40, 1)];
    separatorLine.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5];
    [self.cyberpunkControlPanel addSubview:separatorLine];
    currentY += 15;
    
    // 🎛️ 其他控制分组标题
    UILabel *otherLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, currentY, panelWidth - 40, 25)];
    otherLabel.text = @"🎛️ 其他控制";
    otherLabel.textColor = [UIColor colorWithRed:0.5 green:0.9 blue:0.9 alpha:1.0];
    otherLabel.font = [UIFont boldSystemFontOfSize:14];
    [self.cyberpunkControlPanel addSubview:otherLabel];
    currentY += 30;
    
    // 高能效果开关（黄色）
    UILabel *climaxLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, currentY, 160, 30)];
    climaxLabel.text = @"🟨 高能效果";
    climaxLabel.textColor = [UIColor whiteColor];
    climaxLabel.font = [UIFont systemFontOfSize:15];
    [self.cyberpunkControlPanel addSubview:climaxLabel];
    
    self.climaxEffectSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(panelWidth - 70, currentY, 51, 31)];
    self.climaxEffectSwitch.on = [self.visualEffectManager getCyberpunkEnableClimaxEffect];
    self.climaxEffectSwitch.onTintColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    [self.climaxEffectSwitch addTarget:self 
                                action:@selector(climaxEffectSwitchChanged:) 
                      forControlEvents:UIControlEventValueChanged];
    [self.cyberpunkControlPanel addSubview:self.climaxEffectSwitch];
    currentY += rowHeight;
    
    // 调试条开关
    UILabel *debugLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, currentY, 160, 30)];
    debugLabel.text = @"🎯 调试强度条";
    debugLabel.textColor = [UIColor whiteColor];
    debugLabel.font = [UIFont systemFontOfSize:15];
    [self.cyberpunkControlPanel addSubview:debugLabel];
    
    self.debugBarsSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(panelWidth - 70, currentY, 51, 31)];
    self.debugBarsSwitch.on = [self.visualEffectManager getCyberpunkShowDebugBars];
    self.debugBarsSwitch.onTintColor = [UIColor cyanColor];
    [self.debugBarsSwitch addTarget:self 
                             action:@selector(debugBarsSwitchChanged:) 
                   forControlEvents:UIControlEventValueChanged];
    [self.cyberpunkControlPanel addSubview:self.debugBarsSwitch];
    
    // 关闭按钮
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [closeButton setTitle:@"✕" forState:UIControlStateNormal];
    closeButton.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    closeButton.frame = CGRectMake(panelWidth - 40, 10, 30, 30);
    [closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [closeButton addTarget:self 
                    action:@selector(hideCyberpunkControlPanel) 
          forControlEvents:UIControlEventTouchUpInside];
    [self.cyberpunkControlPanel addSubview:closeButton];
    
    [self.view addSubview:self.cyberpunkControlPanel];
}

// 显示赛博朋克控制面板
- (void)showCyberpunkControlPanel {
    [UIView animateWithDuration:0.3 animations:^{
        self.cyberpunkControlPanel.alpha = 1.0;
    }];
    [self.view bringSubviewToFront:self.cyberpunkControlPanel];
}

// 隐藏赛博朋克控制面板
- (void)hideCyberpunkControlPanel {
    [UIView animateWithDuration:0.3 animations:^{
        self.cyberpunkControlPanel.alpha = 0;
    }];
}

// 高能效果开关变化
- (void)climaxEffectSwitchChanged:(UISwitch *)sender {
    [self.visualEffectManager setCyberpunkEnableClimaxEffect:sender.on];
    
    // 视觉反馈
    [UIView animateWithDuration:0.2 animations:^{
        self.cyberpunkControlButton.transform = CGAffineTransformMakeScale(1.1, 1.1);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2 animations:^{
            self.cyberpunkControlButton.transform = CGAffineTransformIdentity;
        }];
    }];
}

// 调试条开关变化
- (void)debugBarsSwitchChanged:(UISwitch *)sender {
    [self.visualEffectManager setCyberpunkShowDebugBars:sender.on];
    
    // 视觉反馈
    [UIView animateWithDuration:0.2 animations:^{
        self.cyberpunkControlButton.transform = CGAffineTransformMakeScale(1.1, 1.1);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2 animations:^{
            self.cyberpunkControlButton.transform = CGAffineTransformIdentity;
        }];
    }];
}

// 🎨 低音特效开关变化（红色）
- (void)bassEffectSwitchChanged:(UISwitch *)sender {
    [self.visualEffectManager setCyberpunkEnableBassEffect:sender.on];
    
    // 视觉反馈
    [UIView animateWithDuration:0.2 animations:^{
        self.cyberpunkControlButton.transform = CGAffineTransformMakeScale(1.1, 1.1);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2 animations:^{
            self.cyberpunkControlButton.transform = CGAffineTransformIdentity;
        }];
    }];
}

// 🎨 中音特效开关变化（绿色）
- (void)midEffectSwitchChanged:(UISwitch *)sender {
    [self.visualEffectManager setCyberpunkEnableMidEffect:sender.on];
    
    // 视觉反馈
    [UIView animateWithDuration:0.2 animations:^{
        self.cyberpunkControlButton.transform = CGAffineTransformMakeScale(1.1, 1.1);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2 animations:^{
            self.cyberpunkControlButton.transform = CGAffineTransformIdentity;
        }];
    }];
}

// 🎨 高音特效开关变化（蓝色）
- (void)trebleEffectSwitchChanged:(UISwitch *)sender {
    [self.visualEffectManager setCyberpunkEnableTrebleEffect:sender.on];
    
    // 视觉反馈
    [UIView animateWithDuration:0.2 animations:^{
        self.cyberpunkControlButton.transform = CGAffineTransformMakeScale(1.1, 1.1);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2 animations:^{
            self.cyberpunkControlButton.transform = CGAffineTransformIdentity;
        }];
    }];
}

- (void)quickEffectButtonTapped:(UIButton *)sender {
    VisualEffectType effectType = (VisualEffectType)sender.tag;
    
    // 检查设备是否支持该特效
    if ([self.visualEffectManager isEffectSupported:effectType]) {
        [self.visualEffectManager setCurrentEffect:effectType animated:YES];
        
        // 视觉反馈
        [UIView animateWithDuration:0.2 animations:^{
            sender.transform = CGAffineTransformMakeScale(1.2, 1.2);
            sender.backgroundColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.5 alpha:0.9];
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.2 animations:^{
                sender.transform = CGAffineTransformIdentity;
                sender.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.2 alpha:0.7];
            }];
        }];
    } else {
        // 不支持的特效，显示提示
        [self showUnsupportedEffectAlert];
    }
}

- (void)showUnsupportedEffectAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"特效不支持" 
                                                                   message:@"该特效需要更高性能的设备支持" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" 
                                                       style:UIAlertActionStyleDefault 
                                                     handler:nil];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - VisualEffectManagerDelegate

- (void)visualEffectManager:(VisualEffectManager *)manager didChangeEffect:(VisualEffectType)effectType {
    NSLog(@"🎨 特效已切换: %lu", (unsigned long)effectType);
    
    // 开始渲染新特效
    [manager startRendering];
    
    // 更新UI状态
    [self updateEffectButtonStates:effectType];
}

- (void)visualEffectManager:(VisualEffectManager *)manager didUpdatePerformance:(NSDictionary *)stats {
    NSNumber *fps = stats[@"fps"];
    if (fps && [fps doubleValue] < 20.0) {
        NSLog(@"⚠️ 性能警告: FPS过低 (%.1f)", [fps doubleValue]);
    }
}

- (void)visualEffectManager:(VisualEffectManager *)manager didEncounterError:(NSError *)error {
    NSLog(@"❌ 视觉效果错误: %@", error.localizedDescription);
}

- (void)updateEffectButtonStates:(VisualEffectType)currentEffect {
    // 更新快捷按钮的选中状态
    for (UIView *subview in self.view.subviews) {
        if ([subview isKindOfClass:[UIButton class]] && subview.tag >= 0 && subview.tag < VisualEffectTypeCount) {
            UIButton *button = (UIButton *)subview;
            if (button.tag == currentEffect) {
                button.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.8];
            } else {
                button.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.2 alpha:0.7];
            }
        }
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - GalaxyControlDelegate

- (void)galaxyControlDidUpdateSettings:(NSDictionary *)settings {
    NSLog(@"🌌 星系设置更新: %@", settings);
    
    // 应用新的星系设置
    [self.visualEffectManager setRenderParameters:settings];
    
    // 如果当前不是星系效果，自动切换到星系效果
    if (self.visualEffectManager.currentEffectType != VisualEffectTypeGalaxy) {
        [self.visualEffectManager setCurrentEffect:VisualEffectTypeGalaxy animated:YES];
        [self updateEffectButtonStates:VisualEffectTypeGalaxy];
    }
}

@end
