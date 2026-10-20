unit uMainForm;

{
  Unit: uMainForm

  Purpose
  -------
  The main window. A thin shell (spec §2.3): it creates TMView and the
  drawing surface, passes commands on, and does the few things only a
  window can do (close, fullscreen).

  Two faces (spec §11, v1.2d):
  - Started with a file or folder: the viewer, at once.
  - Started without: the settings editor (TIniEditor, MView.ini).
    "View images" there starts the viewer with the last session;
    TMView is only created then, so it reads the settings just saved.

  Owns
  ----
  TMView (once the viewer runs), and through the LCL component tree:
  the drawing surface, the right-click menu, the settings editor.
  In detail:
  - FMView (TMView): created by CreateViewer, freed when going back
    to the settings editor (Esc) or in FormDestroy.
  - The drawing surface: FCpuView (TMediaView) or FGLView
    (TGLMediaView). The renderer made for it (TCpuRenderer or
    TGLRenderer) is handed to TMView (AttachView), which owns it.
  - FPopupMenu (the right-click menu), FDeliveryTimer (TTimer, 50 ms),
    FEditor (TIniEditor, made once and kept hidden while viewing).
  - FSortMenu: the sort panel's slot menu ("..." corner, "+"), filled
    anew each time it opens (Phase G).
  - A short-lived TConfig when no viewer runs (ShowEditor,
    RememberBounds).

  Knows
  -----
  - The watchdog (uWatchdog): started here (StartWatchdog), armed
    with ExitDeadlineMs when the viewer or MView shuts down (2 min
    while a copy or move of the sort panel is running).
  - The surface's mouse engine (ViewInput): gets TMView's mouse
    profile and [Mouse] ZonesEnabled; Tick, FocusLost, cursor hiding.
  - TMView.Config: window place, UseGPU, UseMipMaps, StartFullscreen,
    MouseHideTime.

  Responsibilities
  ----------------
  - Choose the GPU surface if OpenGL works and UseGPU=1, otherwise the
    CPU one (spec §8.5); the reason is shown in the diagnostics line.
  - Pass the surface's commands to TMView.Execute; show the menu
    itself (cmdShowMenu), including "About MView" (the dedication to
    Hamana, AboutText).
  - Fullscreen, exit, and going back to the settings editor (Esc in
    the viewer, run later through QueueAsyncCall).
  - Esc on the settings screen: like the editor's Exit (unless the
    "Try it here" area or an open list has the focus).
  - Drag and drop: a dropped file or folder is opened; folders dropped
    on the open sort panel become its folders instead (onto a button:
    replaces it, elsewhere on the panel: added).
  - Sorting (Phase G): the menu entries "Sort panel (side menu)",
    "Delete current image" and "Undo ..." (only when there is something
    to undo); the slot menu (choose folder with a dialog starting where
    TMView.SortStartFolder says, recent folders, this image's folder or
    its parent, colour, move up / down, remove); the views' overlay
    mouse events go to TMView.HandleOverlayMouse.
  - Stage 2: "Make icon from this image"; the slot menu's "Open this
    folder" and "Icon" (by name, none, the icon folder's icons with
    their pictures, choose a file, open the icon folder); icon files
    dropped on a button.
  - Only one instance ([Startup] OnlyOneInstance, uSingleInstance): a
    second MView's file or folder arrives through HandleHandedOver and
    is opened like a drop (not onto the sort panel); the window comes to
    the front.
  - The magnifier: the menu entry "Magnifier (lens)" (ticked while on);
    the view's cursor is TMView.ViewCursor (a cross while the lens
    follows the mouse).
  - Looking closer (Phase H): the menu entries "Filters (side menu,
    left)", "Lock filters" (checked when on) and "Apply filters to a
    copy" (enabled while a filter is set); "Resize to the size shown
    (W x H)".
  - "Follow Total Commander" (Off / Its folder / Its folder and the image
    under its cursor): TMView.SetFollowMode.
  - The settings screen's "Total Commander side by side" (OnSideBySide):
    the last session's folder, else Documents; its own timer waits for a
    Total Commander just started.
  - Side by side with Total Commander (menu, command SideBySide): MView
    the left half of its screen's work area, Total Commander the right
    half in the image's folder (uTotalCommander; a just started one is
    placed when its window appears, on the timer); again: back to
    fullscreen or the place before. While side by side, the window
    place remembered is the one before.
  - Settings screen (Day 21): Ctrl+V with an image in the clipboard
    opens the viewer with it; files dropped anywhere on the editor
    (also on the text) open it (AcceptDropsOn).
  - Remember the window place in MView.ini (1 s after the last move /
    resize in the viewer; on close; before switching faces), and put
    the window there at start if it is still on a monitor.
  - On its timer: TMView.PumpDeliveries, the mouse engine's Tick,
    cursor hiding ([Mouse] MouseCursorHideTime).

  Does NOT
  --------
  - Contain viewer logic (copying, moving, undo: TMView).
  - Show dialogs (spec §3.1), except the save and folder dialogs the
    user asks for from the menu.

  Threads
  -------
  UI thread only (LCL events, a TTimer, one QueueAsyncCall). The
  worker threads are TMView's; the watchdog runs its own thread
  (uWatchdog).

  Uses (MView units)
  ------------------
  interface:      uCommands, uMouseEngine, uRenderer, uMView,
                  uMediaView, uGLRenderer, uGLMediaView, uConfig,
                  uSortFolders, uSortPanel, uSortIcons, uIniEditor, uStopwatch,
                  uWatchdog
  implementation: uMousePage, uTotalCommander, uEdition (names,
                  About), uExtensions (the edition's menu entries)
  Libraries:      Classes, SysUtils, Forms, Controls, Graphics, Menus,
                  ExtCtrls, LCLType, LCLIntf, StdCtrls, Dialogs, Clipbrd,
                  Math, BGRABitmap

  Used by
  -------
  VersariteViewer.lpr, VersariteImageLab.lpr (programs)
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  Forms,
  Controls,
  Graphics,
  Menus,
  ExtCtrls,
  LCLType,
  uCommands,
  uMouseEngine,
  uRenderer,
  uMView,
  uMediaView,
  uGLRenderer,
  uGLMediaView,
  uConfig,
  uSortFolders,
  uSortPanel,
  uSortIcons,
  uIniEditor,
  uStopwatch,
  uWatchdog,
  uTypes,
  uSlotMenuWindow,
  uExifRotate;

type

  { TMainForm }

  TMainForm = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    FMView: TMView;
    FView: TWinControl;          { the drawing surface, CPU or GPU }
    FCpuView: TMediaView;        { one of these two is used }
    FGLView: TGLMediaView;
    FPopupMenu: TPopupMenu;
    FCropItem: TMenuItem;
    { Rotate losslessly (1.1): JPEGs only; Tag = the TOrientOp. }
    FRotateItem: TMenuItem;
    FUndoItem: TMenuItem;
    FSortMenu: TPopupMenu;       { a slot's "..." menu / the "+" menu (Phase G) }
    FSortMenuSlot: Integer;      { the slot it is for; -1 = a new slot }
    FSortMenuIcons: TStringList; { the icon files offered in it (names in the icon folder) }
    { The slot menu shown as MView's own window (Day 27, testers: stays
      open while moving, Move up / down repeat while held). }
    FSlotMenuWindow: TSlotMenuWindow;
    FMoveTopItem, FMoveUpItem, FMoveDownItem: TMenuItem;
    { Rapid Selection on / off (Day 27, testers). }
    FRapidItem: TMenuItem;
    { The sort panel and the scan bar, on / off (ticked while open). }
    FSortPanelItem: TMenuItem;
    FPreviewStripItem: TMenuItem;
    FMakeIconItem: TMenuItem;
    { Side by side with Total Commander (Phase G, user): on, the place to
      go back to, and a Total Commander just started that is still to be
      placed (its window appears a moment later). }
    FSideItem: TMenuItem;
    { Looking closer (Phase H): "Lock filters" (checked when on). }
    FLockFiltersItem: TMenuItem;
    FApplyFiltersItem: TMenuItem;
    FResizeItem: TMenuItem;
    FMagnifierItem: TMenuItem;
    { Follow Total Commander (Day 23): off / folder / folder and cursor. }
    FFollowItems: array[0..2] of TMenuItem;
    { Total Commander dir preview (1.1, testers): on / off. }
    FDirPreviewItem: TMenuItem;
    { The order of the images (Day 27, testers): Tag = the TSortMode. }
    FSortOrderItems: array[TSortMode] of TMenuItem;
    { The edition's own entries (uExtensions, M0), before "About";
      Tag = the entry's index. None in MView. }
    FExtensionItems: array of TMenuItem;
    FSideBySide: Boolean;
    FSideWasFullscreen: Boolean;
    FSideBounds: TRect;
    FSideHaveBounds: Boolean;
    FSideRight: TRect;
    { 1.1 (user): MView's half; fullscreen while side by side comes back
      to it (next to Total Commander), not to the place before. }
    FSideLeft: TRect;
    FSideWaitUntil: QWord;       { 0 = not waiting }
    FSideAgainAt: QWord;         { place it once more then (it may move itself); 0 = no }
    { The same on the settings screen: its own timer (the viewer's isn't
      running there). }
    FEditorSideTimer: TTimer;
    FEditorSideUntil: QWord;     { waiting for a Total Commander just started; 0 = no }
    FEditorSideAgainAt: QWord;
    { Only one instance (Day 23): a path handed over by a second MView,
      opened right after its message (not inside it: it waits). }
    FHandedOverPath: string;
    { [Startup] Mode=2 (Day 24): the folder Total Commander is sent to
      when MView starts side by side with it. }
    FStartFolder: string;
    { The very first start (no MView.ini yet, no file given): the welcome
      picture next to MView.exe, shown in the viewer (Day 24); '' = no. }
    FWelcome: string;
    FStarted: Boolean;
    FFullscreen: Boolean;
    FNormalBounds: TRect;
    FDeliveryTimer: TTimer;
    FEditor: TIniEditor;
    FBoundsApplied: Boolean;     { the stored window place was used }
    FBoundsDirty: Boolean;       { moved / resized since last saved }
    FBoundsChangedTick: QWord;
    FCursorHidden: Boolean;
    FMenuOpen: Boolean;          { the cursor stays while the menu is open }
    FViewerEnded: Boolean;       { a viewer was closed with Esc before }
    FEscHeld: Boolean;           { the Esc that left the viewer is still down }
    FWindowCreatedMs: Double;    { start-up: ms after the process started }
    { Esc to the settings (user, Day 25): the viewer that is closing in
      the background - its threads told to stop, freed by FCloseTimer
      once they are back (or after CloseWaitMs). }
    FClosingViewer: TMView;
    FCloseTimer: TTimer;
    FCloseStartTick: QWord;

    procedure CreateViewer;
    procedure HandleCloseTimer(Sender: TObject);
    { The closing viewer freed now (waiting for its threads if needed);
      the settings screen does what it kept (Save, View images).
      AOnExit: MView is ending (the exit deadline stays armed). }
    procedure FinishClosingViewer(AOnExit: Boolean = False);
    { AApplyBounds: put the window where it was last time (not when
      coming back from the viewer). }
    procedure ShowEditor(AApplyBounds: Boolean = True);
    procedure HandleSettingsRequest(Sender: TObject);
    procedure ReturnToEditor(AData: PtrInt);
    procedure HandleFormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure HandleFormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure HandleEditorViewImages(Sender: TObject);
    procedure StartViewerFromEditor(const APath: string; APaste: Boolean = False);
    procedure HandleDropFiles(Sender: TObject; const FileNames: array of string);
    procedure HandleFormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure HandleEditorExit(Sender: TObject);
    { "Total Commander side by side" on the settings screen (Day 22). }
    procedure HandleEditorSideBySide(Sender: TObject);
    procedure HandleEditorSideTimer(Sender: TObject);
    procedure OpenHandedOver(AData: PtrInt);
    procedure CreateView;
    function TryCreateGLView(out AReason: string): Boolean;
    function ViewInput: TMouseEngine;
    procedure UpdateCursor;
    procedure HandleExtensionMenuOpen(AOpen: Boolean);
    procedure HandleDeactivate(Sender: TObject);
    procedure HandleCommand(Sender: TObject; ACommand: TCommand; const AArgs: TCommandArgs);
    procedure HandleExitRequest(Sender: TObject);
    procedure HandleToggleFullscreen(Sender: TObject);
    procedure HandleExitMenuClick(Sender: TObject);
    procedure HandleAboutMenuClick(Sender: TObject);
    procedure HandleExtensionMenuClick(Sender: TObject);
    procedure HandleSaveMenuClick(Sender: TObject);
    procedure HandleSaveAsMenuClick(Sender: TObject);
    procedure HandleSaveDebugMenuClick(Sender: TObject);
    procedure HandlePasteMenuClick(Sender: TObject);
    procedure HandleCopyMenuClick(Sender: TObject);
    procedure HandleCropMenuClick(Sender: TObject);
    procedure HandleSortPanelMenuClick(Sender: TObject);
    procedure HandleDeleteMenuClick(Sender: TObject);
    procedure HandleUndoMenuClick(Sender: TObject);
    { Sorting (Phase G): the slot menu and what it does. }
    procedure HandleSortMenu(ASlot: Integer; const AScreen: TPoint);
    procedure AssignSortFolder(const AFolder: string);
    procedure HandleSortChooseClick(Sender: TObject);
    procedure HandleSortRecentClick(Sender: TObject);
    procedure HandleSortImageFolderClick(Sender: TObject);
    procedure HandleSortParentFolderClick(Sender: TObject);
    procedure HandleSortColorClick(Sender: TObject);
    procedure HandleSortMoveClick(Sender: TObject);
    procedure HandleSortRemoveClick(Sender: TObject);
    procedure HandleSortClipClick(Sender: TObject);
    procedure HandleDirPreviewMenuClick(Sender: TObject);
    procedure HandleRotateMenuClick(Sender: TObject);
    procedure HandleSortIconClick(Sender: TObject);
    procedure HandleSortOpenClick(Sender: TObject);
    procedure AcceptDropsOn(AControl: TWinControl);
    procedure HandleSortIconChooseClick(Sender: TObject);
    procedure HandleSortIconFolderClick(Sender: TObject);
    procedure HandleMakeIconMenuClick(Sender: TObject);
    procedure HandleSideBySideMenuClick(Sender: TObject);
    procedure HandleFilterPanelMenuClick(Sender: TObject);
    procedure HandleLockFiltersMenuClick(Sender: TObject);
    procedure HandleApplyFiltersMenuClick(Sender: TObject);
    procedure HandleResizeMenuClick(Sender: TObject);
    procedure HandleMagnifierMenuClick(Sender: TObject);
    procedure HandleFollowMenuClick(Sender: TObject);
    procedure HandleSortRenameClick(Sender: TObject);
    procedure HandleSortMakeFolderClick(Sender: TObject);
    procedure HandleSlotMenuClosed(Sender: TObject);
    procedure UpdateSortMoveItems;
    procedure HandleRapidMenuClick(Sender: TObject);
    procedure HandlePreviewStripMenuClick(Sender: TObject);
    procedure AddMenuLine;
    { The Total Commander entries: bold, Side by side deep green (user,
      Day 27). }
    procedure HandleStrongMenuDraw(Sender: TObject; ACanvas: TCanvas; ARect: TRect;
      AState: TOwnerDrawState);
    procedure HandleStrongMenuMeasure(Sender: TObject; ACanvas: TCanvas;
      var AWidth, AHeight: Integer);
    procedure HandleSortOrderMenuClick(Sender: TObject);
    { AFolder: Total Commander's folder when no image is shown yet (the
      start, [Startup] Mode=2); '' = the current image's. }
    procedure ToggleSideBySide(const AFolder: string = '');
    procedure StartSideBySide(AData: PtrInt);
    procedure PlaceTotalCommander(AWindow: THandle);
    procedure CheckSideBySideWait;
    procedure SetSlotIcon(ASlot: Integer; const AFile: string);
    function DropOnSortPanel(const FileNames: array of string): Boolean;
    procedure DetachViews;
    function ExitDeadline: Integer;
    procedure HandleDeliveryTimer(Sender: TObject);
    procedure HandleFormResize(Sender: TObject);
    procedure SetFullscreen(AValue: Boolean);
    procedure ApplySavedBounds(AConfig: TConfig);
    function CurrentNormalBounds(out ARect: TRect): Boolean;
    procedure RememberBounds;
    procedure HandleChangeBounds(Sender: TObject);
  public
    { Only one instance: a second MView's file or folder ('' = just come
      to the front); VersariteViewer.lpr hands it to uSingleInstance's listener. }
    procedure HandleHandedOver(const APath: string);
  end;

var
  MainForm: TMainForm;

implementation

uses
  LCLIntf,
  Themes,
  StdCtrls,
  Dialogs,
  Clipbrd,
  Math,
  BGRABitmap,
  uTotalCommander,
  uMousePage,
  uEdition,
  uExtensions,
  uContainers;

{$R *.lfm}

const
  { The slot menu's "Move to top" (Day 27): its Tag. }
  MoveToTopTag = -100000;
  { A menu entry drawn deep green (HandleStrongMenuDraw): its Tag. }
  StrongGreenTag = -200000;
  StrongGreen = TColor($00006400);
  { ... drawn red (Rapid sorting). }
  StrongRedTag = -200001;
  StrongRed = TColor($000000C8);
  { The About box: what MView is, and where it comes from. The first lines
    are the edition's (uEdition): AboutText. }
  AboutBody =
    'Written with support from Claude/Opus 5.5 and ChatGPT' + LineEnding +
    LineEnding +
    'Dedicated by DL1BWA/KD1AEV to Makito Miyano, creator of Hamana (last version 2006) ,' + LineEnding +
    'the viewer that pioneered how browsing images should feel:' + LineEnding +
    'FAST first, MOUSE first, no frills, never in the way.' + LineEnding +
    LineEnding +
    'Built with Free Pascal and Lazarus.' + LineEnding +
    'Free software under the GNU GPL v3.' + LineEnding +
    'Kryptonite, if it ever hangs: ' + EmergencyExitKeyText + '.';

  { Time for a normal shutdown (threads stopped, settings saved). }
  ExitDeadlineMs = 4000;
  { ... while a copy or move is running (Phase G): it is finished, never
    cut off halfway (a large file to a slow drive). }
  FileJobDeadlineMs = 120000;

  { A stored window smaller than this is ignored. }
  MinWindowWidth = 200;
  MinWindowHeight = 150;
  { The map of the screen, shown at the very first start (Day 24). }
  WelcomeSuffix = '_welcome.png';      { VersariteViewer_welcome.png, per edition }
  { The window place is saved this long after the last move / resize
    (viewer; the settings editor saves it on close). }
  BoundsSaveDelayMs = 1000;

{ TMainForm }

{ The About box's text: the edition's name and version, then the rest. }
function AboutText: string;
begin
  Result := EditionTitle + ' ' + EditionVersion + LineEnding;
  if EditionId = 'VersariteViewer' then
    Result := Result + 'A fast image viewer, driven by the mouse.' + LineEnding
      + 'Its microscopy edition, Versarite Image Lab (metadata, calibration, measuring),'
      + LineEnding + 'is a program of its own, in development.' + LineEnding
  else
    Result := Result + 'The microscopy edition of VersariteViewer.' + LineEnding;
  Result := Result + LineEnding + AboutBody;
end;

{ The very first start: the edition's ini isn't there yet (it is made
  right after; an MView.ini from before the rename counts as there) and
  <EditionId>_welcome.png (VersariteViewer_welcome.png) is next to the
  program: its path, else ''. }
function WelcomeForFirstStart: string;
var
  Dir: string;
begin
  Result := '';
  Dir := ExtractFilePath(ParamStr(0));
  if (ParamCount = 0) and not FileExists(EditionIniFileName)
    and not FileExists(EditionOldIniFileName)        { 1.1: not new, renamed }
    and FileExists(Dir + EditionId + WelcomeSuffix) then
    Result := Dir + EditionId + WelcomeSuffix;
end;

{ [Startup] Mode is 1 or 2 (read before any window is made). }
function StartsWithViewer: Boolean;
var
  Config: TConfig;
begin
  Result := False;
  Config := TConfig.Create;
  try
    try
      Config.Load;
      Result := Config.StartsViewer;
    except
      { Unreadable ini: as before, the settings screen. }
    end;
  finally
    Config.Free;
  end;
end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FWindowCreatedMs := ProcessAgeMs;
  Caption := EditionCaption;
  Color := clBlack;

  { Failsafe (uWatchdog): Ctrl+Alt+Shift+Q ends MView even when it is
    frozen, and a close that doesn't finish within ExitDeadlineMs
    ends the process. }
  StartWatchdog;
  OnClose := @HandleFormClose;
  OnChangeBounds := @HandleChangeBounds;

  { Safety net for results from the worker threads (see TMView,
    "Delivery safety net"). Runs once the viewer exists. }
  FDeliveryTimer := TTimer.Create(Self);
  FDeliveryTimer.Enabled := False;
  FDeliveryTimer.Interval := 50;
  FDeliveryTimer.OnTimer := @HandleDeliveryTimer;
  OnDeactivate := @HandleDeactivate;
  { An edition's popup (the left panel's scale list): the pointer stays
    (Day 26). }
  uExtensions.OnMenuOpen := @HandleExtensionMenuOpen;
  FCloseTimer := TTimer.Create(Self);
  FCloseTimer.Enabled := False;
  FCloseTimer.Interval := 50;
  FCloseTimer.OnTimer := @HandleCloseTimer;

  { Drag and drop: a file or folder dropped on the window opens it,
    like a command line argument (in the settings editor too). }
  AllowDropFiles := True;
  OnDropFiles := @HandleDropFiles;

  { Esc on the settings screen ends MView (the viewer's Esc goes back
    to it). The form sees keys first. }
  KeyPreview := True;
  OnKeyDown := @HandleFormKeyDown;
  OnKeyUp := @HandleFormKeyUp;

  { [Startup] Mode (Day 24): 0 = without a file the settings screen;
    1 / 2 = the viewer first (fullscreen / side by side). }
  { Before anything makes MView.ini: is this the very first start? }
  FWelcome := WelcomeForFirstStart;
  if (ParamCount >= 1) or (FWelcome <> '') or StartsWithViewer then
    CreateViewer
  else
    ShowEditor;
end;


{ Everything the viewer needs; FormShow (or the editor) starts it. }
procedure TMainForm.CreateViewer;
var
  Item: TMenuItem;
  FollowIndex: Integer;
  RotateOp: TOrientOp;
  ExtensionIndex: Integer;
  ViewStartMs: Double;
  Order: TSortMode;
begin
  { A viewer still closing from the last Esc goes first (two viewers
    must not run at once: they share the read gate and the files); a
    kept "View images" is not needed any more (this is the viewer), a
    kept Save is done before the new viewer reads the settings. }
  if Assigned(FEditor) then
    FEditor.CancelPendingView;
  FinishClosingViewer;
  FMView := TMView.Create;
  FMView.Initialize;
  { The window's place from last time (unless the settings editor
    already put it there). Before fullscreen, which keeps it as the
    place to return to. }
  if not FBoundsApplied then
    ApplySavedBounds(FMView.Config);
  { Large images get a copy of about this size, made on the worker. }
  FMView.SetDisplaySize(Screen.Width, Screen.Height);
  { From now on the window's own size: quick views are made to fit it
    exactly, so they are drawn without scaling. }
  OnResize := @HandleFormResize;
  FMView.OnExitRequest := @HandleExitRequest;
  FMView.OnToggleFullscreen := @HandleToggleFullscreen;
  FMView.OnSettingsRequest := @HandleSettingsRequest;
  FMView.OnSortMenu := @HandleSortMenu;

  { The menu (spec §3.1), opened by the mouse profile's Menu command
    (right click by default). Its order and grouping are the user's
    (Day 27): Total Commander first, then the file, then the viewing
    aids, then About / Exit. Entries left out are kept but hidden
    (their commands still work from the mouse profile). }
  FPopupMenu := TPopupMenu.Create(Self);

  { MView to the left half, Total Commander to the right, in this
    image's folder; again: back. Bold, deep green (user). }
  FSideItem := TMenuItem.Create(FPopupMenu);
  FSideItem.Caption := 'Side by side with Total Commander';
  FSideItem.OnClick := @HandleSideBySideMenuClick;
  FSideItem.OnDrawItem := @HandleStrongMenuDraw;
  FSideItem.OnMeasureItem := @HandleStrongMenuMeasure;
  FSideItem.Tag := StrongGreenTag;
  FPopupMenu.Items.Add(FSideItem);
  { Follow Total Commander: its folder, or also the image under its
    cursor (MView as its viewer). Tag = the mode. Bold (user). }
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Follow Total Commander';
  Item.OnDrawItem := @HandleStrongMenuDraw;
  Item.OnMeasureItem := @HandleStrongMenuMeasure;
  FPopupMenu.Items.Add(Item);
  FFollowItems[0] := TMenuItem.Create(FPopupMenu);
  FFollowItems[0].Caption := 'Off';
  FFollowItems[1] := TMenuItem.Create(FPopupMenu);
  FFollowItems[1].Caption := 'Its folder';
  FFollowItems[2] := TMenuItem.Create(FPopupMenu);
  FFollowItems[2].Caption := 'Its folder and the image under its cursor';
  for FollowIndex := 0 to 2 do
  begin
    FFollowItems[FollowIndex].Tag := FollowIndex;
    FFollowItems[FollowIndex].RadioItem := True;
    FFollowItems[FollowIndex].GroupIndex := 1;
    FFollowItems[FollowIndex].OnClick := @HandleFollowMenuClick;
    Item.Add(FFollowItems[FollowIndex]);
  end;
  { The folder under Total Commander's cursor as a slide show (1.1). }
  FDirPreviewItem := TMenuItem.Create(FPopupMenu);
  FDirPreviewItem.Caption := 'Total Commander dir preview  (a folder under its cursor plays)';
  FDirPreviewItem.OnClick := @HandleDirPreviewMenuClick;
  FPopupMenu.Items.Add(FDirPreviewItem);
  AddMenuLine;

  { The file. The image at its own resolution to the clipboard (Day 25). }
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Copy image     (Ctrl+C)';
  Item.OnClick := @HandleCopyMenuClick;
  FPopupMenu.Items.Add(Item);
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Paste image     (Ctrl+V)';
  Item.OnClick := @HandlePasteMenuClick;
  FPopupMenu.Items.Add(Item);
  { Moves the file into the deleted-files folder (never really deleted). }
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Delete current image  (into the deleted-files folder)';
  Item.OnClick := @HandleDeleteMenuClick;
  FPopupMenu.Items.Add(Item);
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Save image';
  Item.OnClick := @HandleSaveMenuClick;
  FPopupMenu.Items.Add(Item);
  { As in IrfanView: Save goes straight to the save folder, Save as asks. }
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Save image as ...';
  Item.OnClick := @HandleSaveAsMenuClick;
  FPopupMenu.Items.Add(Item);
  { Edit mode: the selected area becomes the image; shown only once a
    selection is made (user, Day 27). }
  FCropItem := TMenuItem.Create(FPopupMenu);
  FCropItem.Caption := 'Crop selection';
  FCropItem.OnClick := @HandleCropMenuClick;
  FCropItem.Visible := False;
  FPopupMenu.Items.Add(FCropItem);
  { A copy at the size shown (the info line's W x H), like Crop (user,
    Day 22); an icon for the sort panel from this image. }
  FResizeItem := TMenuItem.Create(FPopupMenu);
  FResizeItem.Caption := 'Resize to the size shown';
  FResizeItem.OnClick := @HandleResizeMenuClick;
  FPopupMenu.Items.Add(FResizeItem);
  FMakeIconItem := TMenuItem.Create(FPopupMenu);
  FMakeIconItem.Caption := 'Make icon from this image';
  FMakeIconItem.OnClick := @HandleMakeIconMenuClick;
  FPopupMenu.Items.Add(FMakeIconItem);
  { Lossless: the JPEG's orientation tag (1.1, user). }
  FRotateItem := TMenuItem.Create(FPopupMenu);
  FRotateItem.Caption := 'Rotate losslessly  (JPEG)';
  FPopupMenu.Items.Add(FRotateItem);
  for RotateOp := Low(TOrientOp) to High(TOrientOp) do
  begin
    Item := TMenuItem.Create(FPopupMenu);
    case RotateOp of
      ooRotateRight: Item.Caption := '90 degrees right';
      ooRotateLeft: Item.Caption := '90 degrees left';
      ooRotate180: Item.Caption := '180 degrees';
      ooFlipHorizontal: Item.Caption := 'Mirror left-right';
      ooFlipVertical: Item.Caption := 'Mirror top-bottom';
    end;
    Item.Tag := Ord(RotateOp);
    Item.OnClick := @HandleRotateMenuClick;
    FRotateItem.Add(Item);
  end;
  { Hidden (user, Day 27: "might be useful later"). }
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Save image and view (debugging)';
  Item.OnClick := @HandleSaveDebugMenuClick;
  Item.Visible := False;
  FPopupMenu.Items.Add(Item);
  AddMenuLine;

  { Ten fixed folders, keys 1 .. 0 move the image (Day 27, testers). }
  FRapidItem := TMenuItem.Create(FPopupMenu);
  FRapidItem.Caption := 'Rapid sorting  (keys 1 .. 0)';
  { Bold, red (user, Day 27). }
  FRapidItem.Tag := StrongRedTag;
  FRapidItem.OnDrawItem := @HandleStrongMenuDraw;
  FRapidItem.OnMeasureItem := @HandleStrongMenuMeasure;
  FRapidItem.OnClick := @HandleRapidMenuClick;
  FPopupMenu.Items.Add(FRapidItem);
  { On / off (ticked while open; it also opens at the right edge). }
  FSortPanelItem := TMenuItem.Create(FPopupMenu);
  FSortPanelItem.Caption := 'Sort panel (side menu)';
  FSortPanelItem.OnClick := @HandleSortPanelMenuClick;
  FPopupMenu.Items.Add(FSortPanelItem);
  { On / off (ticked while open; it also opens at the top edge). }
  FPreviewStripItem := TMenuItem.Create(FPopupMenu);
  FPreviewStripItem.Caption := 'Preview strip  (or rest the mouse at the top edge)';
  FPreviewStripItem.OnClick := @HandlePreviewStripMenuClick;
  FPopupMenu.Items.Add(FPreviewStripItem);
  { The filter panel also opens at the left edge. Lock filters: they stay
    for the next images. }
  { Hidden (user, Day 27: the left edge and the mouse command
    FilterPanel open it). }
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Filters (side menu, left)';
  Item.OnClick := @HandleFilterPanelMenuClick;
  Item.Visible := False;
  FPopupMenu.Items.Add(Item);
  { The filters (and the rotation, the measurement) into the pixels of a
    copy (enabled while there is something to apply). }
  FApplyFiltersItem := TMenuItem.Create(FPopupMenu);
  FApplyFiltersItem.Caption := 'Apply filters to a copy';
  FApplyFiltersItem.OnClick := @HandleApplyFiltersMenuClick;
  FPopupMenu.Items.Add(FApplyFiltersItem);
  { The order of the images (Day 27, testers): by date, by name, random
    (Random again: a new shuffle). }
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Order of the images';
  FPopupMenu.Items.Add(Item);
  for Order := Low(TSortMode) to High(TSortMode) do
  begin
    FSortOrderItems[Order] := TMenuItem.Create(FPopupMenu);
    case Order of
      smDateDescending: FSortOrderItems[Order].Caption := 'By date, newest first';
      smDateAscending: FSortOrderItems[Order].Caption := 'By date, oldest first';
      smFileNameAscending: FSortOrderItems[Order].Caption := 'By name, A - Z';
      smFileNameDescending: FSortOrderItems[Order].Caption := 'By name, Z - A';
      smRandom: FSortOrderItems[Order].Caption := 'Random  (again: shuffle anew)';
    end;
    FSortOrderItems[Order].Tag := Ord(Order);
    FSortOrderItems[Order].RadioItem := True;
    FSortOrderItems[Order].GroupIndex := 2;
    FSortOrderItems[Order].OnClick := @HandleSortOrderMenuClick;
    Item.Add(FSortOrderItems[Order]);
  end;

  { Not in the user's menu (Day 27): kept, hidden. Their commands still
    work (mouse profile: Undo, Magnifier; Undo also by a click on the
    sort panel's bottom line). }
  { Lock filters: hidden (user, Day 27: the filter panel has its own
    lock symbol); the command LockFilters stays. }
  FLockFiltersItem := TMenuItem.Create(FPopupMenu);
  FLockFiltersItem.Caption := 'Lock filters';
  FLockFiltersItem.OnClick := @HandleLockFiltersMenuClick;
  FLockFiltersItem.Visible := False;
  FPopupMenu.Items.Add(FLockFiltersItem);
  FUndoItem := TMenuItem.Create(FPopupMenu);
  FUndoItem.Caption := 'Undo';
  FUndoItem.OnClick := @HandleUndoMenuClick;
  FUndoItem.Visible := False;
  FPopupMenu.Items.Add(FUndoItem);
  FMagnifierItem := TMenuItem.Create(FPopupMenu);
  FMagnifierItem.Caption := 'Magnifier (lens)';
  FMagnifierItem.OnClick := @HandleMagnifierMenuClick;
  FMagnifierItem.Visible := False;
  FPopupMenu.Items.Add(FMagnifierItem);

  { The edition's own entries (uExtensions, M0): a group of their own
    (none in MView). }
  if MenuEntryCount > 0 then
  begin
    AddMenuLine;
    SetLength(FExtensionItems, MenuEntryCount);
    for ExtensionIndex := 0 to MenuEntryCount - 1 do
    begin
      FExtensionItems[ExtensionIndex] := TMenuItem.Create(FPopupMenu);
      FExtensionItems[ExtensionIndex].Caption := MenuEntry(ExtensionIndex).Caption;
      FExtensionItems[ExtensionIndex].Tag := ExtensionIndex;
      FExtensionItems[ExtensionIndex].OnClick := @HandleExtensionMenuClick;
      FPopupMenu.Items.Add(FExtensionItems[ExtensionIndex]);
    end;
  end;
  AddMenuLine;
  { The homage to Hamana (docs\From_Hamana_to_VersariteViewer.md). }
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'About ' + EditionTitle;
  Item.OnClick := @HandleAboutMenuClick;
  FPopupMenu.Items.Add(Item);
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := 'Exit     (if it ever hangs: ' + EmergencyExitKeyText + ')';
  Item.OnClick := @HandleExitMenuClick;
  FPopupMenu.Items.Add(Item);

  ViewStartMs := NowMs;
  CreateView;
  FMView.NoteStartup(FWindowCreatedMs, ProcessAgeMs, NowMs - ViewStartMs);
  if FViewerEnded then
    FMView.SkipStartupLog;
  { The mouse language: the surface gets the profile. }
  if Assigned(ViewInput) then
  begin
    ViewInput.SetProfile(FMView.MouseProfile);
    ViewInput.ZonesEnabled := FMView.Config.ZonesEnabled;
    { The edges (Day 27): the bottom one switches zoom mode (zones off),
      the top one opens the preview strip. }
    ViewInput.EdgeWidth := Max(2, Round(FMView.Config.EdgeWidth * Max(1.0, Screen.PixelsPerInch / 96)));
    ViewInput.BottomEdgeMs := FMView.Config.BottomEdgeMs;
    ViewInput.TopEdgeMs := FMView.Config.TopEdgeMs;
  end;
  FDeliveryTimer.Enabled := True;

  if FMView.Config.StartFullscreen then
    SetFullscreen(True);
end;

{ Started without a file or folder: MView.ini in an editor. }
procedure TMainForm.ShowEditor(AApplyBounds: Boolean);
var
  Config: TConfig;
  Note: string;
begin
  { Complete the file first: a new installation gets one with all
    defaults, an older one gets the keys added since (existing values,
    comments and unknown keys stay). }
  Config := TConfig.Create;
  try
    try
      Config.Load;
      Config.Save;
    except
      { Read-only folder or the like: the editor shows what is there. }
    end;
    if AApplyBounds then
      ApplySavedBounds(Config);
    { Coming back from the viewer: the editor made at the start is still
      there (hidden); it reads the files again (the viewer may have
      written them). }
    { One layout for all of it, not one per control (Day 25). }
    DisableAutoSizing;
    try
    if FEditor = nil then
    begin
      FEditor := TIniEditor.Create(Self);
      FEditor.Parent := Self;
      FEditor.Align := alClient;
      FEditor.OnViewImages := @HandleEditorViewImages;
      FEditor.OnExitRequest := @HandleEditorExit;
      FEditor.OnSideBySide := @HandleEditorSideBySide;
    end;
    FEditor.Visible := True;
    FEditor.LoadFile(Config.IniFileName);
    FEditor.LoadMouseProfile(Config.MouseProfileFileName);
    { A damaged ini was restored at the start (1.1): said once. }
    Note := TakeIniNote;
    if Note <> '' then
      FEditor.ShowNote(Note);
    finally
      EnableAutoSizing;
    end;
    { Files dropped anywhere on it (the text too) open the viewer. }
    AcceptDropsOn(FEditor);
  finally
    Config.Free;
  end;
  Caption := EditionCaption + ' - settings';
end;

{ "View images": the viewer with the settings just saved, and the last
  session. The editor stays hidden (it is freed with the form; freeing
  it here, inside its own button click, would not be safe). }
procedure TMainForm.HandleEditorViewImages(Sender: TObject);
begin
  StartViewerFromEditor('');
end;

{ APath: a file or folder to open; '' = the last session. APaste: the
  clipboard's image instead (Ctrl+V on the settings screen, Day 21). }
procedure TMainForm.StartViewerFromEditor(const APath: string; APaste: Boolean);
begin
  { The window's place into the file first: the viewer reads it (and
    writes it back on exit). }
  RememberBounds;
  FEditor.Visible := False;
  Caption := EditionCaption;
  CreateViewer;
  { The window is already on screen and won't be resized now (unless
    StartFullscreen): give the viewer its real size. }
  HandleFormResize(Self);
  FStarted := True;
  if FView.CanFocus then
    FView.SetFocus;
  if APaste then
    FMView.StartWithPaste
  else
    FMView.Start(APath);
end;

{ The first dropped file or folder is opened: its folder becomes the
  browsing root, as with a command line start. Several dropped files:
  only the first counts. Folders dropped on the open sort panel go to
  its slots instead (Phase G). }
procedure TMainForm.HandleDropFiles(Sender: TObject; const FileNames: array of string);
var
  Path: string;
begin
  if Length(FileNames) = 0 then
    Exit;
  { Not checked here: that would read the disk on the window thread.
    The scanner reports "Not found" (Day 19). }
  Path := FileNames[0];

  { Folders dropped on the open sort panel become sort folders. }
  if Assigned(FMView) and DropOnSortPanel(FileNames) then
  begin
    Application.BringToFront;
    Exit;
  end;

  if FMView = nil then
    StartViewerFromEditor(Path)   { dropped on the settings editor }
  else
    FMView.OpenMedia(Path);

  { The window usually isn't active after a drop from Explorer. }
  Application.BringToFront;
  if Assigned(FView) and FView.CanFocus then
    FView.SetFocus;
end;

{ Esc in the viewer (no mode on): back to the settings screen. Not
  here: this runs inside the view's key handler, and the view goes. }
procedure TMainForm.HandleSettingsRequest(Sender: TObject);
begin
  Application.QueueAsyncCall(@ReturnToEditor, 0);
end;

{ The viewer ends (threads stopped, settings saved, as on exit) and the
  settings editor shows, as after a start without an image. }
procedure TMainForm.ReturnToEditor(AData: PtrInt);
begin
  if FMView = nil then
    Exit;
  if FFullscreen then
    SetFullscreen(False);
  RememberBounds;

  FDeliveryTimer.Enabled := False;
  OnResize := nil;
  DetachViews;
  { The views first (they reach TMView's renderer), then the viewer -
    in the background (user, Day 25: the settings show at once). Its
    settings are saved now (the settings screen reads them next), its
    threads told to stop; FCloseTimer frees it once they are back. }
  FView := nil;
  FreeAndNil(FCpuView);
  FreeAndNil(FGLView);
  FMView.BeginClose;
  FClosingViewer := FMView;
  FMView := nil;
  FCloseStartTick := GetTickCount64;
  FreeAndNil(FPopupMenu);
  FreeAndNil(FSortMenu);
  FUndoItem := nil;
  FMakeIconItem := nil;
  { Leaving the viewer: back to the place before side by side. }
  if FSideBySide and FSideHaveBounds then
    BoundsRect := FSideBounds;
  FSideItem := nil;
  FLockFiltersItem := nil;
  FApplyFiltersItem := nil;
  FResizeItem := nil;
  FMagnifierItem := nil;
  FFollowItems[0] := nil;
  FFollowItems[1] := nil;
  FFollowItems[2] := nil;
  FSideBySide := False;
  FSideWaitUntil := 0;
  FSideAgainAt := 0;
  FViewerEnded := True;
  { The Esc that got here (or its key repeat) must not also end MView
    on the settings screen: wait until it is released (if it still is
    down; a quick press may be up already). }
  FEscHeld := GetKeyState(VK_ESCAPE) < 0;
  FCropItem := nil;
  FExtensionItems := nil;
  FStarted := False;
  FCursorHidden := False;
  FMenuOpen := False;

  ShowEditor(False);
  Caption := EditionCaption + ' - settings';
  FEditor.FocusEditor;
  { Save and View images wait (a spinner) until the viewer has closed. }
  FEditor.Busy := True;
  FCloseTimer.Enabled := True;
end;


const
  { Threads not back after this long: freed the old way (waiting, with
    the watchdog's deadline). }
  CloseWaitMs = 15000;

procedure TMainForm.HandleCloseTimer(Sender: TObject);
begin
  { A copy under way is waited for however long it takes (never half a
    file); anything else at most CloseWaitMs. }
  if (FClosingViewer = nil) or FClosingViewer.CloseFinished
    or ((GetTickCount64 - FCloseStartTick > CloseWaitMs) and not FClosingViewer.FileJobsBusy) then
    FinishClosingViewer;
end;

procedure TMainForm.FinishClosingViewer(AOnExit: Boolean);
var
  Viewer: TMView;
begin
  FCloseTimer.Enabled := False;
  { A kept Save first: the closing viewer writes no settings any more
    (they were saved at Esc), and a worker stuck in a read below must
    not cost the user's save. The window's place again after it (the
    editor's text holds the place from when it was loaded). }
  if Assigned(FEditor) and FEditor.FlushPendingSave and (FMView = nil) then
    RememberBounds;
  if FClosingViewer <> nil then
  begin
    Viewer := FClosingViewer;
    FClosingViewer := nil;
    { Its threads are back, normally: this waits for nothing. A worker
      stuck in a read must not freeze the window for good. }
    if Assigned(Watchdog) and not AOnExit then
      Watchdog.ArmExitDeadline(ExitDeadline);
    Viewer.Free;
    if Assigned(Watchdog) and not AOnExit then
      Watchdog.DisarmExitDeadline;
  end;
  { What the settings screen kept (Save, View images). }
  if Assigned(FEditor) then
    FEditor.Busy := False;
end;

procedure TMainForm.HandleFormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  { Settings screen, Ctrl+V with an image (and no text) in the
    clipboard: the viewer opens with it (Day 21, user). Text is pasted
    into the editor as usual. }
  if (Key = VK_V) and (Shift = [ssCtrl]) and (FMView = nil) and Assigned(FEditor)
    and FEditor.Visible and Clipboard.HasPictureFormat
    and not Clipboard.HasFormat(PredefinedClipboardFormat(pcfText)) then
  begin
    Key := 0;
    StartViewerFromEditor('', True);
    Exit;
  end;
  { Only the settings screen: the viewer's keys go to the mouse engine. }
  if (Key <> VK_ESCAPE) or (Shift <> []) or Assigned(FMView)
    or (FEditor = nil) or not FEditor.Visible then
    Exit;
  if FEscHeld then
  begin
    Key := 0;
    Exit;
  end;
  { The "Try it here" area tries Esc out; an open list closes with it. }
  if (ActiveControl is TTryArea)
    or ((ActiveControl is TComboBox) and TComboBox(ActiveControl).DroppedDown) then
    Exit;
  Key := 0;
  FEditor.RequestExit;
end;

procedure TMainForm.HandleFormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
    FEscHeld := False;
end;

{ The settings screen's "Total Commander side by side": MView to the left
  half of its screen, Total Commander to the right, in the last session's
  folder ([Startup] LastDirectory), else Documents (user, Day 22). Not a
  toggle: the window can be moved back as usual. }
procedure TMainForm.HandleEditorSideBySide(Sender: TObject);
var
  Config: TConfig;
  Work, LeftHalf: TRect;
  Wnd: THandle;
  Exe, Folder, Configured: string;
  Mid: Integer;
begin
  if FEditor = nil then
    Exit;
  Folder := '';
  Configured := '';
  Config := TConfig.Create;
  try
    try
      Config.Load;
      Folder := Config.LastDirectory;
      Configured := Config.TotalCommander;
    except
      { Unreadable ini: Documents, and look for Total Commander. }
    end;
  finally
    Config.Free;
  end;
  if (Trim(Folder) = '') or not DirectoryExists(Folder) then
    Folder := UserDocumentsDirectory;
  Folder := ExcludeTrailingPathDelimiter(Folder);

  Wnd := FindTotalCommanderWindow;
  Exe := TotalCommanderExe(Configured, Wnd);
  if (Wnd = 0) and (Exe = '') then
  begin
    FEditor.ShowNote('Total Commander not found: put its path into [Sort] TotalCommander= above, '
      + 'and Save.');
    Exit;
  end;

  Work := Monitor.WorkareaRect;
  Mid := Work.Left + (Work.Right - Work.Left) div 2;
  LeftHalf := Rect(Work.Left, Work.Top, Mid, Work.Bottom);
  FSideLeft := LeftHalf;
  FSideRight := Rect(Mid, Work.Top, Work.Right, Work.Bottom);
  if WindowState <> wsNormal then
    WindowState := wsNormal;
  if not PlaceWindow(Handle, LeftHalf) then
    BoundsRect := LeftHalf;

  if (Exe <> '') and not OpenInTotalCommander(Exe, Folder) then
  begin
    FEditor.ShowNote('Total Commander could not be started: ' + Exe);
    Exit;
  end;

  if FEditorSideTimer = nil then
  begin
    FEditorSideTimer := TTimer.Create(Self);
    FEditorSideTimer.Interval := 100;
    FEditorSideTimer.OnTimer := @HandleEditorSideTimer;
  end;
  if Wnd <> 0 then
  begin
    if PlaceWindow(Wnd, FSideRight) then
      FEditor.ShowNote('Total Commander side by side, in ' + Folder)
    else
      FEditor.ShowNote('Total Commander could not be moved (does it run as administrator?)');
    { It gets the folder a moment later and may bring itself up where it
      was: placed once more. }
    FEditorSideUntil := 0;
    FEditorSideAgainAt := GetTickCount64 + 600;
  end
  else
  begin
    FEditorSideUntil := GetTickCount64 + 60000;
    FEditorSideAgainAt := 0;
    FEditor.ShowNote('starting Total Commander ...');
  end;
  FEditorSideTimer.Enabled := True;
end;

procedure TMainForm.HandleEditorSideTimer(Sender: TObject);
var
  Wnd: THandle;
begin
  Wnd := FindTotalCommanderWindow;
  if (FEditorSideAgainAt > 0) and (GetTickCount64 >= FEditorSideAgainAt) then
  begin
    FEditorSideAgainAt := 0;
    if Wnd <> 0 then
      PlaceWindow(Wnd, FSideRight);
  end;
  if FEditorSideUntil > 0 then
  begin
    if (Wnd <> 0) and IsWindowVisible(Wnd) then
    begin
      FEditorSideUntil := 0;
      if PlaceWindow(Wnd, FSideRight) then
      begin
        if Assigned(FEditor) then
          FEditor.ShowNote('Total Commander side by side');
      end
      else if Assigned(FEditor) then
        FEditor.ShowNote('Total Commander could not be moved (does it run as administrator?)');
      FEditorSideAgainAt := GetTickCount64 + 600;
    end
    else if GetTickCount64 > FEditorSideUntil then
    begin
      FEditorSideUntil := 0;
      if Assigned(FEditor) then
        FEditor.ShowNote('Total Commander''s window did not appear');
    end;
  end;
  if (FEditorSideUntil = 0) and (FEditorSideAgainAt = 0) then
    FEditorSideTimer.Enabled := False;
end;

{ Only one instance: a second MView (e.g. started by Total Commander)
  sent its file or folder (uSingleInstance's listener, UI thread, inside
  its message). Opened right after: the sender waits for the answer. }
procedure TMainForm.HandleHandedOver(const APath: string);
begin
  FHandedOverPath := APath;
  Application.QueueAsyncCall(@OpenHandedOver, 0);
end;

procedure TMainForm.OpenHandedOver(AData: PtrInt);
var
  Path: string;
begin
  Path := FHandedOverPath;
  FHandedOverPath := '';
  if WindowState = wsMinimized then
    WindowState := wsNormal;
  Application.BringToFront;
  if Path = '' then
    Exit;            { started without a file: just come to the front }
  if FMView = nil then
    StartViewerFromEditor(Path)
  else
    FMView.OpenMedia(Path);
  if Assigned(FView) and FView.CanFocus then
    FView.SetFocus;
end;

procedure TMainForm.HandleEditorExit(Sender: TObject);
begin
  Close;
end;

{ Every way of closing ends here (Esc, gesture, menu, window button,
  editor). The shutdown that follows waits for the worker threads; if
  one is stuck in a decode, the watchdog ends the process after the
  deadline instead of leaving it running without a window. }
procedure TMainForm.HandleFormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  RememberBounds;
  if Assigned(Watchdog) then
    Watchdog.ArmExitDeadline(ExitDeadline);
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  { The view is freed after this, together with the form's other
    components; make sure it can't paint with a freed renderer. }
  { A return to the settings screen (Esc) may still be waiting. }
  Application.RemoveAsyncCalls(Self);
  uExtensions.OnMenuOpen := nil;
  OnResize := nil;
  FDeliveryTimer.Enabled := False;
  FDeliveryTimer.OnTimer := nil;
  OnDeactivate := nil;
  { The renderer belongs to TMView and goes with it. }
  DetachViews;
  FreeAndNil(FMView);
  { A viewer still closing from Esc (and a save kept by the settings;
    not a kept "View images": MView is ending). }
  if Assigned(FEditor) then
    FEditor.CancelPendingView;
  FinishClosingViewer(True);
  FCloseTimer.OnTimer := nil;
  FreeAndNil(FSortMenuIcons);
end;

procedure TMainForm.FormShow(Sender: TObject);
var
  Path: string;
  Flat: Boolean;
begin
  if FMView = nil then
  begin
    { The settings editor. }
    if Assigned(FEditor) and FEditor.Visible then
      FEditor.FocusEditor;
    Exit;
  end;

  if FView.CanFocus then
    FView.SetFocus;

  { OnShow can fire again (e.g. after the window style changes);
    start only once. }
  if FStarted then
    Exit;
  FStarted := True;

  { Spec §11: a file or folder on the command line. (Without one the
    editor came first, and its "View images" started the viewer;
    [Startup] Mode 1 / 2: the last session, else MView's own folder.) }
  Path := ParamStr(1);
  Flat := False;
  if FWelcome <> '' then
  begin
    { The very first start: the map of the screen, alone. }
    Path := FWelcome;
    Flat := True;
  end
  else if (Path = '') and (FMView.Config.LastDirectory = '') then
  begin
    Path := ExtractFilePath(ParamStr(0));
    Flat := True;     { not the folders around MView's own }
  end;
  FMView.Start(Path, Flat);

  { [Startup] Mode=2: side by side with Total Commander, once the window
    is up, Total Commander in the start folder. }
  if FMView.Config.StartMode = 2 then
  begin
    if Path = '' then
      FStartFolder := FMView.Config.LastDirectory
    else if DirectoryExists(Path) then
      FStartFolder := Path
    else
      FStartFolder := ExtractFileDir(Path);
    Application.QueueAsyncCall(@StartSideBySide, 0);
  end;
end;

procedure TMainForm.StartSideBySide(AData: PtrInt);
begin
  if (FMView = nil) or FSideBySide then
    Exit;
  ToggleSideBySide(ExcludeTrailingPathDelimiter(FStartFolder));
end;

{ Spec §8.5: the GPU renderer if OpenGL is usable (and [Renderer]
  UseGPU=1), otherwise the CPU renderer. The reason for a fallback is
  shown in the diagnostics line (D). }
procedure TMainForm.CreateView;
var
  Reason: string;
  Cpu: TCpuRenderer;
begin
  Reason := 'GPU switched off (UseGPU=0)';
  if FMView.Config.UseGPU and TryCreateGLView(Reason) then
    Exit;

  FCpuView := TMediaView.Create(Self);
  FCpuView.Parent := Self;
  FCpuView.Align := alClient;
  FCpuView.OnCommand := @HandleCommand;
  FCpuView.OnOverlayMouse := @FMView.HandleOverlayMouse;
  FView := FCpuView;

  Cpu := TCpuRenderer.Create;
  Cpu.Note := Reason;
  FCpuView.SetRenderer(Cpu);
  FMView.AttachView(FCpuView, Cpu);
end;

function TMainForm.TryCreateGLView(out AReason: string): Boolean;
var
  GLView: TGLMediaView;
  GLRenderer: TGLRenderer;
begin
  Result := False;
  AReason := '';
  GLView := nil;
  try
    GLView := TGLMediaView.Create(Self);
    GLView.Parent := Self;
    GLView.Align := alClient;
    { Creates the window and the OpenGL context now, so a failure
      shows here and not at the first paint. }
    GLView.HandleNeeded;
    GLRenderer := TGLRenderer.Create(GLView, FMView.Config.UseMipMaps);
  except
    on E: Exception do
    begin
      AReason := 'GPU not used: ' + E.Message;
      FreeAndNil(GLView);
      Exit;
    end;
  end;

  GLView.OnCommand := @HandleCommand;
  GLView.OnOverlayMouse := @FMView.HandleOverlayMouse;
  GLView.Renderer := GLRenderer;
  FGLView := GLView;
  FView := GLView;
  FMView.AttachView(GLView, GLRenderer);
  Result := True;
end;

function TMainForm.ViewInput: TMouseEngine;
begin
  if Assigned(FGLView) then
    Result := FGLView.Input
  else if Assigned(FCpuView) then
    Result := FCpuView.Input
  else
    Result := nil;
end;

{ Another program got the focus: no key or side button stays held. }
procedure TMainForm.HandleDeactivate(Sender: TObject);
begin
  FEscHeld := False;   { its release would go to the other program }
  if Assigned(ViewInput) then
    ViewInput.FocusLost;
  if Assigned(FMView) then
    FMView.SortPanelMouseGone;
end;

procedure TMainForm.HandleCommand(Sender: TObject; ACommand: TCommand;
  const AArgs: TCommandArgs);
var
  P: TPoint;
  I: Integer;
  Entry: TExtensionMenuEntry;
  Order: TSortMode;
begin
  { Placing windows is the window's business. }
  if ACommand = cmdSideBySide then
  begin
    ToggleSideBySide;
    Exit;
  end;
  { The menu is the window's business; X, Y are surface pixels. }
  if ACommand = cmdShowMenu then
  begin
    if Assigned(FView) and Assigned(FPopupMenu) then
    begin
      if FCursorHidden then
      begin
        FCursorHidden := False;
        FView.Cursor := FMView.ViewCursor;
      end;
      P := FView.ClientToScreen(Point(Round(AArgs.X), Round(AArgs.Y)));
      FCropItem.Visible := FMView.CanCrop;
      FUndoItem.Caption := FMView.UndoCaption;
      FUndoItem.Visible := FUndoItem.Caption <> '';
      FMakeIconItem.Enabled := FMView.CanMakeIcon;
      FRotateItem.Visible := FMView.CanRotateLossless;
      FSideItem.Checked := FSideBySide;
      FSortPanelItem.Checked := FMView.SortPanelVisible;
      FPreviewStripItem.Checked := FMView.PreviewStripPinned;
      FDirPreviewItem.Checked := FMView.DirPreview;
      FLockFiltersItem.Checked := FMView.FiltersLocked;
      FApplyFiltersItem.Enabled := FMView.CanApplyFilters;
      { What goes into the copy (Day 26: the measurement too). }
      if FMView.ViewRotated and FMView.CopyBurnsIn then
        FApplyFiltersItem.Caption := 'Apply filters, rotation and measurement to a copy'
      else if FMView.ViewRotated then
        FApplyFiltersItem.Caption := 'Apply filters and rotation to a copy'
      else if FMView.CopyBurnsIn then
        FApplyFiltersItem.Caption := 'Apply filters and measurement to a copy'
      else
        FApplyFiltersItem.Caption := 'Apply filters to a copy';
      FResizeItem.Enabled := FMView.CanResizeToShown;
      FMagnifierItem.Checked := FMView.MagnifierOn;
      for I := 0 to 2 do
        FFollowItems[I].Checked := FMView.FollowMode = I;
      for Order := Low(TSortMode) to High(TSortMode) do
        FSortOrderItems[Order].Checked := FMView.SortOrder = Order;
      FRapidItem.Checked := FMView.RapidSelection;
      { The edition's entries ask the edition (nil test: enabled /
        unchecked). }
      for I := 0 to High(FExtensionItems) do
      begin
        Entry := MenuEntry(I);
        FExtensionItems[I].Enabled := (not Assigned(Entry.IsEnabled)) or Entry.IsEnabled(FMView);
        FExtensionItems[I].Checked := Assigned(Entry.IsChecked) and Entry.IsChecked(FMView);
      end;
      if FMView.ShownSizeText <> '' then
        FResizeItem.Caption := 'Resize to the size shown (' + FMView.ShownSizeText + ')'
      else
        FResizeItem.Caption := 'Resize to the size shown';
      FMenuOpen := True;
      try
        FPopupMenu.PopUp(P.X, P.Y);
      finally
        FMenuOpen := False;
        { Time in the menu doesn't count towards hiding the cursor. }
        if Assigned(ViewInput) then
          ViewInput.NoteActivity(GetTickCount64);
      end;
    end;
    Exit;
  end;
  FMView.Execute(ACommand, AArgs);
end;

{ Exit feels immediate: the window disappears at once. Stopping the
  threads (which may have to wait for a decode that can't be
  interrupted) happens afterwards, while the window is already gone. }
procedure TMainForm.HandleExitRequest(Sender: TObject);
begin
  Hide;
  Close;
end;

procedure TMainForm.HandleSaveMenuClick(Sender: TObject);
begin
  FMView.Execute(cmdSaveImage);
end;

{ "Save image as ...": a save dialog, starting in the folder last used
  for this (else the save folder), with the image's name as PNG. }
procedure TMainForm.HandleSaveAsMenuClick(Sender: TObject);
var
  Dialog: TSaveDialog;
  Dir, Suggested: string;
  SaveName, Ext: string;
begin
  if not FMView.CanSaveImage then
  begin
    { Nothing to save, or a save still running: Save says which. }
    FMView.Execute(cmdSaveImage);
    Exit;
  end;
  FMView.SaveAsSuggestion(Dir, Suggested);
  Dialog := TSaveDialog.Create(nil);
  try
    Dialog.Title := 'Save image as';
    Dialog.InitialDir := Dir;
    Dialog.FileName := Suggested;
    { PNG, or TIFF (Day 26: in the microscopy edition with the scale,
      ImageJ's way, so Fiji opens it in µm). }
    Dialog.Filter := 'PNG image (*.png)|*.png|TIFF image (*.tif)|*.tif';
    Dialog.FilterIndex := 1;
    Dialog.DefaultExt := 'png';
    Dialog.Options := Dialog.Options + [ofOverwritePrompt, ofPathMustExist, ofNoReadOnlyReturn];
    if Dialog.Execute then
    begin
      SaveName := Dialog.FileName;
      { TIFF chosen: its ending, whatever the suggestion had ("cell.png",
        "cell.jpg" -> "cell.tif"; "cell.v2" -> "cell.v2.tif"). The dialog
        asked about the name it returned: a renamed one is asked here. }
      Ext := LowerCase(ExtractFileExt(SaveName));
      if (Dialog.FilterIndex = 2) and (Ext <> '.tif') and (Ext <> '.tiff') then
      begin
        if (Ext = '.png') or (Ext = '.jpg') or (Ext = '.jpeg') or (Ext = '.bmp')
          or (Ext = '.gif') then
          SaveName := ChangeFileExt(SaveName, '.tif')
        else
          SaveName := SaveName + '.tif';
        if FileExists(SaveName) and (MessageDlg('Save image as', ExtractFileName(SaveName)
          + ' exists already. Replace it?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
          Exit;
      end;
      FMView.SaveImageAs(SaveName);
    end;
  finally
    Dialog.Free;
  end;
  { Time in the dialog doesn't count towards hiding the cursor. }
  if Assigned(ViewInput) then
    ViewInput.NoteActivity(GetTickCount64);
end;

procedure TMainForm.HandleSaveDebugMenuClick(Sender: TObject);
begin
  FMView.Execute(cmdSaveDebug);
end;

procedure TMainForm.HandleCropMenuClick(Sender: TObject);
begin
  FMView.Execute(cmdCropSelection);
end;

procedure TMainForm.HandlePasteMenuClick(Sender: TObject);
begin
  FMView.Execute(cmdPaste);
end;

procedure TMainForm.HandleCopyMenuClick(Sender: TObject);
begin
  FMView.Execute(cmdCopyImage);
end;

function TMainForm.ExitDeadline: Integer;
begin
  { A copy under way (also in a viewer still closing after Esc) may take
    long: never cut it off halfway. }
  if (Assigned(FMView) and FMView.FileJobsBusy)
    or (Assigned(FClosingViewer) and FClosingViewer.FileJobsBusy) then
    Result := FileJobDeadlineMs
  else
    Result := ExitDeadlineMs;
end;

{ The views reach TMView (renderer, commands, the sort panel): cut them
  off before it goes. }
procedure TMainForm.DetachViews;
begin
  if Assigned(FCpuView) then
  begin
    FCpuView.SetRenderer(nil);
    FCpuView.OnCommand := nil;
    FCpuView.OnOverlayMouse := nil;
  end;
  if Assigned(FGLView) then
  begin
    FGLView.Renderer := nil;
    FGLView.OnCommand := nil;
    FGLView.OnOverlayMouse := nil;
  end;
end;

{ ---- Sorting (Phase G, G1) ---- }

{ On / off (Day 27, user: a toggle). }
procedure TMainForm.HandleSortPanelMenuClick(Sender: TObject);
begin
  FMView.ShowSortPanel(not FMView.SortPanelVisible);
end;

procedure TMainForm.AddMenuLine;
var
  Item: TMenuItem;
begin
  Item := TMenuItem.Create(FPopupMenu);
  Item.Caption := '-';
  FPopupMenu.Items.Add(Item);
end;

{ Drawn here (LCL draws every Windows menu entry itself; an entry with
  its own OnDrawItem is left to it): the menu's background, the hover,
  a tick when checked, the caption bold, deep green for Side by side.
  The submenu arrow of "Follow" is drawn by Windows. }
procedure TMainForm.HandleStrongMenuDraw(Sender: TObject; ACanvas: TCanvas; ARect: TRect;
  AState: TOwnerDrawState);
var
  Item: TMenuItem;
  Gutter, CX, CY, S: Integer;
  ItemText: string;
begin
  if not (Sender is TMenuItem) then
    Exit;
  Item := TMenuItem(Sender);
  ACanvas.Font.Assign(Screen.MenuFont);
  ACanvas.Font.Style := [fsBold];
  if Item.Tag = StrongGreenTag then
    ACanvas.Font.Color := StrongGreen
  else if Item.Tag = StrongRedTag then
    ACanvas.Font.Color := StrongRed
  else
    ACanvas.Font.Color := clMenuText;
  if ThemeServices.ThemesEnabled then
  begin
    { As the other entries: the themed menu background and hover (the
      text keeps its colour on the light hover). }
    ThemeServices.DrawElement(ACanvas.Handle, ThemeServices.GetElementDetails(tmPopupBackground), ARect);
    if odSelected in AState then
      ThemeServices.DrawElement(ACanvas.Handle, ThemeServices.GetElementDetails(tmPopupItemHot), ARect)
    else
      ThemeServices.DrawElement(ACanvas.Handle, ThemeServices.GetElementDetails(tmPopupItemNormal), ARect);
  end
  else
  begin
    if odSelected in AState then
    begin
      ACanvas.Brush.Color := clHighlight;
      ACanvas.Font.Color := clHighlightText;
    end
    else
      ACanvas.Brush.Color := clMenu;
    ACanvas.FillRect(ARect);
  end;
  { Where the other entries' text starts (after the check column). }
  Gutter := ARect.Height + Max(8, ARect.Height div 2);
  if Item.Checked then
  begin
    CX := ARect.Left + Gutter div 2;
    CY := (ARect.Top + ARect.Bottom) div 2;
    S := Max(3, ARect.Height div 6);
    ACanvas.Pen.Color := ACanvas.Font.Color;
    ACanvas.Pen.Width := 2;
    ACanvas.Line(CX - S - 1, CY, CX - 1, CY + S);
    ACanvas.Line(CX - 1, CY + S, CX + S + 2, CY - S - 1);
    ACanvas.Pen.Width := 1;
  end;
  ItemText := StringReplace(Item.Caption, '&&', #1, [rfReplaceAll]);
  ItemText := StringReplace(ItemText, '&', '', [rfReplaceAll]);
  ItemText := StringReplace(ItemText, #1, '&', [rfReplaceAll]);
  ACanvas.Brush.Style := bsClear;
  ACanvas.TextOut(ARect.Left + Gutter, ARect.Top + (ARect.Height - ACanvas.TextHeight(ItemText)) div 2,
    ItemText);
  ACanvas.Brush.Style := bsSolid;
end;

procedure TMainForm.HandleStrongMenuMeasure(Sender: TObject; ACanvas: TCanvas;
  var AWidth, AHeight: Integer);
begin
  if not (Sender is TMenuItem) then
    Exit;
  ACanvas.Font.Assign(Screen.MenuFont);
  ACanvas.Font.Style := [fsBold];
  AWidth := Max(AWidth, ACanvas.TextWidth(TMenuItem(Sender).Caption) + 3 * AHeight + 16);
  AHeight := Max(AHeight, ACanvas.TextHeight('Ag') + 8);
end;

procedure TMainForm.HandleFilterPanelMenuClick(Sender: TObject);
begin
  FMView.ShowFilterPanel(True);
end;

procedure TMainForm.HandleLockFiltersMenuClick(Sender: TObject);
var
  Args: TCommandArgs;
begin
  Args := Default(TCommandArgs);
  Args.Value := 1;                     { said: from the menu }
  FMView.Execute(cmdLockFilters, Args);
end;

procedure TMainForm.HandleFollowMenuClick(Sender: TObject);
begin
  if Sender is TMenuItem then
    FMView.SetFollowMode(TMenuItem(Sender).Tag);
end;

procedure TMainForm.HandlePreviewStripMenuClick(Sender: TObject);
begin
  FMView.Execute(cmdPreviewStrip);
end;

procedure TMainForm.HandleRapidMenuClick(Sender: TObject);
begin
  FMView.SetRapidSelection(not FMView.RapidSelection);
end;

procedure TMainForm.HandleSortOrderMenuClick(Sender: TObject);
begin
  if Sender is TMenuItem then
    FMView.SetSortOrder(TSortMode(TMenuItem(Sender).Tag));
end;

procedure TMainForm.HandleMagnifierMenuClick(Sender: TObject);
begin
  FMView.Execute(cmdMagnifier);
end;

procedure TMainForm.HandleResizeMenuClick(Sender: TObject);
begin
  FMView.Execute(cmdResizeToShown);
end;

procedure TMainForm.HandleApplyFiltersMenuClick(Sender: TObject);
begin
  FMView.Execute(cmdApplyFilters);
end;

procedure TMainForm.HandleDeleteMenuClick(Sender: TObject);
begin
  FMView.Execute(cmdDeleteImage);
end;

procedure TMainForm.HandleUndoMenuClick(Sender: TObject);
begin
  FMView.Execute(cmdUndo);
end;

function IsIconFileName(const AName: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(AName));
  Result := (Ext = '.ico') or (Ext = '.png');
end;

{ A folder name as a menu caption: "&" would underline the next letter. }
function MenuText(const AText: string): string;
begin
  Result := StringReplace(AText, '&', '&&', [rfReplaceAll]);
end;

{ A slot's "..." corner (ASlot >= 0) or the "+" (ASlot = -1): a small
  menu of ways to pick the folder; for a slot also its colour, its place
  and removing it. Every choice for "+" adds a slot. }
procedure TMainForm.HandleSortMenu(ASlot: Integer; const AScreen: TPoint);
const
  MaxMenuIcons = 40;
var
  Folders: TSortFolders;
  Item, Sub: TMenuItem;
  C: TSlotColor;
  I: Integer;
  Dir, IconFolder, Auto: string;
  Icons: TSortIcons;
  Pic: TBGRABitmap;

  function NewItem(AParent: TMenuItem; const ACaption: string; AHandler: TNotifyEvent;
    ATag: Integer = 0): TMenuItem;
  begin
    Result := TMenuItem.Create(FSortMenu);
    Result.Caption := ACaption;
    Result.OnClick := AHandler;
    Result.Tag := ATag;
    if AParent = nil then
      FSortMenu.Items.Add(Result)
    else
      AParent.Add(Result);
  end;

begin
  if FMView = nil then
    Exit;
  if Assigned(FSlotMenuWindow) and FSlotMenuWindow.Visible then
    FSlotMenuWindow.CloseMenu;
  Folders := FMView.Config.SortFolders;
  if (ASlot >= Folders.Count) then
    Exit;
  if ASlot < 0 then
    ASlot := -1;
  FSortMenuSlot := ASlot;
  FMoveTopItem := nil;
  FMoveUpItem := nil;
  FMoveDownItem := nil;
  if FSortMenu = nil then
    FSortMenu := TPopupMenu.Create(Self);
  if FSortMenuIcons = nil then
  begin
    FSortMenuIcons := TStringList.Create;
    { Freed with the form (FormDestroy). }
  end;
  FSortMenu.Items.Clear;

  { Rapid Selection (Day 27): a fixed list; only into the folder, or off. }
  if Folders.Rapid then
  begin
    if ASlot < 0 then
      Exit;
    Item := NewItem(nil, MenuText(Folders.Slot(ASlot).Folder), nil);
    Item.Enabled := False;
    NewItem(nil, 'Open this folder  (swipe over the button)', @HandleSortOpenClick);
    NewItem(nil, '-', nil);
    NewItem(nil, 'Rapid sorting off', @HandleRapidMenuClick);
  end
  else
  begin

  if ASlot >= 0 then
  begin
    Item := NewItem(nil, MenuText(Folders.Slot(ASlot).Folder), nil);
    Item.Enabled := False;
    { Into the folder (also: a swipe left or right over the button, or a
      wheel click on it). }
    NewItem(nil, 'Open this folder  (swipe over the button)', @HandleSortOpenClick);
    { The name in the list only; the folder keeps its own (Day 27,
      testers). }
    NewItem(nil, 'Rename ...  (in this list)', @HandleSortRenameClick);
    { A new folder beside this one or inside it, "<name>_001", added to
      the list below this button (Day 27, testers). }
    NewItem(nil, 'Make folder  (beside this one)', @HandleSortMakeFolderClick, 0);
    NewItem(nil, 'Make subfolder  (inside this one)', @HandleSortMakeFolderClick, 1);
    NewItem(nil, '-', nil);
  end;
  NewItem(nil, 'Choose folder ...', @HandleSortChooseClick);

  { Recent folders (not the slot's own). }
  Sub := NewItem(nil, 'Recent folders', nil);
  for I := 0 to Folders.Recent.Count - 1 do
    if (ASlot < 0) or not SameText(Folders.Recent[I], Folders.Slot(ASlot).Folder) then
      NewItem(Sub, MenuText(Folders.Recent[I]), @HandleSortRecentClick, I);
  Sub.Enabled := Sub.Count > 0;

  if FMView.Navigator.HasCurrentImage then
  begin
    Dir := ExcludeTrailingPathDelimiter(FMView.FolderOnDisk);
    NewItem(nil, 'This image''s folder:  ' + MenuText(FolderDisplayName(Dir)),
      @HandleSortImageFolderClick);
    if ExtractFileDir(Dir) <> Dir then
      NewItem(nil, 'Its parent folder:  ' + MenuText(FolderDisplayName(ExtractFileDir(Dir))),
        @HandleSortParentFolderClick);
  end;

  if ASlot >= 0 then
  begin
    NewItem(nil, '-', nil);
    Sub := NewItem(nil, 'Colour', nil);
    for C := Low(TSlotColor) to High(TSlotColor) do
    begin
      Item := NewItem(Sub, SlotColorName(C), @HandleSortColorClick, Ord(C));
      Item.RadioItem := True;
      Item.Checked := Folders.Slot(ASlot).Color = C;
    end;
    { The icon: by name, none, one of the icon folder's, another file. }
    Sub := NewItem(nil, 'Icon', nil);
    Icons := FMView.SortIcons;
    IconFolder := FMView.Config.IconFilesFolder;
    Auto := IconBaseName(Folders.Slot(ASlot).Folder);
    { Another file first (Day 27, testers: with many icons it was far
      down), then the icon folder, the automatic choices, the folder's
      icons. }
    { Used most (1.1, user): bold, deep green. }
    NewItem(Sub, 'Choose icon file ...', @HandleSortIconChooseClick, SlotMenuStrongTag);
    NewItem(Sub, 'Open the icon folder', @HandleSortIconFolderClick);
    NewItem(Sub, '-', nil);
    Item := NewItem(Sub, 'By name  (' + MenuText(Auto) + '.ico / .png in the icon folder)',
      @HandleSortIconClick, -1);
    Item.RadioItem := True;
    Item.Checked := Folders.Slot(ASlot).Icon = '';
    Item := NewItem(Sub, 'Coloured folder (no icon)', @HandleSortIconClick, -2);
    Item.RadioItem := True;
    Item.Checked := Folders.Slot(ASlot).Icon = '-';
    FSortMenuIcons.Clear;
    if Icons.Loaded then
    begin
      if Icons.FolderFiles.Count > 0 then
        NewItem(Sub, '-', nil);
      for I := 0 to Min(Icons.FolderFiles.Count, MaxMenuIcons) - 1 do
      begin
        FSortMenuIcons.Add(Icons.FolderFiles[I]);
        Item := NewItem(Sub, MenuText(Icons.FolderFiles[I]), @HandleSortIconClick,
          FSortMenuIcons.Count - 1);
        Item.RadioItem := True;
        Item.Checked := SameText(Folders.Slot(ASlot).Icon, Icons.FolderFiles[I]);
        Pic := Icons.Bitmap(IconFolder + Icons.FolderFiles[I], 16);
        if Pic <> nil then
          Item.Bitmap.Assign(Pic.Bitmap);
      end;
      if Icons.FolderFiles.Count > MaxMenuIcons then
        NewItem(Sub, Format('(%d more in the icon folder: Choose icon file ...)',
          [Icons.FolderFiles.Count - MaxMenuIcons]), nil).Enabled := False;
    end
    else
      NewItem(Sub, '(reading the icon folder ...)', nil).Enabled := False;
    { To the top (Day 27, testers); the window stays open, up / down
      repeat while held. }
    NewItem(nil, '-', nil);
    FMoveTopItem := NewItem(nil, 'Move to top', @HandleSortMoveClick, MoveToTopTag);
    FMoveTopItem.Hint := SlotMenuRepeatHint;
    FMoveUpItem := NewItem(nil, 'Move up  (hold: on and on)', @HandleSortMoveClick, -1);
    FMoveUpItem.Hint := SlotMenuRepeatHint;
    FMoveDownItem := NewItem(nil, 'Move down  (hold: on and on)', @HandleSortMoveClick, 1);
    FMoveDownItem.Hint := SlotMenuRepeatHint;
    UpdateSortMoveItems;
    { To another page of the panel (1.1, testers): copy or cut, then
      paste in the other list (after the button its menu is opened on). }
    Sub := NewItem(nil, 'Copy / move entry', nil);
    NewItem(Sub, 'Copy entry', @HandleSortClipClick, 0);
    NewItem(Sub, 'Cut entry  (it leaves its place when pasted)', @HandleSortClipClick, 1);
    Item := NewItem(Sub, 'Paste entry  (after this one)', @HandleSortClipClick, 2);
    if Folders.HasClip then
      Item.Caption := 'Paste entry "' + MenuText(Folders.ClipName) + '"  (after this one)'
    else
      Item.Enabled := False;
    NewItem(nil, '-', nil);
    NewItem(nil, 'Remove this button', @HandleSortRemoveClick);
  end
  else if Folders.HasClip then
  begin
    { The panel's own menu (no button): paste on top, e.g. into an empty
      list. }
    NewItem(nil, '-', nil);
    NewItem(nil, 'Paste entry "' + MenuText(Folders.ClipName) + '"  (on top)', @HandleSortClipClick, 2);
  end;

  end;   { not Rapid Selection }

  { The panel stays open behind its menu (the mouse leaves the view). }
  FMView.ShowSortPanel(True);
  if FSlotMenuWindow = nil then
  begin
    FSlotMenuWindow := TSlotMenuWindow.CreateMenu(Self);
    FSlotMenuWindow.OnClosed := @HandleSlotMenuClosed;
  end;
  FMenuOpen := True;
  { Left of the panel, so the folders stay in sight (Day 27, testers). }
  FSlotMenuWindow.ShowMenu(FSortMenu.Items, AScreen.X - 2, AScreen.Y - 8);
end;

procedure TMainForm.HandleSlotMenuClosed(Sender: TObject);
begin
  FMenuOpen := False;
  if Assigned(ViewInput) then
    ViewInput.NoteActivity(GetTickCount64);
end;

{ Move to top / up / down: enabled where the slot can go. }
procedure TMainForm.UpdateSortMoveItems;
var
  N: Integer;
begin
  if FMView = nil then
    Exit;
  N := FMView.Config.SortFolders.Count;
  if Assigned(FMoveTopItem) then
    FMoveTopItem.Enabled := FSortMenuSlot > 0;
  if Assigned(FMoveUpItem) then
    FMoveUpItem.Enabled := FSortMenuSlot > 0;
  if Assigned(FMoveDownItem) then
    FMoveDownItem.Enabled := (FSortMenuSlot >= 0) and (FSortMenuSlot < N - 1);
end;

{ "<name>_001", "<name>_002" ...: the first free one beside the slot's
  folder (Tag 0) or inside it (Tag 1), made, and added to the list just
  below the slot. }
procedure TMainForm.HandleSortMakeFolderClick(Sender: TObject);
var
  Folders: TSortFolders;
  Base, Where, NewDir: string;
  N, Index: Integer;
begin
  if (FMView = nil) or (FSortMenuSlot < 0) then
    Exit;
  Folders := FMView.Config.SortFolders;
  if FSortMenuSlot >= Folders.Count then
    Exit;
  Base := ExcludeTrailingPathDelimiter(Folders.Slot(FSortMenuSlot).Folder);
  if TMenuItem(Sender).Tag = 1 then
    Where := Base
  else
    Where := ExtractFileDir(Base);
  if (Where = '') or not DirectoryExists(Where) then
  begin
    FMView.StatusNote('cannot make a folder: ' + Where + ' not found', 3000);
    Exit;
  end;
  NewDir := '';
  for N := 1 to 999 do
    if not DirectoryExists(IncludeTrailingPathDelimiter(Where) + FolderDisplayName(Base)
      + Format('_%.3d', [N])) then
    begin
      NewDir := IncludeTrailingPathDelimiter(Where) + FolderDisplayName(Base) + Format('_%.3d', [N]);
      Break;
    end;
  if (NewDir = '') or not CreateDir(NewDir) then
  begin
    FMView.StatusNote('could not make a folder in ' + Where, 3000);
    Exit;
  end;
  Index := Folders.SetFolder(Folders.Count, NewDir);
  if Index < 0 then
  begin
    FMView.StatusNote('made ' + NewDir + ' (the list is full)', 3000);
    Exit;
  end;
  if Index <> FSortMenuSlot + 1 then
  begin
    Folders.Move(Index, FSortMenuSlot + 1);
    Index := FSortMenuSlot + 1;
  end;
  FMView.SortFoldersChanged(Index);
  FMView.StatusNote('made ' + NewDir, 2500);
end;

{ The folder for the slot the menu is for, or a new slot. }
procedure TMainForm.AssignSortFolder(const AFolder: string);
var
  Folders: TSortFolders;
  Index: Integer;
begin
  if (FMView = nil) or (Trim(AFolder) = '') then
    Exit;
  Folders := FMView.Config.SortFolders;
  if FSortMenuSlot >= 0 then
    Index := FSortMenuSlot
  else
    Index := Folders.Count;
  Index := Folders.SetFolder(Index, AFolder);
  if Index < 0 then
    Exit;   { all slots in use }
  FMView.SortFoldersChanged(Index);
end;

procedure TMainForm.HandleSortChooseClick(Sender: TObject);
var
  Dialog: TSelectDirectoryDialog;
begin
  Dialog := TSelectDirectoryDialog.Create(nil);
  try
    if FSortMenuSlot >= 0 then
      Dialog.Title := 'Folder for this button'
    else
      Dialog.Title := 'Folder for a new button';
    Dialog.InitialDir := FMView.SortStartFolder(FSortMenuSlot);
    Dialog.Options := Dialog.Options + [ofPathMustExist];
    if Dialog.Execute then
      AssignSortFolder(Dialog.FileName);
  finally
    Dialog.Free;
  end;
  if Assigned(ViewInput) then
    ViewInput.NoteActivity(GetTickCount64);
end;

procedure TMainForm.HandleSortRecentClick(Sender: TObject);
var
  Recent: TStrings;
  I: Integer;
begin
  Recent := FMView.Config.SortFolders.Recent;
  I := TMenuItem(Sender).Tag;
  if (I >= 0) and (I < Recent.Count) then
    AssignSortFolder(Recent[I]);
end;

procedure TMainForm.HandleSortImageFolderClick(Sender: TObject);
begin
  if FMView.Navigator.HasCurrentImage then
    AssignSortFolder(ExcludeTrailingPathDelimiter(FMView.FolderOnDisk));
end;

procedure TMainForm.HandleSortParentFolderClick(Sender: TObject);
begin
  if FMView.Navigator.HasCurrentImage then
    AssignSortFolder(ExtractFileDir(ExcludeTrailingPathDelimiter(FMView.FolderOnDisk)));
end;

procedure TMainForm.HandleSortColorClick(Sender: TObject);
begin
  if FSortMenuSlot < 0 then
    Exit;
  FMView.Config.SortFolders.SetColor(FSortMenuSlot, TSlotColor(TMenuItem(Sender).Tag));
  FMView.SortFoldersChanged;
end;

procedure TMainForm.HandleSortMoveClick(Sender: TObject);
var
  Target: Integer;
begin
  if FSortMenuSlot < 0 then
    Exit;
  if TMenuItem(Sender).Tag = MoveToTopTag then
    Target := 0
  else
    Target := FSortMenuSlot + TMenuItem(Sender).Tag;
  if (Target < 0) or (Target >= FMView.Config.SortFolders.Count)
    or (Target = FSortMenuSlot) then
    Exit;
  FMView.Config.SortFolders.Move(FSortMenuSlot, Target);
  { The menu stays open (Day 27): it now is for the slot's new place. }
  FSortMenuSlot := Target;
  UpdateSortMoveItems;
  FMView.SortFoldersChanged(Target);
end;

{ The name the slot has in the list (Day 27, testers); the folder on
  disk is not renamed. }
procedure TMainForm.HandleSortRenameClick(Sender: TObject);
var
  Folders: TSortFolders;
  NewName: string;
begin
  if (FMView = nil) or (FSortMenuSlot < 0) then
    Exit;
  Folders := FMView.Config.SortFolders;
  if FSortMenuSlot >= Folders.Count then
    Exit;
  NewName := Folders.Slot(FSortMenuSlot).Name;
  FMenuOpen := True;
  try
    if not InputQuery('Rename', 'Name in the list (the folder ' + FolderDisplayName(
      Folders.Slot(FSortMenuSlot).Folder) + ' keeps its own; empty = its name):', NewName) then
      Exit;
  finally
    FMenuOpen := False;
  end;
  NewName := Trim(NewName);
  if NewName = '' then
    NewName := FolderDisplayName(Folders.Slot(FSortMenuSlot).Folder);
  Folders.SetName(FSortMenuSlot, NewName);
  FMView.SortFoldersChanged;
end;

procedure TMainForm.HandleRotateMenuClick(Sender: TObject);
begin
  if FMView <> nil then
    FMView.RotateLossless(TOrientOp(TMenuItem(Sender).Tag));
end;

procedure TMainForm.HandleDirPreviewMenuClick(Sender: TObject);
begin
  if FMView <> nil then
    FMView.SetDirPreview(not FMView.DirPreview);
end;

{ Copy (Tag 0), cut (1) or paste (2) a button (1.1). }
procedure TMainForm.HandleSortClipClick(Sender: TObject);
var
  Folders: TSortFolders;
  Why: string;
  Pasted: Integer;
begin
  if FMView = nil then
    Exit;
  Folders := FMView.Config.SortFolders;
  case TMenuItem(Sender).Tag of
    0, 1:
      begin
        if (FSortMenuSlot < 0) or (FSortMenuSlot >= Folders.Count) then
          Exit;
        Folders.CopySlot(FSortMenuSlot, TMenuItem(Sender).Tag = 1);
        FMView.SortFoldersChanged;
        if Folders.ClipIsCut then
          FMView.ShowNote('cut: ' + Folders.ClipName + ' - paste it in another list (its menu: '
            + 'Copy / move entry > Paste); Esc cancels', 8000)
        else
          FMView.ShowNote('copied: ' + Folders.ClipName + ' - paste it in another list (its menu: '
            + 'Copy / move entry > Paste)', 8000);
      end;
    2:
      begin
        Pasted := Folders.PasteSlot(FSortMenuSlot, Why);
        if Pasted < 0 then
          FMView.ShowNote('not pasted: ' + Why, 5000)
        else
        begin
          FMView.SortFoldersChanged(Pasted);
          FMView.ShowNote('pasted: ' + Folders.Slot(Pasted).Name, 3000);
        end;
      end;
  end;
end;

procedure TMainForm.HandleSortRemoveClick(Sender: TObject);
begin
  if FSortMenuSlot < 0 then
    Exit;
  FMView.Config.SortFolders.Remove(FSortMenuSlot);
  FMView.SortFoldersChanged;
end;

{ An icon for slot ASlot: a file in the icon folder is kept by its name,
  any other by its full path. }
procedure TMainForm.SetSlotIcon(ASlot: Integer; const AFile: string);
var
  IconName: string;
begin
  if (FMView = nil) or (ASlot < 0) or (ASlot >= FMView.Config.SortFolders.Count) then
    Exit;
  if SameText(IncludeTrailingPathDelimiter(ExtractFileDir(AFile)), FMView.Config.IconFilesFolder) then
    IconName := ExtractFileName(AFile)
  else
    IconName := AFile;
  FMView.Config.SortFolders.SetIcon(ASlot, IconName);
  FMView.SortFoldersChanged;
end;

{$IFDEF WINDOWS}
procedure MViewDragAcceptFiles(AWnd: THandle; AAccept: LongBool); stdcall;
  external 'shell32.dll' name 'DragAcceptFiles';
{$ENDIF}

{ Windows sends a drop to the window under the mouse if it takes files;
  the text editor's windows are told they do, and LCL passes their drops
  to the form (OnDropFiles), as for the form itself. }
procedure TMainForm.AcceptDropsOn(AControl: TWinControl);
var
  I: Integer;
begin
  {$IFDEF WINDOWS}
  if AControl = nil then
    Exit;
  try
    AControl.HandleNeeded;
    MViewDragAcceptFiles(AControl.Handle, True);
  except
    Exit;   { a window that can't be made now: it takes no drops }
  end;
  for I := 0 to AControl.ControlCount - 1 do
    if AControl.Controls[I] is TWinControl then
      AcceptDropsOn(TWinControl(AControl.Controls[I]));
  {$ENDIF}
end;

procedure TMainForm.HandleSortOpenClick(Sender: TObject);
begin
  if (FMView <> nil) and (FSortMenuSlot >= 0) then
    FMView.OpenSortFolder(FSortMenuSlot);
end;

procedure TMainForm.HandleSortIconClick(Sender: TObject);
var
  Choice: Integer;
begin
  if (FMView = nil) or (FSortMenuSlot < 0) then
    Exit;
  Choice := TMenuItem(Sender).Tag;
  case Choice of
    -1: FMView.Config.SortFolders.SetIcon(FSortMenuSlot, '');    { by name }
    -2: FMView.Config.SortFolders.SetIcon(FSortMenuSlot, '-');   { none }
  else
    if (Choice >= 0) and (Choice < FSortMenuIcons.Count) then
      FMView.Config.SortFolders.SetIcon(FSortMenuSlot, FSortMenuIcons[Choice])
    else
      Exit;
  end;
  FMView.SortFoldersChanged;
end;

procedure TMainForm.HandleSortIconChooseClick(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  if (FMView = nil) or (FSortMenuSlot < 0) then
    Exit;
  Dialog := TOpenDialog.Create(nil);
  try
    Dialog.Title := 'Icon for this button';
    Dialog.InitialDir := FMView.Config.IconFilesFolder;
    Dialog.Filter := 'Icons (*.ico, *.png)|*.ico;*.png|All files|*.*';
    Dialog.Options := Dialog.Options + [ofFileMustExist];
    if Dialog.Execute then
      SetSlotIcon(FSortMenuSlot, Dialog.FileName);
  finally
    Dialog.Free;
  end;
  if Assigned(ViewInput) then
    ViewInput.NoteActivity(GetTickCount64);
end;

{ Explorer on the icon folder (made if it isn't there yet: it is
  MView's own). }
procedure TMainForm.HandleSortIconFolderClick(Sender: TObject);
var
  Folder: string;
begin
  if FMView = nil then
    Exit;
  Folder := ExcludeTrailingPathDelimiter(FMView.Config.IconFilesFolder);
  ForceDirectories(Folder);
  OpenDocument(Folder);
end;

procedure TMainForm.HandleMakeIconMenuClick(Sender: TObject);
begin
  FMView.MakeIconFromImage;
end;

{ Folders dropped on the open sort panel (e.g. from Total Commander):
  onto a button: the first replaces its folder, the others are added;
  anywhere else on the panel: all are added. Files are ignored there.
  False: not dropped on the panel (the drop opens as usual). }
function TMainForm.DropOnSortPanel(const FileNames: array of string): Boolean;
var
  P: TPoint;
  Hit: TPanelHit;
  Folders: TSortFolders;
  I, Index, Added: Integer;
begin
  Result := False;
  if (FView = nil) or not FMView.SortPanelVisible then
    Exit;
  P := FView.ScreenToClient(Mouse.CursorPos);
  Hit := FMView.SortPanelHit(P.X, P.Y);
  if Hit.Part = ppNone then
    Exit;
  Result := True;
  Folders := FMView.Config.SortFolders;
  Added := 0;
  { An icon file dropped on a button: its icon (stage 2). }
  if (Hit.Part in [ppSlot, ppSlotMenu]) and (Hit.Slot >= 0) then
    for I := 0 to High(FileNames) do
      if IsIconFileName(FileNames[I]) then
      begin
        SetSlotIcon(Hit.Slot, FileNames[I]);
        Exit;
      end;
  for I := 0 to High(FileNames) do
  begin
    { A container (.lif, the microscopy edition, M2c): opened in the
      view, never a sort folder and never kept (Day 25, user: containers
      are transient in the panel). Never in MView (no reader). }
    if IsContainerName(FileNames[I]) and FileExists(FileNames[I]) then
    begin
      if Added > 0 then
        FMView.SortFoldersChanged;
      FMView.OpenDroppedContainer(FileNames[I]);
      Exit;
    end;
    { A drop is rare and made by hand: asking the disk here is fine. }
    if not DirectoryExists(FileNames[I]) then
      Continue;
    if (Added = 0) and (Hit.Part in [ppSlot, ppSlotMenu]) and (Hit.Slot >= 0) then
      Index := Hit.Slot
    else
      Index := Folders.Count;
    if Folders.SetFolder(Index, FileNames[I]) >= 0 then
      Inc(Added);
  end;
  if Added > 0 then
    FMView.SortFoldersChanged;
end;

{ [Mouse] MouseCursorHideTime: the cursor hides after that long without
  input, and comes back with the next movement. }
procedure TMainForm.UpdateCursor;
var
  HideMs: Integer;
  HideNow: Boolean;
begin
  if (FView = nil) or (ViewInput = nil) or (FMView = nil) or FMenuOpen then
    Exit;
  HideMs := FMView.Config.MouseHideTime;
  HideNow := (HideMs > 0) and (ViewInput.LastActivityMs > 0)
    and (GetTickCount64 - ViewInput.LastActivityMs >= QWord(HideMs));
  if HideNow = FCursorHidden then
    Exit;
  FCursorHidden := HideNow;
  if HideNow then
    FView.Cursor := crNone
  else
    FView.Cursor := FMView.ViewCursor;   { a cross while the magnifier follows }
end;

{ An edition's popup menu opens / closed (uExtensions.NoteMenuOpen): as
  the right-click menu, the pointer shows and doesn't hide meanwhile;
  the time in the menu doesn't count. }
procedure TMainForm.HandleExtensionMenuOpen(AOpen: Boolean);
begin
  FMenuOpen := AOpen;
  if AOpen then
  begin
    if FCursorHidden and (FView <> nil) and (FMView <> nil) then
    begin
      FCursorHidden := False;
      FView.Cursor := FMView.ViewCursor;
    end;
  end
  else if Assigned(ViewInput) then
    ViewInput.NoteActivity(GetTickCount64);
end;

procedure TMainForm.HandleExitMenuClick(Sender: TObject);
begin
  Hide;
  Close;
end;

{ An edition's own entry (uExtensions, M0): its action, with the viewer. }
procedure TMainForm.HandleExtensionMenuClick(Sender: TObject);
var
  Entry: TExtensionMenuEntry;
begin
  if not (Sender is TMenuItem) then
    Exit;
  if (TMenuItem(Sender).Tag < 0) or (TMenuItem(Sender).Tag >= MenuEntryCount) then
    Exit;
  Entry := MenuEntry(TMenuItem(Sender).Tag);
  if Assigned(Entry.Action) then
    Entry.Action(FMView);
end;

{ The dedication (docs\From_Hamana_to_VersariteViewer.md). }
procedure TMainForm.HandleAboutMenuClick(Sender: TObject);
begin
  Application.MessageBox(PChar(AboutText), PChar('About ' + EditionTitle), MB_OK or MB_ICONINFORMATION);
  { Time spent reading doesn't count towards hiding the cursor. }
  if Assigned(ViewInput) then
    ViewInput.NoteActivity(GetTickCount64);
end;

procedure TMainForm.HandleFormResize(Sender: TObject);
begin
  if Assigned(FMView) then
    FMView.SetDisplaySize(ClientWidth, ClientHeight);
end;

procedure TMainForm.HandleDeliveryTimer(Sender: TObject);
begin
  if Assigned(FMView) then
    FMView.PumpDeliveries;
  { Mouse language: clicks that waited for a double-click; the cursor. }
  if Assigned(ViewInput) then
  begin
    ViewInput.Tick(GetTickCount64);
    UpdateCursor;
  end;
  { Side by side: a Total Commander just started, placed once its
    window is there. }
  if (FSideWaitUntil > 0) or (FSideAgainAt > 0) then
    CheckSideBySideWait;
  { Viewer: the window's place, once it has stopped moving. }
  if FBoundsDirty and Assigned(FMView)
    and (GetTickCount64 - FBoundsChangedTick >= BoundsSaveDelayMs) then
    RememberBounds;
end;

{ The window's place from MView.ini, if it is still on a monitor (one
  may have been unplugged since). }
procedure TMainForm.ApplySavedBounds(AConfig: TConfig);
var
  R: TRect;
begin
  FBoundsApplied := True;
  if (AConfig.Width < MinWindowWidth) or (AConfig.Height < MinWindowHeight) then
    Exit;
  R := Rect(AConfig.Left, AConfig.Top, AConfig.Left + AConfig.Width,
    AConfig.Top + AConfig.Height);
  if Screen.MonitorFromRect(R, mdNull) = nil then
    Exit;
  BoundsRect := R;
end;

{ The place to remember: the normal window, or the one fullscreen
  returns to. Not while maximised or minimised. }
function TMainForm.CurrentNormalBounds(out ARect: TRect): Boolean;
begin
  Result := False;
  { Side by side: the place it goes back to, not the half. }
  if FSideBySide then
  begin
    if not FSideHaveBounds then
      Exit;
    ARect := FSideBounds;
  end
  else if FFullscreen then
    ARect := FNormalBounds
  else if WindowState = wsNormal then
    ARect := BoundsRect
  else
    Exit;
  Result := (ARect.Right - ARect.Left >= MinWindowWidth)
    and (ARect.Bottom - ARect.Top >= MinWindowHeight);
end;

{ Writes [Window] Left/Top/Width/Height (only those keys). }
procedure TMainForm.RememberBounds;
var
  R: TRect;
  Config: TConfig;
  OwnConfig: Boolean;
begin
  FBoundsDirty := False;
  if not CurrentNormalBounds(R) then
    Exit;
  OwnConfig := FMView = nil;     { the settings editor: no viewer config }
  if OwnConfig then
    Config := TConfig.Create
  else
    Config := FMView.Config;
  try
    Config.Left := R.Left;
    Config.Top := R.Top;
    Config.Width := R.Right - R.Left;
    Config.Height := R.Bottom - R.Top;
    Config.SaveWindowBounds;
  finally
    if OwnConfig then
      Config.Free;
  end;
end;

procedure TMainForm.HandleChangeBounds(Sender: TObject);
begin
  FBoundsDirty := True;
  FBoundsChangedTick := GetTickCount64;
end;

procedure TMainForm.HandleToggleFullscreen(Sender: TObject);
var
  Wnd: THandle;
begin
  { Side by side stays on through fullscreen (1.1, user): leaving
    fullscreen puts MView back next to Total Commander (its half, and
    Total Commander on its own half again), not at the place before. The
    side-by-side menu entry still goes back to the place before. }
  if FSideBySide then
  begin
    if not FFullscreen then
    begin
      SetFullscreen(True);
      Exit;
    end;
    SetFullscreen(False);
    if not PlaceWindow(Handle, FSideLeft) then
      BoundsRect := FSideLeft;
    Wnd := FindTotalCommanderWindow;
    if Wnd <> 0 then
      PlaceWindow(Wnd, FSideRight);
    Exit;
  end;
  SetFullscreen(not FFullscreen);
end;

{ Fullscreen (Day 25, user): a borderless window one pixel taller than
  its screen, not the LCL's wsFullScreen. A GPU-drawn (OpenGL) window
  that covers its screen exactly is shown by Windows / the driver as a
  "full-screen picture"; a popup over it (the right-click menu) forces a
  switch back, and the Intel driver flickers then and puts the window
  behind the others (seen on a Dell XPS 15 on its Intel GPU; NVIDIA was
  fine). One pixel more is not exactly the screen: no such mode, no
  flicker. The extra row is below the screen's bottom edge, unseen.
  Known: Khronos forum "TrackPopupMenu breaks full-screen OpenGL
  window" (one pixel less fixed it); Qt gives such windows a border. }
{$IFDEF WINDOWS}
{ The window's frame on and off without making the window again (Day 25:
  LCL's BorderStyle re-creates the form's window, and with it every
  control of the hidden settings screen - over a second on each Esc
  from fullscreen). }
const
  GWL_STYLE_ = -16;
  WS_CAPTION_ = $00C00000;
  WS_THICKFRAME_ = $00040000;
  SWP_FRAME_ONLY = $0001 or $0002 or $0004 or $0010 or $0020 or $0200;
    { NOSIZE, NOMOVE, NOZORDER, NOACTIVATE, FRAMECHANGED, NOOWNERZORDER }

{$IFDEF CPU64}
function MViewGetWindowLong(AWnd: THandle; AIndex: LongInt): PtrInt; stdcall;
  external 'user32.dll' name 'GetWindowLongPtrW';
function MViewSetWindowLong(AWnd: THandle; AIndex: LongInt; AValue: PtrInt): PtrInt; stdcall;
  external 'user32.dll' name 'SetWindowLongPtrW';
{$ELSE}
function MViewGetWindowLong(AWnd: THandle; AIndex: LongInt): PtrInt; stdcall;
  external 'user32.dll' name 'GetWindowLongW';
function MViewSetWindowLong(AWnd: THandle; AIndex: LongInt; AValue: PtrInt): PtrInt; stdcall;
  external 'user32.dll' name 'SetWindowLongW';
{$ENDIF}
function MViewSetWindowPos(AWnd, AAfter: THandle; X, Y, CX, CY: LongInt; AFlags: LongWord): LongBool;
  stdcall; external 'user32.dll' name 'SetWindowPos';

procedure SetWindowFrame(AWnd: THandle; AOn: Boolean);
var
  Style: PtrInt;
begin
  Style := MViewGetWindowLong(AWnd, GWL_STYLE_);
  if AOn then
    Style := Style or WS_CAPTION_ or WS_THICKFRAME_
  else
    Style := Style and not (WS_CAPTION_ or WS_THICKFRAME_);
  MViewSetWindowLong(AWnd, GWL_STYLE_, Style);
  MViewSetWindowPos(AWnd, 0, 0, 0, 0, 0, SWP_FRAME_ONLY);
end;
{$ENDIF}

procedure TMainForm.SetFullscreen(AValue: Boolean);
var
  R: TRect;
begin
  if AValue = FFullscreen then
    Exit;
  FFullscreen := AValue;

  if AValue then
  begin
    FNormalBounds := BoundsRect;
    R := Monitor.BoundsRect;           { the screen the window is on }
    if WindowState <> wsNormal then
      WindowState := wsNormal;
    {$IFDEF WINDOWS}
    SetWindowFrame(Handle, False);
    {$ELSE}
    BorderStyle := bsNone;
    {$ENDIF}
    Inc(R.Bottom);
    BoundsRect := R;
  end
  else
  begin
    if WindowState <> wsNormal then
      WindowState := wsNormal;
    {$IFDEF WINDOWS}
    SetWindowFrame(Handle, True);
    {$ELSE}
    BorderStyle := bsSizeable;
    {$ENDIF}
    BoundsRect := FNormalBounds;
  end;
end;

{ ---- Side by side with Total Commander (Phase G, user) ---- }

procedure TMainForm.HandleSideBySideMenuClick(Sender: TObject);
begin
  ToggleSideBySide;
end;

{ On: MView fills the left half of its screen (the work area: the
  taskbar stays free), Total Commander the right half, in the current
  image's folder; MView's sort panel is then right next to it. Off: MView
  goes back to fullscreen or its place before; Total Commander stays. }
procedure TMainForm.ToggleSideBySide(const AFolder: string);
var
  Work, LeftHalf: TRect;
  Wnd: THandle;
  Exe, Folder: string;
  Mid: Integer;
begin
  if FMView = nil then
    Exit;

  if FSideBySide then
  begin
    FSideBySide := False;
    FSideWaitUntil := 0;
    FSideAgainAt := 0;
    if FFullscreen then
    begin
      { Fullscreen meanwhile (1.1): it stays; leaving it later goes to
        the place before side by side. }
      if FSideHaveBounds then
        FNormalBounds := FSideBounds;
    end
    else
    begin
      if FSideHaveBounds then
        BoundsRect := FSideBounds;
      if FSideWasFullscreen then
        SetFullscreen(True);
    end;
    FMView.ShowNote('back from side by side (Total Commander stays where it is)', 4000);
    Exit;
  end;

  Wnd := FindTotalCommanderWindow;
  Exe := TotalCommanderExe(FMView.Config.TotalCommander, Wnd);
  if (Wnd = 0) and (Exe = '') then
  begin
    FMView.ShowNote(EditionText('Total Commander not found: put its path into VersariteViewer.ini, [Sort] TotalCommander='),
      10000);
    Exit;
  end;

  { The place to go back to. }
  FSideWasFullscreen := FFullscreen;
  FSideHaveBounds := CurrentNormalBounds(FSideBounds);

  Work := Monitor.WorkareaRect;
  Mid := Work.Left + (Work.Right - Work.Left) div 2;
  LeftHalf := Rect(Work.Left, Work.Top, Mid, Work.Bottom);
  FSideLeft := LeftHalf;
  FSideRight := Rect(Mid, Work.Top, Work.Right, Work.Bottom);

  if FFullscreen then
    SetFullscreen(False);
  if WindowState <> wsNormal then
    WindowState := wsNormal;
  FSideBySide := True;
  if not PlaceWindow(Handle, LeftHalf) then
    BoundsRect := LeftHalf;

  { Total Commander: into this image's folder (started if not running). }
  if FMView.Navigator.HasCurrentImage then
    Folder := ExcludeTrailingPathDelimiter(FMView.FolderOnDisk)
  else
    Folder := AFolder;      { at the start: the start folder }
  if Exe <> '' then
  begin
    if not OpenInTotalCommander(Exe, Folder) then
    begin
      { Nothing happened: MView goes back as well. }
      FSideBySide := False;
      if FSideHaveBounds then
        BoundsRect := FSideBounds;
      if FSideWasFullscreen then
        SetFullscreen(True);
      FMView.ShowNote('Total Commander could not be started: ' + Exe, 10000);
      Exit;
    end;
  end
  else if Folder <> '' then
    FMView.ShowNote('Total Commander''s program was not found: it can''t be told the folder '
      + EditionText('(set [Sort] TotalCommander= in VersariteViewer.ini)'), 8000);

  if Wnd <> 0 then
  begin
    PlaceTotalCommander(Wnd);
    { The running one gets the folder a moment later and may bring
      itself up where it was: placed once more. }
    FSideAgainAt := GetTickCount64 + 600;
  end
  else
  begin
    { Just started: its window comes in a moment (the 50 ms timer); an
      unregistered copy shows its reminder first, so wait a while. }
    FSideWaitUntil := GetTickCount64 + 60000;
    FMView.ShowNote('starting Total Commander ...', 0);
  end;
end;

procedure TMainForm.PlaceTotalCommander(AWindow: THandle);
begin
  if PlaceWindow(AWindow, FSideRight) then
    FMView.ShowNote('side by side with Total Commander   (the same menu entry again: back)', 5000)
  else
    FMView.ShowNote('Total Commander could not be moved (does it run as administrator?)', 8000);
end;

procedure TMainForm.CheckSideBySideWait;
var
  Wnd: THandle;
begin
  if (not FSideBySide) or (FMView = nil) then
  begin
    FSideWaitUntil := 0;
    FSideAgainAt := 0;
    Exit;
  end;
  Wnd := FindTotalCommanderWindow;
  if (FSideAgainAt > 0) and (GetTickCount64 >= FSideAgainAt) then
  begin
    FSideAgainAt := 0;
    if Wnd <> 0 then
      PlaceWindow(Wnd, FSideRight);   { quietly: the note was given }
    Exit;
  end;
  if FSideWaitUntil = 0 then
    Exit;
  if (Wnd <> 0) and IsWindowVisible(Wnd) then
  begin
    FSideWaitUntil := 0;
    PlaceTotalCommander(Wnd);
    FSideAgainAt := GetTickCount64 + 600;
  end
  else if GetTickCount64 > FSideWaitUntil then
  begin
    FSideWaitUntil := 0;
    FMView.ShowNote('Total Commander''s window did not appear', 6000);
  end;
end;

end.
