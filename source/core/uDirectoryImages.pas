unit uDirectoryImages;

{
  Unit: uDirectoryImages

  Purpose
  -------
  The list of image files in one directory, in the current sort order.

  Owns
  ----
  - Its list of entries, FEntries (plain records, no objects).

  Knows
  -----
  - uImageFormats (IsSupportedImageFile) to tell image files apart.
  - uNaturalSort for comparing file names.

  Responsibilities
  ----------------
  - Scan one directory (not recursively) for supported image files
    (uImageFormats).
  - Be filled from outside instead (BeginFill, AddEntry, EndFill):
    the tree scan collects every folder's images this way.
  - Copy another list (Assign), sorted in this list's own mode.
  - Keep them in the current TSortMode order. File names compare
    naturally (Image2 < Image10); equal dates are ordered by name, so
    the order is always the same. Setting SortMode re-sorts at once.
  - Look up entries by index and by file name.

  Does NOT
  --------
  - Recurse into subdirectories. That is TDirectoryTree's job.
  - Decode or load image content.

  Threads
  -------
  No lock: one thread at a time uses a list. The scanner thread fills
  lists (TDirectoryTree.Build, TScanStart.Listing) and hands them to
  the UI thread, where TNavigator uses them. With ReadsDisk = True
  the UI thread also scans folders itself.

  Uses (MView units)
  ------------------
  interface:      uTypes, uImageFormats, uNaturalSort
  Libraries:      Classes, SysUtils, DateUtils

  Used by
  -------
  uDirectoryScanner, uDirectoryTree, uNavigator
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  DateUtils,
  uTypes,
  uImageFormats,
  uNaturalSort;

type

  TImageEntry = record
    FileName: string;     { full path }
    Size: Int64;
    Modified: TDateTime;
  end;

  TDirectoryImages = class(TObject)
  private
    FDirectory: string;
    FEntries: array of TImageEntry;
    FCount: Integer;
    FSortMode: TSortMode;
    FSortedSeed: LongWord;       { RandomSortSeed of the last Sort (Day 27) }
    FVideoCount: Integer;        { videos in the folder (not listed; Day 24) }
    FContainers: array of string; { container files (.lif) in the folder (M2c) }

    procedure SetSortMode(AMode: TSortMode);
    function CompareEntries(const A, B: TImageEntry): Integer;
    procedure QuickSort(ALo, AHi: Integer);
    procedure Sort;
    function RandomKey(const AFileName: string): LongWord;
    procedure SortContainers;
    function SortIsStale: Boolean;
  public
    constructor Create;

    procedure Scan(const ADirectory: string);
    { Sorted again (the shuffled order changed, Day 27). }
    procedure Resort;
    procedure Clear;

    { Filling from outside (the tree scan collects the images of every
      folder while it lists the folders): BeginFill, AddEntry for each
      image, EndFill sorts. }
    procedure BeginFill(const ADirectory: string);
    procedure AddEntry(const AFileName: string; ASize: Int64; AModified: TDateTime);
    procedure EndFill;
    { A video was found while filling (counted, not listed). }
    procedure AddVideo;
    { A container file (.lif, an edition's reader; M2c) in the folder:
      not an image, listed apart for the side panel. Kept in natural
      name order. }
    procedure AddContainer(const AFileName: string);
    { A container's images, listed with the folder's own (user, Day 25:
      a .lif is a one-time folder, not a folder of the tree). }
    procedure AddContainerEntries(const AFile: string);
    { The first of container AFile's images in the list's order; -1 if
      none is listed. }
    function FirstOfContainer(const AFile: string): Integer;
    function ContainerCount: Integer;
    function Container(AIndex: Integer): string;

    { A copy of ASource (directory and entries), sorted in this list's
      own sort mode. }
    procedure Assign(ASource: TDirectoryImages);

    function Count: Integer;
    function FileName(AIndex: Integer): string;
    function FileSize(AIndex: Integer): Int64;
    function DateModified(AIndex: Integer): TDateTime;
    function IndexOfFile(const AFileName: string): Integer;

    { Sorting into folders (Phase G): a file moved away or back, or
      copied in. Delete removes entry AIndex; AddFile adds one and
      keeps the list sorted (nothing if it is already listed). }
    procedure Delete(AIndex: Integer);
    procedure AddFile(const AFileName: string; ASize: Int64; AModified: TDateTime);

    property Directory: string read FDirectory;
    { Videos in the folder (IsVideoFile): only counted. }
    property VideoCount: Integer read FVideoCount;
    { Setting the sort mode re-sorts the list at once. }
    property SortMode: TSortMode read FSortMode write SetSortMode;
  end;

var
  { The shuffled order's seed (smRandom); new at each start and with
    NewRandomSortOrder. Read by any thread, written on the UI thread. }
  RandomSortSeed: LongWord = 0;

{ A new shuffled order (choosing "Random" again). }
procedure NewRandomSortOrder;

implementation

uses
  uContainers;

{ TDirectoryImages }

constructor TDirectoryImages.Create;
begin
  inherited Create;
  FSortMode := smDateDescending;
  FCount := 0;
end;

procedure TDirectoryImages.Clear;
begin
  FDirectory := '';
  FEntries := nil;
  FCount := 0;
  FVideoCount := 0;
  FContainers := nil;
end;

procedure TDirectoryImages.AddContainer(const AFileName: string);
begin
  SetLength(FContainers, Length(FContainers) + 1);
  FContainers[High(FContainers)] := AFileName;
end;

{ A container's images (virtual names) as images of this folder, with
  the container file's size and time (an entry's key changes with the
  file). Reads the file's description (the scanner thread, or a test). }
procedure TDirectoryImages.AddContainerEntries(const AFile: string);
var
  Names: TStringArray;
  Size: Int64;
  Time: TDateTime;
  I: Integer;
begin
  if ListContainer(AFile, Names, Size, Time) then
    for I := 0 to High(Names) do
      AddEntry(Names[I], Size, Time);
end;

function TDirectoryImages.FirstOfContainer(const AFile: string): Integer;
var
  Prefix: string;
  I: Integer;
begin
  Prefix := AFile + ContainerSeparator;
  for I := 0 to FCount - 1 do
    if SameText(Copy(FEntries[I].FileName, 1, Length(Prefix)), Prefix) then
      Exit(I);
  Result := -1;
end;

function TDirectoryImages.ContainerCount: Integer;
begin
  Result := Length(FContainers);
end;

function TDirectoryImages.Container(AIndex: Integer): string;
begin
  Result := FContainers[AIndex];
end;

{ Natural order (Day2 before Day10), case ignored; a few entries. }
procedure TDirectoryImages.SortContainers;
var
  I, J: Integer;
  Item: string;
begin
  for I := 1 to High(FContainers) do
  begin
    Item := FContainers[I];
    J := I - 1;
    while (J >= 0) and (NaturalCompareText(FContainers[J], Item) > 0) do
    begin
      FContainers[J + 1] := FContainers[J];
      Dec(J);
    end;
    FContainers[J + 1] := Item;
  end;
end;

procedure TDirectoryImages.Scan(const ADirectory: string);
var
  SearchRec: TSearchRec;
  Prefix: string;
begin
  Clear;
  FDirectory := ExcludeTrailingPathDelimiter(ADirectory);
  if FDirectory = '' then
    Exit;

  Prefix := IncludeTrailingPathDelimiter(FDirectory);
  if FindFirst(Prefix + '*', faAnyFile, SearchRec) = 0 then
  begin
    try
      repeat
        if ((SearchRec.Attr and faDirectory) = 0)
          and IsSupportedImageFile(SearchRec.Name) then
        begin
          { Grow in steps, not by one, so large folders stay fast. }
          if FCount = Length(FEntries) then
            SetLength(FEntries, 16 + 2 * Length(FEntries));

          FEntries[FCount].FileName := Prefix + SearchRec.Name;
          FEntries[FCount].Size := SearchRec.Size;
          FEntries[FCount].Modified := FileDateToDateTime(SearchRec.Time);
          Inc(FCount);
        end
        else if ((SearchRec.Attr and faDirectory) = 0) and IsVideoFile(SearchRec.Name) then
          Inc(FVideoCount)
        else if ((SearchRec.Attr and faDirectory) = 0) and IsContainerName(SearchRec.Name) then
        begin
          { A container (never in MView: no reader; user, Day 25): a
            one-time folder - its images with the folder's own, at its
            place; and in the container list (the side panel). }
          AddContainer(Prefix + SearchRec.Name);
          AddContainerEntries(Prefix + SearchRec.Name);
        end;
      until FindNext(SearchRec) <> 0;
    finally
      FindClose(SearchRec);
    end;
  end;

  Sort;
  SortContainers;
end;

procedure TDirectoryImages.BeginFill(const ADirectory: string);
begin
  Clear;
  FDirectory := ExcludeTrailingPathDelimiter(ADirectory);
end;

procedure TDirectoryImages.AddEntry(const AFileName: string; ASize: Int64;
  AModified: TDateTime);
begin
  if FCount = Length(FEntries) then
    SetLength(FEntries, 16 + 2 * Length(FEntries));
  FEntries[FCount].FileName := AFileName;
  FEntries[FCount].Size := ASize;
  FEntries[FCount].Modified := AModified;
  Inc(FCount);
end;

procedure TDirectoryImages.EndFill;
begin
  Sort;
  SortContainers;
end;

procedure TDirectoryImages.AddVideo;
begin
  Inc(FVideoCount);
end;

procedure TDirectoryImages.Assign(ASource: TDirectoryImages);
var
  I: Integer;
begin
  Clear;
  if ASource = nil then
    Exit;
  FDirectory := ASource.FDirectory;
  SetLength(FEntries, ASource.FCount);
  for I := 0 to ASource.FCount - 1 do
    FEntries[I] := ASource.FEntries[I];
  FCount := ASource.FCount;
  FVideoCount := ASource.FVideoCount;
  FContainers := Copy(ASource.FContainers, 0, Length(ASource.FContainers));
  FSortedSeed := ASource.FSortedSeed;
  if (ASource.FSortMode <> FSortMode) or SortIsStale then
    Sort;
end;

{ A shuffled list whose shuffle is older than the current seed. }
function TDirectoryImages.SortIsStale: Boolean;
begin
  Result := (FSortMode = smRandom) and (FSortedSeed <> RandomSortSeed);
end;

procedure TDirectoryImages.SetSortMode(AMode: TSortMode);
begin
  if (AMode = FSortMode) and not SortIsStale then
    Exit;
  FSortMode := AMode;
  Sort;
end;

procedure NewRandomSortOrder;
begin
  RandomSortSeed := LongWord(Random($7FFFFFFF)) xor LongWord(GetTickCount64);
end;

{$PUSH}{$Q-}{$R-}
{ A shuffled order (smRandom, Day 27): each name's hash with the seed
  (FNV-1a); the same order for every list until the seed changes. }
function TDirectoryImages.RandomKey(const AFileName: string): LongWord;
var
  I: Integer;
  Name: string;
begin
  Name := LowerCase(AFileName);
  Result := 2166136261 xor RandomSortSeed;
  for I := 1 to Length(Name) do
    Result := (Result xor Ord(Name[I])) * 16777619;
end;
{$POP}

function TDirectoryImages.CompareEntries(const A, B: TImageEntry): Integer;
var
  KA, KB: LongWord;
begin
  case FSortMode of
    smRandom:
      begin
        KA := RandomKey(A.FileName);
        KB := RandomKey(B.FileName);
        if KA < KB then
          Result := -1
        else if KA > KB then
          Result := 1
        else
          Result := NaturalCompareText(A.FileName, B.FileName);
      end;
    smFileNameAscending:
      Result := NaturalCompareText(A.FileName, B.FileName);
    smFileNameDescending:
      Result := NaturalCompareText(B.FileName, A.FileName);
    smDateAscending:
      begin
        Result := CompareDateTime(A.Modified, B.Modified);
        if Result = 0 then
          Result := NaturalCompareText(A.FileName, B.FileName);
      end;
  else
    { smDateDescending, the default: newest first. }
    begin
      Result := CompareDateTime(B.Modified, A.Modified);
      if Result = 0 then
        Result := NaturalCompareText(A.FileName, B.FileName);
    end;
  end;
end;

{ Classic Hoare quicksort. The pivot is copied, so swapping entries
  can't move it. The comparison is a total order (ties are broken by
  name), so the result doesn't depend on the input order. }
procedure TDirectoryImages.QuickSort(ALo, AHi: Integer);
var
  I, J: Integer;
  Pivot, Tmp: TImageEntry;
begin
  I := ALo;
  J := AHi;
  Pivot := FEntries[(ALo + AHi) div 2];
  repeat
    while CompareEntries(FEntries[I], Pivot) < 0 do
      Inc(I);
    while CompareEntries(FEntries[J], Pivot) > 0 do
      Dec(J);
    if I <= J then
    begin
      Tmp := FEntries[I];
      FEntries[I] := FEntries[J];
      FEntries[J] := Tmp;
      Inc(I);
      Dec(J);
    end;
  until I > J;

  if ALo < J then
    QuickSort(ALo, J);
  if I < AHi then
    QuickSort(I, AHi);
end;

procedure TDirectoryImages.Resort;
begin
  Sort;
end;

procedure TDirectoryImages.Sort;
begin
  FSortedSeed := RandomSortSeed;
  if FCount > 1 then
    QuickSort(0, FCount - 1);
end;

function TDirectoryImages.Count: Integer;
begin
  Result := FCount;
end;

function TDirectoryImages.FileName(AIndex: Integer): string;
begin
  Result := FEntries[AIndex].FileName;
end;

function TDirectoryImages.FileSize(AIndex: Integer): Int64;
begin
  Result := FEntries[AIndex].Size;
end;

function TDirectoryImages.DateModified(AIndex: Integer): TDateTime;
begin
  Result := FEntries[AIndex].Modified;
end;

function TDirectoryImages.IndexOfFile(const AFileName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FCount - 1 do
    if SameText(FEntries[I].FileName, AFileName) then
      Exit(I);
  Result := -1;
end;

procedure TDirectoryImages.Delete(AIndex: Integer);
var
  I: Integer;
begin
  if (AIndex < 0) or (AIndex >= FCount) then
    Exit;
  for I := AIndex to FCount - 2 do
    FEntries[I] := FEntries[I + 1];
  Dec(FCount);
  FEntries[FCount].FileName := '';
end;

procedure TDirectoryImages.AddFile(const AFileName: string; ASize: Int64;
  AModified: TDateTime);
begin
  if IndexOfFile(AFileName) >= 0 then
    Exit;
  AddEntry(AFileName, ASize, AModified);
  Sort;
end;

initialization
  Randomize;
  NewRandomSortOrder;
end.
