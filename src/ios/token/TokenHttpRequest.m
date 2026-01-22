//
//  TokenHttpRequest.m
//  NlsSdk
//
//  Created by Songsong Shao on 2018/10/29.
//  Copyright © 2018 Songsong Shao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonDigest.h>
#import "TokenHttpRequest.h"

static NSString *HEADER_ACCEPT = @"Accept";
static NSString *url = @"nls-meta.cn-shanghai.aliyuncs.com";
static NSString *method = @"GET";
static NSString *accept = @"application/json";
static NSString *action = @"CreateToken";
static NSString *regionId = @"cn-shanghai";
static NSString *version = @"2019-02-28";
static NSString *signatureVersion = @"1.0";

@interface TokenHttpRequest(){

}
@end

@implementation TokenHttpRequest

NSString *dateTime = nil;

-(id)init {
    self = [super init];
    return self;
}

- (NSString *)authorize:(NSString *)accessKeyId with:(NSString *)accessSecret andStsToken:(NSString *)stsToken {
    __block NSString *resultString = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    @autoreleasepool {
        dateTime = [self getCurrentISO8601UTCDateString];
        NSUUID *uuid = [NSUUID UUID];
        NSString *uuidString = [uuid UUIDString];

        // 创建包含所有查询参数的字典
        NSDictionary *params = @{
            @"AccessKeyId": accessKeyId,
            @"Action": action,
            @"Format": @"JSON",
            @"RegionId": regionId,
            @"SignatureMethod": @"HMAC-SHA1",
            @"SignatureVersion": signatureVersion,
            @"SignatureNonce":uuidString,
            @"Timestamp": dateTime,
            @"Version": version
        };

        // 如果是STS鉴权，则添加security token
        NSMutableDictionary *params2 = [params mutableCopy];
        if (stsToken != nil && [stsToken length] > 0) {
            [params2 setObject:stsToken forKey:@"SecurityToken"];
        }

        // 将 NSMutableDictionary 转换为 NSDictionary
        NSDictionary *queryParams = [NSDictionary dictionaryWithDictionary:params2];

        // 生成规范化的查询字符串
        NSString *queryString = canonicalizedQuery(queryParams);
        // 构造签名字符串
        NSString *stringToSign = createStringToSign(method, @"/", queryString);
        // 生成 HMAC-SHA1 签名并进行 Base64 编码后 URL 编码
        NSString *signature = generateSignature(stringToSign, [accessSecret stringByAppendingString:@"&"]);
        NSString *queryStringWithSign = [NSString stringWithFormat:@"Signature=%@&%@", signature, queryString];

        // 发送 GET 请求并处理响应
        processGETRequest(queryStringWithSign, ^(NSString *result) {
            if (result) {
                NSLog(@"Received Token: %@", result);
                resultString = result; // 设置 resultString
            } else {
                NSLog(@"Failed to receive token or error occurred.");
            }
            dispatch_semaphore_signal(semaphore);
        });

        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    }
    return resultString;
}

NSString *generateSignature(NSString *stringToSign, NSString *accessKeySecret) {
    const char *cKey = [accessKeySecret UTF8String];
    const char *cData = [stringToSign UTF8String];
    unsigned char cHMAC[CC_SHA1_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA1, cKey, strlen(cKey), cData, strlen(cData), cHMAC);
    NSData *HMACData = [NSData dataWithBytes:cHMAC length:sizeof(cHMAC)];
    NSString *base64String = [HMACData base64EncodedStringWithOptions:0];
    return URLEncode(base64String);
}

// Helper Functions
NSString *URLEncode(NSString *value) {
    NSString *encodedString = [(NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)value, NULL, (CFStringRef)@"!*'\"();:@&=+$,/?%#[]% ", kCFStringEncodingUTF8)) stringByReplacingOccurrencesOfString:@"+" withString:@"%20"];
    encodedString = [encodedString stringByReplacingOccurrencesOfString:@"*" withString:@"%2A"];
    encodedString = [encodedString stringByReplacingOccurrencesOfString:@"%7E" withString:@"~"];
    return encodedString;
}

// Generate canonicalized query
NSString *canonicalizedQuery(NSDictionary *queryParams) {
    NSArray *sortedKeys = [[queryParams allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *queryStringComponents = [NSMutableArray array];
    for (NSString *key in sortedKeys) {
        NSString *encodedKey = URLEncode(key);
        NSString *encodedValue = URLEncode([queryParams objectForKey:key]);
        [queryStringComponents addObject:[NSString stringWithFormat:@"%@=%@", encodedKey, encodedValue]];
    }
    return [queryStringComponents componentsJoinedByString:@"&"];
}

// Create signature string
NSString *createStringToSign(NSString *method, NSString *urlPath, NSString *queryString) {
    return [NSString stringWithFormat:@"%@&%@&%@", method, URLEncode(urlPath), URLEncode(queryString)];
}

// Make GET request
void processGETRequest(NSString *queryString, void (^completionHandler)(NSString *resultString)) {
    NSString *urlString = [NSString stringWithFormat:@"https://%@?%@", url, queryString];
    NSLog(@"request url is: %@", urlString);
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];
    [request setValue:accept forHTTPHeaderField:HEADER_ACCEPT];

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"Error: %@", error);
            if (completionHandler) {
                NSString *error_string = error.localizedDescription;
                completionHandler(error_string); // Pass nil in case of error
            }
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (completionHandler) {
            completionHandler(result); // Pass nil in case of failure
        }
        if ([httpResponse statusCode] != 200) {
            return;
        }
    }];
    [task resume];
}

-(NSString *)getCurrentISO8601UTCDateString {
    // 创建并配置 NSDateFormatter 实例
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];

    // 设置时区为 UTC
    [dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    // 获取当前日期
    NSDate *currentDate = [NSDate date];
    // 将 NSDate 对象格式化为指定的字符串格式
    NSString *dateString = [dateFormatter stringFromDate:currentDate];

    return dateString;
}

@end
