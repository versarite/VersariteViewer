unit uSortPanel;

{
  Unit: uSortPanel

  Purpose
  -------
  The sort panel (Phase G, G1): a slim column at the right edge of the
  view with one button per sort folder. Left click on a button = copy
  the image there, right click = move it. It opens when the mouse rests
  at the right edge (EdgeDelayMs), has a pin, a "+" to add a folder, a
  small "..." corner per button (the folder menu), and a bottom line
  with the last action (click = undo) or, while the mouse rests on a
  button, that button's full folder.

  Owns
  ----
  - FBitmap: the panel as a picture (BGRABitmap, with alpha), redrawn
    when something changes (FDirty); FVersion counts the redraws so the
    GPU renderer knows when to upload it again.
  - The layout (FRows: one rectangle per visible row), the hover state,
    the scroll offset, the edge timer.

  Knows
  -----
  - TSortFolders (the slots), handed in; read only here.

  Responsibilities
  ----------------
  - Layout for the view's size (elastic): as tall as the view, about
    160 px wide (scaled for the screen's DPI); each button between 36 and
    20 px high (scaled), as many as fit; more slots than fit at the
    minimum: the column scrolls with the wheel.
  - Draw: dark translucent background, per button a folder shape in the
    slot's colour with its number, the name (cut with "..." if long), the
    "..." corner; hover highlight; the pin (lit when pinned); the bottom
    line.
  - Confirmation (Day 21): a button with a copy / move under way has a
    frame in its colour; when the job is done the button lights up in
    its colour with a check mark and fades (0.9 s); red with a cross if
    it failed. Delete and undo flash the bottom line. Unpinned, the
    panel closes only after the flash (at most 3 s after the click);
    if it is closed already, a strip at the right edge flashes instead.
  - Icons (stage 2): a button shows its icon (OnSlotIcon, scaled to
    the button by the owner) with the number small in a corner, else the
    coloured folder; a folder that was not found (OnSlotMissing) is
    drawn grey and its bottom line says so.
  - Icon preview (Day 24): while the mouse rests on a button with an
    icon, the icon large (OnSlotPreview: up to its own size, 256 px at
    most) in a box to the left of the panel, level with the button. The
    picture then is FPreviewW wider than the panel (Left moves left;
    hit tests use PanelLeft); the box takes no clicks.
  - Containers (M2c, the microscopy edition only; none in MView): a
    group on top, above the buttons, one row per container file (.lif) -
    a grey folder with a star in its kind's colour (amber .lif, cyan
    stack, violet other), where the numbers used to be. Since Day 25
    (user) only the container the wheel is in, transient; a Pinned one
    would have a "..." corner (no owner pins any more). Contents mode (ShowContents): the open container's
    images instead of the buttons, a "back" row first, each with its
    thumbnail (OnEntryThumb), the one shown in the view in yellow
    (SetCurrentEntry, scrolled into sight); the one under the mouse large in the box
    left of the panel (OnEntryPreview).
  - Hit test: which part is at a point (button, its "..." corner, "+",
    pin, bottom line, empty panel, outside; a container, its "...",
    "back", an image).
  - Edge opening: NoteMouse (every mouse move) and Tick (the viewer's
    50 ms timer) open the panel after the mouse has rested EdgeDelayMs at
    the right edge with no button down; unpinned, it closes again when
    the mouse has been away from it for CloseDelayMs.

  Does NOT
  --------
  - Copy, move or delete files, or change the slots (TMView does, from
    the hit test).
  - Show itself: the renderers draw Bitmap at (Left, Top) on top of
    everything (uRenderer, uGLRenderer).
  - Read the disk (no folder checks, no icon files yet: Stage 2).

  Threads
  -------
  UI thread only.

  Uses (MView units)
  ------------------
  interface:      uSortFolders
  Libraries:      Classes, SysUtils, Math, Types, Graphics, BGRABitmap,
                  BGRABitmapTypes, LazUTF8

  Used by
  -------
  uMView
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  Math,
  Types,
  Graphics,
  BGRABitmap,
  BGRABitmapTypes,
  LazUTF8,
  uSortFolders;

type

  { ppContainer .. ppEntry: the microscopy edition's containers (M2c);
    never hit in MView (no containers). }
  TPanelPart = (ppNone, ppPanel, ppSlot, ppSlotMenu, ppAdd, ppPin, ppFooter,
    ppContainer, ppContainerMenu, ppBack, ppEntry,
    ppListPrev, ppListNext);   { the header's arrows: other folder lists (Day 27) }

  TPanelHit = record
    Part: TPanelPart;
    Slot: Integer;      { ppSlot / ppSlotMenu: the slot; ppContainer(Menu): the
                          container; ppEntry: the entry; else -1 }
  end;

  { The panel shows the sort buttons (and containers), or a container's
    images (M2c). }
  TPanelMode = (pmSlots, pmContents);

  { A container file (.lif) in the panel (M2c): drawn like a folder with
    a star in its kind's colour. }
  TPanelContainer = record
    Path: string;
    Name: string;
    Kind: Integer;      { 0 = .lif (amber), 1 = stack (cyan), 2 = other (violet) }
    Pinned: Boolean;    { a "..." corner; unused since Day 25 (containers are transient) }
  end;

  { An image inside the open container. }
  TPanelEntry = record
    Name: string;
    VirtualName: string;
    Frames: Integer;      { a stack (> 1): an animation mark on its thumbnail (Day 26) }
  end;

  { Entry AEntry's thumbnail, at most ASize px square; nil = not there yet
    (a grey square). The picture stays the owner's. }
  TEntryThumbEvent = function(AEntry, ASize: Integer): TBGRABitmap of object;
  { Its large picture for the box left of the panel; nil = none yet. }
  TEntryPreviewEvent = function(AEntry, AMaxSize: Integer; out ACaption: string): TBGRABitmap of object;
  { What the file says about entry AEntry (Day 26: the microscope's
    details), laid over the bottom of its large picture; nil = nothing. }
  TEntryDetailsEvent = function(AEntry: Integer): TStringArray of object;

  { The icon of slot ASlot as an ASize x ASize picture; nil = draw the
    coloured folder. The picture stays the owner's. }
  TSlotIconEvent = function(ASlot, ASize: Integer): TBGRABitmap of object;
  { Slot ASlot's folder was not found (drawn greyed). }
  TSlotMissingEvent = function(ASlot: Integer): Boolean of object;
  { The large preview of slot ASlot's icon (Day 24), at most AMaxSize px
    square, and a line under it (ACaption); nil = no preview (no icon).
    The picture stays the owner's. }
  TSlotPreviewEvent = function(ASlot, AMaxSize: Integer; out ACaption: string): TBGRABitmap of object;

  TSortPanel = class(TObject)
  private
    FFolders: TSortFolders;
    FBitmap: TBGRABitmap;
    FVersion: Cardinal;
    FDirty: Boolean;
    FVisible: Boolean;
    FPinned: Boolean;
    FScale: Double;

    FViewW, FViewH: Integer;
    FWidth: Integer;
    FHeaderH, FFooterH, FRowH: Integer;
    FLines: Integer;             { [Sort] PanelLines: rows the panel is laid out for; 0 = elastic }
    FFirstRow: Integer;          { scroll: index of the first row shown }
    FRowsShown: Integer;
    FHover: TPanelHit;
    FFooterText: string;
    FBusy: Boolean;

    FEdgeDelayMs: Integer;
    FEdgeWidth: Integer;         { px at 96 dpi }
    FEdgeSinceMs: Double;        { mouse at the edge since; 0 = not }
    FAwaySinceMs: Double;        { mouse away from the open panel since; 0 = on it }
    FMouseX, FMouseY: Integer;
    FButtonDown: Boolean;
    FHold: Boolean;              { opened by a command: stays until the mouse has been on it }
    { Confirmation (Day 21, user: "a flash in the folder icon color"):
      the button of a finished copy / move lights up in its colour and
      fades (red with a cross if it failed); the bottom line for delete
      and undo. A button with a job under way has a frame. }
    FFlashSlot: Integer;         { -1 = the bottom line }
    FFlashOK: Boolean;
    FFlashStartMs: Double;       { 0 = no flash }
    FFlashLevel: Double;         { 1 .. 0 while it fades }
    FPending: array of Integer;  { per slot: jobs under way }
    FCloseWhenDone: Boolean;     { unpinned: close once the flash is over }
    FCloseDeadlineMs: Double;    { ... or at the latest then }
    FStrip: TBGRABitmap;         { the flash as a strip at the edge, panel closed }
    FOnSlotIcon: TSlotIconEvent;
    FOnSlotMissing: TSlotMissingEvent;
    FOnSlotPreview: TSlotPreviewEvent;
    { The hovered button's icon, large, to the left of the panel: the
      panel and the preview as one picture (FOut), FPreviewW px wider on
      the left than the panel; 0 = no preview (FBitmap alone). }
    FOut: TBGRABitmap;
    FPreviewW: Integer;
    { Containers (M2c): a group above the "+" row; and the open one's
      images (contents mode). Empty in MView. }
    FContainers: array of TPanelContainer;
    FMode: TPanelMode;
    FEntries: array of TPanelEntry;
    FContentsTitle: string;
    FCurrentEntry: string;       { the image shown (virtual name): drawn yellow }
    FOnEntryThumb: TEntryThumbEvent;
    FOnEntryPreview: TEntryPreviewEvent;
    FOnEntryDetails: TEntryDetailsEvent;
    procedure ComposePreview;
    procedure RevealCurrent;
    function SlotMissing(ASlot: Integer): Boolean;
    procedure DrawStar(ACX, ACY, ARadius: Single; AColor: TBGRAPixel);
    procedure DrawContainerRow(AIndex: Integer; const R: TRect; APad, AIconW: Integer;
      AText, ADim: TBGRAPixel);
    procedure DrawContentsRow(ARow: Integer; const R: TRect; APad: Integer;
      AText, ADim: TBGRAPixel);
    function FlashColor: TBGRAPixel;
    function StripMode: Boolean;
    procedure RedrawStrip;
    procedure DrawMark(const R: TRect; AOK: Boolean; AAlpha: Byte);
    procedure DrawArrow(const R: TRect; ADir: Integer; AColor: TBGRAPixel);

    function RowCount: Integer;  { containers (on top) + the "+" row + slots }
    procedure SetLines(AValue: Integer);
    function RowRect(ARow: Integer): TRect;
    function MenuRect(const ARow: TRect): TRect;
    function PinRect: TRect;
    function ArrowRect(ADir: Integer): TRect;
    function ShowsArrows: Boolean;
    function AddRows: Integer;
    function FooterRect: TRect;
    procedure Redraw;
    procedure DrawFolder(X, Y, W, H: Integer; AColor: TBGRAPixel; const ANumber: string);
    procedure SetPinned(AValue: Boolean);
    procedure SetFooterText(const AValue: string);
    procedure SetBusy(AValue: Boolean);
  public
    constructor Create(AFolders: TSortFolders);
    destructor Destroy; override;

    { The view's size in pixels and the screen's scale (PixelsPerInch /
      96). Call when the view is resized; the layout follows. }
    procedure SetViewSize(AWidth, AHeight: Integer; AScale: Double);
    { The slots changed (a folder, colour or order): redraw. }
    procedure Changed;
    { Scrolls slot ASlot into sight (a folder just added, Day 27). }
    procedure RevealSlot(ASlot: Integer);
    { The first row on top (another folder list, Day 27). }
    procedure ScrollToTop;

    { AHold: opened by the menu or a key, not at the edge: an unpinned
      panel stays open until the mouse has been on it (and then left). }
    procedure Show(AHold: Boolean = False);
    procedure Hide;

    function HitTest(AX, AY: Integer): TPanelHit;
    function Contains(AX, AY: Integer): Boolean;
    { Mouse position (every move), for hover and the edge timer. True
      if the picture changed (hover). }
    function NoteMouse(AX, AY: Integer; AButtonDown: Boolean; ANowMs: Double): Boolean;
    { The wheel over the panel: scroll. True if it scrolled. }
    function Scroll(ANotches: Integer): Boolean;
    { Edge opening and closing, the flash's fading; True if the picture
      changed (call Bitmap again). }
    function Tick(ANowMs: Double): Boolean;

    { A copy / move into ASlot was queued (-1: delete, undo): the button
      gets a frame until it is done. }
    procedure JobStarted(ASlot: Integer);
    { It is done: the button flashes (in its colour, or red if AOK is
      False). With the panel closed, a strip at the right edge flashes. }
    procedure JobDone(ASlot: Integer; AOK: Boolean; ANowMs: Double);
    { Just the flash (e.g. red for "already in that folder"). }
    procedure Flash(ASlot: Integer; AOK: Boolean; ANowMs: Double);
    { Unpinned: close after this action, once its flash has been seen
      (at most CloseWaitMs). Pinned: nothing. }
    procedure CloseAfterAction(ANowMs: Double);
    { The mouse left the window, or the window lost the focus: an
      unpinned panel closes as when the mouse leaves it. }
    procedure MouseGone(ANowMs: Double);

    { The picture, up to date; nil while hidden (except while a flash
      shows as a strip at the edge: then that, at Left / Top). }
    function Bitmap: TBGRABitmap;
    { Where the picture goes: Left is FPreviewW left of the panel while
      the large icon preview shows. }
    function Left: Integer;
    function Top: Integer;
    { The panel's own left edge (hit tests, the folder menu). }
    function PanelLeft: Integer;

    property Visible: Boolean read FVisible;
    property Pinned: Boolean read FPinned write SetPinned;
    { [Sort] PanelLines (Day 27): rows laid out for; 0 = elastic (as
      before). MaxPanelLines: as many as fit at the smallest row. }
    property Lines: Integer read FLines write SetLines;
    function MaxPanelLines: Integer;
    property Version: Cardinal read FVersion;
    property EdgeDelayMs: Integer read FEdgeDelayMs write FEdgeDelayMs;
    { How close to the right edge counts as "at the edge" (px at 96 dpi,
      scaled). }
    property EdgeWidth: Integer read FEdgeWidth write FEdgeWidth;
    { The bottom line when no button is hovered: the last action. }
    property FooterText: string read FFooterText write SetFooterText;
    { A copy / move is running: shown in the header. }
    property Busy: Boolean read FBusy write SetBusy;
    { Stage 2: icons and missing folders, asked for while drawing. }
    property OnSlotIcon: TSlotIconEvent read FOnSlotIcon write FOnSlotIcon;
    property OnSlotMissing: TSlotMissingEvent read FOnSlotMissing write FOnSlotMissing;
    property OnSlotPreview: TSlotPreviewEvent read FOnSlotPreview write FOnSlotPreview;

    { Containers (M2c). SetContainers: pinned first, then the current
      folder's; redraws only if the list changed. }
    procedure SetContainers(const AItems: array of TPanelContainer);
    function ContainerCount: Integer;
    function Container(AIndex: Integer): TPanelContainer;
    { A container's images, instead of the buttons; a "back" row first. }
    procedure ShowContents(const ATitle: string; const AEntries: array of TPanelEntry);
    procedure ShowSlots;
    function EntryCount: Integer;
    function Entry(AIndex: Integer): TPanelEntry;
    { A thumbnail arrived: redraw (Bitmap gives a new version). }
    procedure ThumbsChanged;
    { The image shown in the view (virtual name; '' = none): its row in
      the container's list is drawn yellow and scrolled into sight. True
      if the list shows it and it changed (redraw). }
    function SetCurrentEntry(const AVirtualName: string): Boolean;
    property Mode: TPanelMode read FMode;
    property ContentsTitle: string read FContentsTitle;
    property OnEntryThumb: TEntryThumbEvent read FOnEntryThumb write FOnEntryThumb;
    property OnEntryPreview: TEntryPreviewEvent read FOnEntryPreview write FOnEntryPreview;
    property OnEntryDetails: TEntryDetailsEvent read FOnEntryDetails write FOnEntryDetails;
  end;

implementation

uses
  uTypes;

const
  CloseDelayMs = 600;      { unpinned: mouse away this long closes the panel }
  FlashMs = 900;           { the confirmation flash: full for FlashHoldMs, then fading }
  FlashHoldMs = 200;
  CloseWaitMs = 3000;      { unpinned: closes at the latest this long after an action }
  StripPx = 8;             { the flash strip with the panel closed (scaled) }

function ScaleI(AValue: Integer; AScale: Double): Integer;
begin
  Result := Max(1, Round(AValue * AScale));
end;

{ TSortPanel }

constructor TSortPanel.Create(AFolders: TSortFolders);
begin
  inherited Create;
  FFolders := AFolders;
  FScale := 1;
  FEdgeDelayMs := 500;
  FEdgeWidth := 12;
  FHover.Part := ppNone;
  FHover.Slot := -1;
  FFlashSlot := -1;
  FDirty := True;
end;

destructor TSortPanel.Destroy;
begin
  FStrip.Free;
  FOut.Free;
  FBitmap.Free;
  inherited Destroy;
end;

procedure TSortPanel.SetLines(AValue: Integer);
begin
  AValue := Max(0, AValue);
  if AValue = FLines then
    Exit;
  FLines := AValue;
  Changed;
end;

function TSortPanel.MaxPanelLines: Integer;
begin
  Result := Max(1, Max(0, FViewH - FHeaderH - FFooterH) div Max(1, ScaleI(20, FScale)));
end;

function TSortPanel.RowCount: Integer;
begin
  if FMode = pmContents then
    Result := 1 + Length(FEntries)
  else
    Result := FFolders.Count + AddRows + Length(FContainers);
end;

procedure TSortPanel.SetContainers(const AItems: array of TPanelContainer);
var
  I: Integer;
  Same: Boolean;
begin
  Same := Length(AItems) = Length(FContainers);
  if Same then
    for I := 0 to High(AItems) do
      if (AItems[I].Path <> FContainers[I].Path) or (AItems[I].Pinned <> FContainers[I].Pinned)
        or (AItems[I].Kind <> FContainers[I].Kind) or (AItems[I].Name <> FContainers[I].Name) then
      begin
        Same := False;
        Break;
      end;
  if Same then
    Exit;
  { The group is on top: when its size changes every row below moves,
    so the hover is no longer where the mouse is. }
  Same := Length(AItems) = Length(FContainers);
  SetLength(FContainers, Length(AItems));
  for I := 0 to High(AItems) do
    FContainers[I] := AItems[I];
  if (not Same) or ((FHover.Part in [ppContainer, ppContainerMenu]) and (FHover.Slot > High(FContainers))) then
  begin
    FHover.Part := ppNone;
    FHover.Slot := -1;
  end;
  Changed;
end;

function TSortPanel.ContainerCount: Integer;
begin
  Result := Length(FContainers);
end;

function TSortPanel.Container(AIndex: Integer): TPanelContainer;
begin
  Result := FContainers[AIndex];
end;

procedure TSortPanel.ShowContents(const ATitle: string; const AEntries: array of TPanelEntry);
var
  I: Integer;
begin
  { Another list (a stack's frames after its .lif's images, Day 26): from
    its top. }
  if (FMode <> pmContents) or (ATitle <> FContentsTitle) then
    FFirstRow := 0;
  FMode := pmContents;
  FContentsTitle := ATitle;
  SetLength(FEntries, Length(AEntries));
  for I := 0 to High(AEntries) do
    FEntries[I] := AEntries[I];
  FHover.Part := ppNone;
  FHover.Slot := -1;
  Changed;
  RevealCurrent;
end;

function TSortPanel.SetCurrentEntry(const AVirtualName: string): Boolean;
begin
  Result := False;
  if AVirtualName = FCurrentEntry then
    Exit;
  FCurrentEntry := AVirtualName;
  if FMode <> pmContents then
    Exit;
  RevealCurrent;
  FDirty := True;
  Result := True;
end;

{ Contents mode: the current image's row into sight (the layout is
  fresh: Changed ran). Row 0 is "back", entry I is row I + 1. }
procedure TSortPanel.RevealCurrent;
var
  I, Row: Integer;
begin
  if (FMode <> pmContents) or (FCurrentEntry = '') or (FRowsShown <= 0) then
    Exit;
  for I := 0 to High(FEntries) do
    if SameText(FEntries[I].VirtualName, FCurrentEntry) then
    begin
      Row := I + 1;
      if Row < FFirstRow then
        FFirstRow := Row
      else if Row >= FFirstRow + FRowsShown then
        FFirstRow := Row - FRowsShown + 1;
      FFirstRow := EnsureRange(FFirstRow, 0, Max(0, RowCount - FRowsShown));
      FDirty := True;
      Exit;
    end;
end;

procedure TSortPanel.ShowSlots;
begin
  if FMode = pmSlots then
    Exit;
  FMode := pmSlots;
  FEntries := nil;
  FContentsTitle := '';
  FFirstRow := 0;
  FHover.Part := ppNone;
  FHover.Slot := -1;
  Changed;
end;

function TSortPanel.EntryCount: Integer;
begin
  Result := Length(FEntries);
end;

function TSortPanel.Entry(AIndex: Integer): TPanelEntry;
begin
  Result := FEntries[AIndex];
end;

procedure TSortPanel.ThumbsChanged;
begin
  FDirty := True;
end;

procedure TSortPanel.SetViewSize(AWidth, AHeight: Integer; AScale: Double);
var
  Avail, MinH, MaxH: Integer;
begin
  if AScale <= 0 then
    AScale := 1;
  FViewW := Max(0, AWidth);
  FViewH := Max(0, AHeight);
  FScale := AScale;
  FWidth := Min(ScaleI(160, FScale), Max(ScaleI(60, FScale), FViewW div 2));
  FHeaderH := ScaleI(26, FScale);
  FFooterH := ScaleI(52, FScale);   { three short lines }
  MinH := ScaleI(20, FScale);
  MaxH := ScaleI(36, FScale);
  Avail := Max(0, FViewH - FHeaderH - FFooterH);
  if FLines > 0 then
  begin
    { [Sort] PanelLines (Day 27, testers: with many folders the rows got
      too small): the rows fill the panel for that many lines, larger
      than the elastic rows may be; at most as many as fit at the
      smallest row (MaxPanelLines); more rows than that: the wheel
      scrolls. }
    FRowH := Avail div Max(1, Min(FLines, MaxPanelLines));
    FRowH := EnsureRange(FRowH, MinH, 3 * MaxH);
  end
  else
  begin
    { Elastic: as large as fits, within the limits. }
    if RowCount > 0 then
      FRowH := Avail div RowCount
    else
      FRowH := MaxH;
    FRowH := EnsureRange(FRowH, MinH, MaxH);
  end;
  FRowsShown := Max(1, Avail div FRowH);
  { More than fit: a line for the "1-12 of 20 (wheel)" hint. }
  if RowCount > FRowsShown then
    FRowsShown := Max(1, (Avail - ScaleI(16, FScale)) div FRowH);
  FFirstRow := EnsureRange(FFirstRow, 0, Max(0, RowCount - FRowsShown));
  FDirty := True;
end;

procedure TSortPanel.Changed;
begin
  { The row count may have changed: the same layout rules again. }
  SetViewSize(FViewW, FViewH, FScale);
end;

procedure TSortPanel.ScrollToTop;
begin
  FFirstRow := 0;
  FHover.Part := ppNone;
  FHover.Slot := -1;
  FDirty := True;
end;

procedure TSortPanel.RevealSlot(ASlot: Integer);
var
  Row: Integer;
begin
  if (FMode <> pmSlots) or (ASlot < 0) or (FRowsShown <= 0) then
    Exit;
  Row := Length(FContainers) + AddRows + ASlot;
  if Row < FFirstRow then
    FFirstRow := Row
  else if Row >= FFirstRow + FRowsShown then
    FFirstRow := Row - FRowsShown + 1;
  FFirstRow := EnsureRange(FFirstRow, 0, Max(0, RowCount - FRowsShown));
  FDirty := True;
end;

procedure TSortPanel.Show(AHold: Boolean);
begin
  FHold := AHold;
  if AHold then
    FCloseWhenDone := False;   { asked for: stays }
  FAwaySinceMs := 0;
  if FVisible then
    Exit;
  FVisible := True;
  FDirty := True;
end;

procedure TSortPanel.Hide;
begin
  FCloseWhenDone := False;
  if not FVisible then
    Exit;
  FVisible := False;
  FPreviewW := 0;
  FDirty := True;      { a new picture (the strip, or none): a new version }
  FEdgeSinceMs := 0;
  FHover.Part := ppNone;
  FHover.Slot := -1;
end;

procedure TSortPanel.SetPinned(AValue: Boolean);
begin
  if FPinned = AValue then
    Exit;
  FPinned := AValue;
  FDirty := True;
end;

procedure TSortPanel.SetFooterText(const AValue: string);
begin
  if FFooterText = AValue then
    Exit;
  FFooterText := AValue;
  FDirty := True;
end;

procedure TSortPanel.SetBusy(AValue: Boolean);
begin
  if FBusy = AValue then
    Exit;
  FBusy := AValue;
  FDirty := True;
end;

function TSortPanel.Left: Integer;
begin
  if StripMode then
    Result := FViewW - ScaleI(StripPx, FScale)
  else
    Result := PanelLeft - FPreviewW;
end;

function TSortPanel.PanelLeft: Integer;
begin
  Result := FViewW - FWidth;
end;

function TSortPanel.Top: Integer;
begin
  Result := 0;
end;

{ Panel coordinates (0,0 = the panel's top left). }
function TSortPanel.RowRect(ARow: Integer): TRect;
var
  Y: Integer;
begin
  Y := FHeaderH + (ARow - FFirstRow) * FRowH;
  Result := Rect(0, Y, FWidth, Y + FRowH);
end;

function TSortPanel.MenuRect(const ARow: TRect): TRect;
var
  W: Integer;
begin
  W := Min(ScaleI(22, FScale), ARow.Height);
  Result := Rect(ARow.Right - W, ARow.Top, ARow.Right, ARow.Bottom);
end;

function TSortPanel.PinRect: TRect;
begin
  Result := Rect(FWidth - FHeaderH, 0, FWidth, FHeaderH);
end;

{ The header's arrows (Day 27): ADir = -1 the left one, 1 the right one,
  left of the pin. }
function TSortPanel.ArrowRect(ADir: Integer): TRect;
var
  W: Integer;
begin
  W := FHeaderH;
  if ADir > 0 then
    Result := Rect(FWidth - FHeaderH - W, 0, FWidth - FHeaderH, FHeaderH)
  else
    Result := Rect(FWidth - FHeaderH - 2 * W, 0, FWidth - FHeaderH - W, FHeaderH);
end;

{ The arrows: the folder lists, not a container's images nor Rapid
  Selection. }
function TSortPanel.ShowsArrows: Boolean;
begin
  Result := (FMode = pmSlots) and not FFolders.Rapid;
end;

{ The "+ add folder" row: none in Rapid Selection (a fixed list). }
function TSortPanel.AddRows: Integer;
begin
  if FFolders.Rapid then
    Result := 0
  else
    Result := 1;
end;

function TSortPanel.FooterRect: TRect;
begin
  Result := Rect(0, FViewH - FFooterH, FWidth, FViewH);
end;

function TSortPanel.Contains(AX, AY: Integer): Boolean;
begin
  Result := FVisible and (AX >= PanelLeft) and (AX < PanelLeft + FWidth) and (AY >= 0) and (AY < FViewH);
end;

function TSortPanel.HitTest(AX, AY: Integer): TPanelHit;
var
  PX, PY, Row: Integer;
  R: TRect;
begin
  Result.Part := ppNone;
  Result.Slot := -1;
  if not Contains(AX, AY) then
    Exit;
  PX := AX - PanelLeft;
  PY := AY - Top;
  Result.Part := ppPanel;
  if PtInRect(PinRect, Point(PX, PY)) then
  begin
    Result.Part := ppPin;
    Exit;
  end;
  if ShowsArrows and PtInRect(ArrowRect(-1), Point(PX, PY)) then
  begin
    Result.Part := ppListPrev;
    Exit;
  end;
  if ShowsArrows and PtInRect(ArrowRect(1), Point(PX, PY)) then
  begin
    Result.Part := ppListNext;
    Exit;
  end;
  if PtInRect(FooterRect, Point(PX, PY)) then
  begin
    Result.Part := ppFooter;
    Exit;
  end;
  if (PY < FHeaderH) or (FRowH <= 0) then
    Exit;
  Row := FFirstRow + (PY - FHeaderH) div FRowH;
  if (Row - FFirstRow >= FRowsShown) or (Row >= RowCount) then
    Exit;
  R := RowRect(Row);
  if R.Bottom > FViewH - FFooterH then
    Exit;
  if FMode = pmContents then
  begin
    { A container's images (M2c): "back", then the images. }
    if Row = 0 then
      Result.Part := ppBack
    else
    begin
      Result.Part := ppEntry;
      Result.Slot := Row - 1;
    end;
    Exit;
  end;
  if Row < Length(FContainers) then
  begin
    { A container (M2c), on top: its "..." corner only when pinned. }
    Result.Slot := Row;
    if FContainers[Result.Slot].Pinned and PtInRect(MenuRect(R), Point(PX, PY)) then
      Result.Part := ppContainerMenu
    else
      Result.Part := ppContainer;
    Exit;
  end;
  { "+ add folder" first (Day 27, testers), then the slots. }
  Row := Row - Length(FContainers);
  if (Row = 0) and (AddRows > 0) then
    Result.Part := ppAdd
  else
  begin
    Result.Slot := Row - AddRows;
    if PtInRect(MenuRect(R), Point(PX, PY)) then
      Result.Part := ppSlotMenu
    else
      Result.Part := ppSlot;
  end;
end;

function TSortPanel.NoteMouse(AX, AY: Integer; AButtonDown: Boolean; ANowMs: Double): Boolean;
var
  Hit: TPanelHit;
begin
  Result := False;
  FMouseX := AX;
  FMouseY := AY;
  FButtonDown := AButtonDown;

  if FVisible then
  begin
    Hit := HitTest(AX, AY);
    if (Hit.Part <> FHover.Part) or (Hit.Slot <> FHover.Slot) then
    begin
      FHover := Hit;
      FDirty := True;
      Result := True;
    end;
    if Hit.Part <> ppNone then
      FHold := False;
    if (Hit.Part = ppNone) and not FHold then
    begin
      if FAwaySinceMs = 0 then
        FAwaySinceMs := ANowMs;
    end
    else
      FAwaySinceMs := 0;
  end
  else
  begin
    { The edge timer: only while resting there with no button down (a
      right-drag gesture ending at the edge doesn't open it). }
    if (not AButtonDown) and (FEdgeDelayMs > 0) and (FViewW > 0)
      and (AX >= FViewW - ScaleI(FEdgeWidth, FScale)) then
    begin
      if FEdgeSinceMs = 0 then
        FEdgeSinceMs := ANowMs;
    end
    else
      FEdgeSinceMs := 0;
  end;
end;

function TSortPanel.Tick(ANowMs: Double): Boolean;
var
  T: Double;
  AnyPending: Boolean;
  I: Integer;
begin
  Result := False;

  { The flash fades. }
  if FFlashStartMs > 0 then
  begin
    T := ANowMs - FFlashStartMs;
    if T >= FlashMs then
    begin
      FFlashStartMs := 0;
      FFlashLevel := 0;
    end
    else if T <= FlashHoldMs then
      FFlashLevel := 1
    else
      FFlashLevel := 1 - (T - FlashHoldMs) / (FlashMs - FlashHoldMs);
    FDirty := True;
    Result := True;
  end;

  { Unpinned, after an action: closes once its job is done and the
    flash has been seen (or after CloseWaitMs, a slow copy). }
  if FCloseWhenDone then
  begin
    AnyPending := False;
    for I := 0 to High(FPending) do
      if FPending[I] > 0 then
        AnyPending := True;
    if FPinned or not FVisible then
      FCloseWhenDone := False
    else if ((not AnyPending) and (FFlashStartMs = 0)) or (ANowMs >= FCloseDeadlineMs) then
    begin
      Hide;
      Exit(True);
    end
    else
      Exit;   { not closed by the mouse leaving meanwhile }
  end;

  if not FVisible then
  begin
    if (FEdgeSinceMs > 0) and (not FButtonDown) and (ANowMs - FEdgeSinceMs >= FEdgeDelayMs) then
    begin
      FEdgeSinceMs := 0;
      Show;
      FHover := HitTest(FMouseX, FMouseY);
      Result := True;
    end;
  end
  else if (not FPinned) and (FAwaySinceMs > 0) and (ANowMs - FAwaySinceMs >= CloseDelayMs) then
  begin
    Hide;
    Result := True;
  end;
end;

procedure TSortPanel.JobStarted(ASlot: Integer);
begin
  if ASlot < 0 then
    Exit;
  if ASlot > High(FPending) then
    SetLength(FPending, ASlot + 1);
  Inc(FPending[ASlot]);
  FDirty := True;
end;

procedure TSortPanel.JobDone(ASlot: Integer; AOK: Boolean; ANowMs: Double);
begin
  if (ASlot >= 0) and (ASlot <= High(FPending)) and (FPending[ASlot] > 0) then
    Dec(FPending[ASlot]);
  Flash(ASlot, AOK, ANowMs);
end;

procedure TSortPanel.Flash(ASlot: Integer; AOK: Boolean; ANowMs: Double);
begin
  if ASlot >= FFolders.Count then
    ASlot := -1;
  FFlashSlot := ASlot;
  FFlashOK := AOK;
  FFlashStartMs := Max(1.0, ANowMs);
  FFlashLevel := 1;
  FDirty := True;
end;

procedure TSortPanel.CloseAfterAction(ANowMs: Double);
begin
  if FPinned or not FVisible then
    Exit;
  FCloseWhenDone := True;
  FCloseDeadlineMs := ANowMs + CloseWaitMs;
end;

function TSortPanel.FlashColor: TBGRAPixel;
var
  C: LongWord;
begin
  if not FFlashOK then
    Result := BGRA(230, 40, 40, 255)
  else if (FFlashSlot >= 0) and (FFlashSlot < FFolders.Count) then
  begin
    C := SlotColorValue(FFolders.Slot(FFlashSlot).Color);
    Result := BGRA(C and $FF, (C shr 8) and $FF, (C shr 16) and $FF, 255);
  end
  else
    Result := BGRA(220, 220, 220, 255);   { delete / undo: neutral }
end;

{ The panel is closed but a flash is still to be seen: a strip. }
function TSortPanel.StripMode: Boolean;
begin
  Result := (not FVisible) and (FFlashStartMs > 0) and (FViewW > 0) and (FViewH > 0);
end;

procedure TSortPanel.RedrawStrip;
var
  W: Integer;
  C: TBGRAPixel;
begin
  FDirty := False;
  Inc(FVersion);
  W := ScaleI(StripPx, FScale);
  if FStrip = nil then
    FStrip := TBGRABitmap.Create(W, FViewH)
  else
    FStrip.SetSize(W, FViewH);
  C := FlashColor;
  C.alpha := Round(230 * FFlashLevel);
  FStrip.Fill(C);
end;

{ A check mark (done) or a cross (failed) in R. }
procedure TSortPanel.DrawMark(const R: TRect; AOK: Boolean; AAlpha: Byte);
var
  X, Y, S, W: Single;
  C: TBGRAPixel;
begin
  C := BGRA(255, 255, 255, AAlpha);
  S := Min(R.Width, R.Height) * 0.30;
  X := R.Left + R.Width / 2;
  Y := R.Top + R.Height / 2;
  W := Max(2.0, FScale * 2.5);
  if AOK then
    FBitmap.DrawPolyLineAntialias([PointF(X - S, Y), PointF(X - S * 0.3, Y + S * 0.7),
      PointF(X + S, Y - S * 0.7)], C, W)
  else
  begin
    FBitmap.DrawLineAntialias(X - S * 0.7, Y - S * 0.7, X + S * 0.7, Y + S * 0.7, C, W);
    FBitmap.DrawLineAntialias(X - S * 0.7, Y + S * 0.7, X + S * 0.7, Y - S * 0.7, C, W);
  end;
end;

procedure TSortPanel.MouseGone(ANowMs: Double);
begin
  FEdgeSinceMs := 0;
  if FVisible and (not FHold) and (FAwaySinceMs = 0) then
    FAwaySinceMs := ANowMs;
  if FVisible and (FHover.Part <> ppNone) then
  begin
    FHover.Part := ppNone;
    FHover.Slot := -1;
    FDirty := True;
  end;
end;

function TSortPanel.Scroll(ANotches: Integer): Boolean;
var
  Old: Integer;
begin
  Old := FFirstRow;
  FFirstRow := EnsureRange(FFirstRow - ANotches, 0, Max(0, RowCount - FRowsShown));
  Result := FFirstRow <> Old;
  if Result then
    FDirty := True;
end;

function TSortPanel.Bitmap: TBGRABitmap;
begin
  if StripMode then
  begin
    if FDirty or (FStrip = nil) then
      RedrawStrip;
    Exit(FStrip);
  end;
  if not FVisible then
    Exit(nil);
  if FDirty or (FBitmap = nil) then
    Redraw;
  if (FPreviewW > 0) and (FOut <> nil) then
    Result := FOut
  else
    Result := FBitmap;
end;

function TSortPanel.SlotMissing(ASlot: Integer): Boolean;
begin
  Result := Assigned(FOnSlotMissing) and FOnSlotMissing(ASlot);
end;

{ A five-pointed star (a container's mark, M2c, where the slot numbers
  used to be). }
procedure TSortPanel.DrawStar(ACX, ACY, ARadius: Single; AColor: TBGRAPixel);
var
  Pts: array[0..9] of TPointF;
  I: Integer;
  A, R: Single;
begin
  for I := 0 to 9 do
  begin
    A := -Pi / 2 + I * Pi / 5;
    if Odd(I) then
      R := ARadius * 0.45
    else
      R := ARadius;
    Pts[I] := PointF(ACX + R * Cos(A), ACY + R * Sin(A));
  end;
  FBitmap.FillPolyAntialias(Pts, AColor);
  FBitmap.DrawPolygonAntialias(Pts, BGRA(0, 0, 0, 150), Max(1.0, FScale));
end;

{ A folder: a tab and a body in AColor, the number on it. }
{ A small triangle pointing left (ADir < 0) or right. }
procedure TSortPanel.DrawArrow(const R: TRect; ADir: Integer; AColor: TBGRAPixel);
var
  CX, CY, H: Single;
begin
  CX := (R.Left + R.Right) / 2;
  CY := (R.Top + R.Bottom) / 2;
  H := R.Height * 0.22;
  if ADir < 0 then
    FBitmap.FillPolyAntialias([PointF(CX + H * 0.6, CY - H), PointF(CX + H * 0.6, CY + H),
      PointF(CX - H * 0.8, CY)], AColor)
  else
    FBitmap.FillPolyAntialias([PointF(CX - H * 0.6, CY - H), PointF(CX - H * 0.6, CY + H),
      PointF(CX + H * 0.8, CY)], AColor);
end;

procedure TSortPanel.DrawFolder(X, Y, W, H: Integer; AColor: TBGRAPixel; const ANumber: string);
var
  TabW, TabH: Integer;
  Dark: TBGRAPixel;
  TS: TSize;
begin
  TabW := W * 2 div 5;
  TabH := Max(2, H div 6);
  Dark := BGRA(AColor.red * 3 div 4, AColor.green * 3 div 4, AColor.blue * 3 div 4, 255);
  FBitmap.FillRoundRectAntialias(X, Y, X + TabW, Y + TabH * 2, 2, 2, Dark);
  FBitmap.FillRoundRectAntialias(X, Y + TabH, X + W, Y + H, 3, 3, AColor);
  if ANumber <> '' then
  begin
    FBitmap.FontHeight := Max(8, (H - TabH) * 3 div 4);
    FBitmap.FontStyle := [fsBold];
    TS := FBitmap.TextSize(ANumber);
    FBitmap.TextOut(X + (W - TS.cx) div 2, Y + TabH + (H - TabH - TS.cy) div 2,
      ANumber, BGRA(255, 255, 255, 235));
    FBitmap.FontStyle := [];
  end;
end;

{ The lines of AText (split at line endings). }
function TextLines(const AText: string): TStringArray;
var
  L: TStringList;
  I: Integer;
begin
  L := TStringList.Create;
  try
    L.Text := AText;
    SetLength(Result, L.Count);
    for I := 0 to L.Count - 1 do
      Result[I] := L[I];
  finally
    L.Free;
  end;
end;

{ Cuts AText to AWidth pixels, with "..." at the end. }
function FitText(ABitmap: TBGRABitmap; const AText: string; AWidth: Integer): string;
var
  N: Integer;
begin
  Result := AText;
  if ABitmap.TextSize(Result).cx <= AWidth then
    Exit;
  { In characters, not bytes: "Präparate" must not be cut inside the ä. }
  N := UTF8Length(AText);
  while (N > 0) and (ABitmap.TextSize(UTF8Copy(AText, 1, N) + '...').cx > AWidth) do
    Dec(N);
  Result := UTF8Copy(AText, 1, N) + '...';
end;

{ Container AIndex's row: a grey folder with a star in its kind's colour,
  its name; "..." when pinned. The group is on top: a line below its last row. }
procedure TSortPanel.DrawContainerRow(AIndex: Integer; const R: TRect; APad, AIconW: Integer;
  AText, ADim: TBGRAPixel);
var
  C: TPanelContainer;
  H, TabH, TextX, TextRight: Integer;
  M: TRect;
  StarCol: TBGRAPixel;
  Line: string;
begin
  C := FContainers[AIndex];
  if (FHover.Part in [ppContainer, ppContainerMenu]) and (FHover.Slot = AIndex) then
    FBitmap.FillRect(R, BGRA(255, 255, 255, 38), dmDrawWithTransparency);
  { The group is on top: a line below its last row. }
  if AIndex = High(FContainers) then
    FBitmap.DrawLine(APad, R.Bottom - 1, FWidth - APad, R.Bottom - 1, BGRA(255, 255, 255, 70), False);
  H := R.Height - APad;
  TabH := Max(2, H div 6);
  DrawFolder(APad, R.Top + APad div 2, AIconW, H, BGRA(105, 105, 115, 255), '');
  case C.Kind of
    0: StarCol := BGRA(255, 190, 40, 255);     { .lif: amber }
    1: StarCol := BGRA(60, 210, 230, 255);     { stack: cyan }
  else
    StarCol := BGRA(175, 115, 245, 255);       { other: violet }
  end;
  DrawStar(APad + AIconW / 2, R.Top + APad div 2 + TabH + (H - TabH) / 2,
    Min(AIconW, H - TabH) * 0.40, StarCol);
  M := MenuRect(R);
  TextX := APad + AIconW + APad;
  if C.Pinned then
    TextRight := M.Left - 2
  else
    TextRight := R.Right - APad;
  FBitmap.FontHeight := Max(9, Min(ScaleI(14, FScale), R.Height * 11 div 20));
  Line := FitText(FBitmap, C.Name, TextRight - TextX);
  FBitmap.TextOut(TextX, R.Top + (R.Height - FBitmap.TextSize(Line).cy) div 2, Line, AText);
  if C.Pinned then
  begin
    if (FHover.Part = ppContainerMenu) and (FHover.Slot = AIndex) then
      FBitmap.FillRect(M, BGRA(255, 255, 255, 60), dmDrawWithTransparency);
    FBitmap.FontHeight := Max(9, R.Height div 2);
    FBitmap.TextOut(M.Left + (M.Width - FBitmap.TextSize('...').cx) div 2,
      M.Top + (M.Height - FBitmap.TextSize('...').cy) div 2 - 2, '...', ADim);
  end;
end;

{ Contents mode, row ARow: 0 = "back", else an image with its
  thumbnail (a grey square until it is made). }
procedure TSortPanel.DrawContentsRow(ARow: Integer; const R: TRect; APad: Integer;
  AText, ADim: TBGRAPixel);
var
  S, X, Y, TextX, M: Integer;
  Thumb: TBGRABitmap;
  Line: string;
begin
  if ((ARow = 0) and (FHover.Part = ppBack))
    or ((ARow > 0) and (FHover.Part = ppEntry) and (FHover.Slot = ARow - 1)) then
    FBitmap.FillRect(R, BGRA(255, 255, 255, 38), dmDrawWithTransparency);
  FBitmap.FontHeight := Max(9, Min(ScaleI(14, FScale), R.Height * 11 div 20));
  if ARow = 0 then
  begin
    Line := FitText(FBitmap, '<  back', FWidth - 2 * APad);
    FBitmap.TextOut(APad, R.Top + (R.Height - FBitmap.TextSize(Line).cy) div 2, Line, ADim);
    FBitmap.DrawLine(APad, R.Bottom - 1, FWidth - APad, R.Bottom - 1, BGRA(255, 255, 255, 50), False);
    Exit;
  end;
  S := R.Height - APad;
  Thumb := nil;
  if Assigned(FOnEntryThumb) and (S >= 8) then
    Thumb := FOnEntryThumb(ARow - 1, S);
  if Thumb <> nil then
  begin
    X := APad + (S - Thumb.Width) div 2;
    Y := R.Top + APad div 2 + (S - Thumb.Height) div 2;
    FBitmap.PutImage(X, Y, Thumb, dmDrawWithTransparency);
  end
  else
    FBitmap.FillRect(APad, R.Top + APad div 2, APad + S, R.Top + APad div 2 + S,
      BGRA(60, 60, 68, 255), dmSet);
  { A stack: the animation mark (user, Day 25: it can play), a cyan play
    triangle on a dark square at the thumbnail's lower right corner. }
  if FEntries[ARow - 1].Frames > 1 then
  begin
    M := Max(7, S * 9 div 20);
    X := APad + S - M;
    Y := R.Top + APad div 2 + S - M;
    FBitmap.FillRect(X, Y, X + M, Y + M, BGRA(0, 0, 0, 190), dmDrawWithTransparency);
    FBitmap.FillPolyAntialias([PointF(X + M * 0.32, Y + M * 0.22), PointF(X + M * 0.32, Y + M * 0.78),
      PointF(X + M * 0.80, Y + M * 0.50)], BGRA(60, 210, 230, 255));
  end;
  TextX := APad + S + APad;
  Line := FitText(FBitmap, FEntries[ARow - 1].Name, FWidth - TextX - APad);
  { The image shown in the view: yellow (user, Day 25). }
  if (FCurrentEntry <> '') and SameText(FEntries[ARow - 1].VirtualName, FCurrentEntry) then
    FBitmap.TextOut(TextX, R.Top + (R.Height - FBitmap.TextSize(Line).cy) div 2, Line,
      BGRA(255, 215, 40, 255))
  else
    FBitmap.TextOut(TextX, R.Top + (R.Height - FBitmap.TextSize(Line).cy) div 2, Line, AText);
end;

procedure TSortPanel.Redraw;
var
  Row, SlotIndex, Pad, IconW, TextX, TextW, Y2: Integer;
  R, M, P: TRect;
  Slot: TSortSlot;
  C: LongWord;
  Col, Text, Dim: TBGRAPixel;
  Line: string;
  FooterLines: TStringArray;
  I, IconS, IconX: Integer;
  Icon: TBGRABitmap;
  Missing: Boolean;
begin
  FDirty := False;
  Inc(FVersion);
  FPreviewW := 0;
  if (FWidth <= 0) or (FViewH <= 0) then
    Exit;
  if FBitmap = nil then
    FBitmap := TBGRABitmap.Create(FWidth, FViewH)
  else
    FBitmap.SetSize(FWidth, FViewH);
  FBitmap.FontQuality := fqSystem;       { transparent background: no ClearType }
  FBitmap.Fill(BGRA(12, 12, 16, PanelAlpha(205)));
  { A thin line on the left: where the panel starts. }
  FBitmap.DrawLine(0, 0, 0, FViewH - 1, BGRA(255, 255, 255, 60), False);

  Text := BGRA(235, 235, 235, 255);
  Dim := BGRA(160, 160, 160, 255);
  Pad := ScaleI(6, FScale);

  { Header: title and the pin. }
  FBitmap.FontHeight := ScaleI(15, FScale);
  if FMode = pmContents then
    Line := FitText(FBitmap, FContentsTitle, FWidth - FHeaderH - Pad)   { the open container }
  else if FFolders.Rapid then
    Line := 'Rapid sorting'
  else
  begin
    Line := 'Sort';
    { Several lists (Day 27): which one; the empty one shown is new. }
    if FFolders.Count = 0 then
    begin
      if FFolders.ListCount > 1 then
        Line := 'New list';
    end
    else if FFolders.ListCount > 1 then
      Line := Format('Sort %d/%d', [FFolders.ListIndex + 1, FFolders.ListCount]);
    if FBusy then
      Line := Line + '   (working ...)';
  end;
  { Not into the arrows or the pin. }
  if ShowsArrows then
    Line := FitText(FBitmap, Line, ArrowRect(-1).Left - Pad)
  else
    Line := FitText(FBitmap, Line, PinRect.Left - Pad);
  FBitmap.TextOut(Pad, (FHeaderH - FBitmap.TextSize(Line).cy) div 2, Line, Dim);
  { The arrows: other lists (Day 27, testers). }
  if ShowsArrows then
    for I := -1 to 1 do
    begin
      if I = 0 then
        Continue;
      P := ArrowRect(I);
      if ((I < 0) and (FHover.Part = ppListPrev)) or ((I > 0) and (FHover.Part = ppListNext)) then
        FBitmap.FillRect(P, BGRA(255, 255, 255, 40), dmDrawWithTransparency);
      { Red: this way comes a new, empty list (Day 27, user). }
      if FFolders.NextIsNew(I) then
        DrawArrow(P, I, BGRA(235, 70, 60, 255))
      else
        DrawArrow(P, I, Dim);
    end;
  P := PinRect;
  if (FHover.Part = ppPin) then
    FBitmap.FillRect(P, BGRA(255, 255, 255, 40), dmDrawWithTransparency);
  { The pin: a head and a needle; lit when pinned. }
  if FPinned then
    Col := BGRA(255, 200, 60, 255)
  else
    Col := BGRA(150, 150, 150, 255);
  FBitmap.FillEllipseAntialias((P.Left + P.Right) / 2, P.Top + P.Height * 0.38,
    P.Height * 0.18, P.Height * 0.18, Col);
  FBitmap.DrawLineAntialias((P.Left + P.Right) / 2, P.Top + P.Height * 0.5,
    (P.Left + P.Right) / 2, P.Top + P.Height * 0.85, Col, Max(1, FScale * 1.5));

  { Rows. }
  for Row := FFirstRow to Min(RowCount - 1, FFirstRow + FRowsShown - 1) do
  begin
    R := RowRect(Row);
    if R.Bottom > FViewH - FFooterH then
      Break;
    { A container's images (M2c). }
    if FMode = pmContents then
    begin
      DrawContentsRow(Row, R, Pad, Text, Dim);
      Continue;
    end;
    IconW := Round((R.Height - 2 * Pad div 2) * 1.25);
    { The containers' group, on top (M2c; none in MView): the .lif the
      wheel is in (user, Day 25: transient). Then "+", then the slots. }
    if Row < Length(FContainers) then
    begin
      DrawContainerRow(Row, R, Pad, IconW, Text, Dim);
      Continue;
    end;
    { "+ add folder" on top of the slots (Day 27, testers). }
    SlotIndex := Row - Length(FContainers) - AddRows;
    if (FHover.Part in [ppSlot, ppSlotMenu]) and (FHover.Slot = SlotIndex) then
      FBitmap.FillRect(R, BGRA(255, 255, 255, 38), dmDrawWithTransparency);
    { The confirmation flash, and the frame of a job under way. }
    if (SlotIndex >= 0) and (FFlashStartMs > 0) and (FFlashSlot = SlotIndex) then
    begin
      Col := FlashColor;
      Col.alpha := Round(200 * FFlashLevel);
      FBitmap.FillRect(R, Col, dmDrawWithTransparency);
    end;
    if (SlotIndex >= 0) and (SlotIndex < FFolders.Count) and (SlotIndex <= High(FPending))
      and (FPending[SlotIndex] > 0) then
    begin
      C := SlotColorValue(FFolders.Slot(SlotIndex).Color);
      FBitmap.RectangleAntialias(R.Left + 1.5, R.Top + 1.5, R.Right - 2.5, R.Bottom - 2.5,
        BGRA(C and $FF, (C shr 8) and $FF, (C shr 16) and $FF, 230), Max(1.5, FScale * 1.5));
    end;
    if SlotIndex = -1 then
    begin
      { "+": add a folder (or drop one here). }
      if FHover.Part = ppAdd then
        FBitmap.FillRect(R, BGRA(255, 255, 255, 38), dmDrawWithTransparency);
      FBitmap.FontHeight := Max(10, R.Height * 2 div 3);
      FBitmap.TextOut(Pad + IconW div 4, R.Top + (R.Height - FBitmap.TextSize('+').cy) div 2, '+', Dim);
      FBitmap.FontHeight := Max(9, Min(ScaleI(13, FScale), R.Height * 11 div 20));
      Line := 'add folder';
      FBitmap.TextOut(Pad + IconW + Pad, R.Top + (R.Height - FBitmap.TextSize(Line).cy) div 2, Line, Dim);
      Continue;
    end;
    Slot := FFolders.Slot(SlotIndex);
    { A missing folder, or a button cut to be pasted elsewhere (1.1):
      dimmed. }
    Missing := SlotMissing(SlotIndex) or FFolders.IsCutSlot(SlotIndex);
    C := SlotColorValue(Slot.Color);
    if Missing then
      Col := BGRA(90, 90, 90, 255)
    else
      Col := BGRA(C and $FF, (C shr 8) and $FF, (C shr 16) and $FF, 255);
    { Its icon (stage 2), scaled to the button, else the coloured folder. }
    IconS := R.Height - Pad;
    Icon := nil;
    if Assigned(FOnSlotIcon) and (IconS >= 8) then
      Icon := FOnSlotIcon(SlotIndex, IconS);
    if Icon <> nil then
    begin
      IconX := Pad + (IconW - IconS) div 2;
      if Missing then
        FBitmap.PutImage(IconX, R.Top + Pad div 2, Icon, dmDrawWithTransparency, 90)
      else
        FBitmap.PutImage(IconX, R.Top + Pad div 2, Icon, dmDrawWithTransparency);
      { No number on an icon (user, Day 24): the picture alone. }
    end
    else
      DrawFolder(Pad, R.Top + Pad div 2, IconW, R.Height - Pad, Col, FFolders.SlotLabel(SlotIndex));
    M := MenuRect(R);
    TextX := Pad + IconW + Pad;
    TextW := M.Left - TextX - 2;
    FBitmap.FontHeight := Max(9, Min(ScaleI(14, FScale), R.Height * 11 div 20));
    Line := FitText(FBitmap, Slot.Name, TextW);
    if Missing then
      FBitmap.TextOut(TextX, R.Top + (R.Height - FBitmap.TextSize(Line).cy) div 2, Line,
        BGRA(110, 110, 110, 255))
    else
      FBitmap.TextOut(TextX, R.Top + (R.Height - FBitmap.TextSize(Line).cy) div 2, Line, Text);
    { While it flashes: a check mark (or a cross) instead of "...". }
    if (FFlashStartMs > 0) and (FFlashSlot = SlotIndex) then
    begin
      DrawMark(M, FFlashOK, Round(255 * FFlashLevel));
      Continue;
    end;
    { The "..." corner. }
    if (FHover.Part = ppSlotMenu) and (FHover.Slot = SlotIndex) then
      FBitmap.FillRect(M, BGRA(255, 255, 255, 60), dmDrawWithTransparency);
    FBitmap.FontHeight := Max(9, R.Height div 2);
    FBitmap.TextOut(M.Left + (M.Width - FBitmap.TextSize('...').cx) div 2,
      M.Top + (M.Height - FBitmap.TextSize('...').cy) div 2 - 2, '...', Dim);
  end;

  { More rows than fit: a hint that the wheel scrolls. }
  if RowCount > FRowsShown then
  begin
    FBitmap.FontHeight := ScaleI(11, FScale);
    Line := Format('%d-%d of %d  (wheel)', [FFirstRow + 1,
      Min(RowCount, FFirstRow + FRowsShown), RowCount]);
    FBitmap.TextOut(Pad, FViewH - FFooterH - FBitmap.TextSize(Line).cy - 2, Line, Dim);
  end;

  { Footer: the hovered folder, or the last action (click = undo). }
  R := FooterRect;
  FBitmap.DrawLine(0, R.Top, FWidth - 1, R.Top, BGRA(255, 255, 255, 50), False);
  if (FHover.Part in [ppSlot, ppSlotMenu]) and (FHover.Slot >= 0) and (FHover.Slot < FFolders.Count) then
  begin
    if SlotMissing(FHover.Slot) then
      Line := 'folder not found:' + LineEnding + FFolders.Slot(FHover.Slot).Folder
    else if FFolders.Rapid then
      Line := FFolders.Slot(FHover.Slot).Folder
        + LineEnding + 'key ' + FFolders.SlotLabel(FHover.Slot) + ': move the image here'
        + LineEnding + 'double-click  left: copy  right: move'
    else
      Line := FFolders.Slot(FHover.Slot).Folder
        + LineEnding + 'double-click  left: copy  right: move'
        + LineEnding + 'swipe left or right: open the folder';
  end
  else if FHover.Part = ppAdd then
    Line := 'click: choose a folder' + LineEnding + 'or drop folders here'
  else if (FHover.Part = ppContainer) and (FHover.Slot >= 0) and (FHover.Slot <= High(FContainers)) then
    Line := FContainers[FHover.Slot].Path
      + LineEnding + 'double-click: list its images'
      + LineEnding + 'swipe or wheel click: open it'
  else if (FHover.Part = ppEntry) and (FHover.Slot >= 0) and (FHover.Slot <= High(FEntries)) then
    Line := FEntries[FHover.Slot].Name + LineEnding + 'click: show it'
  else if FHover.Part = ppBack then
    Line := 'click: back to the folders'
  else if FHover.Part = ppPin then
    Line := 'pin: stay open'
  else if FHover.Part = ppListPrev then
    Line := 'the previous folder list'
  else if FHover.Part = ppListNext then
    Line := 'the next folder list' + LineEnding + '(after the last: a new, empty one)'
  else if (FMode = pmContents) and (FFooterText = '') then
    Line := Format('%d images', [Length(FEntries)]) + LineEnding + 'click one to show it'
  else
    Line := FFooterText;
  if FHover.Part = ppFooter then
    FBitmap.FillRect(R, BGRA(255, 255, 255, 38), dmDrawWithTransparency);
  { Delete / undo: the bottom line flashes. }
  if (FFlashStartMs > 0) and (FFlashSlot < 0) then
  begin
    Col := FlashColor;
    Col.alpha := Round(110 * FFlashLevel);
    FBitmap.FillRect(R, Col, dmDrawWithTransparency);
  end;
  FBitmap.FontHeight := ScaleI(11, FScale);
  FooterLines := TextLines(Line);
  Y2 := R.Top + 3;
  for I := 0 to Min(High(FooterLines), 2) do
  begin
    FBitmap.TextOut(Pad, Y2, FitText(FBitmap, FooterLines[I], FWidth - 2 * Pad), Dim);
    Inc(Y2, FBitmap.TextSize('Xg').cy);
  end;

  ComposePreview;
end;

{ The mouse rests on a button with an icon: the icon, large (up to its
  own size), in a box to the left of the panel, level with the button
  (user, Day 24). Panel and box become one picture, FOut. }
procedure TSortPanel.ComposePreview;
var
  Slot, Pad, Gap, CapH, MaxS, BoxW, BoxH, BoxY: Integer;
  Pic: TBGRABitmap;
  Cap, Line: string;
  Details: TStringArray;
  I, Shown, LineH, BandH, BandY, PicX: Integer;
begin
  FPreviewW := 0;
  { A slot's icon, or (M2c) an image of the open container. }
  if FHover.Part = ppEntry then
  begin
    if (not Assigned(FOnEntryPreview)) or (FHover.Slot < 0) or (FHover.Slot > High(FEntries)) then
      Exit;
  end
  else
  begin
    if (not Assigned(FOnSlotPreview)) or not (FHover.Part in [ppSlot, ppSlotMenu]) then
      Exit;
    if (FHover.Slot < 0) or (FHover.Slot >= FFolders.Count) then
      Exit;
  end;
  Slot := FHover.Slot;
  Pad := ScaleI(6, FScale);
  Gap := ScaleI(4, FScale);
  CapH := ScaleI(18, FScale);
  { As large as fits beside the panel, and never larger than 256 px
    (scaled for the screen). }
  MaxS := Min(ScaleI(256, FScale), Min(FViewH - 2 * Pad - CapH,
    FViewW - FWidth - Gap - 2 * Pad - ScaleI(16, FScale)));
  if MaxS < ScaleI(96, FScale) then
    Exit;
  Cap := '';
  if FHover.Part = ppEntry then
    Pic := FOnEntryPreview(Slot, MaxS, Cap)
  else
    Pic := FOnSlotPreview(Slot, MaxS, Cap);
  if (Pic = nil) or (Pic.Width <= 0) or (Pic.Height <= 0) then
    Exit;
  Details := nil;
  if (FHover.Part = ppEntry) and Assigned(FOnEntryDetails) then
    Details := FOnEntryDetails(Slot);

  BoxW := Max(Pic.Width, ScaleI(96, FScale)) + 2 * Pad;
  { Room for the details' lines (they may be wider than the picture). }
  if Length(Details) > 0 then
    BoxW := Max(BoxW, Min(ScaleI(340, FScale), FViewW - FWidth - Gap - ScaleI(16, FScale)));
  BoxH := Pic.Height + 2 * Pad;
  if Cap <> '' then
    Inc(BoxH, CapH);
  { Always at the top of the view (user, Day 24), not level with the
    button: it stays put while the mouse moves down the list. }
  BoxY := 0;
  FPreviewW := BoxW + Gap;

  if FOut = nil then
    FOut := TBGRABitmap.Create(FPreviewW + FWidth, FViewH)
  else
    FOut.SetSize(FPreviewW + FWidth, FViewH);
  FOut.FillTransparent;
  FOut.FontQuality := fqSystem;
  FOut.FillRoundRectAntialias(0, BoxY, BoxW - 1, BoxY + BoxH - 1, ScaleI(5, FScale),
    ScaleI(5, FScale), BGRA(12, 12, 16, 220));
  FOut.RoundRectAntialias(0, BoxY, BoxW - 1, BoxY + BoxH - 1, ScaleI(5, FScale),
    ScaleI(5, FScale), BGRA(255, 255, 255, 60), 1);
  PicX := (BoxW - Pic.Width) div 2;
  FOut.PutImage(PicX, BoxY + Pad, Pic, dmDrawWithTransparency);
  { The details over the picture's lower part (user, Day 26), on a dark
    band across the box: as many lines as fit in the picture's height,
    the file's order (what matters for looking and measuring first). }
  if Length(Details) > 0 then
  begin
    FOut.FontHeight := Max(9, ScaleI(10, FScale));
    LineH := FOut.TextSize('Xg').cy;
    Shown := Min(Length(Details), Max(0, (Pic.Height - Pad) div Max(1, LineH)));
    if Shown > 0 then
    begin
      BandH := Shown * LineH + Pad;
      BandY := BoxY + Pad + Pic.Height - BandH;
      FOut.FillRect(Pad div 2, BandY, BoxW - Pad div 2, BoxY + Pad + Pic.Height,
        BGRA(0, 0, 0, 165), dmDrawWithTransparency);
      for I := 0 to Shown - 1 do
      begin
        Line := FitText(FOut, Details[I], BoxW - 2 * Pad);
        FOut.TextOut(Pad, BandY + Pad div 2 + I * LineH, Line, BGRA(225, 225, 225, 255));
      end;
    end;
  end;
  if Cap <> '' then
  begin
    FOut.FontHeight := ScaleI(11, FScale);
    Cap := FitText(FOut, Cap, BoxW - 2 * Pad);
    FOut.TextOut((BoxW - FOut.TextSize(Cap).cx) div 2,
      BoxY + Pad + Pic.Height + (CapH - FOut.TextSize(Cap).cy) div 2, Cap,
      BGRA(160, 160, 160, 255));
  end;
  FOut.PutImage(FPreviewW, 0, FBitmap, dmSet);
end;

end.
