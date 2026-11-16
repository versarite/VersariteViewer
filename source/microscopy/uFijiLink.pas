unit uFijiLink;

{
  Unit: uFijiLink

  Purpose
  -------
  The image to Fiji (1.1; spec "Microscopy edition" §9c, user Day 26: the
  Lab and Fiji side by side, by files). Two right-click entries (user,
  Day 27):
  - "Save original to Fiji": the image's own pixels, as decoded: no
    display filter, no mirror, no turn, for analysis (a crop or a stack
    frame is an image of its own and goes as it is).
  - "Save screen to Fiji": the image as shown - the display filters, the
    mirror and the turn, the marks (scale bar, measuring lines, labels)
    burned in, as "Apply filters to a copy" makes it (MakeFigure,
    OverlayBurnIn). Its file name ends in '_screen', so Fiji's window
    tells the two apart.
  Either is written as a calibrated TIFF (ImageJ's way: Fiji opens it in
  µm; the scale follows a smaller copy and a quarter turn) into a folder
  of temporary files, and handed to Fiji:
  - A Fiji running with the Lab's link script (uFijiChannel,
    Versarite_Lab_Link.js) gets it over 127.0.0.1:57317 and opens it
    at once - no new Fiji, no Java start.
  - Otherwise Fiji is started with it. Before that the link script is
    copied from the Lab's fiji\ folder (next to the program, or ..\fiji\
    in the repository) into <Fiji>\scripts\Plugins\AutoRun\ when it is
    missing there or differs, so the Fiji started listens and the next
    images go to it. Within a minute of that start a second one waits
    ("still starting") instead of starting another Fiji. (Fiji's own
    single-instance listener is not started by the 2025 launcher;
    --force-single-instance is passed anyway, for the older
    ImageJ-win64.exe.)
  - The way back (Day 27): Fiji's Plugins > Versarite > Send to
    Versarite Lab (Send_to_Versarite_Lab.js, from the Lab's fiji\ folder
    into <Fiji>\scripts\Plugins\Versarite\, with the link script and
    kept current on every send) saves Fiji's image as shown there as a
    calibrated TIFF and starts the Lab with it, which hands it to the Lab
    running (uSingleInstance). The Lab's program path is in
    %TEMP%\VersariteImageLab\VersariteImageLab.path, written on every
    send, for that script.
  - Fiji's program: [Fiji] Path in the edition's ini; empty or gone: it
    is looked for (uFijiFind) and the one found is written there; none:
    a dialog asks for it (once).
  - Fiji at the start (Day 31, user): [Fiji] OpenFijiAtStart=1 starts
    Fiji (minimised, its link script put in place) right after the Lab's
    window is up, unless one is listening already, so the first "to Fiji"
    or "Run in Fiji" has no Java start to wait for. On a thread: the Lab
    does not wait. Only with Fiji's program known or found - no dialog at
    the start. Default 0.
  - The temporary TIFFs: %TEMP%\VersariteImageLab\, named after the image
    and the time ('Series009_201530.tif'); those older than a day go when
    the next one is written.
  - A quick view (the full image not loaded yet) or a reduced copy of a
    huge image goes as it is, its scale corrected for its size; the note
    says so.

  Does NOT
  --------
  - Send the labels or the scale bar to Fiji as ROIs (the measuring lines
    go with "Save original to Fiji" as line selections in the ROI Manager,
    MeasureRoiMacro; the screen copy has all marks burned in).
  - Write 16-bit or single-channel TIFFs (the viewer's pixels are 8-bit
    RGB; M5).

  Threads
  -------
  UI thread (the menu). Waits for Fiji's answer (hourglass; quick unless
  Fiji is busy, e.g. a dialog open there; at most 20 s). Fiji at the
  start: TFijiStartThread (asks the link, copies the scripts, starts the
  program; the ini is read before, on the UI thread).

  Uses (MView units)
  ------------------
  implementation: uExtensions, uImageScale, uImageFileScale, uSafeFile,
                  uEdition, uFijiFind, uFijiChannel
  Libraries:      Classes, SysUtils, Math, IniFiles, Forms, Dialogs, LCLType,
                  BGRABitmap, BGRABitmapTypes, Windows (ShellExecute)

  Used by
  -------
  VersariteImageLab.lpr (its uses list only)
}

{$mode ObjFPC}{$H+}

interface

uses
  IniFiles,
  BGRABitmap;

{ For "Run in Fiji" (uFijiRun, Day 28): the temporary folder of the TIFFs;
  ABmp written there as a calibrated TIFF named after ABaseName (AUmX /
  AUmY 0 = no scale) - False and AError if it couldn't be; starting Fiji
  with the link (no image) - True if it was started now, ANote says what
  happened (also "still starting", "not found"); the edition's ini in
  memory and written back. }
function FijiTempFolder: string;
function WriteFijiTiff(ABmp: TBGRABitmap; const ABaseName: string; AUmX, AUmY: Double;
  out AFileName, AError: string): Boolean;
function StartFijiForLink(out ANote: string): Boolean;
function OpenEditionIni: TMemIniFile;
procedure SaveEditionIni(AIni: TMemIniFile);

implementation

uses
  {$IFDEF WINDOWS}
  Windows,
  ShellApi,
  {$ELSE}
  Process,
  {$ENDIF}
  Classes,
  SysUtils,
  Math,
  DateUtils,
  Forms,
  Controls,
  Dialogs,
  LCLType,
  BGRABitmapTypes,
  uExtensions,
  uImageScale,
  uImageFileScale,
  uSafeFile,
  uEdition,
  uFijiFind,
  uFijiChannel,
  uMeasureLine;

const
  FijiSection = 'Fiji';
  FijiPathKey = 'Path';
  OpenAtStartKey = 'OpenFijiAtStart';
  TempFolderName = 'VersariteImageLab';
  KeepTempHours = 24;

{ The edition's ini in memory (its end line left out). }
function OpenIni: TMemIniFile;
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

function StoredFijiPath: string;
var
  Ini: TMemIniFile;
begin
  Result := '';
  try
    Ini := OpenIni;
    try
      Result := Trim(Ini.ReadString(FijiSection, FijiPathKey, ''));
    finally
      Ini.Free;
    end;
  except
    Result := '';
  end;
end;

procedure StoreFijiPath(const APath: string);
var
  Ini: TMemIniFile;
  Lines: TStringList;
begin
  try
    Ini := OpenIni;
    Lines := TStringList.Create;
    try
      Ini.WriteString(FijiSection, FijiPathKey, APath);
      Ini.GetStrings(Lines);
      WriteTextFileSafe(EditionIniFileName, IniTextWithEndLine(Lines.Text));
    finally
      Lines.Free;
      Ini.Free;
    end;
  except
    { A read-only folder: asked again next time. }
  end;
end;

{ Fiji's program: the stored one, else found, else asked; '' = none. }
function FijiProgram: string;
var
  Dialog: TOpenDialog;
begin
  Result := StoredFijiPath;
  if (Result <> '') and FileExists(Result) then
    Exit;
  Result := FindFijiProgram(GetEnvironmentVariable('USERPROFILE'),
    GetEnvironmentVariable('LOCALAPPDATA'), GetEnvironmentVariable('ProgramFiles'));
  if Result = '' then
  begin
    NoteMenuOpen(True);
    Dialog := TOpenDialog.Create(nil);
    try
      Dialog.Title := 'Where is Fiji? (ImageJ-win64.exe or fiji-windows-x64.exe)';
      Dialog.Filter := 'Fiji|ImageJ-win64.exe;fiji-windows-x64.exe;fiji-windows-arm64.exe;'
        + 'fiji.exe;ImageJ.exe|Programs (*.exe)|*.exe';
      Dialog.Options := Dialog.Options + [ofFileMustExist];
      if Dialog.Execute then
        Result := Dialog.FileName;
    finally
      Dialog.Free;
      NoteMenuOpen(False);
    end;
  end;
  if Result <> '' then
    StoreFijiPath(Result);
end;

function TempFolder: string;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir(False)) + TempFolderName + PathDelim;
end;

{ The Lab's temporary TIFFs older than a day go. }
procedure CleanTempFolder;
var
  Info: TSearchRec;
  Limit: TDateTime;
begin
  Limit := IncHour(Now, -KeepTempHours);
  if FindFirst(TempFolder + '*.tif', faAnyFile, Info) = 0 then
    try
      repeat
        if (Info.Attr and faDirectory = 0) and (Info.TimeStamp < Limit) then
          SysUtils.DeleteFile(TempFolder + Info.Name);
      until FindNext(Info) <> 0;
    finally
      FindClose(Info);
    end;
end;

{ R G B per pixel, rows top down. }
function RgbBytes(ABitmap: TBGRABitmap): TBytes;
var
  X, Y, Q: Integer;
  P: PBGRAPixel;
begin
  Result := nil;
  SetLength(Result, Int64(ABitmap.Width) * ABitmap.Height * 3);
  Q := 0;
  for Y := 0 to ABitmap.Height - 1 do
  begin
    P := ABitmap.ScanLine[Y];
    for X := 0 to ABitmap.Width - 1 do
    begin
      Result[Q] := P^.red;
      Result[Q + 1] := P^.green;
      Result[Q + 2] := P^.blue;
      Inc(Q, 3);
      Inc(P);
    end;
  end;
end;

const
  { ImageJ's launcher: hand the arguments to a Fiji already running
    (net.imagej.legacy.SingleInstanceArgument). }
  SingleInstanceFlag = '--force-single-instance';

function StartProgram(const AProgram, AFile: string; out AError: string;
  AMinimised: Boolean = False): Boolean;
var
{$IFNDEF WINDOWS}
  Proc: TProcess;
{$ELSE}
  Params: string;
{$ENDIF}
begin
  AError := '';
  {$IFDEF WINDOWS}
  { No file (Day 28, "Run in Fiji"): Fiji alone, for the link. }
  if AFile = '' then
    Params := SingleInstanceFlag
  else
    Params := SingleInstanceFlag + ' "' + AFile + '"';
  Result := ShellExecuteW(0, 'open', PWideChar(UnicodeString(AProgram)),
    PWideChar(UnicodeString(Params)), PWideChar(UnicodeString(ExtractFileDir(AProgram))),
    IfThen(AMinimised, SW_SHOWMINNOACTIVE, SW_SHOWNORMAL)) > 32;
  if not Result then
    AError := 'Windows could not start it (' + SysErrorMessage(GetLastError) + ')';
  {$ELSE}
  Proc := TProcess.Create(nil);
  try
    Proc.Executable := AProgram;
    Proc.Parameters.Add(SingleInstanceFlag);
    if AFile <> '' then
      Proc.Parameters.Add(AFile);
    Proc.Options := [];
    try
      Proc.Execute;
      Result := True;
    except
      on E: Exception do
      begin
        AError := E.Message;
        Result := False;
      end;
    end;
  finally
    Proc.Free;
  end;
  {$ENDIF}
end;

const
  LinkScriptName = 'Versarite_Lab_Link.js';
  { The first try (1.1 preview), in Groovy: Fiji runs AutoRun files through
    ImageJ, which read it as a macro (an error at every start), so it goes. }
  OldLinkScriptName = 'Versarite_Lab_Link.groovy';
  { Fiji's Plugins > Versarite > Send to Versarite Lab (Fiji -> the Lab). }
  SendScriptName = 'Send_to_Versarite_Lab.js';
  { Where the Lab's program is, for that script (in TempFolder). }
  LabPathFileName = 'VersariteImageLab.path';
  { After the Lab starts Fiji, its link needs Java's start (5-15 s): a
    second "Open in Fiji" within this time must not start another Fiji. }
  FijiStartingMs = 60000;

var
  FijiStartedAt: QWord = 0;   // GetTickCount64 when the Lab last started Fiji

function FileText(const AName: string): string;
var
  S: TFileStream;
begin
  Result := '';
  S := TFileStream.Create(AName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, S.Size);
    if S.Size > 0 then
      S.ReadBuffer(Result[1], S.Size);
  finally
    S.Free;
  end;
end;

{ The Lab's copy of a Fiji script: fiji\ next to the program (a
  release), else ..\fiji\ (the repository, the program in build\). }
function FijiScriptSource(const AName: string): string;
var
  Dir: string;
begin
  Dir := ExtractFilePath(ParamStr(0));
  Result := Dir + 'fiji' + PathDelim + AName;
  if not FileExists(Result) then
    Result := ExpandFileName(Dir + '..' + PathDelim + 'fiji' + PathDelim + AName);
end;

{ AName from the Lab's fiji\ folder into ATargetDir, when it is missing
  there or differs. True = it is in place. }
function InstallFijiScript(const AName, ATargetDir: string): Boolean;
var
  Source, Target, Text: string;
  S: TFileStream;
begin
  Source := FijiScriptSource(AName);
  Target := IncludeTrailingPathDelimiter(ATargetDir) + AName;
  try
    if not FileExists(Source) then
      Exit(FileExists(Target));
    Text := FileText(Source);
    if FileExists(Target) and (FileText(Target) = Text) then
      Exit(True);
    ForceDirectories(ATargetDir);
    S := TFileStream.Create(Target, fmCreate);
    try
      if Text <> '' then
        S.WriteBuffer(Text[1], Length(Text));
    finally
      S.Free;
    end;
    Result := True;
  except
    { Fiji's folder read-only: Fiji works as before, without them. }
    Result := FileExists(Target);
  end;
end;

{ The Lab's scripts into the Fiji of AFiji (its program): the link
  (scripts\Plugins\AutoRun\, run at Fiji's start) and "Send to Versarite
  Lab" (scripts\Plugins\Versarite\: Fiji's Plugins > Versarite menu;
  Fiji shows it after its next start or Help > Refresh Menus). The old
  Groovy link goes. True = the link is in place. }
function InstallFijiScripts(const AFiji: string): Boolean;
var
  Plugins: string;
begin
  Result := False;
  if AFiji = '' then
    Exit;
  Plugins := IncludeTrailingPathDelimiter(ExtractFileDir(AFiji)) + 'scripts' + PathDelim
    + 'Plugins' + PathDelim;
  try
    if FileExists(Plugins + 'AutoRun' + PathDelim + OldLinkScriptName) then
      SysUtils.DeleteFile(Plugins + 'AutoRun' + PathDelim + OldLinkScriptName);
  except
  end;
  Result := InstallFijiScript(LinkScriptName, Plugins + 'AutoRun');
  InstallFijiScript(SendScriptName, Plugins + 'Versarite');
end;

{ The Lab's program, for Fiji's "Send to Versarite Lab": written next to
  the TIFFs (UTF-8, one line) each time the Lab talks to Fiji. }
procedure WriteLabPathFile;
var
  S: TFileStream;
  Text: UTF8String;
begin
  try
    ForceDirectories(TempFolder);
    Text := UTF8String(ParamStr(0));
    S := TFileStream.Create(TempFolder + LabPathFileName, fmCreate);
    try
      if Text <> '' then
        S.WriteBuffer(Text[1], Length(Text));
    finally
      S.Free;
    end;
  except
    { Then Fiji asks for the Lab once. }
  end;
end;

{ Writes ABmp as a calibrated TIFF named after ASourceName + ASuffix and
  hands it to Fiji (the running one over the link, else a new one). AUmX,
  AUmY: µm per pixel of ABmp (0 = no scale); AReduced: the note says the
  copy is smaller than the image. }
{ Day 29 (user): the measuring lines of AImageName as line selections in
  Fiji's ROI Manager (added to what is there; named after the length),
  in the pixels of the image sent (AFactorX / Y: its pixels per image
  pixel). '' = none. }
function MeasureRoiMacro(const AImageName: string; AFactorX, AFactorY: Double;
  out ACount: Integer): string;
var
  Dot: TFormatSettings;
  I: Integer;
  X0, Y0, X1, Y1: Double;
  Text: string;

  function N(AValue: Double): string;
  begin
    Result := FormatFloat('0.###', AValue, Dot);
  end;

begin
  Result := '';
  ACount := 0;
  Dot := DefaultFormatSettings;
  Dot.DecimalSeparator := '.';
  Dot.ThousandSeparator := #0;
  for I := 0 to MeasureLineCount(AImageName) - 1 do
    if MeasureLineGet(AImageName, I, X0, Y0, X1, Y1, Text) then
    begin
      Inc(ACount);
      Result := Result + Format('makeLine(%s, %s, %s, %s);', [N(X0 * AFactorX), N(Y0 * AFactorY),
        N(X1 * AFactorX), N(Y1 * AFactorY)]) + LineEnding
        + 'Roi.setName("' + StringReplace(Format('Line %d: %s', [ACount, Text]), '"', #39,
        [rfReplaceAll]) + '");' + LineEnding
        + 'roiManager("add");' + LineEnding;
    end;
  if ACount = 0 then
    Exit('');
  Result := 'if (nImages > 0) {' + LineEnding + Result
    + 'run("Select None");' + LineEnding
    + 'roiManager("show all with labels");' + LineEnding
    + '}' + LineEnding
    + 'return "" + roiManager("count");';
end;

procedure SendToFiji(ABmp: TBGRABitmap; const ASourceName, ASuffix: string;
  AUmX, AUmY: Double; AReduced: Boolean; const ARoiMacro: string = ''; ARoiCount: Integer = 0);
var
  Err, Fiji, TifName, Note, Reply, RoiNote, Why: string;
  Line: Integer;
  Answer: TFijiAnswer;
  Data: TBytes;
  Stream: TFileStream;
begin
  WriteLabPathFile;
  try
    ForceDirectories(TempFolder);
    CleanTempFolder;
    TifName := TempFolder + FijiTiffName(ASourceName + ASuffix, FormatDateTime('_hhnnss', Now));
    Data := MakeRgbTiff(ABmp.Width, ABmp.Height, RgbBytes(ABmp), AUmX, AUmY);
    Stream := TFileStream.Create(TifName, fmCreate);
    try
      if Length(Data) > 0 then
        Stream.WriteBuffer(Data[0], Length(Data));
    finally
      Stream.Free;
    end;
  except
    on E: Exception do
    begin
      ViewerNote('Fiji: the TIFF could not be written (' + E.Message + ')', 6000);
      Exit;
    end;
  end;
  { A Fiji listening (the link script): it opens the image itself. }
  Screen.Cursor := crHourGlass;
  try
    Answer := FijiSend('OPEN ' + TifName, Reply);
  finally
    Screen.Cursor := crDefault;
  end;
  RoiNote := '';
  case Answer of
    faOk:
      begin
        Note := 'Sent to Fiji: ' + ExtractFileName(TifName);
        { The measuring lines into the ROI Manager, on the image just
          opened. }
        if ARoiMacro <> '' then
          case FijiSend('EVAL ' + FijiEscape(ARoiMacro), Reply) of
            faOk:
              if ARoiCount = 1 then
                RoiNote := ', the measuring line in the ROI Manager'
              else
                RoiNote := Format(', %d measuring lines in the ROI Manager', [ARoiCount]);
            faError:
              begin
                FijiErrorParts(Reply, Line, Why);
                if Pos(LineEnding, Why) > 0 then
                  Why := Copy(Why, 1, Pos(LineEnding, Why) - 1);
                RoiNote := ' (the measuring lines did not go: ' + Why + ')';
              end;
          end;
        { Keep the scripts current (a newer Lab), no dialog: only with
          the path known. }
        InstallFijiScripts(StoredFijiPath);
      end;
    faError:
      begin
        ViewerNote('Fiji answered: ' + Reply, 6000);
        Exit;
      end;
  else
    { faNoFiji: started a moment ago and not listening yet? Then wait. }
    if (FijiStartedAt <> 0) and (GetTickCount64 - FijiStartedAt < FijiStartingMs) then
    begin
      ViewerNote('Fiji is still starting - try again in a moment', 4000);
      Exit;
    end;
    { Start one (the link script put in place first). }
    Fiji := FijiProgram;
    if Fiji = '' then
    begin
      ViewerNote('Fiji not found (set [Fiji] Path in the settings)', 6000);
      Exit;
    end;
    InstallFijiScripts(Fiji);
    if not StartProgram(Fiji, TifName, Err) then
    begin
      ViewerNote('Fiji: ' + Err, 6000);
      Exit;
    end;
    FijiStartedAt := GetTickCount64;
    Note := 'Fiji started with: ' + ExtractFileName(TifName);
    if ARoiMacro <> '' then
      RoiNote := ' (the measuring lines: send it again once Fiji is up)';
  end;
  if (AUmX > 0) and (AUmY > 0) then
    Note := Note + Format('  (%s µm/px)', [FormatFloat('0.####', AUmX)])
  else
    Note := Note + '  (no scale: pixels)';
  if AReduced then
    Note := Note + Format(', reduced to %d x %d (the full image is not loaded)',
      [ABmp.Width, ABmp.Height]);
  ViewerNote(Note + RoiNote, 6000);
end;

{ The image's scale (µm per pixel of its full AFullW x AFullH), False = none. }
function ImageUm(const AImageName: string; AFullW, AFullH: Integer;
  out AUmX, AUmY: Double): Boolean;
var
  Scale: TImageScale;
begin
  AUmX := 0;
  AUmY := 0;
  Result := (AFullW > 0) and (AFullH > 0) and ScaleFor(AImageName, AFullW, AFullH, Scale)
    and (Scale.UmPerPixelX > 0) and (Scale.UmPerPixelY > 0);
  if Result then
  begin
    AUmX := Scale.UmPerPixelX;
    AUmY := Scale.UmPerPixelY;
  end;
end;

{ "Save original to Fiji": the image's own pixels. }
procedure OriginalToFiji(AViewer: TObject);
var
  Bmp: TBGRABitmap;
  ImageName, SourceName, Folder, Err: string;
  FullW, FullH: Integer;
  Quick: Boolean;
  UmX, UmY: Double;
  Rois: string;
  RoiCount: Integer;
begin
  if not GetImagePixels(Bmp, ImageName, SourceName, Folder, Err, FullW, FullH, Quick) then
  begin
    ViewerNote('Save original to Fiji: ' + Err, 4000);
    Exit;
  end;
  Rois := '';
  RoiCount := 0;
  try
    { The scale of the pixels sent: the image's, for a smaller copy
      larger by as much. }
    if ImageUm(ImageName, FullW, FullH, UmX, UmY) then
    begin
      UmX := UmX * FullW / Bmp.Width;
      UmY := UmY * FullH / Bmp.Height;
    end;
    if (FullW > 0) and (FullH > 0) then
      Rois := MeasureRoiMacro(ImageName, Bmp.Width / FullW, Bmp.Height / FullH, RoiCount);
    SendToFiji(Bmp, SourceName, '', UmX, UmY, Quick or (Bmp.Width < FullW), Rois, RoiCount);
  finally
    Bmp.Free;
  end;
end;

{ "Save screen to Fiji": the image as shown, the marks burned in. }
procedure ScreenToFiji(AViewer: TObject);
var
  Bmp: TBGRABitmap;
  Map: TBurnInMap;
  ImageName, SourceName, Folder, Err: string;
  Quick: Boolean;
  FullW, FullH, Turns: Integer;
  UmX, UmY, T, A: Double;
begin
  if not MakeFigure(Bmp, Map, ImageName, SourceName, Folder, Err, Quick) then
  begin
    ViewerNote('Save screen to Fiji: ' + Err, 4000);
    Exit;
  end;
  try
    { The marks into the copy (as "Apply filters to a copy"). }
    OverlayBurnIn(Bmp, ImageName, Map);
    { The scale: the image's, per pixel of the copy's source (Map.ScaleX
      source px per image px); a quarter turn swaps x and y; another
      angle keeps the pixel size (a turned canvas, same scale). }
    FullW := 0;
    FullH := 0;
    if (Map.ScaleX > 0) and (Map.ScaleY > 0) then
    begin
      FullW := Round(Map.SourceWidth / Map.ScaleX);
      FullH := Round(Map.SourceHeight / Map.ScaleY);
    end;
    if ImageUm(ImageName, FullW, FullH, UmX, UmY) then
    begin
      UmX := UmX / Map.ScaleX;
      UmY := UmY / Map.ScaleY;
      A := Map.Angle - 360.0 * Floor(Map.Angle / 360.0);
      Turns := Round(A / 90.0);
      if (Abs(A - Turns * 90.0) < 0.01) and Odd(Turns) then
      begin
        T := UmX;
        UmX := UmY;
        UmY := T;
      end
      else if Abs(A - Turns * 90.0) >= 0.01 then
      begin
        UmX := (UmX + UmY) / 2;
        UmY := UmX;
      end;
    end;
    SendToFiji(Bmp, SourceName, '_screen', UmX, UmY, Quick or (Map.ScaleX < 1));
  finally
    Bmp.Free;
  end;
end;

{ ---- For "Run in Fiji" (uFijiRun, Day 28) ---- }

function FijiTempFolder: string;
begin
  Result := TempFolder;
end;

function WriteFijiTiff(ABmp: TBGRABitmap; const ABaseName: string; AUmX, AUmY: Double;
  out AFileName, AError: string): Boolean;
var
  Data: TBytes;
  Stream: TFileStream;
begin
  AFileName := '';
  AError := '';
  WriteLabPathFile;
  try
    ForceDirectories(TempFolder);
    CleanTempFolder;
    AFileName := TempFolder + FijiTiffName(ABaseName, FormatDateTime('_hhnnss_zzz', Now));
    Data := MakeRgbTiff(ABmp.Width, ABmp.Height, RgbBytes(ABmp), AUmX, AUmY);
    Stream := TFileStream.Create(AFileName, fmCreate);
    try
      if Length(Data) > 0 then
        Stream.WriteBuffer(Data[0], Length(Data));
    finally
      Stream.Free;
    end;
    Result := True;
  except
    on E: Exception do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
end;

function StartFijiForLink(out ANote: string): Boolean;
var
  Fiji, Err: string;
begin
  Result := False;
  if (FijiStartedAt <> 0) and (GetTickCount64 - FijiStartedAt < FijiStartingMs) then
  begin
    ANote := 'Fiji is still starting - try again in a moment';
    Exit;
  end;
  Fiji := FijiProgram;
  if Fiji = '' then
  begin
    ANote := 'Fiji not found (set [Fiji] Path in the settings)';
    Exit;
  end;
  InstallFijiScripts(Fiji);
  if not StartProgram(Fiji, '', Err) then
  begin
    ANote := 'Fiji: ' + Err;
    Exit;
  end;
  FijiStartedAt := GetTickCount64;
  ANote := 'Fiji is starting - run the command again when it is up';
  Result := True;
end;

function OpenEditionIni: TMemIniFile;
begin
  Result := OpenIni;
end;

procedure SaveEditionIni(AIni: TMemIniFile);
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    try
      AIni.GetStrings(Lines);
      WriteTextFileSafe(EditionIniFileName, IniTextWithEndLine(Lines.Text));
    except
      { A read-only folder: the change holds for this session only. }
    end;
  finally
    Lines.Free;
  end;
end;

{ Fiji at the start ([Fiji] OpenFijiAtStart=1, Day 31). }
type
  TFijiStartThread = class(TThread)
  private
    FFiji: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const AFiji: string);
  end;

constructor TFijiStartThread.Create(const AFiji: string);
begin
  FFiji := AFiji;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TFijiStartThread.Execute;
var
  Fiji, Err: string;
begin
  try
    if FijiListening then
      Exit;                       { one is up already }
    Fiji := FFiji;
    if (Fiji = '') or not FileExists(Fiji) then
      Fiji := FindFijiProgram(GetEnvironmentVariable('USERPROFILE'),
        GetEnvironmentVariable('LOCALAPPDATA'), GetEnvironmentVariable('ProgramFiles'));
    if Fiji = '' then
      Exit;                       { asked for at the first use, as before }
    InstallFijiScripts(Fiji);
    WriteLabPathFile;
    if StartProgram(Fiji, '', Err, True) then
      FijiStartedAt := GetTickCount64;   { "still starting" for a minute }
  except
    { Fiji is then started at the first use, as without the key. }
  end;
end;

type
  TFijiAtStart = class
    procedure Run(AData: PtrInt);
  end;

var
  FijiAtStart: TFijiAtStart = nil;

{ Queued at the unit's start: runs once the Lab's window is up. }
procedure TFijiAtStart.Run(AData: PtrInt);
var
  Ini: TMemIniFile;
  Wanted: Boolean;
  Fiji: string;
begin
  { LCL runs the queued calls also while it shuts down: not in a second
    instance that handed its file over, nor in a Lab closed at once. }
  if (Application.MainForm = nil) or (AppDestroying in Application.Flags)
    or Application.Terminated then
    Exit;
  Wanted := False;
  Fiji := '';
  try
    Ini := OpenIni;
    try
      Wanted := Ini.ReadInteger(FijiSection, OpenAtStartKey, 0) = 1;
      Fiji := Trim(Ini.ReadString(FijiSection, FijiPathKey, ''));
    finally
      Ini.Free;
    end;
  except
    Wanted := False;
  end;
  if Wanted then
    TFijiStartThread.Create(Fiji);
end;

function FijiEntryEnabled(AViewer: TObject): Boolean;
begin
  Result := ShownImageName <> '';
end;

initialization
  RegisterMenuEntry('Save original to Fiji', @OriginalToFiji, @FijiEntryEnabled, nil);
  RegisterMenuEntry('Save screen to Fiji', @ScreenToFiji, @FijiEntryEnabled, nil);
  RegisterEditionKey(FijiSection, FijiPathKey, '',
    'Fiji''s program for "Save original / screen to Fiji" (right-click menu), e.g. '
    + 'C:\Fiji.app\ImageJ-win64.exe or ...\Fiji\fiji-windows-x64.exe. Empty = looked for in the '
    + 'usual places (C:\Fiji.app, a Fiji.app or Fiji folder in your user folder, Desktop, '
    + 'Documents, Downloads), else asked once; the one found is written here. Set it when Fiji '
    + 'is elsewhere or you have more than one.');
  RegisterEditionKey(FijiSection, OpenAtStartKey, '0',
    '1 = Fiji is started (minimised) together with the Lab, unless it is running already, so '
    + 'the first "Save ... to Fiji" or "Run in Fiji" does not wait for Java to start (10 s or '
    + 'more). The Lab does not wait for it. 0 = Fiji is started when it is first needed '
    + '(default). Needs Fiji''s program (Path, or found in the usual places).');
  { Once the Lab's window is up (TFijiAtStart.Run). }
  FijiAtStart := TFijiAtStart.Create;
  Application.QueueAsyncCall(@FijiAtStart.Run, 0);

finalization
  FreeAndNil(FijiAtStart);
end.
