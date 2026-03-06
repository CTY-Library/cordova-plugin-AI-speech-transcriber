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
     * @param {string} [config.voice="zhixiaoxia"] - 音色
     * @param {string} [config.format="pcm"] - 音频格式
     * @param {number} [config.sampleRate=16000] - 采样率
     * @param {number} [config.volume=50] - 音量
     * @param {number} [config.speechRate=0] - 语速
     * @param {number} [config.pitchRate=0] - 语调
     * @param {Function} success - 成功回调
     * @param {Function} error - 失败回调
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
     * 发送TTS文本（流式）
     * @param {string} text - 要合成的文本
     * @param {Function} success - 成功回调
     * @param {Function} error - 失败回调
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
    }
};

module.exports = AISpeechTranscriber;