//
//  HttpReques.h
//  NlsSdk
//
//  Created by Songsong Shao on 2018/10/29.
//  Copyright 2018 Songsong Shao. All rights reserved.
//

#import <Foundation/Foundation.h>
/**
 * HTTP令牌请求类（重命名避免冲突）
 */
@interface AIPluginTokenHttpRequest : NSObject

-(NSString *)authorize:(NSString *)accessKeyId with:(NSString *)accessSecret andStsToken:(NSString *)stsToken;
@end
