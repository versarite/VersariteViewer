// Send to Versarite Lab
// ---------------------
// Fiji's menu: Plugins > Versarite > Send to Versarite Lab.
// The current image, as Fiji shows it (this slice, its colours / LUT and
// display range, an overlay drawn in), goes to Versarite Image Lab as a
// calibrated TIFF (the Lab reads ImageJ's µm scale) and opens in the Lab
// already running (the Lab hands it over to itself; [Startup]
// OnlyOneInstance=1, the default).
//
// Where the Lab is: the Lab writes its program's path into
//   %TEMP%\VersariteImageLab\VersariteImageLab.path
// whenever it sends an image to Fiji. Without that file, this asks once
// and remembers the answer (ImageJ's preferences, "versarite.lab.exe").
//
// Install: <Fiji>\scripts\Plugins\Versarite\ (the Lab puts it there),
//          then restart Fiji or Help > Refresh Menus.
//
// Part of Versarite Image Lab (GPL v3), https://github.com/versarite

(function () {
    var IJ = Packages.ij.IJ;
    var Prefs = Packages.ij.Prefs;
    var WindowManager = Packages.ij.WindowManager;
    var File = java.io.File;
    var PREF = "versarite.lab.exe";

    var imp = WindowManager.getCurrentImage();
    if (imp == null) {
        IJ.error("Send to Versarite Lab", "There is no image open.");
        return;
    }

    var tempDir = new File(java.lang.System.getProperty("java.io.tmpdir"), "VersariteImageLab");

    function readPathFile() {
        var f = new File(tempDir, "VersariteImageLab.path");
        if (!f.isFile()) return "";
        try {
            var bytes = java.nio.file.Files.readAllBytes(f.toPath());
            return String(new java.lang.String(bytes, "UTF-8")).trim();
        } catch (e) {
            return "";
        }
    }

    // The Lab's program: the path the Lab left, else the one remembered,
    // else asked (and remembered).
    var exe = readPathFile();
    if (exe === "" || !new File(exe).isFile()) {
        exe = String(Prefs.get(PREF, ""));
    }
    if (exe === "" || !new File(exe).isFile()) {
        var od = new Packages.ij.io.OpenDialog("Where is Versarite Image Lab? (VersariteImageLab.exe)", "");
        if (od.getFileName() == null) return;
        exe = String(od.getPath());
        Prefs.set(PREF, exe);
        Prefs.savePreferences();
    }

    // What Fiji shows: an RGB copy of this slice (LUT, display range and
    // overlay drawn in), with the image's calibration.
    var out = imp;
    if (imp.getBitDepth() != 24 || imp.getStackSize() > 1 || imp.getOverlay() != null
            || imp.isComposite()) {
        out = imp.flatten();
        out.setCalibration(imp.getCalibration().copy());
    }

    var title = String(imp.getTitle()).replace(/\.(tif|tiff|png|jpg|jpeg|gif|bmp|lif|czi|nd2)$/i, "");
    title = title.replace(/[\\\/:*?"<>|]/g, "_");
    if (title.length > 80) title = title.substring(0, 80);
    if (title === "") title = "image";
    var stamp = new java.text.SimpleDateFormat("HHmmss").format(new java.util.Date());

    tempDir.mkdirs();
    var target = new File(tempDir, title + "_fiji_" + stamp + ".tif");
    if (!new Packages.ij.io.FileSaver(out).saveAsTiff(target.getPath())) {
        IJ.error("Send to Versarite Lab", "The image could not be saved:\n" + target.getPath());
        return;
    }

    try {
        var cmd = new java.util.ArrayList();   // (a Java list: any JS engine)
        cmd.add(exe);
        cmd.add(target.getPath());
        var pb = new java.lang.ProcessBuilder(cmd);
        pb.directory(new File(exe).getParentFile());
        pb.start();
        IJ.showStatus("Sent to Versarite Lab: " + target.getName());
    } catch (e) {
        IJ.error("Send to Versarite Lab", "Versarite Image Lab could not be started:\n" + exe + "\n\n" + e);
    }
})();
