# VersariteViewer 1.3

Released 2026-10-27. The changes after the 1.2 release (2026-10-22): 3D models (STL) in the
viewer, drawn by the graphics card; combining two animated GIFs; smarter sorting; surer opening
and browsing; polishing from daily use.

## Slide show and dir preview

- **The slide show overrides the Total Commander dir preview** (user: with both on, nothing
  played): starting the slide show ends a folder's preview and plays that folder; while the show
  runs, Total Commander's cursor on a folder starts no preview; when it ends, the dir preview
  takes up the folder under the cursor again.
- **Down to 0 = paused:** "each image shorter" (DirPreviewShorter) goes all the way to 0 ms,
  whatever the step; there the show pauses (it is not ended; the info line says "paused", the
  image gets its full version). Longer again goes on: the slide show from the image shown, the
  dir preview with the folder's next image.

## Screen and settings

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
- **A zone can browse in random order** (user): "Browsing from this zone" offers **Random**, by
  date and by name (before: "any order", which did nothing visible). A zone with none of them
  ticked, such as Inspect, leaves the order as it is. In a profile file: `Order=Random`.
- **The info line in a small window**: what doesn't fit goes on a second (third …) line,
  broken between its parts, instead of being cut off at the right edge. **Messages** ("Slide show:
  on", "Sent to Fiji", "Saved …") have a line of their own above it, so they are seen at once;
  before, they came last and were often cut off. A message also shows when no image is open.

## Sorting, polished (day 32)

- **Dynamic folder lists** (user): a list of the sort panel can sort itself - a double-click on
  its title ("Sort 2/8"), or the right-click menu's "Dynamic sorting", switches it; a small red
  star before the title marks it. Each copy or move into one of its folders moves that folder up
  one place, so the folders used most gather on top and a long list needs no scrolling. The list
  is rearranged only once the mouse has left the panel: while it rests on a button, the next
  double-click goes to the same folder. Each list on its own (`[DirList<n>] Dynamic=1`).
- **Pin to top** (user): the first line of a folder's menu ("..."). Pinned folders stay on top in
  the order you give them (Move up / down / to top among themselves) and have a red frame;
  the others never climb above them. Unpin: the same line. In every list (`Slot<n>Pinned=1`).
- **Semi-automatic sorting** (user): in a slow slide show or the Total Commander dir preview, a
  copy or move restarts the time, so the next image gets its full time; while the mouse is on the
  sort panel the show waits.
- **After a copy or move** the magnifier and the zoom / rotate mode end, so the next image comes
  at once.
- **No more duplicates** (user): when the same image is in the folder already - the same name (or
  one of its `_1`, `_2` copies), the same size and identical bytes - a copy is not made ("already
  in ... (identical)"), and a move puts the image into the deleted-files folder as `dup1_<name>`
  (`dup2_` ...) instead of making `<name>_1`; Undo brings it back. A file of the same name with
  other content is still kept as `<name>_1`.

## 3D models (STL)

- **.stl files are shown like images** (user): binary and ASCII STL, **drawn live by the graphics
  card** (OpenGL: the model goes up to the card once, every turn is just the next frame, as fluid
  as in a dedicated STL viewer), with the look of the user's own STL viewer - a light model on a
  dark background, the build plate as a grid under it, the axes, the triangles' edges as light
  lines. Without a suitable graphics card it is drawn in software (pictures, slower). No library
  is needed. The info line gives the number of triangles and the size (in the file's units, usually
  mm) in place of the pixel size. Browsing, sorting, copy / move, the filters and "Save image"
  (a PNG of the view) work as for any image.
- **A drag with the left button turns the model in 3D** (as in the STL viewer): left / right
  around its vertical axis, up / down tilts it (elevation). **The rotate mode turns it** too,
  instead of turning the picture: the wheel in rotate mode as usual, R (tap) a quarter turn. Zoom zooms the picture (drawn at
  twice the screen size, so zooming in to 200 % stays sharp).
- **The section controls are in the filter panel** (left), below Auto / Reset all, only while a
  model is shown - on / off boxes and sliders like the filter rows, no buttons: **Section** (cut
  by a plane; the cut face is shown closed), **Flip side** (keep the other side), **Plane X**,
  **Plane Y** (the plane's tilt), **Plane position** (along its normal, in % of the model's
  radius), **Elevation** (seen from the side ... from above / below), **Smoothing** (1 flat ...
  10: curved surfaces soft, sharp edges stay sharp), **Grid**, **Edges**. Wheel and drag on a
  slider, double-click back to the start value; moving the plane switches the section on.
- **Copy, Save image and the filters' copy** take the model as it is turned and cut (a picture
  of it is made in the background once the model rests).
- With the diagnostics line (D): "3D live: x ms per frame, n frames/s", or "3D: pictures".
- Each model starts seen from the front left, uncut; Grid, Edges and Smoothing stay as last set.

## Combine GIFs

- **Two animated GIFs into one** (user): side by side with Total Commander, the menu's
  **Combine GIFs** takes the GIF under Total Commander's cursor in the **left** panel, then the one
  in the **right** panel, and saves them as one animation in the folder VersariteViewer shows,
  named `<left>_<right>.gif` (`_1`, `_2` … if that exists), and shows it. A short pause (0.5 s)
  after each of the two; the result loops as the left one did. Two ways (user):
  - **Original sizes:** the frames are copied as they are (no colours lost, no re-encoding); GIFs
    of different sizes are centred on the larger canvas.
  - **Scaled to largest GIF (resolution loss!):** the smaller animation is first scaled to fit the
    larger one (aspect ratio kept, centred), with its own colours.
- Cancelled with a note when one of them is not an animated GIF (a still GIF, another file, a
  folder) or both are the same file or have the same content. The entry is greyed unless
  VersariteViewer is side by side with a running Total Commander.

## Opening and browsing

- **Open file ...** (user): in the right-click menu, and the mouse / key command **OpenFile**. A
  file dialog in the folder shown (images, 3D models and archives offered); the file chosen opens
  as from the command line.
- **A folder that isn't there any more** (user: the last session's folder had been renamed -
  "Not found", and nothing reacted): the nearest folder above it that exists is opened instead,
  and a note says which path was missing.
- **Steps while the folders are still being read** (user: during "scanning folders ..." the
  gestures did nothing): a step to the next / previous folder (or past the last image) is kept and
  done as soon as the folders are known ("the folders are still being read: the step follows").
- **An empty folder opened while following Total Commander** kept no subfolders after the
  following was switched off, so the folder swipes and "up" did nothing there. Fixed.
- **Climbing one level up** at the end of a folder tree no longer waits for the image still being
  read (it could cost up to a second per folder).

## Settings added

| Section | Key | Default |
|---|---|---|
| `[Window]` | `SideBySideScreens` | 0 |
| `[DirList<n>]` | `Dynamic` | 0 |
| `[DirList<n>]` | `Slot<n>Pinned` | 0 |
