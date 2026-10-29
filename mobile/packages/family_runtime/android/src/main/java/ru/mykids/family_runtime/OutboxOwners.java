package ru.mykids.family_runtime;

import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/** Only detached engines may have their still-persisted upload lease reclaimed. */
final class OutboxOwners {
    private static final String PROCESS_ID = UUID.randomUUID().toString();
    private static final Set<String> ACTIVE = ConcurrentHashMap.newKeySet();
    static String processId() { return PROCESS_ID; }
    static String register() {
        String owner = PROCESS_ID + "." + UUID.randomUUID();
        ACTIVE.add(owner);
        return owner;
    }
    static boolean alive(String owner) {
        return PROCESS_ID.equals(owner) || (owner != null && ACTIVE.contains(owner));
    }
    static void detach(String owner) { if (owner != null) ACTIVE.remove(owner); }
}
