/**
 * 简化版TTS TypeScript使用示例
 */

// 基础TTS配置
interface TTSConfig {
    voice?: string;      // 音色: "zhixiaoxia", "xiaoyun", "xiaogang"等
    format?: string;     // 音频格式: "pcm", "wav", "mp3"
    sampleRate?: number; // 采样率: 8000, 16000, 24000, 48000
    volume?: number;     // 音量: 0-100
    speechRate?: number; // 语速: -500到500
    pitchRate?: number;  // 语调: -500到500
}

class SimpleTTSService {
    private static instance: SimpleTTSService;
    private isInitialized = false;

    static getInstance(): SimpleTTSService {
        if (!SimpleTTSService.instance) {
            SimpleTTSService.instance = new SimpleTTSService();
        }
        return SimpleTTSService.instance;
    }

    // 初始化TTS
    async init(config: TTSConfig = {}): Promise<void> {
        return new Promise((resolve, reject) => {
            const defaultConfig = {
                voice: "zhixiaoxia",
                format: "pcm",
                sampleRate: 16000,
                volume: 50,
                speechRate: 0,
                pitchRate: 0
            };

            window.AISpeechTranscriber.initTTS(
                { ...defaultConfig, ...config },
                (result) => {
                    console.log('TTS初始化成功');
                    this.isInitialized = true;
                    resolve(result);
                },
                (error) => {
                    console.error('TTS初始化失败');
                    reject(error);
                }
            );
        });
    }

    // 语音合成
    async speak(text: string): Promise<void> {
        if (!this.isInitialized) {
            throw new Error('TTS未初始化');
        }

        return new Promise((resolve, reject) => {
            window.AISpeechTranscriber.startTTS(
                text,
                (result) => {
                    console.log('TTS合成开始');
                    resolve(result);
                },
                (error) => {
                    console.error('TTS合成失败');
                    reject(error);
                }
            );
        });
    }

    // 停止合成
    async stop(): Promise<void> {
        return new Promise((resolve, reject) => {
            window.AISpeechTranscriber.stopTTS(
                (result) => resolve(result),
                (error) => reject(error)
            );
        });
    }

    // 释放资源
    async release(): Promise<void> {
        return new Promise((resolve, reject) => {
            window.AISpeechTranscriber.releaseTTS(
                (result) => {
                    this.isInitialized = false;
                    resolve(result);
                },
                (error) => reject(error)
            );
        });
    }
}

// 使用示例
async function basicExample() {
    const tts = SimpleTTSService.getInstance();

    try {
        // 初始化
        await tts.init({
            voice: "zhixiaoxia",
            volume: 70,
            speechRate: 10
        });

        // 合成语音
        await tts.speak("你好，这是TypeScript版本的TTS示例");
        
        // 等待播放完成后释放
        setTimeout(async () => {
            await tts.release();
        }, 3000);

    } catch (error) {
        console.error('TTS操作失败:', error);
    }
}

// Ionic/Angular服务示例
/*
import { Injectable } from '@angular/core';

@Injectable({
    providedIn: 'root'
})
export class TTSService {
    private tts = SimpleTTSService.getInstance();
    private initialized = false;

    async initialize(): Promise<void> {
        if (!this.initialized) {
            await this.tts.init({
                voice: 'zhixiaoxia',
                format: 'pcm',
                sampleRate: 16000,
                volume: 80
            });
            this.initialized = true;
        }
    }

    async speak(text: string): Promise<void> {
        await this.initialize();
        return this.tts.speak(text);
    }

    async stop(): Promise<void> {
        return this.tts.stop();
    }

    async release(): Promise<void> {
        if (this.initialized) {
            await this.tts.release();
            this.initialized = false;
        }
    }
}
*/

// React Hook示例
/*
import { useState, useEffect, useCallback } from 'react';

export function useTTS() {
    const [isReady, setIsReady] = useState(false);
    const [isSpeaking, setIsSpeaking] = useState(false);
    const tts = SimpleTTSService.getInstance();

    useEffect(() => {
        tts.init().then(() => setIsReady(true));
        return () => tts.release();
    }, []);

    const speak = useCallback(async (text: string) => {
        if (!isReady) return;
        
        setIsSpeaking(true);
        try {
            await tts.speak(text);
            setTimeout(() => setIsSpeaking(false), 3000);
        } catch (error) {
            setIsSpeaking(false);
            console.error('TTS失败:', error);
        }
    }, [isReady]);

    const stop = useCallback(async () => {
        await tts.stop();
        setIsSpeaking(false);
    }, []);

    return { speak, stop, isReady, isSpeaking };
}

// 使用组件
function TTSComponent() {
    const { speak, stop, isReady, isSpeaking } = useTTS();

    return (
        <div>
            <button 
                onClick={() => speak('Hello, this is React TTS example')}
                disabled={!isReady || isSpeaking}
            >
                {isSpeaking ? 'Speaking...' : 'Speak'}
            </button>
            <button onClick={stop} disabled={!isSpeaking}>
                Stop
            </button>
        </div>
    );
}
*/

export { SimpleTTSService, TTSConfig };
