program TestCalibrations;

{
  Checks the calibration record of the microscopy edition (M3a, Day 25),
  uCalibrations:
  - µm per pixel: a camera (fixed), a confocal (scaled by width and
    zoom), records that are not usable;
  - the list: add, replace by name, find by objective, rename (names
    stay unique), delete;
  - calibrations.ini: written and read back (numbers with '.'), broken
    and doubled entries skipped, removed records' sections erased, a
    missing file = an empty list;
  - the scale in a saved file (Day 26, uImageFileScale): a TIFF written
    ImageJ's way and a PNG's "MView scale" read back; a TIFF without a
    scale, an ImageJ one in nm, a PNG with a pHYs only (a print size).

  Build and run with build_test.bat (plain fpc).
}

{$mode ObjFPC}{$H+}

uses
  Classes,
  SysUtils,
  IniFiles,
  Math,
  uCalibrations,
  uImageFileScale,
  uFijiFind;

var
  PassCount, FailCount: Integer;

procedure Check(const ALabel: string; ACondition: Boolean; const ADetail: string = '');
begin
  if ACondition then
  begin
    Inc(PassCount);
    WriteLn('  ok    ', ALabel);
  end
  else
  begin
    Inc(FailCount);
    if ADetail <> '' then
      WriteLn('  FAIL  ', ALabel, '  (', ADetail, ')')
    else
      WriteLn('  FAIL  ', ALabel);
  end;
end;

function Near(A, B: Double): Boolean;
begin
  Result := Abs(A - B) <= 1e-9 * Max(1.0, Abs(B));
end;

function Camera: TCalibration;
begin
  Result := Default(TCalibration);
  Result.Name := 'Zeiss 20x';
  Result.Microscope := 'Axio';
  Result.Objective := 'Plan-Apochromat 20x/0.8';
  Result.Confocal := False;
  Result.ReferenceMicrons := 100;
  Result.ReferencePixels := 250;
  Result.ReferenceWidth := 2048;
  Result.ReferenceZoom := 0;
  Result.Date := '2026-10-07';
  Result.Note := 'stage micrometer';
end;

function Confocal: TCalibration;
begin
  Result := Default(TCalibration);
  Result.Name := 'SP8 40x oil';
  Result.Microscope := 'TCS SP8';
  Result.Objective := 'HC PL APO CS2 40x/1.30 OIL';
  Result.Confocal := True;
  Result.ReferenceMicrons := 100;
  Result.ReferencePixels := 873.2;
  Result.ReferenceWidth := 1024;
  Result.ReferenceZoom := 1;
  Result.Date := '2026-10-07';
end;

procedure TestMath;
var
  C: TCalibration;
begin
  WriteLn('µm per pixel');
  C := Camera;
  Check('camera: 100 µm / 250 px = 0.4', Near(UmPerPixel(C, 2048, 0), 0.4));
  Check('camera: not scaled by width or zoom', Near(UmPerPixel(C, 512, 3), 0.4));
  C := Confocal;
  Check('confocal at its own width and zoom', Near(UmPerPixel(C, 1024, 1), 100 / 873.2));
  Check('confocal at 512 px: twice', Near(UmPerPixel(C, 512, 1), 2 * 100 / 873.2));
  Check('confocal at zoom 2: half', Near(UmPerPixel(C, 1024, 2), 0.5 * 100 / 873.2));
  Check('confocal, zoom unknown (0): width only', Near(UmPerPixel(C, 2048, 0), 0.5 * 100 / 873.2));
  C.ReferenceZoom := 0;
  Check('confocal, no reference zoom: width only', Near(UmPerPixel(C, 1024, 4), 100 / 873.2));
  C := Confocal;
  C.ReferenceWidth := 0;
  Check('confocal without a reference width: not usable', (not CalibrationValid(C))
    and (UmPerPixel(C, 1024, 1) = 0));
  C := Camera;
  C.ReferencePixels := 0;
  Check('no pixels: not usable', not CalibrationValid(C));
  C := Camera;
  C.Name := '  ';
  Check('no name: not usable', not CalibrationValid(C));
  Check('text: camera in px/µm', Pos('2.5 px/', CalibrationValueText(Camera)) = 1,
    CalibrationValueText(Camera));
  Check('text: confocal in µm/px with width and zoom',
    (Pos('0.1145 ', CalibrationValueText(Confocal)) = 1)
    and (Pos('1024 px', CalibrationValueText(Confocal)) > 0)
    and (Pos('zoom 1', CalibrationValueText(Confocal)) > 0), CalibrationValueText(Confocal));
end;

procedure TestList;
var
  L: TCalibrationList;
  C: TCalibration;
begin
  WriteLn('The list');
  L := TCalibrationList.Create;
  try
    Check('empty', L.Count = 0);
    Check('add camera', L.Put(Camera) = 0);
    Check('add confocal', L.Put(Confocal) = 1);
    C := Confocal;
    C.ReferencePixels := 900;
    C.Name := 'sp8 40X OIL ';
    Check('same name (case, spaces): replaced', (L.Put(C) = 1) and (L.Count = 2)
      and Near(L.Item(1).ReferencePixels, 900));
    Check('not usable: refused', L.Put(Default(TCalibration)) = -1);
    Check('by objective', L.IndexOfObjective('TCS SP8', 'hc pl apo cs2  40x/1.30 oil') = 1);
    Check('by objective, microscope unknown', L.IndexOfObjective('', 'Plan-Apochromat 20x/0.8') = 0);
    Check('by objective, other microscope: none', L.IndexOfObjective('Stellaris', 'Plan-Apochromat 20x/0.8') = -1);
    Check('no objective: none', L.IndexOfObjective('TCS SP8', '') = -1);
    L.Rename(0, 'SP8 40x oil');
    Check('rename to a taken name: refused', L.Item(0).Name = 'Zeiss 20x');
    L.Rename(0, 'Axio 20x');
    Check('rename', L.IndexOfName('axio 20x') = 0);
    L.Delete(0);
    Check('delete', (L.Count = 1) and (L.Item(0).Microscope = 'TCS SP8'));
    L.Delete(5);
    Check('delete out of range: nothing', L.Count = 1);
  finally
    L.Free;
  end;
end;

procedure TestFile(const ADir: string);
var
  L, M: TCalibrationList;
  FileName: string;
  Ini: TMemIniFile;
begin
  WriteLn('calibrations.ini');
  FileName := ADir + 'calibrations.ini';
  DeleteFile(FileName);
  L := TCalibrationList.Create;
  M := TCalibrationList.Create;
  try
    M.LoadFromFile(FileName);
    Check('missing file: empty list', M.Count = 0);
    L.Put(Camera);
    L.Put(Confocal);
    L.SaveToFile(FileName);
    M.LoadFromFile(FileName);
    Check('read back: two', M.Count = 2);
    Check('  every field', (M.Item(1).Name = 'SP8 40x oil') and (M.Item(1).Microscope = 'TCS SP8')
      and (M.Item(1).Objective = 'HC PL APO CS2 40x/1.30 OIL') and M.Item(1).Confocal
      and Near(M.Item(1).ReferenceMicrons, 100) and Near(M.Item(1).ReferencePixels, 873.2)
      and (M.Item(1).ReferenceWidth = 1024) and Near(M.Item(1).ReferenceZoom, 1)
      and (M.Item(1).Date = '2026-10-07') and (M.Item(0).Note = 'stage micrometer')
      and (not M.Item(0).Confocal));
    Ini := TMemIniFile.Create(FileName);
    try
      Check('numbers written with "."', Ini.ReadString('Calibration2', 'ReferencePixels', '') = '873.2',
        Ini.ReadString('Calibration2', 'ReferencePixels', ''));
      { By hand: a decimal comma, a broken entry, a doubled name. }
      Ini.WriteString('Calibration2', 'ReferencePixels', '873,5');
      Ini.WriteString('Calibration3', 'Name', 'broken');
      Ini.WriteString('Calibration3', 'ReferenceMicrons', 'abc');
      Ini.WriteString('Calibration4', 'Name', 'Zeiss 20x');
      Ini.WriteString('Calibration4', 'ReferenceMicrons', '1');
      Ini.WriteString('Calibration4', 'ReferencePixels', '1');
      Ini.UpdateFile;
    finally
      Ini.Free;
    end;
    M.LoadFromFile(FileName);
    Check('decimal comma by hand: read', Near(M.Item(1).ReferencePixels, 873.5));
    Check('broken and doubled entries: skipped', M.Count = 2);
    M.Delete(0);
    M.SaveToFile(FileName);
    Ini := TMemIniFile.Create(FileName);
    try
      Check('removed records: sections erased', Ini.SectionExists('Calibration1')
        and not Ini.SectionExists('Calibration2') and not Ini.SectionExists('Calibration3')
        and not Ini.SectionExists('Calibration4'));
    finally
      Ini.Free;
    end;
  finally
    M.Free;
    L.Free;
  end;
end;

{ A PNG of a signature, an IHDR (1 x 1) and an IEND: enough for its
  chunks. }
function TinyPng: TBytes;
const
  Bytes: array[0..44] of Byte = (137, 80, 78, 71, 13, 10, 26, 10,
    0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119, 83, 222,
    0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130);
begin
  SetLength(Result, Length(Bytes));
  Move(Bytes[0], Result[0], Length(Bytes));
end;

function ScaleOf(const AData: TBytes; out AUmX, AUmY: Double): Boolean;
var
  Stream: TBytesStream;
begin
  Stream := TBytesStream.Create(AData);
  try
    Result := ReadStreamScale(Stream, AUmX, AUmY);
  finally
    Stream.Free;
  end;
end;

procedure TestFileScale(const ADir: string);
const
  Phys300: array[0..20] of Byte = (0, 0, 0, 9, 112, 72, 89, 115, 0, 0, 46, 35, 0, 0, 46, 35, 1,
    120, 165, 63, 118);
var
  RGB, Data: TBytes;
  UmX, UmY: Double;
  Desc: AnsiString;
  I, P: Integer;
begin
  WriteLn('The scale in a saved file (Day 26)');
  SetLength(RGB, 4 * 3 * 3);
  for I := 0 to High(RGB) do
    RGB[I] := I;
  Data := MakeRgbTiff(4, 3, RGB, 0.1173, 0.25);
  Check('TIFF made', Length(Data) > 36 + Length(RGB), IntToStr(Length(Data)));
  Check('TIFF: its scale read back (0.1173 x 0.25 µm)', ScaleOf(Data, UmX, UmY)
    and (Abs(UmX - 0.1173) < 1e-6) and (Abs(UmY - 0.25) < 1e-6),
    FloatToStr(UmX) + ' x ' + FloatToStr(UmY));
  Check('TIFF: the pixels at the end, as given',
    CompareMem(@Data[Length(Data) - Length(RGB)], @RGB[0], Length(RGB)));
  Data := MakeRgbTiff(4, 3, RGB, 0, 0);
  Check('TIFF without a scale: none read', not ScaleOf(Data, UmX, UmY));
  Data := MakeRgbTiff(4, 3, RGB, 0.5, 0.5);
  { The description's unit changed to nm: the same numbers, 1000 times
    smaller. }
  Desc := 'unit=micron';
  for I := 0 to Length(Data) - Length(Desc) do
    if CompareMem(@Data[I], @Desc[1], Length(Desc)) then
    begin
      P := I + 5;
      Data[P] := Ord('n');
      Data[P + 1] := Ord('m');
      Data[P + 2] := 10;      { the line ends there }
      Break;
    end;
  Check('ImageJ unit nm: 0.0005 µm', ScaleOf(Data, UmX, UmY) and (Abs(UmX - 0.0005) < 1e-9),
    FloatToStr(UmX));
  Data := AddPngPixelSize(TinyPng, 0.1173, 0.25);
  Check('PNG: pHYs and the MView scale added (after IHDR)', (Length(Data) > Length(TinyPng) + 21)
    and (Data[37] = Ord('p')) and (Data[38] = Ord('H')) and (Data[39] = Ord('Y'))
    and (Data[40] = Ord('s')));
  Check('PNG: its scale read back exactly (0.1173 x 0.25 µm)', ScaleOf(Data, UmX, UmY)
    and (Abs(UmX - 0.1173) < 1e-12) and (Abs(UmY - 0.25) < 1e-12), FloatToStr(UmX));
  Check('PNG without them: none', not ScaleOf(TinyPng, UmX, UmY));
  { A pHYs alone - 300 dpi from an image program - is a print size, no
    scale. }
  Data := TinyPng;
  SetLength(Data, Length(Data) + Length(Phys300));
  Move(Data[33], Data[33 + Length(Phys300)], Length(TinyPng) - 33);
  Move(Phys300[0], Data[33], Length(Phys300));
  Check('PNG with a pHYs only (300 dpi): no scale', not ScaleOf(Data, UmX, UmY));
  Check('not an image: none', not ScaleOf(RGB, UmX, UmY));
end;

{ 1.1: "Open in Fiji" - finding Fiji, the TIFF's name. }
procedure TestFijiFind(const ADir: string);
var
  Home, App, Exe: string;
  F: TextFile;
  Folders: TStringArray;
begin
  WriteLn('Finding Fiji');
  Home := ADir + 'home' + PathDelim;
  { A Fiji left from an earlier run goes first. }
  SysUtils.DeleteFile(Home + 'Desktop' + PathDelim + 'Fiji.app' + PathDelim + 'ImageJ-win64.exe');
  ForceDirectories(Home + 'Desktop');
  Check('nothing there: none', FindFijiProgram(Home, '', '') = '');
  Folders := FijiCandidateFolders(Home, 'L', 'P');
  Check('candidates: C:\Fiji.app first', (Length(Folders) > 0) and (Folders[0] = 'C:\Fiji.app'),
    Folders[0]);
  Check('candidates: 14 folders', Length(Folders) = 14, IntToStr(Length(Folders)));
  App := Home + 'Desktop' + PathDelim + 'Fiji.app' + PathDelim;
  ForceDirectories(App);
  Check('an empty Fiji.app: none', FijiProgramIn(App) = '');
  Exe := App + 'ImageJ-win64.exe';
  AssignFile(F, Exe);
  Rewrite(F);
  WriteLn(F, 'x');
  CloseFile(F);
  Check('Fiji.app on the desktop: found', FindFijiProgram(Home, '', '') = Exe,
    FindFijiProgram(Home, '', ''));
  Check('program names', IsFijiProgramName('C:\x\ImageJ-win64.exe')
    and IsFijiProgramName('fiji-windows-x64.exe') and not IsFijiProgramName('notepad.exe'));
  Check('tiff name: plain', FijiTiffName('cells', '_201530') = 'cells_201530.tif',
    FijiTiffName('cells', '_201530'));
  Check('tiff name: a .lif image', FijiTiffName('221107.lif|Series009', '') = '221107.lif_Series009.tif',
    FijiTiffName('221107.lif|Series009', ''));
  Check('tiff name: no .tif twice', FijiTiffName('stack.tif', '_1') = 'stack_1.tif',
    FijiTiffName('stack.tif', '_1'));
  Check('tiff name: bad characters', FijiTiffName('a:b*c?', '') = 'a_b_c_.tif', FijiTiffName('a:b*c?', ''));
  Check('tiff name: empty', FijiTiffName('', '') = 'image.tif');
end;

var
  TempDir: string;
begin
  PassCount := 0;
  FailCount := 0;
  WriteLn('Versarite Image Lab calibration record test (M3a)');
  TempDir := IncludeTrailingPathDelimiter(GetTempDir) + 'mviewlab_cal_test' + PathDelim;
  ForceDirectories(TempDir);
  TestMath;
  TestList;
  TestFile(TempDir);
  TestFileScale(TempDir);
  TestFijiFind(TempDir);
  WriteLn;
  WriteLn(Format('%d passed, %d failed', [PassCount, FailCount]));
  if FailCount > 0 then
    ExitCode := 1;
end.
