unit uLifContainer;

{
  Unit: uLifContainer

  Purpose
  -------
  Leica .lif files as containers (M2b, Day 25): registers the .lif
  reader (uLifFile) with the core's containers (uContainers), so a .lif
  is a one-time folder: its images are listed among its folder's. A stack
  (z-planes or time points) shows its maximum projection.

  Stacks (Day 26): a stack's frames are entries too - listed for the side
  panel (left double-click on the stack), each decoded on its own. A
  frame's id is the stack's, '|#t03' (time) or '|#z03' (depth), 1-based;
  LifIndexOfId finds the stack for it (its scale is the stack's). The
  info line's note: 't 11 × 2.6 s (projection)'. The frames' list and
  the notes use one cached TLifFile (the usable frames are read from the
  pixels once).

  Entry ids
  ---------
  The image's path in the file with '/' replaced by '|' (Folder/Series009
  -> Folder|Series009); '\' and ':' (they would split the name for
  ExtractFileDir) and ? * " < > (not allowed in the names of saved
  copies) become '_'. Two images of the same name: the second gets '~2'.

  Owns
  ----
  The cached TLifFile of the frames' lists and the notes (under a lock).
  Listing and decoding open the file on their own (re-entrant: the
  scanner lists while workers decode).

  Threads
  -------
  Any (scanner, decode workers).

  Uses (MView units)
  ------------------
  interface:      uLifFile
  implementation: uTypes, uContainers
  Libraries:      SysUtils, SyncObjs

  Used by
  -------
  VersariteImageLab.lpr (its uses list), uImageScale (LifIndexOfId)
}

{$mode ObjFPC}{$H+}

interface

uses
  uLifFile;

{ The image of ALif whose entry id (the part after '|' in a virtual
  name) is AId; -1 if none. The same ids the container list makes. A
  frame's id: its stack. }
function LifIndexOfId(ALif: TLifFile; const AId: string): Integer;
{ A frame's id ('Series009|#t03'): the stack's id and the frame
  (0-based). False for any other id. }
function LifSplitFrame(const AId: string; out ABaseId: string; out AFrame: Integer): Boolean;

implementation

uses
  SysUtils,
  SyncObjs,
  uTypes,
  uContainers;

var
  CacheLock: TCriticalSection = nil;
  CacheLif: TLifFile = nil;
  CacheName: string = '';
  CacheAge: LongInt = 0;

function IdOfPath(const APath: string): string;
const
  Unsafe: array[0..6] of string = ('\', ':', '?', '*', '"', '<', '>');
var
  I: Integer;
begin
  Result := StringReplace(APath, '/', ContainerSeparator, [rfReplaceAll]);
  for I := 0 to High(Unsafe) do
    Result := StringReplace(Result, Unsafe[I], '_', [rfReplaceAll]);
end;

{ The ids of all images, in the file's order, unique (a second image of
  the same name gets '~2', a third '~3' ...): the list and the decoder
  make them the same way. }
function ImageIds(ALif: TLifFile): TStringArray;
var
  I, J, N: Integer;
  Taken: Boolean;
  Base: string;
begin
  SetLength(Result, ALif.ImageCount);
  for I := 0 to ALif.ImageCount - 1 do
  begin
    Base := IdOfPath(ALif.Images[I].Path);
    Result[I] := Base;
    N := 1;
    repeat
      Taken := False;
      for J := 0 to I - 1 do
        if SameText(Result[J], Result[I]) then
        begin
          Taken := True;
          Break;
        end;
      if Taken then
      begin
        Inc(N);
        Result[I] := Base + '~' + IntToStr(N);
      end;
    until not Taken;
  end;
end;

function LifSplitFrame(const AId: string; out ABaseId: string; out AFrame: Integer): Boolean;
var
  P, I, N: Integer;
  Tail: string;
begin
  Result := False;
  ABaseId := AId;
  AFrame := -1;
  P := Length(AId);
  while (P > 0) and (AId[P] <> ContainerSeparator) do
    Dec(P);
  if P <= 1 then
    Exit;
  Tail := Copy(AId, P + 1, MaxInt);
  { '#t03' / '#z03' }
  if (Length(Tail) < 3) or (Tail[1] <> '#') or not (Tail[2] in ['t', 'z', 'T', 'Z']) then
    Exit;
  N := 0;
  for I := 3 to Length(Tail) do
  begin
    if not (Tail[I] in ['0'..'9']) or (N > 100000) then
      Exit;
    N := N * 10 + Ord(Tail[I]) - Ord('0');
  end;
  if N < 1 then
    Exit;
  ABaseId := Copy(AId, 1, P - 1);
  AFrame := N - 1;
  Result := True;
end;

function IndexOfExactId(ALif: TLifFile; const AId: string): Integer;
var
  Ids: TStringArray;
  I: Integer;
begin
  Ids := ImageIds(ALif);
  for I := 0 to High(Ids) do
    if SameText(Ids[I], AId) then
      Exit(I);
  Result := -1;
end;

{ The image whose id is AId; a frame's id: its stack; -1 if none. }
function LifIndexOfId(ALif: TLifFile; const AId: string): Integer;
var
  BaseId: string;
  Frame: Integer;
begin
  Result := IndexOfExactId(ALif, AId);
  if (Result < 0) and LifSplitFrame(AId, BaseId, Frame) then
    Result := IndexOfExactId(ALif, BaseId);
end;

{ The cached file (CacheLock held): opened again when the file changed. }
function CachedLifLocked(const AFile: string): TLifFile;
var
  Age: LongInt;
begin
  Result := nil;
  Age := FileAge(AFile);
  if Age = -1 then
    Exit;
  if (CacheLif <> nil) and SameText(CacheName, AFile) and (CacheAge = Age) then
    Exit(CacheLif);
  FreeAndNil(CacheLif);
  CacheName := '';
  CacheLif := TLifFile.Create;
  if not CacheLif.Open(AFile) then
  begin
    FreeAndNil(CacheLif);
    Exit;
  end;
  CacheName := AFile;
  CacheAge := Age;
  Result := CacheLif;
end;

{ '7.8' (seconds) / '1.50' (µm): with a point, as the panel shows numbers. }
function NumberText(AValue: Double; ADigits: Integer): string;
var
  Fmt: TFormatSettings;
begin
  Fmt := DefaultFormatSettings;
  Fmt.DecimalSeparator := '.';
  Result := FloatToStrF(AValue, ffFixed, 15, ADigits, Fmt);
end;

function ListLif(const AFile: string; out AEntries: TContainerEntryArray): Boolean;
var
  Lif: TLifFile;
  Ids: TStringArray;
  I: Integer;
begin
  AEntries := nil;
  Lif := TLifFile.Create;
  try
    Result := Lif.Open(AFile);
    if not Result then
      Exit;
    Ids := ImageIds(Lif);
    SetLength(AEntries, Lif.ImageCount);
    for I := 0 to Lif.ImageCount - 1 do
    begin
      AEntries[I].Id := Ids[I];
      AEntries[I].Name := Lif.Images[I].Path;
      { A stack (the side panel marks it; Day 26). }
      if Lif.Images[I].FrameCount > 1 then
        AEntries[I].Frames := Lif.Images[I].FrameCount
      else
        AEntries[I].Frames := 0;
      AEntries[I].Time := -1;
    end;
  finally
    Lif.Free;
  end;
end;

{ A stack's usable frames (Day 26): ids '<stack>|#t03', names
  't 3    5.2 s' / 'z 3    1.00 µm'. }
function FramesLif(const AFile, AId: string; out AEntries: TContainerEntryArray): Boolean;
var
  Lif: TLifFile;
  Img: TLifImage;
  Index, Count, F: Integer;
  Letter: Char;
  Name: string;
begin
  AEntries := nil;
  Result := False;
  CacheLock.Enter;
  try
    Lif := CachedLifLocked(AFile);
    if Lif = nil then
      Exit;
    Index := IndexOfExactId(Lif, AId);
    if Index < 0 then
      Exit;
    Img := Lif.Images[Index];
    if Img.FrameCount <= 1 then
      Exit;
    Count := Lif.UsableFrameCount(Index);
    Img := Lif.Images[Index];
    if Img.StackKind = lsDepth then
      Letter := 'z'
    else
      Letter := 't';
    SetLength(AEntries, Count);
    for F := 0 to Count - 1 do
    begin
      AEntries[F].Id := AId + ContainerSeparator + '#' + Letter + Format('%.2d', [F + 1]);
      Name := Letter + ' ' + IntToStr(F + 1);
      if (Letter = 't') and (Length(Img.FrameTimes) > F) then
        Name := Name + '    ' + NumberText(Img.FrameTimes[F], 1) + ' s'
      else if (Letter = 'z') and (Img.ZStep > 0) then
        Name := Name + '    ' + NumberText(F * Img.ZStep, 2) + ' µm';
      AEntries[F].Name := Name;
      AEntries[F].Frames := 0;
      { Its time, for playing at the stack's pace (Day 26). }
      if (Letter = 't') and (Length(Img.FrameTimes) > F) then
        AEntries[F].Time := Img.FrameTimes[F]
      else
        AEntries[F].Time := -1;
    end;
    Result := True;
  finally
    CacheLock.Leave;
  end;
end;

{ The info line's note (Day 26): a stack 't 11 × 2.6 s (projection)'. }
function NoteLif(const AFile, AId: string): string;
var
  Lif: TLifFile;
  Index: Integer;
begin
  Result := '';
  { The UI thread asks: never wait for the frames' list reading planes
    (the note comes with the next look). }
  if not CacheLock.TryEnter then
    Exit;
  try
    Lif := CachedLifLocked(AFile);
    if Lif = nil then
      Exit;
    Index := IndexOfExactId(Lif, AId);
    if (Index < 0) or (Lif.Images[Index].FrameCount <= 1) then
      Exit;
    Result := StackSummary(Lif.Images[Index], Lif.UsableFrameCount(Index));
    if Result <> '' then
      Result := Result + ' (projection)';
  finally
    CacheLock.Leave;
  end;
end;

function DecodeLif(const AFile, AId: string; ACancel: TCancelCheck;
  out AWidth, AHeight: Integer; out ARGBA: TBytes; out AError: string): Boolean;
var
  Lif: TLifFile;
  Index, Frame: Integer;
  BaseId: string;
begin
  AWidth := 0;
  AHeight := 0;
  ARGBA := nil;
  AError := '';
  Result := False;
  Lif := TLifFile.Create;
  try
    if not Lif.Open(AFile) then
    begin
      AError := ExtractFileName(AFile) + ': ' + Lif.ErrorText;
      Exit;
    end;
    Index := IndexOfExactId(Lif, AId);
    { A stack's frame (Day 26). }
    if (Index < 0) and LifSplitFrame(AId, BaseId, Frame) then
    begin
      Index := IndexOfExactId(Lif, BaseId);
      if Index >= 0 then
      begin
        Result := Lif.RenderFrameRGBA(Index, Frame, AWidth, AHeight, ARGBA, ACancel);
        if not Result then
          AError := Lif.ErrorText;
        Exit;
      end;
    end;
    if Index < 0 then
    begin
      AError := AId + ' is not in ' + ExtractFileName(AFile) + ' (any more)';
      Exit;
    end;
    { A stack: its maximum projection (spec, microscopy edition §6.5). }
    Result := Lif.RenderRGBA(Index, -1, 0, AWidth, AHeight, ARGBA, ACancel);
    if not Result then
      AError := Lif.ErrorText;
  finally
    Lif.Free;
  end;
end;

initialization
  CacheLock := TCriticalSection.Create;
  RegisterContainerReader('Leica LIF', '.lif', @ListLif, @DecodeLif);
  RegisterContainerStacks('.lif', @FramesLif, @NoteLif);

finalization
  FreeAndNil(CacheLif);
  FreeAndNil(CacheLock);
end.
