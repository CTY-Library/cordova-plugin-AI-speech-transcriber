package com.plugin.aliyun.aispeech;

import android.Manifest;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.text.TextUtils;
import android.util.Log;

import androidx.core.app.ActivityCompat;

//import com.alibaba.fastjson.JSON;
//import com.alibaba.fastjson.JSONException;
//import com.alibaba.fastjson.JSONObject;
//import com.alibaba.fastjson.JSON;
import com.alibaba.idst.nui.AsrResult;
import com.alibaba.idst.nui.Constants;
import com.alibaba.idst.nui.INativeNuiCallback;
import com.alibaba.idst.nui.KwsResult;
import com.alibaba.idst.nui.NativeNui;
import com.alibaba.nls.client.AccessToken;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.PermissionHelper;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.LinkedBlockingQueue;

/**
 * 阿里云语音转写 Cordova 插件核心类
 * 功能：实时语音转写、权限管理、多状态回调、资源释放
 * 适配 Cordova 插件规范，无 UI 依赖
 */
public class AISpeechTranscriber extends CordovaPlugin implements INativeNuiCallback {
    // 日志标签
    private static final String TAG = "AliyunSpeechTranscriber";
    // 音频参数常量
    private static final int SAMPLE_RATE = 16000;
    private static final int WAVE_FRAME_SIZE = 20 * 2 * 1 * SAMPLE_RATE / 1000; // 20ms 音频帧
    // 权限请求码
    private static final int PERMISSION_RECORD_AUDIO = 1001;
    private static final int PERMISSION_WRITE_STORAGE = 1002;
    private static final int READ_EXTERNAL_STORAGE =1003;

    // 阿里云认证参数
    private String appKey;
    private String token;
    private String stsToken;
    private String accessKey;
    private String accessKeySecret;
    private String serviceUrl = "wss://nls-gateway.cn-shanghai.aliyuncs.com:443/ws/v1";

    // SDK 核心实例
    private NativeNui nuiInstance = new NativeNui();
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
    private String currentTaskId = "";
    private String debugPath;

    // 异步线程
    private HandlerThread workerThread;
    private Handler workerHandler;
    // Cordova 回调上下文
    private CallbackContext transcribeCallback;

    /**
     * Cordova 插件核心入口：处理 JS 调用的方法
     */
    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) {
        try {
            String version = nuiInstance.GetVersion();
            Log.i(TAG, "当前版本号 sdk version: " + version);

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
                default:
                    callbackContext.error("不支持的操作：" + action);
                    return false;
            }
        }  catch (Exception e) {
            callbackContext.error("操作失败：" + e.getMessage());
            Log.e(TAG, "执行操作异常", e);
            return false;
        }
    }

    // ====================== SDK 初始化 ======================
    // 1. 新增文件权限数组（合并录音+文件权限）
    private static final String[] ALL_PERMISSIONS = {
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.READ_EXTERNAL_STORAGE,
            Manifest.permission.WRITE_EXTERNAL_STORAGE
    };
    private static final int PERMISSION_REQUEST_CODE = 1001;
    private void initSDK(org.json.JSONObject config, CallbackContext callbackContext) {
        // 解析配置参数
        try {

            isSaveAudio = config.optBoolean("saveAudio", false);

            Context context = this.cordova.getActivity().getApplicationContext();
            // 获取ApplicationInfo中的元数据
            ApplicationInfo appInfo =  context.getPackageManager().getApplicationInfo(context.getPackageName(),
                    PackageManager.GET_META_DATA);

            // 读取配置的参数（与plugin.xml中android:name对应）
            appKey = appInfo.metaData.getString("com.plugin.ai.speech.APPKEY");
            accessKey = appInfo.metaData.getString("com.plugin.ai.speech.ACCESSKEYID");
            accessKeySecret = appInfo.metaData.getString("com.plugin.ai.speech.ACCESSKEYSECRET");
//            token = appInfo.metaData.getString("com.plugin.ai.speech.TOKEN");
//            stsToken = appInfo.metaData.getString("com.plugin.ai.speech.STSTOKEN");
            serviceUrl = appInfo.metaData.getString("com.plugin.ai.speech.SERVICEURL", serviceUrl);

            AccessToken accessToken = new AccessToken(accessKey, accessKeySecret);
            accessToken.apply();
            token = accessToken.getToken();
            long expireTime = accessToken.getExpireTime();

            // 校验必要参数
            if (TextUtils.isEmpty(appKey)) {
                callbackContext.error("appKey 不能为空");
                return;
            }

            // 初始化异步线程
            if (workerThread == null || !workerThread.isAlive()) {
                workerThread = new HandlerThread("SpeechTranscriber-Worker");
                workerThread.start();
                workerHandler = new Handler(workerThread.getLooper());
            }

            // 创建调试目录
            debugPath = cordova.getActivity().getExternalCacheDir().getAbsolutePath() + "/speech_debug";
            CommonUtils.createDir(debugPath);

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


//                if (cordova.getActivity().checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
//                    // 动态请求存储权限
//                    PermissionHelper.requestPermission(this, PERMISSION_WRITE_STORAGE, Manifest.permission.WRITE_EXTERNAL_STORAGE);
//                    return;
//                }
//
//                if (cordova.getActivity().checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
//                    // 动态请求存储权限
//                    PermissionHelper.requestPermission(this, READ_EXTERNAL_STORAGE, Manifest.permission.READ_EXTERNAL_STORAGE);
//                    return;
//                }
//
//                // 检查录音权限
//                if (cordova.getActivity().checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
//                    // 动态请求存储权限
//                    PermissionHelper.requestPermission(this, PERMISSION_RECORD_AUDIO, Manifest.permission.RECORD_AUDIO);
//                    return;
//                }

            }



            // 拷贝 SDK 资源文件并验证结果
//            if (!CommonUtils.copyAssetsData(cordova.getActivity())) {
//                callbackContext.error("拷贝 SDK 资源文件失败，错误码240021");
//                return;
//            }

            Log.i(TAG, "SDK资源文件拷贝完成");

            initSDKAfterPermissionGranted();

        } catch (Exception e) {
            callbackContext.error("初始化参数解析失败：" + e.getMessage());
            Log.e(TAG, "初始化参数解析异常", e);
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
        if (isTranscribing) {
            callbackContext.error("当前已有转写任务在运行");
            return;
        }

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

            // 异步启动转写
            workerHandler.post(() -> {
                try {
                    // 设置转写参数
                    String asrParams = generateAsrParams();
                    Log.i(TAG, "nui set params " + asrParams);
                    nuiInstance.setParams(asrParams);

                    // 启动实时转写（核心调用）
                    int startResult = nuiInstance.startDialog(Constants.VadMode.TYPE_P2T, generateDialogParams());
                    Log.i(TAG, "start done with " + startResult);

                    if (startResult == Constants.NuiResultCode.SUCCESS) {
                        isTranscribing = true;
                        isStopping = false;
                        sendCallback("start", "实时转写已启动");
                        Log.i(TAG, "实时转写启动成功");
                    } else {
                        String errorMsg = CommonUtils.getMsgWithErrorCode(startResult, "启动转写");
                        sendCallback("error", "启动转写失败：" + errorMsg);
                        Log.e(TAG, "启动转写失败：" + errorMsg);
                    }
                } catch (Exception e) {
                    sendCallback("error", "启动转写异常：" + e.getMessage());
                    Log.e(TAG, "启动转写异常", e);
                }
            });
        } else {
            Log.e(TAG, "donnot get RECORD_AUDIO permission!");
            sendCallback("error", "未获得录音权限，无法正常运行。请通过设置界面重新开启权限。");
            Log.e(TAG, "录音权限申请失败");
        }
    }

    // ====================== 停止转写 ======================
    private void stopTranscription(CallbackContext callbackContext) {
        if (!isTranscribing) {
            callbackContext.error("暂无运行中的转写任务");
            return;
        }

        workerHandler.post(() -> {
            try {
                isStopping = true;
                long stopResult = nuiInstance.stopDialog();
                isTranscribing = false;

                // 释放音频资源
                releaseAudioRecorder();

                if (stopResult == 0) {
                    callbackContext.success("转写已停止");
                    sendCallback("stop", "转写停止成功");
                    Log.i(TAG, "转写停止成功");
                } else {
                    callbackContext.error("停止转写失败，错误码：" + stopResult);
                    Log.e(TAG, "停止转写失败，错误码：" + stopResult);
                }
            } catch (Exception e) {
                callbackContext.error("停止转写异常：" + e.getMessage());
                Log.e(TAG, "停止转写异常", e);
            }
        });
    }

    // ====================== 释放所有资源 ======================
    private void releaseAllResources(CallbackContext callbackContext) {
        workerHandler.post(() -> {
            try {
                // 停止转写
                if (isTranscribing) {
                    nuiInstance.stopDialog();
                    isTranscribing = false;
                }

                // 释放 SDK
                if (nuiInstance != null) {
                    nuiInstance.release();
                    nuiInstance = null;
                }

                // 释放音频资源
                releaseAudioRecorder();

                // 停止异步线程
                if (workerThread != null) {
                    workerThread.quit();
                    workerThread = null;
                }

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
     * 生成 SDK 初始化参数
     */
    private String generateInitParams() throws JSONException {
        JSONObject params = new JSONObject();

        // 设置认证参数
        Auth.GetTicketMethod authMethod = getAuthMethod();
        JSONObject authParams = Auth.getTicket(authMethod);

//        if (!authParams.containsKey("token") && !authParams.containsKey("access_key")) {
//            throw new RuntimeException("未获取到有效认证凭证");
//        }

        // 基础配置
        authParams.put("device_id", "android_" + Build.SERIAL);
        authParams.put("url", serviceUrl);
        authParams.put("workspace", CommonUtils.getModelPath(cordova.getActivity()));
        authParams.put("save_wav", "false");
        authParams.put("debug_path", debugPath);
        authParams.put("max_log_file_size", 50 * 1024 * 1024);
        authParams.put("log_track_level", Constants.LogLevel.toInt(Constants.LogLevel.LOG_LEVEL_NONE));
        authParams.put("service_mode", Constants.ModeFullCloud);

        return authParams.toString();
    }

    /**
     * 获取认证方式
     */
    private Auth.GetTicketMethod getAuthMethod() {
        Auth.GetTicketMethod method = Auth.GetTicketMethod.GET_TOKEN_FROM_SERVER_FOR_ONLINE_FEATURES;

        Auth.setAppKey(appKey);
        Auth.setToken(token);
        Auth.setAccessKey(accessKey);
        Auth.setAccessKeySecret(accessKeySecret);
        Auth.setStsToken(stsToken);

        if (!TextUtils.isEmpty(accessKey) && !TextUtils.isEmpty(accessKeySecret)) {
            method = TextUtils.isEmpty(stsToken)
                    ? Auth.GetTicketMethod.GET_ACCESS_IN_CLIENT_FOR_ONLINE_FEATURES
                    : Auth.GetTicketMethod.GET_STS_ACCESS_IN_CLIENT_FOR_ONLINE_FEATURES;
        } else if (!TextUtils.isEmpty(token)) {
            method = Auth.GetTicketMethod.GET_TOKEN_IN_CLIENT_FOR_ONLINE_FEATURES;
        }

        Log.i(TAG, "使用认证方式：" + method);
        return method;
    }

    /**
     * 生成转写参数
     */
    private String generateAsrParams() throws JSONException {
        JSONObject nlsConfig = new JSONObject();
        nlsConfig.put("enable_intermediate_result", true); // 开启实时中间结果
        nlsConfig.put("enable_punctuation_prediction", true); // 开启标点预测
        nlsConfig.put("sample_rate", SAMPLE_RATE);
        nlsConfig.put("sr_format", "opus");

        JSONObject root = new JSONObject();
        root.put("nls_config", nlsConfig);
        root.put("service_type", Constants.kServiceTypeSpeechTranscriber);

        return root.toString();
    }

    /**
     * 生成对话参数
     */
    private String generateDialogParams() throws JSONException {
        JSONObject params = new JSONObject();
        params = Auth.refreshTokenIfNeed(params, 1800); // 30分钟刷新 token
        return params.toString();
    }

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
                        WAVE_FRAME_SIZE * 4
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
        workerHandler.post(() -> {
            try {
                // 拷贝 SDK 资源文件并验证结果
//                if (!CommonUtils.copyAssetsData(cordova.getActivity())) {
//                    transcribeCallback.error("拷贝 SDK 资源文件失败，错误码240021");
//                    return;
//                }

                Log.i(TAG, "SDK资源文件拷贝完成");

                // 生成初始化参数
                String initParams = generateInitParams();
                // 初始化 SDK
                int initResult = nuiInstance.initialize(
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
        });
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

    // ====================== 阿里云认证辅助类 ======================
    private static class Auth {
        private static String appKey = "";
        private static String token = "";
        private static String accessKey = "";
        private static String accessKeySecret = "";
        private static String stsToken = "";

        public enum GetTicketMethod {
            GET_TOKEN_FROM_SERVER_FOR_ONLINE_FEATURES,
            GET_TOKEN_IN_CLIENT_FOR_ONLINE_FEATURES,
            GET_ACCESS_IN_CLIENT_FOR_ONLINE_FEATURES,
            GET_STS_ACCESS_IN_CLIENT_FOR_ONLINE_FEATURES
        }

        public static void setAppKey(String key) {
            appKey = key;
        }

        public static void setToken(String t) {
            token = t;
        }

        public static void setAccessKey(String ak) {
            accessKey = ak;
        }

        public static void setAccessKeySecret(String sk) {
            accessKeySecret = sk;
        }

        public static void setStsToken(String st) {
            stsToken = st;
        }

        public static JSONObject getTicket(GetTicketMethod method) throws JSONException {
            JSONObject ticket = new JSONObject();
            ticket.put("appkey", appKey);

            switch (method) {
                case GET_TOKEN_IN_CLIENT_FOR_ONLINE_FEATURES:
                    ticket.put("token", token);
                    break;
                case GET_ACCESS_IN_CLIENT_FOR_ONLINE_FEATURES:
                    ticket.put("access_key", accessKey);
                    ticket.put("access_key_secret", accessKeySecret);
                    break;
                case GET_STS_ACCESS_IN_CLIENT_FOR_ONLINE_FEATURES:
                    ticket.put("access_key", accessKey);
                    ticket.put("access_key_secret", accessKeySecret);
                    ticket.put("sts_token", stsToken);
                    break;
                default:
                    ticket.put("token", "");
                    break;
            }
            return ticket;
        }

        public static JSONObject refreshTokenIfNeed(JSONObject params, long expireTime) throws JSONException {
            // 此处可扩展 token 刷新逻辑
            return params;
        }
    }

    // ====================== 工具类 ======================
    private static class CommonUtils {
//        public static boolean copyAssetsData(android.content.Context context) {
//            try {
//                Log.i(TAG, "开始拷贝SDK资源文件");
//
//                // 获取assets中的资源文件列表
//                String[] assets = context.getAssets().list("");
//                if (assets == null || assets.length == 0) {
//                    Log.w(TAG, "Assets目录为空，跳过资源拷贝");
//                    return true; // 纯云端功能可不需要资源文件
//                }
//
//                Log.i(TAG, "Assets目录包含 " + assets.length + " 个文件");
//
//                // 目标目录
//                String targetDir = getModelPath(context);
//                java.io.File dir = new java.io.File(targetDir);
//                if (!dir.exists()) {
//                    boolean created = dir.mkdirs();
//                    Log.i(TAG, "创建目标目录: " + targetDir + ", 结果: " + created);
//                    if (!created) {
//                        Log.e(TAG, "无法创建目标目录: " + targetDir);
//                        return false;
//                    }
//                }
//
//                // 检查目录写权限
//                if (!dir.canWrite()) {
//                    Log.e(TAG, "目标目录无写权限: " + targetDir);
//                    return false;
//                }
//
//                int successCount = 0;
//                int skipCount = 0;
//
//                // 拷贝每个资源文件
////                for (String asset : assets) {
////                    // 跳过目录和特殊文件
////                    if (asset.contains(".") || asset.equalsIgnoreCase("images") ||
////                            asset.equalsIgnoreCase("sounds") || asset.equalsIgnoreCase("webkit")) {
////                        skipCount++;
////                        continue;
////                    }
////
////                    if (copyAssetFile(context, asset, targetDir + "/" + asset)) {
////                        successCount++;
////                    } else {
////                        Log.e(TAG, "拷贝文件失败: " + asset);
////                        return false;
////                    }
////                }
//
//                Log.i(TAG, "SDK资源文件拷贝完成 - 成功: " + successCount + ", 跳过: " + skipCount);
//                return true;
//            } catch (IOException e) {
//                Log.e(TAG, "拷贝SDK资源文件失败 - IO异常", e);
//                return false;
//            } catch (Exception e) {
//                Log.e(TAG, "拷贝SDK资源文件失败 - 未知异常", e);
//                return false;
//            }
//        }
//
//        public static boolean copyAssetFile(android.content.Context context, String assetName, String targetPath) {
//            try (java.io.InputStream in = context.getAssets().open(assetName);
//                 java.io.OutputStream out = new java.io.FileOutputStream(targetPath)) {
//
//                byte[] buffer = new byte[1024];
//                int length;
//                while ((length = in.read(buffer)) > 0) {
//                    out.write(buffer, 0, length);
//                }
//
//                Log.d(TAG, "拷贝资源文件: " + assetName + " -> " + targetPath);
//                return true;
//            } catch (IOException e) {
//                Log.e(TAG, "拷贝单个资源文件失败: " + assetName, e);
//                return false;
//            }
//        }

        public static void createDir(String path) {
            java.io.File dir = new java.io.File(path);
            if (!dir.exists()) {
                dir.mkdirs();
            }
        }

        public static String getModelPath(android.content.Context context) {
            return context.getFilesDir().getAbsolutePath();
        }

        public static String getMsgWithErrorCode(int code, String action) {
            // 映射错误码到提示信息（参考阿里云 SDK 文档）
            Map<Integer, String> errorMap = new HashMap<>();
            errorMap.put(Constants.NuiResultCode.SUCCESS, "成功");
            errorMap.put(140001, "引擎未创建, 请检查是否成功初始化");
            errorMap.put(140008, "鉴权失败, 请关注日志中详细失败原因");
            errorMap.put(140011, "当前方法调用不符合当前状态");
            errorMap.put(140013, "当前方法调用不符合当前状态");
            errorMap.put(144003, "token过期或无效, 请检查token是否有效");
            errorMap.put(144006, "云端返回未分类错误");
            errorMap.put(240005, "设置的参数不正确或初始化参数无效");
            errorMap.put(240011, "SDK未成功初始化");
            errorMap.put(240052, "2s未传入音频数据，请检查录音权限或录音模块");
            errorMap.put(240063, "SSL错误，可能为SSL建连失败");
            errorMap.put(240068, "403 Forbidden, token无效或者过期");
            errorMap.put(240070, "鉴权失败, 请查看日志确定具体问题");

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                return errorMap.getOrDefault(code, action + "失败，未知错误");
            }
            return action;
        }
    }
}
