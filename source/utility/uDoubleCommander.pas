unit uDoubleCommander;

{
  Unit: uDoubleCommander

  Purpose
  -------
  Double Commander as VersariteViewer's file manager (1.4, Linux port,
  Day 36; Windows, Day 39): the same calls as Total Commander
  (uFileManager), through Double Commander's remote control channel, text
  lines with TAB-separated fields (see Double Commander's uRemoteControl):
  - Linux: a Unix domain socket of the user's own
    ($XDG_RUNTIME_DIR/doublecmd-remote, else
    /tmp/doublecmd-<uid>/doublecmd-remote);
  - Windows: the named pipe \\.\pipe\doublecmd-remote-<user SID>, which
    only this user can open (Double Commander sets its access list).
  That channel is a proposed addition to Double Commander, not in its
  releases yet.

  Owns
  ----
  The connection (one socket / pipe handle, kept open), the token Double
  Commander gave at the pairing (VersariteViewer.dctoken next to the ini).

  Knows
  -----
  uFileManager (TFileManager), uEdition (where the ini is).

  Responsibilities
  ----------------
  - Connect, say HELLO with the token; the first time Double Commander
    asks its user whether to allow VersariteViewer: the answer is waited
    for without blocking (Poll keeps returning "no answer" meanwhile).
  - Poll: the active panel's folder (file system only) and the file under
    its cursor; PanelItems: the files under both cursors.
  - Open: a running Double Commander is told the folder (cm_ChangeDir
    activepath=); else it is started with the folder (-L).
  - PlaceAt / WindowRect / MoveToWork: through GET / SET WINDOW (Double
    Commander places its own window; under Wayland it runs on XWayland).
    Windows: its rectangle includes the invisible resize borders of
    Windows 10; they are added / taken off here, so the visible frame
    fills the half as Total Commander's does.

  Does NOT
  --------
  - Block the window: every question waits at most 300 ms for its answer.

  Threads
  -------
  UI thread.

  Uses (MView units)
  ------------------
  interface:      uFileManager
  implementation: uEdition
  Libraries:      Classes, SysUtils, Types, Math, Process; BaseUnix, Sockets
                  (Unix only); kernel32 / advapi32 / user32 calls (Windows)

  Used by
  -------
  uMainForm (linked there, registers itself; chosen by [FileManager]
  DirManager)
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  Types,
  uFileManager;

type
  TDCState = (dsNone, dsWaitingHello, dsReady, dsDenied);

  TDoubleCommanderLink = class(TFileManager)
  private
    FCommandsDue: Boolean;       { SET COMMANDS still to send (this connection) }
    FStartFolder: string;        { the folder for the one VV started, once connected }
    FStartFolderUntil: QWord;    { ... given up after this (it never answered) }
    {$IFDEF UNIX}
    FSocket: LongInt;
    {$ENDIF}
    {$IFDEF WINDOWS}
    FPipe: THandle;
    {$ENDIF}
    FInput: string;
    FState: TDCState;
    FNextTryMs: QWord;
    FCursorSeen: Boolean;
    FInfo: string;
    { 1.4 (Day 40) }
    FProgram: string;                { [FileManager] DoubleCommander= }
    FConfigured: Boolean;            { set and there: else no connection at all }
    FCheckStart: Boolean;            { paired again: is it a new Double Commander? }
    FInstanceMs: Int64;              { when the Double Commander seen last started (VV's clock) }
    FFresh: Boolean;                 { a new one, started less than a minute ago }
    FSortSent: string;               { the order sent to this Double Commander }
    FNoFollowQuery: Boolean;         { an older patch: no GET FOLLOW (two questions) }
    function IsConnected: Boolean;
    function SendRaw(const AData: string): Boolean;
    { Appends what arrives within AWaitMs to FInput: > 0 bytes came, 0
      nothing came, -1 the connection ended. }
    function RecvSome(AWaitMs: Integer): Integer;
    procedure CloseChannel;
    function OpenChannel: Boolean;
    procedure Disconnect;
    function Connect: Boolean;
    function Ready: Boolean;
    function ReadLine(AWaitMs: Integer; out ALine: string): Boolean;
    function Ask(const ARequest: string; out AFields: TStringArray): Boolean;
    function Token: string;
    procedure SaveToken(const AToken: string);
  public
    constructor Create; override;
    destructor Destroy; override;
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
    function CanShowFolder: Boolean; override;
    function ShowFolder(const AFolder: string; APanel: TFMPanel): Boolean; override;
    function CanMakeFolder: Boolean; override;
    function MakeFolder(const AFolder: string): Boolean; override;
    function NextEvent(out AFields: TStringArray): Boolean; override;
    procedure Configure(const AProgram: string); override;
    function IsConfigured: Boolean; override;
    function SetCursor(const AFile: string): Boolean; override;
    function SetSort(const AKey: string; ADescending: Boolean): Boolean; override;
    function TakeFreshStart: Boolean; override;
    function SetThumbnails(APanel: Integer): Boolean; override;
    { Double Commander's socket file (Unix) / pipe name (Windows). }
    class function SocketFileName: string;
  end;

implementation

uses
  Math,
  Process,
  uEdition
  {$IFDEF UNIX}
  , BaseUnix,
  Sockets
  {$ENDIF}
  ;

const
  ClientName = 'VersariteViewer';
  AnswerWaitMs = 300;
  RetryMs = 1000;                { a missing Double Commander is looked for once a second }

{$IFDEF UNIX}
const
  { Double Commander closed: a write to its socket raises SIGPIPE, which
    would end VV; asked not to (Linux), the write fails (EPIPE) and VV
    disconnects as on any other error. }
  {$IFDEF LINUX}
  VV_MSG_NOSIGNAL = $4000;
  {$ELSE}
  VV_MSG_NOSIGNAL = 0;
  {$ENDIF}
  VV_FD_CLOEXEC = 1;
{$ENDIF}

{$IFDEF WINDOWS}
{ Declared here with plain pointer parameters (no var/pointer overloads
  of the Windows unit to pick from). }
const
  PipePrefix = '\\.\pipe\doublecmd-remote-';
  VV_INVALID_HANDLE = THandle(-1);
  VV_TOKEN_QUERY = $0008;
  VV_TokenUser = 1;
  VV_GENERIC_READ = DWORD($80000000);
  VV_GENERIC_WRITE = $40000000;
  VV_OPEN_EXISTING = 3;
  { The pipe's server may only identify VersariteViewer, not act as it
    (against a program that put up a pipe of that name first). }
  VV_SECURITY_SQOS_PRESENT = $00100000;
  VV_SECURITY_IDENTIFICATION = $00010000;
  VV_SM_CXSIZEFRAME = 32;
  VV_SM_CXPADDEDBORDER = 92;

type
  TVVSidAndAttributes = record
    Sid: Pointer;
    Attributes: DWORD;
  end;
  PVVSidAndAttributes = ^TVVSidAndAttributes;

function VV_OpenProcessToken(Process: THandle; Access: DWORD; Token: Pointer): LongBool;
  stdcall; external 'advapi32.dll' name 'OpenProcessToken';
function VV_GetTokenInformation(Token: THandle; InfoClass: DWORD; Info: Pointer;
  InfoLength: DWORD; ReturnLength: PDWORD): LongBool;
  stdcall; external 'advapi32.dll' name 'GetTokenInformation';
function VV_ConvertSidToStringSidW(Sid: Pointer; StringSid: PPWideChar): LongBool;
  stdcall; external 'advapi32.dll' name 'ConvertSidToStringSidW';
function VV_LocalFree(Mem: Pointer): Pointer;
  stdcall; external 'kernel32.dll' name 'LocalFree';
function VV_CreateFileW(Name: PWideChar; Access, Share: DWORD; SA: Pointer;
  Disposition, FlagsAndAttributes: DWORD; Template: THandle): THandle;
  stdcall; external 'kernel32.dll' name 'CreateFileW';
function VV_PeekNamedPipe(Pipe: THandle; Buffer: Pointer; BufferSize: DWORD;
  BytesRead, TotalAvail, BytesLeft: PDWORD): LongBool;
  stdcall; external 'kernel32.dll' name 'PeekNamedPipe';
function VV_ReadFile(F: THandle; Buffer: Pointer; ToRead: DWORD; Read: PDWORD;
  Ovl: Pointer): LongBool;
  stdcall; external 'kernel32.dll' name 'ReadFile';
function VV_WriteFile(F: THandle; Buffer: Pointer; ToWrite: DWORD; Written: PDWORD;
  Ovl: Pointer): LongBool;
  stdcall; external 'kernel32.dll' name 'WriteFile';
function VV_CloseHandle(H: THandle): LongBool;
  stdcall; external 'kernel32.dll' name 'CloseHandle';
function VV_GetCurrentProcess: THandle;
  stdcall; external 'kernel32.dll' name 'GetCurrentProcess';
function VV_GetSystemMetrics(Index: LongInt): LongInt;
  stdcall; external 'user32.dll' name 'GetSystemMetrics';

{ The current user's SID as text (S-1-5-21-...); '' if not known. }
function UserSidString: string;
var
  TokenH: THandle;
  Buffer: array[0..1023] of Byte;
  Len: DWORD;
  P: PWideChar;
begin
  Result := '';
  if not VV_OpenProcessToken(VV_GetCurrentProcess, VV_TOKEN_QUERY, @TokenH) then
    Exit;
  try
    Len := 0;
    if VV_GetTokenInformation(TokenH, VV_TokenUser, @Buffer[0], SizeOf(Buffer), @Len) then
    begin
      P := nil;
      if VV_ConvertSidToStringSidW(PVVSidAndAttributes(@Buffer[0])^.Sid, @P) then
      begin
        Result := string(UTF8Encode(UnicodeString(P)));
        VV_LocalFree(P);
      end;
    end;
  finally
    VV_CloseHandle(TokenH);
  end;
end;

{ Windows 10's invisible resize border (left, right, bottom) of a sizeable
  window: Double Commander's rectangle is that much larger than what is
  seen. }
function InvisibleBorder: Integer;
begin
  Result := VV_GetSystemMetrics(VV_SM_CXSIZEFRAME) + VV_GetSystemMetrics(VV_SM_CXPADDEDBORDER);
  if (Result < 0) or (Result > 32) then
    Result := 0;
end;
{$ENDIF}

class function TDoubleCommanderLink.SocketFileName: string;
{$IFDEF UNIX}
var
  Dir: string;
{$ENDIF}
begin
  {$IFDEF UNIX}
  Dir := GetEnvironmentVariable('XDG_RUNTIME_DIR');
  if (Dir = '') or not DirectoryExists(Dir) then
    Dir := '/tmp/doublecmd-' + IntToStr(FpGetUid);
  Result := IncludeTrailingPathDelimiter(Dir) + 'doublecmd-remote';
  {$ELSE}
  {$IFDEF WINDOWS}
  Result := UserSidString;
  if Result <> '' then
    Result := PipePrefix + Result;
  {$ELSE}
  Result := '';
  {$ENDIF}
  {$ENDIF}
end;

constructor TDoubleCommanderLink.Create;
begin
  inherited Create;
  {$IFDEF UNIX}
  FSocket := -1;
  {$ENDIF}
  {$IFDEF WINDOWS}
  FPipe := VV_INVALID_HANDLE;
  {$ENDIF}
end;

destructor TDoubleCommanderLink.Destroy;
begin
  Disconnect;
  inherited Destroy;
end;

function TDoubleCommanderLink.Name: string;
begin
  Result := 'Double Commander';
end;

function TDoubleCommanderLink.Token: string;
var
  L: TStringList;
begin
  Result := '';
  if not FileExists(ChangeFileExt(EditionIniFileName, '.dctoken')) then
    Exit;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(ChangeFileExt(EditionIniFileName, '.dctoken'));
      if L.Count > 0 then
        Result := Trim(L[0]);
    except
      Result := '';
    end;
  finally
    L.Free;
  end;
end;

procedure TDoubleCommanderLink.SaveToken(const AToken: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Add(AToken);
    try
      L.SaveToFile(ChangeFileExt(EditionIniFileName, '.dctoken'));
      {$IFDEF UNIX}
      FpChmod(ChangeFileExt(EditionIniFileName, '.dctoken'), &600);
      {$ENDIF}
    except
      { A read-only folder: paired for this session only. }
    end;
  finally
    L.Free;
  end;
end;

{ ---- the channel: socket (Unix) / pipe (Windows) ---- }

function TDoubleCommanderLink.IsConnected: Boolean;
begin
  {$IFDEF UNIX}
  Result := FSocket >= 0;
  {$ELSE}
  {$IFDEF WINDOWS}
  Result := FPipe <> VV_INVALID_HANDLE;
  {$ELSE}
  Result := False;
  {$ENDIF}
  {$ENDIF}
end;

procedure TDoubleCommanderLink.CloseChannel;
begin
  {$IFDEF UNIX}
  if FSocket >= 0 then
    CloseSocket(FSocket);
  FSocket := -1;
  {$ENDIF}
  {$IFDEF WINDOWS}
  if FPipe <> VV_INVALID_HANDLE then
    VV_CloseHandle(FPipe);
  FPipe := VV_INVALID_HANDLE;
  {$ENDIF}
end;

{ Opens the socket / the pipe; False: Double Commander isn't there (or
  its remote control is off). }
function TDoubleCommanderLink.OpenChannel: Boolean;
{$IFDEF UNIX}
var
  Addr: TUnixSockAddr;
  Path: string;
  S: LongInt;
{$ENDIF}
{$IFDEF WINDOWS}
var
  Path: string;
  H: THandle;
{$ENDIF}
begin
  Result := False;
  {$IFDEF UNIX}
  Path := SocketFileName;
  if (Length(Path) >= SizeOf(Addr.path)) or not FileExists(Path) then
  begin
    FInfo := 'not running (or remote control off)';
    Exit;
  end;
  S := fpSocket(AF_UNIX, SOCK_STREAM, 0);
  if S < 0 then
    Exit;
  FillChar(Addr, SizeOf(Addr), 0);
  Addr.family := AF_UNIX;
  Move(Path[1], Addr.path[0], Length(Path));
  if fpConnect(S, @Addr, SizeOf(Addr)) <> 0 then
  begin
    CloseSocket(S);
    FInfo := 'not running';
    Exit;
  end;
  FpFcntl(S, F_SETFL, FpFcntl(S, F_GETFL) or O_NONBLOCK);
  { Not handed on to programs VV starts (Fiji, the editor, ...): a copy
    would keep the connection open after VV closed it. }
  FpFcntl(S, F_SETFD, FpFcntl(S, F_GETFD) or VV_FD_CLOEXEC);
  FSocket := S;
  Result := True;
  {$ENDIF}
  {$IFDEF WINDOWS}
  Path := SocketFileName;
  if Path = '' then
  begin
    FInfo := 'the user''s SID is not known';
    Exit;
  end;
  { No pipe of that name: not running, or its remote control is off.
    Busy (all instances taken, a moment only): next second. }
  H := VV_CreateFileW(PWideChar(UnicodeString(UTF8Decode(Path))),
    VV_GENERIC_READ or VV_GENERIC_WRITE, 0, nil, VV_OPEN_EXISTING,
    VV_SECURITY_SQOS_PRESENT or VV_SECURITY_IDENTIFICATION, 0);
  if H = VV_INVALID_HANDLE then
  begin
    FInfo := 'not running (or remote control off)';
    Exit;
  end;
  FPipe := H;
  Result := True;
  {$ENDIF}
end;

function TDoubleCommanderLink.SendRaw(const AData: string): Boolean;
{$IFDEF WINDOWS}
var
  N: DWORD;
{$ENDIF}
{$IFDEF UNIX}
var
  Done, Got: ssize_t;
  Fds: TFDSet;
  Wait: TTimeVal;
{$ENDIF}
begin
  Result := False;
  if (AData = '') or not IsConnected then
    Exit;
  {$IFDEF UNIX}
  { Non-blocking socket: a long line (SET COMMANDS) may go in parts; a
    full socket is waited for briefly (Double Commander reads every 10 ms). }
  Done := 0;
  while Done < Length(AData) do
  begin
    Got := fpSend(FSocket, @AData[1 + Done], Length(AData) - Done, VV_MSG_NOSIGNAL);
    if Got > 0 then
      Inc(Done, Got)
    else if (Got < 0) and (fpGetErrno = ESysEINTR) then
      Continue
    else if (Got < 0) and (fpGetErrno = ESysEAGAIN) then
    begin
      fpFD_ZERO(Fds);
      fpFD_SET(FSocket, Fds);
      Wait.tv_sec := 0;
      Wait.tv_usec := AnswerWaitMs * 1000;
      if fpSelect(FSocket + 1, nil, @Fds, nil, @Wait) <= 0 then
        Exit(False);
    end
    else
      Exit(False);               { EPIPE / ECONNRESET: Double Commander has gone }
  end;
  Result := True;
  {$ENDIF}
  {$IFDEF WINDOWS}
  { A short line into a 4 KB pipe buffer: returns at once. }
  N := 0;
  Result := VV_WriteFile(FPipe, @AData[1], Length(AData), @N, nil)
    and (N = DWORD(Length(AData)));
  {$ENDIF}
end;

function TDoubleCommanderLink.RecvSome(AWaitMs: Integer): Integer;
var
  Buffer: array[0..4095] of Char;
{$IFDEF UNIX}
  Got: ssize_t;
  Fds: TFDSet;
  Wait: TTimeVal;
  S: string;
{$ENDIF}
{$IFDEF WINDOWS}
  Avail, Got, Want: DWORD;
  Until_: QWord;
{$ENDIF}
begin
  Result := -1;
  if not IsConnected then
    Exit;
  if AWaitMs < 0 then
    AWaitMs := 0;
  {$IFDEF UNIX}
  fpFD_ZERO(Fds);
  fpFD_SET(FSocket, Fds);
  Wait.tv_sec := AWaitMs div 1000;
  Wait.tv_usec := (AWaitMs mod 1000) * 1000;
  if fpSelect(FSocket + 1, @Fds, nil, nil, @Wait) <= 0 then
    Exit(0);
  Got := fpRecv(FSocket, @Buffer[0], SizeOf(Buffer), 0);
  if (Got < 0) and ((fpGetErrno = ESysEAGAIN) or (fpGetErrno = ESysEINTR)) then
    Exit(0);
  if Got <= 0 then
    Exit(-1);
  SetString(S, PChar(@Buffer[0]), Got);
  FInput := FInput + S;
  Result := Got;
  {$ENDIF}
  {$IFDEF WINDOWS}
  { A pipe has no select: asked every 2 ms until something is there. }
  Until_ := GetTickCount64 + QWord(AWaitMs);
  repeat
    Avail := 0;
    if not VV_PeekNamedPipe(FPipe, nil, 0, nil, @Avail, nil) then
      Exit(-1);                 { Double Commander has gone }
    if Avail > 0 then
    begin
      Want := Avail;
      if Want > SizeOf(Buffer) then
        Want := SizeOf(Buffer);
      Got := 0;
      if not VV_ReadFile(FPipe, @Buffer[0], Want, @Got, nil) or (Got = 0) then
        Exit(-1);
      FInput := FInput + Copy(Buffer, 0, Got);
      Exit(Got);
    end;
    if GetTickCount64 >= Until_ then
      Exit(0);
    Sleep(2);
  until False;
  {$ENDIF}
end;

procedure TDoubleCommanderLink.Disconnect;
begin
  CloseChannel;
  FInput := '';
  if FState <> dsDenied then
    FState := dsNone;
end;

{ Opens the channel and says HELLO; True once connected (the answer to
  HELLO may still be outstanding: dsWaitingHello). }
function TDoubleCommanderLink.Connect: Boolean;
begin
  Result := IsConnected;
  if Result then
    Exit;
  { 1.4 (Day 40): no program configured, no connection (VV shows a
    notice; no pairing question in Double Commander). }
  if not FConfigured then
  begin
    FInfo := 'needs its program: [FileManager] DoubleCommander= in the ini';
    Exit;
  end;
  if GetTickCount64 < FNextTryMs then
    Exit;
  FNextTryMs := GetTickCount64 + RetryMs;
  if not OpenChannel then
    Exit;
  FInput := '';
  if not SendRaw('HELLO'#9 + ClientName + #9 + Token + #10) then
  begin
    Disconnect;
    Exit;
  end;
  FState := dsWaitingHello;
  FInfo := 'asking for permission (Double Commander asks its user once)';
  Result := True;
end;

{ Up to AWaitMs for one line; False if none came (or the connection
  ended: then disconnected). }
function TDoubleCommanderLink.ReadLine(AWaitMs: Integer; out ALine: string): Boolean;
var
  P: Integer;
  Until_: QWord;
  Left: Int64;
begin
  ALine := '';
  Result := False;
  Until_ := GetTickCount64 + QWord(Max(0, AWaitMs));
  repeat
    P := Pos(#10, FInput);
    if P > 0 then
    begin
      ALine := Copy(FInput, 1, P - 1);
      if (ALine <> '') and (ALine[Length(ALine)] = #13) then
        SetLength(ALine, Length(ALine) - 1);
      Delete(FInput, 1, P);
      Exit(True);
    end;
    if not IsConnected then
      Exit;
    Left := Int64(Until_) - Int64(GetTickCount64);
    if Left < 0 then
      Left := 0;
    case RecvSome(Integer(Left)) of
      -1:
        begin
          Disconnect;
          FInfo := 'connection ended';
          Exit;
        end;
      0:
        Exit;
    end;
  until False;
end;

{ Connected and allowed. The answer to HELLO is picked up here as soon as
  it has come (never waited for: Double Commander's user may take time). }
function TDoubleCommanderLink.Ready: Boolean;
var
  Line, Path: string;
  F: TStringArray;
begin
  Result := False;
  if FState = dsDenied then
    Exit;
  if not Connect then
    Exit;
  if FState = dsWaitingHello then
  begin
    if not ReadLine(0, Line) then
      Exit;
    F := Line.Split([#9]);
    if (Length(F) >= 2) and (F[0] = 'OK') then
    begin
      if F[1] <> Token then
        SaveToken(F[1]);
      FState := dsReady;
      FInfo := 'connected';
      FCheckStart := True;
      FCommandsDue := True;
    end
    else
    begin
      FState := dsDenied;
      FInfo := 'Double Commander refused (allow VersariteViewer there, then switch following off and on)';
      Disconnect;
      FState := dsDenied;
      Exit;
    end;
  end;
  Result := FState = dsReady;
  { Day 40: VV's commands, once per connection, for Double Commander's
    toolbar editor (cm_ViewerCommand). An older patch answers ERR: fine. }
  if Result and FCommandsDue then
  begin
    FCommandsDue := False;
    if FileManagerCommands <> '' then
      Ask('SET'#9'COMMANDS'#9 + FileManagerCommands, F);
    Result := FState = dsReady;
  end;
  { Day 40 (user: started with -L, only the left panel had its folder, the
    right one came up at C:\): the one VV started got no folder on its
    command line; it has restored its own panels by the time it answers,
    and now its active panel goes to VV's folder. }
  if Result and (FStartFolder <> '') then
  begin
    if GetTickCount64 <= FStartFolderUntil then
    begin
      Path := FStartFolder;
      FStartFolder := '';
      Ask('CMD'#9'cm_ChangeDir'#9'activepath=' + Path, F);
      Result := FState = dsReady;
    end
    else
      FStartFolder := '';
  end;
end;

function TDoubleCommanderLink.Ask(const ARequest: string; out AFields: TStringArray): Boolean;
var
  Line: string;
begin
  AFields := nil;
  Result := False;
  if not Ready then
    Exit;
  if not SendRaw(ARequest + #10) then
  begin
    Disconnect;
    Exit;
  end;
  if not ReadLine(AnswerWaitMs, Line) then
  begin
    { No answer in time (busy): the connection is dropped, so a late
      answer can't be taken for the next question's. }
    Disconnect;
    FInfo := 'no answer in time';
    Exit;
  end;
  AFields := Line.Split([#9]);
  Result := (Length(AFields) >= 1) and (AFields[0] = 'OK');
end;

function TDoubleCommanderLink.IsRunning: Boolean;
begin
  if not FConfigured then
    Exit(False);
  {$IFDEF UNIX}
  Result := IsConnected or FileExists(SocketFileName) and Connect;
  {$ELSE}
  { Windows: a pipe isn't looked at with FileExists (that would open an
    instance); trying to connect is the test. }
  Result := IsConnected or Connect;
  {$ENDIF}
end;

{ Side by side waits for this before placing Double Commander (Day 39):
  the pipe / socket is there as soon as Double Commander's main form is
  made, before the pairing answer and before its window is shown (with
  its saved place, often maximized). So: paired, and GET WINDOW says
  "shown" (an older patch without that field: taken as shown). }
function TDoubleCommanderLink.IsShown: Boolean;
var
  F: TStringArray;
begin
  Result := IsRunning and Ready and Ask('GET'#9'WINDOW', F)
    and ((Length(F) < 6) or (F[5] <> 'hidden'));
end;

{ 1.4 (user, Day 40): only the configured program ([FileManager]
  DoubleCommander=), no search: the patched build is wanted, not a stock
  one found in Program Files or on the PATH. }
function TDoubleCommanderLink.ProgramPath(const AConfigured: string): string;
var
  C: string;
begin
  C := Trim(AConfigured);
  if (C <> '') and FileExists(C) then
    Result := C
  else
    Result := '';
end;

function TDoubleCommanderLink.Open(const AProgram, AFolder: string): Boolean;
var
  F: TStringArray;
  P: TProcess;
begin
  if not FConfigured then
    Exit(False);
  if IsRunning and Ready then
  begin
    if AFolder = '' then
      Exit(True);
    Exit(Ask('CMD'#9'cm_ChangeDir'#9'activepath=' + AFolder, F));
  end;
  { Running, its pairing question still open: no second one started
    (it would only bring up another question). }
  if IsConnected and (FState = dsWaitingHello) then
    Exit(True);
  Result := False;
  if AProgram = '' then
    Exit;
  P := TProcess.Create(nil);
  try
    {$IFDEF UNIX}
    { 1.4: through setsid -f (util-linux): it forks Double Commander off
      in a session of its own and ends at once; that end is waited for
      here, so no ended child is left unreaped (it showed as
      "doublecmd <defunct>" until VV ended), and Double Commander isn't
      VV's child at all: it outlives VV. Without setsid: as before. }
    if FileExists('/usr/bin/setsid') then
    begin
      P.Executable := '/usr/bin/setsid';
      P.Parameters.Add('-f');
      P.Parameters.Add(AProgram);
      P.Options := [poWaitOnExit];
    end
    else
    begin
      P.Executable := AProgram;
      P.Options := [];
    end;
    {$ELSE}
    { Windows: started on its own (no console, not waited for); it
      outlives VV. }
    P.Executable := AProgram;
    P.Options := [];
    {$ENDIF}
    P.Parameters.Add('--no-splash');
    P.InheritHandles := False;
    try
      P.Execute;
      Result := True;
      FNextTryMs := 0;
      { The folder once it is connected (Ready), not -L (Day 40). }
      FStartFolder := AFolder;
      FStartFolderUntil := GetTickCount64 + 60000;
    except
      Result := False;
    end;
  finally
    P.Free;
  end;
end;

function TDoubleCommanderLink.PlaceAt(const ARect: TRect): Boolean;
var
  F: TStringArray;
  R: TRect;
{$IFDEF WINDOWS}
  B: Integer;
{$ENDIF}
begin
  R := ARect;
  {$IFDEF WINDOWS}
  B := InvisibleBorder;
  R := Rect(R.Left - B, R.Top, R.Right + B, R.Bottom + B);
  {$ENDIF}
  Result := Ask(Format('SET'#9'WINDOW'#9'%d'#9'%d'#9'%d'#9'%d',
    [R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top]), F);
end;

function TDoubleCommanderLink.WindowRect(out ARect: TRect): Boolean;
var
  F: TStringArray;
  L, T, W, H: Integer;
{$IFDEF WINDOWS}
  B: Integer;
{$ENDIF}
begin
  ARect := Rect(0, 0, 0, 0);
  Result := Ask('GET'#9'WINDOW', F) and (Length(F) >= 5)
    and TryStrToInt(F[1], L) and TryStrToInt(F[2], T)
    and TryStrToInt(F[3], W) and TryStrToInt(F[4], H);
  if Result then
  begin
    ARect := Rect(L, T, L + W, T + H);
    {$IFDEF WINDOWS}
    B := InvisibleBorder;
    if (W > 2 * B) and (H > B) then
      ARect := Rect(ARect.Left + B, ARect.Top, ARect.Right - B, ARect.Bottom - B);
    {$ENDIF}
  end;
end;

function TDoubleCommanderLink.MoveToWork(const AFrom, ATo: TRect): Boolean;
var
  R: TRect;
  W, H, L, T: Integer;
begin
  Result := WindowRect(R);
  if not Result then
    Exit;
  W := Min(R.Right - R.Left, ATo.Right - ATo.Left);
  H := Min(R.Bottom - R.Top, ATo.Bottom - ATo.Top);
  L := R.Left - AFrom.Left + ATo.Left;
  T := R.Top - AFrom.Top + ATo.Top;
  if L + W > ATo.Right then
    L := ATo.Right - W;
  if T + H > ATo.Bottom then
    T := ATo.Bottom - H;
  if L < ATo.Left then
    L := ATo.Left;
  if T < ATo.Top then
    T := ATo.Top;
  Result := PlaceAt(Rect(L, T, L + W, T + H));
end;

function TDoubleCommanderLink.Poll(AWantFile: Boolean; out AFolder, AFile: string): Boolean;
var
  F: TStringArray;
begin
  AFolder := '';
  AFile := '';
  { GET FOLLOW (Day 40): folder and cursor in one question - each one
    holds VV's window until Double Commander answers. }
  if not FNoFollowQuery then
  begin
    Result := Ask('GET'#9'FOLLOW'#9'active', F);
    if not Result and (Length(F) >= 2) and (F[0] = 'ERR') then
      FNoFollowQuery := True            { an older patch: the two questions }
    else
    begin
      Result := Result and (Length(F) >= 3) and (F[2] = 'filesystem');
      if not Result then
        Exit;
      AFolder := F[1];
      if AWantFile and (Length(F) >= 4) then
      begin
        AFile := F[3];
        FCursorSeen := True;
      end;
      FInfo := 'folder ' + AFolder;
      if AFile <> '' then
        FInfo := FInfo + ', cursor ' + ExtractFileName(AFile);
      Exit;
    end;
  end;
  Result := Ask('GET'#9'PATH'#9'active', F) and (Length(F) >= 3) and (F[2] = 'filesystem');
  if not Result then
    Exit;
  AFolder := F[1];
  if AWantFile then
  begin
    if Ask('GET'#9'CURSOR'#9'active', F) and (Length(F) >= 2) then
    begin
      AFile := F[1];
      FCursorSeen := True;
    end;
  end;
  FInfo := 'folder ' + AFolder;
  if AFile <> '' then
    FInfo := FInfo + ', cursor ' + ExtractFileName(AFile);
end;

function TDoubleCommanderLink.CursorSupported: Boolean;
begin
  Result := FCursorSeen or (FState = dsReady);
end;

function TDoubleCommanderLink.PanelItems(out ALeft, ARight: string): Boolean;
var
  F: TStringArray;
begin
  ALeft := '';
  ARight := '';
  Result := Ask('GET'#9'CURSOR'#9'left', F);
  if not Result then
    Exit;
  if Length(F) >= 2 then
    ALeft := F[1];
  if Ask('GET'#9'CURSOR'#9'right', F) and (Length(F) >= 2) then
    ARight := F[1];
end;

function TDoubleCommanderLink.Info: string;
begin
  Result := FInfo;
end;

procedure TDoubleCommanderLink.Restart;
begin
  { Following switched off and on: a refusal is asked again. }
  if FState = dsDenied then
    FState := dsNone;
  FCursorSeen := False;
  FNextTryMs := 0;
end;

function TDoubleCommanderLink.CanShowFolder: Boolean;
begin
  Result := True;
end;

{ 1.4: cm_ChangeDir with the panel's parameter (leftpath= etc.), one of
  the commands its remote control allows. The folder goes as one field
  (TAB-separated), so spaces are fine. }
function TDoubleCommanderLink.ShowFolder(const AFolder: string; APanel: TFMPanel): Boolean;
const
  Param: array[TFMPanel] of string = ('activepath=', 'inactivepath=', 'leftpath=', 'rightpath=');
var
  F: TStringArray;
  Folder: string;
begin
  Folder := ExcludeTrailingPathDelimiter(AFolder);
  {$IFDEF WINDOWS}
  { A drive's root keeps its backslash ("C:\"; "C:" is the drive's
    current folder). }
  if (Length(Folder) = 2) and (Folder[2] = ':') then
    Folder := Folder + '\';
  {$ENDIF}
  if Folder = '' then
    Folder := PathDelim;
  Result := (Pos(#9, Folder) = 0) and (Pos(#10, Folder) = 0)
    and Ask('CMD'#9'cm_ChangeDir'#9 + Param[APanel] + Folder, F);
  if Result then
    FInfo := 'showed ' + Folder;
end;

function TDoubleCommanderLink.CanMakeFolder: Boolean;
begin
  Result := True;
end;

{ 1.4 (user): cm_MakeDir path=<full name> (the patch: made without its
  dialog, an existing folder left alone). Double Commander makes it as
  one of its operations: VV gives it up to a second to appear. }
function TDoubleCommanderLink.MakeFolder(const AFolder: string): Boolean;
const
  AppearMs = 1000;
var
  F: TStringArray;
  Folder: string;
  Until_: QWord;
begin
  Folder := ExcludeTrailingPathDelimiter(AFolder);
  { Double Commander expands %-variables in parameters: such a name is
    left to VV. }
  Result := (Folder <> '') and (Pos(#9, Folder) = 0) and (Pos(#10, Folder) = 0)
    and (Pos('%', Folder) = 0) and IsRunning
    and Ask('CMD'#9'cm_MakeDir'#9'path=' + Folder, F);
  if not Result then
    Exit;
  Until_ := GetTickCount64 + AppearMs;
  while not DirectoryExists(Folder) and (GetTickCount64 < Until_) do
    Sleep(20);
  Result := DirectoryExists(Folder);
  if Result then
    FInfo := 'made ' + Folder;
end;

{ GET EVENT: "OK" alone = nothing; "OK <fields>" = one message. A Double
  Commander without events answers ERR: nothing. Only once paired (the
  pairing question is never waited for here). }
function TDoubleCommanderLink.NextEvent(out AFields: TStringArray): Boolean;
var
  F: TStringArray;
  I: Integer;
begin
  AFields := nil;
  Result := False;
  if not IsRunning or not Ready then
    Exit;
  if not Ask('GET'#9'EVENT', F) or (Length(F) < 2) then
    Exit;
  SetLength(AFields, Length(F) - 1);
  for I := 1 to High(F) do
    AFields[I - 1] := F[I];
  Result := True;
end;

procedure TDoubleCommanderLink.Configure(const AProgram: string);
var
  Was: Boolean;
begin
  Was := FConfigured;
  FProgram := Trim(AProgram);
  FConfigured := (FProgram <> '') and FileExists(FProgram);
  if Was and not FConfigured then
    Disconnect;
  if not FConfigured then
  begin
    if FProgram = '' then
      FInfo := 'needs its program: [FileManager] DoubleCommander= in the ini'
    else
      FInfo := 'its program is not there: ' + FProgram;
  end
  else if not Was then
    FNextTryMs := 0;
end;

function TDoubleCommanderLink.IsConfigured: Boolean;
begin
  Result := FConfigured;
end;

{ SET CURSOR active <file> (Day 40): the file VV shows, under the cursor
  of Double Commander's active panel (another folder: it goes there). }
function TDoubleCommanderLink.SetCursor(const AFile: string): Boolean;
var
  F: TStringArray;
begin
  Result := (AFile <> '') and (Pos(#9, AFile) = 0) and (Pos(#10, AFile) = 0)
    and IsRunning and Ready and Ask('SET'#9'CURSOR'#9'active'#9 + AFile, F);
end;

{ SET SORT active name|date asc|desc (Day 40); the same order again is not
  sent (until another Double Commander comes). }
function TDoubleCommanderLink.SetSort(const AKey: string; ADescending: Boolean): Boolean;
var
  F: TStringArray;
  Line: string;
begin
  Line := 'SET'#9'SORT'#9'active'#9 + AKey + #9;
  if ADescending then
    Line := Line + 'desc'
  else
    Line := Line + 'asc';
  if Line = FSortSent then
    Exit(True);
  Result := IsRunning and Ready and Ask(Line, F);
  if Result then
    FSortSent := Line;
end;

{ After each pairing, GET UPTIME: a Double Commander that started at
  another moment than the one seen before is a new one (its order is sent
  again); one that started less than a minute ago is "fresh" (settings
  for its start: thumbnails). An older patch without UPTIME: never fresh. }
function TDoubleCommanderLink.TakeFreshStart: Boolean;
const
  FreshMs = 60000;
  SameStartMs = 3000;
var
  F: TStringArray;
  Up, Started: Int64;
begin
  { Ready first: it takes in the pairing answer (and sets FCheckStart). }
  if IsRunning and Ready and FCheckStart then
  begin
    FCheckStart := False;
    if Ask('GET'#9'UPTIME', F) and (Length(F) >= 2) and TryStrToInt64(F[1], Up) then
    begin
      Started := Int64(GetTickCount64) - Up;
      if Abs(Started - FInstanceMs) > SameStartMs then
      begin
        FInstanceMs := Started;
        FSortSent := '';
        FFresh := Up < FreshMs;
      end;
    end;
  end;
  Result := FFresh;
  FFresh := False;
end;

{ Thumbnail view on (Day 40): 1 = the inactive panel, 2 = the active one
  (cm_LeftThumbView / cm_RightThumbView state=on). }
function TDoubleCommanderLink.SetThumbnails(APanel: Integer): Boolean;
var
  F: TStringArray;
  Left: Boolean;
begin
  Result := False;
  if not (APanel in [1, 2]) or not Ask('GET'#9'ACTIVE', F) or (Length(F) < 2) then
    Exit;
  Left := F[1] = 'left';
  if APanel = 1 then
    Left := not Left;
  if Left then
    Result := Ask('CMD'#9'cm_LeftThumbView'#9'state=on', F)
  else
    Result := Ask('CMD'#9'cm_RightThumbView'#9'state=on', F);
end;

initialization
  RegisterFileManager(dmDoubleCommander, TDoubleCommanderLink);

end.
