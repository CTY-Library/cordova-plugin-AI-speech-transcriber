//
//  NLSPlayAudio.h
//  AliyunNlsClientSample
//
//  Created by 刘方 on 2/25/16.
//  Copyright © 2016 阿里巴巴. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#define DEBUG_MODE
#ifdef DEBUG_MODE
#define TLog( s, ... ) NSLog( s, ##__VA_ARGS__ )
#else
#define TLog( s, ... )
#endif

#define EVERY_READ_LENGTH 200
#define NUM_BUFFERS 3
#define QUEUE_BUFFER_SIZE 640
enum PlayerState {
    idle = 0,
    starting = 1,
    playing = 2,
    paused = 3,
    stopped = 4,
    draining = 5,
};
typedef enum PlayerState PlayerState;

/**
 *@discuss NLSPlayAudio 回调接口
 */
@protocol NlsPlayerDelegate <NSObject>
/**
 * @Player数据完成播放回调
 */
-(void) playerDidFinish;
@end


@interface NLSPlayAudio : NSObject {
    //音频参数
    AudioStreamBasicDescription audioDescription;
    // 音频播放队列
    AudioQueueRef audioQueue;
    // 音频缓存
    AudioQueueBufferRef audioQueueBuffers[QUEUE_BUFFER_SIZE];
}
@property(nonatomic,assign) id<NlsPlayerDelegate> delegate;

-(void)play;
-(void)pause;
-(void)resume;
-(void)stop;
-(void)drain;
-(void)cleanup;
-(void)setstate :(PlayerState)state;
-(void)setsamplerate :(int)sr;
-(int)write:(const char*)buffer Length:(int)len;
-(int)getAudioData:(AudioQueueBufferRef)buffer;
@end
