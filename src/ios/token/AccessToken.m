//
//  AccessToken.m
//  NlsSdk
//
//  Created by Songsong Shao on 2018/10/29.
//  Copyright © 2018 Songsong Shao. All rights reserved.
//
#import <Foundation/Foundation.h>
#import "AccessToken.h"
#import "TokenHttpRequest.h"

@interface AccessToken(){
    TokenHttpRequest *httpRequest;
}

@end

@implementation AccessToken

NSString *accesskeyId;
NSString *accessSecret;
NSString *securityToken;

-(id)initWithAccessKeyId:(NSString *)akId andAccessSecret:(NSString *)akSecret andSecurityToken:(NSString *)stsToken {
    if ((self = [super init])) {
        accesskeyId = akId;
        accessSecret = akSecret;
        securityToken = stsToken;
    }
    httpRequest = [[TokenHttpRequest alloc]init];
    return self;
}

-(void)apply {
    [self requestToken];
}

-(void)requestToken {
    NSString *reponse = [httpRequest authorize:accesskeyId with:accessSecret andStsToken:securityToken];
    NSError *jsonError;
    NSData *objectData = [reponse dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:objectData
                                                         options:NSJSONReadingMutableContainers
                                                           error:&jsonError];
    
    _token = [[json objectForKey:@"Token"] objectForKey:@"Id"];
    _expireTime =[[[json objectForKey:@"Token"] objectForKey:@"ExpireTime"] longLongValue];
    NSLog(@"token is %@ ExpireTime is %ld",_token,_expireTime);
}

@end
