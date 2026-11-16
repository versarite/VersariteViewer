unit uTextLabel;

{
  Unit: uTextLabel

  Purpose
  -------
  Text labels (1.1, user: "labels that can be removed or edited
  later"): a right-click entry "Text labels". While it is on:
  - a left click on the image asks for a text (a small dialog) and puts
    it there, horizontal on screen;
  - a left click on a label asks again, with its text: changed, or
    emptied = removed;
  - a right click leaves the mode (the labels stay until the next
    image).
  The look is the scale bar's: [ScaleBar] Color / Font / FontSize / Bold
  (uScaleBar): simple text, no outline or box (Day 29, user).
  "Apply filters to a copy" draws them into the copy; the SVG figure has
  them as text in a layer "Labels" (each label editable, movable,
  removable there).
  One tool at a time: starting it ends the measuring line's and the
  scale bar's modes (and the other way round).
  Day 28 (user): adding, changing and removing a label can be undone
  (uMarkUndo; the viewer's Undo).

  Owns
  ----
  - The labels (their place - the text's top left - in pixels of the
    original image, their text) and their picture.

  Threads
  -------
  UI thread (paint, mouse, menu).

  Uses (MView units)
  ------------------
  implementation: uCommands, uRenderer, uExtensions, uScaleBar,
                  uMeasureLine
  Libraries:      Types, SysUtils, Math, Forms, Dialogs, BGRABitmap,
                  BGRABitmapTypes

  Used by
  -------
  VersariteImageLab.lpr (its uses list), uMeasureLine, uScaleBar
}

{$mode ObjFPC}{$H+}

interface

{ Another tool starts: the label mode ends (the labels stay). }
procedure LeaveTextLabels;
{ The label mode is on (Day 28: the left panel's style rows). }
function TextLabelsActive: Boolean;

implementation

uses
  Types,
  SysUtils,
  Math,
  Forms,
  Dialogs,
  BGRABitmap,
  BGRABitmapTypes,
  uCommands,
  uRenderer,
  uExtensions,
  uScaleBar,
  uMeasureLine,
  uMarkUndo,
  uMarkMemory;

const
  LabelFontPt = 10;
  LabelPad = 4;
  Margin = 4;
  MaxLabels = 50;

type
  TTextMark = record
    X, Y: Double;               { the box's top left, image pixels }
    Text: string;
  end;

  TTextLabels = class(TOverlayLayer)
  private
    FOn: Boolean;
    FMarks: array of TTextMark;
    FMarkImage: string;         { the image the labels belong to }
    FImageName: string;         { the last paint's image }
    FImageW, FImageH: Integer;
    { The last paint: each label's box on screen (for a click). }
    FBoxes: array of TRect;
    FPicture: TBGRABitmap;
    FPictureKey: string;
    FPictureLeft, FPictureTop: Integer;
    FVersion: Cardinal;
    procedure Changed;
    { The labels as they are, for Undo (Day 28), before a change. }
    procedure KeepForUndo(const ACaption: string);
    function Ask(const ACaption, AText: string; out AResult: string): Boolean;
    function HitLabel(AX, AY: Integer): Integer;
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
    property IsOn: Boolean read FOn;
    property ImageName: string read FImageName;
  end;

var
  Labels: TTextLabels = nil;   { owned by uExtensions' registry }

type
  { The labels as they were (Day 28, Undo). }
  TLabelSnapshot = class(TMarkSnapshot)
  public
    Marks: array of TTextMark;
    MarkImage: string;
    procedure Restore; override;
  end;

procedure TLabelSnapshot.Restore;
begin
  if Labels = nil then
    Exit;
  Labels.FMarks := Copy(Marks);
  Labels.FMarkImage := MarkImage;
  Labels.FBoxes := nil;
  Labels.Changed;
end;

{ '"Scale 1"', shortened for the menu. }
function Quoted(const AText: string): string;
begin
  if Length(AText) > 24 then
    Result := '"' + Copy(AText, 1, 22) + '..."'
  else
    Result := '"' + AText + '"';
end;

{ TTextLabels }

type
  { The labels kept for their image while another is shown (Day 29,
    uMarkMemory). }
  TLabelMemo = class
  public
    Marks: array of TTextMark;
  end;

const
  MemoryTool = 'labels';

destructor TTextLabels.Destroy;
begin
  FPicture.Free;
  inherited Destroy;
end;

procedure TTextLabels.Changed;
begin
  FPictureKey := '';
  OverlayChanged(Self);
end;

procedure TTextLabels.KeepForUndo(const ACaption: string);
var
  S: TLabelSnapshot;
begin
  S := TLabelSnapshot.Create;
  S.Marks := Copy(FMarks);
  S.MarkImage := FMarkImage;
  PushMarkUndo(S, FImageName, ACaption);
end;

procedure TTextLabels.Start;
begin
  LeaveMeasurement;            { one tool at a time }
  LeaveScaleBar;
  ReloadMarkStyle;             { [ScaleBar] look, edited meanwhile }
  FOn := True;
  ViewerNote('text labels: click on the image to add one, on a label to change or remove it; '
    + 'right click: done', 6000);
  Changed;
end;

procedure TTextLabels.Leave;
begin
  FOn := False;
  Changed;
end;

function TTextLabels.Ask(const ACaption, AText: string; out AResult: string): Boolean;
begin
  AResult := AText;
  NoteMenuOpen(True);
  try
    Result := InputQuery('Text label', ACaption, AResult);
  finally
    NoteMenuOpen(False);
  end;
  AResult := Trim(StringReplace(StringReplace(AResult, #13, ' ', [rfReplaceAll]), #10, ' ',
    [rfReplaceAll]));
end;

function TTextLabels.HitLabel(AX, AY: Integer): Integer;
var
  I: Integer;
begin
  { The topmost (the last drawn) first. }
  for I := High(FBoxes) downto 0 do
    if PtInRect(FBoxes[I], Point(AX, AY)) then
      Exit(I);
  Result := -1;
end;

function TTextLabels.HandleMouse(AView: TObject; AKind: TOverlayMouseKind;
  AButton: TOverlayButton; AX, AY, AWheel: Integer): Boolean;
var
  Renderer: TRenderer;
  ImgX, ImgY: Double;
  Hit, N: Integer;
  NewText: string;
begin
  Result := False;
  { A release reaches a layer only when it took the press: keep it. }
  if AKind = omUp then
    Exit(True);
  if (not FOn) or not (AView is TRenderer) or (AKind <> omDown) then
    Exit;
  Renderer := TRenderer(AView);
  case AButton of
    obLeft:
      begin
        Result := True;
        if (Renderer.Image = nil) or (FImageName = '') then
          Exit;
        if FMarkImage <> FImageName then
        begin
          FMarks := nil;
          FBoxes := nil;
          FMarkImage := FImageName;
        end;
        Hit := HitLabel(AX, AY);
        if Hit >= 0 then
        begin
          { Change it; emptied: removed. }
          if not Ask('Change the text (empty: remove the label):', FMarks[Hit].Text, NewText) then
            Exit;
          if NewText = FMarks[Hit].Text then
            Exit;
          if NewText = '' then
          begin
            KeepForUndo('Undo removal of label ' + Quoted(FMarks[Hit].Text));
            Delete(FMarks, Hit, 1);
          end
          else
          begin
            KeepForUndo('Undo change of label ' + Quoted(FMarks[Hit].Text));
            FMarks[Hit].Text := NewText;
          end;
          Changed;
          Exit;
        end;
        if Length(FMarks) >= MaxLabels then
        begin
          ViewerNote(Format('at most %d labels on an image', [MaxLabels]), 4000);
          Exit;
        end;
        if not Renderer.ScreenToImage(AX + 0.5, AY + 0.5, ImgX, ImgY) then
          Exit;
        if not Ask('Text of the label:', '', NewText) or (NewText = '') then
          Exit;
        KeepForUndo('Undo label ' + Quoted(NewText));
        N := Length(FMarks);
        SetLength(FMarks, N + 1);
        FMarks[N].X := ImgX;
        FMarks[N].Y := ImgY;
        FMarks[N].Text := NewText;
        Changed;
      end;
    obRight:
      begin
        Result := True;          { no menu: it leaves the mode }
        Leave;
      end;
  end;
end;

{ One label, simple text in AColour (Day 29, user); AX, AY its box's top
  left in ABitmap's pixels; ABitmap's font is set. }
procedure DrawText(ABitmap: TBGRABitmap; AX, AY: Integer; const AText: string; APad: Integer;
  AColour: TBGRAPixel);
begin
  ABitmap.TextOut(AX + APad, AY + APad, AText, AColour);
end;

function TTextLabels.Picture(AView: TObject; AWidth, AHeight: Integer;
  out ALeft, ATop: Integer): TBGRABitmap;
var
  Renderer: TRenderer;
  Key: string;
  I, L, T, R, B, W, H, FontPx: Integer;
  SX, SY: Double;
  Sz: TSize;
  Colour: TBGRAPixel;
  Solid: Boolean;
  Memo: TLabelMemo;
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
    FBoxes := nil;
    Exit;
  end;
  FImageName := Renderer.Image.Key.FileName;
  FImageW := Renderer.Image.FullWidth;
  FImageH := Renderer.Image.FullHeight;
  { A new image: the labels go. }
  if (FMarkImage <> '') and (FImageName <> FMarkImage) then
  begin
    { Kept for their image (Day 29, user). }
    if Length(FMarks) > 0 then
    begin
      Memo := TLabelMemo.Create;
      Memo.Marks := Copy(FMarks);
      RememberMarks(MemoryTool, FMarkImage, Memo);
    end;
    FMarks := nil;
    FMarkImage := '';
  end;
  { Back on an image that had labels: they are there again. }
  if (FMarkImage = '') and (FImageName <> '') then
  begin
    Recalled := RecallMarks(MemoryTool, FImageName);
    if Recalled is TLabelMemo then
    begin
      FMarks := Copy(TLabelMemo(Recalled).Marks);
      FMarkImage := FImageName;
    end;
    Recalled.Free;
  end;
  FBoxes := nil;
  if Length(FMarks) = 0 then
    Exit;

  FontPx := Max(8, Round(LabelFontPt * Screen.PixelsPerInch / 72));
  if FPicture = nil then
    FPicture := TBGRABitmap.Create(1, 1);
  FPicture.FontQuality := fqFineAntialiasing;
  SetMarkFont(FPicture, FontPx);
  Colour := MarkColour(BGRAWhite);
  Solid := False;

  { Each label's box on screen; the picture holds them all. }
  SetLength(FBoxes, Length(FMarks));
  Key := Format('%d %d %s %d %d %d %s %d %d', [AWidth, AHeight, BoolToStr(Solid, True), Colour.red,
    Colour.green, Colour.blue, FPicture.FontName, FPicture.FontHeight, MarkStyleVersion]);
  L := MaxInt;
  T := MaxInt;
  R := -MaxInt;
  B := -MaxInt;
  for I := 0 to High(FMarks) do
  begin
    Renderer.ImageToScreen(FMarks[I].X, FMarks[I].Y, SX, SY);
    Sz := FPicture.TextSize(FMarks[I].Text);
    FBoxes[I] := Rect(Round(SX), Round(SY), Round(SX) + Sz.cx + 2 * LabelPad,
      Round(SY) + Sz.cy + 2 * LabelPad);
    Key := Key + Format('|%d %d ', [FBoxes[I].Left, FBoxes[I].Top]) + FMarks[I].Text;
    L := Min(L, FBoxes[I].Left);
    T := Min(T, FBoxes[I].Top);
    R := Max(R, FBoxes[I].Right);
    B := Max(B, FBoxes[I].Bottom);
  end;
  if (Key = FPictureKey) then
  begin
    ALeft := FPictureLeft;
    ATop := FPictureTop;
    Exit(FPicture);
  end;
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
  for I := 0 to High(FMarks) do
    DrawText(FPicture, FBoxes[I].Left - L, FBoxes[I].Top - T, FMarks[I].Text, LabelPad, Colour);
  FPictureKey := Key;
  FPictureLeft := L;
  FPictureTop := T;
  Inc(FVersion);
  ALeft := L;
  ATop := T;
  Result := FPicture;
end;

function TTextLabels.Version: Cardinal;
begin
  Result := FVersion;
end;

function TTextLabels.CanBurnIn(const AImageName: string): Boolean;
begin
  Result := (AImageName <> '') and (AImageName = FMarkImage) and (Length(FMarks) > 0);
end;

{ The labels into the copy, horizontal there, sized for it (as the
  measuring line's labels: about 1/45 of its shorter side). }
function TTextLabels.BurnIn(ABitmap: TBGRABitmap; const AImageName: string;
  const AMap: TBurnInMap): string;
var
  I, Short, FontPx, Pad, X, Y: Integer;
  CX, CY, K: Double;
  Sz: TSize;
  Colour: TBGRAPixel;
begin
  Result := '';
  if (ABitmap = nil) or not CanBurnIn(AImageName) then
    Exit;
  if AMap.ViewScale > 0 then
  begin
    { As on screen (Day 28, user), at the zoom the copy was made at. }
    K := 1 / AMap.ViewScale;
    FontPx := Max(6, Round(LabelFontPt * Screen.PixelsPerInch / 72 * K));
    ABitmap.FontQuality := fqFineAntialiasing;
    SetMarkFont(ABitmap, FontPx);
    Pad := Max(1, Round(LabelPad * K));
  end
  else
  begin
    Short := Max(1, Min(ABitmap.Width, ABitmap.Height));
    FontPx := Max(12, Round(Short / 45));
    ABitmap.FontQuality := fqFineAntialiasing;
    SetMarkFont(ABitmap, FontPx);
    Pad := Max(LabelPad, ABitmap.FontHeight div 4);
  end;
  Colour := MarkColour(BGRAWhite);
  for I := 0 to High(FMarks) do
  begin
    BurnInPoint(AMap, FMarks[I].X, FMarks[I].Y, CX, CY);
    Sz := ABitmap.TextSize(FMarks[I].Text);
    X := EnsureRange(Round(CX), 0, Max(0, ABitmap.Width - Sz.cx - 2 * Pad));
    Y := EnsureRange(Round(CY), 0, Max(0, ABitmap.Height - Sz.cy - 2 * Pad));
    DrawText(ABitmap, X, Y, FMarks[I].Text, Pad, Colour);
  end;
  Result := 'labelled';
end;

function TTextLabels.SvgLayerName: string;
begin
  Result := 'Labels';
end;

{ Each label a text of its own (plain, Day 29): edit,
  move or remove it in the drawing program. }
function TTextLabels.SvgMarkup(const AImageName: string; const AMap: TBurnInMap): string;
var
  I, Short, BaseFontPx: Integer;
  CX, CY, FontPx, Pad, BoxW, BoxH, X, Y: Double;
  Sz: TSize;
  Colour: TBGRAPixel;
  Measure: TBGRABitmap;
begin
  Result := '';
  if not CanBurnIn(AImageName) then
    Exit;
  Short := Max(1, Min(AMap.Width, AMap.Height));
  BaseFontPx := Max(12, Round(Short / 45));
  FontPx := BaseFontPx * MarkFontFactor;
  Pad := Max(LabelPad, Round(FontPx) div 4);
  Colour := MarkColour(BGRAWhite);
  Measure := TBGRABitmap.Create(1, 1);
  try
    SetMarkFont(Measure, BaseFontPx);
    for I := 0 to High(FMarks) do
    begin
      BurnInPoint(AMap, FMarks[I].X, FMarks[I].Y, CX, CY);
      Sz := Measure.TextSize(FMarks[I].Text);
      BoxW := Sz.cx + 2 * Pad;
      BoxH := Sz.cy + 2 * Pad;
      X := EnsureRange(CX, 0, Max(0, AMap.Width - BoxW));
      Y := EnsureRange(CY, 0, Max(0, AMap.Height - BoxH));
      Result := Result + SvgLabel(FMarks[I].Text, X, Y, BoxW, BoxH, Pad, Sz.cy, FontPx, Colour,
        False, Max(1, FontPx / 14));
    end;
  finally
    Measure.Free;
  end;
end;

{ The menu entry and the other tools' call. }

function TextLabelsActive: Boolean;
begin
  Result := (Labels <> nil) and Labels.IsOn;
end;

procedure LeaveTextLabels;
begin
  if (Labels <> nil) and Labels.IsOn then
    Labels.Leave;
end;

procedure ToggleTextLabels(AViewer: TObject);
begin
  if Labels = nil then
    Exit;
  if Labels.IsOn then
    Labels.Leave
  else
    Labels.Start;
end;

function TextLabelsEnabled(AViewer: TObject): Boolean;
begin
  Result := (Labels <> nil) and (ShownImageName <> '');
end;

function TextLabelsChecked(AViewer: TObject): Boolean;
begin
  Result := (Labels <> nil) and Labels.IsOn;
end;

initialization
  Labels := TTextLabels.Create;
  RegisterOverlayLayer(Labels);
  RegisterMenuEntry('Text labels', @ToggleTextLabels, @TextLabelsEnabled, @TextLabelsChecked);
end.
