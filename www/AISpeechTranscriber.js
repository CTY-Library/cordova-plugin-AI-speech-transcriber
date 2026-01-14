var exec = require('cordova/exec');

var AISpeechTranscriber = {
    /**
     * 初始化阿里云SDK
     * @param {Object} config - 配置参数
     * @param {string} config.accessKeyId - 阿里云AccessKeyId
     * @param {string} config.accessKeySecret - 阿里云AccessKeySecret
     * @param {string} config.appKey - 阿里云语音应用AppKey
     * @param {string} [config.regionId=cn-shanghai] - 地域ID
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
    }
};

module.exports = AISpeechTranscriber;