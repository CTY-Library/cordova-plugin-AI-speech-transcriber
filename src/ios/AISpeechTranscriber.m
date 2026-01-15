#import <Cordova/CDV.h>
// 引入阿里云语音转写SDK头文件（需根据实际SDK调整）
#import <AliyunOSSiOS/AliyunOSSiOS.h>
#import <SpeechTranscriber/SpeechTranscriber.h>

@interface AISpeechTranscriber : CDVPlugin

// 阿里云语音转写核心实例
@property (nonatomic, strong) SpeechTranscriber *transcriber;
// 配置参数
@property (nonatomic, strong) NSDictionary *config;
// 当前是否正在转写
@property (nonatomic, assign) BOOL isTranscribing;
// 回调ID（用于持续返回转写结果）
@property (nonatomic, copy) NSString *transcribeCallbackId;

// 初始化SDK
- (void)init:(CDVInvokedUrlCommand *)command;
// 启动语音转写
- (void)startTranscribe:(CDVInvokedUrlCommand *)command;
// 停止语音转写
- (void)stopTranscribe:(CDVInvokedUrlCommand *)command;
// 释放SDK资源
- (void)release:(CDVInvokedUrlCommand *)command;

@end

@implementation AISpeechTranscriber

- (void)init:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = nil;
    self.config = command.arguments[0];
    
    @try {
        // 1. 解析配置参数
        BOOL saveAudio = [[self.config objectForKey:@"saveAudio"] boolValue];
        // 补充阿里云SDK必要配置（需从config中获取，如appKey、accessKey等，需你根据实际配置补充）
        NSString *appKey = [self.config objectForKey:@"appKey"];
        NSString *accessKeyId = [self.config objectForKey:@"accessKeyId"];
        NSString *accessKeySecret = [self.config objectForKey:@"accessKeySecret"];
        
        // 2. 初始化阿里云语音转写实例
        self.transcriber = [[SpeechTranscriber alloc] init];
        // 设置SDK配置（需根据阿里云官方文档调整）
        [self.transcriber setAppKey:appKey];
        [self.transcriber setAccessKeyId:accessKeyId];
        [self.transcriber setAccessKeySecret:accessKeySecret];
        [self.transcriber setSaveAudio:saveAudio]; // 是否保存音频
        
        // 3. 设置代理（用于接收转写回调）
        self.transcriber.delegate = self;
        
        // 初始化成功
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"SDK初始化成功"];
    } @catch (NSException *exception) {
        // 初始化失败
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"初始化失败：%@", exception.reason]];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)startTranscribe:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = nil;
    self.transcribeCallbackId = command.callbackId;
    
    @try {
        if (self.isTranscribing) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"已在转写中，请勿重复启动"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }
        
        // 启动语音转写
        [self.transcriber startTranscribing];
        self.isTranscribing = YES;
        
        // 返回启动成功，并设置回调为持续回调（用于接收实时转写结果）
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"转写已启动"];
        [pluginResult setKeepCallbackAsBool:YES];
    } @catch (NSException *exception) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"启动转写失败：%@", exception.reason]];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)stopTranscribe:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = nil;
    
    @try {
        if (!self.isTranscribing) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"未在转写中，无需停止"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }
        
        // 停止语音转写
        [self.transcriber stopTranscribing];
        self.isTranscribing = NO;
        
        // 停止成功，结束持续回调
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"转写已停止"];
        [pluginResult setKeepCallbackAsBool:NO];
    } @catch (NSException *exception) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"停止转写失败：%@", exception.reason]];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.transcribeCallbackId];
    self.transcribeCallbackId = nil;
}

- (void)release:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = nil;
    
    @try {
        // 释放SDK资源
        if (self.transcriber) {
            [self.transcriber releaseResources];
            self.transcriber = nil;
            self.config = nil;
            self.isTranscribing = NO;
            self.transcribeCallbackId = nil;
        }
        
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"SDK资源已释放"];
    } @catch (NSException *exception) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"释放资源失败：%@", exception.reason]];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

#pragma mark - SpeechTranscriberDelegate（阿里云转写代理回调）
- (void)onTranscriptionResult:(NSString *)result isFinal:(BOOL)isFinal {
    // 实时返回转写结果给JS
    if (self.transcribeCallbackId) {
        NSDictionary *resultDict = @{
            @"text": result,
            @"isFinal": @(isFinal) // 是否是最终结果
        };
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:resultDict];
        [pluginResult setKeepCallbackAsBool:YES]; // 保持回调，持续返回结果
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.transcribeCallbackId];
        
        // 如果是最终结果，结束持续回调
        if (isFinal) {
            [pluginResult setKeepCallbackAsBool:NO];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:self.transcribeCallbackId];
            self.isTranscribing = NO;
        }
    }
}

- (void)onTranscriptionError:(NSError *)error {
    // 转写错误回调
    if (self.transcribeCallbackId) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"转写错误：%@", error.localizedDescription]];
        [pluginResult setKeepCallbackAsBool:NO];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.transcribeCallbackId];
        self.isTranscribing = NO;
    }
}

@end