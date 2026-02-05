AI语音转文字插件,基于阿里云的SDK (V2.7.1-039-20251125)



参考链接

 https://help.aliyun.com/zh/isi/developer-reference/nui-sdk-for-android-1?spm=a2c4g.11186623.help-menu-30413.d_3_2_1_1_1.60ae4009ENq05F#h2-xz5-4y5-mus



 https://help.aliyun.com/zh/isi/sdk-selection-and-download?spm=a2c4g.11186623.0.0.314c77ab2Fh4UB#bdf5e010bfg9t




安装命令
```
 ionic cordova plugin add   https://github.com/CTY-Library/cordova-plugin-AI-speech-transcriber --variable APPKEY=xxxxxx   --variable SERVICEURL=wss://nls-gateway.cn-shanghai.aliyuncs.com:443/ws/v1 --save
```

本地安装 
 ```
 ionic cordova plugin add  F:\app\cordova-plugin-AI-speech-transcriber --variable APPKEY=1ww23    --variable SERVICEURL=wss://nls-gateway.cn-shanghai.aliyuncs.com:443/ws/v1 --save  
 ```

Android平台配置
```
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


使用案例关键代码
```
  async audioToWord(){
        this.ctrlService.Toast("初始化录音...", 'middle', 2000, 'login-toast');
        this.resultWordMsg += '\n' + "你好,世界!";

        // 初始化
         AISpeechTranscriber.init(
            { saveAudio: false, lang: 'zh_CN', token:"4e89df9758a145a18cd37dc34906418e" },
            (e : any) => {
                alert(JSON.stringify(e));//成功 

            }, (e : any) => {
                alert(JSON.stringify(e))//失败
            });

    
    }

        async beginAudio(){
            this.ctrlService.Toast("初始化录音...", 'middle', 2000, 'login-toast');
                // 开始转写
                AISpeechTranscriber.startTranscribe(            
                (e : any) => {
                    var result = JSON.parse(e.message)?.payload?.result ?? "";
                    if(result!=''){
                        this.resultWordMsg = result;
                    }
                    //成功
                    //this.resultWordMsg = '\r\n' + (result==''?JSON.stringify(e):result) + '\n';   
                }, (e : any) => {
                    alert(JSON.stringify(e))//失败
            });
        }



    async stopAudio(){
        AISpeechTranscriber.stopTranscribe(            
        (e : any) => {
            //成功 
            this.ctrlService.Toast("录音停止成功", 'middle', 2000, 'login-toast');
        }, (e : any) => {
            alert(JSON.stringify(e))//失败
        });
    }



    


```

    

