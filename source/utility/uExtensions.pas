unit uExtensions;

{
  Unit: uExtensions

  Purpose
  -------
  The plug-in points of the core (M0, Day 25). The microscopy edition is
  a second program from the same source tree; its units plug themselves
  in here, in their initialization sections, and the core never names
  them. MView's own program lists none of them, so in MView every list
  here is empty and nothing changes - except the panel rows: since 1.3
  TMView registers its own (the section controls of a 3D model,
  uStlPanel).

  Owns
  ----
  - The registered overlay layers (freed at the end of the program).
  - The lists of metadata readers and menu entries (plain records).

  Knows
  -----
  - OnOverlayChanged: set by TMView; a layer calls OverlayChanged when
    its picture changed, TMView repaints.

  Responsibilities
  ----------------
  - Metadata readers: RegisterMetadataReader(name, function);
    ReadImageMetadata asks them in turn (first one that understands the
    file wins) and returns the facts in a TImageMetadata (pixel size in
    µm, lines for a panel). Pure functions: any thread.
  - Overlay layers (TOverlayLayer): drawn by both renderers over the
    image and its lens / selection, under the info line, the badge and
    the panels, as one picture (with alpha) at a place in the view;
    offered the mouse over the view (not over the panels) before the
    mouse language.
  - Menu entries: caption, action, enabled / checked tests; the main
    form adds them to the right-click menu before "About".
  - Panel sections (M3b): an edition's rows at the bottom of the left
    (filter) panel - drawn, hinted and clicked through TPanelSection.
  - The image shown (M3b): name and size, kept current by TMView.
  - Settings pages (M3b): an edition's own tab in the settings screen,
    made when first opened.
  - Burn-in (Day 26): a layer draws itself into "Apply filters to a
    copy" (CanBurnIn / BurnIn, BurnInPoint for the geometry).
  - NoteMenuOpen (Day 26): an edition's popup is open (the pointer
    stays).
  - NoteDerivedImage (Day 26): a crop, copy or resized image was made
    from another (the edition carries the scale over).
  - The aiming loupe (Day 28): an edition's tool tells TMView the point
    it aims at (ShowAimLoupe) or that it no longer aims (HideAimLoupe);
    TMView shows the small lens there when the mouse rests.
  - A new image (Day 28, "Run in Fiji"): an edition hands the viewer a
    bitmap to show as a crop is shown (ShowImageInViewer).
  - Undo (Day 28): an edition's own undo (the marks) joins the viewer's
    (RegisterEditionUndo); NextUndoStamp orders both, so Undo takes back
    whichever came last.

  Does NOT
  --------
  - Draw, read files or know any edition's units.

  Threads
  -------
  Registration: in initialization sections (main thread, before any
  other thread). Metadata readers: any thread. Layers and menu entries:
  UI thread.

  Uses (MView units)
  ------------------
  interface:      uCommands (the overlay mouse types)
  Libraries:      Classes, SysUtils, Types, Controls, BGRABitmap

  Used by
  -------
  uMView, uRenderer, uGLRenderer, uMainForm, uFilterPanel, uIniEditor; the
  microscopy edition's units
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  Types,
  Controls,
  BGRABitmap,
  uCommands;

{ ---- Metadata readers ---- }

type
  { What a file says about itself, as far as a reader understood it. }
  TImageMetadata = record
    Reader: string;              { which reader understood it; '' = none }
    PixelSizeX: Double;          { µm per pixel; 0 = unknown }
    PixelSizeY: Double;
    { The image size the pixel size is for (M3a): an export can be
      smaller than the scan it came from; the user scales by
      ScaleWidth / the image's width. 0 = the image's own size. }
    ScaleWidth: Integer;
    ScaleHeight: Integer;
    { Where the scale is from, when not the file itself:
      'sample.lif › Series084' (shown next to measurements). }
    ScaleSource: string;
    { For choosing a calibration (M3a); '' / 0 = unknown. }
    Microscope: string;          { 'TCS SP8' }
    Objective: string;           { 'HC PL APO CS2 40x/1.30 OIL' }
    Zoom: Double;
    Lines: TStringArray;         { 'Objective: HC PL APO 40x/1.30 OIL', for a panel }
  end;

  { True if the reader understood AFileName (AMeta filled in). No UI,
    no shared state: called on any thread. }
  TMetadataReadFunc = function(const AFileName: string; var AMeta: TImageMetadata): Boolean;

procedure RegisterMetadataReader(const AName: string; AReader: TMetadataReadFunc);
function MetadataReaderCount: Integer;
{ The first registered reader that understands the file; False (and an
  empty AMeta) if none does or none is registered. A reader that raises
  counts as "not understood". }
function ReadImageMetadata(const AFileName: string; out AMeta: TImageMetadata): Boolean;
procedure ClearMetadata(out AMeta: TImageMetadata);

{ ---- Overlay layers ---- }

type
  { From the image's pixels (its full size) to a copy's: scaled to the
    pixels the copy was made from (a quick view is smaller), mirrored,
    then turned clockwise onto the copy's canvas (as RotatedBitmap). }
  TBurnInMap = record
    ScaleX, ScaleY: Double;     { copy source px per image px }
    SourceWidth, SourceHeight: Integer;   { before the turn }
    Mirror: Boolean;
    Angle: Double;              { degrees, clockwise }
    Width, Height: Integer;     { the copy }
    { Screen pixels per copy pixel when the copy was made (Day 28, user:
      the burned-in marks look as on screen - the same text size, line
      width, padding at that zoom); 0 = not known (the layer sizes them
      for the copy). }
    ViewScale: Double;
  end;

{ AX, AY (image pixels, edges at whole numbers) in the copy. }
procedure BurnInPoint(const AMap: TBurnInMap; AX, AY: Double; out ACopyX, ACopyY: Double);

type
  { A layer over the image (a scale bar, a measuring line). AView is the
    renderer (TRenderer: ScreenToImage / ImageToScreen, View); a layer
    unit may use uRenderer, the core's units don't use the layers. }
  TOverlayLayer = class
  public
    { The picture, with alpha, and its place in the view (AWidth x
      AHeight; ALeft, ATop: its top left corner there); nil = nothing to
      draw now. Only as large as what it shows (M1: the GPU uploads it
      again on every change; a whole 4K view each mouse move is too
      much). Kept by the layer (not freed by the caller). Called in
      every paint: keep it cheap (draw again only when something
      changed). }
    function Picture(AView: TObject; AWidth, AHeight: Integer; out ALeft, ATop: Integer): TBGRABitmap; virtual;
    { Changes whenever the picture changes, including after a pan or zoom
      (the GPU uploads it again; a new size is uploaded anyway). }
    function Version: Cardinal; virtual;
    { The mouse over the view (not over the open sort panel); True =
      taken (the mouse language doesn't see it). The layer that takes a
      press gets its release, wherever it is; a move it takes still
      reaches the sort panel's edge. }
    function HandleMouse(AView: TObject; AKind: TOverlayMouseKind; AButton: TOverlayButton;
      AX, AY, AWheel: Integer): Boolean; virtual;
    { "Apply filters to a copy" (Day 26, user: the measurement goes into
      the copy too): True if the layer has something to draw into a copy
      of AImageName (the name the image is shown under). }
    function CanBurnIn(const AImageName: string): Boolean; virtual;
    { Draws it into ABitmap, the copy (filtered, mirrored and turned
      already); AMap takes the layer's image pixels to the copy's
      (BurnInPoint). Returns a short part for the copy's name
      ('56,32um'), or ''. }
    function BurnIn(ABitmap: TBGRABitmap; const AImageName: string;
      const AMap: TBurnInMap): string; virtual;
    { The SVG figure (1.1): the layer's name there ('Measurements';
      '' = not in figures) and its elements in the copy's pixels (as
      BurnIn, but as vectors and text: editable later), '' = nothing for
      AImageName. }
    function SvgLayerName: string; virtual;
    function SvgMarkup(const AImageName: string; const AMap: TBurnInMap): string; virtual;
  end;

{ The registry owns ALayer from now on. }
procedure RegisterOverlayLayer(ALayer: TOverlayLayer);
function OverlayLayerCount: Integer;
function OverlayLayer(AIndex: Integer): TOverlayLayer;
{ A layer's picture changed: OnOverlayChanged (TMView: repaint). }
procedure OverlayChanged(ALayer: TOverlayLayer);

{ Any layer's CanBurnIn; BurnIn of each that can (its name parts joined
  with '_'; '' = none). }
function OverlayCanBurnIn(const AImageName: string): Boolean;
function OverlayBurnIn(ABitmap: TBGRABitmap; const AImageName: string;
  const AMap: TBurnInMap): string;

{ ---- The figure (1.1): the image as shown, for an SVG export ---- }

type
  { The current image's pixels as "Apply filters to a copy" makes them
    (filters, mirror, turn; no layer burned in): ABitmap (the caller
    frees it) and AMap (the layers' image pixels -> its pixels; Width /
    Height set). AImageName: the name the layers know the image by;
    ASourceName: a short name for the file; AFolder: where the image
    is (or the save folder); AQuick: from the quick view (the full
    image not loaded yet). False and AError if there is none. }
  TFigureSourceFunc = function(out ABitmap: TBGRABitmap; out AMap: TBurnInMap;
    out AImageName, ASourceName, AFolder, AError: string; out AQuick: Boolean): Boolean of object;

{ The viewer offers it (TMView); nil = none. Unregister only removes
  AOwner's own. }
procedure RegisterFigureSource(ASource: TFigureSourceFunc);
procedure UnregisterFigureSource(AOwner: TObject);
function FigureSourceAvailable: Boolean;
function MakeFigure(out ABitmap: TBGRABitmap; out AMap: TBurnInMap;
  out AImageName, ASourceName, AFolder, AError: string; out AQuick: Boolean): Boolean;

{ ---- The image's own pixels (1.1: "Open in Fiji") ---- }

type
  { The current image's pixels as decoded: no display filter, no mirror,
    no turn (for analysis). ABitmap: a copy (the caller frees it);
    AFullWidth x AFullHeight: the image's full size (the copy can be
    smaller: a quick view, or a huge image shown reduced); AImageName,
    ASourceName, AFolder as for the figure. False and AError if none. }
  TImagePixelsFunc = function(out ABitmap: TBGRABitmap; out AImageName, ASourceName,
    AFolder, AError: string; out AFullWidth, AFullHeight: Integer; out AQuick: Boolean): Boolean of object;

procedure RegisterImagePixelsSource(ASource: TImagePixelsFunc);
procedure UnregisterImagePixelsSource(AOwner: TObject);
function GetImagePixels(out ABitmap: TBGRABitmap; out AImageName, ASourceName, AFolder,
  AError: string; out AFullWidth, AFullHeight: Integer; out AQuick: Boolean): Boolean;

{ ---- A new image from an edition (Day 28: Fiji's result) ---- }

type
  { Shows ABitmap as a new image, as a crop is shown (until the next
    step; "Save image" writes it): AName its name (the key the layers and
    the scale know it by), ATitle for the info line, ASaveName the start
    of its file name when saved. The viewer owns ABitmap from then on.
    False if there is no viewer (ABitmap is freed). }
  TShowImageFunc = function(ABitmap: TBGRABitmap; const AName, ATitle,
    ASaveName: string): Boolean of object;

procedure RegisterShowImage(AFunc: TShowImageFunc);
procedure UnregisterShowImage(AOwner: TObject);
function ShowImageInViewer(ABitmap: TBGRABitmap; const AName, ATitle, ASaveName: string): Boolean;

{ An edition's popup menu (the left panel's scale list) is open: the
  main form keeps the mouse pointer from hiding meanwhile (Day 26: it
  vanished outside the menu). Call with True before PopUp, False after. }
procedure NoteMenuOpen(AOpen: Boolean);

type
  TMenuOpenEvent = procedure(AOpen: Boolean) of object;
  TViewerNoteEvent = procedure(const AText: string; ADurationMs: Double) of object;

var
  OnOverlayChanged: TNotifyEvent = nil;
  OnMenuOpen: TMenuOpenEvent = nil;   { set by the main form }
  { 1.1: a note in the viewer's info line (set by TMView). }
  OnViewerNote: TViewerNoteEvent = nil;

{ A note in the viewer's info line for ADurationMs (nothing without a
  viewer). }
procedure ViewerNote(const AText: string; ADurationMs: Double);

{ ---- Menu entries ---- }

type
  { AViewer: the viewer (TMView). }
  TExtensionAction = procedure(AViewer: TObject);
  TExtensionTest = function(AViewer: TObject): Boolean;

  TExtensionMenuEntry = record
    Caption: string;
    Action: TExtensionAction;
    IsEnabled: TExtensionTest;   { nil = always }
    IsChecked: TExtensionTest;   { nil = never }
  end;

procedure RegisterMenuEntry(const ACaption: string; AAction: TExtensionAction;
  AIsEnabled: TExtensionTest = nil; AIsChecked: TExtensionTest = nil);
function MenuEntryCount: Integer;
function MenuEntry(AIndex: Integer): TExtensionMenuEntry;

{ ---- Rows in the left (filter) panel (M3b) ---- }

type
  { How the mouse acts on a row: a button (Click at the release), an
    on / off box (Click; the second click of a double-click is left
    out), a slider (drag along it, wheel, double-click: back to its
    start value; no Click). }
  TSectionRowKind = (srkButton, srkToggle, srkSlider);

  { A few rows at the bottom of the left panel, below "Auto / Reset
    all" (the microscopy edition: the calibration selector and
    "Confocal"; 1.3: the section controls of a 3D model). The panel
    draws the background and the hover; the section its content. }
  TPanelSection = class
  public
    function RowCount: Integer; virtual;
    function RowKind(ARow: Integer): TSectionRowKind; virtual;
    { Sliders: the position on the bar (0 .. 1); SetSliderPos moves it
      (a drag); Wheel: notches, + = more; ResetRow: the start value. }
    function SliderPos(ARow: Integer): Double; virtual;
    procedure SetSliderPos(ARow: Integer; APos: Double); virtual;
    procedure Wheel(ARow: Integer; ANotches: Double); virtual;
    procedure ResetRow(ARow: Integer); virtual;
    { ARect: the row in the panel's picture; AHover: the mouse is on it. }
    procedure DrawRow(ARow: Integer; ABitmap: TBGRABitmap; const ARect: TRect;
      AHover: Boolean; AScale: Double); virtual;
    { The panel's bottom line while the mouse is on the row. }
    function Hint(ARow: Integer): string; virtual;
    { A click (on release, where it was pressed); AScreen: the mouse on
      the screen (for a popup menu). }
    procedure Click(ARow: Integer; AButton: TOverlayButton; const AScreen: TPoint); virtual;
    { Changes whenever the rows would look different: the panel draws
      them again. }
    function Version: Cardinal; virtual;
  end;

{ The registry owns ASection from now on. }
procedure RegisterPanelSection(ASection: TPanelSection);
{ All sections' rows together; row 0 is the first section's first. }
function PanelSectionRowCount: Integer;
function PanelSectionAt(ARow: Integer; out ASection: TPanelSection; out ALocalRow: Integer): Boolean;
{ Sum of the sections' versions: a change means "draw again". }
function PanelSectionsVersion: Cardinal;

{ ---- Pages in the settings screen (M3b) ---- }

type
  { An edition's own tab next to "Mouse & keys" (the microscopy
    edition: "Calibrations"). Made when the tab is first opened
    (Create: its content, parented to the tab); Refresh each time the tab
    is shown or the settings screen comes back. It keeps its own file. }
  TSettingsPageCreate = function(AOwner: TComponent; AParent: TWinControl): TWinControl;
  TSettingsPageRefresh = procedure(APage: TWinControl);

  TSettingsPageEntry = record
    Caption: string;
    Hint: string;               { the settings screen's help line on it }
    Create: TSettingsPageCreate;
    Refresh: TSettingsPageRefresh;   { nil = nothing to refresh }
  end;

procedure RegisterSettingsPage(const ACaption, AHint: string; ACreate: TSettingsPageCreate;
  ARefresh: TSettingsPageRefresh = nil);
function SettingsPageCount: Integer;
function SettingsPage(AIndex: Integer): TSettingsPageEntry;

{ ---- Derived images (Day 26) ---- }

type
  { A new image made from another (a crop, a filtered / turned copy, a
    resized one): ANewName its name (the key's), AParentName the image
    it was made from, AOperation 'crop' / 'copy' / 'resized'.
    AParentWidth x AParentHeight: the parent's size (its original
    pixels); AFactorX / AFactorY: parent pixels per new pixel along the
    parent's axes (1 for a crop); ATurn: degrees the new pixels are
    turned by (quarter turns swap x and y). The microscopy edition: the
    scale travels with the image. }
  TDerivedImageProc = procedure(const ANewName, AParentName, AOperation: string;
    AParentWidth, AParentHeight: Integer; AFactorX, AFactorY, ATurn: Double);

procedure RegisterDerivedImageHandler(AHandler: TDerivedImageProc);

type
  { The scale an image has (µm per pixel of its original, AWidth x
    AHeight), as the edition knows it; False = none (Day 26: saved into
    the file). UI thread. }
  TImageScaleQuery = function(const AName: string; AWidth, AHeight: Integer;
    out AUmX, AUmY: Double): Boolean;

procedure RegisterImageScaleQuery(AQuery: TImageScaleQuery);
function QueryImageScale(const AName: string; AWidth, AHeight: Integer;
  out AUmX, AUmY: Double): Boolean;
procedure NoteDerivedImage(const ANewName, AParentName, AOperation: string;
  AParentWidth, AParentHeight: Integer; AFactorX, AFactorY, ATurn: Double);

{ ---- The aiming loupe (Day 28) ---- }

type
  { AOn: the tool aims at (AX, AY) (surface pixels; the loupe's middle
    once the mouse rests there); AFromX / AFromY: where its line or bar
    starts (kept for the tools, unused since the loupe is centred);
    False: the tool no longer aims (the loupe goes). }
  TAimLoupeEvent = procedure(AOn: Boolean; AX, AY, AFromX, AFromY: Double) of object;

var
  OnAimLoupe: TAimLoupeEvent = nil;   { set by TMView }

{ An edition's tool aims (a click to come) at (AX, AY); HideAimLoupe:
  not any more. }
procedure ShowAimLoupe(AX, AY, AFromX, AFromY: Double);
procedure HideAimLoupe;

{ ---- Undo (Day 28) ---- }

type
  { The edition's undo: what Undo would take back ('Undo scale bar'; ''
    = nothing), the stamp of its newest entry (0 = none), and doing it. }
  TEditionUndoCaption = function: string;
  TEditionUndoStamp = function: Int64;
  TEditionUndoProc = procedure;

procedure RegisterEditionUndo(ACaption: TEditionUndoCaption; AStamp: TEditionUndoStamp;
  AUndo: TEditionUndoProc);
function EditionUndoCaption: string;
function EditionUndoStamp: Int64;
procedure EditionUndo;
{ A new stamp for an undo entry (the viewer's and the edition's): later
  is larger. }
function NextUndoStamp: Int64;

{ ---- The image shown (M3b) ---- }

{ Kept current by TMView (after every step), for the edition's panels
  and menu tests; '' / 0 = none. }
procedure SetShownImage(const AName: string; AWidth, AHeight: Integer);
function ShownImageName: string;
function ShownImageWidth: Integer;
function ShownImageHeight: Integer;

implementation

type
  TReaderEntry = record
    Name: string;
    Read: TMetadataReadFunc;
  end;

var
  DerivedHandler: TDerivedImageProc = nil;
  ScaleQuery: TImageScaleQuery = nil;
  Readers: array of TReaderEntry;
  Layers: array of TOverlayLayer;
  MenuEntries: array of TExtensionMenuEntry;
  Sections: array of TPanelSection;
  SettingsPages: array of TSettingsPageEntry;
  ShownName: string = '';
  ShownWidth: Integer = 0;
  ShownHeight: Integer = 0;

function Max0(AValue: Integer): Integer;
begin
  if AValue < 0 then
    Result := 0
  else
    Result := AValue;
end;

procedure ClearMetadata(out AMeta: TImageMetadata);
begin
  AMeta.Reader := '';
  AMeta.PixelSizeX := 0;
  AMeta.PixelSizeY := 0;
  AMeta.ScaleWidth := 0;
  AMeta.ScaleHeight := 0;
  AMeta.ScaleSource := '';
  AMeta.Microscope := '';
  AMeta.Objective := '';
  AMeta.Zoom := 0;
  AMeta.Lines := nil;
end;

procedure RegisterMetadataReader(const AName: string; AReader: TMetadataReadFunc);
begin
  if not Assigned(AReader) then
    Exit;
  SetLength(Readers, Length(Readers) + 1);
  Readers[High(Readers)].Name := AName;
  Readers[High(Readers)].Read := AReader;
end;

function MetadataReaderCount: Integer;
begin
  Result := Length(Readers);
end;

function ReadImageMetadata(const AFileName: string; out AMeta: TImageMetadata): Boolean;
var
  I: Integer;
  Ok: Boolean;
begin
  ClearMetadata(AMeta);
  Result := False;
  for I := 0 to High(Readers) do
  begin
    try
      Ok := Readers[I].Read(AFileName, AMeta);
    except
      Ok := False;
    end;
    if Ok then
    begin
      if AMeta.Reader = '' then
        AMeta.Reader := Readers[I].Name;
      Exit(True);
    end;
    ClearMetadata(AMeta);   { a reader that gave up leaves nothing behind }
  end;
end;

{ TOverlayLayer: the defaults draw nothing and take no mouse. }

function TOverlayLayer.Picture(AView: TObject; AWidth, AHeight: Integer;
  out ALeft, ATop: Integer): TBGRABitmap;
begin
  ALeft := 0;
  ATop := 0;
  Result := nil;
end;

function TOverlayLayer.Version: Cardinal;
begin
  Result := 0;
end;

function TOverlayLayer.HandleMouse(AView: TObject; AKind: TOverlayMouseKind;
  AButton: TOverlayButton; AX, AY, AWheel: Integer): Boolean;
begin
  Result := False;
end;

function TOverlayLayer.CanBurnIn(const AImageName: string): Boolean;
begin
  Result := False;
end;

function TOverlayLayer.BurnIn(ABitmap: TBGRABitmap; const AImageName: string;
  const AMap: TBurnInMap): string;
begin
  Result := '';
end;

function TOverlayLayer.SvgLayerName: string;
begin
  Result := '';
end;

function TOverlayLayer.SvgMarkup(const AImageName: string; const AMap: TBurnInMap): string;
begin
  Result := '';
end;

var
  FigureSource: TFigureSourceFunc = nil;

procedure RegisterFigureSource(ASource: TFigureSourceFunc);
begin
  FigureSource := ASource;
end;

procedure UnregisterFigureSource(AOwner: TObject);
begin
  if Assigned(FigureSource) and (TMethod(FigureSource).Data = Pointer(AOwner)) then
    FigureSource := nil;
end;

function FigureSourceAvailable: Boolean;
begin
  Result := Assigned(FigureSource);
end;

function MakeFigure(out ABitmap: TBGRABitmap; out AMap: TBurnInMap;
  out AImageName, ASourceName, AFolder, AError: string; out AQuick: Boolean): Boolean;
begin
  ABitmap := nil;
  AImageName := '';
  ASourceName := '';
  AFolder := '';
  AQuick := False;
  AError := 'no image';
  Result := Assigned(FigureSource)
    and FigureSource(ABitmap, AMap, AImageName, ASourceName, AFolder, AError, AQuick);
end;

var
  PixelsSource: TImagePixelsFunc = nil;

procedure RegisterImagePixelsSource(ASource: TImagePixelsFunc);
begin
  PixelsSource := ASource;
end;

procedure UnregisterImagePixelsSource(AOwner: TObject);
begin
  if Assigned(PixelsSource) and (TMethod(PixelsSource).Data = Pointer(AOwner)) then
    PixelsSource := nil;
end;

function GetImagePixels(out ABitmap: TBGRABitmap; out AImageName, ASourceName, AFolder,
  AError: string; out AFullWidth, AFullHeight: Integer; out AQuick: Boolean): Boolean;
begin
  ABitmap := nil;
  AImageName := '';
  ASourceName := '';
  AFolder := '';
  AFullWidth := 0;
  AFullHeight := 0;
  AQuick := False;
  AError := 'no image';
  Result := Assigned(PixelsSource)
    and PixelsSource(ABitmap, AImageName, ASourceName, AFolder, AError, AFullWidth,
      AFullHeight, AQuick);
end;

var
  ShowImageFunc: TShowImageFunc = nil;

procedure RegisterShowImage(AFunc: TShowImageFunc);
begin
  ShowImageFunc := AFunc;
end;

procedure UnregisterShowImage(AOwner: TObject);
begin
  if Assigned(ShowImageFunc) and (TMethod(ShowImageFunc).Data = Pointer(AOwner)) then
    ShowImageFunc := nil;
end;

function ShowImageInViewer(ABitmap: TBGRABitmap; const AName, ATitle, ASaveName: string): Boolean;
begin
  Result := False;
  if ABitmap = nil then
    Exit;
  if not Assigned(ShowImageFunc) then
  begin
    ABitmap.Free;
    Exit;
  end;
  Result := ShowImageFunc(ABitmap, AName, ATitle, ASaveName);
end;

procedure BurnInPoint(const AMap: TBurnInMap; AX, AY: Double; out ACopyX, ACopyY: Double);
var
  X, Y, Rad, C, S, DX, DY: Double;
begin
  X := AX * AMap.ScaleX;
  Y := AY * AMap.ScaleY;
  if AMap.Mirror then
    X := AMap.SourceWidth - X;
  { Turned about the centres (RotatedBitmap: the source's centre lands
    on the canvas's; quarter turns the same). }
  Rad := AMap.Angle * Pi / 180;
  C := Cos(Rad);
  S := Sin(Rad);
  DX := X - AMap.SourceWidth / 2;
  DY := Y - AMap.SourceHeight / 2;
  ACopyX := AMap.Width / 2 + DX * C - DY * S;
  ACopyY := AMap.Height / 2 + DX * S + DY * C;
end;

function OverlayCanBurnIn(const AImageName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(Layers) do
    if Layers[I].CanBurnIn(AImageName) then
      Exit(True);
end;

function OverlayBurnIn(ABitmap: TBGRABitmap; const AImageName: string;
  const AMap: TBurnInMap): string;
var
  I: Integer;
  Part: string;
begin
  Result := '';
  for I := 0 to High(Layers) do
    if Layers[I].CanBurnIn(AImageName) then
    begin
      Part := Layers[I].BurnIn(ABitmap, AImageName, AMap);
      if Part <> '' then
      begin
        if Result <> '' then
          Result := Result + '_';
        Result := Result + Part;
      end;
    end;
end;

procedure RegisterDerivedImageHandler(AHandler: TDerivedImageProc);
begin
  DerivedHandler := AHandler;
end;

procedure RegisterImageScaleQuery(AQuery: TImageScaleQuery);
begin
  ScaleQuery := AQuery;
end;

function QueryImageScale(const AName: string; AWidth, AHeight: Integer;
  out AUmX, AUmY: Double): Boolean;
begin
  AUmX := 0;
  AUmY := 0;
  Result := False;
  if not Assigned(ScaleQuery) then
    Exit;
  try
    Result := ScaleQuery(AName, AWidth, AHeight, AUmX, AUmY) and (AUmX > 0) and (AUmY > 0);
  except
    Result := False;
  end;
  if not Result then
  begin
    AUmX := 0;
    AUmY := 0;
  end;
end;

procedure NoteDerivedImage(const ANewName, AParentName, AOperation: string;
  AParentWidth, AParentHeight: Integer; AFactorX, AFactorY, ATurn: Double);
begin
  if not Assigned(DerivedHandler) then
    Exit;
  try
    DerivedHandler(ANewName, AParentName, AOperation, AParentWidth, AParentHeight,
      AFactorX, AFactorY, ATurn);
  except
    { An edition's fault never reaches the viewer. }
  end;
end;

procedure ViewerNote(const AText: string; ADurationMs: Double);
begin
  if Assigned(OnViewerNote) then
    OnViewerNote(AText, ADurationMs);
end;

procedure NoteMenuOpen(AOpen: Boolean);
begin
  if Assigned(OnMenuOpen) then
    OnMenuOpen(AOpen);
end;

procedure RegisterOverlayLayer(ALayer: TOverlayLayer);
begin
  if ALayer = nil then
    Exit;
  SetLength(Layers, Length(Layers) + 1);
  Layers[High(Layers)] := ALayer;
end;

function OverlayLayerCount: Integer;
begin
  Result := Length(Layers);
end;

function OverlayLayer(AIndex: Integer): TOverlayLayer;
begin
  if (AIndex < 0) or (AIndex > High(Layers)) then
    Exit(nil);
  Result := Layers[AIndex];
end;

procedure OverlayChanged(ALayer: TOverlayLayer);
begin
  if Assigned(OnOverlayChanged) then
    OnOverlayChanged(ALayer);
end;

procedure RegisterMenuEntry(const ACaption: string; AAction: TExtensionAction;
  AIsEnabled: TExtensionTest; AIsChecked: TExtensionTest);
begin
  if not Assigned(AAction) then
    Exit;
  SetLength(MenuEntries, Length(MenuEntries) + 1);
  MenuEntries[High(MenuEntries)].Caption := ACaption;
  MenuEntries[High(MenuEntries)].Action := AAction;
  MenuEntries[High(MenuEntries)].IsEnabled := AIsEnabled;
  MenuEntries[High(MenuEntries)].IsChecked := AIsChecked;
end;

function MenuEntryCount: Integer;
begin
  Result := Length(MenuEntries);
end;

function MenuEntry(AIndex: Integer): TExtensionMenuEntry;
begin
  if (AIndex < 0) or (AIndex > High(MenuEntries)) then
  begin
    Result.Caption := '';
    Result.Action := nil;
    Result.IsEnabled := nil;
    Result.IsChecked := nil;
    Exit;
  end;
  Result := MenuEntries[AIndex];
end;

{ TPanelSection: the defaults show nothing. }

function TPanelSection.RowCount: Integer;
begin
  Result := 0;
end;

function TPanelSection.RowKind(ARow: Integer): TSectionRowKind;
begin
  Result := srkButton;
end;

function TPanelSection.SliderPos(ARow: Integer): Double;
begin
  Result := 0;
end;

procedure TPanelSection.SetSliderPos(ARow: Integer; APos: Double);
begin
end;

procedure TPanelSection.Wheel(ARow: Integer; ANotches: Double);
begin
end;

procedure TPanelSection.ResetRow(ARow: Integer);
begin
end;

procedure TPanelSection.DrawRow(ARow: Integer; ABitmap: TBGRABitmap; const ARect: TRect;
  AHover: Boolean; AScale: Double);
begin
end;

function TPanelSection.Hint(ARow: Integer): string;
begin
  Result := '';
end;

procedure TPanelSection.Click(ARow: Integer; AButton: TOverlayButton; const AScreen: TPoint);
begin
end;

function TPanelSection.Version: Cardinal;
begin
  Result := 0;
end;

procedure RegisterPanelSection(ASection: TPanelSection);
begin
  if ASection = nil then
    Exit;
  SetLength(Sections, Length(Sections) + 1);
  Sections[High(Sections)] := ASection;
end;

function PanelSectionRowCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Sections) do
    Inc(Result, Max0(Sections[I].RowCount));
end;

function PanelSectionAt(ARow: Integer; out ASection: TPanelSection; out ALocalRow: Integer): Boolean;
var
  I, N: Integer;
begin
  ASection := nil;
  ALocalRow := -1;
  Result := False;
  if ARow < 0 then
    Exit;
  for I := 0 to High(Sections) do
  begin
    N := Max0(Sections[I].RowCount);
    if ARow < N then
    begin
      ASection := Sections[I];
      ALocalRow := ARow;
      Exit(True);
    end;
    Dec(ARow, N);
  end;
end;

function PanelSectionsVersion: Cardinal;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Sections) do
    Result := Result + Sections[I].Version;
end;

procedure RegisterSettingsPage(const ACaption, AHint: string; ACreate: TSettingsPageCreate;
  ARefresh: TSettingsPageRefresh);
begin
  if not Assigned(ACreate) then
    Exit;
  SetLength(SettingsPages, Length(SettingsPages) + 1);
  SettingsPages[High(SettingsPages)].Caption := ACaption;
  SettingsPages[High(SettingsPages)].Hint := AHint;
  SettingsPages[High(SettingsPages)].Create := ACreate;
  SettingsPages[High(SettingsPages)].Refresh := ARefresh;
end;

function SettingsPageCount: Integer;
begin
  Result := Length(SettingsPages);
end;

function SettingsPage(AIndex: Integer): TSettingsPageEntry;
begin
  if (AIndex < 0) or (AIndex > High(SettingsPages)) then
  begin
    Result.Caption := '';
    Result.Hint := '';
    Result.Create := nil;
    Result.Refresh := nil;
    Exit;
  end;
  Result := SettingsPages[AIndex];
end;

procedure ShowAimLoupe(AX, AY, AFromX, AFromY: Double);
begin
  if Assigned(OnAimLoupe) then
    OnAimLoupe(True, AX, AY, AFromX, AFromY);
end;

procedure HideAimLoupe;
begin
  if Assigned(OnAimLoupe) then
    OnAimLoupe(False, 0, 0, 0, 0);
end;

var
  UndoCaptionFunc: TEditionUndoCaption = nil;
  UndoStampFunc: TEditionUndoStamp = nil;
  UndoProc: TEditionUndoProc = nil;
  LastUndoStamp: Int64 = 0;

procedure RegisterEditionUndo(ACaption: TEditionUndoCaption; AStamp: TEditionUndoStamp;
  AUndo: TEditionUndoProc);
begin
  UndoCaptionFunc := ACaption;
  UndoStampFunc := AStamp;
  UndoProc := AUndo;
end;

function EditionUndoCaption: string;
begin
  Result := '';
  if Assigned(UndoCaptionFunc) then
    try
      Result := UndoCaptionFunc();
    except
      Result := '';
    end;
end;

function EditionUndoStamp: Int64;
begin
  Result := 0;
  if Assigned(UndoStampFunc) then
    try
      Result := UndoStampFunc();
    except
      Result := 0;
    end;
end;

procedure EditionUndo;
begin
  if Assigned(UndoProc) then
    try
      UndoProc();
    except
      { An edition's fault never reaches the viewer. }
    end;
end;

function NextUndoStamp: Int64;
begin
  Inc(LastUndoStamp);
  Result := LastUndoStamp;
end;

procedure SetShownImage(const AName: string; AWidth, AHeight: Integer);
begin
  ShownName := AName;
  ShownWidth := AWidth;
  ShownHeight := AHeight;
end;

function ShownImageName: string;
begin
  Result := ShownName;
end;

function ShownImageWidth: Integer;
begin
  Result := ShownWidth;
end;

function ShownImageHeight: Integer;
begin
  Result := ShownHeight;
end;

procedure FreeLayers;
var
  I: Integer;
begin
  for I := 0 to High(Layers) do
    FreeAndNil(Layers[I]);
  Layers := nil;
  for I := 0 to High(Sections) do
    FreeAndNil(Sections[I]);
  Sections := nil;
end;

finalization
  OnOverlayChanged := nil;
  OnMenuOpen := nil;
  OnAimLoupe := nil;
  FreeLayers;
end.
