//
//  NLSPlayAudio.mm
//  NuiDemo
//
//  Created by zhouguangdong on 2019/12/4.
//  Copyright © 2019 Alibaba idst. All rights reserved.
//

#import "NLSPlayAudio.h"
#import "NLSRingBuffer.h"

static UInt32 gBufferSizeBytes = 2048;//It must be pow(2,x)
static dispatch_queue_t gPlayerQueue;

@interface NLSPlayAudio() {
    int state;
    NSLock *lock;
    NlsRingBuffer* ring_buf;
    UInt32 sample_rate;
}
@end

@implementation NLSPlayAudio

- (id)init {
    self = [super init];
    sample_rate = 16000;
    //若合成文本超长，或多份文本在未播放完的情况下进行快速连续合成，需要考虑ringbuf是不是不足以储存合成的音频数据。
    //若无法及时取走合成的音频数据，会导致SDK上报std::bad_alloc系统内存错误。目前ringbuf分配最大内存 sample_rate * 1024字节。
    ring_buf = [[NlsRingBuffer alloc] init:sample_rate];
    lock = [[NSLock alloc] init];

    [self cleanup];
    
    gPlayerQueue = dispatch_queue_create("NuiAudioPlayerController", DISPATCH_QUEUE_CONCURRENT);

    ///设置音频参数
    audioDescription.mSampleRate  = sample_rate; //采样率Hz
    audioDescription.mFormatID    = kAudioFormatLinearPCM;
    audioDescription.mFormatFlags = kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsNonInterleaved;
    audioDescription.mChannelsPerFrame = 1;
    audioDescription.mFramesPerPacket  = 1;//每一个packet一侦数据
    audioDescription.mBitsPerChannel   = 16;//av_get_bytes_per_sample(AV_SAMPLE_FMT_S16)*8;//每个采样点16bit量化
    audioDescription.mBytesPerPacket   = 2;
    audioDescription.mBytesPerFrame    = 2;
    audioDescription.mReserved = 0;

    //使用player的内部线程播 创建AudioQueue
    AudioQueueNewOutput(&audioDescription, bufferCallback, (__bridge void *)(self), nil, nil, 0, &audioQueue);
    if (audioQueue) {
        TLog(@"audioplayer: AudioQueueNewOutput success.");
        Float32 gain=1.0;
        //设置音量
        AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, gain);
        //添加buffer区 创建Buffer
        for (int i = 0; i < NUM_BUFFERS; i++) {
            int result = AudioQueueAllocateBuffer(audioQueue, gBufferSizeBytes, &audioQueueBuffers[i]);
            AudioQueueEnqueueBuffer(audioQueue, audioQueueBuffers[i], 0, NULL);
            TLog(@"audioplayer: AudioQueueAllocateBuffer i = %d,result = %d", i, result);
        }
    } else {
        TLog(@"audioplayer: AudioQueueNewOutput failed.");
    }

    return self;
}

- (void)primePlayQueueBuffers {
    for (int t = 0; t < NUM_BUFFERS; ++t) {
        TLog(@"audioplayer: buffer %d available size %d", t, audioQueueBuffers[t]->mAudioDataBytesCapacity);
        bufferCallback((__bridge void *)(self), audioQueue, audioQueueBuffers[t]);
    }
    AudioQueuePrime(audioQueue, 0, NULL);
}

- (void)play {
    TLog(@"audioplayer: Audio Play Start >>>>>");
    state = starting;
    [self reset];
    
    dispatch_async(gPlayerQueue, ^{
        TLog(@"audioplayer: Audio Play async ...");
        if (audioQueue) {
            [self primePlayQueueBuffers];
            OSStatus status = AudioQueueStart(audioQueue, NULL);
            if (status != 0) {
                AudioQueueFlush(audioQueue);
                status = AudioQueueStart(audioQueue, NULL);
            }
            if (status != 0) {
                TLog(@"audioplayer: Audio Play 启动queue失败 %d", (int)status);
                state = idle;
            } else {
                state = playing;
            }
        } else {
            TLog(@"audioplayer: Audio Play audioQueue is null! >>>>> ");
            state = idle;
        }
        TLog(@"audioplayer: Audio Play async finish, state:%d", (int)state);
    });
    
    TLog(@"audioplayer: Audio Play done");
}

- (void)pause {
    TLog(@"audioplayer: Audio Play Pause(%d) >>>>>", (int)state);
    [lock lock];
    if (state == starting) {
        TLog(@"audioplayer: Audio Play is starting, waiting for playing ...");
        int try_cnt = 50;
        while (try_cnt-- > 0 && state == starting) {
            usleep(100000);
        }
    }
    TLog(@"audioplayer: Audio Play Pause state %d", (int)state);
    if (state == idle) {
        TLog(@"audioplayer: pause failed, player is idle.");
    } else {
        if (state != draining) {
            state = paused;
        }
        if (audioQueue) {
            AudioQueuePause(audioQueue);
        }
    }
    [lock unlock];
    TLog(@"audioplayer: Audio Play Pause done, state %d", (int)state);
}

- (void)resume {
    TLog(@"audioplayer: Audio Play Resume(%d) >>>>>", (int)state);
    [lock lock];
    if (state == starting) {
        TLog(@"audioplayer: Audio Play is starting, waiting for playing ...");
        int try_cnt = 50;
        while (try_cnt-- > 0 && state == starting) {
            usleep(100000);
        }
    }
    if (state != playing) {
        if (state != draining) {
            state = playing;
        }
        if (audioQueue) {
            AudioQueueStart(audioQueue, NULL);
        }
    }
    [lock unlock];
    TLog(@"audioplayer: Audio Play Resume done, state %d", (int)state);
}

- (void)setstate:(PlayerState)pstate {
    state = pstate;
}

- (void)setsamplerate:(int)sr {
    if (sr != sample_rate) {
        sample_rate = sr;
        //若合成文本超长，或多份文本在未播放完的情况下进行快速连续合成，需要考虑ringbuf是不是不足以储存合成的音频数据。
        //若无法及时取走合成的音频数据，会导致SDK上报std::bad_alloc系统内存错误。目前ringbuf分配最大内存 sample_rate * 1024字节。
        ring_buf = [[NlsRingBuffer alloc] init:sample_rate];

        [self cleanup];

        TLog(@"setsamplerate: set sample_rate %d", sample_rate);
        ///设置音频参数
        audioDescription.mSampleRate  = sample_rate; //采样率Hz
        audioDescription.mFormatID    = kAudioFormatLinearPCM;
        audioDescription.mFormatFlags = kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsNonInterleaved;
        audioDescription.mChannelsPerFrame = 1;
        audioDescription.mFramesPerPacket  = 1;//每一个packet一侦数据
        audioDescription.mBitsPerChannel   = 16;//av_get_bytes_per_sample(AV_SAMPLE_FMT_S16)*8;//每个采样点16bit量化
        audioDescription.mBytesPerPacket   = 2;
        audioDescription.mBytesPerFrame    = 2;
        audioDescription.mReserved = 0;

        //使用player的内部线程播 创建AudioQueue
        AudioQueueNewOutput(&audioDescription, bufferCallback, (__bridge void *)(self), nil, nil, 0, &audioQueue);
        if (audioQueue) {
            Float32 gain=1.0;
            //设置音量
            AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, gain);
            //添加buffer区 创建Buffer
            for (int i = 0; i < NUM_BUFFERS; i++) {
                int result = AudioQueueAllocateBuffer(audioQueue, gBufferSizeBytes, &audioQueueBuffers[i]);
                AudioQueueEnqueueBuffer(audioQueue, audioQueueBuffers[i], 0, NULL);
                TLog(@"audioplayer: AudioQueueAllocateBuffer i = %d,result = %d",i,result);
            }
        }
        TLog(@"setsamplerate: set sample_rate %d done.", sample_rate);
    }
}

- (int)write:(const char*)buffer Length:(int)len {
    int wait_time_ms = 0;
    int ret = 0;
    while (1) {
        if (wait_time_ms > 3000) {
            TLog(@"wait for 3s, player must not consuming pcm data. overrun...");
            break;
        }
        TLog(@"ringbuf want write data %d",  len);
        int ret = [ring_buf ringbuffer_write:(unsigned char*)buffer Length:len];
        TLog(@"ringbuf writed data %d",  ret);
        if (len != 0 && ret == 0) {
            int realloc_ret = [ring_buf try_realloc];
            if (realloc_ret == 0) {
                TLog(@"ringbuf try_realloc, size of buffer is: %d", [ring_buf ringbuffer_size]);
            }
        }
        if (state != playing && state != starting) {
            TLog(@"ringbuf want state %d, break",  state);
            break;
        }
        if (ret <= 0) {
            usleep(10000);
            wait_time_ms += 10;
            continue;
        } else {
            wait_time_ms = 0;
            break;
        }
    }
    return ret;
}

-(void)reset {
    TLog(@"audioplayer: Audio Player Reset >>>>>");
    [ring_buf ringbuffer_reset];
    if (audioQueue) {
        TLog(@"audioplayer: Flush reset");
        //AudioQueueReset(audioQueue);
        AudioQueueStop(audioQueue, TRUE);
        AudioQueueFlush(audioQueue);
    }
    TLog(@"audioplayer: Audio Player Reset done");
}

-(void)stop {
    TLog(@"audioplayer: Audio Player Stop state:%d >>>>>", state);
    state = idle;
    [self reset];
    TLog(@"audioplayer: Audio Player Stop done");
}

-(void)drain {
    TLog(@"audioplayer: Audio Player Draining, state:%d", state);
    state = draining;
}

-(void)cleanup {
    [ring_buf ringbuffer_reset];
    state = idle;
    if (audioQueue) {
        TLog(@"audioplayer: Release AudioQueueNewOutput");
        
        AudioQueueFlush(audioQueue);
        AudioQueueReset(audioQueue);
        AudioQueueStop(audioQueue, TRUE);
        for (int i = 0; i < QUEUE_BUFFER_SIZE; i++) {
            AudioQueueFreeBuffer(audioQueue, audioQueueBuffers[i]);
            audioQueueBuffers[i] = nil;
        }
        AudioQueueDispose(audioQueue, true);
        audioQueue = nil;
    } else {
        TLog(@"audioplayer: has released AudioQueueNewOutput");
    }
}

//回调函数(Callback)的实现
static void bufferCallback(void *inUserData,AudioQueueRef inAQ, AudioQueueBufferRef buffer) {
    NLSPlayAudio* player = (__bridge NLSPlayAudio *)inUserData;
    int ret = [player getAudioData:buffer];
    if (ret > 0) {
        OSStatus status = AudioQueueEnqueueBuffer(inAQ, buffer, 0, NULL);
        TLog(@"audioplayer: playCallback status %d.", status);
    } else {
        TLog(@"audioplayer: no more data");
        if (player->state == draining) {
            TLog(@"audioplayer: draining ...");
            //drain data finish, stop player.
            [player stop];

            if ([player->_delegate respondsToSelector:@selector(playerDidFinish)]) {
               dispatch_async(gPlayerQueue, ^{
                   [player->_delegate playerDidFinish];
               });
            }
        }
    }
}

- (int)getAudioData:(AudioQueueBufferRef)buffer {
    if (buffer == NULL || buffer->mAudioData == NULL) {
        TLog(@"no more data to play");
        return 0;
    }
    while (1) {
        int ret = [ring_buf ringbuffer_read:(unsigned char*)buffer->mAudioData Length:buffer->mAudioDataBytesCapacity];
//        TLog(@"ringbuf read data %d; state:%d", ret, state);

        if (0 < ret) {
            TLog(@"ringbuf read data %d",  ret);
            buffer->mAudioDataByteSize = ret;
            return ret;
        } else {
            if (state != playing && state != starting) {
                break;
            }
            usleep(10*1000);
            continue;
        }
    }
    return 0;
}


@end
