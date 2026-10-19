unit uDirPeek;

{
  Unit: uDirPeek

  Purpose
  -------
  A quick look into a folder for the Total Commander dir preview (1.1,
  testers): how many images it has (directly in it) and how many
  subfolders (one level down). On a thread of its own, so a folder with
  thousands of files, or on a slow network drive, never holds up the
  window while the arrow keys move Total Commander's cursor.

  Owns
  ----
  - One short-lived thread per request (freed by itself), and a shared
    state object the owner and its threads hold (TPeekShared).

  Knows
  -----
  - Which files are images (uImageFormats.IsSupportedImageFile).

  Responsibilities
  ----------------
  - Request(folder): the newest request wins; an older one still running
    delivers nothing.
  - OnResult on the UI thread: the folder, its image count, its
    subfolder count. Handed over with TThread.Queue (the program's rule:
    a thread never waits for the UI). A thread with a result does not
    free itself (FPC drops a thread's queued calls when it is freed):
    the result frees it once delivered. A thread with nothing to deliver
    frees itself.
  - The owner freed: its threads deliver nothing (Detach).

  Does NOT
  --------
  - Sort or show anything (TMView: the navigator does).

  Threads
  -------
  Request / the event: UI thread. The counting: its thread.

  Uses (MView units)
  ------------------
  implementation: uImageFormats
  Libraries:      Classes, SysUtils, SyncObjs

  Used by
  -------
  uMView, TestNavigation
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  SyncObjs;

type
  TDirPeekEvent = procedure(const AFolder: string; AImages, AFolders: Integer) of object;

  TDirPeek = class;

  { Lives as long as the owner or any of its threads. }
  TPeekShared = class
  private
    FLock: TCriticalSection;
    FOwner: TDirPeek;           { nil once the owner has gone }
    FGeneration: Cardinal;
    FUsers: Integer;            { the owner + running threads }
  public
    constructor Create(AOwner: TDirPeek);
    destructor Destroy; override;
    procedure AddUser;
    procedure Release;
  end;

  TDirPeek = class(TObject)
  private
    FShared: TPeekShared;
    FOnResult: TDirPeekEvent;
  public
    constructor Create;
    destructor Destroy; override;
    { Count AFolder's images and subfolders; the result comes later
      (OnResult), unless another request came first. }
    procedure Request(const AFolder: string);
    { Nothing more from the requests so far. }
    procedure Cancel;
    property OnResult: TDirPeekEvent read FOnResult write FOnResult;
  end;

{ The counting itself (any thread; also for the tests). }
procedure CountFolder(const AFolder: string; out AImages, AFolders: Integer);

implementation

uses
  uImageFormats;

procedure CountFolder(const AFolder: string; out AImages, AFolders: Integer);
var
  Info: TSearchRec;
begin
  AImages := 0;
  AFolders := 0;
  if FindFirst(IncludeTrailingPathDelimiter(AFolder) + '*', faAnyFile, Info) = 0 then
    try
      repeat
        if (Info.Name = '.') or (Info.Name = '..') then
          Continue;
        if (Info.Attr and faDirectory) <> 0 then
          Inc(AFolders)
        else if IsSupportedImageFile(Info.Name) then
          Inc(AImages);
      until FindNext(Info) <> 0;
    finally
      FindClose(Info);
    end;
end;

type
  { One count on its way to the UI thread; frees itself and its thread. }
  TPeekResult = class
  private
    FThread: TThread;
    FShared: TPeekShared;
    FFolder: string;
    FGeneration: Cardinal;
    FImages, FFolders: Integer;
  public
    procedure Deliver;
  end;

  TPeekThread = class(TThread)
  private
    FShared: TPeekShared;
    FFolder: string;
    FGeneration: Cardinal;
    FImages, FFolders: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(AShared: TPeekShared; const AFolder: string; AGeneration: Cardinal);
  end;

{ TPeekShared }

constructor TPeekShared.Create(AOwner: TDirPeek);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FOwner := AOwner;
  FUsers := 1;
end;

destructor TPeekShared.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

procedure TPeekShared.AddUser;
begin
  FLock.Acquire;
  try
    Inc(FUsers);
  finally
    FLock.Release;
  end;
end;

procedure TPeekShared.Release;
var
  Last: Boolean;
begin
  FLock.Acquire;
  try
    Dec(FUsers);
    Last := FUsers = 0;
  finally
    FLock.Release;
  end;
  if Last then
    Free;
end;

{ TPeekThread }

constructor TPeekThread.Create(AShared: TPeekShared; const AFolder: string; AGeneration: Cardinal);
begin
  FShared := AShared;
  FShared.AddUser;
  FFolder := AFolder;
  FGeneration := AGeneration;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TPeekThread.Execute;
var
  Wanted: Boolean;
  R: TPeekResult;
begin
  try
    try
      CountFolder(FFolder, FImages, FFolders);
    except
      FImages := -1;
      FFolders := -1;
    end;
    FShared.FLock.Acquire;
    try
      Wanted := (FShared.FOwner <> nil) and (FShared.FGeneration = FGeneration);
    finally
      FShared.FLock.Release;
    end;
    if Wanted then
    begin
      FreeOnTerminate := False;   { the result frees it }
      R := TPeekResult.Create;
      R.FThread := Self;
      R.FShared := FShared;
      FShared.AddUser;
      R.FFolder := FFolder;
      R.FGeneration := FGeneration;
      R.FImages := FImages;
      R.FFolders := FFolders;
      TThread.Queue(nil, @R.Deliver);
    end;
  finally
    FShared.Release;
  end;
end;

{ TPeekResult: UI thread. }
procedure TPeekResult.Deliver;
var
  Owner: TDirPeek;
begin
  try
    Owner := nil;
    FShared.FLock.Acquire;
    try
      if FShared.FGeneration = FGeneration then
        Owner := FShared.FOwner;
    finally
      FShared.FLock.Release;
    end;
    if (Owner <> nil) and (FImages >= 0) and Assigned(Owner.FOnResult) then
      Owner.FOnResult(FFolder, FImages, FFolders);
  finally
    FShared.Release;
    FThread.WaitFor;       { it is at its very end: past its last line }
    FThread.Free;
    Free;
  end;
end;

{ TDirPeek }

constructor TDirPeek.Create;
begin
  inherited Create;
  FShared := TPeekShared.Create(Self);
end;

destructor TDirPeek.Destroy;
begin
  FShared.FLock.Acquire;
  try
    FShared.FOwner := nil;
    Inc(FShared.FGeneration);
  finally
    FShared.FLock.Release;
  end;
  FShared.Release;
  inherited Destroy;
end;

procedure TDirPeek.Request(const AFolder: string);
var
  Gen: Cardinal;
begin
  FShared.FLock.Acquire;
  try
    Inc(FShared.FGeneration);
    Gen := FShared.FGeneration;
  finally
    FShared.FLock.Release;
  end;
  TPeekThread.Create(FShared, AFolder, Gen);
end;

procedure TDirPeek.Cancel;
begin
  FShared.FLock.Acquire;
  try
    Inc(FShared.FGeneration);
  finally
    FShared.FLock.Release;
  end;
end;

end.
