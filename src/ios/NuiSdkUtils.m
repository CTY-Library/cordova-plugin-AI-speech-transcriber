//
//  Utils.m
//  NUIdemo
//
//  Created by zhouguangdong on 2019/12/26.
//  Copyright © 2019 Alibaba idst. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NuiSdkUtils.h"
#include <netdb.h>
#include <arpa/inet.h>
#import <AdSupport/ASIdentifierManager.h>
#import "AccessToken.h"

@implementation NuiSdkUtils
//Get Document Dir
-(NSString *)dirDoc {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSLog(@"app_home_doc: %@",documentsDirectory);
    return documentsDirectory;
}

//create dir for saving files
-(NSString *)createDir {
    NSString *documentsPath = [self dirDoc];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *testDirectory = [documentsPath stringByAppendingPathComponent:@"voices"];
    NSError *error;
    if (![fileManager fileExistsAtPath:testDirectory]) {
        BOOL res = [fileManager createDirectoryAtPath:testDirectory
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:&error];
        if (!res) {
            NSLog(@"创建目录失败: %@", error.localizedDescription);
        } else {
            NSLog(@"创建目录成功: %@", testDirectory);
        }
    } else {
        NSLog(@"已存在目录: %@", testDirectory);
    }

    return testDirectory;
}

-(void) getTicket:(NSMutableDictionary*) dictM Type:(TokenTicketType)type{
    //郑重提示:
    //  语音交互服务需要先准备好账号，并开通相关服务。具体步骤请查看：
    //    https://help.aliyun.com/zh/isi/getting-started/start-here
    //
    //原始账号:
    //  账号(子账号)信息主要包括AccessKey ID(后续简称为ak_id)和AccessKey Secret(后续简称为ak_secret)。
    //  此账号信息一定不可存储在app代码中或移动端侧，以防账号信息泄露造成资费损失。
    //
    //STS临时凭证:
    //  由于账号信息下发给客户端存在泄露的可能，阿里云提供的一种临时访问权限管理服务STS(Security Token Service)。
    //  STS是由账号信息ak_id和ak_secret，通过请求生成临时的sts_ak_id/sts_ak_secret/sts_token
    //  (为了区别原始账号信息和STS临时凭证, 命名前缀sts_表示STS生成的临时凭证信息)
    //什么是STS：https://help.aliyun.com/zh/ram/product-overview/what-is-sts
    //STS SDK概览：https://help.aliyun.com/zh/ram/developer-reference/sts-sdk-overview
    //STS Python SDK调用示例：https://help.aliyun.com/zh/ram/developer-reference/use-the-sts-openapi-example
    //
    //账号需求说明:
    //  若使用离线功能(离线语音合成、唤醒), 则必须app_key、ak_id和ak_secret，或app_key、sts_ak_id、sts_ak_secret和sts_token
    //  若使用在线功能(语音合成、实时转写、一句话识别、录音文件转写等), 则只需app_key和token

    //项目创建
    //  创建appkey请查看：https://help.aliyun.com/zh/isi/getting-started/start-here
    NSString *APPKEY = @"<您申请创建的app_key>";
    [dictM setObject:APPKEY forKey:@"app_key"]; // 必填
    
    self.curTokenTicketType = type;
    self.curAppkey = APPKEY;

    if (type == get_sts_access_from_server_for_online_features) {
        //方法一，仅适合在线语音交互服务(强烈推荐):
        //  客户远端服务端使用STS服务获得STS临时凭证，然后下发给移动端侧，详情请查看：
        //    https://help.aliyun.com/document_detail/466615.html 使用其中方案二使用STS获取临时账号。
        //  然后在移动端侧通过AccessToken()获得Token和有效期，用于在线语音交互服务。
        NSString *STS_AK_ID = @"STS.<服务器生成的具有时效性的临时凭证>";
        NSString *STS_AK_SECRET = @"<服务器生成的具有时效性的临时凭证>";
        NSString *STS_TOKEN = @"<服务器生成的具有时效性的临时凭证>";
        NSString *TOKEN = @"<由STS生成的临时访问令牌>";
        TOKEN = [self generateToken:STS_AK_ID withSecret:STS_AK_SECRET withStsToken:STS_TOKEN];
        if (TOKEN == NULL) {
            NSLog(@"generate token failed");
            return;
        }
        [dictM setObject:TOKEN forKey:@"token"]; // 必填
        self.curToken = TOKEN;
    } else if (type == get_sts_access_from_server_for_offline_features) {
        //方法二，仅适合离线语音交互服务(强烈推荐):
        //  客户远端服务端使用STS服务获得STS临时凭证，然后下发给移动端侧，详情请查看：
        //    https://help.aliyun.com/document_detail/466615.html 使用其中方案二使用STS获取临时账号。
        NSString *STS_AK_ID = @"STS.<服务器生成的具有时效性的临时凭证>";
        NSString *STS_AK_SECRET = @"<服务器生成的具有时效性的临时凭证>";
        NSString *STS_TOKEN = @"<服务器生成的具有时效性的临时凭证>";
        [dictM setObject:STS_AK_ID forKey:@"ak_id"]; // 必填
        [dictM setObject:STS_AK_SECRET forKey:@"ak_secret"]; // 必填
        [dictM setObject:STS_TOKEN forKey:@"sts_token"]; // 必填
        // 离线语音合成sdk_code取值：精品版为software_nls_tts_offline， 标准版为software_nls_tts_offline_standard
        // 离线语音合成账户和sdk_code可用于唤醒
        // 由创建Appkey时设置
        NSString *sdk_code = @"software_nls_tts_offline_standard";
        [dictM setObject:sdk_code forKey:@"sdk_code"]; // 必填
    } else if (type == get_sts_access_from_server_for_mixed_features) {
        //方法三，适合离在线语音交互服务(强烈推荐):
        //  客户远端服务端使用STS服务获得STS临时凭证，然后下发给移动端侧，详情请查看：
        //    https://help.aliyun.com/document_detail/466615.html 使用其中方案二使用STS获取临时账号。
        //  然后在移动端侧通过AccessToken()获得Token和有效期，用于在线语音交互服务。
        //注意！此处介绍同一个Appkey用于在线和离线功能，用户可创建两个Appkey分别用于在线和离线功能。
        NSString *STS_AK_ID = @"STS.<服务器生成的具有时效性的临时凭证>";
        NSString *STS_AK_SECRET = @"<服务器生成的具有时效性的临时凭证>";
        NSString *STS_TOKEN = @"<服务器生成的具有时效性的临时凭证>";
        NSString *TOKEN = @"<由STS生成的临时访问令牌>";
        TOKEN = [self generateToken:STS_AK_ID withSecret:STS_AK_SECRET withStsToken:STS_TOKEN];
        if (TOKEN == NULL) {
            NSLog(@"generate token failed");
            return;
        }
        [dictM setObject:STS_AK_ID forKey:@"ak_id"]; // 必填
        [dictM setObject:STS_AK_SECRET forKey:@"ak_secret"]; // 必填
        [dictM setObject:STS_TOKEN forKey:@"sts_token"]; // 必填
        [dictM setObject:TOKEN forKey:@"token"]; // 必填
        self.curToken = TOKEN;
        // 离线语音合成sdk_code取值：精品版为software_nls_tts_offline， 标准版为software_nls_tts_offline_standard
        // 离线语音合成账户和sdk_code可用于唤醒
        // 由创建Appkey时设置
        NSString *sdk_code = @"software_nls_tts_offline_standard";
        [dictM setObject:sdk_code forKey:@"sdk_code"]; // 必填
    } else if (type == get_token_from_server_for_online_features) {
        //方法四，仅适合在线语音交互服务(推荐):
        //  客户远端服务端使用Token服务获得Token临时令牌，然后下发给移动端侧，详情请查看：
        //    https://help.aliyun.com/document_detail/466615.html 使用其中方案一获取临时令牌Token
        //  获得Token方法：
        //    https://help.aliyun.com/zh/isi/getting-started/overview-of-obtaining-an-access-token
        NSString *TOKEN = @"<服务器生成的具有时效性的临时凭证>";
        [dictM setObject:TOKEN forKey:@"token"]; // 必填
    } else if (type == get_access_from_server_for_offline_features) {
        //方法五，仅适合离线语音交互服务(不推荐):
        //  客户远端服务端将账号信息ak_id和ak_secret(请加密)下发给移动端侧。
        //注意！账号信息出现在移动端侧，存在泄露风险。
        NSString *AK_ID = @"<一定不可代码中存储和本地明文存储>";
        NSString *AK_SECRET = @"<一定不可代码中存储和本地明文存储>";

        [dictM setObject:AK_ID forKey:@"ak_id"]; // 必填
        [dictM setObject:AK_SECRET forKey:@"ak_secret"]; // 必填
        // 离线语音合成sdk_code取值：精品版为software_nls_tts_offline， 标准版为software_nls_tts_offline_standard
        // 离线语音合成账户和sdk_code可用于唤醒
        // 由创建Appkey时设置
        NSString *sdk_code = @"software_nls_tts_offline_standard";
        [dictM setObject:sdk_code forKey:@"sdk_code"]; // 必填
    } else if (type == get_access_from_server_for_mixed_features) {
        //方法六，适合离在线语音交互服务(不推荐):
        //  客户远端服务端将账号信息ak_id和ak_secret(请加密)下发给移动端侧。
        //  然后在移动端侧通过AccessToken()获得Token和有效期，用于在线语音交互服务。
        //注意！账号信息出现在移动端侧，存在泄露风险。
        NSString *AK_ID = @"<一定不可代码中存储和本地明文存储>";
        NSString *AK_SECRET = @"<一定不可代码中存储和本地明文存储>";
        NSString *TOKEN = @"<生成的临时访问令牌>";
        TOKEN = [self generateToken:AK_ID withSecret:AK_SECRET withStsToken:@""];
        if (TOKEN == NULL) {
            NSLog(@"generate token failed");
            return;
        }
        [dictM setObject:AK_ID forKey:@"ak_id"]; // 必填
        [dictM setObject:AK_SECRET forKey:@"ak_secret"]; // 必填
        [dictM setObject:TOKEN forKey:@"token"]; // 必填
        self.curToken = TOKEN;
        // 离线语音合成sdk_code取值：精品版为software_nls_tts_offline， 标准版为software_nls_tts_offline_standard
        // 离线语音合成账户和sdk_code可用于唤醒
        // 由创建Appkey时设置
        NSString *sdk_code = @"software_nls_tts_offline_standard";
        [dictM setObject:sdk_code forKey:@"sdk_code"]; // 必填
    } else if (type == get_token_in_client_for_online_features) {
        //方法七，仅适合在线语音交互服务(强烈不推荐):
        //  仅仅用于开发和调试
        //注意！账号信息出现在移动端侧，存在泄露风险。
        NSString *TOKEN = @"<移动端写死的访问令牌，仅用于调试>";
        [dictM setObject:TOKEN forKey:@"token"]; // 必填
        self.curToken = TOKEN;
    } else if (type == get_access_in_client_for_offline_features) {
        //方法八，仅适合离线语音交互服务(强烈不推荐):
        //  仅仅用于开发和调试
        //注意！账号信息出现在移动端侧，存在泄露风险。
        NSString *AK_ID = @"<移动端写死的账号信息，仅用于调试>";
        NSString *AK_SECRET = @"<移动端写死的账号信息，仅用于调试>";
        [dictM setObject:AK_ID forKey:@"ak_id"]; // 必填
        [dictM setObject:AK_SECRET forKey:@"ak_secret"]; // 必填
        // 离线语音合成sdk_code取值：精品版为software_nls_tts_offline， 标准版为software_nls_tts_offline_standard
        // 离线语音合成账户和sdk_code可用于唤醒
        // 由创建Appkey时设置
        NSString *sdk_code = @"software_nls_tts_offline_standard";
        [dictM setObject:sdk_code forKey:@"sdk_code"]; // 必填
    } else if (type == get_access_in_client_for_mixed_features) {
        //方法九，适合离在线语音交互服务(强烈不推荐):
        //  仅仅用于开发和调试
        //注意！账号信息出现在移动端侧，存在泄露风险。
        NSString *AK_ID = @"<移动端写死的账号信息，仅用于调试>";
        NSString *AK_SECRET = @"<移动端写死的账号信息，仅用于调试>";
        NSString *TOKEN = @"<生成的临时访问令牌>";
        TOKEN = [self generateToken:AK_ID withSecret:AK_SECRET withStsToken:@""];
        if (TOKEN == NULL) {
            NSLog(@"generate token failed");
            return;
        }
        [dictM setObject:AK_ID forKey:@"ak_id"]; // 必填
        [dictM setObject:AK_SECRET forKey:@"ak_secret"]; // 必填
        [dictM setObject:TOKEN forKey:@"token"]; // 必填
        self.curToken = TOKEN;
        // 离线语音合成sdk_code取值：精品版为software_nls_tts_offline， 标准版为software_nls_tts_offline_standard
        // 离线语音合成账户和sdk_code可用于唤醒
        // 由创建Appkey时设置
        NSString *sdk_code = @"software_nls_tts_offline_standard";
        [dictM setObject:sdk_code forKey:@"sdk_code"]; // 必填
    } else if (type == get_access_in_client_for_online_features) {
        //方法十，适合在线语音交互服务(强烈不推荐):
        //  仅仅用于开发和调试
        //注意！账号信息出现在移动端侧，存在泄露风险。
        NSString *AK_ID = @"<移动端写死的账号信息，仅用于调试>";
        NSString *AK_SECRET = @"<移动端写死的账号信息，仅用于调试>";
        NSString *TOKEN = @"<生成的临时访问令牌>";
        TOKEN = [self generateToken:AK_ID withSecret:AK_SECRET withStsToken:@""];
        if (TOKEN == NULL) {
            NSLog(@"generate token failed");
            return;
        }
        [dictM setObject:AK_ID forKey:@"ak_id"]; // 必填
        [dictM setObject:AK_SECRET forKey:@"ak_secret"]; // 必填
        [dictM setObject:TOKEN forKey:@"token"]; // 必填
        self.curToken = TOKEN;
    } else if (type == get_sts_access_in_client_for_online_features) {
        //方法十一，适合在线语音交互服务(强烈不推荐):
        //  仅仅用于开发和调试
        NSString *STS_AK_ID = @"STS.<移动端写死的账号信息，仅用于调试>";
        NSString *STS_AK_SECRET = @"<移动端写死的账号信息，仅用于调试>";
        NSString *STS_TOKEN = @"<移动端写死的账号信息，仅用于调试>";
        NSString *TOKEN = @"<由STS生成的临时访问令牌>";
        TOKEN = [self generateToken:STS_AK_ID withSecret:STS_AK_SECRET withStsToken:STS_TOKEN];
        if (TOKEN == NULL) {
            NSLog(@"generate token failed");
            return;
        }
        [dictM setObject:STS_AK_ID forKey:@"ak_id"]; // 必填
        [dictM setObject:STS_AK_SECRET forKey:@"ak_secret"]; // 必填
        [dictM setObject:STS_TOKEN forKey:@"sts_token"]; // 必填
        [dictM setObject:TOKEN forKey:@"token"]; // 必填
        self.curToken = TOKEN;
    } else if (type == get_sts_access_in_client_for_offline_features) {
        //方法十二，适合离线语音交互服务(强烈不推荐):
        //  仅仅用于开发和调试
        NSString *STS_AK_ID = @"STS.<移动端写死的账号信息，仅用于调试>";
        NSString *STS_AK_SECRET = @"<移动端写死的账号信息，仅用于调试>";
        NSString *STS_TOKEN = @"<移动端写死的账号信息，仅用于调试>";
        NSString *TOKEN = @"<由STS生成的临时访问令牌>";
        TOKEN = [self generateToken:STS_AK_ID withSecret:STS_AK_SECRET withStsToken:STS_TOKEN];
        if (TOKEN == NULL) {
            NSLog(@"generate token failed");
            return;
        }
        [dictM setObject:STS_AK_ID forKey:@"ak_id"]; // 必填
        [dictM setObject:STS_AK_SECRET forKey:@"ak_secret"]; // 必填
        [dictM setObject:STS_TOKEN forKey:@"sts_token"]; // 必填
        [dictM setObject:TOKEN forKey:@"token"]; // 必填
        self.curToken = TOKEN;
        // 离线语音合成sdk_code取值：精品版为software_nls_tts_offline， 标准版为software_nls_tts_offline_standard
        // 离线语音合成账户和sdk_code可用于唤醒
        // 由创建Appkey时设置
        NSString *sdk_code = @"software_nls_tts_offline_standard";
        [dictM setObject:sdk_code forKey:@"sdk_code"]; // 必填
    } else if (type == get_sts_access_in_client_for_mixed_features) {
        //方法十三，适合离在线语音交互服务(强烈不推荐):
        //  仅仅用于开发和调试
        NSString *STS_AK_ID = @"STS.<移动端写死的账号信息，仅用于调试>";
        NSString *STS_AK_SECRET = @"<移动端写死的账号信息，仅用于调试>";
        NSString *STS_TOKEN = @"<移动端写死的账号信息，仅用于调试>";
        NSString *TOKEN = @"<由STS生成的临时访问令牌>";
        TOKEN = [self generateToken:STS_AK_ID withSecret:STS_AK_SECRET withStsToken:STS_TOKEN];
        if (TOKEN == NULL) {
            NSLog(@"generate token failed");
            return;
        }
        [dictM setObject:STS_AK_ID forKey:@"ak_id"]; // 必填
        [dictM setObject:STS_AK_SECRET forKey:@"ak_secret"]; // 必填
        [dictM setObject:STS_TOKEN forKey:@"sts_token"]; // 必填
        [dictM setObject:TOKEN forKey:@"token"]; // 必填
        self.curToken = TOKEN;
        // 离线语音合成sdk_code取值：精品版为software_nls_tts_offline， 标准版为software_nls_tts_offline_standard
        // 离线语音合成账户和sdk_code可用于唤醒
        // 由创建Appkey时设置
        NSString *sdk_code = @"software_nls_tts_offline_standard";
        [dictM setObject:sdk_code forKey:@"sdk_code"]; // 必填
    }
}

-(NSString*)generateToken:(NSString*)accessKey withSecret:(NSString*)accessSecret withStsToken:(NSString*)stsToken {
    AccessToken *accessToken = [[AccessToken alloc]initWithAccessKeyId:accessKey andAccessSecret:accessSecret andSecurityToken:stsToken];
    [accessToken apply];
    long expire_time = [accessToken expireTime];
    NSLog(@"Token expire time is %ld", expire_time);
    self.curTokenExpiredTime = expire_time;
    return [accessToken token];
}

- (void)refreshTokenIfNeed:(NSMutableDictionary *)json distanceExpireTime:(long)distanceExpireTime {
    if (self.curAppkey.length > 0 && self.curToken.length > 0 && self.curTokenExpiredTime > 0) {
        long millis = (long)([[NSDate date] timeIntervalSince1970] * 1000);
        long unixTimestampInSeconds = millis / 1000;
        
        if (self.curTokenExpiredTime - distanceExpireTime < unixTimestampInSeconds) {
            NSString *oldToken = self.curToken;
            long oldExpireTime = self.curTokenExpiredTime;
            
            NSMutableDictionary *ticketJsonDict = [NSMutableDictionary dictionary];
            [self getTicket:ticketJsonDict Type:self.curTokenTicketType];
            if ([ticketJsonDict objectForKey:@"token"] != nil) {
                self.curToken = [ticketJsonDict objectForKey:@"token"];
                if ([self.curToken length] == 0) {
                    TLog(@"The 'token' key exists but the value is empty.");
                }
                [json setObject:self.curToken forKey:@"token"];
            } else {
                TLog(@"The 'token' key does not exist.");
            }
            if ([ticketJsonDict objectForKey:@"app_key"] != nil) {
                self.curAppkey = [ticketJsonDict objectForKey:@"app_key"];
                if ([self.curAppkey length] == 0) {
                    TLog(@"The 'app_key' key exists but the value is empty.");
                }
                [json setObject:self.curAppkey forKey:@"app_key"];
            } else {
                TLog(@"The 'app_key' key does not exist.");
            }
            
            NSString *newToken = self.curToken;
            long newExpireTime = self.curTokenExpiredTime;
            
            NSLog(@"Refresh old token(%@ : %ld) to (%@ : %ld).", oldToken, oldExpireTime, newToken, newExpireTime);
        }
    }
}

-(NSString*) getDirectIp {
    const int MAX_HOST_IP_LENGTH = 16;
    struct hostent *remoteHostEnt = gethostbyname("nls-gateway-inner.aliyuncs.com");
    if(remoteHostEnt == NULL) {
        NSLog(@"demo get host failed!");
    }
    struct in_addr *remoteInAddr = (struct in_addr *) remoteHostEnt->h_addr_list[0];
    //ip = inet_ntoa(*remoteInAddr);
    char ip_[MAX_HOST_IP_LENGTH];
    inet_ntop(AF_INET, (void *)remoteInAddr, ip_, MAX_HOST_IP_LENGTH);
    NSString *ip=[NSString stringWithUTF8String:ip_];
    return ip;
}

-(NSString*) getGuideWithError:(int)errorCode withError:(NSString*)errMesg withStatus:(NSString*)status {
    NSString * str = errMesg;
    switch (errorCode) {
        case 140001:
            str = @" 错误信息: 引擎未创建, 请检查是否成功初始化, 详情可查看运行日志.";
            break;
        case 140008:
            str = @" 错误信息: 鉴权失败, 请关注日志中详细失败原因.";
            break;
        case 140011:
            str = @" 错误信息: 当前方法调用不符合当前状态, 比如在未初始化情况下调用pause接口.";
            break;
        case 140013:
            str = @" 错误信息: 当前方法调用不符合当前状态, 比如在未初始化情况下调用pause/release等接口.";
            break;
        case 140900:
            str = @" 错误信息: tts引擎初始化失败, 请检查资源路径和资源文件是否正确.";
            break;
        case 140901:
            str = @" 错误信息: tts引擎初始化失败, 请检查使用的SDK是否支持离线语音合成功能.";
            break;
        case 140903:
            str = @" 错误信息: tts引擎任务创建失败, 请检查资源路径和资源文件是否正确.";
            break;
        case 140908:
            str = @" 错误信息: 发音人资源无法获得正确采样率, 请检查发音人资源是否正确.";
            break;
        case 140910:
            str = @" 错误信息: 发音人资源路径无效, 请检查发音人资源文件路径是否正确.";
            break;
        case 144002:
            str = @" 错误信息: 若发生于语音合成, 可能为传入文本超过16KB. 可升级到最新版本, 具体查看日志确认.";
            break;
        case 144003:
            str = @" 错误信息: token过期或无效, 请检查token是否有效.";
            break;
        case 144004:
            str = @" 错误信息: 语音合成超时, 具体查看日志确认.";
            break;
        case 144006:
            str = @" 错误信息: 云端返回未分类错误, 请看详细的错误信息.";
            break;
        case 144103:
            str = @" 错误信息: 设置参数无效, 请参考接口文档检查参数是否正确, 也可通过task_id咨询客服.";
            break;
        case 144500:
            str = @" 错误信息: 流式TTS状态错误, 可能是在停止状态调用接口.";
            break;
        case 170008:
            str = @" 错误信息: 鉴权成功, 但是存储鉴权信息的文件路径不存在或无权限.";
            break;
        case 170806:
            str = @" 错误信息: 请设置SecurityToken.";
            break;
        case 170807:
            str = @" 错误信息: SecurityToken过期或无效, 请检查SecurityToken是否有效.";
            break;
        case 240002:
            str = @" 错误信息: 设置的参数不正确, 比如设置json参数格式不对, 设置的文件无效等.";
            break;
        case 240005:
            if ([status isEqualToString:@"init"]) {
                str = @" 错误信息: 请检查appkey、akId、akSecret、url等初始化参数是否无效或空.";
            } else {
                str = @" 错误信息: 传入参数无效, 请检查参数正确性.";
            }
            break;
        case 240008:
            str = @" 错误信息: SDK内部核心引擎未成功初始化.";
            break;
        case 240011:
            str = @" 错误信息: SDK未成功初始化.";
            break;
        case 240040:
            str = @" 错误信息: 本地引擎初始化失败，可能是资源文件(如kws.bin)损坏，或者内存不足等.";
            break;
        case 240052:
            str = @" 错误信息: 2s未传入音频数据，请检查录音相关代码、权限或录音模块是否被其他应用占用.";
            break;
        case 240063:
            str = @" 错误信息: SSL错误，可能为SSL建连失败。比如token无效或者过期，或SSL证书校验失败(可升级到最新版)等等，具体查日志确认.";
            break;
        case 240068:
            str = @" 错误信息: 403 Forbidden, token无效或者过期.";
            break;
        case 240070:
            str = @" 错误信息: 鉴权失败, 请查看日志确定具体问题, 特别是关注日志 E/iDST::ErrMgr: errcode=.";
            break;
        case 240072:
            str = @" 错误信息: 录音文件识别传入的录音文件不存在.";
            break;
        case 240073:
            str = @" 错误信息: 录音文件识别传入的参数错误, 比如audio_address不存在或file_path不存在或其他参数错误.";
            break;
        case 10000016:
            if ([status rangeOfString:@"403 Forbidden"].location != NSNotFound) {
                str = @" 错误信息: 流式语音合成未成功连接服务, 请检查设置的账号临时凭证.";
            } else if ([status rangeOfString:@"404 Forbidden"].location != NSNotFound) {
                str = @" 错误信息: 流式语音合成未成功连接服务, 请检查设置的服务地址URL.";
            } else {
                str = @" 错误信息: 流式语音合成未成功连接服务, 请检查设置的参数及服务地址.";
            }
            break;
        case 40000004:
            str = @" 错误信息: 长时间未收到指令或音频.";
            break;
        case 40000010:
            if ([errMesg rangeOfString:@"FREE_TRIAL_EXPIRED"].location != NSNotFound) {
                str = @" 错误信息: 此账号试用期已过, 请开通商用版或检查账号权限.";
            } else {
                str = errMesg;
            }
            break;
        case 41010105:
            str = @" 错误信息: 长时间未收到人声, 触发静音超时.";
            break;
        case 999999:
            str = @" 错误信息: 库加载失败, 可能是库不支持当前服务, 或库加载时崩溃, 可详细查看日志判断.";
            break;
        default:
            str = errMesg;
    }

    return str;
}

- (NSArray<NSString *> *)getVoiceList:(NSString *)voiceType {
    if ([voiceType isEqualToString:@"SambertTts"]) {
        return @[
            @"sambert-zhinan-v1;知楠;广告男声;中英文;48000",
            @"sambert-zhiqi-v1;知琪;温柔女声;中英文;48000",
            @"sambert-zhichu-v1;知厨;舌尖男声;中英文;48000",
            @"sambert-zhide-v1;知德;新闻男声;中英文;48000",
            @"sambert-zhijia-v1;知佳;标准女声;中英文;48000",
            @"sambert-zhiru-v1;知茹;新闻女声;中英文;48000",
            @"sambert-zhiqian-v1;知倩;资讯女声;中英文;48000",
            @"sambert-zhixiang-v1;知祥;磁性男声;中英文;48000",
            @"sambert-zhiwei-v1;知薇;萝莉女声;中英文;48000",
            @"sambert-zhihao-v1;知浩;咨询男声;中英文;16000",
            @"sambert-zhijing-v1;知婧;严厉女声;中英文;16000",
            @"sambert-zhiming-v1;知茗;诙谐男声;中英文;16000",
            @"sambert-zhimo-v1;知墨;情感男声;中英文;16000",
            @"sambert-zhina-v1;知娜;浙普女声;中英文;16000",
            @"sambert-zhishu-v1;知树;资讯男声;中英文;16000",
            @"sambert-zhistella-v1;知莎;知性女声;中英文;16000",
            @"sambert-zhiting-v1;知婷;电台女声;中英文;16000",
            @"sambert-zhixiao-v1;知笑;资讯女声;中英文;16000",
            @"sambert-zhiya-v1;知雅;严厉女声;中英文;16000",
            @"sambert-zhiye-v1;知晔;青年男声;中英文;16000",
            @"sambert-zhiying-v1;知颖;软萌童声;中英文;16000",
            @"sambert-zhiyuan-v1;知媛;知心姐姐;中英文;16000",
            @"sambert-zhiyue-v1;知悦;温柔女声;中英文;16000",
            @"sambert-zhigui-v1;知柜;直播女声;中英文;16000",
            @"sambert-zhishuo-v1;知硕;自然男声;中英文;16000",
            @"sambert-zhimiao-emo-v1;知妙(多情感);阅读产品简介数字人直播;中英文;16000",
            @"sambert-zhimao-v1;知猫;直播女声;中英文;16000",
            @"sambert-zhilun-v1;知伦;悬疑解说;中英文;16000",
            @"sambert-zhifei-v1;知飞;激昂解说;中英文;16000",
            @"sambert-zhida-v1;知达;标准男声;中英文;16000",
            @"sambert-camila-v1;Camila;西班牙语女声;西班牙语;16000",
            @"sambert-perla-v1;Perla;意大利语女声;意大利语;16000",
            @"sambert-indah-v1;Indah;印尼语女声;印尼语;16000",
            @"sambert-clara-v1;Clara;法语女声;法语;16000",
            @"sambert-hanna-v1;Hanna;德语女声;德语;16000",
            @"sambert-beth-v1;Beth;咨询女声;美式英文;16000",
            @"sambert-betty-v1;Betty;客服女声;美式英文;16000",
            @"sambert-cally-v1;Cally;自然女声;美式英文;16000",
            @"sambert-cindy-v1;Cindy;对话女声;美式英文;16000",
            @"sambert-eva-v1;Eva;陪伴女声;美式英文;16000",
            @"sambert-donna-v1;Donna;教育女声;美式英文;16000",
            @"sambert-brian-v1;Brian;客服男声;美式英文;16000",
            @"sambert-waan-v1;Waan;泰语女声;泰语;16000",
            @"<更多音色请查看官网列表>"
        ];
    }
    
    else if ([voiceType isEqualToString:@"CosyVoiceV3"] || [voiceType isEqualToString:@"cosyvoice-v3"]) {
        return @[
            /* 童声（标杆音色） */
            @"longhuohuo_v3-龙火火;桀骜不驯男童;中英文", /*若有语音服务业务对接人，请直接联系其申请开通；否则请提交工单申请*/
            @"longhuhu_v3-龙呼呼;天真烂漫女童;中英文", /*若有语音服务业务对接人，请直接联系其申请开通；否则请提交工单申请*/
            /* 方言（标杆音色） */
            @"longchuanshu_v3-龙川叔;油腻搞笑叔;中英文", /*若有语音服务业务对接人，请直接联系其申请开通；否则请提交工单申请*/
            @"<更多音色请查看官网列表>"
        ];
    }
    
    else if ([voiceType isEqualToString:@"cosyvoice-v3-plus"]) {
        return @[
            @"<目前只能使用克隆音色, 详细请见官网说明>"
        ];
    }
    
    else if ([voiceType isEqualToString:@"CosyVoiceV2"] || [voiceType isEqualToString:@"cosyvoice-v2"]) {
        return @[
            /* 语音助手 */
            @"longyumi_v2-YUMI;正经青年女;中英文",
            @"longxiaochun_v2-龙小淳;知性积极女;中英文",
            @"longxiaoxia_v2-龙小夏;沉稳权威女;中英文",
            /* 童声（标杆音色） */
            @"longhuohuo-龙火火;桀骜不驯男童;中英文", /*若有语音服务业务对接人，请直接联系其申请开通；否则请提交工单申请*/
            @"longhuhu-龙呼呼;天真烂漫女童;中英文", /*若有语音服务业务对接人，请直接联系其申请开通；否则请提交工单申请*/
            /* 方言（标杆音色） */
            @"longchuanshu-龙川叔;油腻搞笑叔;中英文", /*若有语音服务业务对接人，请直接联系其申请开通；否则请提交工单申请*/
            /* 消费电子-教育培训 */
            @"longanpei-龙安培;青少年教师女;中英文", /*若有语音服务业务对接人，请直接联系其申请开通；否则请提交工单申请*/
            /* 消费电子-儿童陪伴 */
            @"longwangwan-龙汪汪;台湾少年音;中英文", /*若有语音服务业务对接人，请直接联系其申请开通；否则请提交工单申请*/
            @"longpaopao-龙泡泡;飞天泡泡音;中英文", /*若有语音服务业务对接人，请直接联系其申请开通；否则请提交工单申请*/
            /* 消费电子-儿童有声书 */
            @"longshanshan-龙闪闪;戏剧化童声;中英文", /*若有语音服务业务对接人，请直接联系其申请开通；否则请提交工单申请*/
            @"longniuniu-龙牛牛;阳光男童声;中英文", /*若有语音服务业务对接人，请直接联系其申请开通；否则请提交工单申请*/
            /* 短视频配音 */
            @"longdaiyu-龙黛玉;娇率才女音;中英文", /*若有语音服务业务对接人，请直接联系其申请开通；否则请提交工单申请*/
            @"longgaoseng-龙高僧;得道高僧音;中英文", /*若有语音服务业务对接人，请直接联系其申请开通；否则请提交工单申请*/
            /* 客服 */
            @"longyingmu-龙应沐;优雅知性女;中英文",
            @"longyingxun-龙应询;年轻青涩男;中英文",
            @"longyingcui-龙应催;严肃催收男;中英文",
            @"longyingda-龙应答;开朗高音女;中英文",
            @"longyingjing-龙应静;低调冷静女;中英文",
            @"longyingyan-龙应严;义正严辞女;中英文",
            @"longyingtian-龙应甜;温柔甜美女;中英文",
            @"longyingbing-龙应冰;尖锐强势女;中英文",
            @"longyingtao-龙应桃;温柔淡定女;中英文",
            @"longyingling-龙应聆;温和共情女;中英文",
            /* 直播带货 */
            @"longanran-龙安燃;活泼质感女;中英文",
            @"longanxuan-龙安宣;经典直播女;中英文",
            @"longanchong-龙安冲;激情推销男;中英文", /*若有语音服务业务对接人，请直接联系其申请开通；否则请提交工单申请*/
            @"longanping-龙安萍;高亢直播女;中英文", /*若有语音服务业务对接人，请直接联系其申请开通；否则请提交工单申请*/
            /* 有声书 */
            @"longbaizhi-龙白芷;睿气旁白女;中英文", /*若有语音服务业务对接人，请直接联系其申请开通；否则请提交工单申请*/
            @"longsanshu-龙三叔;沉稳质感男;中英文",
            @"longxiu_v2-龙修;博才说书男;中英文",
            @"longmiao_v2-龙妙;抑扬顿挫女;中英文",
            @"longyue_v2-龙悦;温暖磁性女;中英文",
            @"longnan_v2-龙楠;睿智青年男;中英文",
            @"longyuan_v2-龙媛;温暖治愈女;中英文",
            /* 社交陪伴 */
            @"longanrou-龙安柔;温柔闺蜜女;中英文",
            @"longqiang_v2-龙嫱;浪漫风情女;中英文",
            @"longhan_v2-龙寒;温暖痴情男;中英文",
            @"longxing_v2-龙星;温婉邻家女;中英文",
            @"longhua_v2-龙华;元气甜美女;中英文",
            @"longwan_v2-龙婉;积极知性女;中英文",
            @"longcheng_v2-龙橙;智慧青年男;中英文",
            @"longfeifei_v2-龙菲菲;甜美娇气女;中英文",
            @"longxiaocheng_v2-龙小诚;磁性低音男;中英文",
            @"longzhe_v2-龙哲;呆板大暖男;中英文",
            @"longyan_v2-龙颜;温暖春风女;中英文",
            @"longtian_v2-龙天;磁性理智男;中英文",
            @"longze_v2-龙泽;温暖元气男;中英文",
            @"longshao_v2-龙邵;积极向上男;中英文",
            @"longhao_v2-龙浩;多情忧郁男;中英文",
            @"kabuleshen_v2-龙深;实力歌手男;中英文",
            /* 童声 */
            @"longjielidou_v2-龙杰力豆;阳光顽皮男;中英文",
            @"longling_v2-龙铃;稚气呆板女;中英文",
            @"longke_v2-龙可;懵懂乖乖女;中英文",
            @"longxian_v2-龙仙;豪放可爱女;中英文",
            /* 方言 */
            @"longlaotie_v2-龙老铁;东北直率男;中英文",
            @"longjiayi_v2-龙嘉怡;知性粤语女;中英文",
            @"longtao_v2-龙桃;积极粤语女;中英文",
            /* 诗词朗诵 */
            @"longfei_v2-龙飞;热血磁性男;中英文",
            @"libai_v2-李白;古代诗仙男;中英文",
            @"longjin_v2-龙津;优雅温润男;中英文",
            /* 新闻播报 */
            @"longshu_v2-龙书;沉稳青年男;中英文",
            @"loongbella_v2-Bella2.0;精准干练女;中英文",
            @"longshuo_v2-龙硕;博才干练男;中英文",
            @"longxiaobai_v2-龙小白;沉稳播报女;中英文",
            @"longjing_v2-龙婧;典型播音女;中英文",
            @"loongstella_v2-loongstella;飒爽利落女;中英文",
            /* 出海营销 */
            @"loongeva_v2-loongeva;知性英文女;英文",
            @"loongbrian_v2-loongbrian;沉稳英文男;英文",
            @"loongabby_v2-loongabby;美式英文女;英文",
            @"loongkyong_v2-loongkyong;韩语女;韩语",
            @"loongtomoka_v2-loongtomoka;日语女;日语",
            @"loongtomoya_v2-loongtomoya;日语男;日语",
            @"<更多音色请查看官网列表>"
        ];
    }
    
    else if ([voiceType isEqualToString:@"CosyVoiceV1"] || [voiceType isEqualToString:@"cosyvoice-v1"]) {
        return @[
            @"longwan-龙婉;聊天数字人;中文普通话",
            @"longcheng-龙橙;聊天数字人;中文普通话",
            @"longhua-龙华;聊天数字人;中文普通话",
            @"longxiaochun-龙小淳;聊天数字人;中英文",
            @"longxiaoxia-龙小夏;聊天数字人;中文普通话",
            @"longxiaocheng-龙小诚;聊天数字人;中英文",
            @"longxiaobai-龙小白;聊天数字人;中文普通话",
            @"longlaotie-龙老铁;新闻播报;东北口音",
            @"longshu-龙书;智能客服;中文普通话",
            @"longshuo-龙硕;语音助手;中文普通话",
            @"longjing-龙婧;语音助手;中文普通话",
            @"longmiao-龙妙;语音助手;中文普通话",
            @"longyue-龙悦;语音助手;中文普通话",
            @"longyuan-龙媛;聊天数字人;中文普通话",
            @"longfei-龙飞;有声书;中文普通话",
            @"longjielidou-龙杰力豆;聊天助手;中文普通话+英文",
            @"longtong-龙彤;聊天数字人;中文普通话",
            @"longxiang-龙祥;新闻播报;中文普通话",
            @"loongstella-Stella;语音助手;中文普通话+英文",
            @"loongbella-Bella;语音助手;中文普通话",
            @"<更多音色请查看官网列表>"
        ];
    }
    
    else if ([voiceType isEqualToString:@"StreamInputTts"]) {
        return @[
            @"longcheng_v2-龙橙;阳光男声;中英文",
            @"longhua_v2-龙华;活泼女童;中英文",
            @"abin-阿斌;广东普通话;中英文",
            @"zhixiaobai-知小白;普通话女声;中英文",
            @"zhixiaoxia-知小夏;普通话女声;中英文",
            @"zhixiaomei-知小妹;普通话女声;中英文",
            @"zhigui-知柜;普通话女声;中英文",
            @"zhishuo-知硕;普通话男声;中英文",
            @"aixia-艾夏;普通话女声;中英文",
            @"cally-Cally;美式英文女声;英文",
            @"zhifeng_emo-知锋_多情感;多种情感男声;中英文",
            @"zhibing_emo-知冰_多情感;多种情感男声;中英文",
            @"ninger-宁儿;标准女声;中文",
            @"ruilin-瑞琳;标准女声;中文",
            @"aina-艾娜;浙普女声;中文",
            @"yina-伊娜;浙普女声;中文",
            @"sitong-思彤;儿童音;中文",
            @"xiaobei-小北;萝莉女声;中文",
            @"harry-Harry;英音男声;英文",
            @"abby-Abby;美音女声;英文",
            @"shanshan-姗姗;粤语女声;粤英文",
            @"chuangirl-小玥;四川话女声;中英文",
            @"qingqing-青青;中国台湾话女声;中文",
            @"cuijie-翠姐;东北话女声;中文",
            @"xiaoze-小泽;湖南重口音男声;中文",
            @"tomoka-智香;日语女声;日文",
            @"tomoya-智也;日语男声;日文",
            @"indah-Indah;印尼语女声;印尼语",
            @"farah-Farah;马来语女声;马来语",
            @"tala-Tala;菲律宾语女声;菲律宾语",
            @"tien-Tien;越南语女声;越南语",
            @"Kyong-Kyong;韩语女声;韩语",
            @"masha-masha;俄语女声;俄语",
            @"camila-camila;西班牙语女声;西班牙语",
            @"perla-perla;意大利语女声;意大利语",
            @"kelly-Kelly;香港粤语女声;香港粤语",
            @"clara-clara;法语女声;法语",
            @"hanna-hanna;德语女声;德语",
            @"waan-waan;泰语女声;泰语",
            @"eva_ecmix-eva_ecmix;美式英文女声;英中文",
            @"longchen-龙臣;译制片男声;中英文",
            @"longxiong-龙熊;译制片男声;中英文",
            @"longyu-龙玉;御姐女声;中英文",
            @"longjiao-龙娇;御姐女声;中英文",
            @"longmei-龙玫;温柔女声;中英文",
            @"longgui-龙瑰;温柔女声;中英文",
            @"longping-龙乒;体育解说男声;中英文",
            @"longpang-龙乓;体育解说男声;中英文",
            @"longwu-龙无;无厘头男声;中英文",
            @"longqi-龙奇;活泼童声;中英文",
            @"longxian_normal-龙仙;阳光女声;中英文",
            @"longfeifei-龙菲;成熟女声;中英文",
            @"longxiu-龙修;青年男声;中英文",
            @"longdachui-龙大锤;幽默男声;中英文",
            @"longjiajia-龙佳佳;亲和女声;中英文",
            @"longjiayi-龙嘉怡;粤语女声;中英文",
            @"longtao-龙桃;粤语女声;中英文",
            @"longjiaxin-龙嘉欣;粤语女声;中英文",
            @"longcheng-龙橙;阳光男声;中英文",
            @"longzhe-龙哲;成熟男声;中英文",
            @"longnan-龙楠;青年男声;中英文",
            @"longyan-龙颜;亲切女声;中英文",
            @"longqiang-龙嫱;慵懒女声;中英文",
            @"longhua-龙华;活泼女童;中英文",
            @"longxing-龙星;暖心女声;中英文",
            @"longjin-龙津;青年男声;中英文",
            @"longhan-龙寒;青年男声;中英文",
            @"longtian-龙天;霸总男声;中英文",
            @"longshuo-龙硕;沉稳男声;中英文",
            @"loongstella-Stella2.0;飒爽女声;中英文",
            @"longxiaocheng-龙小诚;气质大叔;中英文",
            @"longxiaoxia-龙小夏;温柔女声;中英文",
            @"longxiaochun-龙小淳;温柔姐姐;中英文",
            @"longxiaobai-龙小白;闲聊女声;中英文",
            @"longlaotie-龙老铁;东北男声;中英文",
            @"longyue-龙悦;评书女声;中英文",
            @"loongbella-Bella2.0;新闻女声;中英文",
            @"longshu-龙书;新闻男声;中英文",
            @"longjing-龙婧;严肃女声;中英文",
            @"longmiao-龙妙;气质女声;中英文",
            @"libai-龙老李;普通话男声;中英文",
            @"longwan-龙婉;普通话女声;中英文",
            @"longke-龙可;活泼女童;中英文",
            @"longling-龙铃;活泼女童;中英文",
            @"longshao-龙绍;活力男声;中英文",
            @"longze-龙泽;阳光男声;中英文",
            @"longhao-龙浩;温暖男声;中英文"
        ];
    }
    
    else if ([voiceType isEqualToString:@"NlsTts"]) {
        return @[
            @"aiqi-艾琪;温柔女声;中英文",
            @"aijia-艾佳;标准女声;中英文",
            @"aicheng-艾诚;标准男声;中英文",
            @"aida-艾达;标准男声;中英文",
            @"aiya-艾雅;严厉女声;中英文",
            @"aixia-艾夏;亲和女声;中英文",
            @"aimei-艾美;甜美女声;中英文",
            @"aiyu-艾雨;自然女声;中英文",
            @"aiyue-艾悦;温柔女声;中英文",
            @"aijing-艾婧;严厉女声;中英文",
            @"aina-艾娜;浙普女声;中文",
            @"aitong-艾彤;儿童音;中文",
            @"aiwei-艾薇;萝莉女声;中文",
            @"aibao-艾宝;萝莉女声;中文",
            @"abby-Abby;美音女声;英文",
            @"andy-Andy;美音男声;英文",
            @"aifei-艾飞;激昂解说;中文",
            @"ava-ava;美语女声;英文",
            @"ailun-艾伦;悬疑解说;中英文",
            @"aishuo-艾硕;自然男声;中英文",
            @"annie-Annie;美语女声;英文",
            @"aikan-艾侃;天津话男声;中文",
            @"becca-Becca;美语客服女声;英文",
            @"cuijie-翠姐;东北话女声;中文",
            @"chuangirl-小玥;四川话女声;中文",
            @"dahu-大虎;东北话男声;中文",
            @"eric-Eric;英音男声;英文",
            @"emily-Emily;英音女声;英文",
            @"farah-Farah;马来语女声;马来语",
            @"harry-Harry;英音男声;英文",
            @"indah-Indah;印尼语女声;印尼语",
            @"jiajia-佳佳;粤语女声;粤英",
            @"jielidou-杰力豆;治愈童声;中文",
            @"kenny-Kenny;沉稳男声;中英文",
            @"Kyong-Kyong;韩语女声;韩语",
            @"luna-Luna;英音女声;英文",
            @"luca-Luca;英音男声;英文",
            @"lydia-Lydia;英中双语女声;中英文",
            @"laotie-老铁;东北老铁;中文",
            @"laomei-老妹;吆喝女声;中文",
            @"maoxiaomei-猫小美;活力女声;中英文",
            @"mashu-马树;儿童剧男声;中英文",
            @"masha-masha;俄语女声;俄语",
            @"ninger-宁儿;标准女声;中文",
            @"olivia-Olivia;英音女声;英文",
            @"qingqing-青青;中国台湾话女声;中文",
            @"guijie-柜姐;亲切女声;中英文",
            @"qiaowei-巧薇;卖场广播;中英文",
            @"rosa-Rosa;自然女声;中英文",
            @"ruilin-瑞琳;标准女声;中文",
            @"ruoxi-若兮;温柔女声;中英文",
            @"siqi-思琪;温柔女声;中英文",
            @"sijia-思佳;标准女声;中英文",
            @"sicheng-思诚;标准男声;中英文",
            @"siyue-思悦;温柔女声;中英文",
            @"sijing-思婧;严厉女声;中文",
            @"sitong-思彤;儿童音;中文",
            @"shanshan-姗姗;粤语女声;粤语",
            @"stella-Stella;知性女声;中英文",
            @"stanley-Stanley;沉稳男声;中英文",
            @"tomoka-智香;日语女声;日语",
            @"tomoya-智也;日语男声;日语",
            @"taozi-桃子;粤语女声;粤语",
            @"tala-Tala;菲律宾语女声;菲律宾语",
            @"tien-Tien;越南语女声;越南语",
            @"wendy-Wendy;英音女声;英文",
            @"william-William;英音男声;英文",
            @"xiaomei-小美;甜美女声;中英文",
            @"xiaobei-小北;萝莉女声;中文",
            @"xiaoze-小泽;湖南重口音男声;中文",
            @"xiaoxian-小仙;亲切女声;中英文",
            @"xiaoyun-小云;标准女声;中英文",
            @"xiaogang-小刚;标准男声;中英文",
            @"yina-伊娜;浙普女声;中文",
            @"yuer-悦儿;儿童剧女声;中文",
            @"yaqun-亚群;卖场广播;中英文",
            @"zhimiao_emo-知妙_多情感;多种情感女声;中英文",
            @"zhimi_emo-知米_多情感;多种情感女声;中英文",
            @"zhiyan_emo-知燕_多情感;多种情感女声;中英文",
            @"zhibei_emo-知贝_多情感;多种情感女声;中英文",
            @"zhitian_emo-知甜_多情感;多种情感女声;中英文"
        ];
    }
    
    return @[];
}
@end
