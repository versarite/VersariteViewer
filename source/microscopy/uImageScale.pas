unit uImageScale;

{
  Unit: uImageScale

  Purpose
  -------
  Where an image's µm come from (M3a, Day 25): one answer for every
  image, "µm per pixel, and from where", for the pixel probe now and
  for the measuring line and the scale bar (M3b, M3c) later. Spec
  "Microscopy edition" §7.1.

  The order (the first that knows wins)
  -------------------------------------
  1. The file itself: an image inside a .lif (its pixel size); a TIFF
     or PNG that states its scale (Day 26: a copy saved by MView Lab,
     or an ImageJ / Fiji TIFF; uImageFileScale).
  2. A matching .lif (user, Day 25): an exported TIFF carries no µm (72
     dpi, nothing else), but LAS X names it after its project and image
     - 221119_Series084_t242_ch01.tif is Series084 of 221119.lif. That
     .lif, in the same folder or the one above, lends its pixel size,
     scaled when the export is smaller than the scan; the source says
     so ('221119.lif › Series084').
  3. The chosen calibration (calibrations.ini, uCalibrations; chosen in
     the left panel's selector, M3b), scaled for a confocal by width
     and zoom; the source says 'calibration: <name>'.
  4. None: pixels only.
  0. Before all: an image made from another in this session (a crop, a
     filtered / turned copy, a resized one; Day 26, user: "important
     step") has its parent's scale, by the size change and turned with
     it (uExtensions.NoteDerivedImage); the source says so
     ('Series009 (crop)'). A chain (a crop of a crop) carries it on.

  Owns
  ----
  - The metadata reader 'Leica LIF' (registered with uExtensions): 1
    and 2. One opened .lif kept (the last one: browsing a folder of
    exports asks the same .lif again and again), under a lock.
  - The calibration list (loaded from calibrations.ini at first use),
    the chosen one's name and "Confocal" (in the edition's ini,
    [Calibration] Chosen / Confocal: per installation).
  - The last answer (ScaleFor), per file and size: the pixel probe asks
    in every paint.

  Does NOT
  --------
  - Draw or measure. Read the pixels.
  - Write files (uImageSaver does, asking QueryImageScale - registered
    here - for the scale it writes).

  Threads
  -------
  The reader: any thread (the lock). ScaleFor, the calibrations: UI
  thread.

  Uses (MView units)
  ------------------
  interface:      uCalibrations
  implementation: uEdition, uExtensions, uContainers, uLifFile,
                  uLifContainer, uImageFileScale
  Libraries:      SysUtils, SyncObjs, IniFiles

  Used by
  -------
  VersariteImageLab.lpr (its uses list), uPixelProbe
}

{$mode ObjFPC}{$H+}

interface

uses
  uCalibrations;

type
  TImageScale = record
    UmPerPixelX: Double;     { 0 = no scale: pixels only }
    UmPerPixelY: Double;
    { '' = the file's own; '221119.lif › Series084'; 'calibration: SP8 40x' }
    Source: string;
  end;

{ The scale of the image AFileName (a file or a virtual name), shown at
  its original size AWidth x AHeight. False (pixels only) if nothing
  knows it. Cached: cheap when asked again for the same image. }
function ScaleFor(const AFileName: string; AWidth, AHeight: Integer; out AScale: TImageScale): Boolean;
{ Forget the cached answer (a calibration chosen or changed). }
procedure ScaleChanged;
{ 1.1: the width a confocal calibration made on AName (AWidth px wide)
  holds for. A crop or a resized copy made in this session is followed
  back to its original image: a crop of half the width has the same
  pixel size, so its calibration is for the original's width, not the
  crop's. Not a copy: AWidth. }
function CalibrationWidthFor(const AName: string; AWidth: Integer): Integer;

{ The calibrations (calibrations.ini next to the program), loaded at
  first use. }
function Calibrations: TCalibrationList;
{ calibrations.ini read again (edited by hand meanwhile). }
procedure ReloadCalibrations;
{ The list written to calibrations.ini; False and AError if it can't be. }
function SaveCalibrations(out AError: string): Boolean;
{ The chosen calibration's name; '' = none. Used when the file and a
  matching .lif know nothing. }
function ChosenCalibration: string;
procedure ChooseCalibration(const AName: string);

{ The "Confocal" check box (user, Day 25; the left panel's, M3b): a
  reference measurement made now keeps the image width and zoom (a
  scanner) or is a fixed px/µm (a camera). }
function ConfocalMode: Boolean;
procedure SetConfocalMode(AValue: Boolean);

implementation

uses
  SysUtils,
  SyncObjs,
  Classes,
  IniFiles,
  uSafeFile,
  uEdition,
  uExtensions,
  uContainers,
  uLifFile,
  uLifContainer,
  uImageFileScale;

var
  Lock: TCriticalSection = nil;
  CachedLif: TLifFile = nil;       { under Lock }
  CachedLifName: string = '';
  CachedLifAge: LongInt = 0;

  CalibrationList: TCalibrationList = nil;
  ChosenName: string = '';
  ConfocalValue: Boolean = True;
  ChoiceLoaded: Boolean = False;

  LastName: string = '';
  LastWidth: Integer = 0;
  LastHeight: Integer = 0;
  LastFound: Boolean = False;
  LastScale: TImageScale;
  LastValid: Boolean = False;

{ AFile opened (or the one kept, when it is that file and unchanged).
  Called with Lock held; nil if it can't be read. }
function OpenLifLocked(const AFile: string): TLifFile;
var
  Age: LongInt;
begin
  Result := nil;
  Age := FileAge(AFile);
  if Age = -1 then
    Exit;
  if (CachedLif <> nil) and SameText(CachedLifName, AFile) and (CachedLifAge = Age) then
    Exit(CachedLif);
  FreeAndNil(CachedLif);
  CachedLifName := '';
  CachedLif := TLifFile.Create;
  if not CachedLif.Open(AFile) then
  begin
    FreeAndNil(CachedLif);
    Exit;
  end;
  CachedLifName := AFile;
  CachedLifAge := Age;
  Result := CachedLif;
end;

procedure FillFrom(const AImage: TLifImage; var AMeta: TImageMetadata);
begin
  AMeta.PixelSizeX := AImage.PixelSizeX;
  AMeta.PixelSizeY := AImage.PixelSizeY;
  if AMeta.PixelSizeY <= 0 then
    AMeta.PixelSizeY := AImage.PixelSizeX;
  AMeta.ScaleWidth := AImage.Width;
  AMeta.ScaleHeight := AImage.Height;
  AMeta.Microscope := AImage.SystemName;
  AMeta.Objective := AImage.ObjectiveName;
  AMeta.Zoom := AImage.Zoom;
  AMeta.Lines := Copy(AImage.Lines);
end;

{ 1: an image inside a .lif. }
function ReadInsideLif(const AFileName: string; var AMeta: TImageMetadata): Boolean;
var
  LifName, Id: string;
  Lif: TLifFile;
  Index: Integer;
begin
  Result := False;
  if not SplitVirtual(AFileName, LifName, Id) then
    Exit;
  if not SameText(ExtractFileExt(LifName), '.lif') then
    Exit;
  Lock.Enter;
  try
    Lif := OpenLifLocked(LifName);
    if Lif = nil then
      Exit;
    Index := LifIndexOfId(Lif, Id);
    if Index < 0 then
      Exit;
    FillFrom(Lif.Images[Index], AMeta);
    Result := True;
  finally
    Lock.Leave;
  end;
end;

{ 2: an export whose name means an image of a .lif nearby. }
function ReadMatchingLif(const AFileName: string; var AMeta: TImageMetadata): Boolean;
var
  Guesses: TLifExportGuesses;
  Dirs: array[0..1] of string;
  G, D, Index: Integer;
  Candidate: string;
  Lif: TLifFile;
begin
  Result := False;
  if IsVirtualName(AFileName) or SameText(ExtractFileExt(AFileName), '.lif') then
    Exit;
  { Only a real file: a crop or a resized copy ('..._crop') is no export. }
  if not FileExists(AFileName) then
    Exit;
  Guesses := LifExportGuesses(ChangeFileExt(ExtractFileName(AFileName), ''));
  if Length(Guesses) = 0 then
    Exit;
  Dirs[0] := ExtractFilePath(AFileName);
  Dirs[1] := ExtractFilePath(ExcludeTrailingPathDelimiter(Dirs[0]));
  { 'C:\x.tif': Dirs[1] would be 'C:' (the drive's current folder!). }
  if Dirs[1] <> '' then
    Dirs[1] := IncludeTrailingPathDelimiter(Dirs[1]);
  for G := 0 to High(Guesses) do
    for D := 0 to High(Dirs) do
    begin
      if (D = 1) and ((Dirs[1] = '') or SameText(Dirs[1], Dirs[0])) then
        Continue;                 { a drive root has no folder above }
      Candidate := Dirs[D] + Guesses[G].LifBase + '.lif';
      if not FileExists(Candidate) then
        Continue;
      Lock.Enter;
      try
        Lif := OpenLifLocked(Candidate);
        if Lif = nil then
          Continue;
        Index := LifImageForExport(Lif, Guesses[G].ImageName);
        if Index < 0 then
          Continue;
        FillFrom(Lif.Images[Index], AMeta);
        AMeta.ScaleSource := ExtractFileName(Candidate) + ' › ' + Lif.Images[Index].Name;
        Exit(True);
      finally
        Lock.Leave;
      end;
    end;
end;

{ A file's own statement of its scale (an ImageJ TIFF, a PNG's pHYs):
  read before the .lif guesses (a saved crop named after its .lif image
  must not take the whole image's scale). }
function ReadFileScaleMetadata(const AFileName: string; var AMeta: TImageMetadata): Boolean;
var
  Ext: string;
  UmX, UmY: Double;
begin
  Result := False;
  if IsVirtualName(AFileName) then
    Exit;
  Ext := LowerCase(ExtractFileExt(AFileName));
  if (Ext <> '.tif') and (Ext <> '.tiff') and (Ext <> '.png') then
    Exit;
  if not ReadImageFileScale(AFileName, UmX, UmY) then
    Exit;
  AMeta.PixelSizeX := UmX;
  AMeta.PixelSizeY := UmY;
  AMeta.ScaleWidth := 0;          { the scale is the file's own size's }
  AMeta.ScaleHeight := 0;
  AMeta.ScaleSource := '';
  SetLength(AMeta.Lines, 1);
  AMeta.Lines[0] := 'Pixel size: ' + FloatToStrF(UmX, ffGeneral, 4, 0) + ' µm (in the file)';
  Result := True;
end;

{ The scale for a saved file (uImageSaver, through uExtensions). }
function QueryScale(const AName: string; AWidth, AHeight: Integer;
  out AUmX, AUmY: Double): Boolean;
var
  Scale: TImageScale;
begin
  Result := ScaleFor(AName, AWidth, AHeight, Scale);
  AUmX := Scale.UmPerPixelX;
  AUmY := Scale.UmPerPixelY;
end;

function ReadLifMetadata(const AFileName: string; var AMeta: TImageMetadata): Boolean;
begin
  Result := False;
  if Lock = nil then
    Exit;                         { shutting down (finalization ran) }
  Result := ReadInsideLif(AFileName, AMeta) or ReadMatchingLif(AFileName, AMeta);
end;

const
  ChoiceSection = 'Calibration';

{ The chosen calibration and "Confocal" live in the edition's ini
  ([Calibration] Chosen, Confocal): per installation, unlike the list.
  Read at first use - after SetEdition, which names the ini. }
{ The edition's ini in memory (its end line left out). }
function OpenEditionIni: TMemIniFile;
var
  Text: string;
  Lines: TStringList;
begin
  Result := TMemIniFile.Create('');
  if FileExists(EditionIniFileName) and ReadTextFile(EditionIniFileName, Text) then
  begin
    Lines := TStringList.Create;
    try
      Lines.Text := IniTextWithoutEndLine(Text);
      Result.SetStrings(Lines);
    finally
      Lines.Free;
    end;
  end;
end;

procedure EnsureChoice;
var
  Ini: TMemIniFile;
begin
  if ChoiceLoaded then
    Exit;
  ChoiceLoaded := True;
  try
    Ini := OpenEditionIni;
    try
      ChosenName := Trim(Ini.ReadString(ChoiceSection, 'Chosen', ''));
      ConfocalValue := Ini.ReadBool(ChoiceSection, 'Confocal', True);
    finally
      Ini.Free;
    end;
  except
    { No settings file yet: the defaults. }
  end;
end;

procedure SaveChoice;
var
  Ini: TMemIniFile;
  Lines: TStringList;
begin
  try
    { 1.1: written safely, with the ini's end line (uSafeFile), as every
      save of the settings. }
    Ini := OpenEditionIni;
    Lines := TStringList.Create;
    try
      Ini.WriteString(ChoiceSection, 'Chosen', ChosenName);
      Ini.WriteBool(ChoiceSection, 'Confocal', ConfocalValue);
      Ini.GetStrings(Lines);
      WriteTextFileSafe(EditionIniFileName, IniTextWithEndLine(Lines.Text));
    finally
      Lines.Free;
      Ini.Free;
    end;
  except
    { Read-only folder: the choice lasts this session. }
  end;
end;

function ConfocalMode: Boolean;
begin
  EnsureChoice;
  Result := ConfocalValue;
end;

procedure SetConfocalMode(AValue: Boolean);
begin
  EnsureChoice;
  if ConfocalValue = AValue then
    Exit;
  ConfocalValue := AValue;
  SaveChoice;
end;

function Calibrations: TCalibrationList;
begin
  if CalibrationList = nil then
  begin
    CalibrationList := TCalibrationList.Create;
    CalibrationList.LoadFromFile(DefaultCalibrationFile);
  end;
  Result := CalibrationList;
end;

procedure ReloadCalibrations;
begin
  Calibrations.LoadFromFile(DefaultCalibrationFile);
  ScaleChanged;
end;

function SaveCalibrations(out AError: string): Boolean;
begin
  AError := '';
  try
    Calibrations.SaveToFile(DefaultCalibrationFile);
    Result := True;
  except
    on E: Exception do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
  ScaleChanged;
end;

function ChosenCalibration: string;
begin
  EnsureChoice;
  Result := ChosenName;
end;

procedure ChooseCalibration(const AName: string);
begin
  EnsureChoice;
  ChosenName := AName;
  SaveChoice;
  ScaleChanged;
end;

procedure ScaleChanged;
begin
  LastValid := False;
end;

{ ---- Derived images (Day 26) ---- }

const
  MaxDerived = 200;
  MaxChain = 20;

type
  { How an image was made from another: its scale is worked out from the
    parent's when asked (a calibration chosen later reaches it too). }
  TDerivedRecord = record
    Name: string;
    Parent: string;
    Operation: string;
    ParentWidth, ParentHeight: Integer;
    FactorX, FactorY, Turn: Double;
  end;

var
  Derived: array of TDerivedRecord;

function DerivedIndex(const AName: string): Integer;
var
  I: Integer;
begin
  if AName <> '' then
    for I := High(Derived) downto 0 do
      if Derived[I].Name = AName then
        Exit(I);
  Result := -1;
end;

{ 'Series009' for an image in a container ('Folder › Series009 › #t03'
  nested), the file's name for a file, the name itself for a copy. }
function ShortName(const AName: string): string;
var
  FileName, Id: string;
begin
  if SplitVirtual(AName, FileName, Id) then
    Result := StringReplace(Id, '|', ' › ', [rfReplaceAll])
  else
    Result := ExtractFileName(AName);
end;

procedure HandleDerived(const ANewName, AParentName, AOperation: string;
  AParentWidth, AParentHeight: Integer; AFactorX, AFactorY, ATurn: Double);
var
  Index, I: Integer;
begin
  if (ANewName = '') or (AParentName = '') or (ANewName = AParentName)
    or (AFactorX <= 0) or (AFactorY <= 0) then
    Exit;
  Index := DerivedIndex(ANewName);
  if Index < 0 then
  begin
    if Length(Derived) >= MaxDerived then
    begin
      { The oldest go. }
      for I := 0 to High(Derived) - 1 do
        Derived[I] := Derived[I + 1];
      Index := High(Derived);
    end
    else
    begin
      Index := Length(Derived);
      SetLength(Derived, Index + 1);
    end;
  end;
  Derived[Index].Name := ANewName;
  Derived[Index].Parent := AParentName;
  Derived[Index].Operation := AOperation;
  Derived[Index].ParentWidth := AParentWidth;
  Derived[Index].ParentHeight := AParentHeight;
  Derived[Index].FactorX := AFactorX;
  Derived[Index].FactorY := AFactorY;
  Derived[Index].Turn := ATurn;
  ScaleChanged;
end;

function CalibrationWidthFor(const AName: string; AWidth: Integer): Integer;
var
  Index, Depth: Integer;
  Factor, Width: Double;
begin
  Result := AWidth;
  Factor := 1;
  Width := AWidth;
  Depth := 0;
  Index := DerivedIndex(AName);
  { Up to the original: its width, and how much larger a pixel of the
    copy is (square pixels: the mean of x and y; a turn doesn't matter). }
  while (Index >= 0) and (Depth < MaxChain) do
  begin
    Factor := Factor * (Derived[Index].FactorX + Derived[Index].FactorY) / 2;
    Width := Derived[Index].ParentWidth;
    Index := DerivedIndex(Derived[Index].Parent);
    Inc(Depth);
  end;
  { The same field of view: µm per pixel x pixels stays. }
  if (Depth > 0) and (Factor > 0) and (Width > 0) then
    Result := Round(Width / Factor);
  if Result < 1 then
    Result := AWidth;
end;

{ The scale, not cached; ADepth: how far down a chain of copies. }
function ComputeScale(const AFileName: string; AWidth, AHeight, ADepth: Integer;
  out AScale: TImageScale): Boolean;
var
  Meta: TImageMetadata;
  Index, Turns: Integer;
  C: TCalibration;
  D: TDerivedRecord;
  Parent: TImageScale;
  Mean: Double;
begin
  AScale.UmPerPixelX := 0;
  AScale.UmPerPixelY := 0;
  AScale.Source := '';
  Result := False;
  Index := DerivedIndex(AFileName);
  if Index >= 0 then
  begin
    { 0: made from another image: the parent's scale, by the size change,
      turned with it. }
    D := Derived[Index];
    if (ADepth < MaxChain)
      and ComputeScale(D.Parent, D.ParentWidth, D.ParentHeight, ADepth + 1, Parent) then
    begin
      AScale.UmPerPixelX := Parent.UmPerPixelX * D.FactorX;
      AScale.UmPerPixelY := Parent.UmPerPixelY * D.FactorY;
      { A quarter turn swaps x and y; an oblique one mixes them (the
        mean; equal for a square pixel anyway). }
      Turns := Round(D.Turn / 90);
      if Abs(D.Turn - 90.0 * Turns) < 0.01 then
      begin
        if Odd(Turns) then
        begin
          Mean := AScale.UmPerPixelX;
          AScale.UmPerPixelX := AScale.UmPerPixelY;
          AScale.UmPerPixelY := Mean;
        end;
      end
      else
      begin
        Mean := (AScale.UmPerPixelX + AScale.UmPerPixelY) / 2;
        AScale.UmPerPixelX := Mean;
        AScale.UmPerPixelY := Mean;
      end;
      { Where from: the parent's own source carried on (a chain, a
        calibration), else its name. }
      if Parent.Source <> '' then
        AScale.Source := Parent.Source + ' (' + D.Operation + ')'
      else
        AScale.Source := ShortName(D.Parent) + ' (' + D.Operation + ')';
      Result := AScale.UmPerPixelX > 0;
    end;
  end
  else if (AFileName <> '') and (AWidth > 0) and (AHeight > 0) then
  begin
    { 1 and 2: the file, or a matching .lif. }
    if ReadImageMetadata(AFileName, Meta) and (Meta.PixelSizeX > 0) then
    begin
      AScale.UmPerPixelX := Meta.PixelSizeX;
      AScale.UmPerPixelY := Meta.PixelSizeY;
      { An export smaller (or larger) than the scan: the same field of
        view over fewer pixels. }
      if Meta.ScaleWidth > 0 then
        AScale.UmPerPixelX := AScale.UmPerPixelX * Meta.ScaleWidth / AWidth;
      if Meta.ScaleHeight > 0 then
        AScale.UmPerPixelY := AScale.UmPerPixelY * Meta.ScaleHeight / AHeight;
      AScale.Source := Meta.ScaleSource;
      Result := True;
    end
    else if ChosenName <> '' then
    begin
      { 3: the chosen calibration. }
      Index := Calibrations.IndexOfName(ChosenName);
      if Index >= 0 then
      begin
        C := Calibrations.Item(Index);
        AScale.UmPerPixelX := UmPerPixel(C, AWidth, Meta.Zoom);
        AScale.UmPerPixelY := AScale.UmPerPixelX;
        AScale.Source := 'calibration: ' + C.Name;
        Result := AScale.UmPerPixelX > 0;
      end;
    end;
  end;
  if not Result then
  begin
    AScale.UmPerPixelX := 0;
    AScale.UmPerPixelY := 0;
    AScale.Source := '';
  end;
end;

function ScaleFor(const AFileName: string; AWidth, AHeight: Integer; out AScale: TImageScale): Boolean;
begin
  EnsureChoice;
  if LastValid and (LastName = AFileName) and (LastWidth = AWidth) and (LastHeight = AHeight) then
  begin
    AScale := LastScale;
    Exit(LastFound);
  end;
  Result := ComputeScale(AFileName, AWidth, AHeight, 0, AScale);
  LastName := AFileName;
  LastWidth := AWidth;
  LastHeight := AHeight;
  LastScale := AScale;
  LastFound := Result;
  LastValid := True;
end;

initialization
  Lock := TCriticalSection.Create;
  { The file's own statement first (Day 26). }
  RegisterMetadataReader('File scale', @ReadFileScaleMetadata);
  RegisterMetadataReader('Leica LIF', @ReadLifMetadata);
  RegisterDerivedImageHandler(@HandleDerived);
  RegisterImageScaleQuery(@QueryScale);
  { Explained on the settings screen (1.1, uEdition); written by the
    left panel, not filled in beforehand. }
  RegisterEditionKey(ChoiceSection, 'Chosen',
    '', 'The calibration in use for images without a scale of their own (a name from '
    + 'calibrations.ini; empty = none: pixels). Chosen in the left panel''s "Scale" row or on the '
    + '"Calibrations" page.', False);
  RegisterEditionKey(ChoiceSection, 'Confocal', '1',
    '1 = a reference measurement is made as on a confocal (scanning) microscope: the pixel size '
    + 'changes with the image width and the zoom. 0 = a camera: fixed. Set by the left panel''s '
    + '"Confocal" box.', False);

finalization
  FreeAndNil(CachedLif);
  FreeAndNil(CalibrationList);
  FreeAndNil(Lock);
end.
