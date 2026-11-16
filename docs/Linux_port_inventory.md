---
title: "VersariteViewer on Linux: what is Windows-only"
subtitle: "Step 1 of the Linux port (Day 36, 2026-11-05)"
---

# Target

| | |
|---|---|
| System | Ubuntu 24.04 as installed, GNOME on **Wayland** |
| Widget set | **GTK2**, Lazarus 4.8's default on Linux: no extra libraries; it runs through XWayland |
| File manager | Double Commander (GTK2 build), with a small query patch (step 4) |
| Rule | one source tree; each Windows part gets an `{$IFDEF WINDOWS}` / `{$ELSE}` branch in its own unit; the Windows build stays unchanged |

**Why GTK2 under Wayland:** a GTK2 program is an X11 program run by XWayland. It may place its
own window, and OpenGL works through GLX. Native Wayland (Qt5 / Qt6) forbids a program to place
its window at all, which is what side by side needs. The patched Double Commander runs the same
way.

**What Wayland takes away in any case:**

- no global hotkey, so no Ctrl+Alt+Shift+Q emergency exit (the 4 s exit deadline stays);
- no reading or moving another program's window, so Double Commander is reached only through the
  patch, never through its window;
- "bring to front" from a second instance may only make the window flash in the task bar.

# The Windows-only parts, unit by unit

About 30 units name the `Windows` unit; most only for small types. Real Windows work is done in
these:

| Unit | Windows use | On Linux | Effort |
|---|---|---|---|
| uTCFollow | WM_COPYDATA and WM_USER+50 to Total Commander, message-only window | stays Windows-only; a new **uDCFollow** asks the patched Double Commander (step 2: one interface for both) | large (new unit + patch) |
| uTotalCommander | FindWindow, ShellExecute, SetWindowPos (side by side) | **uDoubleCommander**: start `doublecmd` with a path; side by side: VV places itself, Double Commander is asked to place itself through the patch | medium |
| uSingleInstance | mutex, shared memory, WM_COPYDATA | Free Pascal's SimpleIPC (what Double Commander uses for the same job) | medium |
| uWatchdog | RegisterHotKey, TerminateProcess | exit deadline only, ended with `fpKill(GetProcessID, SIGKILL)`; no hotkey | small |
| uWicDecoder | Windows' codecs (WIC, COM) | not available. `WicAvailable = False`; uMediaLoader already falls back to the own JPEG / TIFF / GIF readers and BGRABitmap. Optional: libjpeg-turbo, loaded at run time (BSD-style licence, in every Ubuntu) for fast JPEG; Double Commander does the same (`uturbojpeg`) | small (fallback); medium (turbo) |
| uMemoryGuard, uImageCache | GlobalMemoryStatusEx | `sysinfo` (total and free RAM) | small |
| uJobScheduler | CancelSynchronousIo (stuck reads) | not available; a stuck worker is replaced as now, its read is not cancelled | small |
| uGLRenderer | wglGetProcAddress | `glXGetProcAddress` (OpenGL 3 functions: glGenerateMipmap, buffers, shaders) | small |
| uClipboardImage, uMView (copy) | CF_DIB on the clipboard | the LCL clipboard as PNG (`Clipboard.Assign`), which Linux programs expect | small |
| uFileMover | MoveFileExW | `fpRename`; across file systems copy + delete (the code path already exists) | small |
| uSafeFile | MoveFileExW (write-through), FlushFileBuffers | `fpFSync`, then `fpRename` (atomic on Linux) | small |
| uStopwatch | QueryPerformanceCounter | `clock_gettime(CLOCK_MONOTONIC)` | small |
| uMainForm | GetKeyState(VK_ESCAPE), window placement, fullscreen | LCL's GetKeyState works on GTK2; fullscreen and placement to be checked under XWayland | check |
| uMView | GetKeyState for the mouse buttons (aiming loupe) | same as above | check |
| uMouseEngine, uMediaView | X1 / X2 buttons, tilt wheel | GTK2 gives mbExtra1 / 2 and the horizontal wheel; to be checked (can be simulated here with xdotool) | check |
| uConfig, uEdition | settings next to the exe | the same, or `~/.config/VersariteViewer` if the program folder is not writable (an installed program) | small |

Not Windows-specific: navigation, scanner, scheduler, cache, own decoders, renderers' logic,
panels, mouse profile, STL, GIF joining. The test programs are plain Pascal and should run on
Linux unchanged.

# Status (Day 36)

Step 2 done (uFileManager). Step 3 done except the file manager itself: VersariteViewer builds
for Linux (GTK2) and runs; Linux branches made in uGLRenderer, uMemoryGuard, uImageCache,
uStopwatch, uWatchdog, uSingleInstance, uClipboardImage, uMView (free space) and uMainForm
(fullscreen). The side buttons and the tilt wheel arrive under GTK2. All tests pass natively on
Linux. Left: Double Commander (uDCFollow / the patch), case-sensitive path comparisons,
localised XDG folders, a test on the user's Ubuntu with a real GPU and Wayland.

# Order of work

1. **This list**, with your yes to GTK2.
2. **One file manager interface** (current folder, file under cursor, other panel, change folder,
   start side by side, place window). Today's Total Commander code becomes its first
   implementation. Refactoring on Windows only; the tests show nothing changed.
3. **The small ones** from the table: each unit gets its Linux branch. Built here with Lazarus /
   GTK2, the tests run, screenshots under a virtual X display.
4. **The Double Commander patch**: discussed with its developers first, then built here, tested
   with VV, on Windows too if it builds there.
5. **Your Ubuntu**: the same build there, real mouse, real Wayland session.
