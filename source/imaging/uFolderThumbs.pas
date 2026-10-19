unit uFolderThumbs;

{
  Unit: uFolderThumbs

  Purpose
  -------
  Small thumbnails of a folder's images for the preview strip (Day 27,
  testers), made on a thread of their own, so the window never waits
  for the disk and the viewer's decode workers keep serving the image
  on screen.

  Owns
  ----
  - Its thread, and a TMediaLoader used only by that thread.
  - The bitmaps until they are delivered (then the receiver's).

  Knows
  -----
  - Nothing of the strip: one event (OnThumb).

  Responsibilities
  ----------------
  - Request(files, size): the newest list replaces the older one; the
    files are made in the list's order (the caller puts the ones in
    sight first). A file already delivered for this size is not made
    again until Forget.
  - A JPEG's embedded thumbnail first (cheap); else a quick decode at
    about twice the thumbnail size (JPEGs scaled in the codec), shrunk
    to fit Size x Size.
  - Gives way to the image on screen (I/O gate) before each file.
  - A file that can't be read: delivered as nil (the strip draws a grey
    box and doesn't ask again).

  Does NOT
  --------
  - Keep thumbnails (the strip caches them).

  Threads
  -------
  Request / Forget / the event: UI thread. The work: its thread.
  Results go through TThread.Queue. At the end the thread is told to
  stop and left alone if stuck in a read (it delivers nothing more), as
  uContainerThumbs does.

  Uses (MView units)
  ------------------
  implementation: uTypes, uDecodedImage, umedialoader, uImageScaling,
                  uIOGate
  Libraries:      Classes, SysUtils, SyncObjs, Math, BGRABitmap

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
  BGRABitmap;

type
  { ABitmap becomes the receiver's; nil = could not be read. }
  TFolderThumbEvent = procedure(const AFileName: string; ABitmap: TBGRABitmap) of object;

  TFolderThumbs = class;

  TFolderThumbThread = class(TThread)
  private
    FLock: TCriticalSection;
    FWake: TEvent;
    FOwner: TFolderThumbs;       { nil once the owner has gone }
    FFiles: TStringList;         { the newest request }
    FSize: Integer;
    FGeneration: Cardinal;
    FWorkGeneration: Cardinal;
    FResults: TStringList;       { file name -> TBGRABitmap (or nil) }
    procedure Deliver;
    function WorkCancelled: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TFolderThumbs);
    destructor Destroy; override;
    procedure Request(AFiles: TStrings; ASize: Integer);
    procedure Detach;
  end;

  TFolderThumbs = class(TObject)
  private
    FThread: TFolderThumbThread;
    FDone: TStringList;          { delivered for FSize (sorted, no case) }
    FSize: Integer;
    FLastRequest: string;        { the last list sent (the same again: not resent) }
    FOnThumb: TFolderThumbEvent;
    procedure Take(const AFileName: string; ABitmap: TBGRABitmap);
  public
    constructor Create;
    destructor Destroy; override;
    { The files to make (the most wanted first), each to fit ASize. }
    procedure Request(const AFiles: array of string; ASize: Integer);
    { Everything may be made again (a new folder, files changed). }
    procedure Forget;
    property OnThumb: TFolderThumbEvent read FOnThumb write FOnThumb;
  end;

implementation

uses
  Math,
  uTypes,
  uDecodedImage,
  umedialoader,
  uImageScaling,
  uIOGate;

{ A copy of ABitmap that fits into ASize x ASize. }
function FitThumb(ABitmap: TBGRABitmap; ASize: Integer): TBGRABitmap;
var
  W, H: Integer;
begin
  Result := nil;
  if (ABitmap = nil) or (ASize <= 0) or (ABitmap.Width <= 0) or (ABitmap.Height <= 0) then
    Exit;
  FitSize(ABitmap.Width, ABitmap.Height, ASize, ASize, W, H);
  W := Max(1, Min(W, ABitmap.Width));
  H := Max(1, Min(H, ABitmap.Height));
  if (W = ABitmap.Width) and (H = ABitmap.Height) then
    Result := ABitmap.Duplicate as TBGRABitmap
  else
    Result := ShrinkToSize(ABitmap, W, H);
end;

{ TFolderThumbThread }

constructor TFolderThumbThread.Create(AOwner: TFolderThumbs);
begin
  FOwner := AOwner;
  FLock := TCriticalSection.Create;
  FWake := TEvent.Create(nil, False, False, '');
  FFiles := TStringList.Create;
  FResults := TStringList.Create;
  inherited Create(False);
end;

destructor TFolderThumbThread.Destroy;
var
  I: Integer;
begin
  for I := 0 to FResults.Count - 1 do
    FResults.Objects[I].Free;
  FResults.Free;
  FFiles.Free;
  FWake.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TFolderThumbThread.Request(AFiles: TStrings; ASize: Integer);
begin
  FLock.Acquire;
  try
    FFiles.Assign(AFiles);
    FSize := ASize;
    Inc(FGeneration);
  finally
    FLock.Release;
  end;
  FWake.SetEvent;
end;

procedure TFolderThumbThread.Detach;
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

function TFolderThumbThread.WorkCancelled: Boolean;
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

procedure TFolderThumbThread.Execute;
var
  Loader: TMediaLoader;
  Files: TStringList;
  Size, I: Integer;
  Img: IDecodedImage;
  Thumb: TBGRABitmap;
  Name: string;
begin
  Loader := TMediaLoader.Create;
  Files := TStringList.Create;
  try
    Loader.AutoRotate := True;
    Loader.ThreadStart;
    try
      while not Terminated do
      begin
        FWake.WaitFor(1000);
        if Terminated then
          Break;
        FLock.Acquire;
        try
          Files.Assign(FFiles);
          FFiles.Clear;              { taken: not again unless asked }
          Size := FSize;
          FWorkGeneration := FGeneration;
        finally
          FLock.Release;
        end;
        for I := 0 to Files.Count - 1 do
        begin
          if WorkCancelled then
            Break;
          Name := Files[I];
          IOGate.YieldToDisplay(@WorkCancelled);
          if WorkCancelled then
            Break;
          Thumb := nil;
          try
            { The embedded thumbnail of a JPEG, else a small decode. }
            Img := Loader.Load(Name, qlPreview, @WorkCancelled);
            if (Img = nil) or Img.IsError or (Img.Bitmap = nil)
              or (Max(Img.Width, Img.Height) < Size div 2) then
              Img := Loader.Load(Name, qlScreen, @WorkCancelled, Size * 2, Size * 2);
            if (Img <> nil) and not Img.IsError and (Img.Bitmap <> nil) then
              Thumb := FitThumb(Img.Bitmap, Size);
          except
            FreeAndNil(Thumb);
          end;
          Img := nil;
          if WorkCancelled then
          begin
            Thumb.Free;
            Break;
          end;
          FLock.Acquire;
          try
            FResults.AddObject(Name, Thumb);
          finally
            FLock.Release;
          end;
          if not Terminated then
            Queue(@Deliver);
        end;
      end;
    finally
      Loader.ThreadEnd;
    end;
  finally
    Files.Free;
    Loader.Free;
  end;
end;

{ UI thread. }
procedure TFolderThumbThread.Deliver;
var
  Taken: TStringList;
  Owner: TFolderThumbs;
  I: Integer;
begin
  Taken := TStringList.Create;
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
        Owner.Take(Taken[I], TBGRABitmap(Taken.Objects[I]))
      else
        Taken.Objects[I].Free;
  finally
    Taken.Free;
  end;
end;

{ TFolderThumbs }

constructor TFolderThumbs.Create;
begin
  inherited Create;
  FDone := TStringList.Create;
  FDone.Sorted := True;
  FDone.CaseSensitive := False;
  FDone.Duplicates := dupIgnore;
end;

destructor TFolderThumbs.Destroy;
var
  I: Integer;
begin
  if Assigned(FThread) then
  begin
    FThread.Detach;
    { A read that hangs (a slow drive): the thread is left alone, it
      delivers nothing (as uContainerThumbs). }
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
  FDone.Free;
  inherited Destroy;
end;

procedure TFolderThumbs.Request(const AFiles: array of string; ASize: Integer);
var
  List: TStringList;
  I: Integer;
begin
  if ASize <> FSize then
  begin
    FDone.Clear;
    FSize := ASize;
  end;
  List := TStringList.Create;
  try
    { The strip asks only for what it hasn't (it may have dropped some it
      had: they are made again). The same list again would only restart
      the work. }
    for I := 0 to High(AFiles) do
      List.Add(AFiles[I]);
    if (List.Count = 0) or (List.Text = FLastRequest) then
      Exit;
    FLastRequest := List.Text;
    if FThread = nil then
      FThread := TFolderThumbThread.Create(Self);
    FThread.Request(List, ASize);
  finally
    List.Free;
  end;
end;

procedure TFolderThumbs.Forget;
begin
  FDone.Clear;
  FLastRequest := '';
end;

procedure TFolderThumbs.Take(const AFileName: string; ABitmap: TBGRABitmap);
begin
  FDone.Add(AFileName);
  if Assigned(FOnThumb) then
    FOnThumb(AFileName, ABitmap)
  else
    ABitmap.Free;
end;

end.
