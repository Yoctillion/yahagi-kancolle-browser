package app.yahagi.kancollebrowser.browser

import org.junit.Assert.*
import org.junit.Test

class FullscreenOverlayGeometryTest {
    @Test fun leftAndRightCameraEdgesPlaceNoticesInsideTheEffectiveContent() {
        for (root in listOf(412 to 915, 915 to 412, 1280 to 800, 344 to 740)) {
            val (width, height) = root
            for (leftInset in listOf(0, 80)) {
                val rightInset = 80 - leftInset
                val content = fullscreenOverlayContentBounds(
                    width,
                    height,
                    FullscreenOverlayBounds(leftInset, 0, width - rightInset, height),
                )
                val notice = FullscreenQuestNoticeGeometry(content, 1f)
                val bounds = notice.place(notice.maxWidth, 64)
                assertTrue(bounds.left >= content.left)
                assertTrue(bounds.right <= content.right)
                assertEquals(content.left + (content.width - bounds.width) / 2, bounds.left)
                assertEquals(8, bounds.top)
                assertTrue(bounds.bottom <= content.bottom)
            }
        }
    }

    @Test fun oversizedAndTinyNoticesNeverExpandOutsideTheirContentRectangle() {
        for (density in listOf(1f, 2f, 3.5f)) {
            for (size in listOf(40 to 12, 1 to 1, 0 to 0, 160 to 48)) {
                val content = FullscreenOverlayBounds(81, 39, 81 + size.first, 39 + size.second)
                val notice = FullscreenQuestNoticeGeometry(content, density)
                val bounds = notice.place(10000, 10000)
                assertTrue(bounds.left >= content.left)
                assertTrue(bounds.top >= content.top)
                assertTrue(bounds.right <= content.right)
                assertTrue(bounds.bottom <= content.bottom)
                assertTrue(notice.maxWidth <= content.width)
                assertTrue(notice.maxHeight <= content.height)
            }
        }
    }

    @Test fun absentContentUsesCurrentRootAndStaleOrMalformedBoundsAreClamped() {
        assertEquals(
            FullscreenOverlayBounds(0, 0, 900, 400),
            fullscreenOverlayContentBounds(900, 400),
        )
        assertEquals(
            FullscreenOverlayBounds(900, 30, 900, 400),
            fullscreenOverlayContentBounds(900, 400, FullscreenOverlayBounds(1200, 30, 1000, 700)),
        )
        assertEquals(
            FullscreenOverlayBounds(0, 0, 800, 400),
            fullscreenOverlayContentBounds(900, 400, FullscreenOverlayBounds(-80, -10, 800, 450)),
        )
    }
}
