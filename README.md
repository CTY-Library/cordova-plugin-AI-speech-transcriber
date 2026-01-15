AI语音转文字插件,基于阿里云的SDK



参考链接

 https://help.aliyun.com/zh/isi/developer-reference/nui-sdk-for-android-1?spm=a2c4g.11186623.help-menu-30413.d_3_2_1_1_1.60ae4009ENq05F#h2-xz5-4y5-mus



 https://help.aliyun.com/zh/isi/sdk-selection-and-download?spm=a2c4g.11186623.0.0.314c77ab2Fh4UB#bdf5e010bfg9t




安装命令
```
 ionic cordova plugin add   https://github.com/CTY-Library/cordova-plugin-AI-speech-transcriber --variable APPKEY=xxxxxx  --variable ACCESSKEYID=xxxxxx --variable   ACCESSKEYSECRET=xxxxxx  --variable TOKEN=xxxxxx  --variable STSTOKEN=xxxxxx  --variable SERVICEURL=xxxxxx --save
```

本地安装 
 ```
 ionic cordova plugin add  F:\app\cordova-plugin-AI-speech-transcriber --variable APPKEY=1ww23  --variable ACCESSKEYID=56rz8 --variable   ACCESSKEYSECRET=fffwx  --variable TOKEN=ee2se  --variable STSTOKEN=1213x  --variable SERVICEURL=467gr  
 ```
 



使用案例关键代码
```
 async audioToWord(){
        this.ctrlService.Toast("开始录音...", 'middle', 2000, 'login-toast');
        this.resultWordMsg += '\n' + "你好,世界!";

        // 初始化
         AISpeechTranscriber.init(
            { saveAudio: true},
            (e : any) => {
                alert(e);//成功
            }, (e : any) => {
                alert(e)//失败
            });

        // 开始转写
        AISpeechTranscriber.startTranscribe(            
        (e : any) => {
            //成功
            this.resultWordMsg += '\n' + e;
        }, (e : any) => {
            alert(e)//失败
        });
    }

    async stopAudio(){
        AISpeechTranscriber.stopTranscribe(            
        (e : any) => {
            //成功
            this.resultWordMsg += '\n' + e;

            // 销毁实例
            AISpeechTranscriber.release (            
            (e : any) => {
                //成功
                this.resultWordMsg += '\n' + e;
            }, (e : any) => {
                alert(e)//失败
            });

        }, (e : any) => {
            alert(e)//失败
        });
    }

```

    

