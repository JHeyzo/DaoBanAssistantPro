package com.daoban.shiftassistantpro

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 原生闹钟接收器（已停用）。
 *
 * App 不再自己响铃：班次/自定义闹钟改走系统时钟（SystemAlarmBridge +
 * HousekeepingReceiver，每天 00:30 建当天那批）。这里只留一个空壳，
 * 防止已排定的旧闹钟在触发时崩溃；旧闹钟由 Dart 侧 `cancelAllNativeAlarms`
 * 在重排时清掉。
 */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", 0)
        AlarmLog.info(context, "AlarmReceiver.onReceive: 已停用，忽略 id=$id")
        // 把落盘清单里那条删掉，避免 BootReceiver 重排。
        AlarmStore.remove(context, id)
    }
}
