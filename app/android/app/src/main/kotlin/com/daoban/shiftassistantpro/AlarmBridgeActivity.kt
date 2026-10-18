package com.daoban.shiftassistantpro

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import org.json.JSONArray

/**
 * 透明中转 Activity：00:30 housekeeping 的前台跳板。
 *
 * 背景 Receiver 直接 startActivity(ACTION_SET_ALARM) 会被 OPPO 在解锁后弹出时钟页。
 * 经由一个前台（透明）Activity 再调 SystemAlarmBridge.create()，
 * 等价于用户在前台点"保存"的路径，SKIP_UI 生效，不弹页。
 */
class AlarmBridgeActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val alarmsJson = intent.getStringExtra("alarms_json") ?: "[]"
            val alarms = JSONArray(alarmsJson)
            for (i in 0 until alarms.length()) {
                val a = alarms.getJSONObject(i)
                SystemAlarmBridge.create(
                    this,
                    a.optInt("h", 7),
                    a.optInt("m", 30),
                    a.optString("msg", "闹钟"),
                )
            }
            AlarmLog.info(this, "AlarmBridgeActivity: 建 ${alarms.length()} 个闹钟")
        } catch (e: Exception) {
            AlarmLog.error(this, "AlarmBridgeActivity 失败: ${e.javaClass.name}: ${e.message}")
        }
        finish()
    }
}
