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
import com.alibaba.idst.nui.KwsResult;
import com.alibaba.idst.nui.NativeNui;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.PermissionHelper;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
//import org.json.JSONException;
//import org.json.JSONObject;

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
public class AISpeechTranscriber extends CordovaPlugin implements INativeNuiCallback {
    // 日志标签
    private static final String TAG = "AliyunSpeechTranscriber";
    // 音频参数常量
    private static final int SAMPLE_RATE = 16000;

    // 权限请求码
    private static final int PERMISSION_RECORD_AUDIO = 1001;
    private static final int PERMISSION_WRITE_STORAGE = 1002;
    private static final int READ_EXTERNAL_STORAGE =1003;


    private String token;

    private String serviceUrl = "wss://nls-gateway.cn-shanghai.aliyuncs.com:443/ws/v1";

    // SDK 核心实例
    private NativeNui nui_instance = new NativeNui();
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
            }


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
        // 保存回调上下文
        transcribeCallback = callbackContext;
        workerHandler.post(() -> {
            try {
                isStopping = true;
                long stopResult = nui_instance.stopDialog();
                isTranscribing = false;

                // 释放音频资源
                releaseAudioRecorder();

                if (stopResult == 0) {
                     
                    sendCallback("stop", "转写停止成功");
                    Log.i(TAG, "转写停止成功");
                } else { 
                    sendCallback("stopError", "转写停止失败，错误码：" + stopResult);
                    Log.e(TAG, "停止转写失败，错误码：" + stopResult);
                }
            } catch (Exception e) { 
                sendCallback("stopError", "转写停止异常：" + e.getMessage());
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
        //JSONObject params = new JSONObject();

        // 设置认证参数
       // Auth.GetTicketMethod authMethod = Auth.GetTicketMethod. GET_TOKEN_IN_CLIENT_FOR_ONLINE_FEATURES ;// getAuthMethod(); GET_TOKEN_FROM_SERVER_FOR_ONLINE_FEATURES
        JSONObject authParams = new JSONObject();
        authParams.put("token", token);
//        authParams.put("appkey", appKey);
//        authParams.put("ak_id", accessKey);
//        authParams.put("ak_secret", accessKeySecret);

        // 基础配置
        authParams.put("device_id", "android_" + Build.SERIAL);
        authParams.put("url", serviceUrl);
        authParams.put("workspace", CommonUtils.getModelPath(cordova.getActivity())); // V2.6.2版本开始纯云端功能可不设置workspace
        authParams.put("save_wav", "false");
        authParams.put("debug_path", debugPath);
        authParams.put("max_log_file_size", 50 * 1024 * 1024);
        authParams.put("log_track_level", Constants.LogLevel.toInt(Constants.LogLevel.LOG_LEVEL_NONE));
        authParams.put("service_mode", Constants.ModeFullCloud);

        return authParams.toString();
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
                String initParams = generateInitParams();
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

    private final Map<String, List<String>> paramMap = new HashMap<>();

    private final static int WAVE_FRAM_SIZE = 20 * 2 * 1 * SAMPLE_RATE / 1000; //20ms audio for 16k/16bit/mono



    private String mDebugPath = "";
    private String curTaskId = "";
    private LinkedBlockingQueue<byte[]> tmpAudioQueue = new LinkedBlockingQueue();



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
            JSONObject object = Auth.getTicket(method);
            if (!object.containsKey("token")) {
                Log.e(TAG, "Cannot get token !!! 未获得有效临时凭证");

            }

            object.put("device_id", "empty_device_id"); // 必填, 推荐填入具有唯一性的id, 方便定位问题
            if (g_url.isEmpty()) {
                g_url = "wss://nls-gateway.cn-shanghai.aliyuncs.com:443/ws/v1"; // 默认
            }
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
        } catch (JSONException e) {
            e.printStackTrace();
        }

        // 注意! str中包含ak_id ak_secret token app_key等敏感信息, 实际产品中请勿在Log中输出这类信息！
        Log.i(TAG, "InsideUserContext:" + str);
        return str;
    }



    private String genParams() {
        String params = "";
        try {
            JSONObject nls_config = new JSONObject();

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
//            JSONObject extend_config = new JSONObject();
//            JSONObject vocab = new JSONObject();
//            vocab.put("热词1", 2);
//            vocab.put("热词2", 2);
//            extend_config.put("vocabulary", vocab);
//            nls_config.put("extend_config", extend_config);

            JSONObject tmp = new JSONObject();
            tmp.put("nls_config", nls_config);
            tmp.put("service_type", Constants.kServiceTypeSpeechTranscriber); // 必填

//            如果有HttpDns则可进行设置
//            tmp.put("direct_ip", Utils.getDirectIp());

            params = tmp.toString();
        } catch (JSONException e) {
            e.printStackTrace();
        }
        return params;
    }



    private String genDialogParams() {
        String params = "";
        try {
            JSONObject dialog_param = new JSONObject();
            // 运行过程中可以在startDialog时更新临时参数，尤其是更新过期token
            // 注意: 若下一轮对话不再设置参数，则继续使用初始化时传入的参数
            long distance_expire_time_30m = 1800;
            dialog_param = Auth.refreshTokenIfNeed(dialog_param, distance_expire_time_30m);

            // 注意: 若需要更换appkey和token，可以直接传入参数
//            dialog_param.put("app_key", "");
//            dialog_param.put("token", "");
            params = dialog_param.toString();
        } catch (JSONException e) {
            e.printStackTrace();
        }

        Log.i(TAG, "dialog params: " + params);
        return params;
    }






}
