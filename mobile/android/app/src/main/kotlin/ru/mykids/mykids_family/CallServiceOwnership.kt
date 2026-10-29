package ru.mykids.mykids_family

/** Each screen owns a distinct lease, even when reopening the same call. */
class CallServiceOwnership {
    private var owner: String? = null
    private var callId: String? = null
    private var request: String? = null
    private var stopped = true
    val windowActive: Boolean get() = owner != null && !stopped

    fun claim(lease: String, id: String) {
        owner = lease
        callId = id
        request = null
        stopped = false
    }

    fun owns(lease: String?): Boolean = lease != null && owner == lease
    fun ownsCall(lease: String?, id: String?): Boolean = owns(lease) && callId == id
    fun start(lease: String?, nextRequest: String): Boolean {
        if (!owns(lease) || stopped) return false
        request = nextRequest
        return true
    }

    fun matches(lease: String?, candidate: String?): Boolean =
        owns(lease) && !stopped && candidate != null && request == candidate

    fun expire(lease: String?, candidate: String?): Boolean {
        if (!matches(lease, candidate)) return false
        request = null
        return true
    }

    fun stop(lease: String?): Boolean {
        if (!owns(lease)) return false
        stopped = true
        request = null
        return true
    }
}
