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
#import <AVFoundation/AVFoundation.h>

@interface ViewController ()<CAAnimationDelegate,UITableViewDelegate, UITableViewDataSource, AudioSpectrumPlayerDelegate>
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
@end

@implementation ViewController
- (void)hadEnterBackGround{
    NSLog(@"进入后台");
    enterBackground =  YES;
    
}

- (void)hadEnterForeGround{
    NSLog(@"回到app");
    if (enterBackground == YES)
    {
        [self performAnimation];
    }
    enterBackground =  NO;

}
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:YES];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    

    
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(hadEnterBackGround) name:UIApplicationDidEnterBackgroundNotification object:nil];
    
    
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(hadEnterForeGround) name:UIApplicationDidBecomeActiveNotification object:nil];
    
    self.view.backgroundColor = [UIColor blackColor];
    
    // Use a horizontal gradient
    
    float centerX = self.view.center.x;
    float centerY =self.view.center.y;
    //半径
    float radius = 100;
    // Create colors using hues in +5 increments
    
    //创建贝塞尔路径
    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(centerX, centerY) radius:radius startAngle:(0.2*M_PI) endAngle:1.5f*M_PI clockwise:YES];
//
//    //添加背景圆环
//
    CAShapeLayer *backLayer = [CAShapeLayer layer];
    backLayer.frame = self.view.bounds;
    backLayer.fillColor =  [[UIColor clearColor] CGColor];
    backLayer.strokeColor  = [UIColor colorWithRed:50.0/255.0f green:50.0/255.0f blue:50.0/255.0f alpha:1].CGColor;
    backLayer.lineWidth = 10;
    backLayer.path = [path CGPath];
    backLayer.strokeEnd = 1;
    backLayer.lineCap = @"round";
    [self.view.layer addSublayer:backLayer];
//
//
//
    UIBezierPath *paths = [UIBezierPath bezierPathWithArcCenter:CGPointMake(centerX, centerY) radius:89 startAngle:(0.3*M_PI) endAngle:1.5f*M_PI clockwise:YES];
    backLayers= [CAShapeLayer layer];
    backLayers.frame = self.view.bounds;
    backLayers.fillColor =  [[UIColor clearColor] CGColor];
    backLayers.strokeColor  = [UIColor colorWithRed:arc4random()%255/255.0 green:arc4random()%255/255.0 blue:arc4random()%255/255.0 alpha:1.0].CGColor;
    backLayers.lineWidth = 5;
    backLayers.path = [paths CGPath];
    backLayers.strokeEnd = 1;
    backLayers.lineCap = @"rounds";
    [self.view.layer addSublayer:backLayers];
    
    
    
//    UIBezierPath *pathss = [UIBezierPath bezierPathWithArcCenter:CGPointMake(centerX, centerY) radius:75 startAngle:(0.45*M_PI) endAngle:1.5f*M_PI clockwise:YES];
//    CAShapeLayer *backLayerss = [CAShapeLayer layer];
//    backLayerss.frame = self.view.bounds;
//    backLayerss.fillColor =  [[UIColor clearColor] CGColor];
//    backLayers.strokeColor  = [UIColor colorWithRed:arc4random()%255/255.0 green:arc4random()%255/255.0 blue:arc4random()%255/255.0 alpha:1.0].CGColor;
//    backLayerss.lineWidth = 3;
//    backLayerss.path = [pathss CGPath];
//    backLayerss.strokeEnd = 1;
//    backLayerss.lineCap = @"roundss";
//    [self.view.layer addSublayer:backLayerss];
    
    
    // 创建渐变色图层
    self.gradientLayer             = [CAGradientLayer layer];
    self.gradientLayer.frame       = self.view.bounds;
    self.gradientLayer.position    = self.view.center;
    self.gradientLayer.cornerRadius = 5;
    [self.gradientLayer  setStartPoint:CGPointMake(0.0, 0.5)];
    [self.gradientLayer  setEndPoint:CGPointMake(1.0, 0.5)];
    NSMutableArray *colors = [NSMutableArray array];
    for (NSInteger hue = 0; hue < 360; hue += 1) {
        
        UIColor *color;
        color = [UIColor colorWithHue:1.0 * hue / 360.0
                           saturation:1.0
                           brightness:1.0
                                alpha:1.0];
        [colors addObject:(id)[color CGColor]];
    }
    [self.gradientLayer setMask:backLayer]; //用progressLayer来截取渐变层
//        [self.gradientLayer setMask:backLayers]; //用progressLayer来截取渐变层
    
    [self.gradientLayer setColors:[NSArray arrayWithArray:colors]];
    
    // 添加图层
    
    [self.view.layer addSublayer:self.gradientLayer];
    
    [self performAnimation];
    
    
//
    CABasicAnimation *rotationAnimation2 = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    rotationAnimation2.fromValue = [NSNumber numberWithFloat:0];
    rotationAnimation2.toValue = [NSNumber numberWithFloat:-6.0*M_PI];
    rotationAnimation2.repeatCount = MAXFLOAT;
    rotationAnimation2.duration = 25;
    rotationAnimation2.removedOnCompletion = NO;
    // 显然这比网上的做法：监听UIApplicationDidBecomeActiveNotification在通知里面重新开始动画简单多了
    [backLayer addAnimation:rotationAnimation2 forKey:@"rotationAnimation2"];
//
    CABasicAnimation *rotationAnimation3 = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    rotationAnimation3.fromValue = [NSNumber numberWithFloat:0];
    rotationAnimation3.toValue = [NSNumber numberWithFloat:6.0*M_PI];
    rotationAnimation3.repeatCount = MAXFLOAT;
    rotationAnimation3.duration = 10;
    rotationAnimation3.removedOnCompletion = NO;
    [backLayers addAnimation:rotationAnimation3 forKey:@"rotationAnimation3"];
    


    [self configInit];
    imageView = [[UIImageView alloc]init];
    imageView.frame = CGRectMake(0, 0, 170, 170);
    NSURL *fileUrl = [[NSBundle mainBundle] URLForResource:self.audioArray[index] withExtension:nil];
    imageView.image = [self musicImageWithMusicURL:fileUrl];
    imageView.layer.cornerRadius = imageView.frame.size.height/2.0;
    imageView.clipsToBounds = YES;
    imageView.contentMode =UIViewContentModeScaleAspectFill;
    imageView.center = self.view.center;
    [self.view addSubview:imageView];
    
        CABasicAnimation *rotationAnimation4 = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        rotationAnimation4.fromValue = [NSNumber numberWithFloat:0];
        rotationAnimation4.toValue = [NSNumber numberWithFloat:-6.0*M_PI];
        rotationAnimation4.repeatCount = MAXFLOAT;
        rotationAnimation4.duration = 120;
        rotationAnimation4.removedOnCompletion = NO;
        [imageView.layer addAnimation:rotationAnimation4 forKey:@"rotationAnimation4"];

    
    UIView * bvView = [[UIView alloc]init];
    bvView.frame = CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width,  [UIScreen mainScreen].bounds.size.height);
    [self.view addSubview:bvView];
    
    self.xlayer = [[CALayer alloc]init];
    self.xlayer.frame = CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height);
    [bvView.layer addSublayer:self.xlayer];
    self.leafEmitter= [CAEmitterLayer layer];
    [self.xlayer addSublayer:self.leafEmitter];
    
    self.leafEmitter.emitterPosition = self.view.center;//发射器中心点
    self.leafEmitter.emitterSize = CGSizeMake(self.view.bounds.size.width, self.view.bounds.size.height);//发射器大小，因为emitterShape设置成线性所以高度可以设置成0，
    
    self.leafEmitter.emitterShape = kCAEmitterLayerCuboid;//发射器形状为线性
    self.leafEmitter.emitterMode = kCAEmitterLayerCircle;//从发射器边缘发出
    
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
    
    [self.view addSubview:[self buildTableHeadView]];
    [self  createMusic];

    
    
}

- (void)performAnimation {
    // Move the last color in the array to the front
    // shifting all the other colors.
    CAGradientLayer *layer = (id)self.gradientLayer;
    NSMutableArray *mutables = [[self.gradientLayer colors] mutableCopy];
    id lastColor = [mutables lastObject];
    [mutables removeLastObject];
    [mutables insertObject:lastColor atIndex:0];
    NSArray *shiftedColors = [NSArray arrayWithArray:mutables];
    // Update the colors on the model layer
    [layer setColors:shiftedColors];
    
    // Create an animation to slowly move the gradient left to right.
    CABasicAnimation *animation;
    animation = [CABasicAnimation animationWithKeyPath:@"colors"];
    [animation setToValue:shiftedColors];
    [animation setDuration:0.01];
    [animation setRemovedOnCompletion:YES];
    [animation setFillMode:kCAFillModeForwards];
    [animation setDelegate:self];
    [layer addAnimation:animation forKey:@"animateGradient"];
    
    
    
}

- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)flag {
    if (enterBackground == YES)
       {
           return;
       }
    [self performAnimation];
}

- (void)createMusic {
    [self configInit];
    [self buildUI];
}
- (void)configInit {
    self.title = @"播放";
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
}

- (UIView *)buildTableHeadView {
    self.spectrumView = [[SpectrumView alloc] initWithFrame:CGRectMake(0, 25, self.view.frame.size.width, self.view.frame.size.height)];
    self.spectrumView.backgroundColor = [UIColor clearColor];
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
    index=indexPath.row;
    [self setImageAudio];
    [self.player playWithFileName:self.audioArray[indexPath.row]];
    backLayers.strokeColor  = [UIColor colorWithRed:arc4random()%255/255.0 green:arc4random()%255/255.0 blue:arc4random()%255/255.0 alpha:1.0].CGColor;
    NSURL *fileUrl = [[NSBundle mainBundle] URLForResource:self.audioArray[index] withExtension:nil];
    imageView.image =[self musicImageWithMusicURL:fileUrl];

}
#pragma mark - AudioSpectrumPlayerDelegate
- (void)playerDidGenerateSpectrum:(nonnull NSArray *)spectrums {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplicationState state = [UIApplication sharedApplication].applicationState;
        if (state == UIApplicationStateBackground){

        }else{
            [self.spectrumView updateSpectra:spectrums withStype:ADSpectraStyleRound];

        }
    });
}
-(void)didFinishPlay
{
    index++;
    if (index> self.audioArray.count)
    {
        index =0;
    }
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



@end
