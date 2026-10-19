program TestNavigation;

{
  Standalone console test for the navigation units: uNaturalSort,
  uImageFormats, uDirectoryTree, uDirectoryImages and uNavigator.

  It builds its own throwaway folder tree with known contents, checks
  the navigation rules against it, and reports PASS / FAIL per check.
  No GUI, no Lazarus project needed. From the test\ folder:

    fpc -FU. -Fu..\source\core -Fu..\source\imaging -Fu..\source\utility TestNavigation.lpr
    TestNavigation.exe

  The exit code is 1 if any check fails. The temporary folder is
  deleted at the end, whether the checks pass or not.

  Test tree (under the system temp folder). The image files are empty;
  navigation never opens them.

    mview_nav_test\
      A\               notes.txt only (no images)
        A1\            a1_2.jpg   a1_3.jpg   a1_10.jpg
        A2\            (empty)
      B\               b.jpg   notes.txt
      C\               (empty)
      D2\              (empty)
      D10\             (empty)

  Directory order (natural): root, A, A1, A2, B, C, D2, D10.

  Phase B adds checks for the background tree: a cancellable scan,
  and a navigator that starts before the tree is known.
  Day 19 adds the no-disk mode: a tree built with every folder's
  images, and a navigator that only works from those lists
  (ReadsDisk = False, OpenListed, ListedKey).
  File dates: a1_2 = 2020-01-02, a1_3 = a1_10 = 2020-01-01.
  M2b (Day 25) adds containers (uContainers) in a tree of their own,
  last, with a fake reader for '.fak' files (one entry per line): before
  it is registered nothing changes; after it, a .fak is a one-time
  folder (Day 25): its entries are listed among its folder's images, it
  is no folder of the tree.
}

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, DateUtils,
  uTypes, uNaturalSort, uImageFormats,
  uDirectoryTree, uDirectoryImages, uNavigator, uContainers, uDirPeek;

type
  { Supplies a TCancelCheck for the cancellation test. }
  TCanceller = class
    function Always: Boolean;
  end;

function TCanceller.Always: Boolean;
begin
  Result := True;
end;

var
  PassCount, FailCount: Integer;
  RootDir: string;

procedure Check(const ALabel: string; ACondition: Boolean; const ADetail: string = '');
begin
  if ACondition then
  begin
    Inc(PassCount);
    WriteLn('  PASS  ', ALabel);
  end
  else
  begin
    Inc(FailCount);
    WriteLn('  FAIL  ', ALabel);
    if ADetail <> '' then
      WriteLn('         got: ', ADetail);
  end;
end;

function P(const ARelative: string): string;
begin
  if ARelative = '' then
    Result := RootDir
  else
    Result := RootDir + PathDelim + StringReplace(ARelative, '/', PathDelim, [rfReplaceAll]);
end;

function Name(const AFileName: string): string;
begin
  Result := ExtractFileName(AFileName);
end;

procedure Touch(const ARelative: string; const ADate: TDateTime = 0);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(P(ARelative), fmCreate);
  Stream.Free;
  if ADate <> 0 then
    FileSetDate(P(ARelative), DateTimeToFileDate(ADate));
end;

procedure DeleteTree(const APath: string);
var
  SearchRec: TSearchRec;
  FullName: string;
begin
  if not DirectoryExists(APath) then
    Exit;

  if FindFirst(IncludeTrailingPathDelimiter(APath) + '*', faAnyFile, SearchRec) = 0 then
  begin
    try
      repeat
        if (SearchRec.Name = '.') or (SearchRec.Name = '..') then
          Continue;
        FullName := IncludeTrailingPathDelimiter(APath) + SearchRec.Name;
        if (SearchRec.Attr and faDirectory) <> 0 then
          DeleteTree(FullName)
        else
          DeleteFile(FullName);
      until FindNext(SearchRec) <> 0;
    finally
      FindClose(SearchRec);
    end;
  end;

  RemoveDir(APath);
end;

procedure BuildTestTree;
begin
  RootDir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'mview_nav_test';
  DeleteTree(RootDir);  { in case a previous run was interrupted }

  ForceDirectories(P('A/A1'));
  ForceDirectories(P('A/A2'));
  ForceDirectories(P('B'));
  ForceDirectories(P('C'));
  ForceDirectories(P('D2'));
  ForceDirectories(P('D10'));

  Touch('A/notes.txt');
  Touch('A/A1/a1_2.jpg', EncodeDate(2020, 1, 2));
  Touch('A/A1/a1_3.jpg', EncodeDate(2020, 1, 1));
  Touch('A/A1/a1_10.jpg', EncodeDate(2020, 1, 1));
  Touch('B/b.jpg');
  Touch('B/notes.txt');
end;

function NewNavigator: TNavigator;
begin
  Result := TNavigator.Create;
  Result.Recursive := True;
  Result.WrapAround := True;
  Result.WrapScope := wsTree;
  Result.SetSortMode(smFileNameAscending);
end;

procedure TestNaturalSort;
begin
  WriteLn;
  WriteLn('-- Natural sort and formats --');
  Check('Image2 < Image10', NaturalCompareText('Image2', 'Image10') < 0);
  Check('image2 < Image10 (case ignored)', NaturalCompareText('image2', 'Image10') < 0);
  Check('scan_9 < scan_010', NaturalCompareText('scan_9', 'scan_010') < 0);
  Check('a < a1', NaturalCompareText('a', 'a1') < 0);
  Check('10 > 9', NaturalCompareText('10', '9') > 0);
  Check('D2 < D10', NaturalCompareText('D2', 'D10') < 0);
  Check('.JPG is supported', IsSupportedImageFile('x.JPG'));
  Check('.tiff is supported', IsSupportedImageFile('x.tiff'));
  Check('.webp, .HEIC, .ico, .cr2 are (1.1: Windows'' codecs)', IsSupportedImageFile('x.webp')
    and IsSupportedImageFile('x.HEIC') and IsSupportedImageFile('x.ico') and IsSupportedImageFile('x.cr2'));
  Check('  and only through WIC', IsWicOnlyFile('x.avif') and not IsWicOnlyFile('x.png'));
  Check('  a missing codec is named', Pos('HEIF', CodecHint('x.heic')) > 0);
  Check('.txt is not', not IsSupportedImageFile('x.txt'));
end;

procedure TestDirectoryTree;
var
  Tree: TDirectoryTree;
  Order: string;
  I: Integer;
begin
  WriteLn;
  WriteLn('-- TDirectoryTree --');

  Tree := TDirectoryTree.Create;
  try
    Tree.Build(RootDir, True);
    Check('recursive: 8 directories', Tree.Count = 8, IntToStr(Tree.Count));

    Order := '';
    for I := 0 to Tree.Count - 1 do
      Order := Order + ExtractFileName(Tree.Directory(I)) + ' ';
    Check('depth-first, natural order: root A A1 A2 B C D2 D10',
      Order = 'mview_nav_test A A1 A2 B C D2 D10 ', Order);

    Check('NextDirectory(A) = A1', Tree.NextDirectory(P('A')) = P('A/A1'));
    Check('NextDirectory(D10) = '''' (end)', Tree.NextDirectory(P('D10')) = '');
    Check('PreviousDirectory(root) = '''' (start)', Tree.PreviousDirectory(RootDir) = '');
    Check('IndexOf is case-insensitive', Tree.IndexOf(UpperCase(P('B'))) = Tree.IndexOf(P('B')));
  finally
    Tree.Free;
  end;

  Tree := TDirectoryTree.Create;
  try
    Tree.Build(RootDir, False);
    Check('non-recursive: root only', Tree.Count = 1, IntToStr(Tree.Count));
  finally
    Tree.Free;
  end;
end;

procedure TestDirectoryImages;
var
  Images: TDirectoryImages;
begin
  WriteLn;
  WriteLn('-- TDirectoryImages --');

  Images := TDirectoryImages.Create;
  try
    Images.Scan(P('A'));
    Check('A: notes.txt is not an image', Images.Count = 0, IntToStr(Images.Count));

    Images.SortMode := smFileNameAscending;
    Images.Scan(P('A/A1'));
    Check('A1: 3 images', Images.Count = 3, IntToStr(Images.Count));
    Check('name order: a1_2, a1_3, a1_10',
      (Name(Images.FileName(0)) = 'a1_2.jpg') and (Name(Images.FileName(1)) = 'a1_3.jpg')
      and (Name(Images.FileName(2)) = 'a1_10.jpg'),
      Name(Images.FileName(0)) + ' ' + Name(Images.FileName(1)) + ' ' + Name(Images.FileName(2)));

    Images.SortMode := smDateDescending;   { re-sorts at once }
    Check('date, newest first: a1_2 first', Name(Images.FileName(0)) = 'a1_2.jpg',
      Name(Images.FileName(0)));
    Check('same date: a1_3 before a1_10 (by name)',
      (Name(Images.FileName(1)) = 'a1_3.jpg') and (Name(Images.FileName(2)) = 'a1_10.jpg'),
      Name(Images.FileName(1)) + ' ' + Name(Images.FileName(2)));

    Images.SortMode := smDateAscending;
    Check('date, oldest first: a1_3, a1_10, a1_2',
      (Name(Images.FileName(0)) = 'a1_3.jpg') and (Name(Images.FileName(2)) = 'a1_2.jpg'),
      Name(Images.FileName(0)) + ' ... ' + Name(Images.FileName(2)));
  finally
    Images.Free;
  end;
end;

procedure TestBrowsing;
var
  Nav: TNavigator;
begin
  WriteLn;
  WriteLn('-- Browsing the whole tree (wrap: tree) --');

  Nav := NewNavigator;
  try
    Nav.OpenPath(RootDir);
    Check('root folder has no images: starts on A1\a1_2',
      Name(Nav.CurrentFileName) = 'a1_2.jpg', Nav.CurrentFileName);
    Check('root = the opened folder', Nav.RootDirectory = RootDir, Nav.RootDirectory);

    Nav.NextImage;
    Nav.NextImage;
    Check('next, next: a1_10', Name(Nav.CurrentFileName) = 'a1_10.jpg', Nav.CurrentFileName);

    Check('next: skips empty A2, lands on B\b.jpg',
      Nav.NextImage and (Name(Nav.CurrentFileName) = 'b.jpg'), Nav.CurrentFileName);

    Check('next: skips C, D2, D10, root, A and wraps to a1_2',
      Nav.NextImage and (Name(Nav.CurrentFileName) = 'a1_2.jpg'), Nav.CurrentFileName);

    Check('previous from a1_2: back to B\b.jpg',
      Nav.PreviousImage and (Name(Nav.CurrentFileName) = 'b.jpg'), Nav.CurrentFileName);

    Check('previous from b.jpg: LAST image of A1 (a1_10)',
      Nav.PreviousImage and (Name(Nav.CurrentFileName) = 'a1_10.jpg'), Nav.CurrentFileName);

    Check('next directory from A1: B',
      Nav.NextDirectory and (Name(Nav.CurrentFileName) = 'b.jpg'), Nav.CurrentFileName);

    Check('previous directory from B: FIRST image of A1',
      Nav.PreviousDirectory and (Name(Nav.CurrentFileName) = 'a1_2.jpg'), Nav.CurrentFileName);
  finally
    Nav.Free;
  end;
end;

procedure TestWrapOptions;
var
  Nav: TNavigator;
begin
  WriteLn;
  WriteLn('-- Wrap-around options --');

  { No wrap-around }
  Nav := NewNavigator;
  try
    Nav.WrapAround := False;
    Nav.OpenPath(P('B/b.jpg'));
    Check('file opened: root is its parent folder', Nav.RootDirectory = RootDir, Nav.RootDirectory);
    Check('no wrap: next after the last image fails', not Nav.NextImage);
    Check('  ...and stays on b.jpg', Name(Nav.CurrentFileName) = 'b.jpg', Nav.CurrentFileName);
  finally
    Nav.Free;
  end;

  { Wrap per folder }
  Nav := NewNavigator;
  try
    Nav.WrapScope := wsFolder;
    Nav.OpenPath(RootDir);   { starts on a1_2 }
    Check('folder wrap: previous from a1_2 goes to a1_10 (same folder)',
      Nav.PreviousImage and (Name(Nav.CurrentFileName) = 'a1_10.jpg'), Nav.CurrentFileName);
    Check('folder wrap: next from a1_10 goes to a1_2 (same folder)',
      Nav.NextImage and (Name(Nav.CurrentFileName) = 'a1_2.jpg'), Nav.CurrentFileName);
    Check('folder wrap: next directory still changes folders',
      Nav.NextDirectory and (Name(Nav.CurrentFileName) = 'b.jpg'), Nav.CurrentFileName);
  finally
    Nav.Free;
  end;

  { Only one folder with images (spec §16 #6) }
  Nav := NewNavigator;
  try
    Nav.OpenPath(P('A/A1'));  { root = A1 }
    Nav.NextImage;
    Nav.NextImage;
    Check('single folder: next from the last image wraps to the first',
      Nav.NextImage and (Name(Nav.CurrentFileName) = 'a1_2.jpg'), Nav.CurrentFileName);
    Check('single folder: previous from the first wraps to the last',
      Nav.PreviousImage and (Name(Nav.CurrentFileName) = 'a1_10.jpg'), Nav.CurrentFileName);
    Check('single folder: next directory has nowhere to go', not Nav.NextDirectory);
  finally
    Nav.Free;
  end;

  { A folder with a single image }
  Nav := NewNavigator;
  try
    Nav.OpenPath(P('B'));
    Check('one image only: next reports no change', not Nav.NextImage);
    Check('  ...and stays on b.jpg', Name(Nav.CurrentFileName) = 'b.jpg', Nav.CurrentFileName);
  finally
    Nav.Free;
  end;

  { No images anywhere }
  Nav := NewNavigator;
  try
    Nav.OpenPath(P('C'));
    Check('empty tree: no current image', not Nav.HasCurrentImage);
    Check('empty tree: next fails', not Nav.NextImage);
  finally
    Nav.Free;
  end;
end;

{ The names in AFiles, joined with commas, for easy comparison. }
function Names(const AFiles: TStringArray): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(AFiles) do
  begin
    if I > 0 then
      Result := Result + ',';
    Result := Result + Name(AFiles[I]);
  end;
end;

procedure TestFilesAhead;
var
  Nav: TNavigator;
  Got: string;
begin
  WriteLn;
  WriteLn('-- Files ahead (preloading) --');

  Nav := NewNavigator;
  try
    Nav.OpenPath(RootDir);
    Got := Names(Nav.FilesAhead(3, 1));
    Check('3 ahead of a1_2: a1_3, a1_10, then B\b', Got = 'a1_3.jpg,a1_10.jpg,b.jpg', Got);
    Got := Names(Nav.FilesAhead(10, 1));
    Check('10 ahead: stops before coming round to a1_2 again', Got = 'a1_3.jpg,a1_10.jpg,b.jpg', Got);
    Got := Names(Nav.FilesAhead(2, -1));
    Check('2 behind a1_2: wraps to b, then a1_10', Got = 'b.jpg,a1_10.jpg', Got);
    Check('asking does not move', Name(Nav.CurrentFileName) = 'a1_2.jpg', Nav.CurrentFileName);
    Got := Names(Nav.FilesAhead(0, 1));
    Check('0 ahead: empty', Got = '', Got);
  finally
    Nav.Free;
  end;

  Nav := NewNavigator;
  try
    Nav.WrapAround := False;
    Nav.OpenPath(P('B/b.jpg'));
    Got := Names(Nav.FilesAhead(3, 1));
    Check('no wrap, last image: nothing ahead', Got = '', Got);
    Got := Names(Nav.FilesAhead(3, -1));
    Check('no wrap, behind b: a1_10, a1_3, a1_2', Got = 'a1_10.jpg,a1_3.jpg,a1_2.jpg', Got);
  finally
    Nav.Free;
  end;

  Nav := NewNavigator;
  try
    Nav.WrapScope := wsFolder;
    Nav.OpenPath(P('A/A1/a1_10.jpg'));
    Got := Names(Nav.FilesAhead(5, 1));
    Check('wrap per folder: a1_2, a1_3 and stop', Got = 'a1_2.jpg,a1_3.jpg', Got);
  finally
    Nav.Free;
  end;

  Nav := NewNavigator;
  try
    Nav.OpenPath(P('A/A1/a1_3.jpg'), '', True);
    Got := Names(Nav.FilesAhead(5, 1));
    Check('tree not known yet: only its own folder, no wrap', Got = 'a1_10.jpg', Got);
  finally
    Nav.Free;
  end;
end;

procedure TestBackgroundTree;
var
  Nav: TNavigator;
  Tree: TDirectoryTree;
  Canceller: TCanceller;
begin
  WriteLn;
  WriteLn('-- Background tree (Phase B) --');

  { A scan that is cancelled reports it. }
  Canceller := TCanceller.Create;
  Tree := TDirectoryTree.Create;
  try
    Check('cancelled scan: Build returns False',
      not Tree.Build(RootDir, True, @Canceller.Always));
    Check('uncancelled scan: Build returns True', Tree.Build(RootDir, True));
  finally
    Tree.Free;
    Canceller.Free;
  end;

  { Root folder without images: nothing to show until the tree comes. }
  Nav := NewNavigator;
  try
    Nav.OpenPath(RootDir, '', True);
    Check('deferred: tree not ready yet', not Nav.TreeReady);
    Check('deferred: empty root has no image yet', not Nav.HasCurrentImage);
    Check('deferred: next has nowhere to go yet', not Nav.NextImage);

    Tree := TDirectoryTree.Create;
    Tree.Build(RootDir, True);
    Check('SetTree moves on to the first folder with images',
      Nav.SetTree(Tree) and (Name(Nav.CurrentFileName) = 'a1_2.jpg'), Nav.CurrentFileName);
    Check('  ...tree ready', Nav.TreeReady);
  finally
    Nav.Free;
  end;

  { A file opened with a deferred tree is shown at once. }
  Nav := NewNavigator;
  try
    Nav.OpenPath(P('A/A1/a1_10.jpg'), '', True);
    Check('deferred: opened file is current at once',
      Name(Nav.CurrentFileName) = 'a1_10.jpg', Nav.CurrentFileName);
    Check('deferred: previous works inside the folder',
      Nav.PreviousImage and (Name(Nav.CurrentFileName) = 'a1_3.jpg'), Nav.CurrentFileName);
    Nav.NextImage;
    Check('deferred: no wrap at the end while the tree is missing', not Nav.NextImage);

    Tree := TDirectoryTree.Create;
    Tree.Build(Nav.RootDirectory, True);
    Check('SetTree keeps the current image', not Nav.SetTree(Tree)
      and (Name(Nav.CurrentFileName) = 'a1_10.jpg'), Nav.CurrentFileName);
    Check('with the tree: next wraps to a1_2 (A1 is the only folder with images under A)',
      Nav.NextImage and (Name(Nav.CurrentFileName) = 'a1_2.jpg'), Nav.CurrentFileName);
  finally
    Nav.Free;
  end;
end;

procedure TestOpenAndSort;
var
  Nav: TNavigator;
begin
  WriteLn;
  WriteLn('-- Opening files, resuming, sort changes --');

  Nav := NewNavigator;
  try
    Nav.OpenPath(P('A/A1/a1_10.jpg'));
    Check('file opened: that file is current', Name(Nav.CurrentFileName) = 'a1_10.jpg', Nav.CurrentFileName);
    Check('file opened: root is the parent folder (A)', Nav.RootDirectory = P('A'), Nav.RootDirectory);

    Nav.SetSortMode(smDateAscending);
    Check('sort change keeps the current file', Name(Nav.CurrentFileName) = 'a1_10.jpg', Nav.CurrentFileName);
    Check('  ...at its new position (2nd)', Nav.CurrentIndex = 1, IntToStr(Nav.CurrentIndex));

    Nav.ToggleSortMode;
    Check('toggle from date: by name', Nav.SortMode = smFileNameAscending);
    Check('  ...still on a1_10', Name(Nav.CurrentFileName) = 'a1_10.jpg', Nav.CurrentFileName);
  finally
    Nav.Free;
  end;

  Nav := NewNavigator;
  try
    Nav.OpenPath(RootDir, P('B/b.jpg'));
    Check('resume: folder opened, file selected', Name(Nav.CurrentFileName) = 'b.jpg', Nav.CurrentFileName);
    Check('resume: root is the folder', Nav.RootDirectory = RootDir, Nav.RootDirectory);
  finally
    Nav.Free;
  end;

  Nav := NewNavigator;
  try
    Nav.OpenPath(P('A'), P('B/b.jpg'));
    Check('resume file outside the tree is ignored', Name(Nav.CurrentFileName) = 'a1_2.jpg', Nav.CurrentFileName);
  finally
    Nav.Free;
  end;
end;

{ Day 19: the viewer's navigator never reads a folder; the scanner
  delivers the start folder's list (OpenListed) and a tree with every
  folder's images. }
procedure TestNoDiskMode;
var
  Nav: TNavigator;
  Tree: TDirectoryTree;
  Start: TDirectoryImages;
  Key: TImageKey;
begin
  WriteLn;
  WriteLn('-- No disk access (Day 19) --');

  Tree := TDirectoryTree.Create;
  try
    Tree.Build(RootDir, True, nil, True);
    Check('tree with images: A1 has 3',
      (Tree.ImagesOf(P('A/A1')) <> nil) and (Tree.ImagesOf(P('A/A1')).Count = 3));
    Check('  B has 1 (notes.txt left out)',
      (Tree.ImagesOf(P('B')) <> nil) and (Tree.ImagesOf(P('B')).Count = 1));
    Check('  C is listed, empty',
      (Tree.ImagesOf(P('C')) <> nil) and (Tree.ImagesOf(P('C')).Count = 0));
  finally
    Tree.Free;
  end;

  Tree := TDirectoryTree.Create;
  try
    Tree.Build(P('A/A1'), False, nil, True);
    Check('not recursive, with images: one folder, 3 images',
      (Tree.Count = 1) and (Tree.Images(0) <> nil) and (Tree.Images(0).Count = 3));
  finally
    Tree.Free;
  end;

  Nav := NewNavigator;
  try
    Nav.ReadsDisk := False;
    Start := TDirectoryImages.Create;
    try
      Start.Scan(P('A/A1'));   { what the scanner delivers first }
      Nav.OpenListed(RootDir, P('A/A1'), Start, P('A/A1/a1_3.jpg'));
    finally
      Start.Free;
    end;
    Check('OpenListed starts on the given file', Name(Nav.CurrentFileName) = 'a1_3.jpg',
      Nav.CurrentFileName);
    Check('  no tree yet: no folder change', not Nav.NextDirectory, Nav.CurrentFileName);

    Tree := TDirectoryTree.Create;
    Tree.Build(RootDir, True, nil, True);
    Check('SetTree keeps the current image',
      (not Nav.SetTree(Tree)) and (Name(Nav.CurrentFileName) = 'a1_3.jpg'), Nav.CurrentFileName);
    Check('next: a1_10', Nav.NextImage and (Name(Nav.CurrentFileName) = 'a1_10.jpg'),
      Nav.CurrentFileName);
    Check('next crosses into B, from the tree''s lists',
      Nav.NextImage and (Name(Nav.CurrentFileName) = 'b.jpg'), Nav.CurrentFileName);
    Check('ListedKey knows b.jpg', Nav.ListedKey(Nav.CurrentFileName, Key) and (Key.FileSize = 0));
    Check('ListedKey: a file not listed', not Nav.ListedKey(P('A/notes.txt'), Key));
    Check('previous directory: back to A1 (A2 empty)',
      Nav.PreviousDirectory and (Name(Nav.CurrentFileName) = 'a1_2.jpg'), Nav.CurrentFileName);
  finally
    Nav.Free;
  end;
end;

{ Day 22 (ClimbUp): at the end of the tree a step doesn't wrap around
  but asks the owner to climb one level (TMView opens the parent). }
procedure TestClimbUp;
var
  Nav: TNavigator;
begin
  WriteLn;
  WriteLn('-- Climbing at the end of the tree (ClimbUp) --');

  Nav := NewNavigator;
  try
    Nav.ClimbUp := True;
    Nav.OpenPath(P('A/A1'));           { a folder: it is the root }
    Check('folder opened: it is the root', Nav.RootDirectory = P('A/A1'), Nav.RootDirectory);
    Check('its parent is no drive: may climb', Nav.CanClimbUp);
    Check('next folder at the end: no step', not Nav.NextDirectory);
    Check('  ...climbing wanted', Nav.ClimbWanted);
    Check('  ...still on a1_2', Name(Nav.CurrentFileName) = 'a1_2.jpg', Nav.CurrentFileName);
    Check('previous folder: climbing wanted too', (not Nav.PreviousDirectory) and Nav.ClimbWanted);
    Nav.NextImage;
    Check('next image inside the folder: a step, no climbing',
      (Name(Nav.CurrentFileName) = 'a1_3.jpg') and not Nav.ClimbWanted, Nav.CurrentFileName);
    Nav.NextImage;
    Check('last image, next: no wrap to a1_2, climbing wanted',
      (not Nav.NextImage) and Nav.ClimbWanted and (Name(Nav.CurrentFileName) = 'a1_10.jpg'),
      Nav.CurrentFileName);
  finally
    Nav.Free;
  end;

  Nav := NewNavigator;
  try
    Nav.ClimbUp := False;
    Nav.OpenPath(P('A/A1'));
    Nav.NextImage;
    Nav.NextImage;
    Check('ClimbUp off: last image, next wraps to a1_2 as before',
      Nav.NextImage and (Name(Nav.CurrentFileName) = 'a1_2.jpg') and not Nav.ClimbWanted,
      Nav.CurrentFileName);
    Check('ClimbUp off: next folder asks for nothing', (not Nav.NextDirectory) and not Nav.ClimbWanted);
  finally
    Nav.Free;
  end;

  Nav := NewNavigator;
  try
    Nav.ClimbUp := True;
    Nav.OpenPath(P('A'));              { A1 and A2 below it }
    Check('inside the tree: next folder steps as before (A1 -> B is outside: climb)',
      (not Nav.NextDirectory) and Nav.ClimbWanted, Nav.CurrentFileName);
  finally
    Nav.Free;
  end;
end;

{ Phase G (sorting): a file moved away leaves the lists and the next one
  becomes current; a file copied in (or moved back by Undo) appears.
  Runs last: it changes the test tree. }
procedure TestRemoveAndAdd;
var
  Nav: TNavigator;
begin
  WriteLn;
  WriteLn('-- Files moved away and back (sorting) --');

  Nav := NewNavigator;
  try
    { The whole tree (root, not the file's folder's parent), so B follows A1. }
    Nav.OpenPath(RootDir, P('A/A1/a1_3.jpg'));
    Check('starts on a1_3', Name(Nav.CurrentFileName) = 'a1_3.jpg', Nav.CurrentFileName);

    DeleteFile(P('A/A1/a1_3.jpg'));
    Check('current moved away: reported as changed', Nav.RemoveFile(P('A/A1/a1_3.jpg')));
    Check('... the next image is current (a1_10)', Name(Nav.CurrentFileName) = 'a1_10.jpg',
      Nav.CurrentFileName);
    Check('... two images left in A1', Nav.ImageCount = 2, IntToStr(Nav.ImageCount));

    DeleteFile(P('A/A1/a1_2.jpg'));
    Check('another file moved away: current unchanged',
      (not Nav.RemoveFile(P('A/A1/a1_2.jpg'))) and (Name(Nav.CurrentFileName) = 'a1_10.jpg'),
      Nav.CurrentFileName);
    Check('... one image left', Nav.ImageCount = 1, IntToStr(Nav.ImageCount));

    Touch('A/A1/a1_3.jpg', EncodeDate(2020, 1, 1));
    Nav.AddFile(P('A/A1/a1_3.jpg'), 0, EncodeDate(2020, 1, 1));
    Check('moved back: listed again, current unchanged',
      (Nav.ImageCount = 2) and (Name(Nav.CurrentFileName) = 'a1_10.jpg'), Nav.CurrentFileName);
    Nav.AddFile(P('A/A1/a1_3.jpg'), 0, EncodeDate(2020, 1, 1));
    Check('added twice: listed once', Nav.ImageCount = 2, IntToStr(Nav.ImageCount));
    Check('SelectFile: a1_3 current again',
      Nav.SelectFile(P('A/A1/a1_3.jpg')) and (Name(Nav.CurrentFileName) = 'a1_3.jpg'),
      Nav.CurrentFileName);
    Nav.AddFile(P('A/A1/notes.txt'), 0, Now);
    Check('not an image: not added', Nav.ImageCount = 2, IntToStr(Nav.ImageCount));

    Check('SelectFile a1_10', Nav.SelectFile(P('A/A1/a1_10.jpg')));
    DeleteFile(P('A/A1/a1_10.jpg'));
    Nav.RemoveFile(P('A/A1/a1_10.jpg'));
    Check('last of the folder moved away: next folder (B)',
      Name(Nav.CurrentFileName) = 'b.jpg', Nav.CurrentFileName);
  finally
    Nav.Free;
  end;
end;

{ ---- Containers (M2b) ---- }

{ A fake container: one entry id per line. }
function ListFake(const AFile: string; out AEntries: TContainerEntryArray): Boolean;
var
  Lines: TStringList;
  I: Integer;
begin
  AEntries := nil;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(AFile);
    SetLength(AEntries, Lines.Count);
    for I := 0 to Lines.Count - 1 do
    begin
      AEntries[I].Id := Lines[I];
      AEntries[I].Name := Lines[I];
    end;
    Result := True;
  finally
    Lines.Free;
  end;
end;

function DecodeFake(const AFile, AId: string; ACancel: TCancelCheck;
  out AWidth, AHeight: Integer; out ARGBA: TBytes; out AError: string): Boolean;
begin
  AWidth := 0;
  AHeight := 0;
  ARGBA := nil;
  AError := 'fake';
  Result := False;
end;

procedure WriteLines(const AFileName: string; const ALines: array of string);
var
  Lines: TStringList;
  I: Integer;
begin
  Lines := TStringList.Create;
  try
    for I := 0 to High(ALines) do
      Lines.Add(ALines[I]);
    Lines.SaveToFile(AFileName);
  finally
    Lines.Free;
  end;
end;

type
  TPeekSink = class
    Count, Images: Integer;
    Folder: string;
    procedure Take(const AFolder: string; AImages, AFolders: Integer);
  end;

procedure TPeekSink.Take(const AFolder: string; AImages, AFolders: Integer);
begin
  Inc(Count);
  Folder := AFolder;
  Images := AImages;
end;

{ 1.1: the dir preview's look into a folder. }
procedure TestDirPeek;
var
  Images, Folders: Integer;
  PeekSink: TPeekSink;
  Peek: TDirPeek;
  Start: TDateTime;
begin
  WriteLn('uDirPeek');
  CountFolder(P('A'), Images, Folders);
  Check('A: no images of its own, two subfolders', (Images = 0) and (Folders = 2),
    Format('%d %d', [Images, Folders]));
  CountFolder(P('A/A1'), Images, Folders);
  Check('A1: three images, no subfolder', (Images = 3) and (Folders = 0),
    Format('%d %d', [Images, Folders]));
  CountFolder(P('B'), Images, Folders);
  Check('B: one image (notes.txt is none)', (Images = 1) and (Folders = 0),
    Format('%d %d', [Images, Folders]));
  CountFolder(P('nothing here'), Images, Folders);
  Check('a folder that is not there: nothing', (Images = 0) and (Folders = 0));
  { The thread: queued results, the newest request wins, a freed owner
    gets nothing. }
  PeekSink := TPeekSink.Create;
  Peek := TDirPeek.Create;
  try
    Peek.OnResult := @PeekSink.Take;
    Peek.Request(P('B'));
    Peek.Request(P('A/A1'));
    Start := Now;
    while (PeekSink.Count = 0) and (MilliSecondsBetween(Now, Start) < 3000) do
    begin
      CheckSynchronize(10);
    end;
    Start := Now;
    while MilliSecondsBetween(Now, Start) < 300 do
      CheckSynchronize(10);
    Check('a request: its result comes back (queued)', PeekSink.Count = 1,
      IntToStr(PeekSink.Count));
    Check('the newest request wins', (PeekSink.Folder = P('A/A1')) and (PeekSink.Images = 3),
      PeekSink.Folder);
    Peek.Request(P('B'));
  finally
    Peek.Free;
  end;
  Start := Now;
  while MilliSecondsBetween(Now, Start) < 300 do
    CheckSynchronize(10);
  Check('the owner freed: nothing more', PeekSink.Count = 1, IntToStr(PeekSink.Count));
  PeekSink.Free;
end;

procedure TestContainers;
var
  Base, CRoot, Stack, S2: string;
  Tree: TDirectoryTree;
  Nav: TNavigator;
  List: TDirectoryImages;
  Key: TImageKey;
  FileName, Id: string;
begin
  WriteLn;
  WriteLn('-- Containers (M2b, M2c; one-time folders, Day 25) --');
  { One level below the temp folder: an opened file's tree is its
    folder's parent (Base), not the whole temp folder. }
  Base := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'mview_nav_containers';
  CRoot := Base + PathDelim + 'box';
  DeleteTree(Base);
  ForceDirectories(CRoot + PathDelim + 'Z');
  Stack := CRoot + PathDelim + 'stack.fak';
  S2 := Stack + '|S2';
  try
    with TFileStream.Create(CRoot + PathDelim + 'img.jpg', fmCreate) do Free;
    with TFileStream.Create(CRoot + PathDelim + 'Z' + PathDelim + 'z.jpg', fmCreate) do Free;
    WriteLines(Stack, ['S1', 'S2', 'Folder|S3']);
    WriteLines(CRoot + PathDelim + 'empty.fak', []);

    { No reader (MView): nothing is a container. }
    Check('no reader: .fak is no container', not IsContainerName(Stack));
    Tree := TDirectoryTree.Create;
    try
      Tree.Build(CRoot, True, nil, True);
      Check('no reader: the tree is root and Z', Tree.Count = 2, IntToStr(Tree.Count));
      Check('no reader: root has img.jpg only', (Tree.ImagesOf(CRoot) <> nil)
        and (Tree.ImagesOf(CRoot).Count = 1) and (Tree.ImagesOf(CRoot).ContainerCount = 0));
    finally
      Tree.Free;
    end;
    List := TDirectoryImages.Create;
    try
      List.Scan(CRoot);
      Check('no reader: listing has 1 image, no containers', (List.Count = 1) and (List.ContainerCount = 0));
    finally
      List.Free;
    end;
    Check('names: virtual', IsVirtualName(S2) and not IsVirtualName(Stack));
    Check('SplitVirtual', SplitVirtual(S2, FileName, Id) and (FileName = Stack) and (Id = 'S2'));
    Check('ItemDirectory: the folder the container lies in; an ordinary file: its folder',
      (ItemDirectory(S2) = CRoot) and (ItemDirectory(CRoot + PathDelim + 'img.jpg') = CRoot),
      ItemDirectory(S2));
    Check('RealFolderOf: where the container lies', RealFolderOf(S2) = CRoot, RealFolderOf(S2));
    Check('DisplayItemName', DisplayItemName(S2) = 'stack.fak › S2', DisplayItemName(S2));
    Check('ItemBaseName', (ItemBaseName(S2) = 'stack_S2') and (ItemBaseName(Stack + '|Folder|S3') = 'stack_Folder_S3'),
      ItemBaseName(S2));
    Check('ItemExists: by its container', ItemExists(S2) and not ItemExists(CRoot + PathDelim + 'x.fak|S2'));

    RegisterContainerReader('Fake', '.FAK', @ListFake, @DecodeFake);
    Check('reader registered: .fak is a container', IsContainerName(Stack) and (ContainerReaderCount = 1));
    Check('  a virtual name is not', not IsContainerName(S2));

    Tree := TDirectoryTree.Create;
    try
      Tree.Build(CRoot, True, nil, True);
      Check('tree: still root and Z (a container is no folder of the tree)', (Tree.Count = 2)
        and (Tree.IndexOf(Stack) < 0), IntToStr(Tree.Count));
      Check('  root: img.jpg and the 3 images of stack.fak', (Tree.ImagesOf(CRoot) <> nil)
        and (Tree.ImagesOf(CRoot).Count = 4), IntToStr(Tree.ImagesOf(CRoot).Count));
      Check('  its images are virtual names', Tree.ImagesOf(CRoot).IndexOfFile(S2) >= 0);
      Check('  the root''s containers: empty.fak, stack.fak',
        (Tree.ImagesOf(CRoot).ContainerCount = 2)
        and (Name(Tree.ImagesOf(CRoot).Container(0)) = 'empty.fak')
        and (Name(Tree.ImagesOf(CRoot).Container(1)) = 'stack.fak'));
      Check('  next directory after root: Z', SameText(Tree.NextDirectory(CRoot), CRoot + PathDelim + 'Z'));
      List := TDirectoryImages.Create;
      try
        List.Assign(Tree.ImagesOf(CRoot));
        Check('  Assign copies the containers', List.ContainerCount = 2);
      finally
        List.Free;
      end;
    finally
      Tree.Free;
    end;

    List := TDirectoryImages.Create;
    try
      List.Scan(CRoot);
      Check('folder listing: img.jpg and the 3 images of stack.fak', List.Count = 4, IntToStr(List.Count));
      Check('  with the container file''s size', List.FileSize(List.IndexOfFile(S2)) > 0);
      Check('  its containers', (List.ContainerCount = 2) and SameText(List.Container(1), Stack));
      Check('  FirstOfContainer', (List.FirstOfContainer(Stack) >= 0)
        and IsVirtualName(List.FileName(List.FirstOfContainer(Stack))));
    finally
      List.Free;
    end;

    Nav := NewNavigator;
    try
      Nav.OpenPath(CRoot);
      Check('open the folder: img.jpg', Name(Nav.CurrentFileName) = 'img.jpg', Nav.CurrentFileName);
      Check('  4 images (the container''s among them)', Nav.ImageCount = 4, IntToStr(Nav.ImageCount));
      Check('  FolderContainers: 2', Length(Nav.FolderContainers) = 2,
        IntToStr(Length(Nav.FolderContainers)));
      Check('the wheel walks into the container', Nav.NextImage and IsVirtualName(Nav.CurrentFileName),
        Nav.CurrentFileName);
      Check('  its folder is the real folder', SameText(Nav.CurrentDirectory, CRoot), Nav.CurrentDirectory);
      Check('next directory from inside it: Z (passes it like a file)',
        Nav.NextDirectory and (Name(Nav.CurrentFileName) = 'z.jpg'), Nav.CurrentFileName);

      Nav.OpenPath(Stack);
      Check('open the container: its folder, on its first image', IsVirtualName(Nav.CurrentFileName)
        and SameText(ContainerFileOf(Nav.CurrentFileName), Stack)
        and SameText(Nav.CurrentDirectory, CRoot), Nav.CurrentFileName);
      Check('  the tree of the folder''s parent, as for a file', SameText(Nav.RootDirectory, Base),
        Nav.RootDirectory);

      Nav.OpenPath(S2);
      Check('open an image in it: that image', SameText(Nav.CurrentFileName, S2), Nav.CurrentFileName);
      Check('ListedKey: the container''s size',
        Nav.ListedKey(S2, Key) and (Key.FileSize > 0) and SameText(Key.FileName, S2));

      Nav.OpenPath(CRoot, S2);
      Check('open the folder, resume on an image in a container', SameText(Nav.CurrentFileName, S2),
        Nav.CurrentFileName);
    finally
      Nav.Free;
    end;
  finally
    DeleteTree(Base);
  end;
end;

begin
  PassCount := 0;
  FailCount := 0;

  WriteLn('VersariteViewer navigation test');
  WriteLn('=====================');

  BuildTestTree;
  WriteLn('Test tree: ', RootDir);

  try
    TestNaturalSort;
    TestDirPeek;      { before the tests that change the tree }
    TestDirectoryTree;
    TestDirectoryImages;
    TestBrowsing;
    TestWrapOptions;
    TestOpenAndSort;
    TestBackgroundTree;
    TestFilesAhead;
    TestNoDiskMode;
    TestClimbUp;
    TestRemoveAndAdd;
    TestContainers;   { last: it registers a reader }
  finally
    DeleteTree(RootDir);
  end;

  WriteLn;
  WriteLn('=====================');
  WriteLn(Format('%d passed, %d failed', [PassCount, FailCount]));

  if FailCount > 0 then
    Halt(1);
end.
