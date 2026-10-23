package com.oneova.app

import android.app.Notification
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Lets Ova read, open, reply to and dismiss notifications once the user turns
 * on Notification access for Oneova. Everything stays in memory on the phone.
 */
class OvaNotificationListener : NotificationListenerService() {

    companion object {
        @Volatile
        var instance: OvaNotificationListener? = null
            private set

        fun isConnected(): Boolean = instance != null
    }

    private val ignoredPackages = setOf("android", "com.android.systemui")

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        OvaDeviceHub.emit("notification_access", mapOf("enabled" to true))
    }

    override fun onListenerDisconnected() {
        instance = null
        OvaDeviceHub.emit("notification_access", mapOf("enabled" to false))
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null || !isUseful(sbn)) return
        OvaDeviceHub.emit("notification", toMap(sbn))
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn == null) return
        OvaDeviceHub.emit("notification_removed", mapOf("key" to sbn.key))
    }

    private fun isUseful(sbn: StatusBarNotification): Boolean {
        if (sbn.packageName in ignoredPackages) return false
        if (sbn.packageName == packageName) return false
        val n = sbn.notification
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return false
        val extras = n.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)
        return !title.isNullOrBlank() || !text.isNullOrBlank()
    }

    fun recent(limit: Int): List<Map<String, Any?>> {
        val all = try { activeNotifications?.toList() ?: emptyList() } catch (_: Exception) { emptyList() }
        return all.filter { isUseful(it) }
            .sortedByDescending { it.postTime }
            .take(limit)
            .map { toMap(it) }
    }

    private fun toMap(sbn: StatusBarNotification): Map<String, Any?> {
        val n = sbn.notification
        val extras = n.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val big = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
        val text = big ?: extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        return mapOf(
            "key" to sbn.key,
            "package" to sbn.packageName,
            "app" to appLabel(sbn.packageName),
            "title" to title,
            "text" to text.take(500),
            "postTime" to sbn.postTime,
            "canReply" to (replyAction(n) != null),
            "category" to (n.category ?: ""),
            "ongoing" to sbn.isOngoing,
        )
    }

    private fun appLabel(pkg: String): String = try {
        val pm = packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (_: PackageManager.NameNotFoundException) {
        pkg
    }

    private fun find(key: String): StatusBarNotification? =
        try { activeNotifications?.firstOrNull { it.key == key } } catch (_: Exception) { null }

    private fun replyAction(n: Notification): Notification.Action? =
        n.actions?.firstOrNull { a -> a.remoteInputs?.any { it.allowFreeFormInput } == true }

    /** Sends [text] through the notification's own inline-reply action. */
    fun reply(key: String, text: String): String {
        val sbn = find(key) ?: return "gone"
        val action = replyAction(sbn.notification) ?: return "no_reply"
        val inputs = action.remoteInputs ?: return "no_reply"
        val intent = Intent()
        val bundle = Bundle()
        for (ri in inputs) bundle.putCharSequence(ri.resultKey, text)
        RemoteInput.addResultsToIntent(inputs, intent, bundle)
        return try {
            action.actionIntent.send(this as Context, 0, intent)
            "ok"
        } catch (e: Exception) {
            "error:${e.message}"
        }
    }

    fun open(key: String): Boolean {
        val sbn = find(key) ?: return false
        return try {
            sbn.notification.contentIntent?.send() ?: return false
            true
        } catch (_: Exception) {
            false
        }
    }

    fun dismiss(key: String): Boolean = try {
        cancelNotification(key)
        true
    } catch (_: Exception) {
        false
    }
}
