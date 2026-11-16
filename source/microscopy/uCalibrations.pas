unit uCalibrations;

{
  Unit: uCalibrations

  Purpose
  -------
  The calibration record (M3a, Day 25, user): a list that links a
  microscope / objective combination to a reference measurement of µm
  against pixels. For images that carry no scale of their own (the
  exported TIFFs: 72 dpi, no µm anywhere).
  Spec: specs\microscopy\Microscopy_Edition_Specification_v0.1.md §7.1.

  The file
  --------
  calibrations.ini in the program's folder (user: a file of its own -
  calibrations belong to the microscope, not to one installation; copy
  it to another PC or give it to colleagues). One section per record:

      [Calibration1]
      Name=SP8 40x oil
      Microscope=TCS SP8
      Objective=HC PL APO CS2 40x/1.30 OIL
      Confocal=1
      ReferenceMicrons=100
      ReferencePixels=873.2
      ReferenceWidth=1024
      ReferenceZoom=1
      Date=2026-10-07
      Note=stage micrometer

  Numbers with a '.' whatever the Windows settings.

  Confocal or not (user)
  ----------------------
  Confocal: a scanning microscope's µm per pixel changes with the scan
  format (the image width) and the zoom, so the record keeps both and
  UmPerPixel scales: µm/px = (µm/px measured) x (reference width / width)
  x (reference zoom / zoom). Not confocal (a camera): a fixed number of
  pixels per µm, no scaling.

  Owns
  ----
  TCalibrationList: the records, in the file's order.

  Does NOT
  --------
  - Choose one for an image (uImageScale), draw anything, or measure.

  Threads
  -------
  A list is used by one thread at a time (the UI).

  Uses (MView units)
  ------------------
  Libraries:      Classes, SysUtils, IniFiles, Math

  Used by
  -------
  uImageScale; test\TestCalibrations.lpr
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  IniFiles,
  Math;

const
  CalibrationFileName = 'calibrations.ini';
  MaxCalibrations = 200;

type
  TCalibration = record
    Name: string;           { shown in the selector; unique in the list }
    Microscope: string;     { 'TCS SP8'; '' = unknown }
    Objective: string;      { 'HC PL APO CS2 40x/1.30 OIL'; '' = unknown }
    Confocal: Boolean;
    ReferenceMicrons: Double;   { the known length }
    ReferencePixels: Double;    { measured over it }
    ReferenceWidth: Integer;    { the image's width then (confocal) }
    ReferenceZoom: Double;      { the zoom then (confocal); 0 = unknown }
    Date: string;               { 'yyyy-mm-dd' }
    Note: string;
  end;

  TCalibrationList = class(TObject)
  private
    FItems: array of TCalibration;
  public
    function Count: Integer;
    function Item(AIndex: Integer): TCalibration;
    { -1 if none of that name (case ignored). }
    function IndexOfName(const AName: string): Integer;
    { The first record for this objective (and microscope, when both
      know one); -1 if none. Case and repeated spaces ignored. }
    function IndexOfObjective(const AMicroscope, AObjective: string): Integer;
    { Adds, or replaces the record of the same name. The index; -1 if
      the record is not usable (CalibrationValid) or the list is full. }
    function Put(const ACalibration: TCalibration): Integer;
    procedure Delete(AIndex: Integer);
    procedure Rename(AIndex: Integer; const ANewName: string);
    procedure Clear;
    { A missing file is an empty list. }
    procedure LoadFromFile(const AFileName: string);
    procedure SaveToFile(const AFileName: string);
    procedure LoadFromIni(AIni: TCustomIniFile);
    procedure SaveToIni(AIni: TCustomIniFile);
  end;

{ A name, a positive length and pixel count; confocal also a width. }
function CalibrationValid(const ACalibration: TCalibration): Boolean;
{ µm per pixel for an image AWidth pixels wide taken at AZoom (0 = not
  known: then no zoom scaling). 0 if the record is not usable. }
function UmPerPixel(const ACalibration: TCalibration; AWidth: Integer; AZoom: Double): Double;
{ For the settings tab and the selector: '0.1145 µm/px' (confocal) or
  '8.73 px/µm' (camera). }
function CalibrationValueText(const ACalibration: TCalibration): string;
{ calibrations.ini next to the program. }
function DefaultCalibrationFile: string;

implementation

uses
  uSafeFile;

var
  Dot: TFormatSettings;

function Squash(const AText: string): string;
var
  I: Integer;
begin
  Result := LowerCase(Trim(AText));
  I := Pos('  ', Result);
  while I > 0 do
  begin
    Delete(Result, I, 1);
    I := Pos('  ', Result);
  end;
end;

function CalibrationValid(const ACalibration: TCalibration): Boolean;
begin
  Result := (Trim(ACalibration.Name) <> '') and (ACalibration.ReferenceMicrons > 0)
    and (ACalibration.ReferencePixels > 0)
    and ((not ACalibration.Confocal) or (ACalibration.ReferenceWidth > 0));
end;

function UmPerPixel(const ACalibration: TCalibration; AWidth: Integer; AZoom: Double): Double;
begin
  Result := 0;
  if not CalibrationValid(ACalibration) then
    Exit;
  Result := ACalibration.ReferenceMicrons / ACalibration.ReferencePixels;
  if not ACalibration.Confocal then
    Exit;                       { a camera: fixed (user) }
  if AWidth > 0 then
    Result := Result * ACalibration.ReferenceWidth / AWidth;
  if (AZoom > 0) and (ACalibration.ReferenceZoom > 0) then
    Result := Result * ACalibration.ReferenceZoom / AZoom;
end;

function CalibrationValueText(const ACalibration: TCalibration): string;
begin
  if not CalibrationValid(ACalibration) then
    Exit('not usable');
  if ACalibration.Confocal then
    Result := FormatFloat('0.0000', ACalibration.ReferenceMicrons / ACalibration.ReferencePixels, Dot)
      + ' µm/px at ' + IntToStr(ACalibration.ReferenceWidth) + ' px'
  else
    Result := FormatFloat('0.###', ACalibration.ReferencePixels / ACalibration.ReferenceMicrons, Dot)
      + ' px/µm';
  if ACalibration.Confocal and (ACalibration.ReferenceZoom > 0) then
    Result := Result + ', zoom ' + FormatFloat('0.##', ACalibration.ReferenceZoom, Dot);
end;

function DefaultCalibrationFile: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + CalibrationFileName;
end;

{ TCalibrationList }

function TCalibrationList.Count: Integer;
begin
  Result := Length(FItems);
end;

function TCalibrationList.Item(AIndex: Integer): TCalibration;
begin
  Result := FItems[AIndex];
end;

function TCalibrationList.IndexOfName(const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FItems) do
    if SameText(Trim(FItems[I].Name), Trim(AName)) then
      Exit(I);
  Result := -1;
end;

function TCalibrationList.IndexOfObjective(const AMicroscope, AObjective: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  if Squash(AObjective) = '' then
    Exit;
  for I := 0 to High(FItems) do
    if (Squash(FItems[I].Objective) = Squash(AObjective))
      and ((Squash(AMicroscope) = '') or (Squash(FItems[I].Microscope) = '')
        or (Squash(FItems[I].Microscope) = Squash(AMicroscope))) then
      Exit(I);
end;

function TCalibrationList.Put(const ACalibration: TCalibration): Integer;
begin
  Result := -1;
  if not CalibrationValid(ACalibration) then
    Exit;
  Result := IndexOfName(ACalibration.Name);
  if Result < 0 then
  begin
    if Length(FItems) >= MaxCalibrations then
      Exit;
    Result := Length(FItems);
    SetLength(FItems, Result + 1);
  end;
  FItems[Result] := ACalibration;
  FItems[Result].Name := Trim(ACalibration.Name);
end;

procedure TCalibrationList.Delete(AIndex: Integer);
var
  I: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FItems)) then
    Exit;
  for I := AIndex to High(FItems) - 1 do
    FItems[I] := FItems[I + 1];
  SetLength(FItems, Length(FItems) - 1);
end;

procedure TCalibrationList.Rename(AIndex: Integer; const ANewName: string);
var
  Other: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FItems)) or (Trim(ANewName) = '') then
    Exit;
  Other := IndexOfName(ANewName);
  if (Other >= 0) and (Other <> AIndex) then
    Exit;                       { names stay unique }
  FItems[AIndex].Name := Trim(ANewName);
end;

procedure TCalibrationList.Clear;
begin
  FItems := nil;
end;

function ReadNumber(AIni: TCustomIniFile; const ASection, AKey: string): Double;
var
  Text: string;
begin
  Text := Trim(AIni.ReadString(ASection, AKey, ''));
  { Tolerate a decimal comma typed by hand. }
  Text := StringReplace(Text, ',', '.', []);
  if not TryStrToFloat(Text, Result, Dot) then
    Result := 0;
end;

procedure TCalibrationList.LoadFromIni(AIni: TCustomIniFile);
var
  I: Integer;
  Section: string;
  C: TCalibration;
begin
  FItems := nil;
  for I := 1 to MaxCalibrations do
  begin
    Section := 'Calibration' + IntToStr(I);
    if not AIni.SectionExists(Section) then
      Continue;
    C.Name := Trim(AIni.ReadString(Section, 'Name', ''));
    C.Microscope := Trim(AIni.ReadString(Section, 'Microscope', ''));
    C.Objective := Trim(AIni.ReadString(Section, 'Objective', ''));
    C.Confocal := AIni.ReadInteger(Section, 'Confocal', 0) <> 0;
    C.ReferenceMicrons := ReadNumber(AIni, Section, 'ReferenceMicrons');
    C.ReferencePixels := ReadNumber(AIni, Section, 'ReferencePixels');
    C.ReferenceWidth := AIni.ReadInteger(Section, 'ReferenceWidth', 0);
    C.ReferenceZoom := ReadNumber(AIni, Section, 'ReferenceZoom');
    C.Date := Trim(AIni.ReadString(Section, 'Date', ''));
    C.Note := AIni.ReadString(Section, 'Note', '');
    { A broken or doubled entry is skipped, not fatal. }
    if CalibrationValid(C) and (IndexOfName(C.Name) < 0) then
      Put(C);
  end;
end;

procedure TCalibrationList.SaveToIni(AIni: TCustomIniFile);
var
  I: Integer;
  Section: string;
begin
  for I := 1 to MaxCalibrations do
  begin
    Section := 'Calibration' + IntToStr(I);
    if I > Length(FItems) then
    begin
      if AIni.SectionExists(Section) then
        AIni.EraseSection(Section);
      Continue;
    end;
    with FItems[I - 1] do
    begin
      AIni.WriteString(Section, 'Name', Name);
      AIni.WriteString(Section, 'Microscope', Microscope);
      AIni.WriteString(Section, 'Objective', Objective);
      AIni.WriteInteger(Section, 'Confocal', Ord(Confocal));
      AIni.WriteString(Section, 'ReferenceMicrons', FloatToStr(ReferenceMicrons, Dot));
      AIni.WriteString(Section, 'ReferencePixels', FloatToStr(ReferencePixels, Dot));
      AIni.WriteInteger(Section, 'ReferenceWidth', ReferenceWidth);
      AIni.WriteString(Section, 'ReferenceZoom', FloatToStr(ReferenceZoom, Dot));
      AIni.WriteString(Section, 'Date', Date);
      AIni.WriteString(Section, 'Note', Note);
    end;
  end;
end;

procedure TCalibrationList.LoadFromFile(const AFileName: string);
var
  Ini: TMemIniFile;
begin
  FItems := nil;
  if not FileExists(AFileName) then
    Exit;
  Ini := TMemIniFile.Create(AFileName);
  try
    LoadFromIni(Ini);
  finally
    Ini.Free;
  end;
end;

procedure TCalibrationList.SaveToFile(const AFileName: string);
var
  Ini: TMemIniFile;
  Lines: TStringList;
begin
  { In memory only (a TMemIniFile made on the file would write it in
    place once more when freed). }
  Ini := TMemIniFile.Create('');
  Lines := TStringList.Create;
  try
    if FileExists(AFileName) then
    begin
      Lines.LoadFromFile(AFileName);
      Ini.SetStrings(Lines);
      Lines.Clear;
    end;
    SaveToIni(Ini);
    { 1.1: never half written (uSafeFile). }
    Ini.GetStrings(Lines);
    WriteTextFileSafe(AFileName, Lines.Text);
  finally
    Lines.Free;
    Ini.Free;
  end;
end;

initialization
  Dot := DefaultFormatSettings;
  Dot.DecimalSeparator := '.';
  Dot.ThousandSeparator := #0;
end.
