# VersariteViewer 1.4

Released 2026-11-17, the final version of VersariteViewer (fixes only from here; new work goes into
Versarite Image Lab). The changes after the 1.3 release (2026-10-27): Double Commander as the file
manager, in both directions, on Windows and Linux; the Linux port; polishing from daily use
(days 36 to 40).

## Double Commander

Needs a Double Commander with the remote control addition:
[versarite/doublecmd › remote-control](https://github.com/versarite/doublecmd/tree/remote-control)
(Windows: a named pipe for the current user only; Linux: a socket in `$XDG_RUNTIME_DIR`).

- **The file manager layer** (day 36): everything VersariteViewer asks a file manager - is it
  running, its folder and the file under its cursor, its two panels, open a folder, place its
  window - goes through one interface (uFileManager), with Total Commander (Windows) and Double
  Commander (Windows, Linux) behind it. Notes, menu entries, the settings screen and the badge
  (**TC** / **DC**) name the file manager in use.
- **Following Double Commander:** its folder, or folder and the image under its cursor; one
  question per poll (`GET FOLLOW`, about 3 ms).
- **Double Commander follows VersariteViewer** in "folder and cursor" mode: the image shown goes
  under its cursor once it has stayed `[FileManager] CursorSyncMs` (default 300 ms; skimming
  doesn't drag the cursor along); after a move or delete in VersariteViewer the cursor goes to the
  next image; VersariteViewer's order (name / date, up / down) is set in Double Commander too.
- **Sort buttons and Double Commander:** a click on a sort button shows its folder in Double
  Commander (`[FileManager] ShowInFileManager`: 1 = its other panel (default), 2 = its active panel,
  0 = off; only while following); new sort folders are made through Double Commander
  (`cm_MakeDir path=`), so its panels show them at once.
- **Side by side:** VersariteViewer places itself on the left half and asks Double Commander to take
  the right half (on Linux under Wayland only a program can place its own window). A **right
  double-click on the badge** puts both back to the halves; a single right click opens the menu
  once the double-click time is over.
- **Commands from Double Commander's toolbar and hotkeys** (fetched about twice a second):
  - `cm_ViewerCommand cmd=<name>`: any action of the "Mouse & keys" page by its name.
    VersariteViewer sends Double Commander the list of its commands once per connection, so the
    toolbar editor offers them by caption.
  - `cm_ViewerFollowModeOn` (none / `mode=1` / `mode=2`), `cm_ViewerFollowModeOff`.
  - `cm_SendTree`: the first-level subfolders of Double Commander's folder are added to the current
    sort list.
  - `cm_RemoteSendFolderToInactive`: VersariteViewer's folder in Double Commander's other panel.
  - `cm_RemoteCreateSortFromSubdirs`: a new sort list from the subfolders of the folder under the cursor (`1`: with the folder
    itself; no parameter = `0`).
  - The list: [Driving VersariteViewer from Double Commander](DoubleCommander_Viewer_Commands.md).
- `[FileManager] DCThumbnails`: Double Commander's thumbnail view switched on once when a freshly
  started one connects (1 = its other panel, 2 = its active panel).
- Only the configured program is connected to (`[FileManager] DoubleCommander=`); the pairing answer
  is waited for without blocking, each question at most 300 ms; the token is kept in
  `VersariteViewer.dctoken` next to the ini.
- No file manager traffic while the sort panel is in use.

## Linux

- VersariteViewer builds and runs on Linux (Lazarus 4.8, GTK2; Ubuntu 24.04, also under Wayland
  through XWayland), from the same source: OpenGL through GLX (mipmaps, the filter shader), memory
  from `sysinfo`, the monotonic clock, single instance through a Unix socket (only the same user's
  programs), the clipboard as PNG, free disk space by `statfs`, fullscreen through the window
  manager. The side buttons and the tilt wheel arrive under GTK2.
- Not on Linux: Total Commander, Windows' image codecs (WIC: WebP, HEIC, AVIF, JPEG XL, camera raw),
  the global emergency key Ctrl+Alt+Shift+Q (the exit deadline stays).
- All tests run natively on Linux. The Image Lab builds for Linux too.
- A ready-made build: `VersariteViewer-1.4-linux-x86_64.tar.gz` (with `install.sh`; settings stay
  next to the program, so it installs into `~/.local/opt/VersariteViewer`).

## A file manager only when chosen

- `[FileManager] DirManager`: 0 = none (the default: the file manager's menu entries and the badge
  are hidden), 1 = Double Commander, 2 = Total Commander. **An ini from 1.3 that worked with Total
  Commander needs `DirManager=2`.** Without a file manager, a file manager feature says how to
  choose one.
- The file manager's keys have a section of their own, `[FileManager]`, high up in the ini; an
  older ini's keys in `[Sort]` are read from there and moved at the next write. Renamed:
  `FollowTotalCommander` → `FollowDirManager`, `TCSlideShowMode` → `DirPreviewSlideShow` (the old
  names are still read).
- The ini is written in a fixed order, the same at every write.

## Fixed

- **The welcome picture showed no more at the very first start:** the check for another running
  instance read the settings first, and reading them makes a new ini when there is none, so the
  main form no longer saw a first start. Now that check reads only an ini that is there
  (`VersariteViewer.lpr`).

## Sorting and browsing

- **Dynamic folder lists:** a run of copies or moves into the same folder moves it up one place only
  once (before: once per file).
- **New commands** for keys, mouse buttons and Double Commander: `RestoreSideBySide`,
  `SendFolderToInactive`, `CreateSortFromSubdirs`, `CreateSortFromSubdirsWithFolder`, and
  `Diagnostics` (the diagnostics line above the info line: decoding, cache, GPU, paint).
- **Small images** (icons) open at `[View] SmallImageZoom` percent of the window's height; 0 = fill
  the window as before.
- A zone set to the context menu's order browses in the order last chosen from the context menu in
  that zone.
- **A drive with read errors** (a failing memory stick) is named in a message, and its images are
  not read ahead; a worker stuck on it is replaced.
- The sort panel ends above the file manager badge; a click on a sort button there no longer
  switches following on.

## Settings added

| Section | Key | Default |
|---|---|---|
| `[FileManager]` | `DirManager` | 0 |
| `[FileManager]` | `DoubleCommander` | (empty) |
| `[FileManager]` | `FollowDirManager` (was `FollowTotalCommander`) | 0 |
| `[FileManager]` | `ShowInFileManager` | 1 |
| `[FileManager]` | `DCThumbnails` | 0 |
| `[FileManager]` | `CursorSyncMs` | 300 |
| `[FileManager]` | `DirPreviewSlideShow` (was `TCSlideShowMode`) | 0 |
| `[View]` | `SmallImageZoom` | 33 |

`TotalCommander`, `DirPreviewFiles`, `DirPreviewDelayMs` and `DirPreviewStepMs` moved from `[Sort]`
to `[FileManager]`.
