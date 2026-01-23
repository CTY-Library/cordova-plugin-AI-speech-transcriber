//
//  NLSRingBuffer.m
//  NUI SDK
//
//  Created by joseph.zgd on 21-11-10.
//  Copyright (c) 2021年 Alibaba iDST. All rights reserved.
//

#include <mutex>
#import "NLSRingBuffer.h"

@interface NlsRingBuffer(){
    unsigned char *buffer;
    unsigned int size;
    unsigned int max_size;
    unsigned int fill;
    unsigned char *read;
    unsigned char *write;
    unsigned int max_try_count_down;
    int try_count_down;
    std::mutex lock;
}
@end

@implementation NlsRingBuffer

-(id) init:(int)size_in_byte {
    std::unique_lock<decltype(lock)> auto_lock(lock);
    buffer = (unsigned char*)malloc(size_in_byte);
    size = size_in_byte;
    max_size = size_in_byte * 2048; // 31.25MB
    fill = 0;
    read = buffer;
    write = buffer;
    max_try_count_down = 100;
    try_count_down = max_try_count_down;
    return self;
}

-(int) realloc {
    std::unique_lock<decltype(lock)> auto_lock(lock);
    if (size * 2 > max_size) {
        return 1;
    }

    unsigned char *tmp = buffer;
    buffer = (unsigned char*)malloc(size * 2);
    if (buffer != nullptr) {
        memset(buffer, 0, size * 2);
        if (write >= read) {
            // < empty - read - data - write - empty >
            memcpy(buffer, tmp, size);
            read = read - tmp + buffer;
            write = write - tmp + buffer;
        } else {
            // < data - write - empty - read - data >
            memcpy(buffer, tmp, write - tmp);
            long tail = tmp + size - read;
            memcpy(buffer + (size * 2) - tail, read, tail);
            read = buffer + (size * 2) - tail;
            write = write - tmp + buffer;
        }
        free(tmp);
        size = size * 2;
    }
    return 0;
}

-(int) try_realloc {
    std::unique_lock<decltype(lock)> auto_lock(lock);
    if (size * 2 > max_size) {
        return 1;
    }

    if (try_count_down-- > 0) {
        if (try_count_down < 0)
            try_count_down = 0;
        return 2;
    }

    unsigned char *tmp = buffer;
    buffer = (unsigned char*)malloc(size * 2);
    if (buffer != nullptr) {
        memset(buffer, 0, size * 2);
        if (write >= read) {
            // < empty - read - data - write - empty >
            memcpy(buffer, tmp, size);
            read = read - tmp + buffer;
            write = write - tmp + buffer;
        } else {
            // < data - write - empty - read - data >
            memcpy(buffer, tmp, write - tmp);
            long tail = tmp + size - read;
            memcpy(buffer + (size * 2) - tail, read, tail);
            read = buffer + (size * 2) - tail;
            write = write - tmp + buffer;
        }
        free(tmp);
        size = size * 2;
        try_count_down = max_try_count_down;
    }
    return 0;
}

-(void) dealloc {
    std::unique_lock<decltype(lock)> auto_lock(lock);
    if (buffer) {
        free(buffer);
        buffer = nullptr;
    }
}

-(int) ringbuffer_empty {
    if (buffer == nullptr)
        return 1;
    std::unique_lock<decltype(lock)> auto_lock(lock);
    /* It's empty when the read and write pointers are the same. */
    if (0 == fill) {
        return 1;
    }else {
        return 0;
    }
}

-(int) ringbuffer_full {
    if (buffer == nullptr)
        return 0;
    std::unique_lock<decltype(lock)> auto_lock(lock);
    /* It's full when the write ponter is 1 element before the read pointer*/
    if (size == fill) {
        return 1;
    }else {
        return 0;
    }
}

-(int) ringbuffer_size {
    if (buffer == nullptr)
        return 0;
    std::unique_lock<decltype(lock)> auto_lock(lock);
    return size;
}

-(int) ringbuffer_get_write_index {
    if (buffer == nullptr)
        return 0;
    return write - buffer;
}

-(int) ringbuffer_get_read_index{
    if (buffer == nullptr)
        return 0;
    return read - buffer;
}

-(int) ringbuffer_get_filled {
    if (buffer == nullptr)
        return 0;
    int r = [self ringbuffer_get_read_index];
    int w = [self ringbuffer_get_write_index];
    if (w >= r) {
        return w - r;
    } else {
        return w + size - r;
    }
}

-(int) ringbuffer_read:(unsigned char*)buf Length:(unsigned int)len {
    if (buffer == nullptr)
        return 0;
    std::unique_lock<decltype(lock)> auto_lock(lock);
    assert(len>0);

    if (fill < len) {
        len = fill;
    }
    if (fill >= len) {
        // in one direction, there is enough data for retrieving
        if (write > read) {
            memcpy(buf, read, len);
            read += len;
        } else if (write < read) {
            long tail = buffer + size - read;
            if (tail >= len) {
                memcpy(buf, read, len);
                read += len;
            } else {
                long len2 = len - tail;
                memcpy(buf, read, tail);
                memcpy(buf + tail, buffer, len2);
                read = buffer + len2; // Wrap around
            }
        }
        fill -= len;
        if (write == read && write != buffer) {
            write = buffer;
            read = buffer;
        }
        return len;
    } else {
        return 0;
    }
}

-(int) ringbuffer_write:(unsigned char*)buf Length:(unsigned int)len {
    if (buffer == nullptr)
        return 0;
    std::unique_lock<decltype(lock)> auto_lock(lock);
//    printf("ringbuffer_write: size:%d fill:%d len:%d write:%d read:%d\n", size, fill, len, write, read);
    assert(len > 0);
    if (size - fill <= len) {
        return 0;
    } else {
        if (write >= read) {
            long remain = buffer + size - write; // 缓冲区尾部剩余空间
            if (remain >= len) {
                memcpy(write, buf, len);
                write += len;
            } else {
                long circul_len = len - remain; // 数据写入缓冲区尾部后剩余未写入数据
                long leisure = read - buffer; // 缓冲区头部可写入空间
                if (circul_len > leisure) {
                    return 0;
                }
                memcpy(write, buf, remain);
                memcpy(buffer, buf + remain, circul_len);
                write = buffer + circul_len; // Wrap around
            }
        } else {
            memcpy(write, buf, len);
            write += len;
        }
        fill += len;
        return len;
    }
}

-(void) ringbuffer_reset {
    std::unique_lock<decltype(lock)> auto_lock(lock);
    if (buffer == nullptr)
        return;
    fill = 0;
    write = buffer;
    read = buffer;
    memset(buffer, 0, size);
    return;
}
@end
