var exec = require('cordova/exec');

var AISpeechTranscriber = {
    /**
     * 初始化阿里云SDK
     * @param {Object} config - 配置参数
     * @param {string} [config {saveAudio:false,token:""}] - 是否保存音频文件
     * @param {Function} success - 成功回调
     * @param {Function} error - 失败回调
     */
    init: function (config, success, error) {
        exec(success, error, 'AISpeechTranscriber', 'init', [config]);
    },
    
    /**
     * 启动语音转写
     * @param {Function} success - 结果回调（含中间/最终结果）
     * @param {Function} error - 错误回调
     */
    startTranscribe: function (success, error) {
        exec(success, error, 'AISpeechTranscriber', 'startTranscribe', []);
    },
    
    /**
     * 停止语音转写
     * @param {Function} success - 成功回调
     * @param {Function} error - 失败回调
     */
    stopTranscribe: function (success, error) {
        exec(success, error, 'AISpeechTranscriber', 'stopTranscribe', []);
    },
    
    /**
     * 释放SDK资源
     * @param {Function} success - 成功回调
     * @param {Function} error - 失败回调
     */
    release: function (success, error) {
        exec(success, error, 'AISpeechTranscriber', 'release', []);
    },

    /**
     * 初始化语音合成
     * @param {Object} config - TTS配置参数
     * @param {string} [config.token] - 认证token
     * @param {string} [config.accessKey] - AccessKey ID（如果不提供，将使用插件配置中的appkey）
     * @param {string} [config.accessKeySecret] - AccessKey Secret
     * @param {string} [config.stsToken] - STS Token
     * @param {string} [config.serviceUrl] - 服务URL
     * @param {string} [config.voice="zhixiaoxia"] - 音色
     * @param {string} [config.format="pcm"] - 音频格式
     * @param {number} [config.sampleRate=16000] - 采样率
     * @param {number} [config.volume=50] - 音量
     * @param {number} [config.speechRate=0] - 语速
     * @param {number} [config.pitchRate=0] - 语调
     * @param {Function} success - 成功回调
     * @param {Function} error - 失败回调
     * @example
     * // 简化使用：初始化后直接发送文本
     * AISpeechTranscriber.initTTS({
     *     token: "your_token",
     *     voice: "xiaoyun",
     *     sampleRate: 24000
     * }, function() {
     *     console.log("TTS初始化成功");
     *     
     *     // 直接发送文本，无需手动启动和停止
     *     AISpeechTranscriber.sendTTSText("你好世界", function(success) {
     *         console.log("TTS播放完成，可以发送下一个文本了");
     *     }, function(error) {
     *         console.error("TTS播放失败:", error);
     *     });
     * }, error);
     */
    initTTS: function (config, success, error) {
        exec(success, error, 'AISpeechTranscriber', 'initTTS', [config]);
    },

    /**
     * 开始语音合成
     * @param {string} text - 要合成的文本
     * @param {Function} success - 成功回调
     * @param {Function} error - 失败回调
     */
    startTTS: function (text, success, error) {
        exec(success, error, 'AISpeechTranscriber', 'startTTS', [text]);
    },

    /**
     * 发送TTS文本（主要方法，自动启动和停止）
     * @param {string} text - 要合成的文本
     * @param {Function} success - 成功回调（播放完毕后自动调用）
     * @param {Function} error - 失败回调
     * @description
     * 这是推荐的TTS使用方式，会自动处理：
     * 1. 启动TTS服务（如果未启动）
     * 2. 发送文本进行语音合成
     * 3. 播放音频
     * 4. 播放完毕后自动停止并重置状态
     * 5. 为下一次使用做好准备
     * 
     * @example
     * // 简单使用
     * AISpeechTranscriber.sendTTSText("你好世界", function() {
     *     console.log("播放完成，可以发送下一个文本");
     * }, function(error) {
     *     console.error("播放失败:", error);
     * });
     * 
     * // 连续播放
     * function playTexts(texts, index) {
     *     if (index >= texts.length) return;
     *     
     *     AISpeechTranscriber.sendTTSText(texts[index], function() {
     *         console.log("播放完成: " + texts[index]);
     *         playTexts(texts, index + 1); // 自动播放下一个
     *     }, function(error) {
     *         console.error("播放失败:", error);
     *     });
     * }
     * 
     * playTexts(["你好", "世界", "欢迎使用"], 0);
     */
    sendTTSText: function (text, success, error) {
        exec(success, error, 'AISpeechTranscriber', 'sendTTSText', [text]);
    },

    /**
     * 停止语音合成
     * @param {Function} success - 成功回调
     * @param {Function} error - 失败回调
     */
    stopTTS: function (success, error) {
        exec(success, error, 'AISpeechTranscriber', 'stopTTS', []);
    },

    /**
     * 释放TTS资源
     * @param {Function} success - 成功回调
     * @param {Function} error - 失败回调
     */
    releaseTTS: function (success, error) {
        exec(success, error, 'AISpeechTranscriber', 'releaseTTS', []);
    },

    /**
     * 检查语音识别是否已初始化
     * @param {Function} success - 成功回调，参数为boolean值
     * @param {Function} error - 失败回调
     * @example
     * AISpeechTranscriber.isInitialized(function(isInit) {
     *     if (isInit) {
     *         console.log("语音识别已初始化");
     *         AISpeechTranscriber.startTranscribe(success, error);
     *     } else {
     *         console.log("语音识别未初始化，请先调用init方法");
     *     }
     * }, error);
     */
    isInitialized: function (success, error) {
        exec(success, error, 'AISpeechTranscriber', 'isInitialized', []);
    },

    /**
     * 检查TTS是否已初始化
     * @param {Function} success - 成功回调，参数为boolean值
     * @param {Function} error - 失败回调
     * @example
     * AISpeechTranscriber.isTTSInitialized(function(isInit) {
     *     if (isInit) {
     *         console.log("TTS已初始化");
     *         AISpeechTranscriber.sendTTSText("你好世界", success, error);
     *     } else {
     *         console.log("TTS未初始化，请先调用initTTS方法");
     *     }
     * }, error);
     */
    isTTSInitialized: function (success, error) {
        exec(success, error, 'AISpeechTranscriber', 'isTTSInitialized', []);
    }
};

module.exports = AISpeechTranscriber;