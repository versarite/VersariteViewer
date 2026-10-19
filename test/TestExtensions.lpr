program TestExtensions;

{
  Checks the plug-in points of the core (M0, Day 25), uEdition and
  uExtensions, with nothing of the microscopy edition:
  - uEdition: VersariteViewer's names by default (VersariteViewer.ini
    next to the exe, MView.ini as the one taken over), SetEdition
    changes them, EditionText says a text for the edition;
  - metadata readers: none registered = nothing understood; the first
    reader that understands a file wins; a reader that gives up or
    raises leaves nothing behind; the reader's name is filled in;
  - overlay layers: registered (nil is not), counted, out-of-range
    index = nil, OverlayChanged reaches OnOverlayChanged with the layer,
    the defaults draw nothing and take no mouse, a layer's own answer;
  - menu entries: an entry without an action is not registered; caption
    and tests are kept.

  No files. Build and run with build_test.bat (needs lazbuild: BGRABitmap).
}

{$mode ObjFPC}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces,   { the LCL's widget set: BGRABitmap links the LCL (as TestGif) }
  Classes,
  SysUtils,
  BGRABitmap,
  uCommands,
  uEdition,
  uExtensions,
  zipper,
  BGRABitmapTypes,
  uContainers,
  uZipContainer;

var
  PassCount, FailCount: Integer;

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

{ ---- Edition ---- }

procedure TestEdition;
var
  OldId, OldOldId, OldTitle, OldVersion: string;
begin
  WriteLn('Edition');
  Check('default id VersariteViewer', EditionId = 'VersariteViewer', EditionId);
  Check('default old id MView (1.1, the rename)', EditionOldId = 'MView', EditionOldId);
  Check('default title', EditionTitle = 'VersariteViewer', EditionTitle);
  Check('default version = MViewVersion', EditionVersion = MViewVersion, EditionVersion);
  Check('default caption VersariteViewer', EditionCaption = 'VersariteViewer', EditionCaption);
  Check('VersariteViewer.ini next to the exe',
    EditionIniFileName = ExtractFilePath(ParamStr(0)) + 'VersariteViewer.ini', EditionIniFileName);
  Check('the old MView.ini next to the exe (taken over)',
    EditionOldIniFileName = ExtractFilePath(ParamStr(0)) + 'MView.ini', EditionOldIniFileName);
  Check('EditionText: unchanged for VersariteViewer',
    EditionText('in VersariteViewer.ini') = 'in VersariteViewer.ini', EditionText('in VersariteViewer.ini'));
  OldId := EditionId;
  OldOldId := EditionOldId;
  OldTitle := EditionTitle;
  OldVersion := EditionVersion;
  SetEdition('VersariteImageLab', 'MViewLab', 'Versarite Image Lab', '0.1');
  Check('SetEdition: id', EditionId = 'VersariteImageLab', EditionId);
  Check('SetEdition: old id', EditionOldId = 'MViewLab', EditionOldId);
  Check('SetEdition: title', EditionTitle = 'Versarite Image Lab', EditionTitle);
  Check('SetEdition: version', EditionVersion = '0.1', EditionVersion);
  Check('SetEdition: own ini',
    ExtractFileName(EditionIniFileName) = 'VersariteImageLab.ini', EditionIniFileName);
  Check('SetEdition: its old ini', ExtractFileName(EditionOldIniFileName) = 'MViewLab.ini',
    EditionOldIniFileName);
  Check('SetEdition: caption = the title when not given', EditionCaption = 'Versarite Image Lab',
    EditionCaption);
  Check('EditionText: the edition''s ini, exe and name',
    EditionText('VersariteViewer.ini, VersariteViewer.exe: VersariteViewer')
      = 'VersariteImageLab.ini, VersariteImageLab.exe: Versarite Image Lab',
    EditionText('VersariteViewer.ini, VersariteViewer.exe: VersariteViewer'));
  SetEdition('VersariteImageLab', 'MViewLab', 'Versarite Image Lab', '0.1', 'Image Lab');
  Check('SetEdition: own caption', EditionCaption = 'Image Lab', EditionCaption);
  SetEdition(OldId, OldOldId, OldTitle, OldVersion, 'VersariteViewer');
end;

{ ---- Metadata readers ---- }

var
  GaveUpCalls, RaiserCalls, LifCalls, SecondCalls: Integer;

{ Fills everything in, then gives up: must leave nothing behind. }
function ReaderGivesUp(const AFileName: string; var AMeta: TImageMetadata): Boolean;
begin
  Inc(GaveUpCalls);
  AMeta.Reader := 'half';
  AMeta.PixelSizeX := 9;
  SetLength(AMeta.Lines, 1);
  AMeta.Lines[0] := 'half';
  Result := False;
end;

function ReaderRaises(const AFileName: string; var AMeta: TImageMetadata): Boolean;
begin
  Inc(RaiserCalls);
  Result := False;
  AMeta.PixelSizeY := 7;
  raise Exception.Create('broken file');
end;

{ Understands *.lif; leaves Reader empty (the registry fills it in). }
function ReaderLif(const AFileName: string; var AMeta: TImageMetadata): Boolean;
begin
  Inc(LifCalls);
  Result := SameText(ExtractFileExt(AFileName), '.lif');
  if not Result then
    Exit;
  AMeta.PixelSizeX := 0.142;
  AMeta.PixelSizeY := 0.142;
  SetLength(AMeta.Lines, 2);
  AMeta.Lines[0] := 'Objective: 40x/1.30 OIL';
  AMeta.Lines[1] := 'Zoom: 2';
end;

{ Understands everything and names itself; after ReaderLif. }
function ReaderSecond(const AFileName: string; var AMeta: TImageMetadata): Boolean;
begin
  Inc(SecondCalls);
  AMeta.Reader := 'second (own name)';
  AMeta.PixelSizeX := 1;
  AMeta.PixelSizeY := 1;
  Result := True;
end;

procedure TestMetadata;
var
  Meta: TImageMetadata;
  Ok: Boolean;
begin
  WriteLn('Metadata readers');
  Check('none registered', MetadataReaderCount = 0, IntToStr(MetadataReaderCount));
  Ok := ReadImageMetadata('a.lif', Meta);
  Check('none: not understood', not Ok);
  Check('none: empty', (Meta.Reader = '') and (Meta.PixelSizeX = 0) and (Length(Meta.Lines) = 0));

  RegisterMetadataReader('nil', nil);
  Check('nil reader not registered', MetadataReaderCount = 0, IntToStr(MetadataReaderCount));

  RegisterMetadataReader('gives up', @ReaderGivesUp);
  RegisterMetadataReader('raises', @ReaderRaises);
  Check('two registered', MetadataReaderCount = 2, IntToStr(MetadataReaderCount));
  Ok := ReadImageMetadata('a.lif', Meta);
  Check('gave up + raised: not understood', not Ok);
  Check('both asked', (GaveUpCalls = 1) and (RaiserCalls = 1),
    Format('%d, %d', [GaveUpCalls, RaiserCalls]));
  Check('nothing left behind', (Meta.Reader = '') and (Meta.PixelSizeX = 0)
    and (Meta.PixelSizeY = 0) and (Length(Meta.Lines) = 0),
    Format('%s %g %g %d', [Meta.Reader, Meta.PixelSizeX, Meta.PixelSizeY, Length(Meta.Lines)]));

  RegisterMetadataReader('Leica LIF', @ReaderLif);
  RegisterMetadataReader('second', @ReaderSecond);
  Ok := ReadImageMetadata('C:\data\sample.LIF', Meta);
  Check('.lif understood', Ok);
  Check('the registered name filled in', Meta.Reader = 'Leica LIF', Meta.Reader);
  Check('pixel size', (Abs(Meta.PixelSizeX - 0.142) < 1e-9) and (Abs(Meta.PixelSizeY - 0.142) < 1e-9),
    Format('%g %g', [Meta.PixelSizeX, Meta.PixelSizeY]));
  Check('lines', (Length(Meta.Lines) = 2) and (Meta.Lines[0] = 'Objective: 40x/1.30 OIL'));
  Check('first that understands wins (second not asked)', SecondCalls = 0, IntToStr(SecondCalls));

  Ok := ReadImageMetadata('photo.jpg', Meta);
  Check('.jpg: the next reader', Ok and (SecondCalls = 1));
  Check('a reader''s own name kept', Meta.Reader = 'second (own name)', Meta.Reader);
  Check('no lines from the reader before', Length(Meta.Lines) = 0, IntToStr(Length(Meta.Lines)));

  ClearMetadata(Meta);
  Check('ClearMetadata', (Meta.Reader = '') and (Meta.PixelSizeX = 0) and (Length(Meta.Lines) = 0));
end;

{ ---- Overlay layers ---- }

type
  { Takes left clicks and counts what it heard. }
  TClickLayer = class(TOverlayLayer)
  public
    Heard: Integer;
    LastX, LastY: Integer;
    FPicture: TBGRABitmap;
    destructor Destroy; override;
    function Picture(AView: TObject; AWidth, AHeight: Integer; out ALeft, ATop: Integer): TBGRABitmap; override;
    function Version: Cardinal; override;
    function HandleMouse(AView: TObject; AKind: TOverlayMouseKind; AButton: TOverlayButton;
      AX, AY, AWheel: Integer): Boolean; override;
  end;

  TChangeListener = class
  public
    Calls: Integer;
    LastSender: TObject;
    procedure Changed(Sender: TObject);
  end;

destructor TClickLayer.Destroy;
begin
  FPicture.Free;
  inherited Destroy;
end;

{ A box a quarter of the view, in its middle. }
function TClickLayer.Picture(AView: TObject; AWidth, AHeight: Integer;
  out ALeft, ATop: Integer): TBGRABitmap;
begin
  ALeft := AWidth div 2 - AWidth div 8;
  ATop := AHeight div 2 - AHeight div 8;
  AWidth := AWidth div 4;
  AHeight := AHeight div 4;
  if (FPicture = nil) or (FPicture.Width <> AWidth) or (FPicture.Height <> AHeight) then
  begin
    FreeAndNil(FPicture);
    FPicture := TBGRABitmap.Create(AWidth, AHeight);
  end;
  Result := FPicture;
end;

function TClickLayer.Version: Cardinal;
begin
  Result := Cardinal(Heard);
end;

function TClickLayer.HandleMouse(AView: TObject; AKind: TOverlayMouseKind;
  AButton: TOverlayButton; AX, AY, AWheel: Integer): Boolean;
begin
  Inc(Heard);
  LastX := AX;
  LastY := AY;
  Result := (AKind = omDown) and (AButton = obLeft);
end;

procedure TChangeListener.Changed(Sender: TObject);
begin
  Inc(Calls);
  LastSender := Sender;
end;

procedure TestLayers;
var
  Plain: TOverlayLayer;
  Click: TClickLayer;
  Listener: TChangeListener;
  Pic: TBGRABitmap;
  PicLeft, PicTop: Integer;
begin
  WriteLn('Overlay layers');
  Check('none registered', OverlayLayerCount = 0, IntToStr(OverlayLayerCount));
  Check('index 0 of none = nil', OverlayLayer(0) = nil);
  RegisterOverlayLayer(nil);
  Check('nil not registered', OverlayLayerCount = 0, IntToStr(OverlayLayerCount));

  Plain := TOverlayLayer.Create;
  RegisterOverlayLayer(Plain);
  Click := TClickLayer.Create;
  RegisterOverlayLayer(Click);
  Check('two registered', OverlayLayerCount = 2, IntToStr(OverlayLayerCount));
  Check('in order', (OverlayLayer(0) = Plain) and (OverlayLayer(1) = Click));
  Check('index -1 = nil', OverlayLayer(-1) = nil);
  Check('index 2 = nil', OverlayLayer(2) = nil);

  Check('default: no picture', Plain.Picture(nil, 640, 480, PicLeft, PicTop) = nil);
  Check('default: at 0, 0', (PicLeft = 0) and (PicTop = 0));
  Check('default: version 0', Plain.Version = 0);
  Check('default: takes no mouse', not Plain.HandleMouse(nil, omDown, obLeft, 1, 2, 0));

  Pic := Click.Picture(nil, 320, 200, PicLeft, PicTop);
  Check('own picture, its own size', (Pic <> nil) and (Pic.Width = 80) and (Pic.Height = 50));
  Check('its place', (PicLeft = 120) and (PicTop = 75), Format('%d, %d', [PicLeft, PicTop]));
  Check('kept by the layer', Click.Picture(nil, 320, 200, PicLeft, PicTop) = Pic);
  Check('takes a left click', Click.HandleMouse(nil, omDown, obLeft, 10, 20, 0));
  Check('not a move', not Click.HandleMouse(nil, omMove, obOther, 11, 21, 0));
  Check('heard both, version changed', (Click.Heard = 2) and (Click.Version = 2)
    and (Click.LastX = 11) and (Click.LastY = 21));

  { No listener: nothing happens. }
  OnOverlayChanged := nil;
  OverlayChanged(Click);
  Check('no listener: no fault', True);
  Listener := TChangeListener.Create;
  try
    OnOverlayChanged := @Listener.Changed;
    OverlayChanged(Click);
    OverlayChanged(Plain);
    Check('listener called twice', Listener.Calls = 2, IntToStr(Listener.Calls));
    Check('with the layer', Listener.LastSender = Plain);
  finally
    OnOverlayChanged := nil;
    Listener.Free;
  end;
  { The registry frees both layers at the end of the program. }
end;

{ ---- Menu entries ---- }

var
  ActionCalls: Integer;
  ActionViewer: TObject;

procedure CountAction(AViewer: TObject);
begin
  Inc(ActionCalls);
  ActionViewer := AViewer;
end;

function AlwaysTrue(AViewer: TObject): Boolean;
begin
  Result := True;
end;

procedure TestMenu;
var
  Entry: TExtensionMenuEntry;
  Viewer: TObject;
begin
  WriteLn('Menu entries');
  Check('none registered', MenuEntryCount = 0, IntToStr(MenuEntryCount));
  RegisterMenuEntry('No action', nil);
  Check('without an action: not registered', MenuEntryCount = 0, IntToStr(MenuEntryCount));
  RegisterMenuEntry('Measurement', @CountAction, @AlwaysTrue);
  RegisterMenuEntry('Scale bar', @CountAction, nil, @AlwaysTrue);
  Check('two registered', MenuEntryCount = 2, IntToStr(MenuEntryCount));
  Entry := MenuEntry(0);
  Check('caption', Entry.Caption = 'Measurement', Entry.Caption);
  Check('enabled test kept, no checked test',
    Assigned(Entry.IsEnabled) and not Assigned(Entry.IsChecked));
  Entry := MenuEntry(1);
  Check('second: checked test, no enabled test',
    Assigned(Entry.IsChecked) and not Assigned(Entry.IsEnabled));
  Viewer := TObject.Create;
  try
    Entry.Action(Viewer);
    Check('action gets the viewer', (ActionCalls = 1) and (ActionViewer = Viewer));
  finally
    Viewer.Free;
  end;
end;

{ ---- ZIP / CBZ as containers (1.1) ---- }

procedure TestZip;
var
  Dir, ZipName, Why: string;
  Bmp: TBGRABitmap;
  Z: TZipper;
  E: TContainerEntryArray;
  W, H: Integer;
  RGBA: TBytes;
  Names: TStringArray;
  Size: Int64;
  Time: TDateTime;
begin
  WriteLn('uZipContainer');
  Dir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'vv_zip_test' + PathDelim;
  ForceDirectories(Dir + 'sub');
  { Three pictures (page10 before page2 in the archive), a text, a
    sub-folder's picture. }
  Bmp := TBGRABitmap.Create(4, 3, BGRA(200, 10, 20, 255));
  try
    Bmp.SaveToFile(Dir + 'page2.png');
    Bmp.SaveToFile(Dir + 'page10.png');
    Bmp.SaveToFile(Dir + 'page1.png');
    Bmp.SaveToFile(Dir + 'sub' + PathDelim + 'x.png');
  finally
    Bmp.Free;
  end;
  with TStringList.Create do
  try
    Text := 'not a picture';
    SaveToFile(Dir + 'notes.txt');
  finally
    Free;
  end;
  ZipName := Dir + 'comic.cbz';
  DeleteFile(ZipName);
  Z := TZipper.Create;
  try
    Z.FileName := ZipName;
    Z.Entries.AddFileEntry(Dir + 'page10.png', 'page10.png');
    Z.Entries.AddFileEntry(Dir + 'page2.png', 'page2.png');
    Z.Entries.AddFileEntry(Dir + 'notes.txt', 'notes.txt');
    Z.Entries.AddFileEntry(Dir + 'page1.png', 'page1.png');
    Z.Entries.AddFileEntry(Dir + 'sub' + PathDelim + 'x.png', 'sub/x.png');
    Z.ZipAllFiles;
  finally
    Z.Free;
  end;
  Check('.cbz is a container', IsContainerName(ZipName));
  Check('.zip is a container', IsContainerName(Dir + 'a.ZIP'));
  Check('listed', ListZip(ZipName, E) and (Length(E) = 4), IntToStr(Length(E)));
  if Length(E) = 4 then
  begin
    Check('natural order: page1, page2, page10, sub/x', (E[0].Name = 'page1.png') and (E[1].Name = 'page2.png')
      and (E[2].Name = 'page10.png') and (E[3].Name = 'sub/x.png'),
      E[0].Name + ' ' + E[1].Name + ' ' + E[2].Name + ' ' + E[3].Name);
    Check('an id has no slash', (Pos('/', E[3].Id) = 0) and (E[3].Id = 'sub~x.png'), E[3].Id);
    Check('decoded: 4 x 3, its colour', DecodeZipEntry(ZipName, E[3].Id, nil, W, H, RGBA, Why)
      and (W = 4) and (H = 3) and (Length(RGBA) = 48) and (RGBA[0] = 200) and (RGBA[1] = 10)
      and (RGBA[2] = 20) and (RGBA[3] = 255), Why);
  end;
  Check('a missing entry: not decoded, said why', not DecodeZipEntry(ZipName, 'nope.png', nil, W, H, RGBA, Why)
    and (Why <> ''), Why);
  Check('through uContainers: four virtual names', ListContainer(ZipName, Names, Size, Time)
    and (Length(Names) = 4) and IsVirtualName(Names[0]), IntToStr(Length(Names)));
  ArchivesEnabled := False;
  Check('archives off: nothing listed', not ListZip(ZipName, E));
  ArchivesEnabled := True;
  Check('not an archive: nothing', not ListZip(Dir + 'notes.txt', E));
end;

begin
  PassCount := 0;
  FailCount := 0;
  WriteLn('VersariteViewer plug-in points test (M0)');
  TestEdition;
  TestMetadata;
  TestLayers;
  TestMenu;
  TestZip;
  WriteLn;
  WriteLn(Format('%d passed, %d failed', [PassCount, FailCount]));
  if FailCount > 0 then
    ExitCode := 1;
end.
