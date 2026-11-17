# Driving VersariteViewer from Double Commander

VersariteViewer (VV) 1.4 and Double Commander (DC) with its remote control addition
([versarite/doublecmd › remote-control](https://github.com/versarite/doublecmd/tree/remote-control))
are connected by DC's remote control channel. DC toolbar buttons and hotkeys can send commands to VV.

## Requirements

- In VersariteViewer.ini, under `[FileManager]`:
  - `DirManager=1` (Double Commander)
  - `DoubleCommander=` set to the patched doublecmd.exe (Linux: `doublecmd`)
- DC's remote control is on (`<RemoteControl>True</RemoteControl>` under `<Behaviours>` in
  doublecmd.xml), `VersariteViewer` is a line of `remoteallow.txt` in DC's settings folder, and VV
  has been allowed once (DC asks at the first connection).
- VV is running. It collects DC's messages about twice a second.

## Making a button

1. In DC, right-click the toolbar and choose **Edit** (or go to Configuration → Toolbar).
2. Click **Insert new button** and choose **Internal command**.
3. As the command, choose one from the table below. All of them are in the category **Tools**.
4. Fill in **Parameters** where the table says so. For `cm_ViewerCommand`, the small button
   to the right of the Parameters field lists all VV commands by their caption. Click one, and
   DC fills in `cmd=<name>`, and the caption as the tooltip. VV sends DC this list each time
   it connects, so it is always up to date, and DC keeps it for when VV isn't running.
5. Add an icon and a tooltip, then click OK.

A hotkey works the same way: Options → Hot keys, the command, and its parameter.

## The DC commands

| Command | Parameter | What it does |
|---|---|---|
| `cm_ViewerCommand` | `cmd=<name>` (or just `<name>`), see below | VV runs its own command of that name |
| `cm_ViewerFollowModeOn` | none, or `mode=1` / `mode=2` | VV follows DC: none = its last mode (else 2); 1 = folder only; 2 = folder and the image under DC's cursor |
| `cm_ViewerFollowModeOff` | none | VV stops following DC |
| `cm_SendTree` | none | The first-level subfolders of DC's active folder are added to VV's sort panel |
| `cm_RemoteSendFolderToInactive` | none | VV's folder is shown in DC's other (inactive) panel |
| `cm_RemoteCreateSortFromSubdirs` | none or `0` / `1` | A new sort list (a new tab of the sort panel) from the subfolders of the folder under DC's cursor; `1`: with that folder itself |

Icons for DC toolbar buttons (follow on / off, slide show, diagnostics line, and the two remote
commands) are in [`docs/dc_icons`](dc_icons) (.png; most also .ico and .svg).

## Names for `cm_ViewerCommand cmd=`

These are the commands of VV's **Mouse & keys** page. The page shows only the caption; the name
goes after `cmd=`. Capitals don't matter. If VV doesn't know a name, it says so in its status
line.

| Mouse & keys page says | `cmd=` |
|---|---|
| Next image / Previous image | `NextImage` / `PreviousImage` |
| Next folder / Previous folder / Parent folder | `NextFolder` / `PreviousFolder` / `ParentFolder` |
| Zoom in / Zoom out (at the mouse) | `ZoomIn` / `ZoomOut` |
| Fit to window | `Fit` |
| Original size (100 %, centred) | `OriginalSize` |
| Fit <-> 100 % (centred) | `FitOr100` |
| Rotate left / right 90° | `RotateLeft` / `RotateRight` |
| Turn left / right 5° (per wheel notch) | `TurnLeft` / `TurnRight` |
| Sort by date / Sort by name / Sort: date <-> name | `SortByDate` / `SortByName` / `ToggleSort` |
| Zoom mode on / off / Rotate mode on / off | `ZoomMode` / `RotateMode` |
| Fullscreen on / off | `Fullscreen` |
| Info line on / off / Diagnostics line on / off | `Info` / `Diagnostics` |
| Menu | `Menu` |
| Paste image from the clipboard | `Paste` |
| Save image | `SaveImage` |
| Edit mode on / off / Edit mode on / Edit mode off | `EditMode` / `EditModeOn` / `EditModeOff` |
| Crop the selection | `CropSelection` |
| Read the folders again | `Rescan` |
| Sort panel open / closed | `SortPanel` |
| Delete image (into the deleted-files folder) | `DeleteImage` |
| Undo the last copy / move / delete | `Undo` |
| Side by side with the file manager (on / off) | `SideBySide` |
| Filter panel open / closed / Lock filters on / off / Reset the filters | `FilterPanel` / `LockFilters` / `ResetFilters` |
| Auto black / white point (once) / for every image (on / off) | `AutoLevels` / `AutoLevelsMode` |
| Apply the filters to a copy | `ApplyFilters` |
| Resize to the size shown (a copy) | `ResizeToShown` |
| Magnifier on / off | `Magnifier` |
| Rapid sorting on / off | `RapidSelection` |
| Toggle preview (the strip of the folder's images) | `TogglePreview` |
| Slide show / dir preview: each image longer / shorter | `DirPreviewLonger` / `DirPreviewShorter` |
| Dir preview: slide show mode on / off | `SlideShowMode` |
| Dir preview on / off | `DirPreview` |
| Slide show of this folder on / off | `SlideShow` |
| Open file ... (a file dialog) | `OpenFile` |
| Back (leave a mode, else the settings screen) | `Back` |
| Exit | `Exit` (closes VV) |

Not available from DC: "Rapid sorting: move into this digit's folder" (`RapidKey`), because it
needs a digit key.

## Examples

| Button | Command | Parameters |
|---|---|---|
| Slide show | `cm_ViewerCommand` | `cmd=SlideShow` |
| Dir preview | `cm_ViewerCommand` | `cmd=DirPreview` |
| Sort panel | `cm_ViewerCommand` | `cmd=SortPanel` |
| Side by side | `cm_ViewerCommand` | `cmd=SideBySide` |
| Follow folder and image | `cm_ViewerFollowModeOn` | `mode=2` |
| Follow off | `cm_ViewerFollowModeOff` | |
