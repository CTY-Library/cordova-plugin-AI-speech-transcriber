//
//  NLSRingBuffer.h
//  NUI SDK
//
//  Created by joseph.zgd on 21-11-10.
//  Copyright (c) 2021年 Alibaba iDST. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 *环形缓冲区，用于音频缓存
 */
@interface NlsRingBuffer : NSObject

-(id) init:(int)size_in_byte;
-(int) realloc;
-(int) try_realloc;
-(int) ringbuffer_empty;
-(int) ringbuffer_full;
-(int) ringbuffer_size;
-(int) ringbuffer_get_read_index;
-(int) ringbuffer_read:(unsigned char*)buf Length:(unsigned int)len;
-(int) ringbuffer_write:(unsigned char*)buf Length:(unsigned int)len;
-(void) ringbuffer_reset;
@end
