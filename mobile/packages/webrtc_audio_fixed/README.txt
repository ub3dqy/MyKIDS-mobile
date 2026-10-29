MyKIDS Android audio lifecycle correction

The module retains all native libraries and all unrelated Java classes from
io.github.webrtc-sdk:android:150.7871.04. Its pinned SHA-256 is checked before
preparing a build. Only WebRtcAudioRecord and its two nested classes are compiled
from the included Java source. No downloaded fork binary or global cache edit
is used.

upstream/WebRtcAudioRecord.java is the original source at
https://github.com/webrtc-sdk/webrtc/commit/a545de45259b47dfac5f3635863e47cb601f1bb2
Its normalized JVM bytecode was compared against all three published classes
before applying the patch. See provenance.json and the release audit receipts.

The correction waits for native StartRecording before delivering PCM and
serializes delivery with native StopRecording. It also clears the started flag
after failed recording start. keepAlive is rechecked while holding the delivery
lock to exclude an orphan reader from a successor session. Client prewarming
and its PCM callbacks continue to work.

Source analysis and related reports:
https://github.com/yellowclass/spx-webrtc/pull/1
https://github.com/webrtc-sdk/webrtc/issues/315

The current Flutter plugin requests 150.7871.04; that exact request is substituted
with this verified module of the same version. The resolved release and test
graphs must both prove this selection before dependency checks pass. Review this module when
upgrading flutter_webrtc or LiveKit, and remove it after the upstream fix is
included and verified. BSD license, patent grant and authors are retained.
