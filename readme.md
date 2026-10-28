# VersariteViewer 1.3
*formerly MView*
## Written with support from Claude/Opus5.5 and ChatGPT

A *very* fast native stand-alone Windows image viewer, driven by the mouse. Keyboard key assignments are supported. No external libraries needed. 
Made for the microscope bench, for browsing whole experiment folders, and not too bad at any other kind of image collection. Designed primarily
to symbiotically work with TotalCommander, but handles files from any other file manager. 
By [Versarite](https://github.com/versarite). Copyright © 2026 DL1BWA/AC1WW. Free software under the GNU GPL v3.
This project is educational. It should not only produce useful software, but illustrate in detail how use agent-based coding on a simple subject to get from an idea to a satisfactory result. Claude and - in the early design phase - ChatGPT helped me greatly to unlock the capabilities of out-of-the-box Lazarus/FPC. 

**Status: release 1.3 (2026-10-27).** 
A small number of new features has been added following feedback - and 3D models (STL) with sections (see [What 1.3 brings](#what-13-brings)). The development of VersariteViewer stops at 1.3 for now.
I concentrate in the future on the Viewer Lab Version, where Versarite is envisioned to become a bridge beween Totalcmd and Fiji/ImageJ.
   
1.2 adds a **slide show** - of the folder on screen, or of
the folders Total Commander's cursor passes - with its speed changed live from a key or mouse
button, and answers the next testers' reports: the X button no longer ends the program by
accident (note: it is also no longer possible to kill the program from the taskbar, only the program-internal exits close the application for good),
an unsaved crop survives a stray turn of the wheel, Ctrl+Z, Rapid Sorting folders of
your own (see [What 1.2 brings](#what-12-brings)). 1.1 brought sort orders, several folder lists,
Rapid Sorting, single keys, a scan bar for long series, many more image formats, ZIP / CBZ
archives, the Total Commander dir preview and lossless JPEG rotation (see
[What 1.1 brings](#what-11-brings)); with 1.1 the program got its new name, VersariteViewer, and
the settings of an earlier version are taken over.
Microscopy-specific work continues in a separate **microscopy edition**, Versarite Image Lab
(see [What comes next](#what-comes-next-the-microscopy-edition)).

![VersariteViewer 1.1 welcome screen: a map of the window over a confocal image - the filter panel at the left edge, the sort panel at the right edge, the four mouse zones (Edit, Browse by name, Browse by date, Inspect), the icon preview and the info line, with the mouse controls below](docs/VersariteViewer_welcome.png)

> **Dedicated to Hamana** - written by Makito Miyano (last version 1.48, 2006),
> the viewer that showed how browsing images should feel:
> **fast first, mouse first, never in the way.**
> Hamana drew its images on the graphics card when few viewers did, read the next image
> before you asked for it, and let you drive *everything* with the mouse. Its development stopped in
> 2006 and its source was never published, so its bugs could never be fixed. VersariteViewer carries its
> ideas forward in code anyone can read, fix and extend.
> See [From Hamana to VersariteViewer](docs/From_Hamana_to_VersariteViewer.md).

## What 1.3 brings

3D models, combining GIFs, and polishing from daily use (days 32 to 34):

- **3D models (.stl)** are shown like images: binary and ASCII STL, drawn live by the graphics
  card (OpenGL: turning, tilting and every slider at once, as fluid as a dedicated STL viewer,
  sharp at any zoom; in software where there is no suitable OpenGL) - a light model on a dark
  background, the build plate as a grid, the axes, the triangles' edges. The info line gives the
  number of triangles and the size. A **drag with the left button turns and tilts the model**;
  the **rotate mode turns it** (wheel; R a quarter turn), zoom zooms. While a model is shown the
  **filter panel** (left) has its controls below Auto / Reset all - boxes and sliders, no buttons:
  **Section** (cut by a plane, the cut face shown closed), **Flip side**, **Plane X / Y** (tilt),
  **Plane position**, **Elevation**, **Smoothing**, **Grid**, **Edges**. Copy and Save image take
  the model as it is turned and cut.
- **Combine GIFs:** side by side with Total Commander, the menu entry joins the animated GIFs under
  its left and right cursor into `<left>_<right>.gif` in the folder shown (left first, a short
  pause, then right). Two ways: **Original sizes** (frames copied unchanged) or **Scaled to
  largest GIF** (the smaller one scaled to fit the larger, its shape kept; new pixels, so some
  resolution is lost).
- **Dynamic folder lists:** a sort list can reorder itself - each copy or move into a folder moves
  it up one place (once the mouse has left the panel); a double-click on the list's title switches
  it, a red star marks it. **Pin to top** (first line of a folder's menu) keeps folders on top,
  with a red frame.
- **Semi-automatic sorting:** in a slide show or the Total Commander dir preview a copy or move
  restarts the time, and the show waits while the mouse is on the sort panel; the magnifier and
  the zoom / rotate mode end after a copy or move.
- **No duplicates:** an identical file (same name or its `_1` copies, same size, same bytes) is not
  copied again; a move puts it into the deleted-files folder as `dup1_<name>` (undoable).
- **Open file ...** in the right-click menu (also the command **OpenFile** for a key or button):
  a file dialog in the folder shown; the file opens as from the command line.
- **Surer browsing:** a folder that isn't there any more (the last session's, say) opens the
  nearest folder above it instead of stopping at "Not found"; a folder step made while the folders
  are still being read ("scanning folders ...") is done as soon as they are known; climbing one
  folder up no longer waits for the image still being read; the **slide show overrides** the
  Total Commander dir preview (with both on, nothing played).
- Fixed: an empty folder opened while following Total Commander kept no subfolders after the
  following was switched off, so the folder swipes and "up" did nothing there.

The full list: [release notes 1.3](docs/release_notes_v1.3.0.md).

## What 1.2 brings

The slide show, and the next testers' reports (day 31):

- **Slide show** (right-click menu "Slide show", or the command **SlideShow** on a key or mouse
  button): the images of the current folder one after another, round and round, each for
  `[Sort] DirPreviewDelayMs` (default 1000 ms). The info line says "slide show" and the time. A
  step with the wheel shows the next image at once and the show goes on from there; **Esc** (or the
  command again) ends it. It waits while an unsaved image or edit mode is on.
- **The speed, live:** the commands **DirPreviewLonger / DirPreviewShorter** (on a key or button,
  "Mouse & keys" page) make each image stay longer or shorter by `[Sort] DirPreviewStepMs`
  (default 100 ms), in the slide show and in the Total Commander dir preview alike; the new time is
  written to the ini at once.
- **The Total Commander dir preview as a slide show** (`[Sort] TCSlideShowMode=1`, or the command
  **SlideShowMode**): the folder under Total Commander's cursor keeps playing also when
  VersariteViewer has the focus, so its keys and buttons work on it. With `0` (default) it waits
  while VersariteViewer has the focus, as in 1.1. Either way the dir preview stays on; back in
  Total Commander it goes on with the folder under the cursor. The command **DirPreview** switches
  the dir preview on and off, like the menu entry.
- **The window's X button sends VersariteViewer to the taskbar** instead of ending it (testers
  closed it by accident); so do Alt+F4 and the taskbar's "Close window". Exit in the right-click
  menu, the mouse profile's Exit and the settings screen's Exit still end it;
  `[Window] CloseButtonMinimizes=0` brings back the old X.
- **An unsaved image is not lost to the wheel:** a crop, a pasted image or a copy with the filters
  is not left by the first turn of the wheel (the info line says "kept"); the wheel again after a
  short pause goes on. `[Navigation] GuardUnsavedCopy=0` switches it off.
- **Ctrl+Z** is Undo (the last copy / move / delete), like the menu's first entry.
- **Rapid Sorting folders of your own:** `[Sort] RapidFolder1` … `RapidFolder0` give a key its own
  folder: a full path (`D:\Sorted\Good`) or a name inside `DefaultImageFolder`; empty =
  `Selection<n>` as before. The panel shows each folder's name.
- **A double-click on the title bar** (in a window) goes straight to the settings screen, like Esc.
- `[Magnifier] AimRestMs` (default 500): how long the mouse rests in edit mode until the aiming
  loupe shows.

Added after the first 1.2 builds (now part of 1.3):

- **Pause by going down to 0:** "each image shorter" now goes all the way down to 0 ms, whatever
  the step; at 0 the slide show or dir preview **pauses** (it is not ended; the info line says
  "paused"). "Each image longer" goes on: the slide show from the image shown, the dir preview
  with the folder's next image.
- **Messages are seen:** they have a line of their own above the info line (before, they came
  last and were often cut off), and an info line too long for the window goes on a second line,
  broken between its parts, instead of being cut off at the right edge.
- **Side by side on two screens:** `[Window] SideBySideScreens=1` moves Total Commander to the
  other screen and leaves VersariteViewer as it is (fullscreen too); `=2` moves VersariteViewer
  instead. The windows keep their size. Needs Windows' "Extend these displays" (Win+P › Extend);
  `0` (default) or one screen: the halves, as before.
- **The "Mouse & keys" page:** the command boxes grow with the display scaling (long commands
  were cut off at 125 / 150 %), an open list is as wide as its longest command, and resting the
  mouse on a box (or on a button or key name) shows it in full.
- **A zone can browse in random order:** "Browsing from this zone" offers **random** besides by
  date and by name; "unchanged" (before: "any order") leaves the order as it is.

The full list: [release notes 1.2](docs/release_notes_v1.2.0.md).

## What 1.1 brings

Asked for by the first testers, built on days 27 to 30:

- **A new name:** VersariteViewer (the microscopy edition: Versarite Image Lab). The program is
  `VersariteViewer.exe`, its settings `VersariteViewer.ini`; an `MView.ini` (and the deleted-files
  folder) from before is taken over at the first start. Total Commander buttons that start
  `MView.exe` need the new name.
- **ZIP and CBZ archives** open like folders, nothing is unpacked to the disk: the pictures inside
  are listed in the side panel with their thumbnails (natural order: page2 before page10), the
  wheel walks through them, a click opens one. `[Navigation] Archives=0` switches it off.
- **Total Commander dir preview** (right-click menu): Follow switches to "folder and cursor"; a
  folder under Total Commander's cursor plays its first images in a loop, in the viewer's order
  (by name / date / random), and the info line shows how many images and subfolders it has.
  `[Sort] DirPreviewFiles` (default 3, 0 = all) and `DirPreviewDelayMs` (default 1000).
- **Rotate losslessly** (right-click menu, JPEG): 90° right / left, 180°, mirror. Only the EXIF
  orientation tag is changed, the pixels are not touched; the file keeps its date.
- **Copy / move entries between folder lists** (a folder's ⋯ menu, "Copy / move entry"): copy or
  cut an entry, then paste it after the highlighted line on another list.
- **The settings can no longer be lost:** they are written in one step and backed up at each start;
  a damaged file is restored from the backup (a tester's report).
- **Panel transparency:** `[View] PanelOpacity` (20 … 100 %, default 80), the same for all panels.

- **Order of the images** in the right-click menu: by date, by name (A–Z / Z–A), or **random**
  (choose it again for a new shuffle).
- **The sort panel, reworked:**
  - "+ add folder" on top; `[Sort] PanelLines` lays the panel out for a number of rows (larger
    text; the wheel scrolls the rest).
  - **Several folder lists:** the ◀ ▶ arrows in the panel's top line go through them; after the last
    one comes a new, empty list (an arrow turns red when that is where it leads). Each list is a
    `[DirList1]`, `[DirList2]` … section of the ini.
  - A folder's ⋯ menu is a window of its own now, left of the panel so the folders stay in sight. It
    stays open while you move a folder: **Move to top**, and Move up / down repeat while held.
    New in it: **Rename** (the name in the list only), **Make folder** / **Make subfolder**
    (`<name>_001` …, added to the list), and the icon menu starts with "Choose icon file …" (bold).
- **Rapid Sorting** (right-click menu): ten fixed folders `Selection1` … `Selection9`,
  `Selection0` in your Pictures folder (`[Sort] DefaultImageFolder`), in ten colours; **the keys
  1 … 9, 0 move the image there** (with undo). Switched off, the panel shows your list again.
- **Single keys** on the "Mouse & keys" page: letters, digits, F-keys, the number pad, punctuation
  … each can run up to three commands; the page names the keys as your keyboard layout does
  ("Ü", "Num 5"). A digit without its own entry is a Rapid Sorting key.
- **The scan bar** (after Hamana's seek bar): rest the mouse at the top edge for half a second (or
  use the command "Toggle preview"). A bar across the middle of the top stands for the folder's
  images from first to last; the mouse over it shows the image at that place, so a time lapse or
  a long series is scanned in seconds. The wheel steps one image; a click opens it.
- **The bottom edge** (with the zones off): resting there for a second switches the wheel between
  next / previous image and zoom at the mouse.
- **More image formats** through Windows' own codecs: **WebP, HEIC / HEIF, AVIF, JPEG XL, JPEG XR,
  DDS, icons** (`.ico`: the largest picture in the file) and **camera raw** files (DNG, CR2, CR3,
  NEF, ARW, ORF, RW2, RAF, PEF …). Some need a free codec from the Microsoft Store (HEIF Image
  Extensions, AV1 Video Extension, JPEG XL Image Extension, Raw Image Extension); without it VersariteViewer
  says which one.
- **A drive almost full:** a red notice when a drive VersariteViewer works with has less than 100 MB free
  (`[View] DiskWarning`).
- Also: the edit-mode frame stays upright on a turned image; Esc closes the magnifier, the filter
  panel, edit mode and the sort panel in that order; "Save image as …" can write TIFF; Auto
  re-levels a selection when the mouse button is released.

The full list: [release notes 1.1](docs/release_notes_v1.1.0.md).

## What 1.0 brought

### Fast, from the first image to the last

- **Fullscreen browsing through whole folder trees.** A background thread scans the folders; next /
  previous image and folder are instant, sorted by date or by name (natural order: Image2 before
  Image10), with wrap-around and no dialogs.
- **Never waits.** Several decode threads read the neighbours ahead; the image on screen always reads
  the disk first. Quick views (EXIF thumbnails, reduced decoding) come before the full image; holding
  the wheel switches to a skim mode that never builds up lag.
- **Drawn on the GPU** (OpenGL): tiled textures, mipmaps, pixel-exact 1:1, free rotation. A CPU
  renderer takes over when OpenGL can't be used.
- **Large images:** own fast TIFF readers (uncompressed and parallel LZW), PNG / BMP / TIFF in bands
  through Windows WIC (21600 × 21600 NASA images), JPEG through WIC with an own fallback decoder,
  GIF with animation (own decoder). Images that would not fit in memory are refused, not crashed on.
- **Fit ↔ 100 %, zoom, rotate:** 100 % shows centred in the window; the zoom mode zooms at the mouse.

### The mouse language

- **Four screen zones**, each with its own name, browsing order and commands; right-drag gestures,
  tilt wheel, side buttons. Everything lives in a readable profile (`Default.mouse`), edited on the
  "Mouse & keys" page with a "Try it here" area. The keyboard is optional.
- **A Hamana profile** (`mouse\Hamana.mouse`) gives VersariteViewer Hamana's mouse.

### Sorting after inspection

- **The sort panel** slides out at the right edge: double-click left copies, double-click right moves
  the image into a button's folder. The copy or move runs on a thread of its own; the button flashes
  in its colour when the file is really there.
- **Nothing is ever lost:** never overwrites, never really deletes (a deleted-files folder), undo up to
  50 steps, every action in `sorting.log`.
- **Icons on the buttons** from `.ico` / `.png` files, or made from the image itself ("Make icon from
  this image"). Resting the mouse on a button shows its icon large at the top of the screen.
- **Into a folder:** swipe left or right over a button, or click it with the wheel.
- **Folders from Total Commander or Explorer:** drop them on the panel to make buttons.

### Looking closer

- **Display filters** at the left edge: black / white point, brightness, contrast, gamma, saturation,
  hue, invert, mirror left / right. Applied by a shader on the graphics card (one frame even on
  100-megapixel images); the image file is never changed.
- **Auto** sets the black and white point like Fiji's Auto contrast, from a live histogram (or from a
  selection); double-click makes it work on every image, `[Filters] AutoFilter=1` from the start.
- **Lock filters** keeps them for the next images; **Apply filters (and rotation) to a copy** makes
  a new image with them in its pixels, ready to save or sort.
- **The magnifier:** a round lens over the image, 1.25 to 32 × from the full image, with optional
  sharpening, lockable in place.
- **Resize to the size shown:** the info line shows the size on screen (`52 % = 1997 x 1331`); one
  menu entry makes a copy of exactly that size.

### A viewer for Total Commander

- **Follows Total Commander:** its folder, or even the file under its cursor. A **TC** label shows the
  state (see-through, light blue, amber) and switches it with a click.
- **Only one VersariteViewer:** opening images from Total Commander one after another goes to the running
  VersariteViewer, which comes to the front.
- **Side by side:** VersariteViewer on the left half of the screen, Total Commander on the right
  (with two screens, optionally one on each: `[Window] SideBySideScreens`).
- See [Working with Total Commander](#working-with-total-commander) below.

### Everyday details

- **Edit mode:** select an area, crop it; save an image, a crop or a picture pasted from the
  clipboard (Ctrl+V) as PNG.
- **The info line is yours:** `[InfoLine]` in VersariteViewer.ini lists its parts (file name, size, folder,
  position, videos, sorting, zoom, state, animation, filters, messages); switch each on or off,
  move the lines to change the order, choose the font.
- **Videos are counted, not shown:** the info line says "3 videos" when a folder has them, and a
  folder with only videos says so instead of looking empty.
- **Drive roots** (C:\, a network share) open without their subfolders unless you want them
  (`[Navigation] RecurseFromDriveRoot`), so a whole drive is never scanned by accident.
- **Safe:** emergency exit (Ctrl+Alt+Shift+Q), a shutdown deadline, decode threads stuck on a failing
  disk are replaced, the window never waits for a slow drive.
- **Documented:** every unit explains itself (Purpose, Owns, Responsibilities, Does NOT, Threads),
  architecture pictures, a developer specification and a daily development log.

The full list for this release: [release notes 1.0](docs/release_notes_v1.0.0.md).

## What comes next: the microscopy edition

The microscopy edition, **Versarite Image Lab**, is in development (0.1: Leica .lif files and their
stacks, metadata, calibration, measuring with real units, scale kept in crops and saved files).
With 1.0 the general viewer was finished. Everything specific to microscopy, and to image editing,
goes into a **second program, the microscopy edition**, so VersariteViewer stays the lean, fast viewer it is.
It is not a fork: both programs are built from the same source tree, so every fix to the renderer,
the decoders or the navigation reaches both with one rebuild. The microscopy edition has its own
project file, and its units live in their own folder (`source\microscopy\`).

Planned for it:

- **Instrument metadata:** Leica (.lif / .lei and LAS X exports with their MetaData), Nikon, and the
  usual TIFF / OME / ImageJ descriptions, shown in a panel.
- **Calibration** per objective (by numbers, or by measuring a stage micrometer or a known object),
  so camera images without metadata get a real scale too.
- **Measuring:** a straight line that follows the mouse after the first click and shows its length
  after the second; no dragging needed.
- **Scale bar** with round lengths, written into a saved copy for figures.
- **A provenance note** in saved PNGs listing what was done to the image.
- **Movies and camera recordings** (Prosilica, Thorlabs, Imaging Source, Point Grey: raw AVI, TIFF
  stacks, MP4 / MKV through FFmpeg's libraries) as frame stacks with time stamps.
- **Editing**, with the keyboard allowed: Photoshop .8bf filters (64-bit), and Fiji / ImageJ plugins
  and macros run by Fiji itself.

## Using it

- The very first start shows `VersariteViewer_welcome.png`, a map of the screen (keep it next to
  `VersariteViewer.exe`; it is in `docs\`).
- Start `VersariteViewer.exe` with a file or folder, or drop one on the window. Without one,
  `[Startup] Mode` decides: 1 (default) the viewer fullscreen in the last folder, 2 the same side
  by side with Total Commander, 0 the settings screen.
- The mouse profile `Default.mouse` says what each button, wheel, gesture and zone does.
  `mouse\Hamana.mouse` gives VersariteViewer Hamana's mouse: copy it next to `VersariteViewer.ini` first,
  then set `Profile=Hamana.mouse` under `[Mouse]` (`Profile=Default.mouse` goes back).
- Sorting: rest the mouse at the right edge (or right-click menu, "Sort panel"). Double-click
  left copies, double-click right moves the image into a button's folder; drop folders from
  Total Commander or Explorer onto the panel to add buttons. Nothing is ever overwritten or
  really deleted ("Delete current image" moves the file to a deleted-files folder).
- Filters: rest the mouse at the left edge (or right-click menu, "Filters"). Black / white point,
  brightness, contrast, gamma, saturation, hue, invert, mirror; **Auto** sets the black and white
  point like Fiji (click: once, double-click: for every image). Display only; "Apply filters to a
  copy" makes a new image with them (and with the rotation, if the view is turned).
- Magnifier: right-click menu, "Magnifier (lens)". Left drag sideways = magnification, up / down =
  size, wheel = sharpening, wheel click = lock the lens.
- The info line: `[InfoLine]` in the settings screen (VersariteViewer.ini). The help text on the right says
  what each line does.
- Several folder lists: the ◀ ▶ arrows in the sort panel's top line. Rapid Sorting: right-click
  menu, then the keys 1 … 0.
- The scan bar: rest the mouse at the top edge; move along the bar to see the folder's images.
- Keys: "Mouse & keys" page, "Keys", "Add a key".
- Esc closes the scan bar, the magnifier, the filter panel, edit mode and the sort panel, in that
  order, then goes to the settings screen; Esc there exits.
- If VersariteViewer ever hangs: Ctrl+Alt+Shift+Q.

## Working with Total Commander

VersariteViewer doesn't try to be a file manager: [Total Commander](https://www.ghisler.com) is the
tree manager, VersariteViewer is its viewer. They work together in five ways:

- **Dir preview** (right-click menu, "Total Commander dir preview"): with the cursor on a folder in
  Total Commander, its first images play in a loop (`[Sort] DirPreviewFiles`, `DirPreviewDelayMs`),
  with its image and subfolder count in the info line; on a file, the file is shown as usual.
- **Opening from Total Commander.** Make VersariteViewer the program for image files (Enter or a double-click
  opens it). With `[Startup] OnlyOneInstance=1` (the default) there is only ever one VersariteViewer: an image
  opened while VersariteViewer runs goes to the running VersariteViewer, which comes to the front.
- **Following Total Commander** (right-click menu "Follow Total Commander", or click the **TC**
  label in the bottom right corner to cycle):
  - *Its folder:* when Total Commander's active panel changes folder, VersariteViewer shows that folder.
  - *Its folder and the image under its cursor:* arrow through a folder in Total Commander and
    VersariteViewer shows each image as the cursor reaches it, VersariteViewer becomes Total Commander's viewer.
  - The **TC** label shows the state: see-through = not following (off, or Total Commander isn't
    running), light blue = its folder, amber = folder and cursor.
  - While VersariteViewer follows, Total Commander decides the folder: folders are opened without their
    subfolders, the image steps wrap around inside the folder, and a folder step in VersariteViewer shows a
    short notice ("TC connection: directory change disabled!") instead.
  - Archives, FTP and plugin folders in Total Commander are ignored. VersariteViewer only reacts to changes
    in Total Commander, never pulls you back from your own browsing in VersariteViewer.
- **Side by side** (right-click menu, or the button on the settings screen): VersariteViewer on the left half
  of the screen, Total Commander on the right half, in the image's folder (from the settings
  screen: the last session's folder, else Documents). With a second screen ("Extend these
  displays"), `[Window] SideBySideScreens=1` puts Total Commander on the other screen and `=2`
  VersariteViewer, both keeping their size; the same entry again brings VersariteViewer back.
- **Sorting with folders from Total Commander:** drag folders from Total Commander onto the open
  sort panel to make them sort buttons.

How it works: Total Commander announces nothing, so VersariteViewer asks it a few times a second through its
documented window messages (`WM_USER+50`, see the Total Commander wiki) and its `WM_COPYDATA`
questions ("SP" = the active panel's path, "SN" = the name under the cursor). It costs nothing
noticeable and needs no plugin or setting in Total Commander. `[Sort] FollowTotalCommander=0/1/2`
keeps the choice; `[Sort] TotalCommander=` can name the program if VersariteViewer doesn't find it itself.
Tested with Total Commander 11.03 (64-bit).

## Building

- Lazarus 4.x with Free Pascal 3.2.2, Windows 64-bit.
- Lazarus packages: **BGRABitmapPack** (install through the Online Package Manager),
  **LazOpenGLContext** and **SynEdit** (both come with Lazarus).
- Open `VersariteViewer.lpi`, build. The program goes to `build\VersariteViewer.exe`.
- Tests: `test\build_test.bat` builds and runs TestNavigation, TestExif, TestMouse, TestSort,
  TestFilters, TestGif and TestExtensions.
- The new image formats (WebP, HEIC, AVIF, JPEG XL, camera raw …) are read by Windows' own codecs;
  some need a free extension from the Microsoft Store (HEIF Image Extensions, AV1 Video Extension,
  JPEG XL Image Extension, Raw Image Extension). VersariteViewer itself needs nothing extra.

## Documentation

- `specs\` — the developer specification
- `docs\architecture\` — how the units depend on each other and work together at run time (1.1)
- `docs\dayNNN.log` — the development log, one file per day
- `docs\Strategy_Phase_G.md` — the plan for sorting, metadata, magnifier and filters
- `docs\release_notes_*.md` — what each release brings (`release_notes_v1.0.0.md`, `release_notes_v1.0.1.md`,
  `release_notes_v1.1.0.md`, `release_notes_v1.2.0.md`, `release_notes_v1.3.0.md`)
- `docs\Hamana_Research.md`, `docs\Hamana_Commands.md` — what was learned from Hamana
- `docs\From_Hamana_to_VersariteViewer.md` — the homage: what VersariteViewer kept, what it changed, and why

## Principles

Fast first, mouse first, never in the way.
No frills, every feature must improve the workflow.
Every module should be easy to understand.
Every design decision should be documented.
The source code should teach as well as implement.

## License

VersariteViewer is free software: you can redistribute it and/or modify it under the terms of
the GNU General Public License, version 3 (see `LICENSE`).

It is built with the Free Pascal runtime and the Lazarus LCL (modified LGPL), BGRABitmap
(modified LGPL) and pasjpeg (Independent JPEG Group licence).

## What is not in this repository

- Hamana itself: its program, plug-ins, manual and screenshots belong to its author.
  VersariteViewer contains no Hamana code, formats, artwork or text.
- The microscopy edition (Versarite Image Lab, `source\microscopy\`, its project file and tests): in
  development, published when it is ready. The shared units it plugs into (uEdition, uExtensions,
  uContainers) are here; in VersariteViewer they serve the ZIP / CBZ archives.
- The author's own test images (microscopy data, photos, very large images). Only the test sets
  the tests need are included: `test\images\gif`, `test\images\exif` and `test\images\thumb`,
  all made for testing.
