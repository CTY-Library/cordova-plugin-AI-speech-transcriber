/**
 * 阿里云语音合成(TTS) TypeScript使用案例
 * @author CTY-Library
 * @version 1.0.0
 */

// 定义TTS配置接口
interface TTSConfig {
    voice?: string;           // 音色，默认: "zhixiaoxia"
    format?: string;          // 音频格式，默认: "pcm" (pcm/wav/mp3)
    sampleRate?: number;      // 采样率，默认: 16000 (8000/16000/24000/48000)
    volume?: number;          // 音量，默认: 50 (0-100)
    speechRate?: number;      // 语速，默认: 0 (-500~500)
    pitchRate?: number;       // 语调，默认: 0 (-500~500)
}

// 定义TTS事件类型
interface TTSEvent {
    type: 'tts_event' | 'tts_data' | 'tts_error';
    event?: string;          // TTS事件名称
    message?: string;        // 事件消息
    data?: ArrayBuffer;      // 音频数据
    length?: number;         // 数据长度
    timestamp?: string;      // 时间戳
}

// 定义回调函数类型
type SuccessCallback = (result: any) => void;
type ErrorCallback = (error: any) => void;

/**
 * 语音合成服务类
 */
class TTSService {
    private isInitialized: boolean = false;
    private isSpeaking: boolean = false;
    private audioQueue: ArrayBuffer[] = [];
    private currentAudio: HTMLAudioElement | null = null;

    /**
     * 初始化TTS服务
     */
    async initialize(config: TTSConfig = {}): Promise<void> {
        const defaultConfig: TTSConfig = {
            voice: "zhixiaoxia",
            format: "pcm",
            sampleRate: 16000,
            volume: 50,
            speechRate: 0,
            pitchRate: 0
        };

        const finalConfig = { ...defaultConfig, ...config };

        return new Promise((resolve, reject) => {
            if (window.AISpeechTranscriber) {
                window.AISpeechTranscriber.initTTS(
                    finalConfig,
                    (result: any) => {
                        console.log('TTS初始化成功:', result);
                        this.isInitialized = true;
                        resolve();
                    },
                    (error: any) => {
                        console.error('TTS初始化失败:', error);
                        reject(error);
                    }
                );
            } else {
                reject(new Error('AISpeechTranscriber插件未加载'));
            }
        });
    }

    /**
     * 开始语音合成
     */
    async speak(text: string): Promise<void> {
        if (!this.isInitialized) {
            throw new Error('TTS服务未初始化，请先调用initialize()');
        }

        if (this.isSpeaking) {
            throw new Error('当前正在播放语音，请稍后再试');
        }

        return new Promise((resolve, reject) => {
            this.isSpeaking = true;
            this.audioQueue = [];

            window.AISpeechTranscriber.startTTS(
                text,
                (result: any) => {
                    try {
                        const event: TTSEvent = JSON.parse(result.message);
                        this.handleTTSEvent(event);
                        
                        if (event.type === 'tts_event' && 
                            event.event === 'STREAM_INPUT_TTS_EVENT_SYNTHESIS_COMPLETE') {
                            console.log('语音合成完成');
                            this.playAudioQueue();
                            resolve();
                        }
                    } catch (error) {
                        console.error('解析TTS结果失败:', error);
                        reject(error);
                    }
                },
                (error: any) => {
                    console.error('语音合成失败:', error);
                    this.isSpeaking = false;
                    reject(error);
                }
            );
        });
    }

    /**
     * 流式发送更多文本
     */
    async sendText(text: string): Promise<void> {
        if (!this.isInitialized || !this.isSpeaking) {
            throw new Error('TTS服务未启动，请先调用speak()');
        }

        return new Promise((resolve, reject) => {
            window.AISpeechTranscriber.sendTTSText(
                text,
                (result: any) => {
                    console.log('文本发送成功:', result);
                    resolve();
                },
                (error: any) => {
                    console.error('文本发送失败:', error);
                    reject(error);
                }
            );
        });
    }

    /**
     * 停止语音合成
     */
    async stop(): Promise<void> {
        if (!this.isInitialized) {
            return;
        }

        return new Promise((resolve, reject) => {
            window.AISpeechTranscriber.stopTTS(
                (result: any) => {
                    console.log('TTS停止成功:', result);
                    this.isSpeaking = false;
                    this.audioQueue = [];
                    if (this.currentAudio) {
                        this.currentAudio.pause();
                        this.currentAudio = null;
                    }
                    resolve();
                },
                (error: any) => {
                    console.error('TTS停止失败:', error);
                    reject(error);
                }
            );
        });
    }

    /**
     * 释放TTS资源
     */
    async release(): Promise<void> {
        if (!this.isInitialized) {
            return;
        }

        return new Promise((resolve, reject) => {
            window.AISpeechTranscriber.releaseTTS(
                (result: any) => {
                    console.log('TTS资源释放成功:', result);
                    this.isInitialized = false;
                    this.isSpeaking = false;
                    this.audioQueue = [];
                    if (this.currentAudio) {
                        this.currentAudio.pause();
                        this.currentAudio = null;
                    }
                    resolve();
                },
                (error: any) => {
                    console.error('TTS资源释放失败:', error);
                    reject(error);
                }
            );
        });
    }

    /**
     * 处理TTS事件
     */
    private handleTTSEvent(event: TTSEvent): void {
        switch (event.type) {
            case 'tts_event':
                console.log('TTS事件:', event.event, event.message);
                break;
            case 'tts_data':
                if (event.data) {
                    this.audioQueue.push(event.data);
                    console.log('收到音频数据:', event.length, 'bytes');
                }
                break;
            case 'tts_error':
                console.error('TTS错误:', event.message);
                this.isSpeaking = false;
                break;
        }
    }

    /**
     * 播放音频队列
     */
    private async playAudioQueue(): Promise<void> {
        if (this.audioQueue.length === 0) {
            this.isSpeaking = false;
            return;
        }

        try {
            // 将PCM数据转换为WAV格式
            const wavData = this.pcmToWav(this.audioQueue);
            const blob = new Blob([wavData], { type: 'audio/wav' });
            const audioUrl = URL.createObjectURL(blob);
            
            this.currentAudio = new Audio(audioUrl);
            
            this.currentAudio.onended = () => {
                URL.revokeObjectURL(audioUrl);
                this.currentAudio = null;
                this.isSpeaking = false;
            };

            this.currentAudio.onerror = (error) => {
                console.error('音频播放失败:', error);
                URL.revokeObjectURL(audioUrl);
                this.currentAudio = null;
                this.isSpeaking = false;
            };

            await this.currentAudio.play();
        } catch (error) {
            console.error('播放音频失败:', error);
            this.isSpeaking = false;
        }
    }

    /**
     * PCM转WAV格式
     */
    private pcmToWav(pcmData: ArrayBuffer[]): ArrayBuffer {
        const totalLength = pcmData.reduce((sum, data) => sum + data.byteLength, 0);
        const buffer = new ArrayBuffer(44 + totalLength);
        const view = new DataView(buffer);

        // WAV文件头
        const writeString = (offset: number, string: string) => {
            for (let i = 0; i < string.length; i++) {
                view.setUint8(offset + i, string.charCodeAt(i));
            }
        };

        writeString(0, 'RIFF');
        view.setUint32(4, 36 + totalLength, true);
        writeString(8, 'WAVE');
        writeString(12, 'fmt ');
        view.setUint32(16, 16, true);
        view.setUint16(20, 1, true);
        view.setUint16(22, 1, true);
        view.setUint32(24, 16000, true);
        view.setUint32(28, 32000, true);
        view.setUint16(32, 2, true);
        view.setUint16(34, 16, true);
        writeString(36, 'data');
        view.setUint32(40, totalLength, true);

        // 写入PCM数据
        let offset = 44;
        pcmData.forEach(data => {
            const bytes = new Uint8Array(data);
            for (let i = 0; i < bytes.length; i++) {
                view.setUint8(offset++, bytes[i]);
            }
        });

        return buffer;
    }

    /**
     * 获取当前状态
     */
    getStatus(): { initialized: boolean; speaking: boolean } {
        return {
            initialized: this.isInitialized,
            speaking: this.isSpeaking
        };
    }
}

// 声明全局AISpeechTranscriber对象
declare global {
    interface Window {
        AISpeechTranscriber: {
            initTTS: (config: TTSConfig, success: SuccessCallback, error: ErrorCallback) => void;
            startTTS: (text: string, success: SuccessCallback, error: ErrorCallback) => void;
            sendTTSText: (text: string, success: SuccessCallback, error: ErrorCallback) => void;
            stopTTS: (success: SuccessCallback, error: ErrorCallback) => void;
            releaseTTS: (success: SuccessCallback, error: ErrorCallback) => void;
        };
    }
}

// 导出TTS服务类
export { TTSService, TTSConfig, TTSEvent };

// 使用示例
async function exampleUsage() {
    const ttsService = new TTSService();

    try {
        // 1. 初始化TTS服务
        await ttsService.initialize({
            voice: "zhixiaoxia",
            format: "pcm",
            sampleRate: 16000,
            volume: 70,
            speechRate: 10,
            pitchRate: 5
        });

        console.log('TTS服务初始化成功');

        // 2. 语音合成
        await ttsService.speak('你好，欢迎使用阿里云语音合成服务');
        console.log('语音合成开始');

        // 3. 等待播放完成
        setTimeout(async () => {
            console.log('当前状态:', ttsService.getStatus());
            
            // 4. 释放资源
            await ttsService.release();
            console.log('TTS资源已释放');
        }, 5000);

    } catch (error) {
        console.error('TTS服务使用失败:', error);
    }
}

// Angular/Ionic组件使用示例
/*
import { Component, OnInit } from '@angular/core';
import { TTSService } from './tts-service';

@Component({
    selector: 'app-tts-demo',
    template: `
        <ion-header>
            <ion-toolbar>
                <ion-title>语音合成演示</ion-title>
            </ion-toolbar>
        </ion-header>
        <ion-content>
            <ion-item>
                <ion-label position="stacked">输入文本</ion-label>
                <ion-textarea [(ngModel)]="text" placeholder="请输入要合成的文本"></ion-textarea>
            </ion-item>
            <ion-button expand="block" (click)="speak()" [disabled]="isSpeaking">
                {{ isSpeaking ? '正在播放...' : '开始合成' }}
            </ion-button>
            <ion-button expand="block" color="danger" (click)="stop()" [disabled]="!isSpeaking">
                停止播放
            </ion-button>
        </ion-content>
    `
})
export class TTSDemoComponent implements OnInit {
    text = '你好，这是一个语音合成演示';
    isSpeaking = false;
    private ttsService: TTSService;

    constructor() {
        this.ttsService = new TTSService();
    }

    async ngOnInit() {
        try {
            await this.ttsService.initialize({
                voice: 'zhixiaoxia',
                volume: 80
            });
        } catch (error) {
            console.error('TTS初始化失败:', error);
        }
    }

    async speak() {
        if (!this.text.trim()) return;

        try {
            this.isSpeaking = true;
            await this.ttsService.speak(this.text);
        } catch (error) {
            console.error('语音合成失败:', error);
            this.isSpeaking = false;
        }
    }

    async stop() {
        try {
            await this.ttsService.stop();
            this.isSpeaking = false;
        } catch (error) {
            console.error('停止播放失败:', error);
        }
    }

    ngOnDestroy() {
        this.ttsService.release();
    }
}
*/
