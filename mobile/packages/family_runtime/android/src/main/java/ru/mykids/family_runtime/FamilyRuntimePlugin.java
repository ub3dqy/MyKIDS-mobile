package ru.mykids.family_runtime;

import android.content.Context;
import android.net.ConnectivityManager;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodChannel;

/** All Flutter engines in this application's single Android process share it. */
public final class FamilyRuntimePlugin implements FlutterPlugin {
    private static final String PROCESS_ID = OutboxOwners.processId();
    private MethodChannel channel;
    private String outboxOwner;

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        outboxOwner = OutboxOwners.register();
        channel = new MethodChannel(binding.getBinaryMessenger(), "ru.mykids/runtime");
        channel.setMethodCallHandler((call, result) -> {
            if (call.method.equals("processIdentity")) result.success(PROCESS_ID);
            else if (call.method.equals("outboxOwner")) result.success(outboxOwner);
            else if (call.method.equals("outboxOwnerAlive")) result.success(OutboxOwners.alive(call.argument("owner")));
            else if (call.method.equals("androidSdkInt")) result.success(android.os.Build.VERSION.SDK_INT);
            else if (call.method.equals("backgroundDataRestricted")) {
                ConnectivityManager connectivity = (ConnectivityManager)
                        binding.getApplicationContext().getSystemService(Context.CONNECTIVITY_SERVICE);
                result.success(connectivity != null && connectivity.isActiveNetworkMetered()
                        && connectivity.getRestrictBackgroundStatus()
                        == ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED);
            }
            else result.notImplemented();
        });
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        OutboxOwners.detach(outboxOwner);
        outboxOwner = null;
        channel.setMethodCallHandler(null);
        channel = null;
    }
}
