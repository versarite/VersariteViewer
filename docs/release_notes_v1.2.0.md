# VersariteViewer 1.2

The slide show, and the next round of testers' reports (day 31, 2026-10-22).

## The slide show

- **Slide show** (right-click menu "Slide show  (this folder; Esc ends it)", ticked while it runs,
  or the new command **SlideShow**): the images of the current folder one after another, round and
  round, in the viewer's order (name / date / random). Each stays for `[Sort] DirPreviewDelayMs`
  (default 1000 ms), counted from when it is on screen, so a slow image gets its full time. The
  info line shows "slide show" and the seconds per image.
  - A step with the wheel (or a key) shows the next image at once; the show goes on from there.
  - **Esc** ends it first, before panels and modes; so do the menu entry and the command.
  - It waits while an unsaved image (crop, paste, filtered copy) or edit mode is on, and gives way
    to the Total Commander dir preview while that plays a folder.
- **The speed, live:** the new commands **DirPreviewLonger** and **DirPreviewShorter** (on a key
  or mouse button, "Mouse & keys" page) make each image stay longer or shorter by
  `[Sort] DirPreviewStepMs` (default 100 ms, 10 … 10000), in the slide show and in the dir
  preview. The image on screen keeps its time, changed by the step; the info line shows the new
  time ("the shortest" at 200 ms, "the longest" at 60 s) and it is written to the ini at once.
- **The Total Commander dir preview as a slide show:** `[Sort] TCSlideShowMode=1` (or the new
  command **SlideShowMode**) keeps the folder under Total Commander's cursor playing also while
  VersariteViewer has the focus, so the keys and buttons above work on it. `0` (default): it waits
  while VersariteViewer has the focus, as in 1.1. Either way the dir preview stays switched on;
  back in Total Commander it goes on with the folder under the cursor.
- The new command **DirPreview** switches the Total Commander dir preview on and off, like its
  menu entry.

## From the testers' reports

- **The X button sends VersariteViewer to the taskbar** instead of ending it (it was closed by
  accident); so do Alt+F4 and the taskbar's "Close window". Exit in the right-click menu, the mouse
  profile's Exit and the settings screen's Exit still end it. `[Window] CloseButtonMinimizes=0`
  brings back the old X.
- **An unsaved image survives a stray turn of the wheel:** a crop, a pasted image or a copy with
  the filters applied is not left by the first step to another image. The info line says "kept";
  a quick spin of several notches stays held; the wheel (or key) again after a short pause goes on.
  `[Navigation] GuardUnsavedCopy=0` switches it off.
- **Ctrl+Z** is Undo, like the menu's first entry (the last copy / move / delete). Fixed keys now:
  Esc, the arrows, Ctrl+V, Ctrl+C, Ctrl+Z.
- **Rapid Sorting folders of your own:** `[Sort] RapidFolder1` … `RapidFolder0`, one per key. A
  full path (`D:\Sorted\Good`) is used as it is; a name is a folder in `DefaultImageFolder`; empty
  = `Selection<n>` as before. Missing folders are made when Rapid Sorting is switched on, and the
  panel shows each folder's own name.
- **A double-click on the title bar** (in a window) goes straight to the settings screen, like Esc
  (on the settings screen it maximizes as usual).
- `[Magnifier] AimRestMs` (default 500, 100 … 3000): how long the mouse must rest in edit mode until
  the aiming loupe shows.

## Settings added

All keys are written to `VersariteViewer.ini` at the first start and explained on the settings
screen (the mouse over a key):

| Section | Key | Default |
|---|---|---|
| `[Sort]` | `DirPreviewStepMs` | 100 |
| `[Sort]` | `TCSlideShowMode` | 0 |
| `[Sort]` | `RapidFolder1` … `RapidFolder0` | empty |
| `[Navigation]` | `GuardUnsavedCopy` | 1 |
| `[Window]` | `CloseButtonMinimizes` | 1 |
| `[Magnifier]` | `AimRestMs` | 500 |

New commands for the mouse profile: `SlideShow`, `DirPreview`, `SlideShowMode`,
`DirPreviewLonger`, `DirPreviewShorter`.
