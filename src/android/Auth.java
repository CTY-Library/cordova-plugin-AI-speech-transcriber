package com.plugin.aliyun.aispeech;


import android.util.Log;

import com.alibaba.fastjson.JSON;
import com.alibaba.fastjson.JSONObject;

//import mit.alibaba.nuidemo.token.AccessToken;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.Reader;

/*
 * STS服务不可直接用于在线功能，包括一句话识别、实时识别、语音合成等。
 * 在线功能需要TOKEN，可由STS临时账号通过TOKEN工具生成，也可在服务端下发TOKEN。
 * STS服务可用于离线功能的鉴权，比如本地语音合成和唤醒。
 */
public class Auth {
    public enum GetTicketMethod {
        /*
         * 客户远端服务端使用STS服务获得STS临时凭证，然后下发给移动端侧，
         * 然后生成语音交互临时凭证Token。用于在线功能场景。
         */
        GET_STS_ACCESS_FROM_SERVER_FOR_ONLINE_FEATURES,
        /*
         * 客户远端服务端使用STS服务获得STS临时凭证，然后下发给移动端侧，
         * 同时设置sdk_code, 用于离线功能场景。
         */
        GET_STS_ACCESS_FROM_SERVER_FOR_OFFLINE_FEATURES,
        /*
         * 客户远端服务端使用STS服务获得STS临时凭证，然后下发给移动端侧，
         * 然后生成语音交互临时凭证Token。
         * 同时设置sdk_code, 用于离线在线功能混合场景。
         */
        GET_STS_ACCESS_FROM_SERVER_FOR_MIXED_FEATURES,
        /*
         * 客户远端服务端使用Token服务获得Token临时令牌，然后下发给移动端侧，
         * 用于在线功能场景。
         */
        GET_TOKEN_FROM_SERVER_FOR_ONLINE_FEATURES,
        /*
         * 客户远端服务端将账号信息ak_id和ak_secret(请加密)下发给移动端侧，
         * 同时设置sdk_code, 用于离线功能场景。
         */
        GET_ACCESS_FROM_SERVER_FOR_OFFLINE_FEATURES,
        /*
         * 客户远端服务端将账号信息ak_id和ak_secret(请加密)下发给移动端侧，
         * 然后生成语音交互临时凭证Token。
         * 同时设置sdk_code, 用于离线在线功能混合场景。
         */
        GET_ACCESS_FROM_SERVER_FOR_MIXED_FEATURES,
        /*
         * 客户直接使用存储在移动端侧的Token，
         * 用于在线功能场景。
         */
        GET_TOKEN_IN_CLIENT_FOR_ONLINE_FEATURES,
        /*
         * 客户直接使用存储在移动端侧的ak_id和ak_secret(请加密)，
         * 同时设置sdk_code, 用于离线功能场景。
         */
        GET_ACCESS_IN_CLIENT_FOR_OFFLINE_FEATURES,
        /*
         * 客户直接使用存储在移动端侧的ak_id和ak_secret(请加密)，
         * 然后生成语音交互临时凭证Token。
         * 同时设置sdk_code, 用于离线在线功能混合场景。
         */
        GET_ACCESS_IN_CLIENT_FOR_MIXED_FEATURES,
        /*
         * 客户直接使用存储在移动端侧的ak_id和ak_secret(请加密)，
         * 用于在线功能场景。
         */
        GET_ACCESS_IN_CLIENT_FOR_ONLINE_FEATURES,
        /*
         * 客户直接使用存储在移动端侧的STS凭证，
         * 然后生成语音交互临时凭证Token。用于在线功能场景。
         */
        GET_STS_ACCESS_IN_CLIENT_FOR_ONLINE_FEATURES,
        /*
         * 客户直接使用存储在移动端侧的STS凭证，
         * 同时设置sdk_code, 用于离线功能场景。
         */
        GET_STS_ACCESS_IN_CLIENT_FOR_OFFLINE_FEATURES,
        /*
         * 客户直接使用存储在移动端侧的STS凭证，
         * 然后生成语音交互临时凭证Token。
         * 同时设置sdk_code, 用于离线在线功能混合场景。
         */
        GET_STS_ACCESS_IN_CLIENT_FOR_MIXED_FEATURES;
    }

    private static GetTicketMethod cur_method = GetTicketMethod.GET_STS_ACCESS_FROM_SERVER_FOR_ONLINE_FEATURES;
    private static String cur_appkey = "";
    private static String cur_token = "";
    private static String cur_sts_token = "";
    private static long cur_token_expired_time = 0;
    private static String cur_ak = "";
    private static String cur_sk = "";
    private static String cur_sdk_code = "software_nls_tts_offline_standard";

    public static void setAppKey(String appkey) {
        if (!appkey.isEmpty()) {
            cur_appkey = appkey;
        }
    }
    public static void setToken(String token) {
        if (!token.isEmpty()) {
            cur_token = token;
        }
    }
    public static void setStsToken(String stsToken) {
        cur_sts_token = stsToken;
    }
    public static void setAccessKey(String ak) {
        if (!ak.isEmpty()) {
            cur_ak = ak;
        }
    }
    public static void setAccessKeySecret(String sk) {
        if (!sk.isEmpty()) {
            cur_sk = sk;
        }
    }
    public static void setSdkCode(String sdkCode) {
        if (!sdkCode.isEmpty()) {
            cur_sdk_code = sdkCode;
        }
    }

    // 将鉴权信息打包成json格式
    public static JSONObject getTicket(GetTicketMethod method) {
        //郑重提示:
        //  语音交互服务需要先准备好账号，并开通相关服务。具体步骤请查看：
        //    https://help.aliyun.com/zh/isi/getting-started/start-here
        //
        //原始账号:
        //  账号(子账号)信息主要包括AccessKey ID(后续简称为ak_id)和AccessKey Secret(后续简称为ak_secret)。
        //  此账号信息一定不可存储在app代码中或移动端侧，以防账号信息泄露造成资费损失。
        //
        //STS临时凭证:
        //  由于账号信息下发给客户端存在泄露的可能，阿里云提供的一种临时访问权限管理服务STS(Security Token Service)。
        //  STS是由账号信息ak_id和ak_secret，通过请求生成临时的sts_ak_id/sts_ak_secret/sts_token
        //  (为了区别原始账号信息和STS临时凭证, 命名前缀sts_表示STS生成的临时凭证信息)
        //什么是STS：https://help.aliyun.com/zh/ram/product-overview/what-is-sts
        //STS SDK概览：https://help.aliyun.com/zh/ram/developer-reference/sts-sdk-overview
        //STS Python SDK调用示例：https://help.aliyun.com/zh/ram/developer-reference/use-the-sts-openapi-example
        //
        //账号需求说明:
        //  若使用离线功能(离线语音合成、唤醒), 则必须app_key、ak_id和ak_secret，或app_key、sts_ak_id、sts_ak_secret和sts_token
        //  若使用在线功能(语音合成、实时转写、一句话识别、录音文件转写等), 则只需app_key和token

        JSONObject object = new JSONObject();

        cur_method = method;

        //项目创建
        //  创建appkey请查看：https://help.aliyun.com/zh/isi/getting-started/start-here
        String APPKEY = "<您申请创建的app_key>";
        if (!cur_appkey.isEmpty()) {
            APPKEY = cur_appkey;
        }
        object.put("app_key", APPKEY); // 必填
        cur_appkey = APPKEY;

        if (method == GetTicketMethod.GET_STS_ACCESS_FROM_SERVER_FOR_ONLINE_FEATURES) {
            //方法一，仅适合在线语音交互服务(强烈推荐):
            //  客户远端服务端使用STS服务获得STS临时凭证，然后下发给移动端侧，详情请查看：
            //    https://help.aliyun.com/document_detail/466615.html 使用其中方案二使用STS获取临时账号。
            //  然后在移动端侧通过AccessToken()获得Token和有效期，用于在线语音交互服务。
            String STS_AK_ID = "STS.<服务器生成的具有时效性的临时凭证>";
            String STS_AK_SECRET = "<服务器生成的具有时效性的临时凭证>";
            String STS_TOKEN = "<服务器生成的具有时效性的临时凭证>";
            String TOKEN = "<由STS生成的临时访问令牌>";
            final AccessToken token = new AccessToken(STS_AK_ID, STS_AK_SECRET, STS_TOKEN);
            Thread th = new Thread() {
                @Override
                public void run() {
                    try {
                        token.apply();
                    } catch (IOException e) {
                        e.printStackTrace();
                    }
                }
            };
            th.start();
            try {
                th.join(5000);
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
            TOKEN = token.getToken();
            if (TOKEN != null && !TOKEN.isEmpty()) {
                object.put("token", TOKEN);  // 必填
                cur_token = TOKEN;
                cur_ak = STS_AK_ID;
                cur_sk = STS_AK_SECRET;
                cur_sts_token = STS_TOKEN;
                // token生命周期超过expired_time, 则需要重新token = new AccessToken()
                cur_token_expired_time = token.getExpireTime();
            } else {
                cur_token = "";
                cur_sts_token = "";
            }
        } else if (method == GetTicketMethod.GET_STS_ACCESS_FROM_SERVER_FOR_OFFLINE_FEATURES) {
            //方法二，仅适合离线语音交互服务(强烈推荐):
            //  客户远端服务端使用STS服务获得STS临时凭证，然后下发给移动端侧，详情请查看：
            //    https://help.aliyun.com/document_detail/466615.html 使用其中方案二使用STS获取临时账号。
            String STS_AK_ID = "STS.<服务器生成的具有时效性的临时凭证>";
            String STS_AK_SECRET = "<服务器生成的具有时效性的临时凭证>";
            String STS_TOKEN = "<服务器生成的具有时效性的临时凭证>";
            object.put("ak_id", STS_AK_ID); // 必填
            object.put("ak_secret", STS_AK_SECRET); // 必填
            object.put("sts_token", STS_TOKEN); // 必填
            cur_ak = STS_AK_ID;
            cur_sk = STS_AK_SECRET;
            cur_sts_token = STS_TOKEN;
            // 离线语音合成sdk_code取值：精品版为software_nls_tts_offline， 标准版为software_nls_tts_offline_standard
            // 离线语音合成账户和sdk_code可用于唤醒
            // 由创建Appkey时设置
            object.put("sdk_code", cur_sdk_code); // 必填
        } else if (method == GetTicketMethod.GET_STS_ACCESS_FROM_SERVER_FOR_MIXED_FEATURES) {
            //方法三，适合离在线语音交互服务(强烈推荐):
            //  客户远端服务端使用STS服务获得STS临时凭证，然后下发给移动端侧，详情请查看：
            //    https://help.aliyun.com/document_detail/466615.html 使用其中方案二使用STS获取临时账号。
            //  然后在移动端侧通过AccessToken()获得Token和有效期，用于在线语音交互服务。
            //注意！此处介绍同一个Appkey用于在线和离线功能，用户可创建两个Appkey分别用于在线和离线功能。
            String STS_AK_ID = "STS.<服务器生成的具有时效性的临时凭证>";
            String STS_AK_SECRET = "<服务器生成的具有时效性的临时凭证>";
            String STS_TOKEN = "<服务器生成的具有时效性的临时凭证>";
            String TOKEN = "<由STS生成的临时访问令牌>";
            final AccessToken token = new AccessToken(STS_AK_ID, STS_AK_SECRET, STS_TOKEN);
            Thread th = new Thread() {
                @Override
                public void run() {
                    try {
                        token.apply();
                    } catch (IOException e) {
                        e.printStackTrace();
                    }
                }
            };
            th.start();
            try {
                th.join(5000);
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
            TOKEN = token.getToken();

            object.put("ak_id", STS_AK_ID); // 必填
            object.put("ak_secret", STS_AK_SECRET); // 必填
            object.put("sts_token", STS_TOKEN); // 必填
            if (TOKEN != null && !TOKEN.isEmpty()) {
                object.put("token", TOKEN);  // 必填
                cur_token = TOKEN;
                cur_ak = STS_AK_ID;
                cur_sk = STS_AK_SECRET;
                cur_sts_token = STS_TOKEN;
                // token生命周期超过expired_time, 则需要重新token = new AccessToken()
                cur_token_expired_time = token.getExpireTime();
            } else {
                cur_token = "";
                cur_sts_token = "";
            }
            // 离线语音合成sdk_code取值：精品版为software_nls_tts_offline， 标准版为software_nls_tts_offline_standard
            // 离线语音合成账户和sdk_code可用于唤醒
            // 由创建Appkey时设置
            object.put("sdk_code", cur_sdk_code); // 必填
        } else if (method == GetTicketMethod.GET_TOKEN_FROM_SERVER_FOR_ONLINE_FEATURES) {
            //方法四，仅适合在线语音交互服务(推荐):
            //  客户远端服务端使用Token服务获得Token临时令牌，然后下发给移动端侧，详情请查看：
            //    https://help.aliyun.com/document_detail/466615.html 使用其中方案一获取临时令牌Token
            //  获得Token方法：
            //    https://help.aliyun.com/zh/isi/getting-started/overview-of-obtaining-an-access-token
            String TOKEN = "<服务器生成的具有时效性的临时凭证>";
            if (TOKEN != null && !TOKEN.isEmpty()) {
                object.put("token", TOKEN);  // 必填
                cur_appkey = APPKEY;
                cur_token = TOKEN;
            } else {
                cur_token = "";
            }
        } else if (method == GetTicketMethod.GET_ACCESS_FROM_SERVER_FOR_OFFLINE_FEATURES) {
            //方法五，仅适合离线语音交互服务(不推荐):
            //  客户远端服务端将账号信息ak_id和ak_secret(请加密)下发给移动端侧。
            //注意！账号信息出现在移动端侧，存在泄露风险。
            String AK_ID = "<一定不可代码中存储和本地明文存储>";
            String AK_SECRET = "<一定不可代码中存储和本地明文存储>";
            object.put("ak_id", AK_ID); // 必填
            object.put("ak_secret", AK_SECRET); // 必填
            cur_ak = AK_ID;
            cur_sk = AK_SECRET;
            // 离线语音合成sdk_code取值：精品版为software_nls_tts_offline， 标准版为software_nls_tts_offline_standard
            // 离线语音合成账户和sdk_code可用于唤醒
            // 由创建Appkey时设置
            object.put("sdk_code", cur_sdk_code); // 必填
        } else if (method == GetTicketMethod.GET_ACCESS_FROM_SERVER_FOR_MIXED_FEATURES) {
            //方法六，适合离在线语音交互服务(不推荐):
            //  客户远端服务端将账号信息ak_id和ak_secret(请加密)下发给移动端侧。
            //  然后在移动端侧通过AccessToken()获得Token和有效期，用于在线语音交互服务。
            //注意！账号信息出现在移动端侧，存在泄露风险。
            String AK_ID = "<一定不可代码中存储和本地明文存储>";
            String AK_SECRET = "<一定不可代码中存储和本地明文存储>";
            String TOKEN = "<生成的临时访问令牌>";
            final AccessToken token = new AccessToken(AK_ID, AK_SECRET, "");
            Thread th = new Thread() {
                @Override
                public void run() {
                    try {
                        token.apply();
                    } catch (IOException e) {
                        e.printStackTrace();
                    }
                }
            };
            th.start();
            try {
                th.join(5000);
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
            TOKEN = token.getToken();

            object.put("ak_id", AK_ID); // 必填
            object.put("ak_secret", AK_SECRET); // 必填
            if (TOKEN != null && !TOKEN.isEmpty()) {
                object.put("token", TOKEN);  // 必填
                cur_appkey = APPKEY;
                cur_token = TOKEN;
                // token生命周期超过expired_time, 则需要重新token = new AccessToken()
                cur_token_expired_time = token.getExpireTime();
            } else {
                cur_token = "";
            }
            // 离线语音合成sdk_code取值：精品版为software_nls_tts_offline， 标准版为software_nls_tts_offline_standard
            // 离线语音合成账户和sdk_code可用于唤醒
            // 由创建Appkey时设置
            object.put("sdk_code", cur_sdk_code); // 必填
        } else if (method == GetTicketMethod.GET_TOKEN_IN_CLIENT_FOR_ONLINE_FEATURES) {
            //方法七，仅适合在线语音交互服务(强烈不推荐):
            //  仅仅用于开发和调试
            //注意！账号信息出现在移动端侧，存在泄露风险。
            String TOKEN = "<移动端写死的访问令牌，仅用于调试>";
            if (!cur_token.isEmpty()) {
                TOKEN = cur_token;
            }
            if (TOKEN != null && !TOKEN.isEmpty()) {
                object.put("token", TOKEN);  // 必填
                cur_appkey = APPKEY;
                cur_token = TOKEN;
            } else {
                cur_token = "";
            }
        } else if (method == GetTicketMethod.GET_ACCESS_IN_CLIENT_FOR_OFFLINE_FEATURES) {
            //方法八，仅适合离线语音交互服务(强烈不推荐):
            //  仅仅用于开发和调试
            //注意！账号信息出现在移动端侧，存在泄露风险。
            String AK_ID = "<移动端写死的账号信息，仅用于调试>";
            String AK_SECRET = "<移动端写死的账号信息，仅用于调试>";
            if (!cur_ak.isEmpty()) {
                AK_ID = cur_ak;
            }
            if (!cur_sk.isEmpty()) {
                AK_SECRET = cur_sk;
            }

            object.put("ak_id", AK_ID); // 必填
            object.put("ak_secret", AK_SECRET); // 必填
            // 离线语音合成sdk_code取值：精品版为software_nls_tts_offline， 标准版为software_nls_tts_offline_standard
            // 离线语音合成账户和sdk_code可用于唤醒
            // 由创建Appkey时设置
            object.put("sdk_code", cur_sdk_code); // 必填
        } else if (method == GetTicketMethod.GET_ACCESS_IN_CLIENT_FOR_MIXED_FEATURES) {
            //方法九，适合离在线语音交互服务(强烈不推荐):
            //  仅仅用于开发和调试
            //注意！账号信息出现在移动端侧，存在泄露风险。
            String AK_ID = "<移动端写死的账号信息，仅用于调试>";
            String AK_SECRET = "<移动端写死的账号信息，仅用于调试>";
            String TOKEN = "<生成的临时访问令牌>";
            if (!cur_ak.isEmpty()) {
                AK_ID = cur_ak;
            }
            if (!cur_sk.isEmpty()) {
                AK_SECRET = cur_sk;
            }
            final AccessToken token = new AccessToken(AK_ID, AK_SECRET, "");
            Thread th = new Thread() {
                @Override
                public void run() {
                    try {
                        token.apply();
                    } catch (IOException e) {
                        e.printStackTrace();
                    }
                }
            };
            th.start();
            try {
                th.join(5000);
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
            TOKEN = token.getToken();

            object.put("ak_id", AK_ID); // 必填
            object.put("ak_secret", AK_SECRET); // 必填
            cur_ak = AK_ID;
            cur_sk = AK_SECRET;
            if (TOKEN != null && !TOKEN.isEmpty()) {
                object.put("token", TOKEN);  // 必填
                cur_appkey = APPKEY;
                cur_token = TOKEN;
                // token生命周期超过expired_time, 则需要重新token = new AccessToken()
                cur_token_expired_time = token.getExpireTime();
            } else {
                cur_token = "";
            }
            // 离线语音合成sdk_code取值：精品版为software_nls_tts_offline， 标准版为software_nls_tts_offline_standard
            // 离线语音合成账户和sdk_code可用于唤醒
            // 由创建Appkey时设置
            object.put("sdk_code", cur_sdk_code); // 必填
        } else if (method == GetTicketMethod.GET_ACCESS_IN_CLIENT_FOR_ONLINE_FEATURES) {
            //方法十，适合在线语音交互服务(强烈不推荐):
            //  仅仅用于开发和调试
            //注意！账号信息出现在移动端侧，存在泄露风险。
            String AK_ID = "<移动端写死的账号信息，仅用于调试>";
            String AK_SECRET = "<移动端写死的账号信息，仅用于调试>";
            String TOKEN = "<生成的临时访问令牌>";
            if (!cur_ak.isEmpty()) {
                AK_ID = cur_ak;
            }
            if (!cur_sk.isEmpty()) {
                AK_SECRET = cur_sk;
            }
            final AccessToken token = new AccessToken(AK_ID, AK_SECRET, "");
            Thread th = new Thread() {
                @Override
                public void run() {
                    try {
                        token.apply();
                    } catch (IOException e) {
                        e.printStackTrace();
                    }
                }
            };
            th.start();
            try {
                th.join(5000);
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
            TOKEN = token.getToken();

            object.put("ak_id", AK_ID); // 必填
            object.put("ak_secret", AK_SECRET); // 必填
            cur_ak = AK_ID;
            cur_sk = AK_SECRET;
            if (TOKEN != null && !TOKEN.isEmpty()) {
                object.put("token", TOKEN);  // 必填
                cur_appkey = APPKEY;
                cur_token = TOKEN;
                // token生命周期超过expired_time, 则需要重新token = new AccessToken()
                cur_token_expired_time = token.getExpireTime();
            } else {
                cur_token = "";
            }
        } else if (method == GetTicketMethod.GET_STS_ACCESS_IN_CLIENT_FOR_ONLINE_FEATURES) {
            //方法十一，适合在线语音交互服务(强烈不推荐):
            //  仅仅用于开发和调试
            String STS_AK_ID = "STS.<移动端写死的账号信息，仅用于调试>";
            String STS_AK_SECRET = "<移动端写死的账号信息，仅用于调试>";
            String STS_TOKEN = "<移动端写死的账号信息，仅用于调试>";
            if (!cur_ak.isEmpty()) {
                STS_AK_ID = cur_ak;
            }
            if (!cur_sk.isEmpty()) {
                STS_AK_SECRET = cur_sk;
            }
            if (!cur_sts_token.isEmpty()) {
                STS_TOKEN = cur_sts_token;
            }
            String TOKEN = "<由STS生成的临时访问令牌>";
            final AccessToken token = new AccessToken(STS_AK_ID, STS_AK_SECRET, STS_TOKEN);
            Thread th = new Thread() {
                @Override
                public void run() {
                    try {
                        token.apply();
                    } catch (IOException e) {
                        e.printStackTrace();
                    }
                }
            };
            th.start();
            try {
                th.join(5000);
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
            TOKEN = token.getToken();

            object.put("ak_id", STS_AK_ID); // 必填
            object.put("ak_secret", STS_AK_SECRET); // 必填
            object.put("sts_token", STS_TOKEN); // 必填
            cur_ak = STS_AK_ID;
            cur_sk = STS_AK_SECRET;
            if (TOKEN != null && !TOKEN.isEmpty()) {
                object.put("token", TOKEN);  // 必填
                cur_appkey = APPKEY;
                cur_token = TOKEN;
                cur_sts_token = STS_TOKEN;
                // token生命周期超过expired_time, 则需要重新token = new AccessToken()
                cur_token_expired_time = token.getExpireTime();
            } else {
                cur_token = "";
                cur_sts_token = "";
            }
        } else if (method == GetTicketMethod.GET_STS_ACCESS_IN_CLIENT_FOR_OFFLINE_FEATURES) {
            //方法十二，适合离线语音交互服务(强烈不推荐):
            //  仅仅用于开发和调试
            String STS_AK_ID = "STS.<移动端写死的账号信息，仅用于调试>";
            String STS_AK_SECRET = "<移动端写死的账号信息，仅用于调试>";
            String STS_TOKEN = "<移动端写死的账号信息，仅用于调试>";
            if (!cur_ak.isEmpty()) {
                STS_AK_ID = cur_ak;
            }
            if (!cur_sk.isEmpty()) {
                STS_AK_SECRET = cur_sk;
            }
            if (!cur_sts_token.isEmpty()) {
                STS_TOKEN = cur_sts_token;
            }
            String TOKEN = "<由STS生成的临时访问令牌>";
            final AccessToken token = new AccessToken(STS_AK_ID, STS_AK_SECRET, STS_TOKEN);
            Thread th = new Thread() {
                @Override
                public void run() {
                    try {
                        token.apply();
                    } catch (IOException e) {
                        e.printStackTrace();
                    }
                }
            };
            th.start();
            try {
                th.join(5000);
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
            TOKEN = token.getToken();

            object.put("ak_id", STS_AK_ID); // 必填
            object.put("ak_secret", STS_AK_SECRET); // 必填
            object.put("sts_token", STS_TOKEN); // 必填
            cur_ak = STS_AK_ID;
            cur_sk = STS_AK_SECRET;
            cur_sts_token = STS_TOKEN;
            if (TOKEN != null && !TOKEN.isEmpty()) {
                object.put("token", TOKEN);  // 必填
                cur_appkey = APPKEY;
                cur_token = TOKEN;
                // token生命周期超过expired_time, 则需要重新token = new AccessToken()
                cur_token_expired_time = token.getExpireTime();
            } else {
                cur_token = "";
                cur_sts_token = "";
            }
            // 离线语音合成sdk_code取值：精品版为software_nls_tts_offline， 标准版为software_nls_tts_offline_standard
            // 离线语音合成账户和sdk_code可用于唤醒
            // 由创建Appkey时设置
            object.put("sdk_code", cur_sdk_code); // 必填
        } else if (method == GetTicketMethod.GET_STS_ACCESS_IN_CLIENT_FOR_MIXED_FEATURES) {
            //方法十三，适合离在线语音交互服务(强烈不推荐):
            //  仅仅用于开发和调试
            String STS_AK_ID = "STS.<移动端写死的账号信息，仅用于调试>";
            String STS_AK_SECRET = "<移动端写死的账号信息，仅用于调试>";
            String STS_TOKEN = "<移动端写死的账号信息，仅用于调试>";
            if (!cur_ak.isEmpty()) {
                STS_AK_ID = cur_ak;
            }
            if (!cur_sk.isEmpty()) {
                STS_AK_SECRET = cur_sk;
            }
            if (!cur_sts_token.isEmpty()) {
                STS_TOKEN = cur_sts_token;
            }
            String TOKEN = "<由STS生成的临时访问令牌>";
            final AccessToken token = new AccessToken(STS_AK_ID, STS_AK_SECRET, STS_TOKEN);
            Thread th = new Thread() {
                @Override
                public void run() {
                    try {
                        token.apply();
                    } catch (IOException e) {
                        e.printStackTrace();
                    }
                }
            };
            th.start();
            try {
                th.join(5000);
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
            TOKEN = token.getToken();

            object.put("ak_id", STS_AK_ID); // 必填
            object.put("ak_secret", STS_AK_SECRET); // 必填
            object.put("sts_token", STS_TOKEN); // 必填
            cur_ak = STS_AK_ID;
            cur_sk = STS_AK_SECRET;
            cur_sts_token = STS_TOKEN;
            if (TOKEN != null && !TOKEN.isEmpty()) {
                object.put("token", TOKEN);  // 必填
                cur_appkey = APPKEY;
                cur_token = TOKEN;
                // token生命周期超过expired_time, 则需要重新token = new AccessToken()
                cur_token_expired_time = token.getExpireTime();
            } else {
                cur_token = "";
                cur_sts_token = "";
            }
            // 离线语音合成sdk_code取值：精品版为software_nls_tts_offline， 标准版为software_nls_tts_offline_standard
            // 离线语音合成账户和sdk_code可用于唤醒
            // 由创建Appkey时设置
            object.put("sdk_code", cur_sdk_code); // 必填
        }

        return object;
    }

    // 也可以将鉴权信息以json格式保存至文件，然后从文件里加载（必须包含成员：ak_id/ak_secret/app_key/device_id/sdk_code）
    // 该方式切换账号切换账号比较方便
    public static JSONObject getTicketFromJsonFile(String fileName) {
        try {
            File jsonFile = new File(fileName);
            FileReader fileReader = new FileReader(jsonFile);
            Reader reader = new InputStreamReader(new FileInputStream(jsonFile), "utf-8");
            int ch = 0;
            StringBuffer sb = new StringBuffer();
            while ((ch = reader.read()) != -1) {
                sb.append((char) ch);
            }
            fileReader.close();
            reader.close();
            String jsonStr = sb.toString();
            return JSON.parseObject(jsonStr);
        } catch (IOException e) {
            e.printStackTrace();
            return null;
        }
    }

    public static JSONObject refreshTokenIfNeed(JSONObject json, long distance_expire_time) {
        if (!cur_appkey.isEmpty() && !cur_token.isEmpty() && cur_token_expired_time > 0) {
            long millis = System.currentTimeMillis();
            long unixTimestampInSeconds = millis / 1000;
            if (cur_token_expired_time - distance_expire_time < unixTimestampInSeconds) {
                String old_token = cur_token;
                long old_expire_time = cur_token_expired_time;
                json = getTicket(cur_method);
                String new_token = cur_token;
                long new_expire_time = cur_token_expired_time;
                Log.i("Auth", "Refresh old token(" + old_token + " : " + old_expire_time +
                        ") to (" + new_token + " : " + new_expire_time + ").");
            }
        }
        return json;
    }
}

