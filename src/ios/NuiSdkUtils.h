//
//  Utils.h
//  NUIdemo
//
//  Created by zhouguangdong on 2019/12/26.
//  Copyright © 2019 Alibaba idst. All rights reserved.
//

#ifndef NuiSdkUtils_h
#define NuiSdkUtils_h
#ifdef DEBUG_MODE
#define TLog( s, ... ) NSLog( s, ##__VA_ARGS__ )
#else
#define TLog( s, ... )
#endif
#import <Foundation/Foundation.h>

/*
 * STS服务不可直接用于在线功能，包括一句话识别、实时识别、语音合成等。
 * 在线功能需要TOKEN，可由STS临时账号通过TOKEN工具生成，也可在服务端下发TOKEN。
 * STS服务可用于离线功能的鉴权，比如本地语音合成和唤醒。
 */
enum TokenTicketType {
    /*
     * 客户远端服务端使用STS服务获得STS临时凭证，然后下发给移动端侧，
     * 然后生成语音交互临时凭证Token。用于在线功能场景。
     */
    get_sts_access_from_server_for_online_features = 0,
    /*
     * 客户远端服务端使用STS服务获得STS临时凭证，然后下发给移动端侧，
     * 同时设置sdk_code, 用于离线功能场景。
     */
    get_sts_access_from_server_for_offline_features = 1,
    /*
     * 客户远端服务端使用STS服务获得STS临时凭证，然后下发给移动端侧，
     * 然后生成语音交互临时凭证Token。
     * 同时设置sdk_code, 用于离线在线功能混合场景。
     */
    get_sts_access_from_server_for_mixed_features = 2,
    /*
     * 客户远端服务端使用Token服务获得Token临时令牌，然后下发给移动端侧，
     * 用于在线功能场景。
     */
    get_token_from_server_for_online_features = 3,
    /*
     * 客户远端服务端将账号信息ak_id和ak_secret(请加密)下发给移动端侧，
     * 同时设置sdk_code, 用于离线功能场景。
     */
    get_access_from_server_for_offline_features = 4,
    /*
     * 客户远端服务端将账号信息ak_id和ak_secret(请加密)下发给移动端侧，
     * 然后生成语音交互临时凭证Token。
     * 同时设置sdk_code, 用于离线在线功能混合场景。
     */
    get_access_from_server_for_mixed_features = 5,
    /*
     * 客户直接使用存储在移动端侧的Token，
     * 用于在线功能场景。
     */
    get_token_in_client_for_online_features = 6,
    /*
     * 客户直接使用存储在移动端侧的ak_id和ak_secret(请加密)，
     * 同时设置sdk_code, 用于离线功能场景。
     */
    get_access_in_client_for_offline_features = 7,
    /*
     * 客户直接使用存储在移动端侧的ak_id和ak_secret(请加密)，
     * 然后生成语音交互临时凭证Token。
     * 同时设置sdk_code, 用于离线在线功能混合场景。
     */
    get_access_in_client_for_mixed_features = 8,
    /*
     * 客户直接使用存储在移动端侧的ak_id和ak_secret(请加密)，
     * 用于在线功能场景。
     */
    get_access_in_client_for_online_features = 9,
    /*
     * 客户直接使用存储在移动端侧的STS凭证，
     * 然后生成语音交互临时凭证Token。用于在线功能场景。
     */
    get_sts_access_in_client_for_online_features = 10,
    /*
     * 客户直接使用存储在移动端侧的STS凭证，
     * 同时设置sdk_code, 用于离线功能场景。
     */
    get_sts_access_in_client_for_offline_features = 11,
    /*
     * 客户直接使用存储在移动端侧的STS凭证，
     * 然后生成语音交互临时凭证Token。
     * 同时设置sdk_code, 用于离线在线功能混合场景。
     */
    get_sts_access_in_client_for_mixed_features = 12
};

typedef enum TokenTicketType TokenTicketType;

@interface NuiSdkUtils : NSObject

@property(nonatomic,assign,readwrite) NSUInteger curTokenExpiredTime;
@property(nonatomic,assign,readwrite) NSUInteger curTokenTicketType;
@property(nonatomic,strong) NSString *curAppkey;
@property(nonatomic,copy) NSString *curToken;

-(NSString *)dirDoc;

//create dir for saving files
-(NSString *)createDir;

-(void) getTicket:(NSMutableDictionary*) dict Type:(TokenTicketType)type;

-(void) getAuthTicket:(NSMutableDictionary*) dict Type:(TokenTicketType)type;

-(NSString*) getDirectIp;

-(NSString*) generateToken:(NSString*)accessKey withSecret:(NSString*)accessSecret;

- (void)refreshTokenIfNeed:(NSMutableDictionary *)json distanceExpireTime:(long)distanceExpireTime;

-(NSString*) getGuideWithError:(int)errorCode withError:(NSString*)errMesg withStatus:(NSString*)status;

-(NSArray<NSString *> *) getVoiceList:(NSString *)voiceType;

@end
#endif /* NuiSdkUtils_h */
