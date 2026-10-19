package app.yahagi.kancollebrowser.notification

import org.junit.Assert.assertEquals
import org.junit.Test

class NotificationStringsTest {
    @Test
    fun englishKeepsNamesAndTranslatesNotificationChrome() {
        val strings = NotificationStrings("en")
        assertEquals("Expedition alerts", strings.channelNames["expedition"])
        assertEquals("Complete", strings.completed)
        assertEquals("矢矧 · Port progress (1 task)", strings.ongoingTitle(1))
        assertEquals("矢矧 · Port progress (3 tasks)", strings.ongoingTitle(3))
        assertEquals("1 more active or completed task", strings.overflow(1))
        assertEquals("2 more active or completed tasks", strings.overflow(2))
        assertEquals("My Fleet · Sound on · Vibration off", strings.channelVariant("My Fleet", true, false))
    }
    @org.junit.Test
    fun koreanKeepsNamesAndTranslatesNotificationChrome() {
        val strings = NotificationStrings("ko")
        assertEquals("원정 알림", strings.channelNames["expedition"])
        assertEquals("완료", strings.completed)
        assertEquals("矢矧 · 모항 진행 상황 (3건)", strings.ongoingTitle(3))
        assertEquals("그 외 진행 중이거나 완료된 작업 2건", strings.overflow(2))
        assertEquals("My Fleet · 소리 켜짐 · 진동 꺼짐", strings.channelVariant("My Fleet", true, false))
    }
    @Test
    fun usesPersistedAppLocaleForNativeNotificationText() {
        assertEquals("远征通知", NotificationStrings().channelNames["expedition"])
        assertEquals("遠征通知", NotificationStrings("zh_Hant").channelNames["expedition"])
        assertEquals("入渠修理", NotificationStrings("ja").channelNames["repair"])
        assertEquals("完了", NotificationStrings("ja").completed)
        assertEquals("矢矧 · 母港の進行状況（3件）", NotificationStrings("ja").ongoingTitle(3))
        assertEquals("另有 2 項進行中或已完成任務", NotificationStrings("zh_Hant").overflow(2))
        assertEquals("遠征通知 · 音あり · 振動なし", NotificationStrings("ja").channelVariant("遠征通知", true, false))
    }
}
