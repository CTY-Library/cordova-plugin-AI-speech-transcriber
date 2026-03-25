package com.plugin.aliyun.aispeech;

import android.Manifest;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioRecord;
import android.media.AudioTrack;
import android.media.MediaRecorder;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.text.TextUtils;
import android.util.Log;
import android.widget.Button;
import android.widget.Spinner;
import android.widget.Switch;
import android.widget.TextView;

import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;

import com.alibaba.fastjson.JSON;
import com.alibaba.fastjson.JSONException;
import com.alibaba.fastjson.JSONObject;
import com.alibaba.idst.nui.AsrResult;
import com.alibaba.idst.nui.Constants;
import com.alibaba.idst.nui.INativeNuiCallback;
import com.alibaba.idst.nui.INativeStreamInputTtsCallback;
import com.alibaba.idst.nui.KwsResult;
import com.alibaba.idst.nui.NativeNui;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.PermissionHelper;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;

import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.LinkedBlockingQueue;

/**
 * 阿里云语音转写 Cordova 插件核心类
 * 功能：实时语音转写、权限管理、多状态回调、资源释放
 * 适配 Cordova 插件规范，无 UI 依赖
 */
public class AISpeechTranscriber extends CordovaPlugin implements INativeNuiCallback, INativeStreamInputTtsCallback {
    // 日志标签
    private static final String TAG = "AliyunSpeechTranscriber";
    // 音频参数常量
    private static final int SAMPLE_RATE = 16000;

    // 权限请求码
    private static final int PERMISSION_RECORD_AUDIO = 1001;
    private static final int PERMISSION_WRITE_STORAGE = 1002;
    private static final int READ_EXTERNAL_STORAGE =1003;

    // TTS相关常量
    private static final int TTS_SAMPLE_RATE = 16000;
    private static final int TTS_VOLUME = 50;
    private static final int TTS_SPEECH_RATE = 0;
    private static final int TTS_PITCH_RATE = 0;

    private String token;

    private String serviceUrl = "wss://nls-gateway.cn-shanghai.aliyuncs.com:443/ws/v1";

    // SDK 核心实例
    private NativeNui nui_instance = new NativeNui();
    // TTS 核心实例 - 使用非流式TTS
    private NativeNui tts_instance = new NativeNui(Constants.ModeType.MODE_TTS);
    // 音频录制相关
    private AudioRecord audioRecorder;
    private LinkedBlockingQueue<byte[]> audioQueue = new LinkedBlockingQueue<>();
    private OutputStream audioFileStream;
    private String audioSavePath;
    private boolean isSaveAudio = false;

    // 状态控制
    private boolean isSdkInitialized = false;
    private boolean isTranscribing = false;
    private boolean isStopping = false;
    private boolean isTTSInitialized = false;
    private boolean isTTSRunning = false;
    private String currentTaskId = "";
    private String currentTTSTaskId = "";
    private String debugPath;

    // TTS相关配置
    private String ttsToken = "";
    private String ttsVoice = "zhixiaoxia";
    private String ttsFormat = "pcm";
    private int ttsSampleRate = TTS_SAMPLE_RATE;
    private int ttsVolume = TTS_VOLUME;
    private int ttsSpeechRate = TTS_SPEECH_RATE;
    private int ttsPitchRate = TTS_PITCH_RATE;

    // TTS音频播放相关
    private AudioTrack audioTrack;
    private boolean isPlaying = false;
    private LinkedBlockingQueue<byte[]> ttsAudioQueue = new LinkedBlockingQueue<>();
    private Thread audioPlayerThread;
    private boolean isFinishSend = false;

    // 异步线程
    private HandlerThread workerThread;
    private Handler workerHandler;
    // Cordova 回调上下文
    private CallbackContext transcribeCallback;
    private CallbackContext ttsCallback;

    /**
     * Cordova 插件核心入口：处理 JS 调用的方法
     */
    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) {
        try {
            switch (action) {
                case "init":
                    initSDK(args.getJSONObject(0), callbackContext);
                    return true;
                case "startTranscribe":
                    startTranscription(callbackContext);
                    return true;
                case "stopTranscribe":
                    stopTranscription(callbackContext);
                    return true;
                case "release":
                    releaseAllResources(callbackContext);
                    return true;
                case "initTTS":
                    try {
                        org.json.JSONObject orgConfig = args.getJSONObject(0);
                        com.alibaba.fastjson.JSONObject fastConfig = new com.alibaba.fastjson.JSONObject();

                        // 转换JSONObject
                        java.util.Iterator<String> keys = orgConfig.keys();
                        while (keys.hasNext()) {
                            String key = keys.next();
                            Object value = orgConfig.get(key);
                            fastConfig.put(key, value);
                        }

                        initTTS(fastConfig, callbackContext);
                    } catch (Exception e) {
                        callbackContext.error("TTS配置参数解析失败：" + e.getMessage());
                        Log.e(TAG, "TTS配置参数解析异常", e);
                    }
                    return true;
                case "sendTTSText":
                    sendTTSText(args.getString(0), callbackContext);
                    return true;
                case "stopTTS":
                    stopTTS(callbackContext);
                    return true;
                case "releaseTTS":
                    releaseTTSResources(callbackContext);
                    return true;
                case "isInitialized":
                    isInitialized(callbackContext);
                    return true;
                case "isTTSInitialized":
                    isTTSInitialized(callbackContext);
                    return true;
                default:
                    callbackContext.error("不支持的操作：" + action);
                    return false;
            }
        }  catch (Exception e) {
            // callbackContext.error("操作失败：" + e.getMessage());
            Log.e(TAG, "执行操作异常", e);
            return false;
        }
    }

    // ====================== SDK 初始化 ======================
    // 1. 新增文件权限数组（合并录音+文件权限）
    private static final String[] ALL_PERMISSIONS = {
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.READ_EXTERNAL_STORAGE,
            Manifest.permission.WRITE_EXTERNAL_STORAGE,

    };
    private static final int PERMISSION_REQUEST_CODE = 1001;
    private void initSDK(org.json.JSONObject config, CallbackContext callbackContext) throws PackageManager.NameNotFoundException, org.json.JSONException {

        String version = nui_instance.GetVersion();
        final String version_text = "内部SDK版本号:" + version;
        Log.i(TAG, "current sdk version: " + version_text);
        Context context = this.cordova.getActivity().getApplicationContext();
        // 获取ApplicationInfo中的元数据
        ApplicationInfo appInfo =  context.getPackageManager().getApplicationInfo(context.getPackageName(),
                PackageManager.GET_META_DATA);


        g_token = config.getString("token");// "4e89df9758a145a18cd37dc34906418e";
        g_appkey = appInfo.metaData.getString("com.plugin.ai.speech.APPKEY");
        g_url =  appInfo.metaData.getString("com.plugin.ai.speech.SERVICEURL", serviceUrl);// "wss://nls-gateway.cn-shanghai.aliyuncs.com:443/ws/v1";

        // 检查文件读写权限
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {

            // 检查是否所有权限都已授予
            boolean hasAllPermission = true;
            for (String permission : ALL_PERMISSIONS) {
                if (!PermissionHelper.hasPermission(this, permission)) {
                    hasAllPermission = false;
                    break;
                }
            }

            if (!hasAllPermission) {
                // 申请所有必要权限
                PermissionHelper.requestPermissions(this, PERMISSION_REQUEST_CODE, ALL_PERMISSIONS);
                return;
            }


        }

        mDebugPath =  Objects.requireNonNull(cordova.getActivity().getExternalCacheDir()).getAbsolutePath()  + "/debug";
        CommonUtils.createDir(mDebugPath);

        // 初始化worker线程和handler
        if (workerThread == null) {
            workerThread = new HandlerThread("AliyunSpeechWorker");
            workerThread.start();
            workerHandler = new Handler(workerThread.getLooper());
            Log.i(TAG, "Worker Handler已初始化");
        }

        //初始化SDK，注意用户需要在Auth.getTicket中填入相关ID信息才可以使用。
        int ret = nui_instance.initialize(this, genInitParams("", mDebugPath),
                Constants.LogLevel.LOG_LEVEL_VERBOSE, true);
        Log.i(TAG, "result = " + ret);
        if (ret == Constants.NuiResultCode.SUCCESS) {
            isSdkInitialized = true;
        }

    }

    // ====================== 启动实时转写 ======================
    private void startTranscription(CallbackContext callbackContext) {
        // 校验 SDK 状态
        if (!isSdkInitialized) {
            callbackContext.error("SDK 未初始化，请先调用 init 方法");
            return;
        }
        // 校验转写状态
//        if (isTranscribing) {
//            callbackContext.error("当前已有转写任务在运行");
//            return;
//        }

        // 保存回调上下文
        transcribeCallback = callbackContext;

        // 录音权限动态申请
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            // 检查该权限是否已经获取
            int i = cordova.getActivity().checkSelfPermission(Manifest.permission.RECORD_AUDIO);
            // 权限是否已经 授权 GRANTED---授权  DINIED---拒绝
            if (i != PackageManager.PERMISSION_GRANTED) {
                // 如果没有授予该权限，就去提示用户请求
                PermissionHelper.requestPermission(this, PERMISSION_RECORD_AUDIO, Manifest.permission.RECORD_AUDIO);
                return;
            }
        }

        if (ActivityCompat.checkSelfPermission(cordova.getActivity(), Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            // 初始化音频录制器
            initAudioRecorder();


            //设置相关识别参数，具体参考API文档，在startDialog前调用
            String setParamsString = genParams();
            Log.i(TAG, "nui set params " + setParamsString);
            nui_instance.setParams(setParamsString);
            //开始实时识别
            int ret = nui_instance.startDialog(Constants.VadMode.TYPE_P2T,
                    genDialogParams());
            Log.i(TAG, "start done with " + ret);
            if (ret == Constants.NuiResultCode.SUCCESS) {
                Log.i(TAG, "实时转写启动成功");
                isTranscribing = true;
            }


        } else {
            Log.e(TAG, "donnot get RECORD_AUDIO permission!");
            sendCallback("error", "未获得录音权限，无法正常运行。请通过设置界面重新开启权限。");
            Log.e(TAG, "录音权限申请失败");
        }
    }

    // ====================== 停止转写 ======================
    private void stopTranscription(CallbackContext callbackContext) {
        long stopResult = nui_instance.stopDialog();
        if (stopResult == 0) {
            isTranscribing = false;
            callbackContext.success("Recognition stopped 停止语音识别成功");
            Log.i(TAG, "转写停止成功");
        } else {
            callbackContext.error("转写停止失败，错误码：" + stopResult);
            Log.e(TAG, "停止转写失败，错误码：" + stopResult);
        }

    }

    // ====================== 释放所有资源 ======================
    private void releaseAllResources(CallbackContext callbackContext) {
        workerHandler.post(() -> {
            try {
                // 停止转写
                if (isTranscribing) {
                    nui_instance.stopDialog();
                    isTranscribing = false;
                }

                // 释放 SDK
                if (nui_instance != null) {
                    nui_instance.release();
                    nui_instance = null;
                }

                // 释放音频资源
                releaseAudioRecorder();

                isSdkInitialized = false;
                callbackContext.success("所有资源已释放");
                Log.i(TAG, "资源释放完成");
            } catch (Exception e) {
                callbackContext.error("释放资源异常：" + e.getMessage());
                Log.e(TAG, "释放资源异常", e);
            }
        });
    }

    // ====================== 辅助方法 ======================


    /**
     * 初始化音频录制器
     */
    private void initAudioRecorder() {
        if (audioRecorder == null) {
            try {
                //录音初始化，录音参数中格式只支持16bit/单通道，采样率支持8K/16K
                //使用者请根据实际情况选择Android设备的MediaRecorder.AudioSource
                //录音麦克风如何选择,可查看https://developer.android.google.cn/reference/android/media/MediaRecorder.AudioSource
                if (ActivityCompat.checkSelfPermission( cordova.getContext() , Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                    // TODO: Consider calling
                    //    ActivityCompat#requestPermissions
                    // here to request the missing permissions, and then overriding
                    //   public void onRequestPermissionsResult(int requestCode, String[] permissions,
                    //                                          int[] grantResults)
                    // to handle the case where the user grants the permission. See the documentation
                    // for ActivityCompat#requestPermissions for more details.
                    return;
                }
                audioRecorder = new AudioRecord(
                        MediaRecorder.AudioSource.DEFAULT,
                        SAMPLE_RATE,
                        AudioFormat.CHANNEL_IN_MONO,
                        AudioFormat.ENCODING_PCM_16BIT,
                        1 * 4 //todo
                );
                Log.d(TAG, "AudioRecorder new ...");
            } catch (Exception e) {
                Log.e(TAG, "初始化音频录制器失败", e);
                sendCallback("error", "初始化录音失败：" + e.getMessage());
            }
        } else {
            Log.w(TAG, "AudioRecord has been new ...");
        }
    }

    /**
     * 释放音频录制资源
     */
    private void releaseAudioRecorder() {
        // 停止并释放录音器
        if (audioRecorder != null) {
            if (audioRecorder.getState() == AudioRecord.STATE_INITIALIZED) {
                audioRecorder.stop();
                audioRecorder.release();
            }
            audioRecorder = null;
        }

        // 关闭音频文件流
        if (audioFileStream != null) {
            try {
                audioFileStream.close();
                audioFileStream = null;
                sendCallback("info", "音频已保存至：" + audioSavePath);
                Log.i(TAG, "音频保存路径：" + audioSavePath);
            } catch (IOException e) {
                Log.e(TAG, "关闭音频文件失败", e);
            }
        }

        // 清空音频队列
        audioQueue.clear();
    }

    /**
     * 保存音频数据到本地
     */
    private void saveAudioData(byte[] buffer) {
        if (!isSaveAudio || buffer.length == 0) {
            return;
        }

        try {
            // 初始化音频文件
            if (audioFileStream == null && !TextUtils.isEmpty(currentTaskId)) {
                audioSavePath = debugPath + "/transcribe_" + currentTaskId + ".pcm";
                audioFileStream = new FileOutputStream(audioSavePath, true);
                Log.i(TAG, "开始保存音频：" + audioSavePath);
            }

            // 写入缓存队列数据
            if (audioFileStream != null && !audioQueue.isEmpty()) {
                audioFileStream.write(audioQueue.take());
            }

            // 写入当前音频数据
            if (audioFileStream != null) {
                audioFileStream.write(buffer);
            } else {
                audioQueue.offer(buffer);
            }
        } catch (IOException | InterruptedException e) {
            Log.e(TAG, "保存音频失败", e);
        }
    }

    /**
     * 向 JS 发送回调结果
     */
    private void sendCallback(String type, String message) {
        if (transcribeCallback == null) {
            return;
        }

        try {
            org.json.JSONObject result = new org.json.JSONObject();
            result.put("type", type); // start/partial/complete/error/info/stop/vad_start/vad_end
            result.put("message", message);
            result.put("taskId", currentTaskId);

            PluginResult pluginResult = new PluginResult(PluginResult.Status.OK, result);
            pluginResult.setKeepCallback(true); // 保持回调通道打开
            transcribeCallback.sendPluginResult(pluginResult);
        } catch (Exception e) {
            Log.e(TAG, "发送回调失败", e);
        }
    }

    // ====================== 权限与 SDK 回调 ======================
    /**
     * 权限请求回调
     */
    @Override
    public void onRequestPermissionResult(int requestCode, String[] permissions, int[] grantResults) throws org.json.JSONException {
        super.onRequestPermissionResult(requestCode, permissions, grantResults);
        if (requestCode == PERMISSION_RECORD_AUDIO) {
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                //startTranscription(transcribeCallback);
                Log.i(TAG, "录音权限申请成功");
            } else {
                sendCallback("error", "拒绝录音权限将无法使用语音转写功能");
                Log.e(TAG, "录音权限申请失败");
            }
        } else if (requestCode == PERMISSION_WRITE_STORAGE) {
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                // 存储权限获取成功，继续初始化
                initSDKAfterPermissionGranted();
                Log.i(TAG, "存储权限申请成功");
            } else {
                transcribeCallback.error("拒绝存储权限将无法拷贝SDK资源文件");
                Log.e(TAG, "存储权限申请失败");
            }
        }
    }

    // 权限获取后继续初始化
    private void initSDKAfterPermissionGranted() {
        // workerHandler.post(() -> {
        try {

            // 生成初始化参数
            String initParams = genInitParams("", mDebugPath);
            // 初始化 SDK
            int initResult = nui_instance.initialize(
                    this,
                    initParams,
                    Constants.LogLevel.LOG_LEVEL_VERBOSE,
                    true
            );

            if (initResult == Constants.NuiResultCode.SUCCESS) {
                isSdkInitialized = true;
                transcribeCallback.success("SDK 初始化成功");
                Log.i(TAG, "SDK 初始化完成");
            } else {
                isSdkInitialized = true;//todo
                String errorMsg = CommonUtils.getMsgWithErrorCode(initResult, "初始化");
                //transcribeCallback.error("SDK 初始化失败：" + errorMsg);
                Log.e(TAG, "SDK 初始化失败：" + errorMsg);
            }
        } catch (Exception e) {
            //transcribeCallback.error("SDK 初始化异常：" + e.getMessage());
            Log.e(TAG, "SDK 初始化异常", e);
        }
        //});
    }

    /**
     * SDK 事件回调
     */
    @Override
    public void onNuiEventCallback(Constants.NuiEvent event, int resultCode, int arg2, KwsResult kwsResult, AsrResult asrResult) {
        Log.i(TAG, "SDK 事件：" + event + "，错误码：" + resultCode);

        // 解析 TaskId
        if (asrResult != null && !TextUtils.isEmpty(asrResult.allResponse)) {
            try {
                currentTaskId = "0"; //todo //JSON.parseObject(asrResult.allResponse).getJSONObject("header").getString("task_id");
            } catch (Exception e) {
                Log.w(TAG, "解析 TaskId 失败", e);
            }
        }

        // 处理不同事件
        switch (event) {
            case EVENT_TRANSCRIBER_STARTED:
                sendCallback("start", "转写连接成功，开始采集音频");
                break;
            case EVENT_ASR_PARTIAL_RESULT:
            case EVENT_SENTENCE_END:
                if (asrResult != null && !TextUtils.isEmpty(asrResult.asrResult)) {
                    sendCallback("partial", asrResult.asrResult);
                }
                break;
            case EVENT_VAD_START:
                sendCallback("vad_start", "检测到语音开始");
                break;
            case EVENT_VAD_END:
                sendCallback("vad_end", "检测到语音结束");
                break;
            case EVENT_TRANSCRIBER_COMPLETE:
                isTranscribing = false;
                releaseAudioRecorder();
                sendCallback("complete", asrResult != null ? asrResult.asrResult : "转写完成，无结果");
                transcribeCallback.success(); // 关闭回调通道
                break;
            case EVENT_ASR_ERROR:
                isTranscribing = false;
                releaseAudioRecorder();
                String errorMsg = CommonUtils.getMsgWithErrorCode(resultCode, "转写");
                sendCallback("error", errorMsg + "（错误码：" + resultCode + "）");
                transcribeCallback.error(errorMsg);
                break;
            case EVENT_MIC_ERROR:
                isTranscribing = false;
                releaseAudioRecorder();
                sendCallback("error", "麦克风异常：" + CommonUtils.getMsgWithErrorCode(resultCode, "录音"));
                transcribeCallback.error("麦克风异常");
                break;
            default:
                Log.i(TAG, "未处理的 SDK 事件：" + event);
                break;
        }
    }

    /**
     * SDK 音频数据请求回调
     */
    @Override
    public int onNuiNeedAudioData(byte[] buffer, int len) {
        if (audioRecorder == null || audioRecorder.getState() != AudioRecord.STATE_INITIALIZED) {
            Log.e(TAG, "音频录制器未初始化");
            return -1;
        }

        // 读取音频数据
        int audioLength = audioRecorder.read(buffer, 0, len);
        // 保存音频（如果开启）
        if (audioLength > 0) {
            saveAudioData(buffer);
        }

        return audioLength;
    }

    /**
     * 音频状态变更回调
     */
    @Override
    public void onNuiAudioStateChanged(Constants.AudioState state) {
        Log.i(TAG, "音频状态变更：" + state);
        switch (state) {
            case STATE_OPEN:
                if (audioRecorder != null) {
                    audioRecorder.startRecording();
                }
                break;
            case STATE_CLOSE:
            case STATE_PAUSE:
                releaseAudioRecorder();
                break;
        }
    }

    // ====================== 空实现回调 ======================
    @Override
    public void onNuiAudioRMSChanged(float val) {}

    @Override
    public void onNuiVprEventCallback(Constants.NuiVprEvent event) {}

    @Override
    public void onNuiLogTrackCallback(Constants.LogLevel level, String log) {
        Log.i(TAG, "SDK 日志：" + level + " -> " + log);
    }



    private String g_appkey = "";
    private String g_token = "";
    private String g_sts_token = "";
    private String g_ak = "";
    private String g_sk = "";
    private String g_url = "";

    private String mDebugPath = "";

    private String genInitParams(String workpath, String debug_path) {
        String str = "";
        try{
            //获取账号访问凭证：
            Auth.GetTicketMethod method = Auth.GetTicketMethod.GET_TOKEN_FROM_SERVER_FOR_ONLINE_FEATURES;
            if (!g_appkey.isEmpty()) {
                Auth.setAppKey(g_appkey);
            }
            if (!g_token.isEmpty()) {
                Auth.setToken(g_token);
            }
            if (!g_ak.isEmpty()) {
                Auth.setAccessKey(g_ak);
            }
            if (!g_sk.isEmpty()) {
                Auth.setAccessKeySecret(g_sk);
            }
            Auth.setStsToken(g_sts_token);
            // 此处展示将用户传入账号信息进行交互，实际产品不可以将任何账号信息存储在端侧
            if (!g_appkey.isEmpty()) {
                if (!g_ak.isEmpty() && !g_sk.isEmpty()) {
                    if (g_sts_token.isEmpty()) {
                        method = Auth.GetTicketMethod.GET_ACCESS_IN_CLIENT_FOR_ONLINE_FEATURES;
                    } else {
                        method = Auth.GetTicketMethod.GET_STS_ACCESS_IN_CLIENT_FOR_ONLINE_FEATURES;
                    }
                }
                if (!g_token.isEmpty()) {
                    method = Auth.GetTicketMethod.GET_TOKEN_IN_CLIENT_FOR_ONLINE_FEATURES;
                }
            }
            Log.i(TAG, "Use method:" + method);
            com.alibaba.fastjson.JSONObject object = Auth.getTicket(method);
            if (!object.containsKey("token")) {
                Log.e(TAG, "Cannot get token !!! 未获得有效临时凭证");

            }

            object.put("device_id", "empty_device_id"); // 必填, 推荐填入具有唯一性的id, 方便定位问题
            // if (g_url.isEmpty()) {
            //     g_url = "wss://nls-gateway.cn-shanghai.aliyuncs.com:443/ws/v1"; // 默认
            // }
            g_url = "wss://nls-gateway.cn-shanghai.aliyuncs.com:443/ws/v1"; // 还原到上海节点
            object.put("url", g_url);

            //工作目录路径，SDK从该路径读取配置文件
//            object.put("workspace", workpath); // V2.6.2版本开始纯云端功能可不设置workspace

            //当初始化SDK时的save_log参数取值为true时，该参数生效。表示是否保存音频debug，该数据保存在debug目录中，需要确保debug_path有效可写。
            object.put("save_wav", "true");
            //debug目录，当初始化SDK时的save_log参数取值为true时，该目录用于保存中间音频文件。
            object.put("debug_path", debug_path);
            //设置本地存储日志文件的最大字节数, 最大将会在本地存储2个设置字节大小的日志文件
            object.put("max_log_file_size", 50 * 1024 * 1024);

            //过滤SDK内部日志通过回调送回到用户层
            object.put("log_track_level", String.valueOf(Constants.LogLevel.toInt(Constants.LogLevel.LOG_LEVEL_NONE)));

            // FullMix = 0   // 选用此模式开启本地功能并需要进行鉴权注册
            // FullCloud = 1
            // FullLocal = 2 // 选用此模式开启本地功能并需要进行鉴权注册
            // AsrMix = 3    // 选用此模式开启本地功能并需要进行鉴权注册
            // AsrCloud = 4
            // AsrLocal = 5  // 选用此模式开启本地功能并需要进行鉴权注册
            // 这里只能选择FullMix和FullCloud
            object.put("service_mode", Constants.ModeFullCloud); // 必填
            str = object.toString();
        } catch (Exception e) {
            e.printStackTrace();
        }

        // 注意! str中包含ak_id ak_secret token app_key等敏感信息, 实际产品中请勿在Log中输出这类信息！
        Log.i(TAG, "InsideUserContext:" + str);
        return str;
    }



    private String genParams() {
        String params = "";
        try {
            com.alibaba.fastjson.JSONObject nls_config = new com.alibaba.fastjson.JSONObject();

            //参数可根据实际业务进行配置
            //接口说明可见https://help.aliyun.com/document_detail/173528.html
            //查看 2.开始识别

            // 是否返回中间识别结果，默认值：False。
            nls_config.put("enable_intermediate_result", true);
            // 是否在后处理中添加标点，默认值：False。
            nls_config.put("enable_punctuation_prediction", true);

            nls_config.put("sample_rate", 16000);
            nls_config.put("sr_format","opus"); // mFormatSpin.getSelectedItem().toString()
//            nls_config.put("enable_inverse_text_normalization", true);
//            nls_config.put("max_sentence_silence", 800);
//            nls_config.put("enable_words", false);

            // 设置文档中不存在的参数, key为custom_params, value以json string的形式设置参数
            // 如下示例传入{vocabulary:{"热词1":2,"热词2":2}} 表示在payload下添加参数
            // payload.vocabulary : {"热词1":2,"热词2":2}
//            com.alibaba.fastjson.JSONObject extend_config = new com.alibaba.fastjson.JSONObject();
//            com.alibaba.fastjson.JSONObject vocab = new com.alibaba.fastjson.JSONObject();
//            vocab.put("热词1", 2);
//            vocab.put("热词2", 2);
//            extend_config.put("vocabulary", vocab);
//            nls_config.put("extend_config", extend_config);

            com.alibaba.fastjson.JSONObject tmp = new com.alibaba.fastjson.JSONObject();
            tmp.put("nls_config", nls_config);
            tmp.put("service_type", Constants.kServiceTypeSpeechTranscriber); // 必填

//            如果有HttpDns则可进行设置
//            tmp.put("direct_ip", Utils.getDirectIp());

            params = tmp.toString();
        } catch (Exception e) {
            e.printStackTrace();
        }
        return params;
    }


    /**
     * 初始化TTS语音合成
     */
    private void initTTS(com.alibaba.fastjson.JSONObject config, CallbackContext callbackContext) {
        Log.i(TAG, "开始初始化TTS，workerHandler状态: " + (workerHandler != null ? "已初始化" : "未初始化"));
        try {
            // 从config中获取TTS相关参数，包括token
            if (config.containsKey("token")) {
                ttsToken = config.getString("token");
            }
            if (config.containsKey("voice")) {
                ttsVoice = config.getString("voice");
            }
            if (config.containsKey("format")) {
                ttsFormat = config.getString("format");
            }
            if (config.containsKey("sampleRate")) {
                ttsSampleRate = config.getInteger("sampleRate");
            }
            if (config.containsKey("volume")) {
                ttsVolume = config.getInteger("volume");
            }
            if (config.containsKey("speechRate")) {
                ttsSpeechRate = config.getInteger("speechRate");
            }
            if (config.containsKey("pitchRate")) {
                ttsPitchRate = config.getInteger("pitchRate");
            }

            // 创建TTS实例
            if (tts_instance == null) {
                tts_instance = new NativeNui(Constants.ModeType.MODE_STREAM_INPUT_TTS);
            }

            // 确保workerHandler已初始化
            if (workerHandler == null) {
                workerThread = new HandlerThread("TTSWorker");
                workerThread.start();
                workerHandler = new Handler(workerThread.getLooper());
                Log.i(TAG, "TTS Worker Handler已初始化");
            }

            // 验证必要的参数
            if (ttsToken.isEmpty()) {
                callbackContext.error("TTS初始化失败：token参数为空");
                Log.e(TAG, "TTS Token为空");
                return;
            }

            // 获取appkey（如果initSDK未调用，则直接从manifest获取）
            String appKey = g_appkey;
            if (appKey.isEmpty()) {
                try {
                    Context context = this.cordova.getActivity().getApplicationContext();
                    ApplicationInfo appInfo = context.getPackageManager().getApplicationInfo(context.getPackageName(),
                            PackageManager.GET_META_DATA);
                    appKey = appInfo.metaData.getString("com.plugin.ai.speech.APPKEY");
                    Log.i(TAG, "从manifest获取TTS AppKey: " + (appKey != null ? appKey.substring(0, Math.min(5, appKey.length())) + "..." : "null"));

                    // 设置到全局变量
                    if (appKey != null && !appKey.isEmpty()) {
                        g_appkey = appKey;
                    }
                } catch (Exception e) {
                    Log.e(TAG, "获取TTS AppKey失败", e);
                }
            }

            if (appKey == null || appKey.isEmpty()) {
                callbackContext.error("TTS初始化失败：appkey未配置");
                Log.e(TAG, "TTS AppKey为空");
                return;
            }

            Log.i(TAG, "TTS初始化参数验证通过，token: " + ttsToken.substring(0, Math.min(10, ttsToken.length())) + ", appkey: " + appKey.substring(0, Math.min(5, appKey.length())) + "...");

            // 异步初始化TTS
            workerHandler.post(() -> {
                try {
                    // 生成TTS初始化参数
                    String ticket = genTTSTicket();
                    String parameters = genTTSParameters();

                    // 清理之前的状态
                    try {
                        Log.i(TAG, "初始化前清理TTS状态");
                        stopTTSPlayback(); // 清理音频播放状态
                        if (tts_instance != null) {
                            tts_instance.stopStreamInputTts();
                        }
                    } catch (Exception e) {
                        Log.w(TAG, "初始化清理TTS状态时出现异常", e);
                    }

                    // 初始化TTS SDK
                    int ret = tts_instance.startStreamInputTts(
                            new INativeStreamInputTtsCallback() {
                                @Override
                                public void onStreamInputTtsEventCallback(StreamInputTtsEvent event, String task_id, String session_id, int ret_code, String error_msg, String timestamp, String all_response) {
                                    Log.i(TAG, "TTS事件回调: " + event + ", ret_code: " + ret_code + ", error_msg: " + error_msg);
                                    handleTTSEvent(event, task_id, session_id, ret_code, error_msg, timestamp, all_response);
                                }

                                @Override
                                public void onStreamInputTtsDataCallback(byte[] data) {
                                    Log.i(TAG, "TTS数据回调: " + data.length + " bytes");
                                    handleTTSData(data);
                                }
                            },
                            ticket,
                            parameters,
                            "",
                            Constants.LogLevel.toInt(Constants.LogLevel.LOG_LEVEL_VERBOSE),
                            false
                    );

                    Log.i(TAG, "TTS SDK初始化结果: " + ret);

                    if (ret == Constants.NuiResultCode.SUCCESS) {
                        isTTSInitialized = true;
                        callbackContext.success("TTS初始化成功");
                        Log.i(TAG, "TTS初始化完成");
                    } else {
                        // 重置运行状态
                        isTTSRunning = false;
                        String errorMsg = "TTS初始化失败，错误码：" + ret;
                        callbackContext.error(errorMsg);
                        Log.e(TAG, errorMsg);
                    }
                } catch (Exception e) {
                    // 重置运行状态
                    isTTSRunning = false;
                    callbackContext.error("TTS初始化异常：" + e.getMessage());
                    Log.e(TAG, "TTS初始化异常", e);
                }
            });
        } catch (Exception e) {
            // 重置运行状态
            isTTSRunning = false;
            callbackContext.error("TTS初始化参数解析失败：" + e.getMessage());
            Log.e(TAG, "TTS初始化参数解析异常", e);
        }
    }


    private String genDialogParams() {
        String params = "";
        try {
            com.alibaba.fastjson.JSONObject dialog_param = new com.alibaba.fastjson.JSONObject();
            // 运行过程中可以在startDialog时更新临时参数，尤其是更新过期token
            // 注意: 若下一轮对话不再设置参数，则继续使用初始化时传入的参数
            long distance_expire_time_30m = 1800;
            dialog_param = Auth.refreshTokenIfNeed(dialog_param, distance_expire_time_30m);

            // 注意: 若需要更换appkey和token，可以直接传入参数
//            dialog_param.put("app_key", "");
//            dialog_param.put("token", "");
            params = dialog_param.toString();
        } catch (Exception e) {
            e.printStackTrace();
        }
        return params;
    }

    /**
     * 发送TTS文本（流式）
     */
    private void sendTTSText(String text, CallbackContext callbackContext) {
        try {
            if (!isTTSInitialized) {
                callbackContext.error("TTS未初始化，无法发送文本");
                return;
            }

            // 异步发送文本
            workerHandler.post(() -> {
                try {
                    // 如果TTS实例未启动，先启动它
                    if (!isTTSRunning) {
                        Log.i(TAG, "TTS实例未启动，先启动TTS服务");

                        // 强制清理之前的状态
                        try {
                            if (tts_instance != null) {
                                Log.i(TAG, "清理旧的TTS实例状态");
                                tts_instance.stopStreamInputTts();
                            }
                            stopTTSPlayback(); // 清理音频播放状态
                        } catch (Exception e) {
                            Log.w(TAG, "清理TTS状态时出现异常，继续启动", e);
                        }

                        int startRet = tts_instance.startStreamInputTts(
                                this, // 添加callback参数
                                genTTSTicket(),
                                genTTSParameters(),
                                "",
                                Constants.LogLevel.toInt(Constants.LogLevel.LOG_LEVEL_DEBUG),
                                true
                        );

                        if (startRet != Constants.NuiResultCode.SUCCESS) {
                            callbackContext.error("启动TTS服务失败，错误码：" + startRet);
                            Log.e(TAG, "启动TTS服务失败，错误码：" + startRet);
                            return;
                        }

                        isTTSRunning = true;
                        Log.i(TAG, "TTS服务启动成功");

                        // 等待一小段时间确保连接建立
                        Thread.sleep(100);
                    }

                    int ret = tts_instance.sendStreamInputTts(text);
                    if (ret == Constants.NuiResultCode.SUCCESS) {
                        callbackContext.success("TTS文本发送成功");
                        Log.i(TAG, "TTS文本发送成功: " + text);

                        // 发送完成后调用stop接口，表示发送结束
                        int stopRet = tts_instance.stopStreamInputTts();
                        if (stopRet == Constants.NuiResultCode.SUCCESS) {
                            Log.i(TAG, "发送完成后停止接口调用成功");
                        } else {
                            Log.e(TAG, "发送完成后停止接口调用失败，错误码: " + stopRet);
                        }
                    } else {
                        String errorMsg = "TTS文本发送失败，错误码：" + ret;
                        callbackContext.error(errorMsg);
                        Log.e(TAG, errorMsg);
                    }
                } catch (Exception e) {
                    callbackContext.error("TTS文本发送异常：" + e.getMessage());
                    Log.e(TAG, "TTS文本发送异常", e);
                }
            });
        } catch (Exception e) {
            callbackContext.error("发送TTS文本失败：" + e.getMessage());
            Log.e(TAG, "发送TTS文本异常", e);
        }
    }

    /**
     * 停止TTS
     */
    private void stopTTS(CallbackContext callbackContext) {
        try {
            if (!isTTSInitialized || !isTTSRunning) {
                callbackContext.error("TTS未初始化或未运行");
                return;
            }

            // 异步停止TTS
            workerHandler.post(() -> {
                try {
                    tts_instance.stopStreamInputTts();
                    isTTSRunning = false;
                    // 停止音频播放
                    stopTTSPlayback();
                    callbackContext.success("TTS停止成功");
                    Log.i(TAG, "TTS停止成功");
                } catch (Exception e) {
                    callbackContext.error("停止TTS异常：" + e.getMessage());
                    Log.e(TAG, "停止TTS异常", e);
                }
            });
        } catch (Exception e) {
            callbackContext.error("停止TTS失败：" + e.getMessage());
            Log.e(TAG, "停止TTS异常", e);
        }
    }

    /**
     * 释放TTS资源
     */
    private void releaseTTSResources(CallbackContext callbackContext) {
        try {
            // 异步释放TTS资源
            workerHandler.post(() -> {
                try {
                    // 停止音频播放
                    stopTTSPlayback();

                    if (tts_instance != null) {
                        tts_instance.release();
                        tts_instance = null;
                    }
                    isTTSInitialized = false;
                    isTTSRunning = false;
                    ttsCallback = null;
                    callbackContext.success("TTS资源释放成功");
                    Log.i(TAG, "TTS资源释放完成");
                } catch (Exception e) {
                    callbackContext.error("释放TTS资源异常：" + e.getMessage());
                    Log.e(TAG, "释放TTS资源异常", e);
                }
            });
        } catch (Exception e) {
            callbackContext.error("释放TTS资源失败：" + e.getMessage());
            Log.e(TAG, "释放TTS资源异常", e);
        }
    }

    /**
     * 生成TTS初始化参数
     */
    private String genTTSTicket() {
        String ticket = "";
        try {
            com.alibaba.fastjson.JSONObject object = new com.alibaba.fastjson.JSONObject();

            Log.i(TAG, "使用TTS Token: " + (ttsToken.isEmpty() ? "空" : ttsToken.substring(0, Math.min(10, ttsToken.length())) + "..."));

            // 使用token参数进行认证
            object.put("token", ttsToken); // 使用token参数
            object.put("appkey", g_appkey); // 使用全局变量g_appkey
            object.put("url", "wss://nls-gateway.cn-shanghai.aliyuncs.com:443/ws/v1"); // 还原到上海节点
            object.put("device_id", "cordova_tts_device"); // 必填参数

            // 添加调试路径
            if (!mDebugPath.isEmpty()) {
                object.put("debug_path", mDebugPath);
                object.put("max_log_file_size", 50 * 1024 * 1024);
            }

            // 启用更多日志来调试
            object.put("log_track_level", String.valueOf(Constants.LogLevel.toInt(Constants.LogLevel.LOG_LEVEL_DEBUG)));

            ticket = object.toString();
            Log.i(TAG, "TTS Ticket已生成: " + ticket);
        } catch (Exception e) {
            e.printStackTrace();
        }
        Log.i(TAG, "TTS ticket: " + ticket);
        return ticket;
    }

    /**
     * 生成TTS参数
     */
    private String genTTSParameters() {
        String params = "";
        try {
            com.alibaba.fastjson.JSONObject object = new com.alibaba.fastjson.JSONObject();
            object.put("voice", "xiaoyun"); // 使用最基本的声音
            object.put("format", "pcm");
            object.put("sample_rate", 24000); // 使用官方demo的采样率
            object.put("volume", 50);
            object.put("speech_rate", 0);
            object.put("pitch_rate", 0);
            object.put("enable_subtitle", false); // 关闭字级别时间戳
            object.put("enable_audio_decoder", false); // 关闭音频解码器

            // 简化参数，只保留最基本的
            Log.i(TAG, "TTS参数简化版:");
            Log.i(TAG, "  voice: xiaoyun");
            Log.i(TAG, "  format: pcm");
            Log.i(TAG, "  sample_rate: 24000");
            Log.i(TAG, "  volume: 50");
            Log.i(TAG, "  speech_rate: 0");
            Log.i(TAG, "  pitch_rate: 0");
            Log.i(TAG, "  enable_subtitle: false");
            Log.i(TAG, "  enable_audio_decoder: false");

            params = object.toString();
        } catch (Exception e) {
            e.printStackTrace();
        }
        Log.i(TAG, "TTS parameters: " + params);
        return params;
    }

    /**
     * 处理TTS事件回调
     */
    private void handleTTSEvent(INativeStreamInputTtsCallback.StreamInputTtsEvent event,
                                String task_id, String session_id, int ret_code,
                                String error_msg, String timestamp, String all_response) {
        Log.d(TAG, "TTS event: " + event + ", session: " + session_id + ", task: " + task_id);

        // 处理特定的TTS事件
        switch (event) {
            case STREAM_INPUT_TTS_EVENT_SYNTHESIS_STARTED:
                Log.i(TAG, "TTS语音合成开始");
                // 重置完成标志
                isFinishSend = false;
                // 强制重新创建AudioTrack以确保播放正常
                Log.i(TAG, "预创建AudioTrack");
                playTTSData(new byte[0]); // 传入空数据来创建AudioTrack
                break;
            case STREAM_INPUT_TTS_EVENT_SYNTHESIS_COMPLETE:
                Log.i(TAG, "TTS语音合成完成");
                // 设置完成标志，通知播放线程可以结束
                isFinishSend = true;
                break;
            case STREAM_INPUT_TTS_EVENT_TASK_FAILED:
                Log.e(TAG, "TTS任务失败: " + error_msg);
                // 设置完成标志，通知播放线程可以结束
                isFinishSend = true;
                break;
            default:
                Log.d(TAG, "其他TTS事件: " + event);
                break;
        }

        if (ttsCallback != null) {
            com.alibaba.fastjson.JSONObject fastResult = new com.alibaba.fastjson.JSONObject();
            try {
                fastResult.put("type", "tts_event");
                fastResult.put("event", event.toString());
                fastResult.put("taskId", task_id);
                fastResult.put("sessionId", session_id);
                fastResult.put("retCode", ret_code);
                fastResult.put("errorMsg", error_msg != null ? error_msg : "");
                fastResult.put("timestamp", timestamp != null ? timestamp : "");
                fastResult.put("allResponse", all_response != null ? all_response : "");

                // 转换为org.json.JSONObject以便Cordova使用
                org.json.JSONObject result = new org.json.JSONObject(fastResult.toJSONString());
                PluginResult pluginResult = new PluginResult(PluginResult.Status.OK, result);
                pluginResult.setKeepCallback(true);
                ttsCallback.sendPluginResult(pluginResult);
            } catch (com.alibaba.fastjson.JSONException e) {
                Log.e(TAG, "TTS事件回调JSON构建失败", e);
            } catch (Exception e) {
                Log.e(TAG, "TTS事件回调JSON转换失败", e);
            }
        }
    }

    /**
     * 处理TTS数据回调
     */
    private void handleTTSData(byte[] data) {
        Log.i(TAG, "TTS数据回调被调用，数据长度: " + data.length);
        Log.d(TAG, "TTS data received, length: " + data.length);

        // 播放音频数据
        playTTSData(data);
    }

    /**
     * 播放TTS音频数据
     */
    private void playTTSData(byte[] data) {
        try {
            // 检查AudioTrack状态，如果未初始化或已停止，重新创建
            if (audioTrack == null || audioTrack.getState() != AudioTrack.STATE_INITIALIZED) {
                // 释放旧的AudioTrack
                if (audioTrack != null) {
                    try {
                        audioTrack.release();
                    } catch (Exception e) {
                        Log.e(TAG, "释放旧AudioTrack失败", e);
                    }
                }

                int bufferSize = AudioTrack.getMinBufferSize(
                        24000, // 使用官方demo的采样率
                        AudioFormat.CHANNEL_OUT_MONO,
                        AudioFormat.ENCODING_PCM_16BIT
                ) * 2; // 放大缓冲区

                audioTrack = new AudioTrack(
                        AudioManager.STREAM_MUSIC,
                        24000, // 使用官方demo的采样率
                        AudioFormat.CHANNEL_OUT_MONO,
                        AudioFormat.ENCODING_PCM_16BIT,
                        bufferSize,
                        AudioTrack.MODE_STREAM
                );

                // 启动播放线程
                startAudioPlayerThread();

                Log.i(TAG, "AudioTrack已创建，采样率: " + 24000 + ", 缓冲区大小: " + bufferSize);
            }

            // 将音频数据放入队列（只有非空数据才入队）
            if (data.length > 0) {
                ttsAudioQueue.offer(data);
                Log.d(TAG, "音频数据已入队，长度: " + data.length);
            }

        } catch (Exception e) {
            Log.e(TAG, "播放TTS音频失败", e);
        }
    }

    /**
     * 启动音频播放线程
     */
    private void startAudioPlayerThread() {
        if (audioPlayerThread == null) {
            audioPlayerThread = new Thread(() -> {
                try {
                    audioTrack.play();
                    isPlaying = true;
                    Log.i(TAG, "AudioTrack开始播放");

                    while (isPlaying) {
                        if (ttsAudioQueue.size() > 0) {
                            byte[] data = ttsAudioQueue.take();
                            audioTrack.write(data, 0, data.length);
                            Log.d(TAG, "音频数据已播放，长度: " + data.length);
                        } else {
                            if (isFinishSend) {
                                Log.i(TAG, "音频播放完成");
                                break;
                            }
                            Thread.sleep(10);
                        }
                    }
                } catch (InterruptedException e) {
                    Log.e(TAG, "音频播放线程被中断", e);
                }
            });
            audioPlayerThread.start();
        }
    }

    /**
     * 停止TTS音频播放
     */
    private void stopTTSPlayback() {
        isPlaying = false;
        isFinishSend = false;

        if (audioPlayerThread != null) {
            try {
                audioPlayerThread.interrupt();
                audioPlayerThread.join(1000); // 等待1秒
                audioPlayerThread = null;
            } catch (InterruptedException e) {
                Log.e(TAG, "停止音频播放线程失败", e);
            }
        }

        if (audioTrack != null) {
            try {
                audioTrack.stop();
                audioTrack.release();
                audioTrack = null;
                Log.i(TAG, "TTS音频播放已停止");
            } catch (Exception e) {
                Log.e(TAG, "停止AudioTrack失败", e);
            }
        }

        // 清空音频队列
        ttsAudioQueue.clear();
    }

    // ====================== INativeStreamInputTtsCallback 接口实现 ======================

    @Override
    public void onStreamInputTtsEventCallback(INativeStreamInputTtsCallback.StreamInputTtsEvent event,
                                              String task_id, String session_id,
                                              int ret_code, String error_msg,
                                              String timestamp, String all_response) {
        Log.d(TAG, "TTS event: " + event + ", session: " + session_id + ", task: " + task_id);
        handleTTSEvent(event, task_id, session_id, ret_code, error_msg, timestamp, all_response);
    }

    @Override
    public void onStreamInputTtsDataCallback(byte[] data) {
        if (data != null && data.length > 0) {
            Log.d(TAG, "TTS数据回调被调用，数据长度: " + data.length);
            handleTTSData(data);
        }
    }

    @Override
    public void onStreamInputTtsLogTrackCallback(Constants.LogLevel level, String log) {
        Log.i(TAG, "TTS Log Track - Level: " + level + ", Message: " + log);
    }

    // ====================== 状态检查函数 ======================

    /**
     * 检查语音识别是否已初始化
     */
    private void isInitialized(CallbackContext callbackContext) {
        try {
            boolean initialized = isSdkInitialized && (nui_instance != null);
            if (initialized) {
                callbackContext.success("true");
                Log.i(TAG, "语音识别已初始化");
            } else {
                callbackContext.success("false");
                Log.i(TAG, "语音识别未初始化");
            }
        } catch (Exception e) {
            callbackContext.error("检查语音识别初始化状态失败：" + e.getMessage());
            Log.e(TAG, "检查语音识别初始化状态异常", e);
        }
    }

    /**
     * 检查TTS是否已初始化
     */
    private void isTTSInitialized(CallbackContext callbackContext) {
        try {
            boolean initialized = isTTSInitialized && (tts_instance != null);
            if (initialized) {
                callbackContext.success("true");
                Log.i(TAG, "TTS已初始化");
            } else {
                callbackContext.success("false");
                Log.i(TAG, "TTS未初始化");
            }
        } catch (Exception e) {
            callbackContext.error("检查TTS初始化状态失败：" + e.getMessage());
            Log.e(TAG, "检查TTS初始化状态异常", e);
        }
    }

}
