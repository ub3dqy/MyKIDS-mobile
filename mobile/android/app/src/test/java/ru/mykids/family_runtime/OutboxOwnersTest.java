package ru.mykids.family_runtime;

import static org.junit.Assert.*;
import org.junit.Test;

public class OutboxOwnersTest {
    @Test public void detachedEngineDoesNotStayAliveWithItsProcess() {
        String first = OutboxOwners.register(), second = OutboxOwners.register();
        assertNotEquals(first, second);
        assertTrue(OutboxOwners.alive(first));
        OutboxOwners.detach(first);
        assertFalse(OutboxOwners.alive(first));
        assertTrue(OutboxOwners.alive(second));
        assertTrue(OutboxOwners.alive(OutboxOwners.processId()));
        OutboxOwners.detach(second);
    }
    @Test public void deadProcessAndUnknownEngineAreNotAlive() {
        assertFalse(OutboxOwners.alive("previous-process"));
        assertFalse(OutboxOwners.alive(null));
        assertFalse(OutboxOwners.alive(OutboxOwners.processId()+".unknown-engine"));
    }
}
