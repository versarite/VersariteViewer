# VersariteViewer 1.1

*formerly MView.* The answer to the first testers' lists, built on days 27 to 30 (2026-10-19).

## A new name

MView is now **VersariteViewer**; its microscopy edition is **Versarite Image Lab**.

- The program is `VersariteViewer.exe`, its settings `VersariteViewer.ini`, its welcome picture
  `VersariteViewer_welcome.png`.
- At the first start an `MView.ini` next to the program is taken over (a notice says so); it is left
  as it was. The deleted-files folder `Documents\MView deleted files` is used on if it exists.
- Total Commander buttons, file associations or links that start `MView.exe` need the new name.
- The project is `VersariteViewer.lpi` / `VersariteViewer.lpr`; the units keep their names
  (`uMView`, `TMView` …).

## New in the second round (day 30)

- **ZIP and CBZ archives** are opened like folders, without unpacking anything to the disk: the
  pictures inside (JPEG, PNG, GIF, BMP, TIFF, TGA, PCX, sub-folders included) are listed in the side
  panel with their thumbnails, in natural order (page2 before page10), exactly as a .lif in the
  microscopy edition. The wheel walks through them, a click opens one. `[Navigation] Archives=0`
  switches it off. (RAR: planned for Versarite Image Lab; a CBZ as one continuous strip: 1.2.)
- **Total Commander dir preview** (right-click menu, "Total Commander dir preview"): Follow switches
  to "folder and cursor" (and back when the preview is switched off). The cursor on a file: shown as
  before. The cursor on a folder: its first images play in a loop, in the viewer's order (name / date /
  random), as quick views; the info line shows the folder's images and its subfolders (one level
  down). `[Sort] DirPreviewFiles=3` (0 = all) and `DirPreviewDelayMs=1000`; with all files and more
  than a second, the images are shown in full.
- **Rotate losslessly** (right-click menu, JPEG only): 90° right, 90° left, 180°, mirror left /
  right, mirror up / down. Only the EXIF orientation tag is written (added if the file has none), the
  pixels are not decoded or recompressed, and the file keeps its date.
- **Copy / move entries between folder lists:** a folder's ⋯ menu, "Copy / move entry" ▸ Copy
  entry, Cut entry, Paste entry. Paste goes after the highlighted line (on a list with nothing
  highlighted: on top). A cut entry is dimmed until it is pasted, and leaves its list then; Back
  cancels a cut. A folder already on the list, or a full list (64), is refused with a notice.
- **Panel transparency:** `[View] PanelOpacity` (20 … 100, default 80), for all panels alike.
- "Choose icon file …" in the icon menu is drawn bold and green, as often-used entries are.
- The "Add a key" list on the "Mouse & keys" page opens above its Add button (it was at the top of
  the page), and long lists fit on the screen.

## New

- **Order of the images** in the right-click menu: by date (newest / oldest first), by name
  (A–Z / Z–A), **random**. Random chosen again shuffles anew; the order is the same for every folder
  until then. `[Navigation] SortMode=Random`.
- **Several folder lists in the sort panel.** Two arrows (◀ ▶) in its top line, left of the pin; the
  title shows "Sort 2/3". After the last list comes a new, empty one, then round to the first; an
  arrow is red when it leads to the new, empty list. A list left empty is dropped. Each list is a
  section of the ini, `[DirList1]`, `[DirList2]` …; `[Sort] List` is the one shown. The folders of
  1.0 (in `[Sort]`) become list 1 by themselves.
- **The folder menu (⋯) is a window of its own**, left of the panel so the folders stay in sight. It
  stays open while a folder is moved: **Move to top**, Move up / down (they repeat while the button
  is held). New entries: **Rename** (the name in the list, not the folder), **Make folder** /
  **Make subfolder** (`<name>_001`, `<name>_002` …, made and added below). Sub-menus (colour, icon,
  recent folders) open in place; "Choose icon file …" is now at the top of the icon menu.
- **Rapid Sorting** (right-click menu): the panel opens, pinned, with ten fixed folders
  `Selection1` … `Selection9`, `Selection0` in `[Sort] DefaultImageFolder` (filled in with your
  Pictures folder; made when missing), numbered 1 … 0 in ten colours. **The keys 1 … 9, 0**, top row or
  number pad, **move the image** into that folder (undo as usual). Switched off: the list and the pin
  from before come back.
- **Single keys** on the "Mouse & keys" page ("Keys"): only the keys you set are listed, each with up
  to three commands and an × to remove it; "Add a key" offers the free keys (pressing a key over the
  list picks it). Letters, digits, F1–F12, the number pad, Space, Enter, Tab, Backspace, Insert /
  Delete / Home / End / Page up / down, Pause, the menu key and the punctuation keys; named as the
  installed keyboard layout names them. No combinations; Esc, the arrows, Ctrl+V and Ctrl+C stay
  fixed. A digit without its own entry is a Rapid Sorting key. New commands: Rapid sorting on /
  off, Rapid key, Toggle preview.
- **The scan bar** (after Hamana's seek bar): a thick, see-through bar at the top, in the middle, half
  the window wide, standing for the folder's images from first to last. Opens when the mouse rests
  at the top edge (0.5 s), by the command Toggle preview or the right-click menu. Opened at the edge
  it closes 1 s after the mouse has left it; opened from the menu (or by the command) it stays until
  switched off there (the entry is ticked while it stays). Esc closes it either way. The mouse over
  it shows the image at that place under the bar, with its number and name (a long name scrolls); one not read yet shows "754 / 1005" on black. Only
  that image is decoded. The wheel steps one image, a click opens it. Its outline is in the info
  line's colour.
- **The bottom edge** (with the zones off): resting there for a second switches zoom mode, as X1
  does (the wheel zooms at the mouse instead of going to the next image).
- **New image formats** through Windows' codecs: WebP, HEIC / HEIF, AVIF, JPEG XL, JPEG XR (.jxr,
  .wdp), DDS, icons (`.ico`: the largest picture in the file), camera raw (DNG, CR2, CR3, CRW, NEF,
  NRW, ARW, SR2, SRF, ORF, RW2, RAF, PEF, SRW, ERF, 3FR). HEIF, AVIF, JPEG XL and raw need a free
  extension from the Microsoft Store; without it the image says which one.
- **A drive almost full:** a red notice in the middle when a drive the viewer works with (the image's,
  the sort folders', the deleted-files folder's) has less than 100 MB free; `[View] DiskWarning=0`
  switches it off.
- **"Save image as …"** can write TIFF as well as PNG.

## Changed

- **The right-click menu, reordered** (user): Total Commander first (Side by side, bold and deep
  green; Follow Total Commander, bold), then Copy / Paste / Delete / Save image / Save image as … /
  Crop selection (only once a selection is made) / Resize to the size shown / Make icon from this
  image, then **Rapid sorting** (bold, red; the feature's new name), Sort panel and Preview strip
  (both on / off, ticked while open), Apply filters to a copy, Order of the images, then About and
  Exit. Filters, Lock filters, Undo, Magnifier and "Save image and view" are hidden from the menu;
  their commands still work (the left edge, the filter panel's lock, mouse profile, keys, the sort
  panel's bottom line for Undo).
- The About box: "VersariteViewer 1.1", and the microscopy edition by its name.
- **The settings can no longer be lost** (a tester's report): every save writes a new file first and
  then replaces the old one in one step, so the ini is never left half written, even if the program or
  Windows stops in the middle. Each start keeps a copy as `VersariteViewer.ini.bak`; an ini found empty or cut
  short is restored from it (a red notice says so; the damaged one is kept as `VersariteViewer.ini.damaged`).
  The ini now ends with a line `; end of the settings ...`, which is used to tell a complete file.
- **Icons made by the viewer** ("Make icon from this image") are now written as Windows' own icons are:
  the sizes up to 128 px as classic 32-bit pictures, 256 px as a PNG with an alpha channel. Before,
  an opaque picture was stored as PNG without alpha, which Windows' codec refuses; the viewer now also
  reads such icons itself (the largest picture), so icons made earlier open again.

- The sort panel: "+ add folder" is on top of the folder rows. `[Sort] PanelLines` (0 = as before)
  lays the panel out for that many rows, so the text stays large; more folders scroll.
- Esc closes, in this order: the scan bar, the magnifier, the filter panel, edit mode, the sort panel;
  then the settings screen (where Esc ends the program).
- The edit-mode frame stays upright when the image is turned.
- Auto (black / white point) re-levels a selection when the mouse button is released.
- The panel's hints in the middle of the view (a new list, Rapid sorting) only with
  `[Sort] ShowDirectoryHint=1`.

## New settings

`[Navigation] Archives` · `[Sort] DirPreviewFiles`, `DirPreviewDelayMs` · `[View] PanelOpacity` ·
`[Navigation] SortMode=Random` · `[Sort] PanelLines`, `List`, `DefaultImageFolder`,
`ShowDirectoryHint` · `[DirList1]`, `[DirList2]` … · `[Mouse] EdgeWidth`, `BottomEdgeMs`, `TopEdgeMs`
· `[View] DiskWarning`. Every key is explained on the settings screen.

## Installing

Unzip anywhere and start `VersariteViewer.exe`, with `VersariteViewer_welcome.png` next to it. An
existing `MView.ini` is taken over as `VersariteViewer.ini`, `Default.mouse` is kept; folders and
keys work as before.
