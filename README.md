AI语音转写和语音合成插件,基于阿里云的SDK (V2.7.1-039-20251125)

## 功能特性

### 语音转写 (ASR)
- 实时语音转写
- 支持多语言识别
- 动态权限管理
- 实时结果回调
- 音频文件保存

### 语音合成 (TTS)
- 流式文本语音合成
- 多种音色选择
- 可调节语速、语调、音量
- 支持多种音频格式
- 实时音频数据回调

## 参考链接

https://help.aliyun.com/zh/isi/developer-reference/nui-sdk-for-android-1?spm=a2c4g.11186623.help-menu-30413.d_3_2_1_1_1.60ae4009ENq05F#h2-xz5-4y5-mus
https://help.aliyun.com/zh/isi/developer-reference/streaming-text-to-speech-android-sdk

## 安装命令

### 完整功能安装（包含语音转写和语音合成）
```
ionic cordova plugin add https://github.com/CTY-Library/cordova-plugin-AI-speech-transcriber --variable APPKEY=xxxxxx --variable SERVICEURL=wss://nls-gateway.cn-shanghai.aliyuncs.com:443/ws/v1 --save
```

### 本地安装
```
ionic cordova plugin add F:\app\cordova-plugin-AI-speech-transcriber --variable APPKEY=1ww23 --variable SERVICEURL=wss://nls-gateway.cn-shanghai.aliyuncs.com:443/ws/v1 --save
```

## Android平台配置

```gradle
// 新增：解决META-INF文件重复冲突
packagingOptions {
    // 处理netty版本文件冲突：只保留第一个找到的文件
    pickFirst 'META-INF/io.netty.versions.properties'
    // 忽略重复的 INDEX.LIST 文件
    exclude 'META-INF/INDEX.LIST'
    // 可选：同时忽略其他常见的重复META文件（避免后续报错）
    exclude 'META-INF/DEPENDENCIES'
    exclude 'META-INF/LICENSE'
    exclude 'META-INF/LICENSE.txt'
    exclude 'META-INF/NOTICE'
    exclude 'META-INF/NOTICE.txt'
    exclude 'META-INF/AL2.0'
    exclude 'META-INF/LGPL2.1'
    exclude 'META-INF/LICENSE.md'
    exclude 'META-INF/NOTICE.md'
}

dependencies {
    // 其他已有的依赖（implementation、api等）
    
    // 添加JAXB兼容依赖，解决DatatypeConverter缺失问题
    // 备选方案（如果上面的依赖有冲突，可使用这个轻量级替代）
    implementation 'org.glassfish.jaxb:jaxb-runtime:2.3.8'
}
```

## 使用案例

### 语音转写功能

#### 初始化语音转写
```javascript
AISpeechTranscriber.init(
    { saveAudio: false, lang: 'zh_CN', token:"xxxx" },
    (e : any) => {
        alert(JSON.stringify(e)); // 成功
    }, (e : any) => {
        alert(JSON.stringify(e)) // 失败
    });
```

#### 开始语音转写
```javascript
AISpeechTranscriber.startTranscribe(            
    (e : any) => {
        var result = JSON.parse(e.message)?.payload?.result ?? "";
        if(result!=''){
            this.resultWordMsg = result;
        }
        // 成功
    }, (e : any) => {
        alert(JSON.stringify(e)) // 失败
    });
```

#### 停止语音转写
```javascript
AISpeechTranscriber.stopTranscribe(            
    (e : any) => {
        // 成功 
        this.ctrlService.Toast("录音停止成功", 'middle', 2000, 'login-toast');
    }, (e : any) => {
        alert(JSON.stringify(e)) // 失败
    });
```

### 语音合成功能

#### 初始化语音合成
```javascript
AISpeechTranscriber.initTTS(
    {
        voice: "zhixiaoxia",        // 音色
        format: "pcm",              // 音频格式: pcm/wav/mp3
        sampleRate: 16000,          // 采样率: 8000/16000/24000/48000
        volume: 50,                 // 音量: 0-100
        speechRate: 0,              // 语速: -500~500
        pitchRate: 0                 // 语调: -500~500
    },
    (e : any) => {
        alert(JSON.stringify(e)); // 成功
    }, (e : any) => {
        alert(JSON.stringify(e)) // 失败
    });
```

#### 开始语音合成
```javascript
AISpeechTranscriber.startTTS("你好，欢迎使用语音合成功能",            
    (e : any) => {
        // 成功 - 开始接收音频数据
        console.log("TTS启动成功");
    }, (e : any) => {
        alert(JSON.stringify(e)) // 失败
    });
```

#### 流式发送文本（可选）
```javascript
AISpeechTranscriber.sendTTSText("这是第二段要合成的文本",            
    (e : any) => {
        // 成功
        console.log("TTS文本发送成功");
    }, (e : any) => {
        alert(JSON.stringify(e)) // 失败
    });
```

#### 停止语音合成
```javascript
AISpeechTranscriber.stopTTS(            
    (e : any) => {
        // 成功
        this.ctrlService.Toast("语音合成停止成功", 'middle', 2000, 'login-toast');
    }, (e : any) => {
        alert(JSON.stringify(e)) // 失败
    });
```

#### 释放TTS资源
```javascript
AISpeechTranscriber.releaseTTS(            
    (e : any) => {
        // 成功
        console.log("TTS资源释放成功");
    }, (e : any) => {
        alert(JSON.stringify(e)) // 失败
    });
```

### 完整的语音交互示例

```javascript
class VoiceAssistant {
    constructor() {
        this.isTranscribing = false;
        this.isTTSSpeaking = false;
    }

    // 初始化语音功能
    async initialize() {
        // 初始化语音转写
        AISpeechTranscriber.init({
            saveAudio: false,
            token: "your_asr_token"
        }, (e) => {
            console.log("ASR初始化成功:", e);
        }, (e) => {
            console.error("ASR初始化失败:", e);
        });

        // 初始化语音合成
        AISpeechTranscriber.initTTS({
            voice: "zhixiaoxia",
            format: "pcm",
            sampleRate: 16000,
            volume: 50,
            speechRate: 0,
            pitchRate: 0
        }, (e) => {
            console.log("TTS初始化成功:", e);
        }, (e) => {
            console.error("TTS初始化失败:", e);
        });
    }

    // 开始语音识别
    startListening() {
        if (this.isTranscribing) return;
        
        AISpeechTranscriber.startTranscribe(
            (result) => {
                const data = JSON.parse(result.message);
                if (data.type === 'partial') {
                    console.log("识别结果:", data.message);
                    // 这里可以处理实时识别结果
                    this.handleSpeechResult(data.message);
                }
            },
            (error) => {
                console.error("识别错误:", error);
            }
        );
        this.isTranscribing = true;
    }

    // 停止语音识别
    stopListening() {
        if (!this.isTranscribing) return;
        
        AISpeechTranscriber.stopTranscribe(
            () => {
                console.log("语音识别已停止");
            },
            (error) => {
                console.error("停止识别失败:", error);
            }
        );
        this.isTranscribing = false;
    }

    // 语音合成
    speak(text) {
        if (this.isTTSSpeaking) return;
        
        AISpeechTranscriber.startTTS(text,
            (result) => {
                console.log("语音合成开始");
            },
            (error) => {
                console.error("语音合成失败:", error);
            }
        );
    }

    // 处理语音结果
    handleSpeechResult(text) {
        // 这里可以实现语音命令识别
        if (text.includes("你好")) {
            this.speak("你好，我是语音助手");
        } else if (text.includes("天气")) {
            this.speak("今天天气晴朗，温度25度");
        }
    }
}

// 使用示例
const voiceAssistant = new VoiceAssistant();
voiceAssistant.initialize();
```

## 事件回调处理

### 语音转写事件
```javascript
AISpeechTranscriber.startTranscribe((result) => {
    const data = JSON.parse(result.message);
    
    switch(data.type) {
        case 'start':
            console.log("转写开始");
            break;
        case 'partial':
            console.log("中间结果:", data.message);
            break;
        case 'complete':
            console.log("最终结果:", data.message);
            break;
        case 'error':
            console.error("转写错误:", data.message);
            break;
        case 'stop':
            console.log("转写停止");
            break;
    }
}, (error) => {
    console.error("转写失败:", error);
});
```

### 语音合成事件
```javascript
// 在TTS回调中处理事件
AISpeechTranscriber.startTTS("测试语音合成", (result) => {
    const data = JSON.parse(result.message);
    
    switch(data.type) {
        case 'tts_event':
            console.log("TTS事件:", data.event);
            if (data.event === "STREAM_INPUT_TTS_EVENT_SYNTHESIS_COMPLETE") {
                console.log("语音合成完成");
            }
            break;
        case 'tts_data':
            console.log("音频数据:", data.length, "bytes");
            // 这里可以处理音频数据，如播放或保存
            break;
    }
}, (error) => {
    console.error("TTS失败:", error);
});


 ailiyuTTS_init(){
        this.ctrlService.Toast("初始化TTS...", 'middle', 2000, 'login-toast');
        // 初始化TTS
        var cfg =  
        {
            "token": "xxx",
            "voice": "zhixiaoxia",
            "format": "pcm", 
            "sample_rate": 16000,
            "volume": 50,
            "speech_rate": 0,
            "pitch_rate": 0,
            "enable_subtitle": true
        } 
        AISpeechTranscriber.initTTS(
         cfg ,
        (e : any) => {
            alert(JSON.stringify(e));//成功 

        }, (e : any) => {
            alert(JSON.stringify(e))//失败
        });
    }

    ailiyuTTS_begin(){
         this.ctrlService.Toast("开始朗读成功...", 'middle', 2000, 'login-toast'); 
         AISpeechTranscriber.sendTTSText(
         '你好,世界2026' ,
        (e : any) => {
            alert(JSON.stringify(e));//成功 

        }, (e : any) => {
            alert(JSON.stringify(e))//失败
        });

    }

    IS_ASR(){
       AISpeechTranscriber.isInitialized(            
            (e : any) => {
                alert(JSON.stringify(e));//成功 

            }, (e : any) => {
                alert(JSON.stringify(e))//失败
            });

    }

    IS_TTS(){
     AISpeechTranscriber.isTTSInitialized(            
        (e : any) => {
            alert(JSON.stringify(e));//成功 

        }, (e : any) => {
            alert(JSON.stringify(e))//失败
        });
    }

    //释放语音合成
    releaseTTS(){
     AISpeechTranscriber.releaseTTS(            
        (e : any) => {
            alert(JSON.stringify(e));//成功 

        }, (e : any) => {
            alert(JSON.stringify(e))//失败
        });
    }
  
    //释放语音识别
    release(){
      AISpeechTranscriber.release(            
        (e : any) => {
            alert(JSON.stringify(e));//成功 

        }, (e : any) => {
            alert(JSON.stringify(e))//失败
        });
    }
```

## 错误码说明

### 语音转写常见错误码
- `240021`: 文件访问错误 - 检查存储权限和SDK资源文件
- `140008`: 鉴权失败 - 检查token是否有效
- `140011`: 状态错误 - 检查调用顺序

### 语音合成常见错误码
- `400`: 参数错误 - 检查TTS配置参数
- `401`: 认证失败 - 检查TTS appkey和token
- `403`: 权限不足 - 检查API权限配置

## 注意事项

1. **权限管理**: 确保应用已获得录音权限
2. **网络连接**: 确保设备可访问阿里云服务
3. **Token管理**: Token会过期，需要定期更新
4. **资源释放**: 使用完毕后及时释放SDK资源
5. **音频格式**: 确保音频格式和采样率配置正确
6. **并发控制**: 避免同时启动多个转写或合成任务



    


```

    

