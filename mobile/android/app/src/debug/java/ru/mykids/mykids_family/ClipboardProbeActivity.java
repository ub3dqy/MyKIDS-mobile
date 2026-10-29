package ru.mykids.mykids_family;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

/** Debug-only foreground context for the system clipboard instrumentation test. */
public class ClipboardProbeActivity extends Activity {
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        TextView notice = new TextView(this);
        notice.setText("MyKIDS: проверка защиты семейного приглашения");
        setContentView(notice);
    }
}
