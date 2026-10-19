program TestSort;

{
  Checks the sorting units of Phase G (G1):
  - uFileMover: UniqueFileName (never overwrite: _1, _2 ...), copy,
    move, a missing source, a missing target folder (reported, or made
    when asked), the log sorting.log, and the worker thread with its
    delivery on the main thread.
  - uSortFolders: slots (add, replace, colour, move, remove, the
    64-slot limit), recent folders, and the [Sort] section of the ini
    file (written and read back, stale keys removed); IconBaseName.
  - Stage 2: writing a file with faWrite (the old one becomes
    _previous, then _previous_1), and uIconFile: the directory of an
    .ico built in memory (32-bit and 4-bit pictures, a PNG entry),
    choosing the picture for a size, decoding with transparency, and
    WriteIconFile read back; 1.1: IconDibEntry and IconPngEntry (an
    opaque picture keeps its alpha channel, colour type 6: Windows
    refuses PNG entries without it), read back with the FPC PNG reader.
  - 1.1: uSafeFile (the ini is written through a .tmp and one replace).

  Works in a folder "sorttest" next to this program, removed at the
  end. Build and run with build_test.bat.
}

{$mode ObjFPC}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, IniFiles,
  FPImage, FPReadPNG,
  uFileMover,
  uSortFolders,
  uIconFile,
  uSafeFile;

var
  PassCount, FailCount: Integer;
  Root: string;

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

procedure WriteFile(const AName, AText: string);
var
  S: TStringList;
begin
  S := TStringList.Create;
  try
    S.Text := AText;
    S.SaveToFile(AName);
  finally
    S.Free;
  end;
end;

function ReadFile(const AName: string): string;
var
  S: TStringList;
begin
  S := TStringList.Create;
  try
    S.LoadFromFile(AName);
    Result := Trim(S.Text);
  finally
    S.Free;
  end;
end;

procedure RemoveTree(const ADir: string);
var
  Info: TSearchRec;
  Dir: string;
begin
  Dir := IncludeTrailingPathDelimiter(ADir);
  if FindFirst(Dir + '*', faAnyFile, Info) = 0 then
  begin
    repeat
      if (Info.Name = '.') or (Info.Name = '..') then
        Continue;
      if (Info.Attr and faDirectory) <> 0 then
        RemoveTree(Dir + Info.Name)
      else
        DeleteFile(Dir + Info.Name);
    until FindNext(Info) <> 0;
    FindClose(Info);
  end;
  RemoveDir(ADir);
end;

function MakeJob(AAction: TFileAction; const ASource, ATargetDir: string): TFileJob;
begin
  Result := Default(TFileJob);
  Result.Action := AAction;
  Result.Kind := fjSort;
  Result.Source := ASource;
  Result.TargetDir := ATargetDir;
  Result.Slot := 0;
  Result.UndoOf := -1;
end;

{ ---- uFileMover ---- }

procedure TestUniqueName;
var
  Dir: string;
begin
  WriteLn('UniqueFileName');
  Dir := Root + 'unique' + PathDelim;
  ForceDirectories(Dir);
  Check('free name stays', UniqueFileName(Dir, 'cell.jpg') = Dir + 'cell.jpg');
  WriteFile(Dir + 'cell.jpg', 'a');
  Check('taken: _1', UniqueFileName(Dir, 'cell.jpg') = Dir + 'cell_1.jpg',
    UniqueFileName(Dir, 'cell.jpg'));
  WriteFile(Dir + 'cell_1.jpg', 'b');
  Check('_1 taken too: _2', UniqueFileName(Dir, 'cell.jpg') = Dir + 'cell_2.jpg');
  Check('folder without trailing delimiter',
    UniqueFileName(ExcludeTrailingPathDelimiter(Dir), 'cell.jpg') = Dir + 'cell_2.jpg');
  WriteFile(Dir + 'noext', 'c');
  Check('no extension: noext_1', UniqueFileName(Dir, 'noext') = Dir + 'noext_1');
  ForceDirectories(Dir + 'sub');
  Check('a folder of that name counts as taken', UniqueFileName(Dir, 'sub') = Dir + 'sub_1');
end;

procedure TestJobs;
var
  Src, Good, Bad, Log: string;
  R: TFileJobResult;
  J: TFileJob;
  Lines: TStringList;
begin
  WriteLn('ExecuteFileJob');
  Src := Root + 'src' + PathDelim;
  Good := Root + 'Good';
  Bad := Root + 'Bad';
  Log := Root + 'sorting.log';
  ForceDirectories(Src);
  ForceDirectories(Good);
  WriteFile(Src + 'a.jpg', 'image a');
  WriteFile(Src + 'b.jpg', 'image b');

  R := ExecuteFileJob(MakeJob(faCopy, Src + 'a.jpg', Good), Log);
  Check('copy: OK', R.OK, R.Message);
  Check('copy: the copy is there', FileExists(Good + PathDelim + 'a.jpg'));
  Check('copy: the original stays', FileExists(Src + 'a.jpg'));
  Check('copy: ResultFile', R.ResultFile = IncludeTrailingPathDelimiter(Good) + 'a.jpg', R.ResultFile);
  Check('copy: same content', ReadFile(R.ResultFile) = 'image a');
  Check('copy: size reported', R.Size > 0);

  R := ExecuteFileJob(MakeJob(faCopy, Src + 'a.jpg', Good), Log);
  Check('copy again: never overwritten, a_1.jpg',
    R.OK and (ExtractFileName(R.ResultFile) = 'a_1.jpg'), R.ResultFile);

  R := ExecuteFileJob(MakeJob(faMove, Src + 'b.jpg', Good), Log);
  Check('move: OK', R.OK, R.Message);
  Check('move: gone from the source', not FileExists(Src + 'b.jpg'));
  Check('move: there', FileExists(IncludeTrailingPathDelimiter(Good) + 'b.jpg'));

  R := ExecuteFileJob(MakeJob(faMove, Src + 'b.jpg', Good), Log);
  Check('missing source: reported', (not R.OK) and (R.Message <> ''), R.Message);

  WriteFile(Src + 'c.jpg', 'image c');
  R := ExecuteFileJob(MakeJob(faMove, Src + 'c.jpg', Bad), Log);
  Check('missing folder: reported, not made', (not R.OK) and not DirectoryExists(Bad), R.Message);
  Check('missing folder: the file stays', FileExists(Src + 'c.jpg'));

  J := MakeJob(faMove, Src + 'c.jpg', Root + 'deleted' + PathDelim + 'inner');
  J.Kind := fjDelete;
  J.CreateTarget := True;
  R := ExecuteFileJob(J, Log);
  Check('CreateTarget: the folder is made and the file moved',
    R.OK and FileExists(R.ResultFile) and not FileExists(Src + 'c.jpg'), R.Message);

  { Undo of the move: back under the old name. }
  J := MakeJob(faMove, IncludeTrailingPathDelimiter(Good) + 'b.jpg', ExcludeTrailingPathDelimiter(Src));
  J.Kind := fjUndo;
  J.TargetName := 'b.jpg';
  R := ExecuteFileJob(J, Log);
  Check('undo: back in its folder', R.OK and FileExists(Src + 'b.jpg'), R.Message);

  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(Log);
    Check('log: header', (Lines.Count >= 2) and (Lines[0] = 'sep=;')
      and (Lines[1] = 'time;action;from;to;result'));
    Check('log: one line per job', Lines.Count = 2 + 7, IntToStr(Lines.Count));
    Check('log: a copy is logged', Pos(';copy;', Lines[2]) > 0, Lines[2]);
    Check('log: delete and undo are marked',
      (Pos('move (delete)', Lines.Text) > 0) and (Pos('move (undo)', Lines.Text) > 0));
    Check('log: failures say why', Pos(';ok', Lines[6]) = 0, Lines[6]);
  finally
    Lines.Free;
  end;
end;

type
  TCollector = class
    Results: array of TFileJobResult;
    procedure Done(const AResult: TFileJobResult);
  end;

procedure TCollector.Done(const AResult: TFileJobResult);
begin
  SetLength(Results, Length(Results) + 1);
  Results[High(Results)] := AResult;
end;

procedure TestThread;
var
  Mover: TFileMover;
  C: TCollector;
  Src, Dst: string;
  I: Integer;
  Start: QWord;
begin
  WriteLn('TFileMover (thread)');
  Src := Root + 'tsrc' + PathDelim;
  Dst := Root + 'tdst';
  ForceDirectories(Src);
  ForceDirectories(Dst);
  for I := 1 to 5 do
    WriteFile(Src + Format('f%d.jpg', [I]), IntToStr(I));

  C := TCollector.Create;
  Mover := TFileMover.Create('');
  try
    Mover.OnDone := @C.Done;
    for I := 1 to 5 do
      Mover.Add(MakeJob(faMove, Src + Format('f%d.jpg', [I]), Dst));
    Check('busy after Add', Mover.Busy);
    Start := GetTickCount64;
    while (Length(C.Results) < 5) and (GetTickCount64 - Start < 10000) do
    begin
      CheckSynchronize(20);
    end;
    Check('all five delivered (on the main thread)', Length(C.Results) = 5,
      IntToStr(Length(C.Results)));
    Check('in order', (Length(C.Results) = 5)
      and (ExtractFileName(C.Results[0].Job.Source) = 'f1.jpg')
      and (ExtractFileName(C.Results[4].Job.Source) = 'f5.jpg'));
    Check('all OK', (Length(C.Results) = 5) and C.Results[0].OK and C.Results[4].OK);
    Check('not busy any more', not Mover.Busy);
  finally
    Mover.Free;
    C.Free;
  end;

  { Freed with jobs waiting: no crash, no hang. }
  Mover := TFileMover.Create('');
  try
    for I := 1 to 3 do
      Mover.Add(MakeJob(faCopy, Src + 'nothing.jpg', Dst));
  finally
    Mover.Free;
  end;
  Check('freed with jobs waiting: fine', True);
end;

{ ---- uSortFolders ---- }

procedure TestFolders;
var
  F, G: TSortFolders;
  Ini: TMemIniFile;
  I: Integer;
  Keys: TStringList;
begin
  WriteLn('TSortFolders');
  F := TSortFolders.Create;
  G := TSortFolders.Create;
  Ini := TMemIniFile.Create(Root + 'test.ini');
  Keys := TStringList.Create;
  try
    Check('empty', F.Count = 0);
    Check('add: index 0', F.SetFolder(0, 'D:\Sorted\Good\') = 0);
    Check('trailing delimiter dropped', F.Slot(0).Folder = ExcludeTrailingPathDelimiter('D:\Sorted\Good\'),
      F.Slot(0).Folder);
    Check('add beyond Count: refused', F.SetFolder(5, 'D:\X') = -1);
    F.SetFolder(1, 'D:\Sorted\Bad');
    F.SetFolder(2, 'D:\Sorted\Maybe');
    Check('three slots', F.Count = 3);
    Check('colours differ', (F.Slot(0).Color <> F.Slot(1).Color) and (F.Slot(1).Color <> F.Slot(2).Color));
    Check('recent: newest first', (F.Recent.Count = 3) and (F.Recent[0] = 'D:\Sorted\Maybe'),
      F.Recent.Text);

    F.SetColor(1, scPurple);
    F.SetIcon(1, 'bad.ico');
    F.SetFolder(1, 'D:\Sorted\Reject');
    Check('replace: colour and icon stay', (F.Slot(1).Color = scPurple) and (F.Slot(1).Icon = 'bad.ico'));
    Check('replace: name follows', F.Slot(1).Name = FolderDisplayName('D:\Sorted\Reject'), F.Slot(1).Name);

    F.Move(2, 0);
    Check('move: last to first', (F.Slot(0).Folder = 'D:\Sorted\Maybe') and (F.Slot(2).Folder = 'D:\Sorted\Reject'));

    F.SaveToIni(Ini);
    G.LoadFromIni(Ini);
    Check('ini: same count', G.Count = F.Count);
    Check('ini: same folders', (G.Count = 3) and (G.Slot(0).Folder = F.Slot(0).Folder)
      and (G.Slot(2).Folder = F.Slot(2).Folder));
    Check('ini: colour and icon', (G.Count = 3) and (G.Slot(2).Color = scPurple) and (G.Slot(2).Icon = 'bad.ico'));
    Check('ini: recent folders', G.Recent.Count = F.Recent.Count);

    F.Remove(0);
    F.SaveToIni(Ini);
    Ini.ReadSection(ListSectionPrefix + '1', Keys);
    Check('ini: keys of a removed slot are gone', Keys.IndexOf('Slot3Folder') < 0, Keys.CommaText);
    Check('ini: the slots are in [DirList1]', Keys.IndexOf('Slot2Folder') >= 0, Keys.CommaText);
    G.LoadFromIni(Ini);
    Check('ini: two slots after remove', G.Count = 2);

    F.Clear;
    for I := 0 to MaxSortSlots + 3 do
      F.SetFolder(F.Count, Format('D:\S\%d', [I]));
    Check('at most MaxSortSlots', F.Count = MaxSortSlots);
    Check('recent: at most MaxRecentFolders', F.Recent.Count <= MaxRecentFolders);

    Check('ParseSlotColor', ParseSlotColor(SlotColorName(scOrange), scGrey) = scOrange);
    Check('ParseSlotColor: unknown -> default', ParseSlotColor('teal', scGrey) = scGrey);
    Check('ParseSlotColor: Pink (Day 27)', ParseSlotColor('pink', scGrey) = scPink);

    { Several lists (Day 27): [DirList<n>], the arrows, a new empty list
      after the last, then round again. }
    F.Clear;
    Check('arrows: nothing yet, not red', not F.NextIsNew(1) and not F.NextIsNew(-1));
    F.SetFolder(0, 'D:\A1');
    Check('lists: one', F.ListCount = 1);
    Check('arrows: one filled list, both red', F.NextIsNew(1) and F.NextIsNew(-1));
    F.CycleList(1);
    Check('lists: a new, empty one after the last', (F.ListCount = 2) and (F.Count = 0)
      and (F.ListIndex = 1));
    F.CycleList(1);
    Check('lists: an empty one is dropped, round to the first', (F.ListCount = 1)
      and (F.ListIndex = 0) and (F.Count = 1) and (F.Slot(0).Folder = 'D:\A1'));
    F.CycleList(-1);
    Check('lists: left from the first: a new one', (F.ListCount = 2) and (F.Count = 0));
    F.SetFolder(0, 'D:\B1');
    F.SetFolder(1, 'D:\B2');
    Check('arrows: on the second of two, right red, left not', F.NextIsNew(1)
      and not F.NextIsNew(-1));
    F.CycleList(1);
    Check('arrows: on the new list, neither red', not F.NextIsNew(1) and not F.NextIsNew(-1));
    Check('lists: the next one is new', (F.ListCount = 3) and (F.Count = 0) and (F.ListIndex = 2));
    F.CycleList(1);
    Check('lists: round to the first', (F.ListIndex = 0) and (F.Slot(0).Folder = 'D:\A1'));
    F.CycleList(1);
    Check('lists: the second kept its folders', (F.ListIndex = 1) and (F.Count = 2)
      and (F.Slot(1).Folder = 'D:\B2'));
    F.SaveToIni(Ini);
    Check('ini: [DirList2]', Ini.SectionExists(ListSectionPrefix + '2')
      and not Ini.SectionExists(ListSectionPrefix + '3'));
    Check('ini: List = 2', Ini.ReadInteger(SortSection, KEY_LIST, 0) = 2);
    G.LoadFromIni(Ini);
    Check('ini: lists read back', (G.ListCount = 2) and (G.ListIndex = 1) and (G.Count = 2)
      and (G.Slot(0).Folder = 'D:\B1'));

    { The old layout: slots in [Sort] are read as list 1 and moved. }
    Ini.EraseSection(ListSectionPrefix + '1');
    Ini.EraseSection(ListSectionPrefix + '2');
    Ini.WriteString(SortSection, 'Slot1Folder', 'D:\Old');
    Ini.WriteInteger(SortSection, KEY_LIST, 1);
    G.LoadFromIni(Ini);
    Check('old [Sort] slots read', (G.ListCount = 1) and (G.Count = 1) and (G.Slot(0).Folder = 'D:\Old'));
    G.SaveToIni(Ini);
    Check('old [Sort] slots moved to [DirList1]', (not Ini.ValueExists(SortSection, 'Slot1Folder'))
      and (Ini.ReadString(ListSectionPrefix + '1', 'Slot1Folder', '') = 'D:\Old'));

    { Rapid Selection: ten fixed slots, keys 1 .. 0; the list before comes back. }
    G.SetRapid(True, 'D:\Pics');
    Check('rapid: ten slots', (G.Count = RapidSlots) and G.Rapid);
    Check('rapid: Selection1 first, Selection0 last',
      (G.Slot(0).Folder = IncludeTrailingPathDelimiter('D:\Pics') + 'Selection1')
      and (G.Slot(9).Name = 'Selection0'), G.Slot(0).Folder);
    Check('rapid: labels 1 .. 0', (G.SlotLabel(0) = '1') and (G.SlotLabel(9) = '0'));
    Check('rapid: not changed by hand', G.SetFolder(G.Count, 'D:\X') = -1);
    G.CycleList(1);
    Check('rapid: the arrows do nothing', G.Count = RapidSlots);
    G.SaveToIni(Ini);
    Check('rapid: never written', Ini.ReadString(ListSectionPrefix + '1', 'Slot1Folder', '') = 'D:\Old');
    G.SetRapid(False, '');
    Check('rapid off: the list before', (not G.Rapid) and (G.Count = 1) and (G.Slot(0).Folder = 'D:\Old'));
    Check('FolderDisplayName', FolderDisplayName('D:\Sorted\Good') = 'Good',
      FolderDisplayName('D:\Sorted\Good'));
    Check('IconBaseName', IconBaseName('D:\Sorted\Good') = 'Good', IconBaseName('D:\Sorted\Good'));
    Check('IconBaseName of a drive: no colon', Pos(':', IconBaseName('D:\')) = 0, IconBaseName('D:\'));
  finally
    Keys.Free;
    Ini.Free;
    G.Free;
    F.Free;
  end;
end;

{ ---- Stage 2: icons ---- }

procedure TestWrite;
var
  J: TFileJob;
  R: TFileJobResult;
  Dir: string;
begin
  WriteLn('faWrite (Make icon)');
  Dir := Root + 'icons';
  J := Default(TFileJob);
  J.Action := faWrite;
  J.Kind := fjIcon;
  J.TargetDir := Dir;
  J.TargetName := 'Good.ico';
  J.CreateTarget := True;
  J.Data := TBytes.Create(1, 2, 3);
  R := ExecuteFileJob(J, Root + 'sorting.log');
  Check('write: folder made, file written', R.OK and FileExists(Dir + PathDelim + 'Good.ico'), R.Message);
  Check('write: nothing renamed the first time', R.RenamedTo = '');
  Check('write: size', R.Size = 3, IntToStr(R.Size));
  J.Data := TBytes.Create(4, 5, 6, 7);
  R := ExecuteFileJob(J, '');
  Check('write again: the old one is Good_previous.ico',
    R.OK and (ExtractFileName(R.RenamedTo) = 'Good_previous.ico')
    and FileExists(Dir + PathDelim + 'Good_previous.ico'), R.RenamedTo);
  Check('write again: the new one has the new content', R.Size = 4, IntToStr(R.Size));
  R := ExecuteFileJob(J, '');
  Check('third time: Good_previous_1.ico (nothing lost)',
    R.OK and (ExtractFileName(R.RenamedTo) = 'Good_previous_1.ico'), R.RenamedTo);
end;

type
  TByteList = record
    Data: TBytes;
  end;

procedure Put8(var B: TByteList; AValue: Integer);
begin
  SetLength(B.Data, Length(B.Data) + 1);
  B.Data[High(B.Data)] := Byte(AValue);
end;

procedure Put16(var B: TByteList; AValue: Integer);
begin
  Put8(B, AValue and $FF);
  Put8(B, (AValue shr 8) and $FF);
end;

procedure Put32(var B: TByteList; AValue: LongWord);
begin
  Put16(B, AValue and $FFFF);
  Put16(B, AValue shr 16);
end;

{ A DIB header for a W x H picture of ABpp bits. }
procedure PutDibHeader(var B: TByteList; W, H, ABpp, APalette: Integer);
begin
  Put32(B, 40);
  Put32(B, W);
  Put32(B, H * 2);
  Put16(B, 1);
  Put16(B, ABpp);
  Put32(B, 0);        { BI_RGB }
  Put32(B, 0);
  Put32(B, 0);
  Put32(B, 0);
  Put32(B, APalette);
  Put32(B, 0);
end;

{ 1.1: copy / cut / paste of a button between lists. }
procedure TestClip;
var
  F: TSortFolders;
  Why: string;
  I: Integer;
begin
  WriteLn('TSortFolders: copy / cut / paste');
  F := TSortFolders.Create;
  try
    F.SetFolder(0, 'D:\A');
    F.SetFolder(1, 'D:\B');
    F.SetFolder(2, 'D:\C');
    F.SetName(1, 'Bee');
    Check('nothing to paste at first', not F.HasClip and (F.PasteSlot(0, Why) = -1) and (Why <> ''), Why);
    F.CopySlot(1, False);
    Check('copied', F.HasClip and not F.ClipIsCut and (F.ClipName = 'Bee'));
    Check('a copy is not dimmed', not F.IsCutSlot(1));
    Check('a copy into its own list: refused (already there)', (F.PasteSlot(2, Why) = -1) and (Pos('already', Why) > 0), Why);
    F.CycleList(1);                     { a new, empty list }
    Check('on the new list', (F.ListIndex = 1) and (F.Count = 0), IntToStr(F.ListIndex));
    Check('pasted on top of the empty list', F.PasteSlot(-1, Why) = 0, Why);
    Check('with its name, colour and icon', (F.Count = 1) and (F.Slot(0).Name = 'Bee')
      and (F.Slot(0).Folder = 'D:\B'));
    Check('the copy stays to paste again', F.HasClip);
    F.CycleList(-1);
    Check('back on list 1: still three', (F.ListIndex = 0) and (F.Count = 3), IntToStr(F.Count));

    { Cut C, paste it in list 2 after Bee: it leaves list 1. }
    F.CopySlot(2, True);
    Check('cut: dimmed in its list', F.IsCutSlot(2) and not F.IsCutSlot(0));
    F.CycleList(1);
    Check('list 2', (F.ListIndex = 1) and (F.Count = 1), IntToStr(F.ListIndex) + ' ' + IntToStr(F.Count));
    Check('pasted after Bee', F.PasteSlot(0, Why) = 1, Why);
    Check('list 2: Bee, C', (F.Count = 2) and (F.Slot(1).Folder = 'D:\C'));
    Check('a cut is pasted once', not F.HasClip);
    F.CycleList(1);                     { round: list 1 again }
    F.CycleList(1);
    I := F.ListIndex;
    Check('list 1 has lost C', (F.Count = 2) and (F.Slot(0).Folder = 'D:\A') and (F.Slot(1).Folder = 'D:\B'),
      IntToStr(I) + ' ' + IntToStr(F.Count));

    { Cut within one list: a move. }
    F.CopySlot(0, True);
    Check('cut A, pasted after B: a move', (F.PasteSlot(1, Why) = 1) and (F.Count = 2)
      and (F.Slot(0).Folder = 'D:\B') and (F.Slot(1).Folder = 'D:\A'), Why);
    F.CopySlot(0, True);
    F.CancelCut;
    Check('cancelled: nothing dimmed, nothing to paste', not F.HasClip and not F.IsCutSlot(0));
  finally
    F.Free;
  end;
end;

{ 1.1: a settings file written safely. }
procedure TestSafeFile;
var
  Name, Text, Error: string;
begin
  WriteLn('uSafeFile');
  Name := Root + 'safe.ini';
  Check('new file written', WriteTextFileSafely(Name, '[A]' + LineEnding + 'x=1' + LineEnding, Error), Error);
  Check('read back', ReadTextFile(Name, Text) and (Text = '[A]' + LineEnding + 'x=1' + LineEnding), Text);
  Check('replaced', WriteTextFileSafely(Name, '[B]' + LineEnding, Error) and ReadTextFile(Name, Text)
    and (Text = '[B]' + LineEnding), Text);
  Check('no .tmp left', not FileExists(Name + '.tmp'));
  Check('a folder that is not there: False, said why',
    not WriteTextFileSafely(Root + 'no such folder' + PathDelim + 'x.ini', 'x', Error) and (Error <> ''), Error);
  Check('the old file stays when the write fails', ReadTextFile(Name, Text) and (Text = '[B]' + LineEnding));
  Check('a UTF-8 BOM is dropped', WriteTextFileSafely(Name, #$EF#$BB#$BF'[C]', Error)
    and ReadTextFile(Name, Text) and (Text = '[C]'), Text);
end;

{ 1.1: entries written from pixels. }
procedure TestIconEntries;
var
  Pixels, Back: TIconPixels;
  Dib, PngData, Written: TBytes;
  Entries: TIconEntries;
  Pictures: array of TBytes;
  Sizes: array of Integer;
  Stream: TMemoryStream;
  Image: TFPMemoryImage;
  Reader: TFPReaderPNG;
  Col: TFPColor;
  X, Y: Integer;
  Same: Boolean;
begin
  WriteLn('uIconFile: entries written (1.1)');
  { 3 x 2: opaque colours, one fully transparent pixel. }
  Pixels.Width := 3;
  Pixels.Height := 2;
  SetLength(Pixels.Data, 6);
  Pixels.Data[0] := $FFFF0000;   { red }
  Pixels.Data[1] := $FF00FF00;   { green }
  Pixels.Data[2] := $FF0000FF;   { blue }
  Pixels.Data[3] := $00000000;   { transparent }
  Pixels.Data[4] := $80FFFFFF;   { white, half }
  Pixels.Data[5] := $FF123456;

  Dib := IconDibEntry(Pixels);
  Check('DIB: header 40, height doubled, 32 bit',
    (Length(Dib) >= 40) and (Dib[0] = 40) and (Dib[4] = 3) and (Dib[8] = 4) and (Dib[14] = 32));
  Check('DIB: size = header + pixels + mask', Length(Dib) = 40 + 6 * 4 + 2 * 4, IntToStr(Length(Dib)));

  { Opaque picture as PNG: still RGBA. }
  PngData := IconPngEntry(Pixels);
  Check('PNG: colour type 6 (RGBA), 8 bit', (Length(PngData) > 33) and (PngData[24] = 8) and (PngData[25] = 6));

  SetLength(Pictures, 2);
  Pictures[0] := Dib;
  Pictures[1] := PngData;
  SetLength(Sizes, 2);
  Sizes[0] := 3;
  Sizes[1] := 3;
  Stream := TMemoryStream.Create;
  try
    WriteIconFile(Stream, Pictures, Sizes);
    SetLength(Written, Stream.Size);
    Move(Stream.Memory^, Written[0], Stream.Size);
  finally
    Stream.Free;
  end;
  Check('written icon: a DIB and a PNG entry', ReadIconDirectory(Written, Entries)
    and (Length(Entries) = 2) and not Entries[0].IsPng and Entries[1].IsPng
    and (Entries[0].BitCount = 32));
  if Length(Entries) <> 2 then
    Exit;
  Same := DecodeIconDib(Written, Entries[0], Back) and (Back.Width = 3) and (Back.Height = 2)
    and (Length(Back.Data) = 6);
  if Same then
    for X := 0 to 5 do
      Same := Same and (Back.Data[X] = Pixels.Data[X]);
  Check('DIB read back: the same pixels (top row first)', Same);

  { The PNG through the FPC reader. }
  Image := TFPMemoryImage.Create(0, 0);
  Reader := TFPReaderPNG.Create;
  Stream := TMemoryStream.Create;
  try
    Stream.WriteBuffer(PngData[0], Length(PngData));
    Stream.Position := 0;
    Same := True;
    try
      Image.LoadFromStream(Stream, Reader);
    except
      Same := False;
    end;
    Same := Same and (Image.Width = 3) and (Image.Height = 2);
    if Same then
      for Y := 0 to 1 do
        for X := 0 to 2 do
        begin
          Col := Image.Colors[X, Y];
          Same := Same and ((LongWord(Col.Alpha shr 8) shl 24 or LongWord(Col.Red shr 8) shl 16
            or LongWord(Col.Green shr 8) shl 8 or LongWord(Col.Blue shr 8)) = Pixels.Data[Y * 3 + X]);
        end;
    Check('PNG read back by FPReadPNG: the same pixels and alpha', Same);
  finally
    Stream.Free;
    Reader.Free;
    Image.Free;
  end;
end;

procedure TestIconFile;
var
  Dib32, Dib4, Png, Ico: TByteList;
  Entries: TIconEntries;
  Pixels: TIconPixels;
  I, Off: Integer;
  Idx: Integer;
  Stream: TMemoryStream;
  Pngs: array of TBytes;
  Sizes: array of Integer;
  Written: TBytes;
begin
  WriteLn('uIconFile');
  { 2 x 2, 32 bit with alpha: rows bottom-up. Bottom row: red, green;
    top row: blue (half transparent), white. Then an AND mask (ignored:
    there is alpha). }
  Dib32.Data := nil;
  PutDibHeader(Dib32, 2, 2, 32, 0);
  Put32(Dib32, $FFFF0000);  { bottom left: red }
  Put32(Dib32, $FF00FF00);  { bottom right: green }
  Put32(Dib32, $800000FF);  { top left: blue, alpha 128 }
  Put32(Dib32, $FFFFFFFF);  { top right: white }
  Put32(Dib32, 0);          { AND mask, 2 rows of 4 bytes }
  Put32(Dib32, 0);

  { 2 x 2, 4 bit, palette 0 = black, 1 = red; top left transparent by
    the AND mask. XOR rows (4 bytes each): bottom row 1,0; top row 0,1. }
  Dib4.Data := nil;
  PutDibHeader(Dib4, 2, 2, 4, 2);
  Put32(Dib4, $00000000);   { palette 0: black }
  Put32(Dib4, $00FF0000);   { palette 1: red }
  Put8(Dib4, $10); Put8(Dib4, 0); Put8(Dib4, 0); Put8(Dib4, 0);   { bottom: 1, 0 }
  Put8(Dib4, $01); Put8(Dib4, 0); Put8(Dib4, 0); Put8(Dib4, 0);   { top: 0, 1 }
  Put32(Dib4, 0);                                                 { AND bottom: none }
  Put8(Dib4, $80); Put8(Dib4, 0); Put8(Dib4, 0); Put8(Dib4, 0);   { AND top: left }

  { A "PNG" entry: the signature and an IHDR saying 64 x 64 (only the
    header is read here). }
  Png.Data := nil;
  Put8(Png, $89); Put8(Png, Ord('P')); Put8(Png, Ord('N')); Put8(Png, Ord('G'));
  Put8(Png, 13); Put8(Png, 10); Put8(Png, 26); Put8(Png, 10);
  Put8(Png, 0); Put8(Png, 0); Put8(Png, 0); Put8(Png, 13);
  Put8(Png, Ord('I')); Put8(Png, Ord('H')); Put8(Png, Ord('D')); Put8(Png, Ord('R'));
  Put8(Png, 0); Put8(Png, 0); Put8(Png, 0); Put8(Png, 64);
  Put8(Png, 0); Put8(Png, 0); Put8(Png, 0); Put8(Png, 64);

  Ico.Data := nil;
  Put16(Ico, 0);
  Put16(Ico, 1);
  Put16(Ico, 3);
  Off := 6 + 3 * 16;
  { entry 0: 32-bit 2x2 }
  Put8(Ico, 2); Put8(Ico, 2); Put8(Ico, 0); Put8(Ico, 0); Put16(Ico, 1); Put16(Ico, 32);
  Put32(Ico, Length(Dib32.Data)); Put32(Ico, Off);
  Inc(Off, Length(Dib32.Data));
  { entry 1: 4-bit 2x2 (depth 0 in the directory: the DIB says 4) }
  Put8(Ico, 2); Put8(Ico, 2); Put8(Ico, 2); Put8(Ico, 0); Put16(Ico, 1); Put16(Ico, 0);
  Put32(Ico, Length(Dib4.Data)); Put32(Ico, Off);
  Inc(Off, Length(Dib4.Data));
  { entry 2: PNG, the directory says 0 x 0 (= 256), the header 64 }
  Put8(Ico, 0); Put8(Ico, 0); Put8(Ico, 0); Put8(Ico, 0); Put16(Ico, 1); Put16(Ico, 32);
  Put32(Ico, Length(Png.Data)); Put32(Ico, Off);
  for I := 0 to High(Dib32.Data) do Put8(Ico, Dib32.Data[I]);
  for I := 0 to High(Dib4.Data) do Put8(Ico, Dib4.Data[I]);
  for I := 0 to High(Png.Data) do Put8(Ico, Png.Data[I]);

  Check('directory: three entries', ReadIconDirectory(Ico.Data, Entries) and (Length(Entries) = 3),
    IntToStr(Length(Entries)));
  if Length(Entries) <> 3 then
    Exit;
  Check('entry 1: depth from the DIB (4)', Entries[1].BitCount = 4, IntToStr(Entries[1].BitCount));
  Check('entry 2: PNG, 64 x 64 from its header', Entries[2].IsPng and (Entries[2].Width = 64),
    IntToStr(Entries[2].Width));
  Idx := ChooseIconEntry(Entries, 2);
  Check('size 2: the 32-bit 2x2 (best depth of the smallest large enough)', Idx = 0, IntToStr(Idx));
  Idx := ChooseIconEntry(Entries, 32);
  Check('size 32: the 64 px PNG (smallest at least 32)', Idx = 2, IntToStr(Idx));
  Idx := ChooseIconEntry(Entries, 128);
  Check('size 128: none that large, the largest (64 px)', Idx = 2, IntToStr(Idx));

  Check('32-bit: decoded', DecodeIconDib(Ico.Data, Entries[0], Pixels)
    and (Pixels.Width = 2) and (Pixels.Height = 2));
  if Length(Pixels.Data) = 4 then
  begin
    Check('32-bit: top left blue, half transparent (top row first)', Pixels.Data[0] = $800000FF,
      IntToHex(Pixels.Data[0], 8));
    Check('32-bit: bottom right green', Pixels.Data[3] = $FF00FF00, IntToHex(Pixels.Data[3], 8));
  end;
  Check('4-bit: decoded', DecodeIconDib(Ico.Data, Entries[1], Pixels) and (Length(Pixels.Data) = 4));
  if Length(Pixels.Data) = 4 then
  begin
    Check('4-bit: top left transparent (AND mask)', Pixels.Data[0] = 0, IntToHex(Pixels.Data[0], 8));
    Check('4-bit: top right red, opaque', Pixels.Data[1] = $FFFF0000, IntToHex(Pixels.Data[1], 8));
    Check('4-bit: bottom left red', Pixels.Data[2] = $FFFF0000, IntToHex(Pixels.Data[2], 8));
    Check('4-bit: bottom right black, opaque', Pixels.Data[3] = $FF000000, IntToHex(Pixels.Data[3], 8));
  end;
  Check('a PNG entry is not decoded as DIB', not DecodeIconDib(Ico.Data, Entries[2], Pixels));

  Check('not an icon: False', not ReadIconDirectory(TBytes.Create(1, 2, 3, 4, 5, 6, 7), Entries));
  Check('cut short: False', not ReadIconDirectory(Copy(Ico.Data, 0, 20), Entries));

  { Written and read back. }
  SetLength(Pngs, 2);
  Pngs[0] := Copy(Png.Data, 0, Length(Png.Data));
  Pngs[1] := Copy(Png.Data, 0, Length(Png.Data));
  SetLength(Sizes, 2);
  Sizes[0] := 64;
  Sizes[1] := 256;
  Stream := TMemoryStream.Create;
  try
    WriteIconFile(Stream, Pngs, Sizes);
    SetLength(Written, Stream.Size);
    Move(Stream.Memory^, Written[0], Stream.Size);
  finally
    Stream.Free;
  end;
  Check('WriteIconFile: read back, two PNG entries',
    ReadIconDirectory(Written, Entries) and (Length(Entries) = 2) and Entries[0].IsPng
    and Entries[1].IsPng);
  Check('WriteIconFile: 256 is stored as 0 in the directory', Written[6 + 16] = 0);
end;

begin
  PassCount := 0;
  FailCount := 0;
  WriteLn('VersariteViewer sorting test (Phase G)');
  Root := ExtractFilePath(ParamStr(0)) + 'sorttest' + PathDelim;
  RemoveTree(Root);
  ForceDirectories(Root);
  try
    TestUniqueName;
    TestJobs;
    TestThread;
    TestFolders;
    TestWrite;
    TestIconFile;
    TestIconEntries;
    TestSafeFile;
    TestClip;
  finally
    RemoveTree(Root);
  end;

  WriteLn;
  WriteLn(Format('%d passed, %d failed', [PassCount, FailCount]));
  if FailCount > 0 then
    ExitCode := 1;
end.
