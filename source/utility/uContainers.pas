unit uContainers;

{
  Unit: uContainers

  Purpose
  -------
  Containers (M2b, Day 25): files that hold several images, such as a
  Leica .lif, are browsed as one-time folders. The microscopy edition
  registers a reader per kind (a container is a one-time folder, see
  Names); the core asks this unit, and only this
  unit, whether a name is a container or an image inside one. With no
  reader registered (MView) every answer is "no" and every code path is
  the old one.

  Names
  -----
  An image inside a container has a "virtual" name: the container's
  full path, '|', the entry's id:

      C:\data\sample.lif|Series009
      C:\data\sample.lif|Folder|Series009      (nested in the file)

  '|' can't occur in a Windows path, so a name with it is always
  virtual, and any code that misses it fails safe (FindFirst and
  FileExists find nothing). Ids never contain '\', '/' or ':' (the
  readers replace them), so ExtractFileDir of a virtual name is still
  the real folder the container lies in.

  A container is a one-time folder (user, Day 25): not a folder of the
  tree (the folder gestures pass it like a file); its images are listed
  with its folder's own images, at its place, so the wheel walks into
  it and out again. ItemDirectory of an image inside it is that folder.

  Owns
  ----
  The list of registered readers (records).

  Knows
  -----
  Nothing else.

  Responsibilities
  ----------------
  - RegisterContainerReader (an edition's initialization section): the
    extension ('.lif'), a function that lists the entries, one that
    decodes an entry to RGBA.
  - IsContainerName (by extension), IsVirtualName, MakeVirtualName,
    SplitVirtual, ContainerFileOf, ItemDirectory, ItemExists, RealFolderOf,
    DisplayItemName ('sample.lif › Series009'), ItemBaseName (for the
    names of saved copies: 'sample_Series009').
  - ListContainer: the entries' virtual names, with the container
    file's size and time (an entry's key changes when the file does).
  - DecodeContainerEntry: RGBA pixels of one entry (stacks: the maximum
    projection; a stack's frame by its own id).
  - Stacks (Day 26): RegisterContainerStacks adds to a reader the
    frames of an entry (ListContainerEntries with a virtual name: the
    stack's frames, their ids relative to the container file like any
    entry's) and a note on an entry for the info line
    (ContainerEntryNote: 't 11 × 2.6 s (projection)'). TContainerEntry.
    Frames > 1 marks a stack in a listing.
  A reader that raises counts as "can't read it".

  Does NOT
  --------
  - Read any file format itself.

  Threads
  -------
  Registration before any thread starts (initialization sections).
  Everything else on any thread: the readers must be re-entrant (the
  scanner lists while several workers decode).

  Uses (MView units)
  ------------------
  interface:      uTypes (TCancelCheck)
  Libraries:      SysUtils

  Used by
  -------
  uDirectoryTree, uDirectoryImages, uDirectoryScanner, uNavigator,
  uMediaLoader, uMView, uMainForm, uImageSaver; the edition's readers
}

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils,
  uTypes;

const
  ContainerSeparator = '|';

type
  TContainerEntry = record
    Id: string;          { no '\', '/', ':' or '|' at its ends; unique in the file }
    Name: string;        { shown: 'Series009' }
    Frames: Integer;     { a stack: its frames (> 1); else 0 or 1 (Day 26) }
    Time: Double;        { a stack's frame: seconds since the first; -1 = unknown }
  end;
  TContainerEntryArray = array of TContainerEntry;

  { The entries of AFile, in the file's order; False if it can't be read. }
  TContainerListFunc = function(const AFile: string; out AEntries: TContainerEntryArray): Boolean;
  { One entry as RGBA (R G B A per pixel, rows top down). }
  TContainerDecodeFunc = function(const AFile, AId: string; ACancel: TCancelCheck;
    out AWidth, AHeight: Integer; out ARGBA: TBytes; out AError: string): Boolean;

  { A stack's frames (Day 26): AId is the stack's id; the entries' ids
    are relative to AFile (decoded by the reader's decode function). }
  TContainerFramesFunc = function(const AFile, AId: string;
    out AEntries: TContainerEntryArray): Boolean;
  { A short note on an entry for the info line; '' = none. }
  TContainerNoteFunc = function(const AFile, AId: string): string;

procedure RegisterContainerReader(const AName, AExtension: string;
  AList: TContainerListFunc; ADecode: TContainerDecodeFunc);
{ After RegisterContainerReader for the same extension (Day 26). }
procedure RegisterContainerStacks(const AExtension: string; AFrames: TContainerFramesFunc;
  ANote: TContainerNoteFunc);
function ContainerReaderCount: Integer;

{ A file whose extension a registered reader takes (not a virtual name). }
function IsContainerName(const AFileName: string): Boolean;
{ An image inside a container ('...|...'). }
function IsVirtualName(const AName: string): Boolean;
function MakeVirtualName(const AFile, AId: string): string;
{ False (AFile = AName, AId = '') for an ordinary name. }
function SplitVirtual(const AName: string; out AFile, AId: string): Boolean;
{ The container file of a virtual name; an ordinary name as it is. }
function ContainerFileOf(const AName: string): string;
{ The folder an item is listed in: for an image inside a container,
  the folder the container lies in (its images are listed there, at its
  place); else ExtractFileDir (as the core always did). }
function ItemDirectory(const AName: string): string;
{ FileExists, for a virtual name that of its container. }
function ItemExists(const AName: string): Boolean;
{ The real folder on disk: where the container lies, or the file's. }
function RealFolderOf(const AName: string): string;
{ For the info line: 'sample.lif › Series009', or the file name. }
function DisplayItemName(const AName: string): string;
{ For the names of saved copies: 'sample_Series009', or the file name
  without its extension. }
function ItemBaseName(const AName: string): string;

{ The virtual names of AFile's entries and the container file's size
  and time. False if no reader takes it or it can't be read. }
function ListContainer(const AFile: string; out ANames: TStringArray;
  out ASize: Int64; out ATime: TDateTime): Boolean;
{ The entries themselves (names for a list). AFile a virtual name (a
  stack inside the container): its frames (Day 26). }
function ListContainerEntries(const AFile: string; out AEntries: TContainerEntryArray): Boolean;
{ The reader's note on an image inside a container; '' = none. }
function ContainerEntryNote(const AName: string): string;
function DecodeContainerEntry(const AName: string; ACancel: TCancelCheck;
  out AWidth, AHeight: Integer; out ARGBA: TBytes; out AError: string): Boolean;

implementation

type
  TReaderRecord = record
    Name: string;
    Extension: string;
    List: TContainerListFunc;
    Decode: TContainerDecodeFunc;
    Frames: TContainerFramesFunc;    { nil = no stacks }
    Note: TContainerNoteFunc;        { nil = no notes }
  end;

var
  Readers: array of TReaderRecord;

procedure RegisterContainerReader(const AName, AExtension: string;
  AList: TContainerListFunc; ADecode: TContainerDecodeFunc);
var
  N: Integer;
begin
  if (not Assigned(AList)) or (not Assigned(ADecode)) or (AExtension = '') then
    Exit;
  N := Length(Readers);
  SetLength(Readers, N + 1);
  Readers[N].Name := AName;
  Readers[N].Extension := LowerCase(AExtension);
  Readers[N].List := AList;
  Readers[N].Decode := ADecode;
  Readers[N].Frames := nil;
  Readers[N].Note := nil;
end;

procedure RegisterContainerStacks(const AExtension: string; AFrames: TContainerFramesFunc;
  ANote: TContainerNoteFunc);
var
  I: Integer;
begin
  for I := 0 to High(Readers) do
    if Readers[I].Extension = LowerCase(AExtension) then
    begin
      Readers[I].Frames := AFrames;
      Readers[I].Note := ANote;
    end;
end;

function ContainerReaderCount: Integer;
begin
  Result := Length(Readers);
end;

function ReaderIndexFor(const AFileName: string): Integer;
var
  Ext: string;
  I: Integer;
begin
  Result := -1;
  if Length(Readers) = 0 then
    Exit;
  Ext := LowerCase(ExtractFileExt(AFileName));
  for I := 0 to High(Readers) do
    if Readers[I].Extension = Ext then
      Exit(I);
end;

function IsVirtualName(const AName: string): Boolean;
begin
  Result := Pos(ContainerSeparator, AName) > 0;
end;

function IsContainerName(const AFileName: string): Boolean;
begin
  Result := (Length(Readers) > 0) and (not IsVirtualName(AFileName))
    and (ReaderIndexFor(AFileName) >= 0);
end;

function MakeVirtualName(const AFile, AId: string): string;
begin
  Result := AFile + ContainerSeparator + AId;
end;

function SplitVirtual(const AName: string; out AFile, AId: string): Boolean;
var
  P: Integer;
begin
  P := Pos(ContainerSeparator, AName);
  if P = 0 then
  begin
    AFile := AName;
    AId := '';
    Exit(False);
  end;
  AFile := Copy(AName, 1, P - 1);
  AId := Copy(AName, P + 1, MaxInt);
  Result := True;
end;

function ContainerFileOf(const AName: string): string;
var
  Id: string;
begin
  SplitVirtual(AName, Result, Id);
end;

function ItemDirectory(const AName: string): string;
begin
  { The folder the container lies in (user, Day 25: a .lif is a
    one-time folder; its images are listed with that folder's own). For
    an ordinary name exactly as before (a drive root keeps its slash). }
  Result := ExtractFileDir(ContainerFileOf(AName));
end;

function ItemExists(const AName: string): Boolean;
begin
  Result := FileExists(ContainerFileOf(AName));
end;

function RealFolderOf(const AName: string): string;
begin
  Result := ExtractFileDir(ContainerFileOf(AName));
end;

function DisplayItemName(const AName: string): string;
var
  FileName, Id: string;
begin
  if SplitVirtual(AName, FileName, Id) then
    Result := ExtractFileName(FileName) + ' › '
      + StringReplace(Id, ContainerSeparator, ' › ', [rfReplaceAll])
  else
    Result := ExtractFileName(AName);
end;

function ItemBaseName(const AName: string): string;
var
  FileName, Id: string;
begin
  if SplitVirtual(AName, FileName, Id) then
    Result := ChangeFileExt(ExtractFileName(FileName), '') + '_'
      + StringReplace(Id, ContainerSeparator, '_', [rfReplaceAll])
  else
    Result := ChangeFileExt(ExtractFileName(AName), '');
end;

function ListContainerEntries(const AFile: string; out AEntries: TContainerEntryArray): Boolean;
var
  Index: Integer;
  FileName, Id: string;
begin
  AEntries := nil;
  Result := False;
  { A stack inside the container: its frames. }
  if SplitVirtual(AFile, FileName, Id) then
  begin
    Index := ReaderIndexFor(FileName);
    if (Index < 0) or not Assigned(Readers[Index].Frames) then
      Exit;
    try
      Result := Readers[Index].Frames(FileName, Id, AEntries);
    except
      Result := False;
    end;
    if not Result then
      AEntries := nil;
    Exit;
  end;
  Index := ReaderIndexFor(AFile);
  if Index < 0 then
    Exit;
  try
    Result := Readers[Index].List(AFile, AEntries);
  except
    Result := False;
  end;
  if not Result then
    AEntries := nil;
end;

function ContainerEntryNote(const AName: string): string;
var
  Index: Integer;
  FileName, Id: string;
begin
  Result := '';
  if not SplitVirtual(AName, FileName, Id) then
    Exit;
  Index := ReaderIndexFor(FileName);
  if (Index < 0) or not Assigned(Readers[Index].Note) then
    Exit;
  try
    Result := Readers[Index].Note(FileName, Id);
  except
    Result := '';
  end;
end;

function ListContainer(const AFile: string; out ANames: TStringArray;
  out ASize: Int64; out ATime: TDateTime): Boolean;
var
  Entries: TContainerEntryArray;
  SearchRec: TSearchRec;
  I: Integer;
begin
  ANames := nil;
  ASize := 0;
  ATime := 0;
  Result := False;
  if not IsContainerName(AFile) then
    Exit;
  { The same fields a folder listing takes, so a key made here matches
    the one the worker makes. }
  if FindFirst(AFile, faAnyFile, SearchRec) <> 0 then
    Exit;
  try
    ASize := SearchRec.Size;
    ATime := FileDateToDateTime(SearchRec.Time);
  finally
    FindClose(SearchRec);
  end;
  if not ListContainerEntries(AFile, Entries) then
    Exit;
  SetLength(ANames, Length(Entries));
  for I := 0 to High(Entries) do
    ANames[I] := MakeVirtualName(AFile, Entries[I].Id);
  Result := True;
end;

function DecodeContainerEntry(const AName: string; ACancel: TCancelCheck;
  out AWidth, AHeight: Integer; out ARGBA: TBytes; out AError: string): Boolean;
var
  FileName, Id: string;
  Index: Integer;
begin
  AWidth := 0;
  AHeight := 0;
  ARGBA := nil;
  AError := '';
  Result := False;
  if not SplitVirtual(AName, FileName, Id) then
  begin
    AError := 'not an image inside a container';
    Exit;
  end;
  Index := ReaderIndexFor(FileName);
  if Index < 0 then
  begin
    AError := 'no reader for ' + ExtractFileExt(FileName) + ' files';
    Exit;
  end;
  try
    Result := Readers[Index].Decode(FileName, Id, ACancel, AWidth, AHeight, ARGBA, AError);
  except
    on E: Exception do
    begin
      Result := False;
      AError := E.Message;
    end;
  end;
  if not Result then
  begin
    ARGBA := nil;
    if AError = '' then
      AError := 'could not read ' + DisplayItemName(AName);
  end;
end;

end.
