unit uContainerThumbs;

{
  Unit: uContainerThumbs

  Purpose
  -------
  The side panel's list of a container's images (M2c, Day 25): reads
  the container's entries and makes a small and a large thumbnail of
  each, on a thread of its own, so the window never waits for the disk
  (MView's rule) and the viewer's own decode workers are not pushed
  aside (they serve the image on screen and its neighbours).

  Owns
  ----
  - Its thread; the bitmaps until they are delivered (then the
    receiver's).

  Knows
  -----
  - Nothing of the panel: two events.

  Responsibilities
  ----------------
  - Request(container, small size, large size): the newest request
    replaces any older one (whose work stops at the next check). The
    container may be a stack inside one (a virtual name, Day 26): its
    frames are listed; the entries' virtual names are always made with
    the container file.
  - First OnListed (the entries), then OnThumb for each entry in the
    file's order, the preferred one (the entry under the mouse, Prefer)
    first.
  - Gives way to the image on screen (I/O gate) before each decode.
  - Cancel: nothing more is delivered for the current request.

  Does NOT
  --------
  - Keep thumbnails (the receiver caches them).

  Threads
  -------
  Request / Prefer / Cancel and the events: UI thread. The work: its
  thread. Results go through TThread.Queue; a thread stuck in a read is
  left alone at the end (it delivers nothing any more), as uSortIcons
  does.

  Uses (MView units)
  ------------------
  interface:      uContainers
  implementation: uTypes, uImageScaling, uIOGate
  Libraries:      Classes, SysUtils, SyncObjs, Math, BGRABitmap,
                  BGRABitmapTypes

  Used by
  -------
  uMView
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  SyncObjs,
  BGRABitmap,
  uContainers;

type
  TThumbListedEvent = procedure(const AContainer: string;
    const AEntries: TContainerEntryArray) of object;
  { ASmall / ALarge become the receiver's (nil if it couldn't be read). }
  TThumbReadyEvent = procedure(const AVirtualName: string;
    ASmall, ALarge: TBGRABitmap) of object;

  TContainerThumbs = class;

  TThumbResult = class
  public
    Generation: Cardinal;
    IsListing: Boolean;
    Container: string;
    Entries: TContainerEntryArray;
    VirtualName: string;
    Small, Large: TBGRABitmap;
    destructor Destroy; override;
  end;

  TContainerThumbThread = class(TThread)
  private
    FLock: TCriticalSection;
    FWake: TEvent;
    FOwner: TContainerThumbs;    { nil once the owner has gone }
    FContainer: string;
    FSmall, FLarge: Integer;
    FGeneration: Cardinal;       { of the newest request }
    FWorkGeneration: Cardinal;   { of the one being worked on }
    FDoneGeneration: Cardinal;   { the last one finished: not again }
    FPreferred: string;
    FResults: TList;             { TThumbResult, waiting for Deliver }
    procedure Deliver;
    procedure Post(AResult: TThumbResult);
    function WorkCancelled: Boolean;
    function TakePreferred: string;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TContainerThumbs);
    destructor Destroy; override;
    procedure Request(const AContainer: string; ASmall, ALarge: Integer; AGeneration: Cardinal);
    procedure Prefer(const AVirtualName: string);
    procedure Detach;
  end;

  TContainerThumbs = class(TObject)
  private
    FThread: TContainerThumbThread;
    FGeneration: Cardinal;
    FContainer: string;
    FOnListed: TThumbListedEvent;
    FOnThumb: TThumbReadyEvent;
    procedure Take(AResult: TThumbResult);
  public
    destructor Destroy; override;
    { Day 25 (Esc to the settings without waiting): the thread told to
      stop, nothing delivered any more; Stopped: it has come back. }
    procedure BeginShutdown;
    function Stopped: Boolean;
    procedure Request(const AContainer: string; ASmall, ALarge: Integer);
    { The entry under the mouse: made next. }
    procedure Prefer(const AVirtualName: string);
    procedure Cancel;
    property Container: string read FContainer;
    property OnListed: TThumbListedEvent read FOnListed write FOnListed;
    property OnThumb: TThumbReadyEvent read FOnThumb write FOnThumb;
  end;

{ RGBA bytes (R G B A per pixel, rows top down) as a bitmap (Day 26: a
  stack's frame shown, uMView). }
function RGBAToBitmap(const ARGBA: TBytes; AWidth, AHeight: Integer): TBGRABitmap;

implementation

uses
  Math,
  BGRABitmapTypes,
  uTypes,
  uImageScaling,
  uIOGate;

{ TThumbResult }

destructor TThumbResult.Destroy;
begin
  Small.Free;
  Large.Free;
  inherited Destroy;
end;

{ A copy of ABitmap that fits into ASize x ASize (never larger than the
  original). }
function FitCopy(ABitmap: TBGRABitmap; ASize: Integer): TBGRABitmap;
var
  W, H: Integer;
begin
  Result := nil;
  if (ABitmap = nil) or (ASize <= 0) then
    Exit;
  FitSize(ABitmap.Width, ABitmap.Height, ASize, ASize, W, H);
  W := Max(1, Min(W, ABitmap.Width));
  H := Max(1, Min(H, ABitmap.Height));
  if (W = ABitmap.Width) and (H = ABitmap.Height) then
    Result := ABitmap.Duplicate as TBGRABitmap
  else
    Result := ShrinkToSize(ABitmap, W, H);
end;

function RGBAToBitmap(const ARGBA: TBytes; AWidth, AHeight: Integer): TBGRABitmap;
var
  X, Y: Integer;
  P: PtrInt;
  Row: PBGRAPixel;
begin
  Result := TBGRABitmap.Create(AWidth, AHeight);
  P := 0;
  for Y := 0 to AHeight - 1 do
  begin
    Row := Result.ScanLine[Y];
    for X := 0 to AWidth - 1 do
    begin
      Row^.red := ARGBA[P];
      Row^.green := ARGBA[P + 1];
      Row^.blue := ARGBA[P + 2];
      Row^.alpha := ARGBA[P + 3];
      Inc(Row);
      Inc(P, 4);
    end;
  end;
  Result.InvalidateBitmap;
end;

{ TContainerThumbThread }

constructor TContainerThumbThread.Create(AOwner: TContainerThumbs);
begin
  FOwner := AOwner;
  FLock := TCriticalSection.Create;
  FWake := TEvent.Create(nil, False, False, '');
  FResults := TList.Create;
  inherited Create(False);
end;

destructor TContainerThumbThread.Destroy;
var
  I: Integer;
begin
  for I := 0 to FResults.Count - 1 do
    TThumbResult(FResults[I]).Free;
  FResults.Free;
  FWake.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TContainerThumbThread.Request(const AContainer: string; ASmall, ALarge: Integer;
  AGeneration: Cardinal);
begin
  FLock.Acquire;
  try
    FContainer := AContainer;
    FSmall := ASmall;
    FLarge := ALarge;
    FGeneration := AGeneration;
    FPreferred := '';
  finally
    FLock.Release;
  end;
  FWake.SetEvent;
end;

procedure TContainerThumbThread.Prefer(const AVirtualName: string);
begin
  FLock.Acquire;
  try
    FPreferred := AVirtualName;
  finally
    FLock.Release;
  end;
end;

procedure TContainerThumbThread.Detach;
begin
  FLock.Acquire;
  try
    FOwner := nil;
    Inc(FGeneration);
  finally
    FLock.Release;
  end;
  Terminate;
  FWake.SetEvent;
end;

{ Thread: the current work is no longer wanted. }
function TContainerThumbThread.WorkCancelled: Boolean;
begin
  if Terminated then
    Exit(True);
  FLock.Acquire;
  try
    Result := FGeneration <> FWorkGeneration;
  finally
    FLock.Release;
  end;
end;

function TContainerThumbThread.TakePreferred: string;
begin
  FLock.Acquire;
  try
    Result := FPreferred;
    FPreferred := '';
  finally
    FLock.Release;
  end;
end;

procedure TContainerThumbThread.Post(AResult: TThumbResult);
begin
  FLock.Acquire;
  try
    FResults.Add(AResult);
  finally
    FLock.Release;
  end;
  if not Terminated then
    Queue(@Deliver);
end;

procedure TContainerThumbThread.Execute;
var
  Container, Name, Preferred, Error: string;
  Small, Large, I, W, H: Integer;
  Entries: TContainerEntryArray;
  Todo: TStringList;
  RGBA: TBytes;
  Full: TBGRABitmap;
  R: TThumbResult;
begin
  Todo := TStringList.Create;
  try
    while not Terminated do
    begin
      FWake.WaitFor(1000);
      if Terminated then
        Break;
      FLock.Acquire;
      try
        Container := FContainer;
        Small := FSmall;
        Large := FLarge;
        FWorkGeneration := FGeneration;
      finally
        FLock.Release;
      end;
      { Nothing asked, or done already (the wait also ends every second). }
      if (Container = '') or (FWorkGeneration = FDoneGeneration) then
        Continue;

      { 1. The entries. }
      IOGate.YieldToDisplay(@WorkCancelled);
      if WorkCancelled then
        Continue;
      ListContainerEntries(Container, Entries);
      R := TThumbResult.Create;
      R.Generation := FWorkGeneration;
      R.IsListing := True;
      R.Container := Container;
      R.Entries := Entries;
      Post(R);

      { 2. Their thumbnails, the preferred one first. }
      Todo.Clear;
      for I := 0 to High(Entries) do
        Todo.Add(MakeVirtualName(ContainerFileOf(Container), Entries[I].Id));
      while (Todo.Count > 0) and not WorkCancelled do
      begin
        Preferred := TakePreferred;
        I := Todo.IndexOf(Preferred);
        if I < 0 then
          I := 0;
        Name := Todo[I];
        Todo.Delete(I);
        IOGate.YieldToDisplay(@WorkCancelled);
        if WorkCancelled then
          Break;
        R := TThumbResult.Create;
        R.Generation := FWorkGeneration;
        R.Container := Container;
        R.VirtualName := Name;
        try
          if DecodeContainerEntry(Name, @WorkCancelled, W, H, RGBA, Error)
            and (W > 0) and (H > 0) then
          begin
            Full := RGBAToBitmap(RGBA, W, H);
            RGBA := nil;
            try
              R.Small := FitCopy(Full, Small);
              R.Large := FitCopy(Full, Large);
            finally
              Full.Free;
            end;
          end;
        except
          { No thumbnail: the panel keeps its grey square. }
          FreeAndNil(R.Small);
          FreeAndNil(R.Large);
        end;
        RGBA := nil;
        if WorkCancelled then
        begin
          R.Free;
          Break;
        end;
        Post(R);
      end;
      if not WorkCancelled then
        FDoneGeneration := FWorkGeneration;
    end;
  finally
    Todo.Free;
  end;
end;

{ UI thread. }
procedure TContainerThumbThread.Deliver;
var
  Taken: TList;
  Owner: TContainerThumbs;
  I: Integer;
begin
  Taken := TList.Create;
  try
    FLock.Acquire;
    try
      Taken.Assign(FResults);
      FResults.Clear;
      Owner := FOwner;
    finally
      FLock.Release;
    end;
    for I := 0 to Taken.Count - 1 do
      if Owner <> nil then
      begin
        try
          Owner.Take(TThumbResult(Taken[I]));
        except
          { One bad delivery doesn't lose the rest. }
        end;
      end
      else
        TThumbResult(Taken[I]).Free;
  finally
    Taken.Free;
  end;
end;

{ TContainerThumbs }

procedure TContainerThumbs.BeginShutdown;
begin
  if Assigned(FThread) then
    FThread.Detach;
end;

function TContainerThumbs.Stopped: Boolean;
begin
  Result := (FThread = nil) or FThread.Finished;
end;

destructor TContainerThumbs.Destroy;
var
  I: Integer;
begin
  if Assigned(FThread) then
  begin
    FThread.Detach;
    { A read that hangs: the thread is left alone, it delivers nothing. }
    for I := 1 to 50 do
    begin
      if FThread.Finished then
        Break;
      Sleep(20);
    end;
    if FThread.Finished then
    begin
      FThread.WaitFor;
      TThread.RemoveQueuedEvents(FThread);
      FThread.Free;
    end;
    FThread := nil;
  end;
  inherited Destroy;
end;

procedure TContainerThumbs.Request(const AContainer: string; ASmall, ALarge: Integer);
begin
  Inc(FGeneration);
  FContainer := AContainer;
  if FThread = nil then
    FThread := TContainerThumbThread.Create(Self);
  FThread.Request(AContainer, ASmall, ALarge, FGeneration);
end;

procedure TContainerThumbs.Prefer(const AVirtualName: string);
begin
  if FThread <> nil then
    FThread.Prefer(AVirtualName);
end;

procedure TContainerThumbs.Cancel;
begin
  Inc(FGeneration);
  FContainer := '';
  if FThread <> nil then
    FThread.Request('', 0, 0, FGeneration);
end;

{ UI thread: a result of the current request goes to the receiver, an
  older one is dropped. }
procedure TContainerThumbs.Take(AResult: TThumbResult);
var
  Small, Large: TBGRABitmap;
begin
  try
    if AResult.Generation <> FGeneration then
      Exit;
    if AResult.IsListing then
    begin
      if Assigned(FOnListed) then
        FOnListed(AResult.Container, AResult.Entries);
    end
    else if Assigned(FOnThumb) then
    begin
      { The receiver's from now on (also if it raises). }
      Small := AResult.Small;
      Large := AResult.Large;
      AResult.Small := nil;
      AResult.Large := nil;
      FOnThumb(AResult.VirtualName, Small, Large);
    end;
  finally
    AResult.Free;
  end;
end;

end.
