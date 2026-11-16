// Versarite Image Lab link for Fiji
// ---------------------------------
// Lets Versarite Image Lab hand images (and macros) to the Fiji that is
// already running, instead of starting a new Fiji each time.
//
// Install: copy this file into  <Fiji>\scripts\Plugins\AutoRun\
//          and restart Fiji. Fiji runs it at every start.
//          (JavaScript, like Fiji's own AutoRun script: Fiji runs the
//          files there through ImageJ, which takes .js but would read a
//          .groovy file as an ImageJ macro.)
//
// It listens on 127.0.0.1 port 57317 (this computer only, nothing from
// the network). One command per line, UTF-8; one reply line per command,
// starting with "OK" or "ERR":
//
//   PING              -> OK <ImageJ version>
//   OPEN <file>       -> OK <image title>      opens the file, window to front
//   EVAL <macro>      -> OK <macro result>     runs ImageJ macro code
//                     -> ERR line=<n>; <why>   the macro failed: ImageJ's
//                        message, its line, and what it wrote to the Log
//                        meanwhile (no error dialog in Fiji; images it
//                        left in batch mode are closed)
//
// In EVAL text and in replies, a backslash is written \\ and a line
// break \n, so that each command and each reply stays on one line.
//
// Part of Versarite Image Lab (GPL v3), https://github.com/versarite

(function () {
    var PORT = 57317;
    var FLAG = "versarite.lab.link";

    var IJ = Packages.ij.IJ;
    var WindowManager = Packages.ij.WindowManager;
    var System = java.lang.System;

    // Already running (script started twice)? Then nothing to do.
    if (System.getProperty(FLAG) != null) return;

    var server;
    try {
        server = new java.net.ServerSocket(PORT, 10, java.net.InetAddress.getLoopbackAddress());
    } catch (e) {
        // Another Fiji already listens: images go to that one.
        IJ.log("Versarite Lab link: port " + PORT + " is in use by another program; link not started.");
        return;
    }
    System.setProperty(FLAG, String(PORT));

    function escape(s) {
        if (s == null) return "";
        return String(s).replace(/\\/g, "\\\\").replace(/\r/g, "").replace(/\n/g, "\\n");
    }

    function unescape(s) {
        return String(s).replace(/\\(.)/g, function (m, c) { return c === "n" ? "\n" : c; });
    }

    function toFront() {
        java.awt.EventQueue.invokeLater(new java.lang.Runnable({
            run: function () {
                var w = WindowManager.getCurrentWindow();
                if (w != null) {
                    if (w.getState() == java.awt.Frame.ICONIFIED) w.setState(java.awt.Frame.NORMAL);
                    w.toFront();
                }
            }
        }));
    }

    function logLength() {
        var t = IJ.getLog();
        return t == null ? 0 : String(t).length;
    }

    // What the Log got since AFrom (the last few lines).
    function logSince(from) {
        var t = IJ.getLog();
        if (t == null) return "";
        t = String(t);
        if (t.length <= from) return "";
        var lines = t.substring(from).replace(/\r/g, "").split("\n").filter(function (l) {
            return l.trim() !== "";
        });
        return lines.slice(-6).join("\n");
    }

    // A failed macro may leave images in batch mode: closed, unsaved.
    function closeBatchImages() {
        var Interp = Packages.ij.macro.Interpreter;
        try {
            var ids = Interp.getBatchModeImageIDs();
            for (var i = 0; i < ids.length; i++) {
                var imp = Interp.getBatchModeImage(ids[i]);
                if (imp != null) {
                    imp.changes = false;
                    imp.close();
                }
            }
        } catch (e) { }
        Interp.batchMode = false;
    }

    function runMacro(macro) {
        var from = logLength();
        var interp = new Packages.ij.macro.Interpreter();
        // Errors come back to the Lab instead of a dialog in Fiji.
        interp.setIgnoreErrors(true);
        IJ.redirectErrorMessages(true);
        var r = null, ex = null;
        try {
            r = interp.run(macro, null);
        } catch (e) {
            ex = e;
        } finally {
            IJ.redirectErrorMessages(false);
        }
        var msg = interp.getErrorMessage();
        var aborted = r != null && String(r) === "[aborted]";
        if (msg == null && ex == null && !aborted) return "OK " + escape(r);
        var why;
        if (msg != null) why = String(msg);
        else if (ex != null) why = String(ex.message != null ? ex.message : ex);
        else why = "macro aborted";
        why = why.replace(/^java\.lang\.RuntimeException: /, "");
        var log = logSince(from);
        if (log !== "") why = why + "\n" + log;
        closeBatchImages();
        return "ERR line=" + interp.getLineNumber() + "; " + escape(why);
    }

    function handle(line) {
        var sp = line.indexOf(" ");
        var cmd = (sp < 0 ? line : line.substring(0, sp)).trim().toUpperCase();
        var arg = sp < 0 ? "" : line.substring(sp + 1);
        if (cmd === "PING") {
            return "OK " + IJ.getVersion();
        }
        if (cmd === "OPEN") {
            var f = new java.io.File(arg.trim());
            if (!f.isFile()) return "ERR no such file: " + arg.trim();
            IJ.open(f.getPath());
            var imp = WindowManager.getCurrentImage();
            toFront();
            return "OK " + escape(imp != null ? imp.getTitle() : f.getName());
        }
        if (cmd === "EVAL") {
            return runMacro(unescape(arg));
        }
        return "ERR unknown command: " + cmd;
    }

    function serve(s) {
        try {
            s.setSoTimeout(60000);
            var UTF8 = java.nio.charset.StandardCharsets.UTF_8;
            var reader = new java.io.BufferedReader(new java.io.InputStreamReader(s.getInputStream(), UTF8));
            var writer = new java.io.OutputStreamWriter(s.getOutputStream(), UTF8);
            var line;
            while ((line = reader.readLine()) != null) {
                line = String(line);
                if (line.trim() === "") continue;
                var reply;
                try {
                    reply = handle(line);
                } catch (e) {
                    reply = "ERR " + escape(String(e));
                }
                writer.write(reply + "\n");
                writer.flush();
            }
        } catch (e) {
            // timeout or the Lab hung up: nothing to do
        } finally {
            try { s.close(); } catch (e) { }
        }
    }

    var listener = new java.lang.Thread(new java.lang.Runnable({
        run: function () {
            while (!server.isClosed()) {
                var client;
                try {
                    client = server.accept();
                } catch (e) {
                    break;
                }
                (function (c) {
                    var worker = new java.lang.Thread(new java.lang.Runnable({
                        run: function () { serve(c); }
                    }), "Versarite Lab link client");
                    worker.setDaemon(true);
                    worker.start();
                })(client);
            }
        }
    }), "Versarite Lab link");
    listener.setDaemon(true);
    listener.start();
})();
