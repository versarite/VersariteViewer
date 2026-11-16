unit uFileManager;

{
  Unit: uFileManager

  Purpose
  -------
  The file manager VersariteViewer works with (1.4, the Linux port,
  Day 36): one class for what the viewer asks of it - is it running,
  which folder and file its cursor is on, start it in a folder, put its
  window beside the viewer - so Total Commander (Windows) and Double
  Commander (Linux, later) can stand behind the same calls.

  Owns
  ----
  The one file manager object (FileManager), made on first use from the
  class registered by its unit, freed at the end.

  Knows
  -----
  Nothing of any file manager: the implementations register themselves
  (RegisterFileManager in their initialization section).

  Responsibilities
  ----------------
  - TFileManager: the calls, abstract.
  - RegisterFileManager / FileManager: the implementation in use. With
    none registered, FileManager is nil (no file manager on this system).
  - SelectFileManager ([Sort] DirManager, 1.4): which of the registered
    ones; decided at the start (the first FileManager call), later
    choices wait for the next start. One not on this system: the other.

  Does NOT
  --------
  - Decide halves, screens or notes (uMainForm), or what to show for a
    folder (TMView): it only answers and carries out.

  Threads
  -------
  UI thread.

  Uses (MView units)
  ------------------
  (none)
  Libraries:      Classes, SysUtils, Types

  Used by
  -------
  uTotalCommander, uMView, uMainForm
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  Types;

type
  { A panel of the file manager (1.4). }
  TFMPanel = (fpActive, fpInactive, fpLeft, fpRight);

  TFileManager = class
  public
    constructor Create; virtual;
    { For notes and menu entries: "Total Commander". }
    function Name: string; virtual; abstract;
    { Its main window is there. }
    function IsRunning: Boolean; virtual; abstract;
    { ... and shown (a just started one: not yet). }
    function IsShown: Boolean; virtual; abstract;
    { The program to start: AConfigured if it exists, else found on this
      system; '' = not found. }
    function ProgramPath(const AConfigured: string): string; virtual; abstract;
    { Started (or the running one told) with AFolder in its active panel;
      AFolder '' = just brought up. False if it could not be started. }
    function Open(const AProgram, AFolder: string): Boolean; virtual; abstract;
    { Its window placed so its visible frame fills ARect. False: it could
      not be moved (e.g. it runs as administrator). }
    function PlaceAt(const ARect: TRect): Boolean; virtual; abstract;
    { Its window's rectangle on the desktop. False if not running. }
    function WindowRect(out ARect: TRect): Boolean; virtual; abstract;
    { Its window moved from the screen with work area AFrom to the one
      with ATo, its size kept, a maximised one maximised there. }
    function MoveToWork(const AFrom, ATo: TRect): Boolean; virtual; abstract;
    { The folder of its active panel and (AWantFile) the file under its
      cursor. False: no answer (not running, or busy). }
    function Poll(AWantFile: Boolean; out AFolder, AFile: string): Boolean; virtual; abstract;
    { The file under the cursor can be asked (after the first Poll). }
    function CursorSupported: Boolean; virtual; abstract;
    { The files under the cursors of the left and the right panel (full
      names; '' for a folder, "..", or a panel in an archive). False:
      not running. }
    function PanelItems(out ALeft, ARight: string): Boolean; virtual; abstract;
    { For the D line: how the last answers came. }
    function Info: string; virtual; abstract;
    { Forget what was learned from earlier answers (e.g. whether it says
      which file its cursor is on); asked afresh at the next Poll. }
    procedure Restart; virtual;
    { 1.4: it can be told to show a folder in a given panel (Double
      Commander through its remote control; Total Commander: not yet). }
    function CanShowFolder: Boolean; virtual;
    { AFolder shown in APanel of the running file manager. False: not
      possible, not running, or no answer. }
    function ShowFolder(const AFolder: string; APanel: TFMPanel): Boolean; virtual;
    { 1.4 (user): it can make a folder (Double Commander: cm_MakeDir
      path=; Total Commander: no). }
    function CanMakeFolder: Boolean; virtual;
    { AFolder (full name) made by the running file manager; True once it
      exists. False: not possible, not running, or it didn't appear. }
    function MakeFolder(const AFolder: string): Boolean; virtual;
    { 1.4 (user): the oldest message it sent on its own (Double
      Commander's cm_SendTree: TREE <folder> <subfolder>...), as fields.
      False: none, or it can't send any. Asks the file manager: call it
      a few times a second at most. }
    function NextEvent(out AFields: TStringArray): Boolean; virtual;
    { 1.4 (user, Day 40): the configured program ([FileManager]
      DoubleCommander= / TotalCommander=). Double Commander with none set:
      no connection at all (VV shows a notice instead). }
    procedure Configure(const AProgram: string); virtual;
    { False: configured not to be used (see Configure). }
    function IsConfigured: Boolean; virtual;
    { The file VV shows, under the cursor of the panel it follows (Double
      Commander: SET CURSOR; another folder: it goes there). }
    function SetCursor(const AFile: string): Boolean; virtual;
    { VV's order for that panel: AKey name / date; sent only when it
      differs from what was sent on this connection. }
    function SetSort(const AKey: string; ADescending: Boolean): Boolean; virtual;
    { True once after a freshly started file manager has connected (for
      settings applied at its start, [FileManager] DCThumbnails). }
    function TakeFreshStart: Boolean; virtual;
    { Thumbnail view on: 1 = its inactive panel, 2 = its active panel. }
    function SetThumbnails(APanel: Integer): Boolean; virtual;
  end;

  TFileManagerClass = class of TFileManager;

const
  { [FileManager] DirManager (1.4, user; Day 40: 0 = none, the default -
    a user without a file manager never hears of one). }
  dmNone            = 0;
  dmDoubleCommander = 1;
  dmTotalCommander  = 2;
  { What VV says when a file manager feature is asked for without one. }
  NoFileManagerNote = 'No file manager: VersariteViewer.ini, [FileManager] DirManager=1 '
    + '(Double Commander) or 2 (Total Commander), and its path';

{ The implementation's unit calls this in its initialization section. }
procedure RegisterFileManager(AId: Integer; AClass: TFileManagerClass);
{ [FileManager] DirManager: dmNone (default), dmDoubleCommander or dmTotalCommander. Has
  an effect only before the file manager object is made (the start). }
procedure SelectFileManager(AId: Integer);
{ The file manager in use, made on first use; nil = none chosen, or none
  on this system. }
function FileManager: TFileManager;
{ 1.4 (Day 40): the configured program ([FileManager] DoubleCommander= /
  TotalCommander=, TConfig.Load); passed on to the file manager now or
  when it is made (TFileManager.Configure). }
procedure SetFileManagerProgram(const AProgram: string);
{ Its name for notes and menu entries ("file manager" when none). }
function FMName: string;
{ Day 40: VV's own commands for the file manager's buttons, as TAB-separated
  name=caption fields (Double Commander: SET COMMANDS, offered in its
  toolbar editor for cm_ViewerCommand). Set once at the start (TMView). }
procedure SetFileManagerCommands(const AFields: string);
function FileManagerCommands: string;

implementation

constructor TFileManager.Create;
begin
  inherited Create;
end;

procedure TFileManager.Restart;
begin
end;

function TFileManager.CanShowFolder: Boolean;
begin
  Result := False;
end;

function TFileManager.ShowFolder(const AFolder: string; APanel: TFMPanel): Boolean;
begin
  Result := False;
end;

function TFileManager.CanMakeFolder: Boolean;
begin
  Result := False;
end;

function TFileManager.MakeFolder(const AFolder: string): Boolean;
begin
  Result := False;
end;

function TFileManager.NextEvent(out AFields: TStringArray): Boolean;
begin
  AFields := nil;
  Result := False;
end;

procedure TFileManager.Configure(const AProgram: string);
begin
end;

function TFileManager.IsConfigured: Boolean;
begin
  Result := True;
end;

function TFileManager.SetCursor(const AFile: string): Boolean;
begin
  Result := False;
end;

function TFileManager.SetSort(const AKey: string; ADescending: Boolean): Boolean;
begin
  Result := False;
end;

function TFileManager.TakeFreshStart: Boolean;
begin
  Result := False;
end;

function TFileManager.SetThumbnails(APanel: Integer): Boolean;
begin
  Result := False;
end;

var
  GClasses: array[dmDoubleCommander..dmTotalCommander] of TFileManagerClass;
  GSelected: Integer = dmNone;
  GManager: TFileManager = nil;
  GProgram: string = '';
  GProgramSet: Boolean = False;
  GCommands: string = '';

procedure SetFileManagerCommands(const AFields: string);
begin
  GCommands := AFields;
end;

function FileManagerCommands: string;
begin
  Result := GCommands;
end;

procedure SetFileManagerProgram(const AProgram: string);
begin
  GProgram := AProgram;
  GProgramSet := True;
  if GManager <> nil then
    GManager.Configure(AProgram);
end;

procedure RegisterFileManager(AId: Integer; AClass: TFileManagerClass);
begin
  if (AId >= Low(GClasses)) and (AId <= High(GClasses)) then
    GClasses[AId] := AClass;
end;

procedure SelectFileManager(AId: Integer);
begin
  if (AId = dmNone) or ((AId >= Low(GClasses)) and (AId <= High(GClasses))) then
    GSelected := AId;
end;

function FileManager: TFileManager;
var
  C: TFileManagerClass;
  I: Integer;
begin
  if (GManager = nil) and (GSelected <> dmNone) then
  begin
    C := GClasses[GSelected];
    { The chosen one isn't on this system (Total Commander on Linux):
      whichever is. }
    if C = nil then
      for I := Low(GClasses) to High(GClasses) do
        if GClasses[I] <> nil then
        begin
          C := GClasses[I];
          Break;
        end;
    if C <> nil then
    begin
      GManager := C.Create;
      if GProgramSet then
        GManager.Configure(GProgram);
    end;
  end;
  Result := GManager;
end;

function FMName: string;
begin
  if FileManager <> nil then
    Result := FileManager.Name
  else
    Result := 'file manager';
end;

finalization
  FreeAndNil(GManager);

end.
