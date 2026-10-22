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
  preview. The image on screen keeps its time, changed by the step; the new time is shown ("the
  longest" at 60 s) and written to the ini at once.
  - **Down to 0 = paused:** shorter goes all the way to 0 ms, whatever the step; there the show
    pauses (it is not ended; the info line says "paused", the image gets its full version).
    Longer again goes on: the slide show from the image shown, the dir preview with the folder's
    next image.
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
- **Side by side on two screens** (user): with `[Window] SideBySideScreens=1` and a second screen,
  "Side by side with Total Commander" moves Total Commander to the other screen and leaves
  VersariteViewer as it is (fullscreen too); `=2` moves VersariteViewer to the other screen and
  leaves Total Commander. The windows keep their size (a maximised one is maximised there);
  nothing moves when they are on two screens already. Back: VersariteViewer returns to where it
  was. `0` (default) and one screen: the halves, as before. Also on the settings screen.
- **The "Mouse & keys" page** (user): the command boxes grow with the display scaling (they
  were 250 pixels at any scaling, so long commands were cut off at 125 / 150 %); an open list is
  as wide as its longest command; resting the mouse on a box shows its command in full, and on a
  button or key name the name in full.
- **A zone can browse in random order** (user): "Browsing from this zone" offers **random**
  besides by date / by name; "unchanged" (before: "any order") leaves the order as it is. In a
  profile file: `Order=Random`.
- **The info line in a small window**: what doesn't fit goes on a second (third …) line,
  broken between its parts, instead of being cut off at the right edge. **Messages** ("Slide show:
  on", "Sent to Fiji", "Saved …") have a line of their own above it, so they are seen at once;
  before, they came last and were often cut off. A message also shows when no image is open.

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
| `[Window]` | `SideBySideScreens` | 0 |
| `[Magnifier]` | `AimRestMs` | 500 |

New commands for the mouse profile: `SlideShow`, `DirPreview`, `SlideShowMode`,
`DirPreviewLonger`, `DirPreviewShorter`.
