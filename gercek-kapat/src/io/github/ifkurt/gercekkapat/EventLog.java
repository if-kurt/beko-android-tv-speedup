package io.github.ifkurt.gercekkapat;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.LinkedList;
import java.util.List;
import java.util.Locale;

/** Last few events, kept in a small file so they survive the shutdown. Read them with dumpsys. */
final class EventLog {
    private static final int MAX_LINES = 80;
    private final File file;
    private final LinkedList<String> lines = new LinkedList<String>();
    private final SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US);

    EventLog(File file) {
        this.file = file;
        load();
    }

    synchronized void add(String message) {
        lines.add(format.format(new Date()) + "  " + message);
        while (lines.size() > MAX_LINES) {
            lines.removeFirst();
        }
        save();
    }

    synchronized List<String> lines() {
        return new ArrayList<String>(lines);
    }

    private void load() {
        if (!file.isFile()) {
            return;
        }
        try {
            BufferedReader reader = new BufferedReader(new InputStreamReader(new FileInputStream(file), "UTF-8"));
            try {
                String line;
                while ((line = reader.readLine()) != null) {
                    lines.add(line);
                }
            } finally {
                reader.close();
            }
            while (lines.size() > MAX_LINES) {
                lines.removeFirst();
            }
        } catch (IOException ignored) {
        }
    }

    private void save() {
        try {
            FileOutputStream stream = new FileOutputStream(file);
            Writer writer = new OutputStreamWriter(stream, "UTF-8");
            try {
                for (String line : lines) {
                    writer.write(line);
                    writer.write('\n');
                }
                writer.flush();
                stream.getFD().sync();
            } finally {
                writer.close();
            }
        } catch (IOException ignored) {
        }
    }
}
