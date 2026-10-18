package com.daoban.shiftassistantpro

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONArray

/**
 * 系统闹钟的每日 housekeeping 接收器。
 *
 * 每天 00:30 触发一次（由 Dart 侧排定 30 天，id 段 50000+）。
 * 触发时读取 SharedPreferences 里预存的「当天闹钟表」，逐条静默写入系统时钟。
 *
 * 为什么是 00:30 建当天：系统闹钟 API 的一次性闹钟只能表示「下一次到这个点」，
 * 在一天刚开始时建，「下一次」就是今天，任何钟点都不会错位。
 */
class HousekeepingReceiver : BroadcastReceiver() {
    companion object {
        const val PREFS = "system_alarm_housekeeping"
        const val KEY_DAYS = "days_json"
        const val BASE_ID = 50000
        const val DAYS = 30

        fun saveDays(context: Context, daysJson: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_DAYS, daysJson)
                .apply()
        }

        fun loadDays(context: Context): JSONArray {
            val json = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY_DAYS, "[]") ?: "[]"
            return try {
                JSONArray(json)
            } catch (e: Exception) {
                JSONArray()
            }
        }

        fun clear(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .remove(KEY_DAYS)
                .apply()
        }

        /**
         * 排定未来 [DAYS] 天的 housekeeping（每天 00:30）。
         *
         * [daysJson] 由 Dart 侧算好：`[{"dayOffset":1,"alarms":[{"h":7,"m":30,"msg":"白班"}]}, …]`，
         * dayOffset 以今天为 0。00:30 建当天系统闹钟时，「下一次到这个点」就是今天，
         * 任何钟点都不会错位。
         */
        fun scheduleAll(context: Context, daysJson: String) {
            saveDays(context, daysJson)
            val am = context.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
            val show = Intent(context, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
            }
            var scheduled = 0
            for (dayOffset in 1..DAYS) {
                val trigger = java.util.Calendar.getInstance().apply {
                    add(java.util.Calendar.DAY_OF_YEAR, dayOffset)
                    set(java.util.Calendar.HOUR_OF_DAY, 0)
                    set(java.util.Calendar.MINUTE, 30)
                    set(java.util.Calendar.SECOND, 0)
                    set(java.util.Calendar.MILLISECOND, 0)
                }.timeInMillis
                if (trigger <= System.currentTimeMillis()) continue
                val op = Intent(context, HousekeepingReceiver::class.java).apply {
                    putExtra("dayOffset", dayOffset)
                }
                val opPi = android.app.PendingIntent.getBroadcast(
                    context, BASE_ID + dayOffset, op,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                        android.app.PendingIntent.FLAG_IMMUTABLE
                )
                val showPi = android.app.PendingIntent.getActivity(
                    context, BASE_ID + dayOffset, show,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                        android.app.PendingIntent.FLAG_IMMUTABLE
                )
                am.setAlarmClock(
                    android.app.AlarmManager.AlarmClockInfo(trigger, showPi), opPi
                )
                scheduled++
            }
            AlarmLog.info(context, "HousekeepingReceiver.scheduleAll: 排定 $scheduled 天")
        }

        fun cancelAll(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
            for (dayOffset in 1..DAYS) {
                val op = Intent(context, HousekeepingReceiver::class.java)
                val opPi = android.app.PendingIntent.getBroadcast(
                    context, BASE_ID + dayOffset, op,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                        android.app.PendingIntent.FLAG_IMMUTABLE
                )
                am.cancel(opPi)
            }
            clear(context)
            AlarmLog.info(context, "HousekeepingReceiver.cancelAll: 已取消")
        }

        /** 开机重排：从落盘数据里把还没过的 housekeeping 捡回来。 */
        fun rescheduleOnBoot(context: Context) {
            val json = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY_DAYS, null) ?: return
            if (json == "[]") return
            scheduleAll(context, json)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val dayOffset = intent.getIntExtra("dayOffset", -1)
        if (dayOffset < 0) return

        AlarmLog.info(context, "HousekeepingReceiver: dayOffset=$dayOffset")

        try {
            val days = loadDays(context)
            for (i in 0 until days.length()) {
                val day = days.getJSONObject(i)
                if (day.optInt("dayOffset", -1) != dayOffset) continue
                val alarms = day.optJSONArray("alarms") ?: continue
                // 经由透明 Activity 前台建闹钟（后台直发会被 OPPO 在解锁后弹页）
                val bridge = Intent(context, AlarmBridgeActivity::class.java).apply {
                    putExtra("alarms_json", alarms.toString())
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(bridge)
                AlarmLog.info(context, "HousekeepingReceiver: 已拉起 AlarmBridgeActivity")
                break
            }
        } catch (e: Exception) {
            AlarmLog.error(
                context,
                "HousekeepingReceiver 失败: ${e.javaClass.name}: ${e.message}"
            )
        }
    }
}
