package com.daoban.shiftassistantpro

import android.content.Context
import android.content.Intent
import android.provider.AlarmClock

/**
 * 系统闹钟桥接：把 App 算好的闹钟静默写入系统时钟。
 *
 * 用 `AlarmClock.ACTION_SET_ALARM` + `EXTRA_SKIP_UI`，不弹确认界面。
 * 系统时钟的闹钟会被 ColorOS 手表的「手机闹钟提醒」同步（第三方 App 的闹钟不会）。
 *
 * 注意 API 限制：一次性闹钟只能表示「下一次到这个点」，没有日期参数。
 * 因此调用方必须保证在正确的时间调用（每日 housekeeping 在 00:30 建当天的）。
 */
object SystemAlarmBridge {
    /**
     * 静默建系统闹钟。
     *
     * [days] 为空 → 一次性（下一次到这个点）；非空 → 每周重复，
     * 取 1..7（周一..周日），对应 `AlarmClock.EXTRA_DAYS` 要的 `Calendar` 常量。
     */
    fun create(
        context: Context,
        hour: Int,
        minute: Int,
        message: String,
        days: List<Int>? = null,
    ): Boolean {
        return try {
            val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                putExtra(AlarmClock.EXTRA_HOUR, hour)
                putExtra(AlarmClock.EXTRA_MINUTES, minute)
                putExtra(AlarmClock.EXTRA_MESSAGE, message)
                putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                if (!days.isNullOrEmpty()) {
                    // AlarmClock.EXTRA_DAYS 要 ArrayList<Int>（Calendar.SUNDAY=1..SATURDAY=7）
                    val calDays = ArrayList(days.map { d -> if (d == 7) 1 else d + 1 })
                    putIntegerArrayListExtra(AlarmClock.EXTRA_DAYS, calDays)
                }
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            AlarmLog.info(context, "SystemAlarmBridge: 静默建系统闹钟 $hour:$minute $message days=$days")
            true
        } catch (e: Exception) {
            AlarmLog.error(
                context,
                "SystemAlarmBridge: 建系统闹钟失败: ${e.javaClass.name}: ${e.message}"
            )
            false
        }
    }
}
