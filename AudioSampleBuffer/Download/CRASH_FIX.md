# 🐛 崩溃修复：类型安全问题

## ❌ 崩溃原因

### 错误信息
```
*** Terminating app due to uncaught exception 'NSInvalidArgumentException', 
reason: '-[__NSCFNumber isEqualToString:]: unrecognized selector sent to instance'
```

### 问题分析

**根本原因：** JSON 解析后的值类型不确定

在 Objective-C 中，`NSJSONSerialization` 解析 JSON 时：
- 字符串 → `NSString`
- 数字 → `NSNumber`
- 数组 → `NSArray`
- 对象 → `NSDictionary`

但是酷狗音乐 API 返回的某些字段（如 `album_audio_id`）有时是字符串，有时是数字，导致：

```objective-c
// ❌ 错误代码（假设一定是 NSString）
NSString *albumAudioId = json[@"album_audio_id"];
if ([albumAudioId isEqualToString:@"0"]) {  // 如果是 NSNumber 就会崩溃！
    // ...
}
```

## ✅ 修复方案

### 1. 安全的类型检查和转换

**修复前：**
```objective-c
NSString *albumAudioId = json[@"album_audio_id"];
if (!albumAudioId || [albumAudioId isEqualToString:@"0"]) {
    // ...
}
```

**修复后：**
```objective-c
id albumAudioIdObj = json[@"album_audio_id"];
NSString *albumAudioId = nil;

// 处理可能是 NSNumber 或 NSString 的情况
if ([albumAudioIdObj isKindOfClass:[NSString class]]) {
    albumAudioId = (NSString *)albumAudioIdObj;
} else if ([albumAudioIdObj isKindOfClass:[NSNumber class]]) {
    albumAudioId = [(NSNumber *)albumAudioIdObj stringValue];
}

if (!albumAudioId || [albumAudioId isEqualToString:@"0"] || albumAudioId.length == 0) {
    // ...
}
```

### 2. 修复的所有位置

#### 位置 1：下载链接（方式1）
```objective-c
// json[@"url"] 可能是 NSString 或其他类型
id downloadUrlObj = json[@"url"];
NSString *downloadUrl = nil;

if ([downloadUrlObj isKindOfClass:[NSString class]]) {
    downloadUrl = (NSString *)downloadUrlObj;
}
```

#### 位置 2：album_audio_id
```objective-c
// json[@"album_audio_id"] 可能是 NSNumber 或 NSString
id albumAudioIdObj = json[@"album_audio_id"];
NSString *albumAudioId = nil;

if ([albumAudioIdObj isKindOfClass:[NSString class]]) {
    albumAudioId = (NSString *)albumAudioIdObj;
} else if ([albumAudioIdObj isKindOfClass:[NSNumber class]]) {
    albumAudioId = [(NSNumber *)albumAudioIdObj stringValue];
}
```

#### 位置 3：play_url（方式2）
```objective-c
// json[@"data"][@"play_url"] 类型检查
id playUrlObj = detailJson[@"data"][@"play_url"];
NSString *playUrl = nil;

if ([playUrlObj isKindOfClass:[NSString class]]) {
    playUrl = (NSString *)playUrlObj;
}
```

#### 位置 4：url 数组（方式3）
```objective-c
// json[@"url"] 可能是数组，数组元素也需要检查
NSArray *urlArray = json[@"url"];
if (urlArray && [urlArray isKindOfClass:[NSArray class]] && urlArray.count > 0) {
    id downloadUrlObj = urlArray[0];
    NSString *downloadUrl = nil;
    
    if ([downloadUrlObj isKindOfClass:[NSString class]]) {
        downloadUrl = (NSString *)downloadUrlObj;
    }
    
    if (downloadUrl && downloadUrl.length > 0) {
        // 使用下载链接
    }
}
```

## 🔍 为什么会出现这个问题？

### JSON 返回值的不确定性

酷狗音乐 API 的响应格式不统一：

**情况 1：返回字符串**
```json
{
    "album_audio_id": "12345"
}
```

**情况 2：返回数字**
```json
{
    "album_audio_id": 12345
}
```

**情况 3：返回数字 0**
```json
{
    "album_audio_id": 0
}
```

这种不一致性是第三方 API 常见问题。

## 📋 最佳实践

### 从 JSON 中安全地提取值

```objective-c
// ✅ 安全的方式
id value = json[@"key"];

if ([value isKindOfClass:[NSString class]]) {
    NSString *stringValue = (NSString *)value;
    // 使用字符串值
} else if ([value isKindOfClass:[NSNumber class]]) {
    NSNumber *numberValue = (NSNumber *)value;
    NSString *stringValue = [numberValue stringValue];
    // 转换为字符串使用
} else if ([value isKindOfClass:[NSArray class]]) {
    NSArray *arrayValue = (NSArray *)value;
    // 使用数组值
} else if ([value isKindOfClass:[NSDictionary class]]) {
    NSDictionary *dictValue = (NSDictionary *)value;
    // 使用字典值
} else {
    // 处理意外类型或 nil
    NSLog(@"⚠️ 意外的类型: %@", [value class]);
}
```

### 辅助宏（可选）

如果需要频繁处理，可以创建辅助宏：

```objective-c
#define SafeString(obj) ({ \
    id _obj = (obj); \
    NSString *_result = nil; \
    if ([_obj isKindOfClass:[NSString class]]) { \
        _result = (NSString *)_obj; \
    } else if ([_obj isKindOfClass:[NSNumber class]]) { \
        _result = [(NSNumber *)_obj stringValue]; \
    } \
    _result; \
})

// 使用
NSString *albumAudioId = SafeString(json[@"album_audio_id"]);
```

## 🧪 测试验证

### 测试步骤

1. **Clean Build**
   ```
   ⇧⌘K (Shift + Command + K)
   ```

2. **重新编译运行**
   ```
   ⌘R (Command + R)
   ```

3. **测试下载**
   - 点击"☁️ 云端"按钮
   - 搜索并下载音乐

### 预期结果

**修复前：**
```
🔍 [酷狗] 获取下载链接: xxx
💥 崩溃：NSInvalidArgumentException
```

**修复后：**
```
🔍 [酷狗] 获取下载链接: xxx
✅ [酷狗] 获取到下载链接（方式1/2/3）
⬇️ [酷狗] 开始下载...
✅ [酷狗] 下载完成
```

## 📊 修复覆盖率

| 位置 | 字段 | 修复前 | 修复后 | 状态 |
|-----|------|--------|--------|------|
| 方式1 | `json[@"url"]` | ❌ 假设是字符串 | ✅ 类型检查 | 已修复 |
| 方式2 | `json[@"album_audio_id"]` | ❌ 假设是字符串 | ✅ 支持 NSNumber | 已修复 |
| 方式2 | `json[@"data"][@"play_url"]` | ❌ 假设是字符串 | ✅ 类型检查 | 已修复 |
| 方式3 | `json[@"url"][0]` | ❌ 假设是字符串 | ✅ 类型检查 | 已修复 |

## 🎯 经验总结

### 处理第三方 API 时

1. ✅ **永远不要假设类型**
   - JSON 解析后的值类型不确定
   - 需要先用 `isKindOfClass:` 检查

2. ✅ **防御性编程**
   - 检查 nil
   - 检查类型
   - 提供默认值

3. ✅ **错误处理**
   - 类型不匹配时有降级方案
   - 记录日志便于调试

4. ✅ **单元测试**
   - 测试不同的 JSON 响应格式
   - 测试边界情况

## 📚 相关资料

- [NSJSONSerialization 官方文档](https://developer.apple.com/documentation/foundation/nsjsonserialization)
- [Objective-C 类型安全最佳实践](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ProgrammingWithObjectiveC/Introduction/Introduction.html)

---

**总结：所有类型安全问题已修复，现在应用不会因为 JSON 类型不匹配而崩溃了！** 🎉
