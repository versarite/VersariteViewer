program TestFileManager;

{
  TestFileManager (1.4, Day 36): the file manager layer (uFileManager).
  - On Windows, uTotalCommander registers Total Commander as the file
    manager; with Total Commander not running every question says "no".
  - Another implementation can be registered in its place (Double
    Commander, later), and FileManager then makes that one.
  Plain fpc, like TestNavigation.
}

{$mode ObjFPC}{$H+}

uses
  SysUtils,
  Types,
  uFileManager,
  uTotalCommander;

var
  Passed, Failed: Integer;

procedure Check(ACondition: Boolean; const AWhat: string);
begin
  if ACondition then
    Inc(Passed)
  else
  begin
    Inc(Failed);
    WriteLn('FAILED: ', AWhat);
  end;
end;

type
  TFakeManager = class(TFileManager)
  public
    Restarts: Integer;
    constructor Create; override;
    function Name: string; override;
    function IsRunning: Boolean; override;
    function IsShown: Boolean; override;
    function ProgramPath(const AConfigured: string): string; override;
    function Open(const AProgram, AFolder: string): Boolean; override;
    function PlaceAt(const ARect: TRect): Boolean; override;
    function WindowRect(out ARect: TRect): Boolean; override;
    function MoveToWork(const AFrom, ATo: TRect): Boolean; override;
    function Poll(AWantFile: Boolean; out AFolder, AFile: string): Boolean; override;
    function CursorSupported: Boolean; override;
    function PanelItems(out ALeft, ARight: string): Boolean; override;
    function Info: string; override;
    procedure Restart; override;
  end;

var
  FakesMade: Integer = 0;

constructor TFakeManager.Create;
begin
  inherited Create;
  Inc(FakesMade);
end;

function TFakeManager.Name: string; begin Result := 'Fake Commander'; end;
function TFakeManager.IsRunning: Boolean; begin Result := True; end;
function TFakeManager.IsShown: Boolean; begin Result := True; end;
function TFakeManager.ProgramPath(const AConfigured: string): string; begin Result := AConfigured; end;
function TFakeManager.Open(const AProgram, AFolder: string): Boolean; begin Result := AFolder <> ''; end;
function TFakeManager.PlaceAt(const ARect: TRect): Boolean; begin Result := ARect.Right > ARect.Left; end;
function TFakeManager.WindowRect(out ARect: TRect): Boolean;
begin
  ARect := Rect(10, 20, 30, 40);
  Result := True;
end;
function TFakeManager.MoveToWork(const AFrom, ATo: TRect): Boolean; begin Result := True; end;
function TFakeManager.Poll(AWantFile: Boolean; out AFolder, AFile: string): Boolean;
begin
  AFolder := '/home/user/images';
  if AWantFile then AFile := AFolder + '/a.tif' else AFile := '';
  Result := True;
end;
function TFakeManager.CursorSupported: Boolean; begin Result := True; end;
function TFakeManager.PanelItems(out ALeft, ARight: string): Boolean;
begin
  ALeft := 'l.gif'; ARight := 'r.gif'; Result := True;
end;
function TFakeManager.Info: string; begin Result := 'fake'; end;
procedure TFakeManager.Restart; begin Inc(Restarts); end;

procedure TestTotalCommander;
var
  FM: TFileManager;
  Folder, F, L, R: string;
  Rc: TRect;
begin
  FM := FileManager;
{$IFDEF WINDOWS}
  Check(FM is TTotalCommanderLink, 'Windows: Total Commander is the file manager');
  Check(FM = FileManager, 'the same object on the next call');
  Check(FM.Name = 'Total Commander', 'its name');
  { The test machine has no Total Commander running. }
  Check(not FM.IsRunning, 'not running');
  Check(not FM.IsShown, 'not shown');
  Check(not FM.Poll(True, Folder, F), 'no answer to a poll');
  Check(not FM.PanelItems(L, R), 'no panel items');
  Check(not FM.WindowRect(Rc), 'no window');
  Check(not FM.PlaceAt(Rect(0, 0, 100, 100)), 'nothing to place');
  Check(not FM.MoveToWork(Rect(0, 0, 100, 100), Rect(100, 0, 200, 100)), 'nothing to move');
  Check(FM.ProgramPath('C:\no such folder\TOTALCMD64.EXE') <> 'C:\no such folder\TOTALCMD64.EXE',
    'a configured path that does not exist is not taken');
  FM.Restart;
  Check(FM.Info = '', 'nothing learned after Restart');
{$ELSE}
  Check(FM = nil, 'no Total Commander on this system');
{$ENDIF}
end;

procedure TestOther;
var
  FM: TFileManager;
  Folder, F, L, R: string;
  Rc: TRect;
begin
  RegisterFileManager(TFakeManager);
  Check(FakesMade = 0, 'made only on first use');
  FM := FileManager;
  Check(FM is TFakeManager, 'the registered one is made');
  Check(FakesMade = 1, 'its own constructor ran');
  Check(FileManager = FM, 'and kept');
  Check(FakesMade = 1, 'made once');
  Check(FM.Name = 'Fake Commander', 'name');
  Check(FM.IsRunning and FM.IsShown, 'running, shown');
  Check(FM.Poll(True, Folder, F) and (Folder = '/home/user/images') and (F = '/home/user/images/a.tif'),
    'poll with the file');
  Check(FM.Poll(False, Folder, F) and (F = ''), 'poll without the file');
  Check(FM.PanelItems(L, R) and (L = 'l.gif') and (R = 'r.gif'), 'panel items');
  Check(FM.WindowRect(Rc) and (Rc.Left = 10) and (Rc.Bottom = 40), 'window rect');
  FM.Restart;
  Check(TFakeManager(FM).Restarts = 1, 'Restart reaches it');
  { Registering again replaces the object. }
  RegisterFileManager(TFakeManager);
  Check(FileManager <> nil, 'made again');
  Check(FakesMade = 2, 'a new one');
end;

begin
  Passed := 0;
  Failed := 0;
  TestTotalCommander;
  TestOther;
  WriteLn(Passed, ' passed, ', Failed, ' failed');
  if Failed > 0 then
    ExitCode := 1;
end.
