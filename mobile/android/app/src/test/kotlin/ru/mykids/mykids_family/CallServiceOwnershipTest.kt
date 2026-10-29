package ru.mykids.mykids_family

import org.junit.Assert.*
import org.junit.Test

class CallServiceOwnershipTest {
    @Test fun oldScreenCannotStopReopenedSameCall() {
        val state = CallServiceOwnership()
        state.claim("old-screen", "same-call")
        assertTrue(state.start("old-screen", "old-start"))
        state.claim("new-screen", "same-call")
        assertTrue(state.start("new-screen", "new-start"))
        assertFalse(state.stop("old-screen"))
        assertFalse(state.ownsCall("old-screen", "same-call"))
        assertTrue(state.windowActive)
        assertTrue(state.matches("new-screen", "new-start"))
    }

    @Test fun oldAcknowledgementAndTimeoutCannotStopNewCall() {
        val state = CallServiceOwnership()
        state.claim("first", "call-one")
        state.start("first", "old")
        state.claim("second", "call-two")
        state.start("second", "new")
        assertFalse(state.matches("first", "old"))
        assertFalse(state.expire("first", "old"))
        assertTrue(state.matches("second", "new"))
    }

    @Test fun olderCameraRequestCannotExpireLatestAudioRequest() {
        val state = CallServiceOwnership()
        state.claim("screen", "call")
        state.start("screen", "camera")
        state.start("screen", "audio")
        assertFalse(state.expire("screen", "camera"))
        assertFalse(state.matches("screen", "camera"))
        assertTrue(state.matches("screen", "audio"))
    }

    @Test fun stoppedScreenCannotRestartAndLatestTimeoutInvalidatesLateStart() {
        val state = CallServiceOwnership()
        state.claim("screen", "call")
        state.start("screen", "start")
        assertTrue(state.expire("screen", "start"))
        assertFalse(state.matches("screen", "start"))
        assertTrue(state.start("screen", "fallback"))
        assertTrue(state.stop("screen"))
        assertFalse(state.windowActive)
        assertFalse(state.start("screen", "late"))
        assertFalse(state.matches("screen", "fallback"))
    }

    @Test fun unownedCommandsAreIgnoredAndOwnerCanFinishItsWindow() {
        val state = CallServiceOwnership()
        assertFalse(state.stop(null))
        assertFalse(state.start("missing", "start"))
        state.claim("screen", "call")
        assertTrue(state.ownsCall("screen", "call"))
        assertFalse(state.ownsCall("screen", "other-call"))
        assertTrue(state.stop("screen"))
        assertTrue(state.owns("screen"))
        state.claim("new", "call")
        assertFalse(state.owns("screen"))
    }
}
