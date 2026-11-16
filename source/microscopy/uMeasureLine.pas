unit uMeasureLine;

{
  Unit: uMeasureLine

  Purpose
  -------
  The measuring line (M3b, Day 25; spec "Microscopy edition" §7.2): two
  right-click entries.
  - "Measurement": on images with a scale (uImageScale). Click - follow
    - click (user: no dragging): the first left click sets the start, a
    straight line follows the mouse, the second click ends it. Its
    length at the line: the µm only (Day 26, user: no second line).
    Shift held: horizontal or vertical.
  - "Reference measurement (calibrate)": on any image. The same line
    over a known object (a stage micrometer); after the second click a
    dialog asks the known length and names the calibration
    (uCalibrationDialog); it goes into calibrations.ini and is chosen.
  A right click leaves the mode (no menu then); a new left click starts
  a new line; the line stays until the next image or the next line.
  Several lines (Day 26, user): Shift held at a line's first click keeps
  the lines drawn before (without Shift a new line replaces them); each
  has its own label. (Shift pressed again while the line follows
  makes it horizontal or vertical; held on from the first click it
  doesn't.) A reference measurement is always one line.
  The line is a single line and its label simple text, in the marks'
  colour (Day 29, user: no dark rim, no outline, no box; no longer the
  info line's OverlaySolid). A reference measurement stays yellow.
  "Apply filters to a copy" draws a finished line into the copy, upright
  and sized for the copy (Day 26, user; uExtensions' burn-in); its
  length goes into the copy's name ('_56.32um').
  Day 28 (user): while the mode waits for a click, resting the mouse
  shows the aiming loupe (TMView's, uExtensions' ShowAimLoupe) centred
  on the point the click will set; and a line can be undone (uMarkUndo): Undo puts
  the lines back as they were before it (also the ones a new line
  replaced).

  Owns
  ----
  - The line (in pixels of the original image, so zoom, pan and turning
    keep it in place) and its picture (only as large as the line and
    its label).

  Knows
  -----
  - The renderer (AView: TRenderer), during a paint and a mouse event;
    the last image painted (for the menu's enabled test).

  Does NOT
  --------
  - Hear Esc (keys go to the mouse language): the right click leaves.
  - Keep lines across images.

  Threads
  -------
  UI thread (paint, mouse, menu).

  Uses (MView units)
  ------------------
  implementation: uCommands, uRenderer, uExtensions, uImageScale,
                  uCalibrations, uCalibrationDialog
  Libraries:      Types, SysUtils, Math, Forms, LCLType, LCLIntf,
                  BGRABitmap, BGRABitmapTypes

  Used by
  -------
  VersariteImageLab.lpr (its uses list), uCalibrationPanel
}

{$mode ObjFPC}{$H+}

interface

{ Starts the reference measurement (the left panel's selector offers
  it too). }
procedure StartReferenceMeasurement;
{ The scale bar starts (1.1): a line being drawn goes, the mode ends
  (finished lines stay). One tool at a time. }
procedure LeaveMeasurement;
{ The measuring line (or a reference measurement) is on (Day 28: the
  left panel's style rows). }
function MeasurementActive: Boolean;
{ The finished measuring lines of AImageName (Day 29, to Fiji as ROIs):
  how many, and one (image pixels; its length as drawn, '56.32 µm').
  None for a reference measurement or another image. }
function MeasureLineCount(const AImageName: string): Integer;
function MeasureLineGet(const AImageName: string; AIndex: Integer;
  out AX0, AY0, AX1, AY1: Double; out AText: string): Boolean;

implementation

uses
  Types,
  SysUtils,
  Math,
  Forms,
  LCLType,
  LCLIntf,
  BGRABitmap,
  BGRABitmapTypes,
  uCommands,
  uRenderer,
  uExtensions,
  uImageScale,
  uCalibrations,
  uCalibrationDialog,
  uScaleBar,
  uTextLabel,
  uMarkUndo,
  uMarkMemory;

const
  LabelFontPt = 10;
  LabelPad = 4;
  Margin = 12;            { around the line in its picture, screen px }
  TickHalf = 6;           { the end marks, half length, screen px }

type
  TMeasureState = (msOff, msWaiting, msFollowing, msDone);

  { A line in image pixels. }
  TMeasureSeg = record
    X0, Y0, X1, Y1: Double;
  end;

  TMeasureLine = class(TOverlayLayer)
  private
    FState: TMeasureState;
    FReference: Boolean;        { the reference measurement (calibrate) }
    FLines: array of TMeasureSeg;   { the finished lines (Day 26: several) }
    FX0, FY0, FX1, FY1: Double; { the line being drawn / the last one, image pixels }
    FLineImage: string;         { the image the lines belong to }
    FSolid: Boolean;            { the labels on a solid box ([View] OverlaySolid, last paint) }
    FShiftFromStart: Boolean;   { Shift held since the line's first click (no snapping) }
    { The last paint: which image, its size (the menu asks). }
    FImageName: string;
    FImageW, FImageH: Integer;
    FPicture: TBGRABitmap;
    FPictureKey: string;        { what FPicture shows }
    FPictureLeft, FPictureTop: Integer;
    FVersion: Cardinal;
    { The lines before the line being drawn (Day 28): for Undo, handed
      in when that line is finished (or when it replaced lines and is
      dropped). }
    FPending: TMarkSnapshot;
    procedure Changed;
    function MakeSnapshot: TMarkSnapshot;
    procedure Aim(ARenderer: TRenderer; AX, AY: Integer);
    procedure Start(AReference: Boolean);
    procedure Leave;
    procedure EndPoint(ARenderer: TRenderer; AX, AY: Integer; out AImgX, AImgY: Double);
    procedure Finish;
    function LengthText(const ASeg: TMeasureSeg): string;
    function CurrentSeg: TMeasureSeg;
  public
    destructor Destroy; override;
    function Picture(AView: TObject; AWidth, AHeight: Integer;
      out ALeft, ATop: Integer): TBGRABitmap; override;
    function Version: Cardinal; override;
    function HandleMouse(AView: TObject; AKind: TOverlayMouseKind; AButton: TOverlayButton;
      AX, AY, AWheel: Integer): Boolean; override;
    function CanBurnIn(const AImageName: string): Boolean; override;
    function BurnIn(ABitmap: TBGRABitmap; const AImageName: string;
      const AMap: TBurnInMap): string; override;
    function SvgLayerName: string; override;
    function SvgMarkup(const AImageName: string; const AMap: TBurnInMap): string; override;
    function HasScale: Boolean;
    function HasImage: Boolean;
    property State: TMeasureState read FState;
    property Reference: Boolean read FReference;
  end;

var
  Measure: TMeasureLine = nil;   { owned by uExtensions' registry }

type
  { The lines as they were (Day 28, Undo). }
  TMeasureSnapshot = class(TMarkSnapshot)
  public
    Lines: array of TMeasureSeg;
    LineImage: string;
    procedure Restore; override;
  end;

procedure TMeasureSnapshot.Restore;
begin
  if Measure = nil then
    Exit;
  FreeAndNil(Measure.FPending);
  Measure.FLines := Copy(Lines);
  Measure.FLineImage := LineImage;
  Measure.FReference := False;
  Measure.FState := msOff;
  HideAimLoupe;
  Measure.Changed;
end;

{ '56.32 µm': two decimals below 100 µm, one up to 1000, none above. }
function MicronText(AValue: Double): string;
begin
  if Abs(AValue) < 100 then
    Result := FormatFloat('0.00', AValue)
  else if Abs(AValue) < 1000 then
    Result := FormatFloat('0.0', AValue)
  else
    Result := FormatFloat('0', AValue);
  Result := Result + ' µm';
end;

{ TMeasureLine }

type
  { The finished lines kept for their image while another is shown
    (Day 29, uMarkMemory). }
  TMeasureMemo = class
  public
    Lines: array of TMeasureSeg;
  end;

const
  MemoryTool = 'measure';

destructor TMeasureLine.Destroy;
begin
  FPending.Free;
  FPicture.Free;
  inherited Destroy;
end;

function TMeasureLine.MakeSnapshot: TMarkSnapshot;
var
  S: TMeasureSnapshot;
begin
  S := TMeasureSnapshot.Create;
  S.Lines := Copy(FLines);
  S.LineImage := FLineImage;
  Result := S;
end;

{ The aiming loupe (Day 28): the point a click would set - the mouse,
  or the line's end while it follows (Shift may square it); TMView
  shows the loupe there when the mouse rests. }
procedure TMeasureLine.Aim(ARenderer: TRenderer; AX, AY: Integer);
var
  PX, PY, FX, FY: Double;
begin
  if FState = msFollowing then
  begin
    ARenderer.ImageToScreen(FX1, FY1, PX, PY);
    ARenderer.ImageToScreen(FX0, FY0, FX, FY);
  end
  else
  begin
    PX := AX + 0.5;
    PY := AY + 0.5;
    FX := PX - 1;
    FY := PY - 1;
  end;
  ShowAimLoupe(PX, PY, FX, FY);
end;

procedure TMeasureLine.Changed;
begin
  FPictureKey := '';            { draw again }
  OverlayChanged(Self);
end;

procedure TMeasureLine.Start(AReference: Boolean);
begin
  LeaveScaleBar;               { one tool at a time (1.1) }
  LeaveTextLabels;
  ReloadMarkStyle;             { [ScaleBar] look, edited meanwhile (1.1) }
  FReference := AReference;
  FState := msWaiting;
  { A reference measurement is one line of its own (the lines before
    can be undone back). }
  if AReference and (Length(FLines) > 0) then
  begin
    PushMarkUndo(MakeSnapshot, FLineImage, 'Undo measurement');
    FLines := nil;
  end;
  Changed;
end;

function TMeasureLine.CurrentSeg: TMeasureSeg;
begin
  Result.X0 := FX0;
  Result.Y0 := FY0;
  Result.X1 := FX1;
  Result.Y1 := FY1;
end;

procedure TMeasureLine.Leave;
begin
  { A line being drawn goes; the finished ones stay (until the next
    image). If it had replaced lines, Undo brings them back. }
  if (FState = msFollowing) and (FPending <> nil)
    and (Length(TMeasureSnapshot(FPending).Lines) <> Length(FLines)) then
  begin
    PushMarkUndo(FPending, FLineImage, 'Undo measurement');
    FPending := nil;
  end;
  FreeAndNil(FPending);
  FState := msOff;
  HideAimLoupe;
  Changed;
end;

function MeasureLineCount(const AImageName: string): Integer;
begin
  Result := 0;
  if (Measure = nil) or Measure.FReference or (AImageName = '')
    or (AImageName <> Measure.FLineImage) then
    Exit;
  Result := Length(Measure.FLines);
end;

function MeasureLineGet(const AImageName: string; AIndex: Integer;
  out AX0, AY0, AX1, AY1: Double; out AText: string): Boolean;
begin
  AX0 := 0;
  AY0 := 0;
  AX1 := 0;
  AY1 := 0;
  AText := '';
  Result := (AIndex >= 0) and (AIndex < MeasureLineCount(AImageName));
  if not Result then
    Exit;
  AX0 := Measure.FLines[AIndex].X0;
  AY0 := Measure.FLines[AIndex].Y0;
  AX1 := Measure.FLines[AIndex].X1;
  AY1 := Measure.FLines[AIndex].Y1;
  AText := Measure.LengthText(Measure.FLines[AIndex]);
end;

function TMeasureLine.HasImage: Boolean;
begin
  Result := (FImageName <> '') and (FImageW > 0) and (FImageH > 0);
end;

function TMeasureLine.HasScale: Boolean;
var
  Scale: TImageScale;
begin
  Result := HasImage and ScaleFor(FImageName, FImageW, FImageH, Scale);
end;

{ The mouse in image pixels, inside the image; Shift: horizontal or
  vertical from the start. }
procedure TMeasureLine.EndPoint(ARenderer: TRenderer; AX, AY: Integer; out AImgX, AImgY: Double);
begin
  if not ARenderer.ScreenToImage(AX + 0.5, AY + 0.5, AImgX, AImgY) then
  begin
    AImgX := FX1;
    AImgY := FY1;
    Exit;
  end;
  AImgX := EnsureRange(AImgX, 0, FImageW);
  AImgY := EnsureRange(AImgY, 0, FImageH);
  { Shift held from the first click (it kept the earlier lines) doesn't
    snap; pressed again while following, it does. }
  if GetKeyState(VK_SHIFT) >= 0 then
    FShiftFromStart := False;
  if (FState = msFollowing) and (GetKeyState(VK_SHIFT) < 0) and not FShiftFromStart then
  begin
    if Abs(AImgX - FX0) >= Abs(AImgY - FY0) then
      AImgY := FY0
    else
      AImgX := FX0;
  end;
end;

{ '12.34 µm'; '105.2 px' without a scale and while calibrating (the
  dialog asks the µm). }
function TMeasureLine.LengthText(const ASeg: TMeasureSeg): string;
var
  Scale: TImageScale;
  Um: Double;
begin
  if (not FReference) and ScaleFor(FLineImage, FImageW, FImageH, Scale) then
  begin
    Um := Hypot((ASeg.X1 - ASeg.X0) * Scale.UmPerPixelX, (ASeg.Y1 - ASeg.Y0) * Scale.UmPerPixelY);
    Result := MicronText(Um);
  end
  else
    Result := FormatFloat('0.0', Hypot(ASeg.X1 - ASeg.X0, ASeg.Y1 - ASeg.Y0)) + ' px';
end;

{ The second click of a reference measurement: the dialog. }
procedure TMeasureLine.Finish;
var
  Scale: TImageScale;
  FileUm: Double;
  FileSource: string;
  Meta: TImageMetadata;
  Cal: TCalibration;
  Px: Double;
  Asked: Boolean;
begin
  if not FReference then
    Exit;
  Px := Hypot(FX1 - FX0, FY1 - FY0);
  if Px < 2 then
    Exit;                        { a click, not a line }
  FileUm := 0;
  FileSource := '';
  { What the file says (microscope, objective, zoom: the dialog fills
    them in), and its own scale (or a matching .lif's) to compare with
    or to take over - never a chosen calibration. }
  if not ReadImageMetadata(FLineImage, Meta) then
    ClearMetadata(Meta);
  { (A crop's inherited scale counts too: it has no metadata of its own.) }
  if ScaleFor(FLineImage, FImageW, FImageH, Scale)
    and (Pos('calibration:', Scale.Source) <> 1) then
  begin
    FileUm := Hypot((FX1 - FX0) * Scale.UmPerPixelX, (FY1 - FY0) * Scale.UmPerPixelY);
    FileSource := Scale.Source;
    if FileSource = '' then
      FileSource := 'the file';
  end;
  { The pointer stays over the view behind the dialog. }
  NoteMenuOpen(True);
  try
    { A crop's calibration holds for its original's width (1.1). }
    Asked := AskReferenceCalibration(Px, CalibrationWidthFor(FLineImage, FImageW),
      Meta.Microscope, Meta.Objective, Meta.Zoom,
      FileUm, FileSource, Cal);
  finally
    NoteMenuOpen(False);
  end;
  if Asked then
  begin
    if Calibrations.Put(Cal) >= 0 then
    begin
      try
        Calibrations.SaveToFile(DefaultCalibrationFile);
      except
        on E: Exception do
          Application.MessageBox(PChar('calibrations.ini could not be written: ' + E.Message),
            'Calibration', MB_OK or MB_ICONWARNING);
      end;
      ChooseCalibration(Cal.Name);
      { Done calibrating: the line stays, now measured in µm. }
      FReference := False;
    end
    else
      Application.MessageBox(PChar(Format('Too many calibrations (%d): delete one in the '
        + 'settings first.', [MaxCalibrations])), 'Calibration', MB_OK or MB_ICONWARNING);
  end;
  { Not calibrated (cancelled, or no room): the reference line goes - it
    is no measurement. }
  if FReference then
    FLines := nil;
  FState := msOff;
  HideAimLoupe;
  Changed;
end;

function TMeasureLine.HandleMouse(AView: TObject; AKind: TOverlayMouseKind;
  AButton: TOverlayButton; AX, AY, AWheel: Integer): Boolean;
var
  Renderer: TRenderer;
  ImgX, ImgY: Double;
begin
  Result := False;
  { A release reaches a layer only when it took the press (TMView's
    capture): keep it, and after the second click of a reference
    measurement open the dialog - after the release, not inside the
    press. }
  if AKind = omUp then
  begin
    Result := True;
    if (AButton = obLeft) and (FState = msDone) and FReference then
      Finish;
    Exit;
  end;
  if (FState = msOff) or not (AView is TRenderer) then
    Exit;
  Renderer := TRenderer(AView);
  case AKind of
    omMove:
      begin
        if FState = msFollowing then
        begin
          EndPoint(Renderer, AX, AY, ImgX, ImgY);
          if (ImgX <> FX1) or (ImgY <> FY1) then
          begin
            FX1 := ImgX;
            FY1 := ImgY;
            Changed;
          end;
        end;
        { Waiting for a click: the loupe (Day 28). }
        if (FState in [msWaiting, msFollowing, msDone]) and HasImage then
          Aim(Renderer, AX, AY);
      end;

    omDown:
      case AButton of
        obLeft:
          begin
            Result := True;
            if (Renderer.Image = nil) or not HasImage then
              Exit;
            if FState in [msWaiting, msDone] then
            begin
              { The first click: the start. Shift held: the lines drawn
                before stay (Day 26, user); else this one replaces them.
                A reference measurement is one line. }
              EndPoint(Renderer, AX, AY, ImgX, ImgY);
              { The lines as they are, for Undo (Day 28). }
              FreeAndNil(FPending);
              if FLineImage = FImageName then
                FPending := MakeSnapshot
              else
                FPending := TMeasureSnapshot.Create;
              if FReference or (GetKeyState(VK_SHIFT) >= 0) or (FLineImage <> FImageName) then
                FLines := nil;
              FShiftFromStart := GetKeyState(VK_SHIFT) < 0;
              FX0 := ImgX;
              FY0 := ImgY;
              FX1 := ImgX;
              FY1 := ImgY;
              FLineImage := FImageName;
              FState := msFollowing;
              Changed;
            end
            else if FState = msFollowing then
            begin
              { The second click: the end; the line joins the finished
                ones. }
              EndPoint(Renderer, AX, AY, ImgX, ImgY);
              FX1 := ImgX;
              FY1 := ImgY;
              SetLength(FLines, Length(FLines) + 1);
              FLines[High(FLines)] := CurrentSeg;
              FState := msDone;
              { Undo: back to the lines before it. }
              if FPending <> nil then
              begin
                TMeasureSnapshot(FPending).LineImage := FLineImage;
                PushMarkUndo(FPending, FLineImage, 'Undo measurement');
                FPending := nil;
              end;
              Changed;
            end;
          end;
        obRight:
          begin
            Result := True;            { no menu: it leaves the mode }
            Leave;
          end;
      end;
  end;
end;

{ The label's place for a line from (X0, Y0) to (X1, Y1): beside its
  middle, on the upper / left side, clear of the line also when it is
  steep (the box is wide). ANX, ANY: the unit normal towards it; ALen:
  the line's length. }
procedure PlaceLabel(X0, Y0, X1, Y1: Double; ABoxW, ABoxH: Integer; AGap: Double;
  out ANX, ANY, AMX, AMY, ALen: Double);
var
  Off: Double;
begin
  ALen := Hypot(X1 - X0, Y1 - Y0);
  if ALen > 0.5 then
  begin
    ANX := (Y0 - Y1) / ALen;
    ANY := (X1 - X0) / ALen;
    if (ANY > 0) or ((ANY = 0) and (ANX > 0)) then
    begin
      ANX := -ANX;               { above, or left of a vertical line }
      ANY := -ANY;
    end;
  end
  else
  begin
    ANX := 0;
    ANY := -1;
  end;
  Off := Abs(ANX) * ABoxW / 2 + Abs(ANY) * ABoxH / 2 + AGap;
  AMX := (X0 + X1) / 2 + ANX * Off;
  AMY := (Y0 + Y1) / 2 + ANY * Off;
end;

{ The line with its end marks and its label at ABoxX, ABoxY, all in
  ALight: a single line and simple text (Day 29, user). All in ABitmap's
  pixels; ABitmap's FontHeight is set. }
procedure DrawMeasure(ABitmap: TBGRABitmap; X0, Y0, X1, Y1, ANX, ANY, ALen: Double;
  ABoxX, ABoxY, APad: Integer; const AText: string; ALight: TBGRAPixel;
  AThick, ATick: Single);
begin
  ABitmap.DrawLineAntialias(X0, Y0, X1, Y1, ALight, AThick);
  { End marks, across the line. }
  if ALen > 0.5 then
  begin
    ABitmap.DrawLineAntialias(X0 - ANX * ATick, Y0 - ANY * ATick, X0 + ANX * ATick,
      Y0 + ANY * ATick, ALight, AThick);
    ABitmap.DrawLineAntialias(X1 - ANX * ATick, Y1 - ANY * ATick, X1 + ANX * ATick,
      Y1 + ANY * ATick, ALight, AThick);
  end;
  ABitmap.TextOut(ABoxX + APad, ABoxY + APad, AText, ALight);
end;

type
  { One line as drawn: on screen (or in a copy), its label and box. }
  TDrawnSeg = record
    X0, Y0, X1, Y1, NX, NY, MX, MY, Len: Double;
    Text: string;
    BoxW, BoxH: Integer;
  end;

function TMeasureLine.Picture(AView: TObject; AWidth, AHeight: Integer;
  out ALeft, ATop: Integer): TBGRABitmap;
var
  Renderer: TRenderer;
  Name, Key: string;
  Segs: array of TMeasureSeg;
  Drawn: array of TDrawnSeg;
  I, L, T, R, B, W, H, FontPx, BoxX, BoxY: Integer;
  TextSz: TSize;
  Light: TBGRAPixel;
  Thick: Single;
  Memo: TMeasureMemo;
  Recalled: TObject;
begin
  ALeft := 0;
  ATop := 0;
  Result := nil;
  if not (AView is TRenderer) then
    Exit;
  Renderer := TRenderer(AView);
  if (Renderer.Image = nil) or Renderer.Image.IsError then
  begin
    FImageName := '';
    Exit;
  end;
  { Remember the image (the menu asks); a new image: the lines go. }
  Name := Renderer.Image.Key.FileName;
  FImageName := Name;
  FImageW := Renderer.Image.FullWidth;
  FImageH := Renderer.Image.FullHeight;
  if (FImageW <= 0) or (FImageH <= 0) then
  begin
    FImageW := Renderer.Image.Width;
    FImageH := Renderer.Image.Height;
  end;
  FSolid := False;                  { Day 29: never a box }
  if (Name <> FLineImage) and ((Length(FLines) > 0) or (FState = msFollowing)) then
  begin
    { Kept for their image (Day 29, user: the marks come back with the
      image); a reference measurement is no measurement. }
    if (Length(FLines) > 0) and not FReference then
    begin
      Memo := TMeasureMemo.Create;
      Memo.Lines := Copy(FLines);
      RememberMarks(MemoryTool, FLineImage, Memo);
    end;
    FLines := nil;
    { Not this image's any more (back on it, its lines come back). }
    FLineImage := '';
    if FState in [msFollowing, msDone] then
      FState := msWaiting;
  end;
  { Back on an image that had lines: they are there again. }
  if (Name <> FLineImage) and (Length(FLines) = 0) and not FReference then
  begin
    Recalled := RecallMarks(MemoryTool, Name);
    if Recalled is TMeasureMemo then
    begin
      FLines := Copy(TMeasureMemo(Recalled).Lines);
      FLineImage := Name;
    end;
    Recalled.Free;
  end;
  { What to draw: the finished lines and the one being drawn. }
  Segs := Copy(FLines);
  if FState = msFollowing then
  begin
    SetLength(Segs, Length(Segs) + 1);
    Segs[High(Segs)] := CurrentSeg;
  end;
  if Length(Segs) = 0 then
    Exit;

  FontPx := Max(8, Round(LabelFontPt * Screen.PixelsPerInch / 72));
  if FPicture = nil then
    FPicture := TBGRABitmap.Create(1, 1);
  FPicture.FontQuality := fqFineAntialiasing;
  SetMarkFont(FPicture, FontPx);    { [ScaleBar] Font / FontSize / Bold (1.1) }
  SetLength(Drawn, Length(Segs));
  if FReference then
    Light := BGRA(255, 215, 40, 255)   { calibrating: yellow }
  else
    Light := MarkColour(BGRAWhite);    { [ScaleBar] Color (1.1) }
  Key := Format('%d %d %s %s %d %d %d %s %d %d', [AWidth, AHeight, BoolToStr(FReference, True),
    BoolToStr(FSolid, True), Light.red, Light.green, Light.blue, FPicture.FontName,
    FPicture.FontHeight, MarkStyleVersion]);
  for I := 0 to High(Segs) do
  begin
    Renderer.ImageToScreen(Segs[I].X0, Segs[I].Y0, Drawn[I].X0, Drawn[I].Y0);
    Renderer.ImageToScreen(Segs[I].X1, Segs[I].Y1, Drawn[I].X1, Drawn[I].Y1);
    Drawn[I].Text := LengthText(Segs[I]);
    Key := Key + Format('|%.1f %.1f %.1f %.1f ', [Drawn[I].X0, Drawn[I].Y0, Drawn[I].X1,
      Drawn[I].Y1]) + Drawn[I].Text;
  end;
  if (FPicture <> nil) and (Key = FPictureKey) then
  begin
    ALeft := FPictureLeft;
    ATop := FPictureTop;
    Exit(FPicture);
  end;

  { The labels' sizes first: the picture holds the lines and labels. }
  L := MaxInt;
  T := MaxInt;
  R := -MaxInt;
  B := -MaxInt;
  for I := 0 to High(Drawn) do
  begin
    TextSz := FPicture.TextSize(Drawn[I].Text);
    Drawn[I].BoxW := TextSz.cx + 2 * LabelPad;
    Drawn[I].BoxH := TextSz.cy + 2 * LabelPad;
    PlaceLabel(Drawn[I].X0, Drawn[I].Y0, Drawn[I].X1, Drawn[I].Y1, Drawn[I].BoxW, Drawn[I].BoxH,
      8, Drawn[I].NX, Drawn[I].NY, Drawn[I].MX, Drawn[I].MY, Drawn[I].Len);
    L := Min(L, Floor(Min(Min(Drawn[I].X0, Drawn[I].X1), Drawn[I].MX - Drawn[I].BoxW / 2)));
    T := Min(T, Floor(Min(Min(Drawn[I].Y0, Drawn[I].Y1), Drawn[I].MY - Drawn[I].BoxH / 2)));
    R := Max(R, Ceil(Max(Max(Drawn[I].X0, Drawn[I].X1), Drawn[I].MX + Drawn[I].BoxW / 2)));
    B := Max(B, Ceil(Max(Max(Drawn[I].Y0, Drawn[I].Y1), Drawn[I].MY + Drawn[I].BoxH / 2)));
  end;
  { The picture: all of them, inside the view. }
  L := Max(L - Margin, 0);
  T := Max(T - Margin, 0);
  R := Min(R + Margin, AWidth);
  B := Min(B + Margin, AHeight);
  W := R - L;
  H := B - T;
  if (W <= 0) or (H <= 0) then
    Exit;
  FPicture.SetSize(W, H);
  FPicture.FillTransparent;
  Thick := Max(1.5, Screen.PixelsPerInch / 96 * 1.5);
  for I := 0 to High(Drawn) do
  begin
    { Each label kept inside the picture. }
    BoxX := EnsureRange(Round(Drawn[I].MX - Drawn[I].BoxW / 2) - L, 0, Max(0, W - Drawn[I].BoxW));
    BoxY := EnsureRange(Round(Drawn[I].MY - Drawn[I].BoxH / 2) - T, 0, Max(0, H - Drawn[I].BoxH));
    DrawMeasure(FPicture, Drawn[I].X0 - L, Drawn[I].Y0 - T, Drawn[I].X1 - L, Drawn[I].Y1 - T,
      Drawn[I].NX, Drawn[I].NY, Drawn[I].Len, BoxX, BoxY, LabelPad, Drawn[I].Text, Light,
      Thick, TickHalf);
  end;

  FPictureKey := Key;
  FPictureLeft := L;
  FPictureTop := T;
  Inc(FVersion);
  ALeft := L;
  ATop := T;
  Result := FPicture;
end;

{ Finished lines (not a reference measurement) of this image; a line
  being drawn is left out. }
function TMeasureLine.CanBurnIn(const AImageName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  if FReference or (AImageName = '') or (AImageName <> FLineImage) then
    Exit;
  for I := 0 to High(FLines) do
    if Hypot(FLines[I].X1 - FLines[I].X0, FLines[I].Y1 - FLines[I].Y0) >= 1 then
      Exit(True);
end;

{ The lines into the copy, as on screen but sized for the copy: the
  labels about 1/45 of its shorter side high (not smaller than 12 px),
  upright whatever the turn, plain as on screen. }
function TMeasureLine.BurnIn(ABitmap: TBGRABitmap; const AImageName: string;
  const AMap: TBurnInMap): string;
var
  Text: string;
  CX0, CY0, CX1, CY1, Len, NX, NY, MX, MY: Double;
  Short, FontPx, Pad, BoxW, BoxH, BoxX, BoxY, I, Count, Tick: Integer;
  TextSz: TSize;
  Thick: Single;
  K: Double;
begin
  Result := '';
  if (ABitmap = nil) or not CanBurnIn(AImageName) then
    Exit;
  if AMap.ViewScale > 0 then
  begin
    { As on screen (Day 28, user): the screen's sizes in copy pixels at
      the zoom the copy was made at. }
    K := 1 / AMap.ViewScale;
    FontPx := Max(6, Round(LabelFontPt * Screen.PixelsPerInch / 72 * K));
    Pad := Max(1, Round(LabelPad * K));
    Thick := Max(1, Max(1.5, Screen.PixelsPerInch / 96 * 1.5) * K);
    Tick := Max(2, Round(TickHalf * K));
  end
  else
  begin
    Short := Max(1, Min(ABitmap.Width, ABitmap.Height));
    FontPx := Max(12, Round(Short / 45));
    Pad := Max(LabelPad, FontPx div 4);
    Thick := Max(1.5, Short / 600);
    Tick := Max(TickHalf, FontPx div 2);
  end;
  ABitmap.FontQuality := fqFineAntialiasing;
  SetMarkFont(ABitmap, FontPx);
  Count := 0;
  for I := 0 to High(FLines) do
  begin
    if Hypot(FLines[I].X1 - FLines[I].X0, FLines[I].Y1 - FLines[I].Y0) < 1 then
      Continue;
    BurnInPoint(AMap, FLines[I].X0, FLines[I].Y0, CX0, CY0);
    BurnInPoint(AMap, FLines[I].X1, FLines[I].Y1, CX1, CY1);
    Text := LengthText(FLines[I]);
    TextSz := ABitmap.TextSize(Text);
    BoxW := TextSz.cx + 2 * Pad;
    BoxH := TextSz.cy + 2 * Pad;
    PlaceLabel(CX0, CY0, CX1, CY1, BoxW, BoxH, FontPx * 0.6, NX, NY, MX, MY, Len);
    { Inside the copy. }
    BoxX := EnsureRange(Round(MX - BoxW / 2), 0, Max(0, ABitmap.Width - BoxW));
    BoxY := EnsureRange(Round(MY - BoxH / 2), 0, Max(0, ABitmap.Height - BoxH));
    DrawMeasure(ABitmap, CX0, CY0, CX1, CY1, NX, NY, Len, BoxX, BoxY, Pad, Text,
      MarkColour(BGRAWhite), Thick, Tick);
    Inc(Count);
    { For the name: one line its length '56.32um' / '105.2px' (no space,
      no µ, a point); several: their number ('3lines'). }
    if Count = 1 then
      Result := StringReplace(StringReplace(StringReplace(Text, ' ', '', [rfReplaceAll]),
        'µ', 'u', [rfReplaceAll]), ',', '.', [rfReplaceAll])
    else
      Result := IntToStr(Count) + 'lines';
  end;
end;

function TMeasureLine.SvgLayerName: string;
begin
  Result := 'Measurements';
end;

{ As BurnIn, as vectors: each line with its end marks (dark under
  light, a group), its length a text - movable and editable later. }
function TMeasureLine.SvgMarkup(const AImageName: string; const AMap: TBurnInMap): string;
var
  Text: string;
  CX0, CY0, CX1, CY1, Len, NX, NY, MX, MY, Thick, Tick, FontPx: Double;
  Short, BaseFontPx, Pad, BoxW, BoxH, BoxX, BoxY, I: Integer;
  TextSz: TSize;
  Colour: TBGRAPixel;
  Measure: TBGRABitmap;

  function Seg(AX0, AY0, AX1, AY1: Double; const AStroke: string; AWidth: Double): string;
  begin
    Result := '<line x1="' + SvgNum(AX0) + '" y1="' + SvgNum(AY0) + '" x2="' + SvgNum(AX1)
      + '" y2="' + SvgNum(AY1) + '" stroke="' + AStroke + '" stroke-width="' + SvgNum(AWidth)
      + '" stroke-linecap="butt"/>' + LineEnding;
  end;

  function Lines(const AStroke: string; AWidth: Double): string;
  begin
    Result := Seg(CX0, CY0, CX1, CY1, AStroke, AWidth);
    if Len > 0.5 then
      Result := Result
        + Seg(CX0 - NX * Tick, CY0 - NY * Tick, CX0 + NX * Tick, CY0 + NY * Tick, AStroke, AWidth)
        + Seg(CX1 - NX * Tick, CY1 - NY * Tick, CX1 + NX * Tick, CY1 + NY * Tick, AStroke, AWidth);
  end;

begin
  Result := '';
  if not CanBurnIn(AImageName) then
    Exit;
  Short := Max(1, Min(AMap.Width, AMap.Height));
  BaseFontPx := Max(12, Round(Short / 45));
  FontPx := BaseFontPx * MarkFontFactor;
  Pad := Max(LabelPad, Round(FontPx) div 4);
  Thick := Max(1.5, Short / 600);
  Tick := Max(TickHalf, Round(FontPx) div 2);
  Colour := MarkColour(BGRAWhite);
  Measure := TBGRABitmap.Create(1, 1);
  try
    SetMarkFont(Measure, BaseFontPx);
    for I := 0 to High(FLines) do
    begin
      if Hypot(FLines[I].X1 - FLines[I].X0, FLines[I].Y1 - FLines[I].Y0) < 1 then
        Continue;
      BurnInPoint(AMap, FLines[I].X0, FLines[I].Y0, CX0, CY0);
      BurnInPoint(AMap, FLines[I].X1, FLines[I].Y1, CX1, CY1);
      Text := LengthText(FLines[I]);
      TextSz := Measure.TextSize(Text);
      BoxW := TextSz.cx + 2 * Pad;
      BoxH := TextSz.cy + 2 * Pad;
      PlaceLabel(CX0, CY0, CX1, CY1, BoxW, BoxH, FontPx * 0.6, NX, NY, MX, MY, Len);
      BoxX := EnsureRange(Round(MX - BoxW / 2), 0, Max(0, AMap.Width - BoxW));
      BoxY := EnsureRange(Round(MY - BoxH / 2), 0, Max(0, AMap.Height - BoxH));
      Result := Result + '<g>' + LineEnding
        + Lines(SvgColour(Colour), Thick)
        + SvgLabel(Text, BoxX, BoxY, BoxW, BoxH, Pad, TextSz.cy, FontPx, Colour, FSolid,
          Max(1, FontPx / 14))
        + '</g>' + LineEnding;
    end;
  finally
    Measure.Free;
  end;
end;

function TMeasureLine.Version: Cardinal;
begin
  Result := FVersion;
end;

{ The menu entries. }

procedure ToggleMeasure(AViewer: TObject);
begin
  if Measure = nil then
    Exit;
  if (Measure.State <> msOff) and not Measure.Reference then
    Measure.Leave
  else
    Measure.Start(False);
end;

function MeasureEnabled(AViewer: TObject): Boolean;
begin
  Result := (Measure <> nil) and Measure.HasScale;
end;

function MeasureChecked(AViewer: TObject): Boolean;
begin
  Result := (Measure <> nil) and (Measure.State <> msOff) and not Measure.Reference;
end;

procedure StartReferenceMeasurement;
begin
  if Measure <> nil then
    Measure.Start(True);
end;

procedure ToggleReference(AViewer: TObject);
begin
  if Measure = nil then
    Exit;
  if (Measure.State <> msOff) and Measure.Reference then
    Measure.Leave
  else
    Measure.Start(True);
end;

function ReferenceEnabled(AViewer: TObject): Boolean;
begin
  Result := (Measure <> nil) and Measure.HasImage;
end;

function MeasurementActive: Boolean;
begin
  Result := (Measure <> nil) and (Measure.State <> msOff);
end;

procedure LeaveMeasurement;
begin
  if (Measure <> nil) and (Measure.State <> msOff) then
    Measure.Leave;
end;

function ReferenceChecked(AViewer: TObject): Boolean;
begin
  Result := (Measure <> nil) and (Measure.State <> msOff) and Measure.Reference;
end;

initialization
  Measure := TMeasureLine.Create;
  RegisterOverlayLayer(Measure);
  RegisterMenuEntry('Measurement', @ToggleMeasure, @MeasureEnabled, @MeasureChecked);
  RegisterMenuEntry('Reference measurement (calibrate)', @ToggleReference, @ReferenceEnabled,
    @ReferenceChecked);
end.
