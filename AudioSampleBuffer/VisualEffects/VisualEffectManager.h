//
//  VisualEffectManager.h
//  AudioSampleBuffer
//
//  视觉效果统一管理器
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>
#import "VisualEffectType.h"
#import "MetalRenderer.h"
#import "EffectSelectorView.h"

NS_ASSUME_NONNULL_BEGIN

@protocol VisualEffectManagerDelegate <NSObject>
@optional
- (void)visualEffectManager:(id)manager didChangeEffect:(VisualEffectType)effectType;
- (void)visualEffectManager:(id)manager didUpdatePerformance:(NSDictionary *)stats;
- (void)visualEffectManager:(id)manager didEncounterError:(NSError *)error;
@end

/**
 * 视觉效果管理器
 * 统一管理所有视觉效果的显示、切换和配置
 */
@interface VisualEffectManager : NSObject <EffectSelectorDelegate>

@property (nonatomic, weak) id<VisualEffectManagerDelegate> delegate;
@property (nonatomic, assign, readonly) VisualEffectType currentEffectType;
@property (nonatomic, assign, readonly) BOOL isEffectActive;
@property (nonatomic, strong, readonly) UIView *effectContainerView;

/**
 * 初始化管理器
 * @param containerView 效果显示容器
 */
- (instancetype)initWithContainerView:(UIView *)containerView;

/**
 * 设置原有的频谱视图引用（用于在Metal特效时暂停）
 * @param spectrumView 频谱视图
 */
- (void)setOriginalSpectrumView:(UIView *)spectrumView;

/**
 * 显示特效选择界面
 */
- (void)showEffectSelector;

/**
 * 隐藏特效选择界面
 */
- (void)hideEffectSelector;

/**
 * 设置当前特效
 * @param effectType 特效类型
 * @param animated 是否使用动画
 */
- (void)setCurrentEffect:(VisualEffectType)effectType animated:(BOOL)animated;

/**
 * 更新频谱数据
 * @param spectrumData 频谱数据数组
 */
- (void)updateSpectrumData:(NSArray<NSNumber *> *)spectrumData;

/**
 * 开始渲染
 */
- (void)startRendering;

/**
 * 停止渲染
 */
- (void)stopRendering;

/**
 * 暂停渲染
 */
- (void)pauseRendering;

/**
 * 恢复渲染
 */
- (void)resumeRendering;

/**
 * 设置渲染参数
 * @param parameters 参数字典
 */
- (void)setRenderParameters:(NSDictionary *)parameters;

/**
 * 获取当前性能统计
 */
- (NSDictionary *)performanceStatistics;

/**
 * 检查特效是否受支持
 */
- (BOOL)isEffectSupported:(VisualEffectType)effectType;

/**
 * 获取推荐的特效设置
 */
- (NSDictionary *)recommendedSettingsForCurrentDevice;

/**
 * 🎛️ 赛博朋克控制方法
 */
- (void)setCyberpunkEnableClimaxEffect:(BOOL)enable;
- (void)setCyberpunkShowDebugBars:(BOOL)show;
- (BOOL)getCyberpunkEnableClimaxEffect;
- (BOOL)getCyberpunkShowDebugBars;

/**
 * 🎨 赛博朋克频段特效控制方法
 */
- (void)setCyberpunkEnableBassEffect:(BOOL)enable;    // 低音特效（红色）
- (void)setCyberpunkEnableMidEffect:(BOOL)enable;     // 中音特效（绿色）
- (void)setCyberpunkEnableTrebleEffect:(BOOL)enable;  // 高音特效（蓝色）
- (BOOL)getCyberpunkEnableBassEffect;
- (BOOL)getCyberpunkEnableMidEffect;
- (BOOL)getCyberpunkEnableTrebleEffect;

// 便捷属性访问（只读）
@property (nonatomic, strong, readonly, nullable) CyberPunkRenderer *cyberpunkRenderer;

@end

NS_ASSUME_NONNULL_END
