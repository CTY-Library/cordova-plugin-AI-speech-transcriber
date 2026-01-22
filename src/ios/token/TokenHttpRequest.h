//
//  HttpReques.h
//  NlsSdk
//
//  Created by Songsong Shao on 2018/10/29.
//  Copyright © 2018 Songsong Shao. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface TokenHttpRequest : NSObject

-(NSString *)authorize:(NSString *)accessKeyId with:(NSString *)accessSecret andStsToken:(NSString *)stsToken;
@end
