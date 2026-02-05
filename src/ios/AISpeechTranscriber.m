#import <Cordova/CDV.h>
#import <Foundation/Foundation.h>
#define DEBUG_MODE
#import "nuisdk.framework/Headers/NeoNui.h"
#import "NuiSdkUtils.h"


#import <AudioToolbox/AudioToolbox.h>
#include <sys/time.h>
#include <time.h>


#import "AISpeechTranscriber.h"

#define SCREEN_WIDTH_BASE 375
#define SCREEN_HEIGHT_BASE 667

static BOOL save_wav = NO;
static BOOL save_log = NO;


@implementation AISpeechTranscriber

- (void)pluginInitialize {
    CDVViewController *viewController = (CDVViewController *)self.viewController;
    _mserviceurl = [viewController.settings objectForKey:@"serviceurl"];//获取插件的SECRET_KEY
    _mappkey = [viewController.settings objectForKey:@"appkey"];//获取插件的APPKEY
}


#pragma mark - Cordova Plugin Methods

- (void)init:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = nil;
    NSDictionary *config = command.arguments[0];
    
    @try {
        // 解析配置参数
        BOOL saveAudio = [config objectForKey:@"saveAudio"] ? [[config objectForKey:@"saveAudio"] boolValue] : NO;
       // NSString *appKey = [config objectForKey:@"appKey"];
        NSString *token = [config objectForKey:@"token"];
        NSString *accessKey = [config objectForKey:@"accessKey"];
        NSString *accessKeySecret = [config objectForKey:@"accessKeySecret"];
        NSString *stsToken = [config objectForKey:@"stsToken"];
        NSString *serviceUrl = [config objectForKey:@"serviceUrl"];
        
        // 保存配置
        self.config = config;
        
        // 初始化工具类
        _utils = [NuiSdkUtils alloc];
      
        
        // 初始化SDK实例
        [self initNuiWithAppKey:_mappkey
                        token:token
                     accessKey:accessKey 
                accessKeySecret:accessKeySecret 
                      stsToken:stsToken 
                     serviceUrl:_mserviceurl
                     saveAudio:saveAudio];
        
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
        
        // 检查麦克风权限
        [self checkMicrophonePermissionWithCompletion:^(BOOL granted) {
            if (!granted) {
                CDVPluginResult *errorResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"未获得录音权限，无法正常运行。请通过设置界面重新开启权限。"];
                [self.commandDelegate sendPluginResult:errorResult callbackId:command.callbackId];
                return;
            }
            
            // 权限获取成功，启动转写
            [self performStartTranscription:command];
        }];
        
        return;
    } @catch (NSException *exception) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"启动转写失败：%@", exception.reason]];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)stopTranscribe:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = nil;
    self.transcribeCallbackId = command.callbackId;
    @try {
        if (!self.isTranscribing) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"未在转写中，无需停止"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }
        
        // 停止转写
        [self performStopTranscription];
        
        // 停止成功
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"转写已停止"];
    } @catch (NSException *exception) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"停止转写失败：%@", exception.reason]];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    
}

- (void)release:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = nil;
    
    @try {
        [self terminateNui];
        
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"SDK资源已释放"];
    } @catch (NSException *exception) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"释放资源失败：%@", exception.reason]];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

#pragma mark - Private Methods

- (void)initNuiWithAppKey:(NSString *)appKey 
                   token:(NSString *)token 
                accessKey:(NSString *)accessKey 
          accessKeySecret:(NSString *)accessKeySecret 
                stsToken:(NSString *)stsToken 
               serviceUrl:(NSString *)serviceUrl 
               saveAudio:(BOOL)saveAudio {
    
    if (_nui == NULL) {
        _nui = [NeoNui get_instance];
        _nui.delegate = self;
    }
    
    // 设置全局保存选项
    save_wav = saveAudio;
    save_log = saveAudio;
    
    // 请注意此处的参数配置，其中账号相关需要按照genInitParams的说明填入后才可访问服务
    NSString *initParam = [self genInitParamsWithAppKey:appKey 
                                          token:token 
                                       accessKey:accessKey 
                                 accessKeySecret:accessKeySecret 
                                       stsToken:stsToken 
                                      serviceUrl:serviceUrl];
    
    //请注意此处的参数配置，其中账号相关需要按照genInitParams的说明填入后才可访问服务
    //NSString * initParam = [self genInitParams];
    
    [_nui nui_initialize:[initParam UTF8String] logLevel:NUI_LOG_LEVEL_DEBUG saveLog:save_log];
    NSString *parameters = [self genParams];
    [_nui nui_set_params:[parameters UTF8String]];
    
    NSLog(@"SDK initialized successfully");
}

 

- (void)performStartTranscription:(CDVInvokedUrlCommand *)command {
    
    if (_audioController == nil) {
        // 注意：这里audioController模块仅用于录音示例，用户可根据业务场景自行实现这部分代码
        _audioController = [[AudioController alloc] init:only_recorder];
        _audioController.delegate = self;
    }
    
    
    if (_nui != nil) {
       
        // 生成对话参数
        NSString *parameters = [self genDialogParams];
        
        // 启动实时转写
        int ret = [_nui nui_dialog_start:MODE_P2T dialogParam:[parameters UTF8String]];
        
        if (ret == 0) {
            self.isTranscribing = YES;
            
            // 返回启动成功，并设置回调为持续回调
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"实时转写已启动"];
            [pluginResult setKeepCallbackAsBool:YES];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        } else {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR 
                                                              messageAsString:[NSString stringWithFormat:@"启动转写失败，错误码：%d", ret]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    } else {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"SDK未初始化"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}

- (void)performStopTranscription {
    if (_nui != nil) {
        [_nui nui_dialog_cancel:NO];
        self.isTranscribing = NO;
        _recordedVoiceData = nil;
        if (_audioController != nil) {
            [_audioController stopRecorder:NO];
        }
        self.recordedVoiceData = nil;
    }
}

- (void)terminateNui {
    NSLog(@"terminateNui");
    if (_nui != nil) {
        [_nui nui_release];
        _nui.delegate = nil;
        _nui = nil;
    }
    _recordedVoiceData = nil;
    
    if (_audioController != nil) {
        _audioController.delegate = nil;
    }
    
    _utils = nil;
    self.isTranscribing = NO;
    self.transcribeCallbackId = nil;
}

- (void)dealloc {
    NSLog(@"AISpeechTranscriber dealloc");
    [self terminateNui];
}


#pragma mark - Voice Recorder Delegate
-(void) recorderDidStart{
    TLog(@"recorderDidStart");
}

-(void) recorderDidStop{
    [self.recordedVoiceData setLength:0];
    TLog(@"recorderDidStop");
}

-(void) voiceRecorded:(unsigned char*)buffer Length:(int)len {
    NSData *frame = [NSData dataWithBytes:buffer length:len];
    @synchronized(_recordedVoiceData){
        [_recordedVoiceData appendData:frame];
    }
}

-(void) voiceDidFail:(NSError*)error{
    TLog(@"recorder error ");
}

#pragma mark - Microphone Permission

- (void)checkMicrophonePermissionWithCompletion:(void (^)(BOOL granted))completion {
    AVAudioSessionRecordPermission permission = [[AVAudioSession sharedInstance] recordPermission];
    
    switch (permission) {
        case AVAudioSessionRecordPermissionGranted:
            if (completion) completion(YES);
            break;
        case AVAudioSessionRecordPermissionDenied:
            if (completion) completion(NO);
            break;
        case AVAudioSessionRecordPermissionUndetermined:
            [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
                if (completion) completion(granted);
            }];
            break;
//        default:
//            if (completion) completion(NO);
//            break;
    }
}

#pragma mark - Parameter Generation Methods

- (NSString*)genInitParamsWithAppKey:(NSString *)appKey 
                            token:(NSString *)token 
                         accessKey:(NSString *)accessKey 
                   accessKeySecret:(NSString *)accessKeySecret 
                         stsToken:(NSString *)stsToken 
                        serviceUrl:(NSString *)serviceUrl {
    
    //    NSString *strResourcesBundle = [[NSBundle mainBundle] pathForResource:@"Resources" ofType:@"bundle"];
    //    NSString *bundlePath = [[NSBundle bundleWithPath:strResourcesBundle] resourcePath]; // 注意: V2.6.2版本开始纯云端功能可不需要资源文件
        NSString *debug_path = [_utils createDir];

        NSMutableDictionary *ticketJsonDict = [NSMutableDictionary dictionary];
        //获取账号访问凭证：
        [_utils getTicket:ticketJsonDict Type:get_token_from_server_for_online_features];
        
        [ticketJsonDict setObject: token forKey:@"token"];
        
        [ticketJsonDict setObject: appKey  forKey:@"app_key"];
        
        
        if ([ticketJsonDict objectForKey:@"token"] != nil) {
            NSString *tokenValue = [ticketJsonDict objectForKey:@"token"];
            if ([tokenValue length] == 0) {
                TLog(@"The 'token' key exists but the value is empty.");
            }
        } else {
            TLog(@"The 'token' key does not exist.");
        }

        [ticketJsonDict setObject:@"wss://nls-gateway.cn-shanghai.aliyuncs.com:443/ws/v1" forKey:@"url"]; // 默认
        //工作目录路径，SDK从该路径读取配置文件
    //    [ticketJsonDict setObject:bundlePath forKey:@"workspace"]; // V2.6.2版本开始纯云端功能可不设置workspace

        //当初始化SDK时的save_log参数取值为true时，该参数生效。表示是否保存音频debug，该数据保存在debug目录中，需要确保debug_path有效可写
        [ticketJsonDict setObject:save_wav ? @"true" : @"false" forKey:@"save_wav"];
        //debug目录。当初始化SDK时的save_log参数取值为true时，该目录用于保存中间音频文件
        [ticketJsonDict setObject:debug_path forKey:@"debug_path"];

        //过滤SDK内部日志通过回调送回到用户层
        [ticketJsonDict setObject:[NSString stringWithFormat:@"%d", NUI_LOG_LEVEL_NONE] forKey:@"log_track_level"];
        //设置本地存储日志文件的最大字节数, 最大将会在本地存储2个设置字节大小的日志文件
        [ticketJsonDict setObject:@(50 * 1024 * 1024) forKey:@"max_log_file_size"];

        //FullMix = 0   // 选用此模式开启本地功能并需要进行鉴权注册
        //FullCloud = 1 // 在线实时语音识别可以选这个
        //FullLocal = 2 // 选用此模式开启本地功能并需要进行鉴权注册
        //AsrMix = 3    // 选用此模式开启本地功能并需要进行鉴权注册
        //AsrCloud = 4  // 在线一句话识别可以选这个
        //AsrLocal = 5  // 选用此模式开启本地功能并需要进行鉴权注册
        [ticketJsonDict setObject:@"1" forKey:@"service_mode"]; // 必填

        [ticketJsonDict setObject:@"empty_device_id" forKey:@"device_id"]; // 必填, 推荐填入具有唯一性的id, 方便定位问题

        NSData *data = [NSJSONSerialization dataWithJSONObject:ticketJsonDict options:NSJSONWritingPrettyPrinted error:nil];
        NSString * jsonStr = [[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
        return jsonStr;
   
}

- (NSString*)genParams {
    NSMutableDictionary *nls_config = [NSMutableDictionary dictionary];
    [nls_config setValue:@YES forKey:@"enable_intermediate_result"];
//    参数可根据实际业务进行配置
//    接口说明可见https://help.aliyun.com/document_detail/173528.html
//    查看 2.开始识别
//    [nls_config setValue:@"<更新token>" forKey:@"token"];
//    [nls_config setValue:@YES forKey:@"enable_punctuation_prediction"];
//    [nls_config setValue:@YES forKey:@"enable_inverse_text_normalization"];
//    [nls_config setValue:@YES forKey:@"enable_voice_detection"];
//    [nls_config setValue:@10000 forKey:@"max_start_silence"];
//    [nls_config setValue:@800 forKey:@"max_end_silence"];
//    [nls_config setValue:@800 forKey:@"max_sentence_silence"];
//    [nls_config setValue:@NO forKey:@"enable_words"];
//    [nls_config setValue:@16000 forKey:@"sample_rate"];
//    [nls_config setValue:@"opus" forKey:@"sr_format"];

    NSMutableDictionary *dictM = [NSMutableDictionary dictionary];
    [dictM setObject:nls_config forKey:@"nls_config"];
    [dictM setValue:@(SERVICE_TYPE_SPEECH_TRANSCRIBER) forKey:@"service_type"]; // 必填

//    如果有HttpDns则可进行设置
//    [dictM setObject:[_utils getDirectIp] forKey:@"direct_ip"];

    /*若文档中不包含某些参数，但是此功能支持这个参数，可以用如下万能接口设置参数*/
//    NSMutableDictionary *extend_config = [NSMutableDictionary dictionary];
//    [extend_config setValue:@YES forKey:@"custom_test"];
//    [dictM setObject:extend_config forKey:@"extend_config"];
    
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictM options:NSJSONWritingPrettyPrinted error:nil];
    NSString * jsonStr = [[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
    return jsonStr;
    
//    NSMutableDictionary *nls_config = [NSMutableDictionary dictionary];
//    [nls_config setValue:@YES forKey:@"enable_intermediate_result"];
//    [nls_config setValue:@YES forKey:@"enable_punctuation_prediction"];
//    [nls_config setValue:@16000 forKey:@"sample_rate"];
//    [nls_config setValue:@"opus" forKey:@"sr_format"];
//    
//    NSMutableDictionary *dictM = [NSMutableDictionary dictionary];
//    [dictM setObject:nls_config forKey:@"nls_config"];
//    [dictM setValue:@(SERVICE_TYPE_SPEECH_TRANSCRIBER) forKey:@"service_type"]; // 必填
//    
//    NSData *data = [NSJSONSerialization dataWithJSONObject:dictM options:NSJSONWritingPrettyPrinted error:nil];
//    NSString *jsonStr = [[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
    return jsonStr;
}

- (NSString*)genDialogParams {
    NSMutableDictionary *dialog_params = [NSMutableDictionary dictionary];
    
    // 运行过程中可以在nui_dialog_start时更新临时参数，尤其是更新过期token
    // 注意: 若下一轮对话不再设置参数，则继续使用初始化时传入的参数
    long distance_expire_time_4h = 14400;
    [_utils refreshTokenIfNeed:dialog_params distanceExpireTime:distance_expire_time_4h];
    
    NSData *data = [NSJSONSerialization dataWithJSONObject:dialog_params options:NSJSONWritingPrettyPrinted error:nil];
    NSString *jsonStr = [[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
    return jsonStr;
}

#pragma mark - NeoNuiSdkDelegate

- (void)onNuiEventCallback:(NuiCallbackEvent)nuiEvent
                   dialog:(long)dialog
                kwsResult:(const char *)wuw
                asrResult:(const char *)asr_result
                 ifFinish:(BOOL)finish
                  retCode:(int)code {
    
    NSLog(@"onNuiEventCallback event %d finish %d code %d", nuiEvent, finish, code);
    
    if (nuiEvent == EVENT_TRANSCRIBER_STARTED) {
        // asr_result在此包含task_id，task_id有助于排查问题，请用户进行记录保存。
        NSString *startedInfo = [NSString stringWithFormat:@"EVENT_TRANSCRIBER_STARTED: %@",
                                 [NSString stringWithUTF8String:asr_result]];
        NSLog(@"%@", startedInfo);
        [self sendCallbackToJS:@"start" message:startedInfo];
    } else if (nuiEvent == EVENT_TRANSCRIBER_COMPLETE) {
        [self sendCallbackToJS:@"complete" message:@"转写完成"];
    } else if (nuiEvent == EVENT_ASR_PARTIAL_RESULT || nuiEvent == EVENT_SENTENCE_END) {
        // asr_result在此包含task_id，task_id有助于排查问题，请用户进行记录保存。
        NSLog(@"ASR RESULT %s finish %d", asr_result, finish);
        NSString *result = [NSString stringWithUTF8String:asr_result];
        [self sendCallbackToJS:@"partial" message:result];
    } else if (nuiEvent == EVENT_VAD_START) {
        NSLog(@"EVENT_VAD_START");
        [self sendCallbackToJS:@"vad_start" message:@"检测到语音开始"];
    } else if (nuiEvent == EVENT_VAD_END) {
        NSLog(@"EVENT_VAD_END");
        [self sendCallbackToJS:@"vad_end" message:@"检测到语音结束"];
    } else if (nuiEvent == EVENT_ASR_ERROR) {
        // asr_result在EVENT_ASR_ERROR中为错误信息，搭配错误码code和其中的task_id更易排查问题，请用户进行记录保存。
        NSLog(@"EVENT_ASR_ERROR error[%d]", code);
        NSString *errorMsg = [NSString stringWithUTF8String:asr_result];
        [self sendCallbackToJS:@"error" message:[NSString stringWithFormat:@"转写错误：%@（错误码：%d）", errorMsg, code]];
    } else if (nuiEvent == EVENT_MIC_ERROR) {
        NSLog(@"MIC ERROR");
        //[self sendCallbackToJS:@"error" message:@"麦克风异常"];
        if (_audioController != nil) {
            [_audioController stopRecorder:NO];
            [_audioController startRecorder];
        }
    }
    
    // finish 为真（可能是发生错误，也可能是完成识别）表示一次任务生命周期结束，可以开始新的识别
    if (finish) {
        self.isTranscribing = NO;
        [self sendCallbackToJS:@"stop" message:@"转写停止"];
    }
}

- (int)onNuiNeedAudioData:(char *)audioData length:(int)len {
    static int emptyCount = 0;
    @autoreleasepool {
        @synchronized(_recordedVoiceData) {
            if (_recordedVoiceData.length > 0) {
                int recorder_len = 0;
                if (_recordedVoiceData.length > len)
                    recorder_len = len;
                else
                    recorder_len = _recordedVoiceData.length;
                NSData *tempData = [_recordedVoiceData subdataWithRange:NSMakeRange(0, recorder_len)];
                [tempData getBytes:audioData length:recorder_len];
                tempData = nil;
                NSInteger remainLength = _recordedVoiceData.length - recorder_len;
                NSRange range = NSMakeRange(recorder_len, remainLength);
                [_recordedVoiceData setData:[_recordedVoiceData subdataWithRange:range]];
                emptyCount = 0;
                return recorder_len;
            } else {
                if (emptyCount++ >= 50) {
                    NSLog(@"_recordedVoiceData length = %lu! empty 50times.", (unsigned long)_recordedVoiceData.length);
                    emptyCount = 0;
                }
                return 0;
            }
        }
    }
    return 0;
}

- (void)onNuiAudioStateChanged:(NuiAudioState)state {
    TLog(@"onNuiAudioStateChanged state=%u", state);
    if (state == STATE_CLOSE || state == STATE_PAUSE) {
        if (_audioController != nil) {
            [_audioController stopRecorder:NO];
        }
    } else if (state == STATE_OPEN){
        self.recordedVoiceData = [NSMutableData data];
        if (_audioController != nil) {
            [_audioController startRecorder];
        }
    }
}

- (void)onNuiRmsChanged:(float)rms {
    // 可以在这里处理音量变化
}

- (void)onNuiLogTrackCallback:(NuiSdkLogLevel)level
                  logMessage:(const char *)log {
    NSLog(@"onNuiLogTrackCallback log level:%d, message -> %s", level, log);
}

#pragma mark - Helper Methods

- (void)sendCallbackToJS:(NSString *)type message:(NSString *)message {
    if (self.transcribeCallbackId) {
        NSDictionary *resultDict = @{
            @"type": type, // start/partial/complete/error/info/stop/vad_start/vad_end
            @"message": message,
            @"taskId": _currentTaskId ?: @""
        };
        
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:resultDict];
        [pluginResult setKeepCallbackAsBool:YES]; // 保持回调，持续返回结果
        
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.transcribeCallbackId];
        
        // 如果是最终结果或错误，结束持续回调
        if ([type isEqualToString:@"complete"] || [type isEqualToString:@"error"] || [type isEqualToString:@"stop"]) {
            [pluginResult setKeepCallbackAsBool:NO];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:self.transcribeCallbackId];
        }
    }
}

- (void)cancelTranscription {
}

 

- (void)destroy {
}

 

@end
