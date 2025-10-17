//
//  ProxyManager.h
//  AudioSampleBuffer
//
//  代理管理器 - 用于访问受限的音乐平台 API
//  参考：https://github.com/0xHJK/Proxies
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 代理类型
 */
typedef NS_ENUM(NSInteger, ProxyType) {
    ProxyTypeHTTP = 0,      // HTTP 代理
    ProxyTypeHTTPS = 1,     // HTTPS 代理
    ProxyTypeSOCKS5 = 2,    // SOCKS5 代理
};

/**
 * 代理信息
 */
@interface ProxyInfo : NSObject

@property (nonatomic, copy) NSString *host;           // 代理服务器地址
@property (nonatomic, assign) NSInteger port;         // 端口
@property (nonatomic, assign) ProxyType type;         // 代理类型
@property (nonatomic, copy, nullable) NSString *username;  // 用户名（可选）
@property (nonatomic, copy, nullable) NSString *password;  // 密码（可选）

- (NSDictionary *)proxyDictionary;  // 转换为 NSURLSession 使用的字典

@end

/**
 * 代理管理器
 */
@interface ProxyManager : NSObject

+ (instancetype)sharedManager;

/**
 * 设置代理
 */
- (void)setProxy:(nullable ProxyInfo *)proxy;

/**
 * 获取当前代理
 */
- (nullable ProxyInfo *)currentProxy;

/**
 * 清除代理
 */
- (void)clearProxy;

/**
 * 创建配置了代理的 NSURLSession
 */
- (NSURLSession *)createSessionWithProxy;

/**
 * 测试代理是否可用
 */
- (void)testProxyConnectivity:(ProxyInfo *)proxy
                   completion:(void(^)(BOOL success, NSTimeInterval responseTime))completion;

@end

NS_ASSUME_NONNULL_END
