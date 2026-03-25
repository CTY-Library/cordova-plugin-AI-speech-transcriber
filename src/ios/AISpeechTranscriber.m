#import <Cordova/CDV.h>
#import <Foundation/Foundation.h>
#define DEBUG_MODE
#import "nuisdk.framework/Headers/NeoNui.h"
#import "nuisdk.framework/Headers/StreamInputTts.h"
#import "NuiSdkUtils.h"

#import <AudioToolbox/AudioToolbox.h>
#include <sys/time.h>
#include <time.h>

#import "AudioController.h"


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

- (void)initTTS:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = nil;
    NSDictionary *config = command.arguments[0];
    
    @try {
        // 解析配置参数 - 与init方法保持一致
        NSString *token = [config objectForKey:@"token"];
        NSString *accessKey = [config objectForKey:@"accessKey"];
        NSString *accessKeySecret = [config objectForKey:@"accessKeySecret"];
        NSString *stsToken = [config objectForKey:@"stsToken"];
        NSString *serviceUrl = [config objectForKey:@"serviceUrl"];
        
        // 保存TTS认证配置
        _ttsToken = token;
        _ttsAccessKey = accessKey;
        _ttsAccessKeySecret = accessKeySecret;
        _ttsStsToken = stsToken;
        _ttsServiceUrl = serviceUrl ?: _mserviceurl;
        
        BOOL success = [self initTTSWithConfig:config];
        if (success) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"TTS初始化成功"];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"TTS初始化失败"];
        }
    } @catch (NSException *exception) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"TTS初始化异常：%@", exception.reason]];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)startTTS:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = nil;
    NSString *text = command.arguments[0];
    
    @try {
        // 验证文本参数
        if (!text || [text length] == 0) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"TTS文本不能为空"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }
        
        BOOL success = [self startTTSWithText:text];
        if (success) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"TTS启动成功"];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"TTS启动失败"];
        }
    } @catch (NSException *exception) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"TTS启动异常：%@", exception.reason]];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)sendTTSText:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = nil;
    NSString *text = command.arguments[0];
    
    @try {
        // 验证文本参数
        if (!text || [text length] == 0) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"TTS文本不能为空"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }
        
        BOOL success = [self sendTTSTextInternal:text];
        if (success) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"TTS文本发送成功"];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"TTS文本发送失败"];
        }
    } @catch (NSException *exception) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"TTS文本发送异常：%@", exception.reason]];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)isInitialized:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = nil;
    
    @try {
        BOOL initialized = [self isInitialized];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:initialized];
        NSLog(@"语音识别状态检查: %@", initialized ? @"已初始化" : @"未初始化");
    } @catch (NSException *exception) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"检查语音识别状态异常：%@", exception.reason]];
        NSLog(@"语音识别状态检查异常: %@", exception.reason);
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)isTTSInitialized:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = nil;
    
    @try {
        BOOL initialized = [self isTTSInitialized];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:initialized];
        NSLog(@"TTS状态检查: %@", initialized ? @"已初始化" : @"未初始化");
    } @catch (NSException *exception) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"检查TTS状态异常：%@", exception.reason]];
        NSLog(@"TTS状态检查异常: %@", exception.reason);
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)stopTTS:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = nil;
    
    @try {
        [self stopTTS];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"TTS停止成功"];
    } @catch (NSException *exception) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"TTS停止异常：%@", exception.reason]];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)releaseTTS:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = nil;
    
    @try {
        [self releaseTTS];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"TTS资源释放成功"];
    } @catch (NSException *exception) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"TTS资源释放异常：%@", exception.reason]];
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
    NSLog(@"AISpeechTranscriber dealloc");
    [self terminateNui];
}

#pragma mark - TTS Methods

- (BOOL)initTTSWithConfig:(NSDictionary *)config {
    @try {
        // 解析TTS配置参数
        if ([config objectForKey:@"voice"]) {
            _ttsVoice = [config objectForKey:@"voice"];
        } else {
            _ttsVoice = @"xiaoyun"; // 统一使用xiaoyun音色
        }
        
        if ([config objectForKey:@"format"]) {
            _ttsFormat = [config objectForKey:@"format"];
        } else {
            _ttsFormat = @"pcm"; // 默认格式
        }
        
        if ([config objectForKey:@"sampleRate"]) {
            _ttsSampleRate = [[config objectForKey:@"sampleRate"] integerValue];
        } else {
            _ttsSampleRate = 24000; // 统一使用24000采样率
        }
        
        if ([config objectForKey:@"volume"]) {
            _ttsVolume = [[config objectForKey:@"volume"] integerValue];
        } else {
            _ttsVolume = 50; // 默认音量
        }
        
        if ([config objectForKey:@"speechRate"]) {
            _ttsSpeechRate = [[config objectForKey:@"speechRate"] integerValue];
        } else {
            _ttsSpeechRate = 0; // 默认语速
        }
        
        if ([config objectForKey:@"pitchRate"]) {
            _ttsPitchRate = [[config objectForKey:@"pitchRate"] integerValue];
        } else {
            _ttsPitchRate = 0; // 默认语调
        }

        // 初始化TTS音频播放器
        [self initTTSAudioPlayer];

        // 初始化TTS实例
        if (_ttsNui == NULL) {
            _ttsNui = [StreamInputTts get_instance];
            _ttsNui.delegate = self;
        }

        // 生成TTS初始化参数
        NSString *ticket = [self genTTSTicket];
        NSString *parameters = [self genTTSParameters];

        // 初始化TTS SDK
        int ret = [_ttsNui startStreamInputTts:[ticket UTF8String]
                                       parameters:[parameters UTF8String]
                                        sessionId:[@"" UTF8String]
                                         logLevel:NUI_LOG_LEVEL_DEBUG
                                          saveLog:save_log];

        if (ret == 0) {
            _isTTSInitialized = YES;
            NSLog(@"TTS initialized successfully with voice: %@, sampleRate: %ld", _ttsVoice, (long)_ttsSampleRate);
            return YES;
        } else {
            NSLog(@"TTS initialization failed with code: %d", ret);
            return NO;
        }
    } @catch (NSException *exception) {
        NSLog(@"TTS initialization exception: %@", exception.reason);
        return NO;
    }
}

- (BOOL)startTTSWithText:(NSString *)text {
    @try {
        if (!_isTTSInitialized) {
            NSLog(@"TTS not initialized");
            return NO;
        }

        if (_isTTSRunning) {
            NSLog(@"TTS already running");
            return NO;
        }

        _isTTSRunning = YES;

        // 发送文本进行语音合成
        int ret = [_ttsNui sendStreamInputTts:[text UTF8String]];
        if (ret == 0) {
            NSLog(@"TTS text sent successfully: %@", text);
            
            // 发送完成后调用stop接口，表示发送结束（与Android保持一致）
            int stopRet = [_ttsNui stopStreamInputTts];
            if (stopRet == 0) {
                NSLog(@"TTS stop interface called successfully");
            } else {
                NSLog(@"TTS stop interface failed with code: %d", stopRet);
            }
            
            return YES;
        } else {
            NSLog(@"TTS text send failed with code: %d", ret);
            _isTTSRunning = NO;
            return NO;
        }
    } @catch (NSException *exception) {
        NSLog(@"TTS start exception: %@", exception.reason);
        _isTTSRunning = NO;
        return NO;
    }
}

- (BOOL)sendTTSTextInternal:(NSString *)text {
    @try {
        if (!_isTTSInitialized) {
            NSLog(@"TTS not initialized");
            return NO;
        }

        // 检查TTS实例状态，如果已完成或未运行，需要重新启动
        if (!_isTTSRunning || _isTTSFinishSend) {
            NSLog(@"TTS instance not running or completed, restarting TTS service");
            
            // 强制清理之前的状态
            if (_ttsNui != NULL) {
                NSLog(@"Cleaning up old TTS instance state");
                [_ttsNui stopStreamInputTts];
            }
            [self stopTTSAudioPlayback]; // 清理音频播放状态
            
            // 重新生成参数并启动TTS实例
            NSString *ticket = [self genTTSTicket];
            NSString *parameters = [self genTTSParameters];
            
            int startRet = [_ttsNui startStreamInputTts:[ticket UTF8String]
                                           parameters:[parameters UTF8String]
                                            sessionId:[@"" UTF8String]
                                             logLevel:NUI_LOG_LEVEL_DEBUG
                                              saveLog:save_log];
            
            if (startRet != 0) {
                NSLog(@"TTS instance restart failed with code: %d", startRet);
                return NO;
            }
            
            NSLog(@"TTS instance restarted successfully");
        }

        _isTTSRunning = YES;

        // 发送文本进行语音合成
        int ret = [_ttsNui sendStreamInputTts:[text UTF8String]];
        if (ret == 0) {
            NSLog(@"TTS text sent successfully: %@", text);
            
            // 发送完成后立即调用stop接口，表示发送结束
            int stopRet = [_ttsNui stopStreamInputTts];
            if (stopRet == 0) {
                NSLog(@"TTS stop interface called successfully");
            } else {
                NSLog(@"TTS stop interface failed with code: %d", stopRet);
            }
            
            return YES;
        } else {
            NSLog(@"TTS text send failed with code: %d", ret);
            _isTTSRunning = NO;
            return NO;
        }
    } @catch (NSException *exception) {
        NSLog(@"TTS send text exception: %@", exception.reason);
        _isTTSRunning = NO;
        return NO;
    }
}

- (void)stopTTS {
    @try {
        if (!_isTTSInitialized || !_isTTSRunning) {
            NSLog(@"TTS not initialized or not running");
            return;
        }

        // 停止TTS
        [_ttsNui stopStreamInputTts];
        _isTTSRunning = NO;
        
        // 停止音频播放
        [self stopTTSAudioPlayback];
        
        NSLog(@"TTS stopped successfully");
    } @catch (NSException *exception) {
        NSLog(@"TTS stop exception: %@", exception.reason);
    }
}

- (void)releaseTTS {
    @try {
        // 停止音频播放
        [self stopTTSAudioPlayback];
        
        // 释放音频控制器
        if (_ttsAudioController) {
            [_ttsAudioController cleanPlayerBuffer];
            _ttsAudioController.delegate = nil;
            _ttsAudioController = nil;
        }
        
        if (_ttsNui != NULL) {
            [_ttsNui releaseStreamInputTts];
            _ttsNui.delegate = nil;
            _ttsNui = NULL;
        }
        _isTTSInitialized = NO;
        _isTTSRunning = NO;
        _ttsCallbackId = nil;
        NSLog(@"TTS resources released successfully");
    } @catch (NSException *exception) {
        NSLog(@"TTS release exception: %@", exception.reason);
    }
}

#pragma mark - TTS Helper Methods

- (NSString *)genTTSTicket {
    NSString *ticket = @"";
    @try {
        // 使用从JS获取的认证信息
        NSMutableDictionary *ticketDict = [NSMutableDictionary dictionary];
        
        // 设置认证信息 - 与init方法保持一致
        if (_ttsToken) {
            [ticketDict setObject:_ttsToken forKey:@"token"];
        }
        
        // 确保appkey存在 - 使用全局配置的appkey
        NSString *appKey = _ttsAccessKey ?: _mappkey;
        if (appKey) {
            [ticketDict setObject:appKey forKey:@"appkey"];
        }
        
        if (_ttsAccessKeySecret) {
            [ticketDict setObject:_ttsAccessKeySecret forKey:@"accesskey"];
        }
        if (_ttsStsToken) {
            [ticketDict setObject:_ttsStsToken forKey:@"sts_token"];
        }
        
        // 设置服务URL
        NSString *serviceUrl = _ttsServiceUrl ?: _mserviceurl ?: @"wss://nls-gateway.cn-shanghai.aliyuncs.com:443/ws/v1";
        [ticketDict setObject:serviceUrl forKey:@"url"];
        
        ticket = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:ticketDict options:0 error:nil] encoding:NSUTF8StringEncoding];
    } @catch (NSException *exception) {
        NSLog(@"Generate TTS ticket exception: %@", exception.reason);
    }
    
    NSLog(@"TTS ticket: %@", ticket);
    return ticket;
}

- (NSString *)genTTSParameters {
    NSString *params = @"";
    @try {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        [dict setObject:@YES forKey:@"enable_subtitle"];
        [dict setObject:_ttsVoice ?: @"xiaoyun" forKey:@"voice"];
        [dict setObject:_ttsFormat ?: @"pcm" forKey:@"format"];
        [dict setObject:@(_ttsSampleRate > 0 ? _ttsSampleRate : 24000) forKey:@"sample_rate"];
        [dict setObject:@(_ttsVolume > 0 ? _ttsVolume : 50) forKey:@"volume"];
        [dict setObject:@(_ttsSpeechRate != 0 ? _ttsSpeechRate : 0) forKey:@"speech_rate"];
        [dict setObject:@(_ttsPitchRate != 0 ? _ttsPitchRate : 0) forKey:@"pitch_rate"];
        
        params = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:dict options:0 error:nil] encoding:NSUTF8StringEncoding];
    } @catch (NSException *exception) {
        NSLog(@"Generate TTS parameters exception: %@", exception.reason);
    }
    
    NSLog(@"TTS parameters: %@", params);
    return params;
}

#pragma mark - StreamInputTtsDelegate

- (void)onStreamInputTtsEventCallback:(StreamInputTtsCallbackEvent)event
                               taskId:(char*)taskid sessionId:(char*)sessionId
                             ret_code:(int)ret_code error_msg:(char*)error_msg
                            timestamp:(char*)timestamp all_response:(char*)all_response {
    NSLog(@"TTS event: %d, task_id: %s, ret_code: %d", event, taskid, ret_code);
    
    // 处理TTS事件，管理播放状态
    switch (event) {
        case TTS_EVENT_SYNTHESIS_STARTED:
            NSLog(@"TTS synthesis started");
            _isTTSFinishSend = NO;
            if (_ttsAudioController) {
                [_ttsAudioController startPlayer];
                _isTTSPlaying = YES;
            }
            break;
            
        case TTS_EVENT_SYNTHESIS_COMPLETE:
            NSLog(@"TTS synthesis completed");
            _isTTSFinishSend = YES;
            if (_ttsAudioController) {
                [_ttsAudioController drain];
            }
            break;
            
        case TTS_EVENT_TASK_FAILED:
            NSLog(@"TTS task failed: %s", error_msg);
            if (_ttsAudioController) {
                [_ttsAudioController drain];
                [_ttsAudioController stopPlayer];
            }
            _isTTSPlaying = NO;
            break;
            
        default:
            break;
    }
    
    // 发送事件给JS
    if (_ttsCallbackId) {
        NSDictionary *resultDict = @{
            @"type": @"tts_event",
            @"event": [NSString stringWithFormat:@"%d", event],
            @"taskId": taskid ? [NSString stringWithUTF8String:taskid] : @"",
            @"sessionId": sessionId ? [NSString stringWithUTF8String:sessionId] : @"",
            @"retCode": @(ret_code),
            @"errorMsg": error_msg ? [NSString stringWithUTF8String:error_msg] : @"",
            @"timestamp": timestamp ? [NSString stringWithUTF8String:timestamp] : @"",
            @"allResponse": all_response ? [NSString stringWithUTF8String:all_response] : @""
        };
        
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:resultDict];
        [pluginResult setKeepCallbackAsBool:YES];
        
        [self.commandDelegate sendPluginResult:pluginResult callbackId:_ttsCallbackId];
    }
}

- (void)onStreamInputTtsDataCallback:(char*)buffer len:(int)len {
    NSLog(@"TTS data received, length: %d", len);
    
    if (buffer != NULL && len > 0 && _ttsAudioController != nil) {
        NSData *data = [NSData dataWithBytes:buffer length:len];
        
        // 播放音频数据
        [self playTTSData:data];
        
        // 同时发送给JS
        if (_ttsCallbackId) {
            NSDictionary *resultDict = @{
                @"type": @"tts_data",
                @"data": [data base64EncodedStringWithOptions:0],
                @"length": @(len)
            };
            
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:resultDict];
            [pluginResult setKeepCallbackAsBool:YES];
            
            [self.commandDelegate sendPluginResult:pluginResult callbackId:_ttsCallbackId];
        }
    }
}

- (void)onStreamInputTtsLogTrackCallback:(NuiSdkLogLevel)level
                             logMessage:(const char *)log {
    NSLog(@"TTS log level:%d, message -> %s", level, log);
}

#pragma mark - AudioController Delegate

- (void)playerDidStart {
    NSLog(@"TTS player did start");
}

- (void)playerDrainDataFinish {
    NSLog(@"TTS player drain data finish");
    _isTTSPlaying = NO;
}

- (void)playerDidFinish {
    NSLog(@"TTS player did finish");
    _isTTSPlaying = NO;
    
    // 播放完毕后自动重置状态，为下一次做准备
    _isTTSRunning = NO;
    _isTTSFinishSend = NO;
    NSLog(@"TTS playback finished, state reset for next use");
}

- (void)playSoundLevel:(int)level {
    // 可以在这里处理音量变化
}

- (void)playData:(unsigned char*)buffer Length:(int)len {
    // 播放数据回调
}

#pragma mark - TTS Audio Player Methods

- (void)initTTSAudioPlayer {
    @try {
        // 使用官方Demo的AudioController
        if (_ttsAudioController == nil) {
            _ttsAudioController = [[AudioController alloc] init:only_player];
            _ttsAudioController.delegate = self;
            [_ttsAudioController setPlayerSampleRate:_ttsSampleRate];
        }
        
        _isTTSPlaying = NO;
        _isTTSFinishSend = NO;
        _shouldStopSendingTTS = NO;
        _currentTTSSessionId = @"";
        
        NSLog(@"TTS audio controller initialized successfully");
    } @catch (NSException *exception) {
        NSLog(@"TTS audio controller initialization exception: %@", exception.reason);
    }
}

- (void)playTTSData:(NSData *)data {
    @try {
        if (!_ttsAudioController) {
            NSLog(@"TTS audio controller not initialized");
            return;
        }
        
        // 如果音频数据为空，只启动播放器不播放
        if (data.length == 0) {
            if (!_isTTSPlaying) {
                [_ttsAudioController startPlayer];
                _isTTSPlaying = YES;
                NSLog(@"TTS audio player started (empty data)");
            }
            return;
        }
        
        // 写入音频数据到播放器
        [_ttsAudioController write:(const char *)data.bytes Length:(int)data.length];
        NSLog(@"TTS audio data written to controller, length: %lu", (unsigned long)data.length);
        
        // 如果播放器未播放，启动播放
        if (!_isTTSPlaying) {
            [_ttsAudioController startPlayer];
            _isTTSPlaying = YES;
            NSLog(@"TTS audio player started");
        }
    } @catch (NSException *exception) {
        NSLog(@"TTS play data exception: %@", exception.reason);
    }
}

- (void)stopTTSAudioPlayback {
    @try {
        _isTTSPlaying = NO;
        _isTTSFinishSend = NO;
        _isTTSRunning = NO; // 重置运行状态
        _shouldStopSendingTTS = YES;
        
        if (_ttsAudioController) {
            [_ttsAudioController stopPlayer];
            [_ttsAudioController cleanPlayerBuffer];
        }
        
        NSLog(@"TTS audio playback stopped and state reset");
    } @catch (NSException *exception) {
        NSLog(@"Stop TTS audio playback exception: %@", exception.reason);
    }
}

#pragma mark - Status Check Methods

- (BOOL)isInitialized {
    @try {
        BOOL initialized = (_nui != NULL);
        NSLog(@"语音识别状态检查: %@", initialized ? @"已初始化" : @"未初始化");
        return initialized;
    } @catch (NSException *exception) {
        NSLog(@"检查语音识别状态异常: %@", exception.reason);
        return NO;
    }
}

- (BOOL)isTTSInitialized {
    @try {
        BOOL initialized = _isTTSInitialized && (_ttsNui != NULL);
        NSLog(@"TTS状态检查: %@", initialized ? @"已初始化" : @"未初始化");
        return initialized;
    } @catch (NSException *exception) {
        NSLog(@"检查TTS状态异常: %@", exception.reason);
        return NO;
    }
}

@end
