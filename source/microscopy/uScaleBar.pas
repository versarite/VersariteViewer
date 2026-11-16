unit uScaleBar;

{
  Unit: uScaleBar

  Purpose
  -------
  The scale bar (M3c, 1.1; spec "Microscopy edition" §7.3, wanted
  features "Draw scale bar"): a right-click entry "Draw scale bar", on
  images with a scale (uImageScale).
  - Click - follow - click - click (user: no dragging): the first left
    click places one end; the bar runs strictly horizontal (on screen)
    to the mouse, its length snapped to a round value (1, 2, 5, 10, 20,
    50 ... µm); the second click fixes the length; the wheel makes it
    thicker / thinner (any time while drawing); the third click
    finishes it.
  - Its length above it, plain text in the marks' colour (Day 29, user:
    the marks are single lines and simple text - no dark rim, no outline,
    no box - and no longer take the info line's colour or OverlaySolid).
  - Its look (1.1, user): [ScaleBar] Color (a name, #RRGGBB or R,G,B),
    Font, FontSize (pt; 0 = 10), Bold in the edition's ini - also used
    by the measuring line and the text labels; set on the left panel
    (uMarkStylePanel). Empty: white, the standard font. SvgReferenceBar
    (default 1): the SVG figure's reference strip (uSvgExport).
  - Again: a new bar replaces the old one. A right click leaves the mode
    (a bar not yet fixed goes, a finished one stays). The bar stays until
    the next image.
  - Starting it ends the measuring line's mode (and the other way round,
    uMeasureLine): one tool at a time.
  - "Apply filters to a copy" draws a finished bar into the copy (M3d):
    horizontal in the copy, its length exact in the copy's pixels;
    '50um-bar' goes into the copy's name.
  - Day 28 (user): resting the mouse shows the aiming loupe (TMView's,
    uExtensions' ShowAimLoupe) while the first end is placed and while
    the length follows (centred on the bar's snapped end); a finished
    bar can be undone
    (uMarkUndo): Undo brings back the bar before it (or none).

  Owns
  ----
  - The bar: one end in pixels of the original image (zoom, pan and
    turning keep it in place), the direction (right / left of that end),
    the length in µm, the thickness in image pixels (it zooms with the
    image).

  Does NOT
  --------
  - Hear Esc (the right click leaves, as for the measuring line).
  - Keep the bar across images.
  - Text labels of the user's own (Strategy decision 6).

  Threads
  -------
  UI thread (paint, mouse, menu).

  Uses (MView units)
  ------------------
  implementation: uSafeFile, uEdition, uCommands, uRenderer,
                  uExtensions, uImageScale, uMeasureLine
  Libraries:      Types, Classes, SysUtils, Math, Forms, Graphics,
                  IniFiles, BGRABitmap, BGRABitmapTypes

  Used by
  -------
  VersariteImageLab.lpr (its uses list), uMeasureLine
}

{$mode ObjFPC}{$H+}

interface

uses
  BGRABitmap,
  BGRABitmapTypes,
  uExtensions;

{ The measuring line starts: a bar being drawn goes (a finished one
  stays). }
procedure LeaveScaleBar;

{ [ScaleBar] Color / Font / FontSize / Bold in the edition's ini (1.1,
  user): the scale bar's and the measuring line's look, on screen and in
  a copy. Read again when a tool starts; missing keys are written (empty
  = as before: the info line's colour, the standard font, 10 pt). }
procedure ReloadMarkStyle;
{ The colour set, else ADefault (the callers pass white: Day 29, the
  marks no longer follow the info line). }
function MarkColour(const ADefault: TBGRAPixel): TBGRAPixel;
{ [ScaleBar] Color as written ('' = the standard, white), and set from
  the left panel (Day 29): written to the ini, every mark drawn again. }
function MarkColourText: string;
procedure SetMarkColour(const AText: string);
{ The font set (name, bold) at APixelHeight; the size set scales it:
  APixelHeight is for 10 pt (MarkFontFactor). }
procedure SetMarkFont(ABitmap: TBGRABitmap; APixelHeight: Integer);
{ FontSize / 10 (1 when not set). }
function MarkFontFactor: Double;
{ The marks' font as set (Day 28, the left panel's Font / Size rows):
  its name ('' = the standard), size in points (0 = the standard, 10),
  bold; SetMarkStyle writes [ScaleBar] Font / FontSize / Bold and draws
  every mark again; MarkStyleVersion changes with it (the layers' picture
  keys). }
function MarkFontName: string;
function MarkFontPt: Integer;
function MarkFontBold: Boolean;
procedure SetMarkStyle(const AFont: string; APt: Integer; ABold: Boolean);
function MarkStyleVersion: Cardinal;
{ The scale bar is being drawn (Day 28: the left panel's style rows). }
function ScaleBarActive: Boolean;
{ [ScaleBar] SvgReferenceBar (default 1): the SVG figure gets a strip
  below the image with the bar burned in (1.1, user). }
function SvgReferenceBar: Boolean;
{ The length of the scale bar drawn on AImageName, 0 = none. }
function ScaleBarMicrons(const AImageName: string): Double;
{ 'Yellow', '#FFD700', 'FFD700', '255,215,0' -> a colour; False if not one. }
function ParseMarkColour(const AText: string; out AColour: TBGRAPixel): Boolean;

{ SVG pieces (1.1, the figure export): '#FFD700'; a number with a point;
  text escaped for XML; the text attributes of the [ScaleBar] font at
  AFontPx (font-family, -size, -weight). }
function SvgColour(const AColour: TBGRAPixel): string;
function SvgNum(AValue: Double): string;
function SvgEscape(const AText: string): string;
function SvgFontAttrs(AFontPx: Double): string;
{ A label as SVG: plain text (Day 29; ASolid and AOutline are no longer
  used). ABoxX / ABoxY: the box's top left, ABoxW x ABoxH, APad inside;
  ATextH: the text's height. }
function SvgLabel(const AText: string; ABoxX, ABoxY, ABoxW, ABoxH, APad, ATextH, AFontPx: Double;
  const AColour: TBGRAPixel; ASolid: Boolean; AOutline: Double): string;

{ The SVG figure's reference strip (1.1, user): the finished bar of
  AImageName in the copy's pixels (AMap): its left end AX0, its length
  ALengthPx, AMicrons. False if there is none. }
function ScaleBarReference(const AImageName: string; const AMap: TBurnInMap;
  out AX0, ALengthPx, AMicrons: Double): Boolean;

{ '50 µm', '0.5 µm' (always µm). }
function ScaleBarText(AMicrons: Double): string;
{ The round length (1, 2, 5 x 10^n µm) nearest to AMicrons; 0 for 0. }
function RoundScaleLength(AMicrons: Double): Double;

implementation

uses
  Types,
  Classes,
  SysUtils,
  Math,
  Forms,
  Graphics,
  IniFiles,
  uSafeFile,
  uEdition,
  uCommands,
  uRenderer,
  uImageScale,
  uMeasureLine,
  uTextLabel,
  uMarkUndo,
  uMarkMemory;

const
  LabelFontPt = 10;
  LabelPad = 4;
  LabelGap = 4;            { between the bar and its label, screen px }
  Margin = 6;              { around the picture, screen px }
  DefaultThickPx = 5;      { the first bar's thickness on screen }
  MinThickPx = 1.5;
  MaxThickPx = 120;
  WheelStep = 1.25;        { the wheel: thickness x / ÷ this }
  MinMicrons = 0.01;

type
  TScaleState = (ssOff, ssWaiting, ssLength, ssThickness, ssDone);

  TScaleBar = class(TOverlayLayer)
  private
    FState: TScaleState;
    FAnchorX, FAnchorY: Double; { the first end, image pixels }
    FDir: Integer;              { +1: the bar runs right of it; -1: left }
    FMicrons: Double;           { its length }
    FThick: Double;             { image pixels; 0 = not set yet }
    FBarImage: string;          { the image the bar belongs to }
    { The last paint: which image, its size, its scale (the menu asks). }
    FImageName: string;
    FImageW, FImageH: Integer;
    FPicture: TBGRABitmap;
    FPictureKey: string;
    FPictureLeft, FPictureTop: Integer;
    FVersion: Cardinal;
    { The bar before the one being drawn (Day 28, Undo): handed in when
      the new one is finished, or when it replaced a bar and is dropped. }
    FPending: TMarkSnapshot;
    procedure Changed;
    function MakeSnapshot: TMarkSnapshot;
    procedure PushPending;
    procedure Aim(ARenderer: TRenderer; AX, AY: Integer);
    function UmPerPixel(const AName: string; out AUm: Double): Boolean;
    function ScreenPerImagePx(ARenderer: TRenderer): Double;
    procedure FollowMouse(ARenderer: TRenderer; AX: Integer);
  public
    destructor Destroy; override;
    procedure Start;
    procedure Leave;
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
    property State: TScaleState read FState;
    property Microns: Double read FMicrons;
  end;

var
  Bar: TScaleBar = nil;   { owned by uExtensions' registry }

type
  { The bar as it was (Day 28, Undo); Microns 0 = none. }
  TBarSnapshot = class(TMarkSnapshot)
  public
    AnchorX, AnchorY: Double;
    Dir: Integer;
    Microns, Thick: Double;
    BarImage: string;
    procedure Restore; override;
  end;

procedure TBarSnapshot.Restore;
begin
  if Bar = nil then
    Exit;
  FreeAndNil(Bar.FPending);
  Bar.FAnchorX := AnchorX;
  Bar.FAnchorY := AnchorY;
  Bar.FDir := Dir;
  Bar.FMicrons := Microns;
  Bar.FThick := Thick;
  Bar.FBarImage := BarImage;
  if (Microns > 0) and (BarImage <> '') then
    Bar.FState := ssDone
  else
    Bar.FState := ssOff;
  HideAimLoupe;
  Bar.Changed;
end;

function RoundScaleLength(AMicrons: Double): Double;
const
  Steps: array[0..2] of Double = (1, 2, 5);
var
  Decade, Best, Candidate: Double;
  E, K, I: Integer;
begin
  Result := 0;
  if AMicrons <= 0 then
    Exit;
  E := Floor(Log10(AMicrons));
  Best := 0;
  { This decade and the next: 1, 2, 5, 10, 20, 50 x 10^E; the nearest
    on a log scale (a bar looks "half as long", not "5 µm shorter"). }
  for K := E to E + 1 do
  begin
    Decade := Power(10, K);
    for I := 0 to High(Steps) do
    begin
      Candidate := Steps[I] * Decade;
      if (Best = 0) or (Abs(Ln(Candidate / AMicrons)) < Abs(Ln(Best / AMicrons))) then
        Best := Candidate;
    end;
  end;
  Result := Max(MinMicrons, Best);
end;

function ScaleBarText(AMicrons: Double): string;
begin
  Result := FormatFloat('0.###', AMicrons) + ' µm';
end;

{ ---- The look ([ScaleBar], 1.1) ---- }

const
  StyleSection = 'ScaleBar';
  DefaultFontPt = 10;

var
  StyleLoaded: Boolean = False;
  StyleHasColour: Boolean = False;
  StyleColour: TBGRAPixel;
  StyleColourText: string = '';
  StyleFont: string = '';
  StyleFontPt: Integer = 0;
  StyleBold: Boolean = False;
  StyleSvgBar: Boolean = True;

function ParseMarkColour(const AText: string; out AColour: TBGRAPixel): Boolean;
const
  Names: array[0..10] of string = ('White', 'Black', 'Yellow', 'Red', 'Green', 'Blue',
    'Cyan', 'Magenta', 'Orange', 'Grey', 'Gray');
  Values: array[0..10] of LongWord = ($FFFFFF, $000000, $FFFF00, $FF0000, $00C000, $3060FF,
    $00FFFF, $FF00FF, $FFA000, $A0A0A0, $A0A0A0);
var
  T: string;
  I, R, G, B: Integer;
  Parts: TStringList;
  V: LongWord;
begin
  Result := False;
  AColour := BGRAWhite;
  T := Trim(AText);
  if T = '' then
    Exit;
  for I := 0 to High(Names) do
    if SameText(T, Names[I]) then
    begin
      V := Values[I];
      AColour := BGRA((V shr 16) and $FF, (V shr 8) and $FF, V and $FF, 255);
      Exit(True);
    end;
  { 255,215,0 }
  if Pos(',', T) > 0 then
  begin
    Parts := TStringList.Create;
    try
      Parts.StrictDelimiter := True;
      Parts.CommaText := T;
      if (Parts.Count = 3) and TryStrToInt(Trim(Parts[0]), R) and TryStrToInt(Trim(Parts[1]), G)
        and TryStrToInt(Trim(Parts[2]), B) then
      begin
        AColour := BGRA(EnsureRange(R, 0, 255), EnsureRange(G, 0, 255), EnsureRange(B, 0, 255), 255);
        Result := True;
      end;
    finally
      Parts.Free;
    end;
    Exit;
  end;
  { #FFD700 / FFD700 }
  if T[1] = '#' then
    Delete(T, 1, 1);
  if (Length(T) = 6) and TryStrToInt('$' + T, I) then
  begin
    AColour := BGRA((I shr 16) and $FF, (I shr 8) and $FF, I and $FF, 255);
    Result := True;
  end;
end;

procedure ReloadMarkStyle;
var
  Ini: TMemIniFile;
  Lines: TStringList;
  Text: string;
  Missing: Boolean;
begin
  StyleLoaded := True;
  StyleHasColour := False;
  StyleColourText := '';
  StyleFont := '';
  StyleFontPt := 0;
  StyleBold := False;
  StyleSvgBar := True;
  try
    Ini := TMemIniFile.Create('');
    Lines := TStringList.Create;
    try
      if FileExists(EditionIniFileName) and ReadTextFile(EditionIniFileName, Text) then
      begin
        Lines.Text := IniTextWithoutEndLine(Text);
        Ini.SetStrings(Lines);
      end;
      StyleColourText := Trim(Ini.ReadString(StyleSection, 'Color', ''));
      StyleHasColour := ParseMarkColour(StyleColourText, StyleColour);
      StyleFont := Trim(Ini.ReadString(StyleSection, 'Font', ''));
      StyleFontPt := EnsureRange(Ini.ReadInteger(StyleSection, 'FontSize', 0), 0, 72);
      StyleBold := Ini.ReadBool(StyleSection, 'Bold', False);
      StyleSvgBar := Ini.ReadBool(StyleSection, 'SvgReferenceBar', True);
      { The keys shown in the settings, empty (= as before), once. }
      Missing := not (Ini.ValueExists(StyleSection, 'Color') and Ini.ValueExists(StyleSection, 'Font')
        and Ini.ValueExists(StyleSection, 'FontSize') and Ini.ValueExists(StyleSection, 'Bold')
        and Ini.ValueExists(StyleSection, 'SvgReferenceBar'));
      if Missing and FileExists(EditionIniFileName) then
      begin
        if not Ini.ValueExists(StyleSection, 'Color') then
          Ini.WriteString(StyleSection, 'Color', '');
        if not Ini.ValueExists(StyleSection, 'Font') then
          Ini.WriteString(StyleSection, 'Font', '');
        if not Ini.ValueExists(StyleSection, 'FontSize') then
          Ini.WriteInteger(StyleSection, 'FontSize', 0);
        if not Ini.ValueExists(StyleSection, 'Bold') then
          Ini.WriteBool(StyleSection, 'Bold', False);
        if not Ini.ValueExists(StyleSection, 'SvgReferenceBar') then
          Ini.WriteBool(StyleSection, 'SvgReferenceBar', True);
        Lines.Clear;
        Ini.GetStrings(Lines);
        WriteTextFileSafe(EditionIniFileName, IniTextWithEndLine(Lines.Text));
      end;
    finally
      Lines.Free;
      Ini.Free;
    end;
  except
    { Unreadable / read-only: as before. }
  end;
end;

procedure EnsureStyle;
begin
  if not StyleLoaded then
    ReloadMarkStyle;
end;

function MarkColour(const ADefault: TBGRAPixel): TBGRAPixel;
begin
  EnsureStyle;
  if StyleHasColour then
    Result := StyleColour
  else
    Result := ADefault;
end;

var
  StyleVersion: Cardinal = 0;

function MarkFontName: string;
begin
  EnsureStyle;
  Result := StyleFont;
end;

function MarkFontPt: Integer;
begin
  EnsureStyle;
  Result := StyleFontPt;
end;

function MarkFontBold: Boolean;
begin
  EnsureStyle;
  Result := StyleBold;
end;

function MarkStyleVersion: Cardinal;
begin
  Result := StyleVersion;
end;

procedure SetMarkStyle(const AFont: string; APt: Integer; ABold: Boolean);
var
  Ini: TMemIniFile;
  Lines: TStringList;
  Text: string;
begin
  EnsureStyle;
  { At once, also when the ini can't be written (this session then). }
  StyleFont := Trim(AFont);
  StyleFontPt := EnsureRange(APt, 0, 72);
  StyleBold := ABold;
  try
    Ini := TMemIniFile.Create('');
    Lines := TStringList.Create;
    try
      if FileExists(EditionIniFileName) and ReadTextFile(EditionIniFileName, Text) then
      begin
        Lines.Text := IniTextWithoutEndLine(Text);
        Ini.SetStrings(Lines);
      end;
      Ini.WriteString(StyleSection, 'Font', StyleFont);
      Ini.WriteInteger(StyleSection, 'FontSize', StyleFontPt);
      Ini.WriteBool(StyleSection, 'Bold', StyleBold);
      Lines.Clear;
      Ini.GetStrings(Lines);
      WriteTextFileSafe(EditionIniFileName, IniTextWithEndLine(Lines.Text));
    finally
      Lines.Free;
      Ini.Free;
    end;
  except
    { Read-only: the new look holds for this session. }
  end;
  Inc(StyleVersion);
  OverlayChanged(nil);
end;

function MarkColourText: string;
begin
  EnsureStyle;
  Result := StyleColourText;
end;

procedure SetMarkColour(const AText: string);
var
  Ini: TMemIniFile;
  Lines: TStringList;
  Text: string;
begin
  EnsureStyle;
  StyleColourText := Trim(AText);
  StyleHasColour := ParseMarkColour(StyleColourText, StyleColour);
  try
    Ini := TMemIniFile.Create('');
    Lines := TStringList.Create;
    try
      if FileExists(EditionIniFileName) and ReadTextFile(EditionIniFileName, Text) then
      begin
        Lines.Text := IniTextWithoutEndLine(Text);
        Ini.SetStrings(Lines);
      end;
      Ini.WriteString(StyleSection, 'Color', StyleColourText);
      Lines.Clear;
      Ini.GetStrings(Lines);
      WriteTextFileSafe(EditionIniFileName, IniTextWithEndLine(Lines.Text));
    finally
      Lines.Free;
      Ini.Free;
    end;
  except
    { Read-only: the colour holds for this session. }
  end;
  Inc(StyleVersion);
  OverlayChanged(nil);
end;

function ScaleBarActive: Boolean;
begin
  Result := (Bar <> nil) and (Bar.State in [ssWaiting, ssLength, ssThickness]);
end;

function MarkFontFactor: Double;
begin
  EnsureStyle;
  if StyleFontPt > 0 then
    Result := StyleFontPt / DefaultFontPt
  else
    Result := 1;
end;

function SvgReferenceBar: Boolean;
begin
  EnsureStyle;
  Result := StyleSvgBar;
end;

procedure SetMarkFont(ABitmap: TBGRABitmap; APixelHeight: Integer);
begin
  EnsureStyle;
  if StyleFont <> '' then
    ABitmap.FontName := StyleFont;
  if StyleBold then
    ABitmap.FontStyle := [fsBold]
  else
    ABitmap.FontStyle := [];
  ABitmap.FontHeight := Max(6, Round(APixelHeight * MarkFontFactor));
end;

{ ---- SVG pieces (1.1) ---- }

var
  SvgDot: TFormatSettings;

function SvgColour(const AColour: TBGRAPixel): string;
begin
  Result := Format('#%.2X%.2X%.2X', [AColour.red, AColour.green, AColour.blue]);
end;

function SvgNum(AValue: Double): string;
begin
  Result := FormatFloat('0.###', AValue, SvgDot);
end;

function SvgEscape(const AText: string): string;
begin
  Result := StringReplace(AText, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

function SvgFontAttrs(AFontPx: Double): string;
var
  Family: string;
begin
  EnsureStyle;
  if StyleFont <> '' then
    Family := SvgEscape(StyleFont) + ', Arial, Helvetica, sans-serif'
  else
    Family := 'Arial, Helvetica, sans-serif';
  Result := 'font-family="' + Family + '" font-size="' + SvgNum(AFontPx) + '"';
  if StyleBold then
    Result := Result + ' font-weight="bold"';
end;

function SvgLabel(const AText: string; ABoxX, ABoxY, ABoxW, ABoxH, APad, ATextH, AFontPx: Double;
  const AColour: TBGRAPixel; ASolid: Boolean; AOutline: Double): string;
var
  BaseY: Double;
  Place: string;
begin
  Result := '';
  { The baseline about four fifths down the text line. }
  BaseY := ABoxY + APad + ATextH * 0.8;
  Place := '<text x="' + SvgNum(ABoxX + ABoxW / 2) + '" y="' + SvgNum(BaseY)
    + '" text-anchor="middle" ' + SvgFontAttrs(AFontPx);
  { Plain text (Day 29, user): no outline, no box. }
  Result := Result + Place + ' fill="' + SvgColour(AColour) + '">' + SvgEscape(AText)
    + '</text>' + LineEnding;
end;

type
  { A finished bar kept for its image while another is shown (Day 29,
    uMarkMemory). }
  TBarMemo = class
  public
    AnchorX, AnchorY: Double;
    Dir: Integer;
    Microns, Thick: Double;
  end;

const
  MemoryTool = 'scalebar';

{ TScaleBar }

destructor TScaleBar.Destroy;
begin
  FPending.Free;
  FPicture.Free;
  inherited Destroy;
end;

function TScaleBar.MakeSnapshot: TMarkSnapshot;
var
  S: TBarSnapshot;
begin
  S := TBarSnapshot.Create;
  { Only a bar of this image counts as one (called at a new bar's first
    click: the old bar's fields are still those of the finished bar). }
  if (FBarImage <> '') and (FBarImage = FImageName) and (FMicrons > 0) then
  begin
    S.AnchorX := FAnchorX;
    S.AnchorY := FAnchorY;
    S.Dir := FDir;
    S.Microns := FMicrons;
    S.Thick := FThick;
    S.BarImage := FBarImage;
  end;
  Result := S;
end;

{ The bar before (FPending) to Undo: a new bar is finished, or one being
  drawn went and had replaced a bar. }
procedure TScaleBar.PushPending;
begin
  if FPending = nil then
    Exit;
  PushMarkUndo(FPending, FImageName, 'Undo scale bar');
  FPending := nil;
end;

{ The aiming loupe (Day 28): at the mouse for the first end; at the
  bar's end (its length snapped) while the length follows. }
procedure TScaleBar.Aim(ARenderer: TRenderer; AX, AY: Integer);
var
  SX, SY, PerPx, Um: Double;
begin
  if (FState = ssLength) and UmPerPixel(FBarImage, Um) then
  begin
    PerPx := ScreenPerImagePx(ARenderer);
    ARenderer.ImageToScreen(FAnchorX, FAnchorY, SX, SY);
    if (PerPx > 0) and (Um > 0) then
    begin
      ShowAimLoupe(SX + FDir * FMicrons / Um * PerPx, SY, SX, SY - 1);
      Exit;
    end;
  end;
  ShowAimLoupe(AX + 0.5, AY + 0.5, AX - 0.5, AY - 0.5);
end;

procedure TScaleBar.Changed;
begin
  FPictureKey := '';
  OverlayChanged(Self);
end;

function TScaleBar.UmPerPixel(const AName: string; out AUm: Double): Boolean;
var
  Scale: TImageScale;
begin
  AUm := 0;
  Result := (AName <> '') and (FImageW > 0) and (FImageH > 0)
    and ScaleFor(AName, FImageW, FImageH, Scale);
  if Result then
  begin
    { Square pixels in practice; else the mean (the bar is horizontal on
      screen, whatever the turn). }
    if Scale.UmPerPixelY > 0 then
      AUm := (Scale.UmPerPixelX + Scale.UmPerPixelY) / 2
    else
      AUm := Scale.UmPerPixelX;
    Result := AUm > 0;
  end;
end;

function TScaleBar.HasScale: Boolean;
var
  Um: Double;
begin
  Result := UmPerPixel(FImageName, Um);
end;

{ Screen pixels per image pixel now (zoom; a turn doesn't change it). }
function TScaleBar.ScreenPerImagePx(ARenderer: TRenderer): Double;
var
  X0, Y0, X1, Y1: Double;
begin
  ARenderer.ImageToScreen(0, 0, X0, Y0);
  ARenderer.ImageToScreen(1, 0, X1, Y1);
  Result := Hypot(X1 - X0, Y1 - Y0);
end;

procedure TScaleBar.Start;
begin
  LeaveMeasurement;            { one tool at a time }
  LeaveTextLabels;
  ReloadMarkStyle;             { [ScaleBar] edited meanwhile }
  FState := ssWaiting;
  Changed;
end;

procedure TScaleBar.Leave;
begin
  case FState of
    { A bar whose length isn't fixed yet goes (Undo brings back the one
      it replaced). }
    ssLength:
      begin
        FMicrons := 0;
        FBarImage := '';
        FState := ssOff;
        if (FPending <> nil) and (TBarSnapshot(FPending).Microns > 0) then
          PushPending;
      end;
    { Its length is fixed: it stays as it is (until the next image). }
    ssThickness:
      begin
        FState := ssDone;
        PushPending;
      end;
    { Not started: an earlier bar stays. }
    ssWaiting:
      FState := ssOff;
  end;
  FreeAndNil(FPending);
  HideAimLoupe;
  Changed;
end;

{ The bar from the anchor to the mouse's x (on screen), its length
  rounded. }
procedure TScaleBar.FollowMouse(ARenderer: TRenderer; AX: Integer);
var
  SX, SY, PerPx, Um, Raw, Snapped: Double;
  Dir: Integer;
begin
  if not UmPerPixel(FBarImage, Um) then
    Exit;
  PerPx := ScreenPerImagePx(ARenderer);
  if PerPx <= 0 then
    Exit;
  ARenderer.ImageToScreen(FAnchorX, FAnchorY, SX, SY);
  if AX >= SX then
    Dir := 1
  else
    Dir := -1;
  Raw := Abs(AX - SX) / PerPx * Um;
  Snapped := RoundScaleLength(Raw);
  if (Snapped <> FMicrons) or (Dir <> FDir) then
  begin
    FMicrons := Snapped;
    FDir := Dir;
    Changed;
  end;
end;

function TScaleBar.HandleMouse(AView: TObject; AKind: TOverlayMouseKind;
  AButton: TOverlayButton; AX, AY, AWheel: Integer): Boolean;
var
  Renderer: TRenderer;
  PerPx, ScreenThick: Double;
begin
  Result := False;
  { A release reaches a layer only when it took the press: keep it. }
  if AKind = omUp then
    Exit(True);
  if (FState in [ssOff, ssDone]) or not (AView is TRenderer) then
    Exit;
  Renderer := TRenderer(AView);
  case AKind of
    omMove:
      begin
        if FState = ssLength then
          FollowMouse(Renderer, AX);
        { Placing an end: the loupe (Day 28). }
        if (FState in [ssWaiting, ssLength]) and (FImageName <> '') then
          Aim(Renderer, AX, AY)
        else
          HideAimLoupe;
      end;

    omWheel:
      if (FState in [ssLength, ssThickness]) and (AWheel <> 0) then
      begin
        Result := True;
        PerPx := ScreenPerImagePx(Renderer);
        if PerPx <= 0 then
          Exit;
        ScreenThick := FThick * PerPx;
        if AWheel > 0 then
          ScreenThick := ScreenThick * WheelStep
        else
          ScreenThick := ScreenThick / WheelStep;
        ScreenThick := EnsureRange(ScreenThick, MinThickPx, MaxThickPx);
        FThick := ScreenThick / PerPx;
        Changed;
      end;

    omDown:
      case AButton of
        obLeft:
          begin
            Result := True;
            if (Renderer.Image = nil) or (FImageName = '') then
              Exit;
            case FState of
              ssWaiting:
                begin
                  { The first click: one end; a new bar replaces the old
                    (kept for Undo, Day 28). }
                  FreeAndNil(FPending);
                  FPending := MakeSnapshot;
                  if not Renderer.ScreenToImage(AX + 0.5, AY + 0.5, FAnchorX, FAnchorY) then
                  begin
                    FreeAndNil(FPending);
                    Exit;
                  end;
                  FBarImage := FImageName;
                  FDir := 1;
                  FMicrons := 0;
                  PerPx := ScreenPerImagePx(Renderer);
                  if PerPx > 0 then
                    FThick := DefaultThickPx / PerPx
                  else
                    FThick := DefaultThickPx;
                  FState := ssLength;
                  FollowMouse(Renderer, AX);
                  Changed;
                end;
              ssLength:
                { The second: the length is fixed (not a bare click). }
                if FMicrons > 0 then
                begin
                  FState := ssThickness;
                  HideAimLoupe;          { the thickness: the wheel, no aiming }
                  Changed;
                end;
              ssThickness:
                begin
                  { The third: finished (Undo: the bar before). }
                  FState := ssDone;
                  PushPending;
                  Changed;
                end;
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

{ The bar and its label at the given place; all in ABitmap's pixels.
  AX0: the bar's left end, AY: its middle line. ABitmap.FontHeight is
  set. Day 29 (user): the bar alone and the text alone, in AColour - no
  dark rim, no outline, no box. }
procedure DrawBar(ABitmap: TBGRABitmap; AX0, AY, ALength, AThick: Double; const AText: string;
  AColour: TBGRAPixel; APad, AGap: Integer; ADraft: Boolean);
var
  TextSz: TSize;
  TX, TY, BoxW, BoxH: Integer;
begin
  if ADraft then
    { Still being drawn: a little see-through. }
    ABitmap.FillRectAntialias(AX0, AY - AThick / 2, AX0 + ALength, AY + AThick / 2,
      BGRA(AColour.red, AColour.green, AColour.blue, 200))
  else
    ABitmap.FillRectAntialias(AX0, AY - AThick / 2, AX0 + ALength, AY + AThick / 2, AColour);
  if AText = '' then
    Exit;
  TextSz := ABitmap.TextSize(AText);
  BoxW := TextSz.cx + 2 * APad;
  BoxH := TextSz.cy + 2 * APad;
  TX := Round(AX0 + ALength / 2 - BoxW / 2);
  TY := Round(AY - AThick / 2 - AGap - BoxH);
  ABitmap.TextOut(TX + APad, TY + APad, AText, AColour);
end;

function TScaleBar.Picture(AView: TObject; AWidth, AHeight: Integer;
  out ALeft, ATop: Integer): TBGRABitmap;
var
  Renderer: TRenderer;
  Name, Key, Text: string;
  SX, SY, PerPx, Um, LenPx, ThickPx, X0: Double;
  FontPx, L, T, R, B, W, H: Integer;
  TextSz: TSize;
  Colour: TBGRAPixel;
  Solid: Boolean;
  Memo: TBarMemo;
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
  { Remember the image (the menu asks); a new image: the bar goes. }
  Name := Renderer.Image.Key.FileName;
  FImageName := Name;
  FImageW := Renderer.Image.FullWidth;
  FImageH := Renderer.Image.FullHeight;
  if (FImageW <= 0) or (FImageH <= 0) then
  begin
    FImageW := Renderer.Image.Width;
    FImageH := Renderer.Image.Height;
  end;
  if (FBarImage <> '') and (Name <> FBarImage) then
  begin
    { A bar with its length fixed is kept for its image (Day 29, user:
      the marks come back with the image). }
    if (FMicrons > 0) and (FState <> ssLength) then
    begin
      Memo := TBarMemo.Create;
      Memo.AnchorX := FAnchorX;
      Memo.AnchorY := FAnchorY;
      Memo.Dir := FDir;
      Memo.Microns := FMicrons;
      Memo.Thick := FThick;
      RememberMarks(MemoryTool, FBarImage, Memo);
    end;
    FBarImage := '';
    FMicrons := 0;
    { Still drawing: the next image gets a new bar; finished: off. }
    if FState in [ssLength, ssThickness] then
      FState := ssWaiting
    else if FState = ssDone then
      FState := ssOff;
  end;
  { Back on an image that had a bar: it is there again. }
  if FBarImage = '' then
  begin
    Recalled := RecallMarks(MemoryTool, Name);
    if Recalled is TBarMemo then
    begin
      Memo := TBarMemo(Recalled);
      FAnchorX := Memo.AnchorX;
      FAnchorY := Memo.AnchorY;
      FDir := Memo.Dir;
      FMicrons := Memo.Microns;
      FThick := Memo.Thick;
      FBarImage := Name;
      if FState = ssOff then
        FState := ssDone;
    end;
    Recalled.Free;
  end;
  if (FBarImage = '') or (FMicrons <= 0) or not UmPerPixel(FBarImage, Um) then
    Exit;
  PerPx := ScreenPerImagePx(Renderer);
  if PerPx <= 0 then
    Exit;

  Renderer.ImageToScreen(FAnchorX, FAnchorY, SX, SY);
  LenPx := FMicrons / Um * PerPx;
  ThickPx := Max(MinThickPx, FThick * PerPx);
  if FDir > 0 then
    X0 := SX
  else
    X0 := SX - LenPx;
  Text := ScaleBarText(FMicrons);
  Solid := False;
  Colour := MarkColour(BGRAWhite);

  Key := Format('%d %d %.1f %.1f %.2f %.2f %s %s %d %d %s %.2f %s', [AWidth, AHeight, X0, SY, LenPx,
    ThickPx, Text, BoolToStr(Solid, True), Ord(FState), Integer(Colour.red) shl 16
    + Integer(Colour.green) shl 8 + Colour.blue, StyleFont, MarkFontFactor, BoolToStr(StyleBold, True)]);
  if (FPicture <> nil) and (Key = FPictureKey) then
  begin
    ALeft := FPictureLeft;
    ATop := FPictureTop;
    Exit(FPicture);
  end;

  FontPx := Max(8, Round(LabelFontPt * Screen.PixelsPerInch / 72));
  if FPicture = nil then
    FPicture := TBGRABitmap.Create(1, 1);
  FPicture.FontQuality := fqFineAntialiasing;
  SetMarkFont(FPicture, FontPx);
  TextSz := FPicture.TextSize(Text);
  { The picture: the bar and the label above it, inside the view. }
  L := Floor(Min(X0, X0 + LenPx / 2 - TextSz.cx / 2 - LabelPad)) - Margin;
  R := Ceil(Max(X0 + LenPx, X0 + LenPx / 2 + TextSz.cx / 2 + LabelPad)) + Margin;
  T := Floor(SY - ThickPx / 2 - LabelGap - TextSz.cy - 2 * LabelPad) - Margin;
  B := Ceil(SY + ThickPx / 2) + Margin;
  L := Max(L, 0);
  T := Max(T, 0);
  R := Min(R, AWidth);
  B := Min(B, AHeight);
  W := R - L;
  H := B - T;
  if (W <= 0) or (H <= 0) then
    Exit;
  FPicture.SetSize(W, H);
  FPicture.FillTransparent;
  DrawBar(FPicture, X0 - L, SY - T, LenPx, ThickPx, Text, Colour, LabelPad, LabelGap,
    FState = ssLength);

  FPictureKey := Key;
  FPictureLeft := L;
  FPictureTop := T;
  Inc(FVersion);
  ALeft := L;
  ATop := T;
  Result := FPicture;
end;

function TScaleBar.Version: Cardinal;
begin
  Result := FVersion;
end;

{ A fixed bar of this image (the length chosen; finished or getting its
  thickness). }
function TScaleBar.CanBurnIn(const AImageName: string): Boolean;
begin
  Result := (AImageName <> '') and (AImageName = FBarImage) and (FMicrons > 0)
    and (FState <> ssLength);
end;

{ The bar into the copy: horizontal there, its length exact in the
  copy's pixels, the label sized for the copy (about 1/45 of its shorter
  side, as the measuring line's). }
function TScaleBar.BurnIn(ABitmap: TBGRABitmap; const AImageName: string;
  const AMap: TBurnInMap): string;
var
  Um, CX, CY, PerPx, LenPx, ThickPx, X0, K: Double;
  Short, FontPx, Pad, Gap: Integer;
  Text: string;
begin
  Result := '';
  if (ABitmap = nil) or not CanBurnIn(AImageName) or not UmPerPixel(FBarImage, Um) then
    Exit;
  { Copy pixels per image pixel (the copy may be a quick view's, or
    resized; a turn keeps the size). }
  PerPx := (AMap.ScaleX + AMap.ScaleY) / 2;
  if PerPx <= 0 then
    Exit;
  BurnInPoint(AMap, FAnchorX, FAnchorY, CX, CY);
  LenPx := FMicrons / Um * PerPx;
  ThickPx := Max(1, FThick * PerPx);
  if FDir > 0 then
    X0 := CX
  else
    X0 := CX - LenPx;
  { Inside the copy, also when the end was near an edge. }
  X0 := EnsureRange(X0, 0, Max(0, ABitmap.Width - LenPx));
  if AMap.ViewScale > 0 then
  begin
    { The label as on screen (Day 28, user), at the zoom the copy was
      made at; the bar's own thickness is in image pixels already. }
    K := 1 / AMap.ViewScale;
    FontPx := Max(6, Round(LabelFontPt * Screen.PixelsPerInch / 72 * K));
    Pad := Max(1, Round(LabelPad * K));
    Gap := Max(1, Round(LabelGap * K));
  end
  else
  begin
    Short := Max(1, Min(ABitmap.Width, ABitmap.Height));
    FontPx := Max(12, Round(Short / 45));
    Pad := Max(LabelPad, FontPx div 4);
    Gap := Max(LabelGap, FontPx div 4);
  end;
  ABitmap.FontQuality := fqFineAntialiasing;
  SetMarkFont(ABitmap, FontPx);
  Text := ScaleBarText(FMicrons);
  DrawBar(ABitmap, X0, CY, LenPx, ThickPx, Text, MarkColour(BGRAWhite), Pad, Gap, False);
  { For the copy's name: '50um-bar' (no space, no µ, a point). }
  Result := StringReplace(StringReplace(StringReplace(Text, ' ', '', [rfReplaceAll]),
    'µ', 'u', [rfReplaceAll]), ',', '.', [rfReplaceAll]) + '-bar';
end;

function TScaleBar.SvgLayerName: string;
begin
  Result := 'Scale bar';
end;

{ As BurnIn, as vectors: the bar a rectangle (its length exact in the
  copy's pixels), the length a text. }
function TScaleBar.SvgMarkup(const AImageName: string; const AMap: TBurnInMap): string;
var
  Um, CX, CY, PerPx, LenPx, ThickPx, X0, FontPx, Pad, Gap, BoxW, BoxH: Double;
  Short: Integer;
  Text: string;
  Colour: TBGRAPixel;
  Measure: TBGRABitmap;
  TextSz: TSize;
begin
  Result := '';
  if not CanBurnIn(AImageName) or not UmPerPixel(FBarImage, Um) then
    Exit;
  PerPx := (AMap.ScaleX + AMap.ScaleY) / 2;
  if PerPx <= 0 then
    Exit;
  BurnInPoint(AMap, FAnchorX, FAnchorY, CX, CY);
  LenPx := FMicrons / Um * PerPx;
  ThickPx := Max(1, FThick * PerPx);
  if FDir > 0 then
    X0 := CX
  else
    X0 := CX - LenPx;
  X0 := EnsureRange(X0, 0, Max(0, AMap.Width - LenPx));
  Short := Max(1, Min(AMap.Width, AMap.Height));
  FontPx := Max(12, Round(Short / 45)) * MarkFontFactor;
  Pad := Max(LabelPad, Round(FontPx) div 4);
  Gap := Max(LabelGap, Round(FontPx) div 4);
  Text := ScaleBarText(FMicrons);
  Colour := MarkColour(BGRAWhite);
  { The label's size as it would be drawn. }
  Measure := TBGRABitmap.Create(1, 1);
  try
    SetMarkFont(Measure, Max(12, Round(Short / 45)));
    TextSz := Measure.TextSize(Text);
  finally
    Measure.Free;
  end;
  BoxW := TextSz.cx + 2 * Pad;
  BoxH := TextSz.cy + 2 * Pad;
  Result := '<rect x="' + SvgNum(X0) + '" y="' + SvgNum(CY - ThickPx / 2) + '" width="'
    + SvgNum(LenPx) + '" height="' + SvgNum(ThickPx) + '" fill="' + SvgColour(Colour)
    + '"/>' + LineEnding
    + SvgLabel(Text, X0 + LenPx / 2 - BoxW / 2, CY - ThickPx / 2 - Gap - BoxH, BoxW, BoxH, Pad,
      TextSz.cy, FontPx, Colour, False, Max(1, FontPx / 14));
end;

function ScaleBarReference(const AImageName: string; const AMap: TBurnInMap;
  out AX0, ALengthPx, AMicrons: Double): Boolean;
var
  Um, CX, CY, PerPx: Double;
begin
  AX0 := 0;
  ALengthPx := 0;
  AMicrons := 0;
  Result := False;
  if (Bar = nil) or not Bar.CanBurnIn(AImageName) or not Bar.UmPerPixel(Bar.FBarImage, Um) then
    Exit;
  PerPx := (AMap.ScaleX + AMap.ScaleY) / 2;
  if PerPx <= 0 then
    Exit;
  BurnInPoint(AMap, Bar.FAnchorX, Bar.FAnchorY, CX, CY);
  ALengthPx := Bar.FMicrons / Um * PerPx;
  if Bar.FDir > 0 then
    AX0 := CX
  else
    AX0 := CX - ALengthPx;
  AX0 := EnsureRange(AX0, 0, Max(0, AMap.Width - ALengthPx));
  AMicrons := Bar.FMicrons;
  Result := ALengthPx >= 1;
end;

{ The menu entry and the measuring line's call. }

function ScaleBarMicrons(const AImageName: string): Double;
begin
  Result := 0;
  if (Bar <> nil) and Bar.CanBurnIn(AImageName) then
    Result := Bar.Microns;
end;

procedure LeaveScaleBar;
begin
  if (Bar <> nil) and (Bar.State in [ssWaiting, ssLength, ssThickness]) then
    Bar.Leave;
end;

procedure ToggleScaleBar(AViewer: TObject);
begin
  if Bar = nil then
    Exit;
  if Bar.State in [ssWaiting, ssLength, ssThickness] then
    Bar.Leave
  else
    Bar.Start;
end;

function ScaleBarEnabled(AViewer: TObject): Boolean;
begin
  Result := (Bar <> nil) and Bar.HasScale;
end;

function ScaleBarChecked(AViewer: TObject): Boolean;
begin
  Result := (Bar <> nil) and (Bar.State in [ssWaiting, ssLength, ssThickness]);
end;

initialization
  SvgDot := DefaultFormatSettings;
  SvgDot.DecimalSeparator := '.';
  SvgDot.ThousandSeparator := #0;
  Bar := TScaleBar.Create;
  RegisterOverlayLayer(Bar);
  RegisterMenuEntry('Draw scale bar', @ToggleScaleBar, @ScaleBarEnabled, @ScaleBarChecked);
  { The look of the marks, shown (empty = as before) and explained on the
    settings screen (1.1, uEdition). }
  RegisterEditionKey(StyleSection, 'Color', '',
    'The colour of the scale bar, the measuring lines and the text labels (on screen, in copies, '
    + 'in the SVG figure): a name (White, Yellow, Orange, Red, Green, Cyan, Blue, Magenta, Black), '
    + '#RRGGBB or R,G,B. Empty = white. Also on the left panel while a mark tool is on.');
  RegisterEditionKey(StyleSection, 'Font', '',
    'The font of the marks'' texts (the bar''s length, the measurements, the labels), e.g. Arial '
    + 'or Segoe UI. Empty = the standard font.');
  RegisterEditionKey(StyleSection, 'FontSize', '0',
    'The size of the marks'' texts in points (on screen; copies and the SVG scale it with the '
    + 'image). 0 = 10 pt.');
  RegisterEditionKey(StyleSection, 'Bold', '0', '1 = the marks'' texts in bold.');
  RegisterEditionKey(StyleSection, 'SvgReferenceBar', '1',
    '1 = "Export figure (SVG)" adds a thin strip below the picture with a white line of the scale '
    + 'bar''s length, in the picture''s own pixels: the scale stays right when the picture alone is '
    + 'resized in the drawing program. Crop it off when the figure is done. 0 = no strip.');
end.
