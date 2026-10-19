unit uZipContainer;

{
  Unit: uZipContainer

  Purpose
  -------
  ZIP and CBZ archives as containers (1.1, testers): the images inside
  are browsed like the images of a Leica .lif in the Lab edition - listed
  in the side panel with their thumbnails, walked through with the
  wheel, opened by a click - without unpacking anything to the disk.

  A container reader for uContainers, registered in the initialization
  section for .zip and .cbz (both editions).

  Owns
  ----
  Nothing between calls (each call opens the archive, reads what it
  needs and closes it again: re-entrant for the scanner and the decode
  workers).

  Knows
  -----
  - FPC's zipper unit (TUnZipper: the archive's directory, one entry
    unpacked into memory).
  - Which entries are pictures (by extension: what BGRABitmap reads).

  Responsibilities
  ----------------
  - The list: the pictures in the archive, in natural name order (a
    comic's pages: page2 before page10), sub-folders included; their ids
    are their paths in the archive with "/" as "~" (an id has no "/",
    "\", ":" or "|"); names as stored (UTF-8).
  - The decode: one entry unpacked into memory and decoded (BGRABitmap
    finds the format), returned as RGBA.
  - ArchivesEnabled ([Navigation] Archives, TMView): off = no archive is
    read (it is then passed over like any other file).

  Does NOT
  --------
  - Write archives, or read RAR / 7z (RAR: planned for the Lab edition).
  - Keep anything (uContainerThumbs and the cache do).

  Threads
  -------
  Any thread; no state.

  Uses (MView units)
  ------------------
  implementation: uContainers, uNaturalSort, uTypes
  Libraries:      Classes, SysUtils, zipper, BGRABitmap, BGRABitmapTypes

  Used by
  -------
  uMView (linked in, so its initialization registers it), TestExtensions
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  uTypes,
  uContainers;

var
  { [Navigation] Archives (default on): set by TMView before the scanner
    starts. }
  ArchivesEnabled: Boolean = True;

{ The reader's two functions (public for the tests). }
function ListZip(const AFile: string; out AEntries: TContainerEntryArray): Boolean;
function DecodeZipEntry(const AFile, AId: string; ACancel: TCancelCheck;
  out AWidth, AHeight: Integer; out ARGBA: TBytes; out AError: string): Boolean;
{ A picture's extension (what BGRABitmap reads from memory). }
function IsZipPictureName(const AName: string): Boolean;

implementation

uses
  zipper,
  BGRABitmap,
  BGRABitmapTypes,
  uNaturalSort;

type
  { Catches one unpacked entry in memory. }
  TZipGrab = class
  public
    Data: TMemoryStream;
    procedure CreateStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
    procedure DoneStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
  end;

procedure TZipGrab.CreateStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
begin
  AStream := TMemoryStream.Create;
end;

procedure TZipGrab.DoneStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
begin
  Data.Free;
  Data := TMemoryStream(AStream);
  AStream := nil;
end;

function IsZipPictureName(const AName: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(AName));
  Result := (Ext = '.jpg') or (Ext = '.jpeg') or (Ext = '.jpe') or (Ext = '.jfif')
    or (Ext = '.png') or (Ext = '.gif') or (Ext = '.bmp') or (Ext = '.tif') or (Ext = '.tiff')
    or (Ext = '.tga') or (Ext = '.pcx');
end;

{ An entry's path as an id: no "/", "\", ":" or "|" (uContainers' rule). }
function IdOf(const APath: string): string;
var
  I: Integer;
begin
  Result := APath;
  for I := 1 to Length(Result) do
    case Result[I] of
      '/', '\': Result[I] := '~';
      ':', '|': Result[I] := '_';
    end;
end;

function DisplayPath(AEntry: TFullZipFileEntry): string;
begin
  Result := AEntry.UTF8ArchiveFileName;
  if Result = '' then
    Result := AEntry.ArchiveFileName;
end;

function CompareByName(List: TStringList; Index1, Index2: Integer): Integer;
begin
  Result := NaturalCompareText(List[Index1], List[Index2]);
end;

function ListZip(const AFile: string; out AEntries: TContainerEntryArray): Boolean;
var
  Z: TUnZipper;
  Names: TStringList;
  I: Integer;
  E: TFullZipFileEntry;
  Path: string;
begin
  AEntries := nil;
  Result := False;
  if not ArchivesEnabled then
    Exit;
  Z := TUnZipper.Create;
  Names := TStringList.Create;
  try
    try
      Z.FileName := AFile;
      Z.Examine;
      for I := 0 to Z.Entries.Count - 1 do
      begin
        E := Z.Entries.FullEntries[I];
        if E.IsDirectory then
          Continue;
        Path := DisplayPath(E);
        { Mac's resource forks and hidden files are no pages. }
        if (Pos('__MACOSX/', Path) = 1) or (Copy(ExtractFileName(StringReplace(Path, '/', '\',
          [rfReplaceAll])), 1, 1) = '.') then
          Continue;
        if IsZipPictureName(Path) then
          Names.Add(Path);
      end;
      Names.CustomSort(@CompareByName);
      SetLength(AEntries, Names.Count);
      for I := 0 to Names.Count - 1 do
      begin
        AEntries[I].Id := IdOf(Names[I]);
        AEntries[I].Name := Names[I];
        AEntries[I].Frames := 0;
        AEntries[I].Time := -1;
      end;
      Result := True;
    except
      AEntries := nil;
      Result := False;
    end;
  finally
    Names.Free;
    Z.Free;
  end;
end;

function DecodeZipEntry(const AFile, AId: string; ACancel: TCancelCheck;
  out AWidth, AHeight: Integer; out ARGBA: TBytes; out AError: string): Boolean;
var
  Z: TUnZipper;
  Grab: TZipGrab;
  I, X, Y: Integer;
  Raw: string;
  Bmp: TBGRABitmap;
  P: PBGRAPixel;
  Q: Integer;
begin
  Result := False;
  AWidth := 0;
  AHeight := 0;
  ARGBA := nil;
  AError := '';
  Raw := '';
  Z := TUnZipper.Create;
  Grab := TZipGrab.Create;
  Bmp := nil;
  try
    try
      Z.FileName := AFile;
      Z.Examine;
      for I := 0 to Z.Entries.Count - 1 do
        if not Z.Entries.FullEntries[I].IsDirectory
          and (IdOf(DisplayPath(Z.Entries.FullEntries[I])) = AId) then
        begin
          Raw := Z.Entries.FullEntries[I].ArchiveFileName;
          Break;
        end;
      if Raw = '' then
      begin
        AError := 'not in the archive any more';
        Exit;
      end;
      if Assigned(ACancel) and ACancel() then
      begin
        AError := 'Cancelled';
        Exit;
      end;
      Z.OnCreateStream := @Grab.CreateStream;
      Z.OnDoneStream := @Grab.DoneStream;
      Z.UnZipFile(Raw);
      if (Grab.Data = nil) or (Grab.Data.Size = 0) then
      begin
        AError := 'could not be unpacked';
        Exit;
      end;
      if Assigned(ACancel) and ACancel() then
      begin
        AError := 'Cancelled';
        Exit;
      end;
      Grab.Data.Position := 0;
      Bmp := TBGRABitmap.Create;
      Bmp.LoadFromStream(Grab.Data);
      if (Bmp.Width <= 0) or (Bmp.Height <= 0) then
      begin
        AError := 'no picture in it';
        Exit;
      end;
      AWidth := Bmp.Width;
      AHeight := Bmp.Height;
      SetLength(ARGBA, Int64(AWidth) * AHeight * 4);
      Q := 0;
      for Y := 0 to AHeight - 1 do
      begin
        P := Bmp.ScanLine[Y];
        for X := 0 to AWidth - 1 do
        begin
          ARGBA[Q] := P^.red;
          ARGBA[Q + 1] := P^.green;
          ARGBA[Q + 2] := P^.blue;
          ARGBA[Q + 3] := P^.alpha;
          Inc(Q, 4);
          Inc(P);
        end;
      end;
      Result := True;
    except
      on E: Exception do
      begin
        ARGBA := nil;
        AError := E.Message;
        Result := False;
      end;
    end;
  finally
    Bmp.Free;
    Grab.Data.Free;
    Grab.Free;
    Z.Free;
  end;
end;

initialization
  RegisterContainerReader('ZIP archive', '.zip', @ListZip, @DecodeZipEntry);
  RegisterContainerReader('Comic book (ZIP)', '.cbz', @ListZip, @DecodeZipEntry);
end.
