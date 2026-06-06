package com.airbridge.mirror

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AccessibilityStatusTest {
    private val comp = "com.airbridge/com.airbridge.mirror.MirrorAccessibilityService"

    @Test fun enabledWhenPresent() {
        assertTrue(accessibilityServiceEnabled("a/b:$comp:c/d", comp))
    }

    @Test fun enabledWhenOnlyOne() {
        assertTrue(accessibilityServiceEnabled(comp, comp))
    }

    @Test fun disabledWhenAbsent() {
        assertFalse(accessibilityServiceEnabled("a/b:c/d", comp))
    }

    @Test fun disabledWhenNull() {
        assertFalse(accessibilityServiceEnabled(null, comp))
    }

    @Test fun disabledWhenEmpty() {
        assertFalse(accessibilityServiceEnabled("", comp))
    }
}
