#import <Foundation/Foundation.h>
#import <Cordova/CDV.h>
#import <AVFoundation/AVFoundation.h>
#define DEBUG_MODE
#import "nuisdk.framework/Headers/NeoNui.h"
#import "NuiSdkUtils.h"

#import "AudioController.h"
#import <AudioToolbox/AudioToolbox.h>
#include <sys/time.h>
#include <time.h>


NS_ASSUME_NONNULL_BEGIN

/**
 * 语音转写错误码枚举
 */
typedef NS_ENUM(NSInteger, AISpeechTranscriberErrorCode) {
    AISpeechTranscriberErrorCodeNone = 0,                // 无错误
    AISpeechTranscriberErrorCodeNetworkError = 1001,     // 网络错误
    AISpeechTranscriberErrorCodeAuthFailed = 1002,       // 鉴权失败
    AISpeechTranscriberErrorCodeNoPermission = 1003,     // 无麦克风权限
    AISpeechTranscriberErrorCodeEngineError = 1004,      // 引擎初始化失败
    AISpeechTranscriberErrorCodeCanceled = 1005          // 用户取消
};

/**
 * 语音转写状态枚举
 */
typedef NS_ENUM(NSInteger, AISpeechTranscriberState) {
    AISpeechTranscriberStateIdle = 0,        // 空闲状态
    AISpeechTranscriberStateListening = 1,   // 正在监听（录音）
    AISpeechTranscriberStateRecognizing = 2, // 正在识别
    AISpeechTranscriberStateFinished = 3,    // 识别完成
    AISpeechTranscriberStateError = 4        // 识别出错
};

/**
 * 语音转写代理协议
 */
@protocol AISpeechTranscriberDelegate <NSObject>

@optional
/**
 * 实时返回转写结果（中间结果）
 * @param transcriber 转写器实例
 * @param result 实时转写文本
 */
- (void)speechTranscriber:(nonnull id)transcriber didReceivePartialResult:(nonnull NSString *)result;

/**
 * 转写完成，返回最终结果
 * @param transcriber 转写器实例
 * @param finalResult 最终转写文本
 */
- (void)speechTranscriber:(nonnull id)transcriber didFinishWithResult:(nonnull NSString *)finalResult;

/**
 * 转写出错
 * @param transcriber 转写器实例
 * @param error 错误信息（包含错误码和描述）
 */
- (void)speechTranscriber:(nonnull id)transcriber didFailWithError:(nonnull NSError *)error;

/**
 * 转写状态发生变化
 * @param transcriber 转写器实例
 * @param state 新的状态
 */
- (void)speechTranscriber:(nonnull id)transcriber didChangeState:(AISpeechTranscriberState)state;

@end

/**
 * AI语音转写核心类
 */
@interface AISpeechTranscriber : CDVPlugin <ConvVoiceRecorderDelegate, NeoNuiSdkDelegate>

// 阿里云SDK核心实例
@property NeoNui *nui;
// 工具类
@property NuiSdkUtils *utils;
// 录音数据缓存
@property NSMutableData *recordedVoiceData;
// 当前任务ID
@property NSString *currentTaskId;
// 音频控制器
//@property id audioController;
@property(nonatomic,strong) AudioController *audioController;

// Cordova相关属性
@property NSDictionary *config;
@property BOOL isTranscribing;
@property NSString *transcribeCallbackId;
@property NSString *mserviceurl;
@property  NSString *mappkey;
/** 代理对象 */
@property (nonatomic, weak, nullable) id<AISpeechTranscriberDelegate> delegate;
/** 当前转写状态 */
@property (nonatomic, assign, readonly) AISpeechTranscriberState state;
/** 是否启用实时转写（边说边识别），默认YES */
@property (nonatomic, assign) BOOL enableRealTimeTranscription;
/** 语音识别语言，默认zh-CN */
@property (nonatomic, copy) NSString *language;
/** 超时时间（秒），默认30秒 */
@property (nonatomic, assign) NSTimeInterval timeout;

///** 配置参数 */
//@property (nonatomic, strong, nullable) NSDictionary *config;
///** 当前是否正在转写 */
//@property (nonatomic, assign) BOOL isTranscribing;
///** 回调ID（用于持续返回转写结果） */
//@property (nonatomic, copy, nullable) NSString *transcribeCallbackId;

/**
 * 单例方法
 * @return 全局唯一的转写器实例
 */
+ (instancetype)sharedInstance;

/**
 * 初始化方法
 * @param appKey 应用唯一标识
 * @param secretKey 应用密钥
 * @return 转写器实例
 */
- (instancetype)initWithAppKey:(NSString *)appKey secretKey:(NSString *)secretKey NS_DESIGNATED_INITIALIZER;

/**
 * 开始语音转写（启动录音和识别）
 * @return 是否启动成功
 */
- (BOOL)startTranscription;

/**
 * 停止语音转写（停止录音，等待最终结果）
 */
- (void)stopTranscription;

/**
 * 取消语音转写（立即终止，不返回结果）
 */
- (void)cancelTranscription;

/**
 * 检查麦克风权限
 * @param completion 权限检查结果回调
 */
- (void)checkMicrophonePermissionWithCompletion:(void (^)(BOOL granted))completion;

/**
 * 销毁资源
 */
- (void)destroy;

/**
 * 禁用默认初始化方法
 */
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (void)terminateNui;
- (NSString*) genInitParams;
- (NSString*) genStartParams;

@end



NS_ASSUME_NONNULL_END
