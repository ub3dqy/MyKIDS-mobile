package com.tekartik.sqflite;

import static org.junit.Assert.*;

import android.content.Context;
import android.database.sqlite.SQLiteDatabase;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import java.util.ArrayList;
import java.util.IdentityHashMap;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import org.junit.Test;
import org.junit.After;
import org.junit.runner.RunWith;
import io.flutter.embedding.engine.FlutterEngine;

@RunWith(AndroidJUnit4.class)
public class EngineDetachDatabaseTest {
    private final Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
    private final Map<SqflitePlugin, FlutterEngine> engines = new IdentityHashMap<>();

    private SqflitePlugin plugin() {
        AtomicReference<FlutterEngine> created = new AtomicReference<>();
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            FlutterEngine engine = new FlutterEngine(context, null, false);
            engine.getPlugins().add(new SqflitePlugin());
            created.set(engine);
        });
        SqflitePlugin plugin = (SqflitePlugin) created.get().getPlugins().get(SqflitePlugin.class);
        assertNotNull(plugin);
        engines.put(plugin, created.get());
        return plugin;
    }
    private void detach(SqflitePlugin plugin) {
        FlutterEngine engine = engines.remove(plugin);
        if (engine != null) InstrumentationRegistry.getInstrumentation().runOnMainSync(engine::destroy);
    }
    @After public void destroyRemainingEngines() {
        for (SqflitePlugin plugin : new ArrayList<>(engines.keySet())) detach(plugin);
    }

    private static final class Reply implements MethodChannel.Result {
        final CountDownLatch done = new CountDownLatch(1);
        Object value;
        String error;
        @Override public void success(Object result) { value = result; done.countDown(); }
        @Override public void error(String code, String message, Object details) {
            error = code + ": " + message; done.countDown();
        }
        @Override public void notImplemented() { error = "not implemented"; done.countDown(); }
        Object await() throws InterruptedException {
            assertTrue("Native database callback timed out", done.await(8, TimeUnit.SECONDS));
            assertNull(error, error);
            return value;
        }
    }

    private static Map<String, Object> args(Object... values) {
        Map<String, Object> map = new HashMap<>();
        for (int i = 0; i < values.length; i += 2) map.put((String) values[i], values[i + 1]);
        return map;
    }
    private static Object call(SqflitePlugin plugin, String method, Map<String, Object> args) throws Exception {
        Reply reply = new Reply();
        plugin.onMethodCall(new MethodCall(method, args), reply);
        return reply.await();
    }
    private static int open(SqflitePlugin plugin, String path, boolean shared) throws Exception {
        Map<?, ?> result = (Map<?, ?>) call(plugin, "openDatabase", args("path", path, "singleInstance", shared));
        return ((Number) result.get("id")).intValue();
    }
    private static void sql(SqflitePlugin plugin, int id, String sql) throws Exception {
        Map<String, Object> values = args("id", id, "sql", sql, "arguments", Collections.emptyList(), "transactionId", -1);
        if (sql.startsWith("BEGIN")) values.put("inTransaction", true);
        call(plugin, "execute", values);
    }
    private String path() { return context.getDatabasePath("mykids-detach-" + UUID.randomUUID() + ".db").getPath(); }
    private static void close(SqflitePlugin plugin, int id) throws Exception {
        call(plugin, "closeDatabase", args("id", id));
    }
    private static Map<?, ?> handles(SqflitePlugin plugin) throws Exception {
        Map<?, ?> state = (Map<?, ?>) call(plugin, "debug", args("cmd", "get"));
        Object handles = state.get("databases");
        return handles instanceof Map ? (Map<?, ?>) handles : Collections.emptyMap();
    }
    private static long count(SqflitePlugin plugin, int id) throws Exception {
        Map<?, ?> data = (Map<?, ?>) call(plugin, "query", args("id", id, "sql", "SELECT COUNT(*) FROM proof", "arguments", Collections.emptyList()));
        java.util.List<?> rows = (java.util.List<?>) data.get("rows");
        return ((Number) ((java.util.List<?>) rows.get(0)).get(0)).longValue();
    }

    @Test public void abandonedTransactionRollsBackAndOtherEngineCanWrite() throws Exception {
        String path = path();
        SqflitePlugin first = plugin(), second = plugin();
        int a = open(first, path, false);
        call(first, "query", args("id", a, "sql", "PRAGMA journal_mode=WAL", "arguments", Collections.emptyList()));
        sql(first, a, "CREATE TABLE proof(id INTEGER PRIMARY KEY)");
        sql(first, a, "INSERT INTO proof VALUES(1)");
        int b = open(second, path, false);
        sql(first, a, "BEGIN EXCLUSIVE");
        sql(first, a, "INSERT INTO proof VALUES(2)");
        detach(first);
        // The same native worker serializes detach cleanup before this write.
        sql(second, b, "INSERT INTO proof VALUES(3)");
        assertEquals(2, count(second, b)); // committed 1 + new 3; abandoned 2 is gone.
        close(second, b);
        SQLiteDatabase.deleteDatabase(new java.io.File(path));
    }

    @Test public void detachClosesAllPrivateHandlesButKeepsOtherEngineOpen() throws Exception {
        String path = path();
        SqflitePlugin first = plugin(), second = plugin();
        int a = open(first, path, false), extra = open(first, path, false), b = open(second, path, false);
        sql(second, b, "CREATE TABLE proof(id INTEGER PRIMARY KEY)");
        detach(first);
        sql(second, b, "INSERT INTO proof VALUES(1)");
        Map<?, ?> handles = handles(second);
        assertFalse(handles.containsKey(Integer.toString(a)));
        assertFalse(handles.containsKey(Integer.toString(extra)));
        assertTrue(handles.containsKey(Integer.toString(b)));
        assertEquals(1, count(second, b));
        close(second, b);
        SQLiteDatabase.deleteDatabase(new java.io.File(path));
    }

    @Test public void sharedHandleSurvivesAnotherEngineDetaching() throws Exception {
        String path = path();
        SqflitePlugin first = plugin(), second = plugin();
        int a = open(first, path, true), b = open(second, path, true);
        assertEquals(a, b);
        detach(first);
        sql(second, b, "CREATE TABLE proof(id INTEGER PRIMARY KEY)");
        sql(second, b, "INSERT INTO proof VALUES(1)");
        assertEquals(1, count(second, b));
        close(second, b);
        SQLiteDatabase.deleteDatabase(new java.io.File(path));
    }

    @Test public void openCompletingAfterDetachDoesNotLeakItsPrivateHandle() throws Exception {
        String path = path();
        SqflitePlugin first = plugin();
        Reply opening = new Reply();
        first.onMethodCall(new MethodCall("openDatabase", args("path", path, "singleInstance", false)), opening);
        detach(first);
        assertTrue(opening.done.await(8, TimeUnit.SECONDS));
        // Opening another handle queues behind any in-flight detach cleanup.
        SqflitePlugin second = plugin();
        int b = open(second, path, false);
        sql(second, b, "CREATE TABLE proof(id INTEGER PRIMARY KEY)");
        sql(second, b, "INSERT INTO proof VALUES(1)");
        assertEquals(1, count(second, b));
        assertEquals(1, handles(second).values().stream().filter(d -> path.equals(((Map<?, ?>) d).get("path"))).count());
        close(second, b);
        SQLiteDatabase.deleteDatabase(new java.io.File(path));
    }

    @Test public void queuedOpenSurvivesAnUnawaitedClose() throws Exception {
        String firstPath = path(), secondPath = path();
        SqflitePlugin owner = plugin();
        int first = open(owner, firstPath, false);
        Reply closing = new Reply(), opening = new Reply();
        java.lang.reflect.Field field = SqflitePlugin.class.getDeclaredField("openCloseLocker");
        field.setAccessible(true);
        // Hold the worker until both calls are queued, making the race repeatable.
        synchronized (field.get(null)) {
            owner.onMethodCall(new MethodCall("closeDatabase", args("id", first)), closing);
            owner.onMethodCall(new MethodCall("openDatabase", args("path", secondPath,
                    "singleInstance", false)), opening);
        }
        closing.await();
        int second = ((Number) ((Map<?, ?>) opening.await()).get("id")).intValue();
        sql(owner, second, "CREATE TABLE proof(id INTEGER PRIMARY KEY)");
        sql(owner, second, "INSERT INTO proof VALUES(1)");
        assertEquals(1, count(owner, second));
        close(owner, second);
        SQLiteDatabase.deleteDatabase(new java.io.File(firstPath));
        SQLiteDatabase.deleteDatabase(new java.io.File(secondPath));
    }
}
