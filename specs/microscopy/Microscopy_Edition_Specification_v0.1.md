---
title: "Versarite MView — Microscopy Edition"
subtitle: "Developer specification v0.1 (2026-10-06, Day 25: M0 and M1 built)"
---

# Microscopy Edition — Developer Specification v0.1

**Date:** 2026-10-06 (Day 25)
**Status:** M0 (the plug-in points in the core) is built, compiled and tested by the user (all tests pass). M1 (the skeleton program) is built and waits for its first compile. Everything from M2 on is planned, not built.
**Name:** *Versarite Image Lab* (from 1.1; formerly MView Lab): the program `VersariteImageLab.exe`, the project `VersariteImageLab.lpi` / `.lpr`, its settings `VersariteImageLab.ini`. The 0.2 preview: `Readme_Lab.md`.
**Relation to MView:** a second program from the **same source tree** as Versarite MView 1.0.x. Not a fork, not a long-lived git branch. MView's own specification (`specs\MView_Developer_Specification_v1.3.md`) stays valid for everything the two programs share; this document only covers what the edition adds, and the plug-in points in the core it needs.
**Platform, language:** as MView: Windows 64-bit, Lazarus / Free Pascal, LCL.

Sections marked **[Decision]** are settled with the user. Sections marked **[Open]** still need a decision or test files.

---

## 1. Purpose

MView is a general viewer, finished with release 1.0: browsing, sorting, display filters, magnifier, the Total Commander connection. Its feature set is frozen; it gets fixes.

The microscopy edition is for **looking at microscope images and measuring in them**, without leaving the viewer: the file's own metadata (objective, pixel size, channels, times), calibration where the file has none, a measuring line, a scale bar, and a note in every saved copy of what was done to it. Later: 16-bit images, camera movies and image stacks, and editing (Photoshop .8bf filters, Fiji / ImageJ).

Everything MView does, the edition does the same way: same mouse language, same speed, same settings (in its own file, §3.2).

## 2. Principles

MView's principles hold unchanged (**fast first, mouse first, never in the way**; never change an original; display first, burn in on request; file work on worker threads). The edition adds:

1. **Measure, don't illustrate.** A measuring line and a scale bar; no arrows, callouts, text labels or drawing tools.
2. **A number is only shown when it is known.** Lengths in µm only with a calibration from the file or the user; otherwise pixels, and the measuring entry is disabled (§7).
3. **Where a number comes from is always visible.** "from file" or "calibration: 40x oil (user)" next to every µm value.
4. **Provenance.** Every saved copy says what it came from and what was done (§9).
5. **The keyboard is allowed** where the work is editing (M7: filter parameters, macro names) — **[Decision]** (user, Day 24). Viewing and measuring stay mouse first.
6. **MView never notices the edition.** Nothing the edition adds changes MView's behaviour, files or settings (§3).

## 3. One source tree, two programs [Decision]

### 3.1 Layout

```
MView.lpr / MView.lpi          Versarite MView (lists no edition unit)
MViewLab.lpr / MViewLab.lpi    the microscopy edition (M1); MViewLab.ico its icon
source\core, config, imaging, mouse, rendering, utility, main
                               shared by both programs
source\microscopy\             the edition's own units (M1 on)
specs\microscopy\              this document
test\                          shared tests; the edition's tests next to them
```

- **Same repository** recommended (one history, fixes reach both). **[Open]**: the user decides (§12).
- The edition's `.lpi` adds `source\microscopy` to its search path; MView's does not. So MView cannot even see the edition's units.
- Both build into `build\` (`MView.exe`, `MViewLab.exe`), each with its own unit folder (`build\units\…`, `build\units-lab\…`), so building one never disturbs the other.
- **Switching** is choosing the project in Lazarus (Project → Open Project), not a setting: the settings file depends on the edition, and MView must not carry the microscopy code.
- **Shared when both run from the same folder** (on purpose): the mouse profile files, the icons folder of the sort panel, the deleted-files folder, `timing.csv` / `startup.csv`. Separate: the settings (`<EditionId>.ini`), the single instance, the welcome picture.
- A fix in a shared unit is a fix in both programs. A change in a shared unit for the edition's sake must leave MView's behaviour exactly as it was (the M0 rule, §4.4).

### 3.2 Which program is this: `uEdition` (M0, built)

| Name | MView | Edition (proposal) | Used for |
|---|---|---|---|
| `EditionId` | `MView` | `MViewLab` | settings file `<EditionId>.ini`; single-instance mutex `Local\Versarite<EditionId>.Instance` and shared memory `Local\Versarite<EditionId>.Window`; the welcome picture `<EditionId>_welcome.png`; captions |
| `EditionTitle` | `Versarite MView` | `Versarite MView Lab` | About box, its title and menu entry |
| `EditionVersion` | `MViewVersion` (1.0.1) | own numbering (0.1 …) | About box |

- The edition's `.lpr` calls `SetEdition(...)` **first thing**, before any `TConfig` exists. MView's `.lpr` doesn't call it: the defaults are MView's.
- So both programs can run side by side, from the same folder, each with its own settings and its own "only one instance". For MView every name is what it was in 1.0.1.

### 3.3 How edition units plug in [Decision]

The edition's units **register themselves** in their `initialization` sections (a metadata reader, an overlay layer, a menu entry). The core only knows the registry (`uExtensions`), never an edition unit. The edition's `.lpr` lists its units in `uses`, which is what runs their `initialization`; MView's `.lpr` lists none, so in MView every registry is empty.

## 4. The plug-in points in the core: `uExtensions` (M0, built)

### 4.1 Metadata readers

```pascal
TImageMetadata = record
  Reader: string;          // which reader understood the file ('' = none)
  PixelSizeX, PixelSizeY: Double;   // µm per pixel; 0 = unknown
  Lines: TStringArray;     // for the metadata panel: 'Objective: HC PL APO 40x/1.30 OIL'
end;
TMetadataReadFunc = function(const AFileName: string; var AMeta: TImageMetadata): Boolean;

RegisterMetadataReader(Name, Func);  MetadataReaderCount;
ReadImageMetadata(FileName, out Meta): Boolean;  ClearMetadata(out Meta);
```

- Readers are asked **in registration order**; the first that returns True wins. Its name fills `Reader` unless it set one itself.
- A reader that returns False, or raises, counts as "not understood" and leaves nothing behind (the record is cleared before the next one).
- **Pure functions**, no UI, no shared state: they run on any thread. In M2 they run on the decode worker, next to the decoder, and the result travels with the decoded image (like the EXIF orientation today). The UI thread never parses a file.
- M0 has no caller yet; the record grows in M2 (objective, NA, immersion, channels, times) — fields are only added, never re-meant.

### 4.2 Overlay layers

```pascal
TOverlayLayer = class
  function Picture(AView: TObject; AWidth, AHeight: Integer;
    out ALeft, ATop: Integer): TBGRABitmap; virtual;   // nil = nothing
  function Version: Cardinal; virtual;
  function HandleMouse(AView: TObject; AKind: TOverlayMouseKind; AButton: TOverlayButton;
    AX, AY, AWheel: Integer): Boolean; virtual;   // True = taken
end;
RegisterOverlayLayer(Layer)   // the registry owns it, frees it at the end
OverlayLayerCount; OverlayLayer(i); OverlayChanged(Layer); OnOverlayChanged
```

**Drawing.** Both renderers draw each layer's picture, with alpha, at the place it gives (`ALeft`, `ATop` in the view of `AWidth` × `AHeight`). The picture is only as large as what it shows (M1: a whole 4K view uploaded to the GPU at every mouse move would be too slow). It is drawn:

- **over** the image, its lens and its selection frame;
- **under** the info line, the badge, the notice, the filter panel and the sort panel;
- only while an image is shown.

`AView` is the renderer (`TRenderer`: `ScreenToImage`, `ImageToScreen`, `View`): a layer unit may use `uRenderer`; the core never uses a layer's unit.

The CPU renderer draws the picture directly. The GPU renderer keeps one texture per layer and uploads it again only when `Version` changes or the size changes; a picture that only moves is drawn again from the same texture. So a layer must **change `Version` whenever its picture's content changes**, and **keep `Picture` cheap**: it is called in every paint, and should draw again only when something changed.

A layer's exception costs its picture, never the paint.

**Mouse.** `TMView.HandleOverlayMouse` asks, in this order:

1. the TC badge;
2. the filter panel;
3. the magnifier;
4. **the layers**, in registration order (not over the open sort panel);
5. the sort panel;
6. the mouse language (gestures, zones).

The first that takes an event ends the chain, with two exceptions:

- **Press and release:** the layer that takes a press gets the release, wherever it happens (also over the sort panel), and no other layer does. A release after a press the panel took stays the panel's.
- **Moves and leaving:** a move or a leave a layer takes still reaches the sort panel, so the right edge keeps opening the panel and the panel still closes when the mouse leaves.

A layer's exception never reaches the mouse language.

**Repaint.** A layer whose picture changed outside a mouse event (a timer, a menu action) calls `OverlayChanged(Self)`; `TMView` repaints.

### 4.3 Menu entries

```pascal
TExtensionAction = procedure(AViewer: TObject);
TExtensionTest   = function(AViewer: TObject): Boolean;
RegisterMenuEntry(Caption, Action, IsEnabled = nil, IsChecked = nil);
```

- The main form adds the entries to the right-click menu, as a group of their own (separator) **before "About"**, in registration order.
- Each time the menu opens, `IsEnabled` and `IsChecked` are asked (nil: always enabled, never checked). "Measurement" uses this to be enabled only with a calibration (§7).
- `AViewer` is the `TMView`.

### 4.4 What M0 changed in MView, and what it didn't

| Unit | Change | MView's behaviour |
|---|---|---|
| `uEdition` (new) | the names | same names as 1.0.1 |
| `uExtensions` (new) | the registries | all empty |
| `uConfig` | settings file from `EditionIniFileName` | `MView.ini` next to the exe, as before |
| `uSingleInstance` | names from `EditionId` | same mutex and mapping names |
| `uIniEditor`, `umainform` | captions, About, welcome picture from `uEdition`; registered menu entries | same texts; no new entries |
| `uMView` | layers' mouse and repaint | no layers: unchanged |
| `uRenderer`, `uGLRenderer` | draw the layers | no layers: unchanged |

Test: `test\TestExtensions.lpr` / `.lpi` (built by `build_test.bat` with lazbuild, as it needs BGRABitmap).

### 4.5 The first edition unit: the pixel probe (M1, built)

`source\microscopy\uPixelProbe.pas`: right-click menu **"Show pixel position"** (checked while on, off at start) shows a small label next to the mouse with the image pixel under it (`x 1234   y 567`), below right of the pointer, flipped at the view's edges; nothing outside the image. It only watches the mouse (never takes it), redraws its label only when the text changes, and is the skeleton's test of every plug-in point: a layer in both renderers, the mouse, the repaint, a menu entry with a check mark, and the renderer's screen ↔ image geometry. From M2 it also shows µm when the pixel size is known.

## 5. Roadmap

| Step | Content | Done when | Status |
|---|---|---|---|
| **M0** | Plug-in points in the core (§3.2, §4); this document | MView compiles and behaves as 1.0.1; `TestExtensions` passes | **Built Day 25**, waits for compile |
| **M1** | Skeleton: `MViewLab.lpr` / `.lpi`, `MViewLab.ico`, `source\microscopy\`, `SetEdition`, the pixel probe (§4.5) | Both programs build from the tree and run side by side | **Built Day 25**, waits for compile |
| **M2** | Leica `.lif` reader (§6); containers like folders, in the view and the right side panel, stars, the list with thumbnails (§6.5); the metadata panel (top left); µm in the pixel probe. In steps: M2a reader + test, M2b container plug-in point and browsing, M2c side panel, M2d metadata panel | Every image of `221107.lif` browsed and shown, with objective, zoom, pixel size and channels | Designed Day 25; **M2a built** (`uLifFile`, `TestLif`); **M2b built** (containers like folders); **M2c built** (the side panel) |
| **M3** | Calibration (§7.1), measuring line (§7.2), scale bar (§7.3), provenance (§9). In steps: M3a where the µm come from (+ µm in the pixel probe), M3b measuring line + reference measurement + the left panel's selector and "Confocal" box + the settings tab, M3c scale bar on screen, M3d burned into a copy | Measuring in µm on calibrated images; a saved copy with a scale bar and its note | **M3a, M3b built** (Day 25); **M3c, M3d built** (Day 30: `uScaleBar`), with text labels (`uTextLabel`) and the SVG figure (`uSvgExport`, §9c) |
| **M4** | More formats: `.lei` (older Leica), LAS X exports finding their project file, Nikon, OME-TIFF, ImageJ TIFF | Each with test files from the user | — |
| **M5** | 16-bit images: windowing, the filters on the real values, the magnifier showing values | A 12 / 16-bit image with full range, no banding | — |
| **M6** | Movies and camera recordings (§10) | Frames stepped with the wheel, time stamps shown | — |
| **M7** | Editing: Photoshop .8bf host (64-bit), Fiji / ImageJ through Fiji (§11) | A filter applied to a copy | — |

Each step ends with both programs compiling, MView unchanged, a day log, and the user's test.

## 6. Leica files (M2) [Decision: .lif first]

### 6.1 What we have

- `221107.lif` (user, private: never published, never in the repository): 69 MB, 24 images, objective 40x / 1.30 oil, zoom 1 … 4.3, two 8-bit channels (Magenta, Green), Series009 a z-stack of 12. Parsed completely with a Python prototype; Image003's pixels decoded correctly.
- LAS X "export with overlays" TIFFs: 8-bit RGB, colour table applied, scale bar and time stamp burned in, 72 dpi placeholder — **no calibration in them**. Their burned-in bars give a check: Series084 0.131 µm/px, Glu…Image003 0.086 µm/px. They come from `221119.lif` and a 2021 project, not from `221107.lif`.

### 6.2 The `.lif` structure

- **Header:** `0x70`, a 4-byte size, `0x2A`, a 4-byte character count, then the XML in UTF-16.
- **Memory blocks**, one after another: `0x70`, a 4-byte size, `0x2A`, an 8-byte memory size, `0x2A`, a 4-byte id length, the id in UTF-16, then the data.
- **The XML** describes each image (`Element` / `Data` / `Image` / `ImageDescription`):
  - `Dimensions`: `DimensionDescription` with `DimID` 1 / 2 / 3 / 4 = x / y / z / t, `NumberOfElements`, `Length` in metres, `BytesInc`;
  - `Channels`: `ChannelDescription` with `LUTName`, `Resolution` (bits) and `BytesInc`;
  - the `Memory` block id to the pixels.
- **The settings** (`ATLConfocalSettingDefinition`): `ObjectiveName`, `Magnification`, `NumericalAperture`, immersion, `Zoom`, `Pinhole`, scan speed; laser lines and detectors; time stamps.

### 6.2a The reader (M2a, built Day 25)

`source\microscopy\uLifFile.pas`, no LCL (tested with plain fpc): `TLifFile.Open` reads the header, the XML and the block index (the pixels are skipped); `Images[i]` gives name, path in its folders, size, z / t counts, pixel size, z step, channels with their LUT colours, objective, zoom, the time it was taken and the lines for the panel; `ReadChannelPlane` one channel's plane; `RenderRGBA` all channels in their colours, one plane or the maximum projection. `test\TestLif.lpr`: a small `.lif` made by the test, damaged files, and — only on the user's machine — `221107.lif` against values from a Python reference reader.

### 6.3 Pixel size [Open]

`Length / NumberOfElements` or `Length / (NumberOfElements − 1)`: the two differ by 0.1 % at 1024 px. Follow Bio-Formats' choice; check it against a burned-in bar once a `.lif` and its export from the same project are at hand (`221119.lif`).

### 6.4 Showing it (from Strategy G2) [Decision]

- **A panel drawn at the top left**, semi-transparent, shown and hidden by a command (`Metadata`) and a menu entry; curated lines first (instrument, objective, zoom, pixel size, channels, date); "more" folds out the rest.
- **The info line** gets a compact summary: `40x / 1.30 oil   0.142 µm/px   Green`.
- A `.lif` holds many images: they are browsed like files in a folder (wheel), with the element name in the info line (§6.5).

### 6.5 Containers: `.lif` files and stacks [Decision] (user, Day 25)

A **container** is a file or an image that holds several images: a `.lif` (many images), a **stack** (an image with z-planes or time points, inside a `.lif`; later multi-page TIFFs and others).

**A one-time folder** (user, Day 25, after trying the first version, where a `.lif` was a folder of the tree and the folder gestures got caught in it). A container is **not a folder of the tree**: the folder gestures (left, right, up) pass it like a file. Its images are listed **among its folder's own images, at its place** (by name or by date), so the wheel walks into it and out again. It is opened by scrolling onto it, from the side panel, or from outside (drop, Total Commander, the command line): its folder opens on its first image. A `.lif` holds images; a stack holds its planes (later). Copy / move / delete act on the whole file (a `.lif`), never on one image inside it.

**What is shown of a stack** (user: no preference): its **maximum-intensity projection** (as LAS X and Fiji), the info line says `z max of 12`; entering the stack steps through its planes.

**Stacks, second look (Day 25, postponed; the user has many more `.lif` files to check against).** In `221107.lif` only `Series009` is a stack: 12 planes × 2 channels, filed as **z**, but z step 0 (Begin = End), time stamps 2.6 s apart — a **time series at one plane** (30 sections were set, 12 recorded); its **last plane is cut off** (rows 0–447 of 1024, last time step 1.15 s). Decided direction (user: "my instinct is following your suggestions"):

- **Tell a fake z from a real one:** z step 0 / Begin = End with running time stamps = **time**; the info line says `t 12 × 2.6 s`, not `z`.
- **The main view shows the projection** (user), for z and t stacks alike — no average.
- **An animation icon** (user, instead of an average): a stack that can play (a time series; a z-stack as a fly-through) carries a small animation mark on its row in the side panel (and the info line), next to its star.
- **Side panel, the stack's row:** **left double-click** = its planes as a list (with thumbnails, like a `.lif`'s images; the projection first); **right double-click** = **play the animation in the main view** (nothing can be moved into a stack, so the right double-click is free there). Reuses the viewer's animation playback (GIF); speed from the time stamps, sped up to a watchable rate; loops.
- **Incomplete planes are left out** (short last time step, black tail).

**Built (stacks step 1, Day 26): what a stack is.** `uLifFile`: a stack's **frames** run along t when the image has a time dimension, else along z (`FrameCount`); all time stamps are read (one per plane and channel; frame f's at f × stamps / frames) into `FrameTimes` and the median step `FrameInterval`. **`StackKind`**: depth, or time — a z filed with step 0 and running time stamps is time at one plane (`FakeZ`; the panel line: "Time: 12 points, every 2.593 s (filed as 12 z-planes at one depth)"). **`UsableFrameCount`**: a last frame is cut off when its step is shorter than 0.8 × the usual one (without time stamps nothing is left out) and its bottom rows are 0 in every channel, a sixteenth of the height more than the frame before; it is left out (repeatedly, from the end). Read from the pixels the first time (one or two planes). The **projection** (`RenderRGBA` with z = −1) takes the usable frames only; **`RenderFrameRGBA`** shows one frame (projected over z when a time series has z too); **`StackSummary`**: `z 12 × 0.5 µm`, `t 11 × 2.6 s` (for the info line and the side panel, step 2). `Series009` of `221107.lif`: time, 12 frames every 2.593 s, 11 usable. Tests: `TestLif` (a fake z made there, cut and complete; the small depth stack; `Series009` when present).

**Built (stacks step 2, Day 26): the mark, the note, the frames' list.**

- **Animation mark:** in the side panel's list of a `.lif`'s images a stack's thumbnail carries a cyan play triangle on a dark square at its lower right corner (`TContainerEntry.Frames`, `TPanelEntry.Frames`).
- **Info line:** a stack's name is followed by its note, `221107.lif › Series009   t 11 × 2.6 s (projection)` (`ContainerEntryNote`; the reader's, one cached).
- **Left double-click** on a stack's row (the first click shows its projection, as before; the panel's foot says "double-click: its frames"): the panel lists its usable **frames**, each with its thumbnail and its time (`t 3    5.2 s`) or depth (`z 3    1.00 µm`); the title `221107.lif › Series009`; **"< back"** returns to the `.lif`'s images. A click on a frame shows it (read at once), like a crop: the info line names it (`221107.lif › Series009 › t 3    5.2 s`), Save image or the sort panel write it (`221107_Series009_#t03`), the wheel goes on from the stack; the frame shown is yellow in the list; the stack's scale measures it.
- **Generic in the core** (`uContainers`): `RegisterContainerStacks` (a reader's frames' list and note); `ListContainerEntries` with a virtual name lists a stack's frames (ids relative to the container file, so `uContainerThumbs` lists and thumbnails them like a `.lif`'s images). MView: no readers, unchanged.
- **`.lif`** (`uLifContainer`): frame ids `<stack>|#t03` / `|#z03` (1-based; `LifSplitFrame`); `LifIndexOfId` takes a frame to its stack; decoding a frame id renders that frame; the frames' list and the notes share one cached `TLifFile`.
- Right double-click (play) is step 3.

**Built (stacks step 3, Day 26): playing.** A **right double-click** on a stack's row (or on any frame of its list) plays it in the view; again — or while its frames are being read — stops it (the stack shown as before). Its usable frames are read one per timer tick (the window stays alive; the status line counts them), held in memory (at most 512 MB: larger stacks are shrunk to fit, the original size kept, so the scale still measures), then shown as an animation like a crop (`TBitmapListAnimation`, uAnimation): the view's zoom, pan, turn and filters work while it plays; the wheel goes on. **Pace:** a time series at its own intervals, sped up so a frame lasts about 0.2 s (never slower than real time; the info line says `(13x real time)`); a depth stack 0.15 s per frame; it loops. Its name is the stack's: the stack's scale measures it; Save image writes the frame on screen. Moving to another image while the frames are read: not played. Frame times come with the frames' list (`TContainerEntry.Time`).
- **The microscope's details over the large picture** (user, Day 26): while the mouse is on an image (or a frame) of the panel's list, its large picture left of the panel carries the file's details on a dark band over its lower part — pixel size, size, stack / time, channels, system, objective, zoom, pinhole, scan, detectors, acquired (the metadata reader's lines, in that order; as many as fit). Core: `TSortPanel.OnEntryDetails`, `TMView.PanelEntryDetails` (`ReadImageMetadata`; none in MView).

**In the right side panel** (user):

- Containers get **entries like folder buttons**, marked with a small **star** where the numbers used to be. **Star colours** tell the kind: `.lif`, stack, and later other kinds each have their own (proposal: amber = `.lif`, cyan = stack, violet = others).
- **Transient** (user, Day 25, replacing the first "both ways in"): only the container **the wheel is in** appears, **on top of the panel**, and the panel **opens it there** (its images listed); a click on any of them shows it. When the wheel leaves the container, it **leaves the panel**. Containers are never pinned and **never written to the ini** (an old `[Containers]` section of the first builds is erased). A `.lif` dropped on the panel is opened in the view (and so appears on top). "< back" shows the sort buttons with the `.lif` still on top while the wheel stays in it; a double-click on it lists its images again.
- **Double-click opens** a container entry: the panel then **lists its images**, each with its **thumbnail**; the mouse over one shows it **large to the left of the panel**, like the folder icons (Day 24). A click shows that image; a "back" entry at the top returns to the panel's folders. (For container entries, double-click opens instead of copy / move: nothing can be copied into a `.lif`.)
- Swipe and wheel click open a container entry in the view, as for folders.

**Built (M2b, Day 25).** `source\utility\uContainers.pas` (no LCL): the readers' registry and the name helpers. An image inside a container has a **virtual name**, `C:\data\221107.lif|Series009` — `|` can't occur in a Windows path, so such a name is always virtual and code that misses it fails safe (FindFirst / FileExists find nothing); ids never contain `\ / :` (nor `? * " < >`), so `ExtractFileDir` of a virtual name is still the real folder. The hooks, each a no-op without a reader (MView):

| Where | What |
|---|---|
| `uDirectoryTree` | a container is listed with the folders (recursive scans), its entries are its images; a container opened directly is the root |
| `uDirectoryImages.Scan`, `uDirectoryScanner.Resolve`, `uNavigator.OpenPath` | a container opened = a folder; a virtual name opened = a file in it |
| `uNavigator` | `ItemDirectory` (the container for a virtual name) instead of `ExtractFileDir` |
| `MakeImageKey` | the container file's size and time: changing the `.lif` renews all its entries |
| `uMediaLoader` | a virtual name is decoded by the edition's reader (no preview level), memory guard, I/O gate |
| `uMView`, `uMainForm`, `uRenderer`, `uImageSaver` | info line `221107.lif › Series009`, folder = where the `.lif` lies; copy / move / delete of an entry refused; saved copies named `221107_Series009_…`; Total Commander's folder = the real folder; TC's cursor on a `.lif` opens it |

`source\microscopy\uLifContainer.pas` registers `.lif`: ids are the image paths in the file (`Folder/Series009` → `Folder|Series009`), unique (`~2` for a second image of the same name); a stack decodes as its maximum projection. The **up gesture** inside a container works as in any folder (it widens the browsing to the parent folder, the image stays). Not yet: containers in non-recursive opens (and while following Total Commander) — the side panel (M2c) will show them; a cached index per `.lif` (each listing and each decode reads the file's description again).

**Built (M2c, Day 25): the side panel.**

- The folder listings (`TDirectoryImages`, the tree) keep the folder's container files apart (`ContainerCount`, `Container`); inside a `.lif` its neighbours. `TNavigator.FolderContainers`.
- ~~`[Containers] Pinned1..N`~~ — removed Day 25 (transient containers, see above): `TPinnedContainers` is gone; `TConfig` erases the section.
- `TSortPanel`: the container group **on top**, above the sort buttons (a line below it), a grey folder with a **star** (amber `.lif`, cyan stack, violet other) where the numbers used to be. `TMView.RefreshPanelContainers` (after every step) puts the container of the current image there and enters it; it acts only when the container changes. **Contents mode**: "< back", then the images, each with its thumbnail; the one under the mouse large in the box left of the panel; a click shows it in the view.
- `uContainerThumbs` (new): the list and the thumbnails (32 px and 256 px, scaled) on a thread of their own, the one under the mouse first, giving way to the image on screen (I/O gate); the newest request replaces the older one.
- Double-click a container = its images; swipe or wheel click = open it in the view; copy / move are never offered on it.

**What the core needs** (M2, the plan): a **container reader** plug-in point (`uExtensions`): "do you hold images?" (by extension and content), list the entries (name, kind, size, a thumbnail on request), decode one entry (on the decode workers), its metadata; and a container as a place in the navigator (path `file.lif` + entry), so browsing, the info line and the cache treat entries like files.

## 7. Calibration, measuring, scale bar (M3)

### 7.1 Calibration [Decision]

- **A scale from the file always wins.**
- Otherwise a **named calibration** per objective ("40x oil, SP8 zoom 1"), entered as numbers or measured on a known object (a stage micrometer: draw the line, type the known length — keyboard allowed here). Kept in the edition's settings.
- Calibrations are stored with the image width they were made for; another width scales them, and the source says so.
- An image without either: pixels only, "Measurement" disabled.

**Where the µm come from, in this order (Day 25, user):**

1. **The file itself** — an image inside a `.lif`.
2. **A matching `.lif`** (user: yes). Exported TIFFs carry no scale (`221119_Series084_t242_ch01.tif`: 8-bit RGB, 72 dpi, no µm), but LAS X names an export `<project>_<image>[_t…][_z…][_ch…]`: that `.lif` in the same folder or the one above lends its pixel size (scaled when the export is smaller than the scan); the source is shown (`221119.lif › Series084`).
3. **The chosen calibration** from the record below.
4. None: pixels only.

**The calibration record** (user, Day 25): a list linking unique **microscope / objective** combinations to a **reference measurement** (a known length in µm over measured pixels).

- **Its own file**, `calibrations.ini` in the program folder (user: separate — calibrations belong to the microscope; copy it to another PC or to colleagues). One section per record: `Name`, `Microscope`, `Objective`, `Confocal`, `ReferenceMicrons`, `ReferencePixels`, `ReferenceWidth`, `ReferenceZoom`, `Date`, `Note`; numbers with a `.`.
- **Confocal or not** (user): a **"Confocal" check box in the left side panel**. Checked: the record keeps the image width and the zoom it was measured at, and µm/px scales with both (a scanner's pixel size changes with the scan format and the zoom). Unchecked (a camera): a fixed **pixels per µm**.
- **Filled from the main screen** when a reference measurement is made: the measuring line in reference mode over a stage micrometer, the known length typed, the name confirmed (pre-filled from the file's microscope / objective). An image that has a scale from its file can be saved as a record directly.
- **The selector at the bottom of the left side panel** (user): one line with the active calibration; a click opens the list (and "none — pixels"). When the file has a scale the line says "from file". The choice **sticks** for the next images; an image whose metadata names an objective that has a record picks it by itself.
- **A tab "Calibrations" in the settings screen** (user), next to "Mouse & keys", microscopy edition only (plugged in like the menu entries): the records listed, renamed, deleted.
- **Saved copies with a scale bar** carry the bar's length in their file name (user: yes), e.g. `…_bar20um.tif`, as bars carry no text.

**Built (M3a, Day 25):** `uCalibrations` (the record, `calibrations.ini`, µm/px with the confocal scaling; `TestCalibrations`), `LifExportGuesses` / `LifImageForExport` in `uLifFile` (tested in `TestLif`), `uImageScale` (the metadata reader "Leica LIF" for 1 and 2, one opened `.lif` kept; `ScaleFor` with the order above; the chosen calibration's name — the selector comes with M3b), `TImageMetadata` with the scale's width / height / source and microscope / objective / zoom (`uExtensions`), and **µm in the pixel probe** (a second line with the source when borrowed). Not yet: LAS X's own metadata files next to exports (no sample yet); crops and resized copies lose the scale (later: the copy carries it).

### 7.2 Measuring line [Decision] (user, Day 24)

- Right-click menu entry **"Measurement"**, enabled only when the image is calibrated.
- **Click – follow – click:** the first left click sets the start; a straight line follows the mouse; the second click ends it. No dragging (user: "depending on your motor skills, dragging is often awkward").
- The length is shown at the line in µm, readable at any zoom. **Day 26 (user):** the µm only — no px, no second line with the scale's source (the left panel's "Scale" row shows it). Without a scale, and while calibrating, px.
- **Burned into a copy (Day 26, user):** "Apply filters to a copy" (right-click menu) also draws a finished line into the copy — after the filters, mirror and turn, upright as on screen, sized for the copy (label about 1/45 of its shorter side); the menu entry says so ("Apply filters and measurement to a copy"); the length goes into the copy's name (`_56.32um`). Plug-in point: `uExtensions` burn-in (`CanBurnIn` / `BurnIn`, `BurnInPoint`).
- **Decided (Day 25):** a right click leaves the mode (Esc does not reach the edition's layers); the line stays until the next image or the next measurement; one line at a time. **Shift** held: horizontal or vertical.
- **Several lines (Day 26, user):** **Shift** held at a line's first click keeps the lines drawn before; without Shift a new line replaces them. Each line has its own label; all go into "Apply filters to a copy" (the name gets `_3lines`, one line its length). Shift pressed again while a line follows makes it horizontal or vertical (held on from the first click it doesn't snap). A reference measurement that is cancelled leaves no line. A reference measurement is always one line.
- **Labels and the info line (Day 26, user):** the labels follow `[View] OverlaySolid` — on a solid black box (1), or straight over the image with a dark outline (0, the default); no setting of their own. A burned-in copy takes the same style.
- **Reference measurement (calibrate)** (user): a second entry, enabled on any image; the same line (yellow), then a dialog — the known length (typed), the name, microscope, objective (from the file when it says), "Confocal" and the zoom, a note; saved to `calibrations.ini` and chosen. When the image has a scale of its own (or a matching `.lif`'s), its length for the same line is shown and filled in: OK keeps the file's scale as a record without a stage micrometer.

**Built (M3b step 3, Day 25): the settings tab.** A plug-in point in the core: settings pages (`uExtensions`: `RegisterSettingsPage` - caption, hint, a function that makes the page's content, one that brings it up to date); the settings screen (`uIniEditor`) adds a tab per page next to "Mouse & keys" and makes its content when the tab is first opened (none in MView). `uCalibrationPage` (new): **"Calibrations"** - the records of `calibrations.ini` (in use, name, microscope, objective, confocal, value, date, note); **Use this one** (also a double-click), **Use none (pixels)**, **Rename …**, **Delete** (asks), **Reload**. Changes go to `calibrations.ini` at once (the page's own file: the settings screen's Save is not needed). New calibrations are made in the viewer.

**Built (M3b step 2, Day 25): the left panel's rows.** A plug-in point in the core: `TPanelSection` (`uExtensions`: rows drawn, hinted and clicked; `RegisterPanelSection`) and the image shown (`SetShownImage`, kept by TMView after every step); `uFilterPanel` draws an edition's rows below "Auto / Reset all" (none in MView: the panel unchanged). `uCalibrationPanel` (new): **"Scale"** — from the file / from `221119.lif › Series084` / the chosen calibration (amber) / none (pixels) *(Day 26, user: the file's own metadata named with its value — `lif metadata  0.1173 µm/px` for an image, stack or frame inside a `.lif`, `file metadata  …` for a file that says it; the hint: "measured with the metadata: …")*; a click opens the list (none, the calibrations with their values, "Reference measurement (calibrate) …"); **"Confocal"** — a check box. The choice and "Confocal" are kept in the edition's ini (`[Calibration] Chosen`, `Confocal`: per installation, not in the shared `calibrations.ini`).

**Built (M3b step 1, Day 25):** `uMeasureLine` (the layer and the two menu entries "Measurement" — enabled when the image has a scale — and "Reference measurement (calibrate)"), `uCalibrationDialog` (the dialog, built in code), `ConfocalMode` in `uImageScale` (the dialog's default until the left panel's box exists).

### 7.1b The scale travels with the image (Day 26, user: "important step")

A crop, a filtered / turned copy ("Apply filters to a copy") and a resized copy ("Resize to the size shown") keep their parent's scale: the core reports each new image (`uExtensions.NoteDerivedImage`: the new name, the parent, the operation, the parent's size, parent pixels per new pixel, the turn), the edition remembers how it was made for the session and works its scale out from the parent's whenever asked (`uImageScale`, order 0, before the file's own; at most 200; a chain up to 20 deep) — so a calibration chosen later reaches the crops too. A crop: unchanged; resized: by the size change; turned: a quarter turn swaps x and y, an oblique one takes their mean. A chain (a crop of a crop, of a stack's frame) carries it on; the source says so: the left panel `from Series009 (crop)`, `… (crop) (resized)`; a parent measured with a calibration: `<calibration> (crop)` (amber). The measuring line, the pixel probe and the burned-in measurement use it. **Built (Day 26): the saved file carries it.** Every save (Save image, Save image as …, a crop or copy saved by the sort panel) writes the image's scale (µm per pixel of the pixels written - a quick view's larger; `QueryImageScale`, `TMView.SaveScale`) into the file (`uImageFileScale`, plain): a **PNG** gets a `pHYs` chunk (pixels per metre, for other programs) and a `tEXt` chunk `MView scale` = `um_per_pixel=0.1173,0.1173` (the exact value, and the mark that it is a scale: a PNG with a `pHYs` only — 300 dpi from an image program — has none); **Save image as … → TIFF** (new choice in the dialog, both editions) writes an uncompressed RGB TIFF the ImageJ way — `ImageDescription` "ImageJ=1.54f / unit=micron", `XResolution` / `YResolution` = pixels per µm, `ResolutionUnit` none — so ImageJ / Fiji open it calibrated. MView Lab reads both back first ("File scale" reader, before the `.lif` guesses): the left panel says `file metadata  0.1173 µm/px`. A Fiji-saved TIFF with an ImageJ unit (micron, µm in UTF-8 / Latin-1 / Greek mu / `\u00B5m`, nm, mm) is read too; a TIFF without one (Leica exports: 72 dpi) has none. Tests: `TestCalibrations` (TestFileScale).

### 7.3 Scale bar [Decision] (user, Day 24)

- Right-click menu entry **"Draw scale bar"**.
- The bar is **horizontal** and **follows the mouse**; its **length snaps to round values** (1, 2, 5, 10, 20, 50 … µm) about a fifth of the visible image; the **wheel changes its thickness**; the **third click** finishes it (the first places it, the second fixes the length — **[Open]**, to be tried on screen).
- Can be repeated (another bar replaces it).
- Into a **saved copy** ("Burn in scale bar"), like Crop: Save / Save as write it. The original is never changed.
- Text labels: no (Strategy decision 6). **Changed (Day 30, user):** text labels that can be edited or removed later — `uTextLabel` ("Text labels": a click asks for a text, a click on a label edits it, empty removes it), as text in the SVG figure.

**Built (M3c / M3d, Day 30): `uScaleBar`.** Click places one end; the bar runs horizontal (on screen) to the mouse, its length snapped to 1, 2, 5 × 10ⁿ µm; the second click fixes the length; the wheel sets the thickness; the third click finishes. Its length above it (solid or outlined as `[View] OverlaySolid`). A new bar replaces the old one; a right click leaves; the bar stays until the next image. "Apply filters to a copy" draws it in (`50um-bar` in the name). The look of the bar, the measuring line and the labels: `[ScaleBar] Color` (a name, `#RRGGBB` or `R,G,B`), `Font`, `FontSize`, `Bold`; `SvgReferenceBar` (the figure's reference strip). One tool at a time: measuring line, scale bar and labels end each other's mode.

## 8. 16-bit (M5)

The SP8 files at hand are 8-bit per channel; 12 / 16-bit comes with other instruments and the new microscope. Then: the decoded image keeps the real values; the filters' black / white points work on them; Auto contrast like Fiji on the real histogram; the magnifier shows the value under the mouse.

## 9. Provenance [Decision] (user's idea, Strategy "Next")

Every image the edition saves gets a "Versarite MView" text entry (PNG tEXt / iTXt, TIFF ImageDescription where free):

```
Source: 221119.lif / Image017
Done: crop 512x512+100+80; filters b+10 g0.80; rotate 90; scale bar 10 µm
Scale: 0.142 µm/px (from file)
Program: Versarite MView Lab 0.1, 2026-10-06
```

## 9a. Stack export [Decision] (user, Day 25)

A stack or time series (`.lif`) written out as a file: **TIFF stack** (a must: every plane, the bit depth kept, readable by Fiji / ImageJ, the pixel size in the TIFF), **animated PNG** (full colour, lossless, plays in browsers; z-stacks with a fixed frame time, forward or back and forth; time series at their real interval). GIF (256 colours, 8-bit) on the back burner. From a right-click entry while a stack is shown; the scale bar (M3) optionally burned into every frame. Planned after M2d.

## 9b. Formats [Decision] (user, Day 25; for the implementation plan)

Context: the user's comparison `specs\Versarite_MView_Viewer_Comparison.docx` names format coverage as MView's main weakness. Looked at: Xelitan's Pascal libraries (XelImageFormats — "50+ formats" for TPicture; AVIF/HEIC in pure Pascal, LGPL-2.1; JPEG XL via libjxl; JPEG 2000; WebP) — useful as a reference, but young, lightly used, with unclear or LGPL licences (two open memory-leak issues on the DLL AVIF/HEIC one).

- **Modern formats through Windows' own codecs (WIC), in both editions:** HEIC, AVIF, WebP, JPEG XL wherever Windows can decode them (the free Microsoft Store extensions); when it can't, say which extension to install. No third-party code. Third-party libraries at most as a later fallback.
- **No large licence overhead** (user: "this is a fun project"): no LGPL / GPL libraries linked in.
- **Microscopy containers, one maker at a time:** Leica `.lif` first (built), then others as the user obtains files — Zeiss `.czi`, Nikon `.nd2`, Olympus `.oir` / `.vsi` — each as a container reader (uContainers), like `.lif`.
- **The TIFF options and the symbiosis with Fiji:** the pixel size from ImageJ / OME-TIFF metadata (a scale from the file, §7.1), 16-bit TIFF (M5), multi-page TIFF stacks; TIFF stacks out (§9a) that Fiji reads with their scale.

## 9c. The Lab between the microscope, Fiji and the drawing programs [Decision] (user, Day 26)

**The place of MView Lab** (user): *microscope → (MView Lab ↔ Fiji) → Inkscape / Adobe Illustrator / CorelDRAW*. The Lab views, crops, levels, measures and adds the scale bar; Fiji analyses; the drawing program only lays out the figure — "once in Inkscape, no more image manipulation should be necessary".

**Appose (considered, not taken now).** Appose (apposed/appose, BSD-2, from the Fiji / SciJava people) is a library for interprocess cooperation with shared memory: a host starts *worker* processes (Python, or Groovy with the ImageJ2 / Fiji libraries), sends them scripts as JSON lines on stdin, gets progress and results as JSON lines on stdout; arrays travel as named shared memory, not copied; it can build the workers' environments. Not for the Lab's Fiji link: it does not attach to the user's running Fiji window (it starts its own headless workers); there is no Pascal implementation (the protocol would have to be written here: JSON lines + Windows named shared memory); its environments are large (hundreds of MB to GB) and a JVM starts slowly — against "no large overhead, a fun project". **Later, as an optional add-on**, it fits *computing from inside the Lab* (Cellpose / StarDist segmentation, background subtraction, deconvolution on the image shown, the result back in the view), installed only by those who want it, never needed for viewing.

**The Fiji link instead:** (1) files — a TIFF saved by the Lab carries its calibration ImageJ's way (built, §7.1b); (2) **"Open in Fiji"** (right-click): the image (or crop, with its scale and measurements) as a calibrated TIFF into a temporary folder, Fiji started with it (with Fiji's "single instance listener" it goes into the open Fiji) — a few dozen lines, no dependencies.

**Measurements as vectors: SVG for the drawing programs.** Burned-in lines and labels are pixels: in Inkscape a label can't be moved off a structure, its font changed, a line recoloured for a journal's style or a typo fixed; enlarged, they blur. So the end product for the drawing programs is an **SVG** (Inkscape's own; Illustrator and CorelDRAW import it well; EPS is legacy — no transparency, clumsy rasters, Inkscape needs Ghostscript for it; PDF at most later, Inkscape converts). **"Export figure (SVG)"**:

- the **image** as shown (crop, turn, filters in its pixels, as "Apply filters to a copy"), embedded as lossless PNG (self-contained; a linked file breaks when files move);
- **measuring lines** with their end marks, **labels as text** ("56.32 µm"); the **scale bar** (M3c) as a line and a text, its length exact in image pixels;
- **layers** "Image", "Measurements", "Scale bar" (Inkscape layers; Illustrator / Corel: named groups), all in one group, so scaling the figure keeps image and overlays together and the bar right;
- the page at the image's pixel size and a print resolution (e.g. 300 dpi) — a sensible physical size;
- a **metadata** note inside: µm per pixel, the source (`221107.lif › Series009 (crop)`), the date — a figure can always be traced back.

**Burning in stays** — the quick way for an e-mail, a slide, a notebook.

**Built (Day 30): `uFijiLink`, "Open in Fiji".** The image shown — its own pixels, as decoded (the core's image pixels source, `uExtensions.GetImagePixels` / `TMView.PixelsSource`: no display filter, no mirror, no turn: Fiji analyses the data) — as an RGB TIFF calibrated ImageJ's way (`MakeRgbTiff`: µm per pixel; a reduced copy of a huge image or a quick view with its scale corrected, the note says so) into `%TEMP%\VersariteImageLab\` (`<name>_hhnnss.tif`; files older than a day are deleted when the next is written), and Fiji started with it (`ShellExecute`; with Fiji's single instance listener it opens in the running Fiji). Fiji's program: `[Fiji] Path` in the edition's ini; empty or gone: looked for (`uFijiFind`: `ImageJ-win64.exe`, `fiji-windows-x64.exe` … in `C:\Fiji.app`, `C:\Fiji` and `Fiji.app` / `Fiji` in the user's folder, Desktop, Documents, Downloads, `%LOCALAPPDATA%`, `%ProgramFiles%`) and written there; not found: a dialog asks once. Not yet: the measuring lines as ImageJ ROIs; 16-bit (M5). **The edition's keys on the settings screen (Day 30, user):** `uEdition.RegisterEditionKey` (section, key, default, help, write): the settings save (`TConfig.Save`) writes a registered key that is missing with its default, the settings screen explains it (`ConfigKeyHelp` falls back to `EditionKeyHelp`). Registered: `[Fiji] Path` (empty), `[ScaleBar] Color / Font / FontSize / Bold / SvgReferenceBar` (before: "not a key … knows"), `[Calibration] Chosen / Confocal` (explained only, written by the left panel). Tests: `TestExtensions` (TestEditionKeys). Tests: `TestCalibrations` (TestFijiFind). Checked under Wine with a stand-in Fiji: found in `C:\Fiji.app`, path stored, the TIFF's pixels identical to the image's, `unit=micron`, 4 px/µm for 0.25 µm/px.

**Built (Day 30): `uSvgExport`, "Export figure (SVG) …".** The image as "Apply filters to a copy" makes it (the core's figure source, `TMView.BuildTurnedCopy`), embedded as PNG; each layer's `SvgMarkup` in its own Inkscape layer (Measurements, Scale bar, Labels) inside one layer "Figure"; the page at 300 dpi; a `<desc>` with the pixel size, its source, the image and the date. **The reference strip** (user): with a scale, a thin black strip below the picture with a white line of the bar's length (no bar: a round fifth of the width), no text — part of the picture's pixels, so the scale survives when the picture alone is resized in the drawing program; cropped off at the end. Checked under Wine: an export with a label, a scale bar and a measurement opens as layered SVG.

**Order (user, Day 26):** stack playback (§6.5 step 3) → **the modern formats through Windows' codecs** (§9b, both editions: closer to the common viewers) → M3 on (M3c scale bar on screen, then the SVG figure export with measurements and scale bar as vectors) → "Open in Fiji".

## 10. Movies and camera recordings (M6) [Decision: only in the edition]

MView 1.0 ignores videos (it counts them in the info line). The user has recordings from Prosilica, Thorlabs, The Imaging Source and Point Grey cameras. Plan: frame stacks with time stamps; raw AVI and TIFF stacks with own readers, compressed video through FFmpeg's libraries; the wheel steps frames. Formats and file sizes to be surveyed from the user's files.

## 11. Editing (M7) [Decision: only in the edition]

- **Photoshop .8bf filters:** a 64-bit host for the classic filter API; the filter's own dialog; the result into a copy.
- **Fiji / ImageJ:** through Fiji itself (headless, macros), not by running the `.jar` filters in MView.
- The keyboard is allowed here.

## 12. Open questions

| # | Question | Proposal |
|---|---|---|
| 1 | The edition's name | *Versarite MView Lab*, id `MViewLab` (in use from M1; can still be renamed) |
| 2 | Same repository or a second one | Same repository, both programs in it |
| 3 | `.lif` pixel size: N or N − 1 | Follow Bio-Formats; check with `221119.lif` and its exports |
| 4 | `.lei` files | User provides them (M4) |
| 5 | Nikon images (camera body, no microscope data) | Calibration per objective (§7.1); user provides files |
| 6 | Stepping z / t in a `.lif` | Decided: a stack is entered like a folder (§6.5) |
| 7 | One measuring line or several | One (simplest), more if the user asks |

## 13. Tests and test data

- `TestExtensions` (M0): the registries and the edition names; no files.
- From M2: small, **anonymised** test files in `test\images\meta`. The user's own microscopy data (`221107.lif`, the SP8 exports, everything in `test\images\Microscope images`), photos and NASA images stay **private**: never published, never in the repository.

## 14. Decisions

| # | Decision | Day |
|---|---|---|
| 1 | Microscopy moves to a second program from the same source tree, not a fork, not a long-lived branch | 24 |
| 2 | MView 1.0's feature set frozen; fixes reach both programs | 24 |
| 3 | Edition units register themselves; the core never names them; MView's `.lpr` lists none | 25 |
| 4 | Own settings file and single instance per edition (`EditionId`) | 25 |
| 5 | Measuring: menu entry, enabled only when calibrated; click – follow – click, no dragging | 24 |
| 6 | Scale bar: horizontal, follows the mouse, round lengths, wheel = thickness, third click finishes, repeatable | 24 |
| 7 | .8bf, Fiji, movies and keyboard editing only in the edition | 24 |
| 8 | Layers drawn over the image, under texts and panels; offered the mouse after the magnifier, before the sort panel | 25 |
| 9 | Name *Versarite MView Lab* (`MViewLab`), same repository, two `.lpi` files (not build modes); a layer's picture only as large as it shows, with its place | 25 |
| 10 | Containers (`.lif`, stacks) are one-time folders; in the side panel with coloured stars, **transient**: only the one the wheel is in, on top, opened there; gone when the wheel leaves; never pinned, never in the ini. The list has thumbnails, enlarged on hover; stacks show the max projection first | 25 |
| 11 | Stack export: **TIFF stacks a must** (keeps 12 / 16-bit, for Fiji), **animated PNG** (full colour, lossless) preferred to GIF; GIF on the back burner. When: after M2d, with plane stepping (M5) and the scale bar (M3) | 25 |
| 12 | Stacks (postponed): a zero-step "z" with time stamps is **t**; the view shows the projection; an **animation icon** marks stacks that play; side panel row: left double-click = list the planes, right double-click = play in the view; cut-off planes left out (§6.5) | 25 |
| 13 | Calibration record: `calibrations.ini` of its own; microscope / objective → reference measurement; "Confocal" box in the left panel (scaled by width and zoom) or px/µm; filled from the main screen; selector at the bottom of the left panel; a settings tab; exports borrow the scale of a matching `.lif`; a scale bar's length in the saved file's name (§7.1) | 25 |
| 15 | The Lab sits between microscope, Fiji and the drawing programs; figures go to Inkscape / Illustrator / Corel as **SVG** with measurements and scale bar as vector layers (image embedded as PNG); burning in stays for quick use; the Fiji link by calibrated TIFF files and "Open in Fiji"; Appose not now (no attach to a running Fiji, no Pascal side, large environments) — later possibly an optional add-on for computing in the Lab; order: stack playback, Windows codecs, M3c, SVG export, Fiji (§9c) | 26 |
| 14 | Formats: modern formats (HEIC, AVIF, WebP, JPEG XL) through Windows' own codecs in both editions; no large licence overhead; microscope makers' files one at a time as containers (Leica first); the TIFF options (ImageJ / OME scale, 16-bit, stacks) and Fiji (§9b) | 25 |
