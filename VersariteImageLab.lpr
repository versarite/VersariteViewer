program VersariteImageLab;

{
  Versarite Image Lab (formerly MView Lab): the microscopy edition (M1,
  Day 25). The same program as VersariteViewer.lpr, from the
  same units, plus:
  - SetEdition first thing: its own name, settings file
    (VersariteImageLab.ini; MViewLab.ini taken over), single instance,
    About box (uEdition);
  - the edition's units in the uses list (source\microscopy): each
    plugs itself in, in its initialization section (uExtensions). MView
    lists none of them.
  Spec: specs\microscopy\Microscopy_Edition_Specification_v0.1.md.
}

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$IFDEF HASAMIGA}
  athreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms,
  SysUtils,
  uSingleInstance,
  uTypes, uCommands, uNaturalSort, uStopwatch, uIOGate, uMemoryGuard, uWatchdog, uImageSaver, uImageFormats,
  uDirectoryImages, uDirectoryTree, uNavigator,
  uDecodedImage, uJpegDecoder, uExifOrientation, uJpegHeader, uTiffQuick, uImageScaling, uWicDecoder,
  uMediaLoader, uRenderer, uGLRenderer, uGLMediaView, uInputHandler,
  uJobQueue, uJobScheduler, uImageCache, uDirectoryScanner,
  uConfig, uIniEditor, uMediaView, uMView, uMainForm,
  uEdition, uExtensions, uContainers,
  { The microscopy edition's own units. }
  uPixelProbe, uLifFile, uLifContainer, uCalibrations, uImageScale,
  uCalibrationDialog, uMeasureLine, uScaleBar, uTextLabel, uSvgExport, uFijiLink, uFijiRun, uCalibrationPanel, uMarkStylePanel, uCalibrationPage;

{$R *.res}

const
  LabVersion = '0.2.0';

{ [Startup] OnlyOneInstance (default 1): another Image Lab running takes the
  file or folder (full path: this process's folder may differ) and comes
  to the front; this one ends before it makes a window. }
function HandedOver: Boolean;
var
  Config: TConfig;
  Path: string;
  OnlyOne: Boolean;
begin
  Result := False;
  OnlyOne := True;
  Config := TConfig.Create;
  try
    try
      Config.Load;
      OnlyOne := Config.OnlyOneInstance;
    except
      { Unreadable ini: the default. }
    end;
  finally
    Config.Free;
  end;
  if not OnlyOne then
    Exit;
  Path := '';
  if ParamCount >= 1 then
    Path := ExpandFileName(ParamStr(1));
  Result := HandOverToRunningInstance(Path);
end;

begin
  { Before anything reads a setting: VersariteImageLab.ini, its own
    instance. }
  SetEdition('VersariteImageLab', 'MViewLab', 'Versarite Image Lab', LabVersion);
  RequireDerivedFormResource:=True;
  Application.Scaled:=True;
  {$PUSH}{$WARN 5044 OFF}
  Application.MainFormOnTaskbar:=True;
  {$POP}
  Application.Initialize;
  Application.Title := EditionTitle;   { dialogs, the task list }
  if HandedOver then
  begin
    { Ending before anything else started (Day 23): the I/O gate, made
      at start-up and normally left for the end of the process (a stuck
      read may still use it), is freed here: no thread exists yet. Else
      a debug build's leak report (heaptrc) shows a dialog each time. }
    FreeAndNil(IOGate);
    Exit;
  end;
  Application.CreateForm(TMainForm, MainForm);
  { The next instances' files and folders come here (only one instance). }
  StartInstanceListener(@MainForm.HandleHandedOver);
  Application.Run;
end.

