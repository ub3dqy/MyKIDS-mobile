# MyKIDS Android engine cleanup

Pinned upstream package: sqflite_android 2.4.5. The original licence and source
are retained. The shared Pub cache is unchanged.

An interrupted Android background worker can destroy its Flutter engine while
a private SQLite connection owns a transaction. Upstream detachment only removes
the method channel; its process-wide connection map keeps that transaction alive.
On 19 October 2026 this was observed during natural deep-idle maintenance: an
abandoned writer remained acquired for more than ten minutes, and later refresh
jobs exhausted their SQLite retry budget and failed their dependents.

This patch tracks private (`singleInstance: false`) handles per engine. Detach
and late completion of an open release those handles on their original worker,
roll back abandoned transactions and close cursors. Committed data and handles
owned by other engines are preserved. Shared single-instance handles retain
upstream behaviour. A bounded shared SQLite worker pool is retained after detach
to avoid discarding another engine's pending open; an ordinary close can shut it
down afterwards.

Keep this patch when upgrading sqflite_android until upstream provides equivalent
engine ownership and interrupted-transaction cleanup. Android instrumentation
tests cover rollback, other-engine ownership and an in-flight open during detach.

The 2.4.5 pending open/close counter is retained. Pool shutdown also waits for
engine-detach closes, preserving the existing ownership patch.

The Android build plugin matches the application's verified 9.4.1 version.
