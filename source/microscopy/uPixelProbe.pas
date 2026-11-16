unit uPixelProbe;

{
  Unit: uPixelProbe

  Purpose
  -------
  The microscopy edition's first unit (M1, Day 25): a small label next
  to the mouse with the image pixel under it ("x 1234   y 567"),
  switched on and off from the right-click menu ("Show pixel
  position"). It is the skeleton's test of every plug-in point the
  measuring line and the scale bar will use (uExtensions): an overlay
  layer drawn by both renderers, the mouse over the view, a repaint
  when it changes, a menu entry with a check mark, and the renderer's
  screen <-> image geometry. Since M3a the label also shows the
  position in µm when the image has a scale (uImageScale: the file, a
  matching .lif, the chosen calibration), and a second line with the
  scale's source when it is not the file itself.

  Owns
  ----
  - Its label picture (a few hundred pixels, not the view).

  Knows
  -----
  - The renderer (AView: TRenderer), only during a paint.

  Responsibilities
  ----------------
  - Registers itself in its initialization section: one overlay layer
    (owned by the registry from then on) and one menu entry.
  - Remembers where the mouse is over the view; never takes the mouse
    (the mouse language and the panels see every event as before).
  - Draws the label only when its text changed (Version: the GPU
    uploads it again only then); moves it with the mouse, below right,
    kept inside the view.

  Does NOT
  --------
  - Show anything when the mouse is outside the image, over no image,
    or while switched off (the default).

  Threads
  -------
  UI thread (paint, mouse, menu).

  Uses (MView units)
  ------------------
  implementation: uCommands, uRenderer, uExtensions, uImageScale
  Libraries:      Types, SysUtils, Math, Forms (the screen's DPI),
                  BGRABitmap, BGRABitmapTypes

  Used by
  -------
  VersariteImageLab.lpr (its uses list only: nothing names this unit)
}

{$mode ObjFPC}{$H+}

interface

implementation

uses
  Types,
  SysUtils,
  Math,
  Forms,
  BGRABitmap,
  BGRABitmapTypes,
  uCommands,
  uRenderer,
  uExtensions,
  uImageScale;

const
  LabelGap = 16;          { from the mouse to the label, screen pixels }
  LabelPadX = 6;
  LabelPadY = 3;
  LabelFontPt = 10;

type
  TPixelProbe = class(TOverlayLayer)
  private
    FShown: Boolean;
    FMouseX, FMouseY: Integer;
    FOverView: Boolean;
    FText: string;              { what FLabel shows }
    FLabel: TBGRABitmap;
    FVersion: Cardinal;
    procedure MakeLabel(const AText: string; const ASource: string = '');
  public
    destructor Destroy; override;
    function Picture(AView: TObject; AWidth, AHeight: Integer;
      out ALeft, ATop: Integer): TBGRABitmap; override;
    function Version: Cardinal; override;
    function HandleMouse(AView: TObject; AKind: TOverlayMouseKind; AButton: TOverlayButton;
      AX, AY, AWheel: Integer): Boolean; override;
    procedure Toggle;
    property Shown: Boolean read FShown;
  end;

var
  Probe: TPixelProbe = nil;   { owned by uExtensions' registry }

destructor TPixelProbe.Destroy;
begin
  FLabel.Free;
  inherited Destroy;
end;

{ One line, or two: the position, then (smaller, grey) the scale's
  source when borrowed. ASource = '' for one line. }
procedure TPixelProbe.MakeLabel(const AText: string; const ASource: string = '');
var
  TextSz, SourceSz: TSize;
  FontPx, SourcePx, W, H: Integer;
begin
  FreeAndNil(FLabel);
  FLabel := TBGRABitmap.Create(1, 1);
  FontPx := Max(8, Round(LabelFontPt * Screen.PixelsPerInch / 72));
  SourcePx := Max(7, FontPx * 4 div 5);
  FLabel.FontQuality := fqFineAntialiasing;
  FLabel.FontHeight := FontPx;
  TextSz := FLabel.TextSize(AText);
  W := TextSz.cx;
  H := TextSz.cy;
  SourceSz.cx := 0;
  SourceSz.cy := 0;
  if ASource <> '' then
  begin
    FLabel.FontHeight := SourcePx;
    SourceSz := FLabel.TextSize(ASource);
    W := Max(W, SourceSz.cx);
    Inc(H, SourceSz.cy);
  end;
  FLabel.SetSize(W + 2 * LabelPadX, H + 2 * LabelPadY);
  FLabel.FillRect(0, 0, FLabel.Width, FLabel.Height, BGRA(0, 0, 0, 170), dmSet);
  FLabel.FontHeight := FontPx;
  FLabel.TextOut(LabelPadX, LabelPadY, AText, BGRAWhite);
  if ASource <> '' then
  begin
    FLabel.FontHeight := SourcePx;
    FLabel.TextOut(LabelPadX, LabelPadY + TextSz.cy, ASource, BGRA(170, 170, 170, 255));
  end;
  FText := AText + #10 + ASource;
  Inc(FVersion);
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

function TPixelProbe.Picture(AView: TObject; AWidth, AHeight: Integer;
  out ALeft, ATop: Integer): TBGRABitmap;
var
  Renderer: TRenderer;
  ImgX, ImgY: Double;
  PixX, PixY: Integer;
  NewText, Source: string;
  FullW, FullH: Integer;
  Scale: TImageScale;
begin
  ALeft := 0;
  ATop := 0;
  Result := nil;
  if not (FShown and FOverView) then
    Exit;
  if not (AView is TRenderer) then
    Exit;
  Renderer := TRenderer(AView);
  if Renderer.Image = nil then
    Exit;
  if not Renderer.ScreenToImage(FMouseX + 0.5, FMouseY + 0.5, ImgX, ImgY) then
    Exit;
  { The original image's size (Bitmap may be a smaller decode); 0 when
    the loader didn't know it: then the bitmap's own. }
  FullW := Renderer.Image.FullWidth;
  FullH := Renderer.Image.FullHeight;
  if (FullW <= 0) or (FullH <= 0) then
  begin
    FullW := Renderer.Image.Width;
    FullH := Renderer.Image.Height;
  end;
  PixX := Floor(ImgX);
  PixY := Floor(ImgY);
  if (PixX < 0) or (PixY < 0) or (PixX >= FullW) or (PixY >= FullH) then
    Exit;

  NewText := Format('x %d   y %d', [PixX, PixY]);
  { With a scale (M3a): the place in µm, from the image's top left
    corner (the pixel's position, like x / y: the label changes only
    when the pixel does). }
  Source := '';
  if ScaleFor(Renderer.Image.Key.FileName, FullW, FullH, Scale) then
  begin
    NewText := NewText + '      ' + MicronText(PixX * Scale.UmPerPixelX)
      + '   ' + MicronText(PixY * Scale.UmPerPixelY);
    if Scale.Source <> '' then
      Source := 'scale: ' + Scale.Source;
  end;
  if (FLabel = nil) or (NewText + #10 + Source <> FText) then
    MakeLabel(NewText, Source);

  { Below right of the mouse; flipped to the other side at the view's
    edges. }
  ALeft := FMouseX + LabelGap;
  if ALeft + FLabel.Width > AWidth then
    ALeft := FMouseX - LabelGap - FLabel.Width;
  ATop := FMouseY + LabelGap;
  if ATop + FLabel.Height > AHeight then
    ATop := FMouseY - LabelGap - FLabel.Height;
  ALeft := Max(0, ALeft);
  ATop := Max(0, ATop);
  Result := FLabel;
end;

function TPixelProbe.Version: Cardinal;
begin
  Result := FVersion;
end;

function TPixelProbe.HandleMouse(AView: TObject; AKind: TOverlayMouseKind;
  AButton: TOverlayButton; AX, AY, AWheel: Integer): Boolean;
begin
  Result := False;   { only watches: everyone else still gets the mouse }
  case AKind of
    omMove:
      begin
        FMouseX := AX;
        FMouseY := AY;
        FOverView := True;
        if FShown then
          OverlayChanged(Self);
      end;
    omLeave:
      begin
        FOverView := False;
        if FShown then
          OverlayChanged(Self);
      end;
  end;
end;

procedure TPixelProbe.Toggle;
begin
  FShown := not FShown;
  OverlayChanged(Self);
end;

{ The menu entry. }

procedure ToggleProbe(AViewer: TObject);
begin
  if Probe <> nil then
    Probe.Toggle;
end;

function ProbeShown(AViewer: TObject): Boolean;
begin
  Result := (Probe <> nil) and Probe.Shown;
end;

initialization
  Probe := TPixelProbe.Create;
  RegisterOverlayLayer(Probe);
  RegisterMenuEntry('Show pixel position', @ToggleProbe, nil, @ProbeShown);
end.
