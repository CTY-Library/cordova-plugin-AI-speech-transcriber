package com.plugin.aliyun.aispeech;

import android.content.Context;
import android.os.Build;
import android.os.Environment;
import android.util.Log;

import androidx.appcompat.app.AppCompatActivity;

import com.alibaba.idst.nui.Constants;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.HashMap;
import java.util.Map;

public class CommonUtils {
    private static final String TAG = "CommonUtils";
    // SDK配置文件的存储路径（根据阿里云SDK要求调整）

    /**
     * 拷贝Assets中的SDK配置文件到本地存储
     * @param context 上下文
     * @return 拷贝是否成功
     */
    public static boolean copyAssetsData(Context context ,String debugPath) {
        // 步骤1：检查外部存储是否可用
//        if (!isExternalStorageWritable()) {
//            Log.e(TAG, "外部存储不可写，无法拷贝文件");
//            return false;
//        }

        // 步骤2：检查并申请文件权限（Android 6.0+ 动态权限）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !checkFilePermission(context)) {
            Log.e(TAG, "文件读写权限未授予，无法拷贝文件");
            return false;
        }

        // 步骤3：创建目标目录（确保目录存在）
//        File targetDir = new File(debugPath);
//        if (!targetDir.exists()) {
//            boolean mkdirSuccess = targetDir.mkdirs();
//            if (!mkdirSuccess) {
//                Log.e(TAG, "创建目标目录失败：" + debugPath);
//                return false;
//            }
//        }

        // 步骤4：遍历Assets中的SDK配置文件并拷贝（需替换为实际的文件名）
        try {
            // 获取Assets中SDK配置文件列表（根据阿里云SDK文档确认文件名，比如"nui_config.dat"）
            String[] assetsFiles = context.getAssets().list(""); // 假设配置文件在assets/nui_config目录下
            if (assetsFiles == null || assetsFiles.length == 0) {
                Log.e(TAG, "Assets目录下未找到SDK配置文件，请检查文件是否存在");
                return false;
            }

            for (String fileName : assetsFiles) {
                InputStream is = context.getAssets().open(fileName);
                File targetFile = new File(debugPath + fileName);
                // 拷贝文件
                copyFile(is, targetFile);
                is.close();
                Log.i(TAG, "成功拷贝文件：" + fileName);
            }
            return true;
        } catch (IOException e) {
            Log.e(TAG, "拷贝Assets文件时发生IO异常：" + e.getMessage(), e);
            return false;
        } catch (Exception e) {
            Log.e(TAG, "拷贝Assets文件失败：" + e.getMessage(), e);
            return false;
        }
    }

    /**
     * 检查外部存储是否可写
     */
    private static boolean isExternalStorageWritable() {
        return Environment.MEDIA_MOUNTED.equals(Environment.getExternalStorageState());
    }

    /**
     * 检查文件读写权限（Android 6.0+ 动态权限）
     */
    private static boolean checkFilePermission(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true; // 6.0以下默认授予权限
        }
        int readPermission = context.checkSelfPermission(android.Manifest.permission.READ_EXTERNAL_STORAGE);
        int writePermission = context.checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE);
        return readPermission == android.content.pm.PackageManager.PERMISSION_GRANTED
                && writePermission == android.content.pm.PackageManager.PERMISSION_GRANTED;
    }

    /**
     * 核心文件拷贝方法
     */
    private static void copyFile(InputStream is, File targetFile) throws IOException {
        OutputStream os = new FileOutputStream(targetFile);
        byte[] buffer = new byte[1024];
        int length;
        while ((length = is.read(buffer)) > 0) {
            os.write(buffer, 0, length);
        }
        os.flush();
        os.close();
    }





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




    /**
     * 申请文件读写权限（在Activity中调用）
     */
    public static void requestFilePermission(android.app.Activity activity, int requestCode) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            activity.requestPermissions(
                    new String[]{
                            android.Manifest.permission.READ_EXTERNAL_STORAGE,
                            android.Manifest.permission.WRITE_EXTERNAL_STORAGE
                    },
                    requestCode
            );
        }
    }
}