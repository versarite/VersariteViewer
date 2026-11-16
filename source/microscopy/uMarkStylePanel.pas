unit uMarkStylePanel;

{
  Unit: uMarkStylePanel

  Purpose
  -------
  The marks' look in the left (filter) panel (Day 28, user: "two entries
  in the left panel when scale bar, measurement and text label is
  activated: font and type size"), a panel section (uExtensions) below
  the calibration's rows:
  - "Color  <name>" (Day 29, user): a click opens the colours (white is
    the standard), each with a swatch, and "Other color ..." (the
    system's colour dialog).
  - "Font  <name>": a click opens a list - the standard font, a few
    common ones that are installed, the current one, "Bold" (a tick),
    and "Other font ..." (the system's font dialog).
  - "Size  <n> pt": a click opens the sizes (8 .. 48 pt; 10 is the
    standard).
  The rows are there only while the scale bar, the measuring line (or
  a reference measurement) or the text labels are on. A choice applies
  at once to all three (and to copies and the SVG figure), and is kept
  as [ScaleBar] Color / Font / FontSize / Bold in the edition's ini
  (uScaleBar's SetMarkColour, SetMarkStyle).

  Owns
  ----
  Its popup menu (made again before each opening).

  Threads
  -------
  UI thread.

  Uses (MView units)
  ------------------
  implementation: uCommands, uExtensions, uScaleBar, uMeasureLine,
                  uTextLabel
  Libraries:      Classes, SysUtils, Types, Math, Menus, Dialogs, Forms,
                  Graphics, BGRABitmap, BGRABitmapTypes, LazUTF8

  Used by
  -------
  VersariteImageLab.lpr (its uses list, after uCalibrationPanel: the
  rows come below the calibration's)
}

{$mode ObjFPC}{$H+}

interface

implementation

uses
  Classes,
  SysUtils,
  Types,
  Math,
  Menus,
  Dialogs,
  Forms,
  Graphics,
  BGRABitmap,
  BGRABitmapTypes,
  LazUTF8,
  uCommands,
  uExtensions,
  uScaleBar,
  uMeasureLine,
  uTextLabel;

const
  { Offered when installed (the first that are there, in this order). }
  CommonFonts: array[0..12] of string = ('Arial', 'Segoe UI', 'Calibri', 'Verdana', 'Tahoma',
    'Helvetica', 'Liberation Sans', 'DejaVu Sans', 'Cambria', 'Georgia', 'Times New Roman',
    'Consolas', 'Courier New');
  Sizes: array[0..13] of Integer = (8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 40, 48);
  Colours: array[0..9] of string = ('White', 'Yellow', 'Orange', 'Red', 'Green', 'Cyan', 'Blue',
    'Magenta', 'Grey', 'Black');
  StandardPt = 10;
  RowColour = 0;
  RowFont = 1;
  RowSize = 2;
  TagStandard = -1;
  TagBold = -2;
  TagOther = -3;

type
  TMarkStyleSection = class(TPanelSection)
  private
    FMenu: TPopupMenu;
    FFonts: TStringList;      { the font menu's names, by Tag }
    FKey: string;
    FVersion: Cardinal;
    procedure HandleFontClick(Sender: TObject);
    procedure HandleSizeClick(Sender: TObject);
    procedure HandleColourClick(Sender: TObject);
    procedure PopUp(const AScreen: TPoint);
  public
    destructor Destroy; override;
    function RowCount: Integer; override;
    procedure DrawRow(ARow: Integer; ABitmap: TBGRABitmap; const ARect: TRect;
      AHover: Boolean; AScale: Double); override;
    function Hint(ARow: Integer): string; override;
    procedure Click(ARow: Integer; AButton: TOverlayButton; const AScreen: TPoint); override;
    function Version: Cardinal; override;
  end;

{ A mark tool is on: the rows are there. }
function ToolOn: Boolean;
begin
  Result := ScaleBarActive or MeasurementActive or TextLabelsActive;
end;

function FontText: string;
begin
  if MarkFontName = '' then
    Result := 'Standard'
  else
    Result := MarkFontName;
  if MarkFontBold then
    Result := Result + ', bold';
end;

{ The colour as set: its name ('White' when not set), or #RRGGBB / R,G,B
  as written. }
function ColourText: string;
begin
  Result := MarkColourText;
  if Result = '' then
    Result := 'White';
end;

function ColourNow: TBGRAPixel;
begin
  Result := MarkColour(BGRAWhite);
end;

{ A small square of AColour for a menu entry. }
function Swatch(const AColour: TBGRAPixel): TBitmap;
begin
  Result := TBitmap.Create;
  Result.SetSize(14, 14);
  Result.Canvas.Brush.Color := RGBToColor(AColour.red, AColour.green, AColour.blue);
  Result.Canvas.Pen.Color := clGray;
  Result.Canvas.Rectangle(0, 0, 14, 14);
end;

function SizeText: string;
begin
  if MarkFontPt = 0 then
    Result := IntToStr(StandardPt) + ' pt'
  else
    Result := IntToStr(MarkFontPt) + ' pt';
end;

{ AText cut with '...' to fit AWidth pixels. }
function FitText(ABitmap: TBGRABitmap; const AText: string; AWidth: Integer): string;
var
  N: Integer;
begin
  Result := AText;
  if ABitmap.TextSize(AText).cx <= AWidth then
    Exit;
  N := UTF8Length(AText);
  while (N > 0) and (ABitmap.TextSize(UTF8Copy(AText, 1, N) + '...').cx > AWidth) do
    Dec(N);
  Result := UTF8Copy(AText, 1, N) + '...';
end;

destructor TMarkStyleSection.Destroy;
begin
  FMenu.Free;
  FFonts.Free;
  inherited Destroy;
end;

function TMarkStyleSection.RowCount: Integer;
begin
  if ToolOn then
    Result := 3
  else
    Result := 0;
end;

procedure TMarkStyleSection.DrawRow(ARow: Integer; ABitmap: TBGRABitmap; const ARect: TRect;
  AHover: Boolean; AScale: Double);
var
  Pad, TextY, ArrowW, X, Sw, SwY: Integer;
  Text, Dim: TBGRAPixel;
  Caption, Value: string;
begin
  Text := BGRA(235, 235, 235, 255);
  Dim := BGRA(160, 160, 160, 255);
  Pad := Max(1, Round(10 * AScale));
  ABitmap.FontHeight := Max(9, Min(Round(13 * AScale), ARect.Height * 2 div 5));
  TextY := ARect.Top + (ARect.Height - ABitmap.TextSize('Xg').cy) div 2;
  case ARow of
    RowColour:
      begin
        Caption := 'Color';
        Value := ColourText;
      end;
    RowFont:
      begin
        Caption := 'Font';
        Value := FontText;
      end;
  else
    Caption := 'Size';
    Value := SizeText;
  end;
  { 'Font  <value>  v', the values in one column. }
  ABitmap.TextOut(ARect.Left + Pad, TextY, Caption, Dim);
  X := ARect.Left + Pad + Max(ABitmap.TextSize('Color').cx, Max(ABitmap.TextSize('Font').cx,
    ABitmap.TextSize('Size').cx)) + Pad;
  { The colour row: a swatch before the name. }
  if ARow = RowColour then
  begin
    Sw := ABitmap.TextSize('Xg').cy * 3 div 4;
    SwY := ARect.Top + (ARect.Height - Sw) div 2;
    ABitmap.FillRect(X, SwY, X + Sw, SwY + Sw, ColourNow, dmSet);
    ABitmap.Rectangle(X, SwY, X + Sw, SwY + Sw, Dim, dmSet);
    X := X + Sw + Pad div 2;
  end;
  ArrowW := Max(6, Round(8 * AScale));
  Value := FitText(ABitmap, Value, ARect.Right - Pad - ArrowW - Pad div 2 - X);
  ABitmap.TextOut(X, TextY, Value, Text);
  ABitmap.FillPolyAntialias([
    PointF(ARect.Right - Pad - ArrowW, ARect.Top + ARect.Height / 2 - ArrowW / 4),
    PointF(ARect.Right - Pad, ARect.Top + ARect.Height / 2 - ArrowW / 4),
    PointF(ARect.Right - Pad - ArrowW / 2, ARect.Top + ARect.Height / 2 + ArrowW / 4)],
    Dim);
end;

function TMarkStyleSection.Hint(ARow: Integer): string;
begin
  if ARow = RowColour then
    Result := 'click: the colour of the marks' + LineEnding + '(lines and texts; white is the standard)'
  else if ARow = RowFont then
    Result := 'click: the font of the marks' + LineEnding + '(scale bar, measurements, labels)'
  else
    Result := 'click: the size of the marks'' text' + LineEnding + '(10 pt is the standard)';
end;

procedure TMarkStyleSection.PopUp(const AScreen: TPoint);
begin
  { The pointer stays while the list is open. }
  NoteMenuOpen(True);
  try
    FMenu.PopUp(AScreen.X, AScreen.Y);
  finally
    NoteMenuOpen(False);
  end;
end;

procedure TMarkStyleSection.HandleFontClick(Sender: TObject);
var
  Tag: PtrInt;
  Dialog: TFontDialog;
begin
  Tag := TMenuItem(Sender).Tag;
  case Tag of
    TagStandard:
      SetMarkStyle('', MarkFontPt, MarkFontBold);
    TagBold:
      SetMarkStyle(MarkFontName, MarkFontPt, not MarkFontBold);
    TagOther:
      begin
        Dialog := TFontDialog.Create(nil);
        NoteMenuOpen(True);
        try
          if MarkFontName <> '' then
            Dialog.Font.Name := MarkFontName;
          if MarkFontPt > 0 then
            Dialog.Font.Size := MarkFontPt
          else
            Dialog.Font.Size := StandardPt;
          if MarkFontBold then
            Dialog.Font.Style := [fsBold];
          if Dialog.Execute then
            SetMarkStyle(Dialog.Font.Name, Dialog.Font.Size, fsBold in Dialog.Font.Style);
        finally
          NoteMenuOpen(False);
          Dialog.Free;
        end;
      end;
  else
    if (Tag >= 0) and (Tag < FFonts.Count) then
      SetMarkStyle(FFonts[Tag], MarkFontPt, MarkFontBold);
  end;
end;

procedure TMarkStyleSection.HandleColourClick(Sender: TObject);
var
  Tag: PtrInt;
  Dialog: TColorDialog;
  C: TBGRAPixel;
begin
  Tag := TMenuItem(Sender).Tag;
  if Tag = TagOther then
  begin
    Dialog := TColorDialog.Create(nil);
    NoteMenuOpen(True);
    try
      C := ColourNow;
      Dialog.Color := RGBToColor(C.red, C.green, C.blue);
      if Dialog.Execute then
        SetMarkColour(Format('#%.2X%.2X%.2X', [Red(Dialog.Color), Green(Dialog.Color),
          Blue(Dialog.Color)]));
    finally
      NoteMenuOpen(False);
      Dialog.Free;
    end;
  end
  { White is the standard: kept as empty. }
  else if Tag = 0 then
    SetMarkColour('')
  else if (Tag > 0) and (Tag <= High(Colours)) then
    SetMarkColour(Colours[Tag]);
end;

procedure TMarkStyleSection.HandleSizeClick(Sender: TObject);
var
  Pt: Integer;
begin
  Pt := TMenuItem(Sender).Tag;
  { 10 pt is the standard: kept as 0 (follows the standard). }
  if Pt = StandardPt then
    Pt := 0;
  SetMarkStyle(MarkFontName, Pt, MarkFontBold);
end;

procedure TMarkStyleSection.Click(ARow: Integer; AButton: TOverlayButton; const AScreen: TPoint);
var
  Item: TMenuItem;
  I, Current: Integer;
  C: TBGRAPixel;
  B: TBitmap;

  procedure AddItem(const ACaption: string; ATag: PtrInt; AChecked, ARadio: Boolean;
    AHandler: TNotifyEvent);
  begin
    Item := TMenuItem.Create(FMenu);
    Item.Caption := StringReplace(ACaption, '&', '&&', [rfReplaceAll]);
    Item.Tag := ATag;
    Item.RadioItem := ARadio;
    Item.Checked := AChecked;
    Item.OnClick := AHandler;
    FMenu.Items.Add(Item);
  end;

  procedure AddLine;
  begin
    Item := TMenuItem.Create(FMenu);
    Item.Caption := '-';
    FMenu.Items.Add(Item);
  end;

begin
  if FMenu = nil then
    FMenu := TPopupMenu.Create(nil);
  if FFonts = nil then
    FFonts := TStringList.Create;
  FMenu.Items.Clear;
  if ARow = RowColour then
  begin
    for I := 0 to High(Colours) do
    begin
      if I = 0 then
        AddItem('White  (standard)', I, (MarkColourText = '') or SameText(MarkColourText, 'White'),
          True, @HandleColourClick)
      else
        AddItem(Colours[I], I, SameText(MarkColourText, Colours[I])
          or (SameText(Colours[I], 'Grey') and SameText(MarkColourText, 'Gray')), True,
          @HandleColourClick);
      if ParseMarkColour(Colours[I], C) then
      begin
        B := Swatch(C);
        try
          Item.Bitmap := B;
        finally
          B.Free;
        end;
      end;
    end;
    AddLine;
    AddItem('Other color ...', TagOther, False, False, @HandleColourClick);
  end
  else if ARow = RowFont then
  begin
    { The installed common fonts, and the current one if it is another. }
    FFonts.Clear;
    for I := Low(CommonFonts) to High(CommonFonts) do
      if Screen.Fonts.IndexOf(CommonFonts[I]) >= 0 then
        FFonts.Add(CommonFonts[I]);
    if (MarkFontName <> '') and (FFonts.IndexOf(MarkFontName) < 0) then
      FFonts.Insert(0, MarkFontName);
    AddItem('Standard', TagStandard, MarkFontName = '', True, @HandleFontClick);
    for I := 0 to FFonts.Count - 1 do
      AddItem(FFonts[I], I, SameText(FFonts[I], MarkFontName), True, @HandleFontClick);
    AddLine;
    AddItem('Bold', TagBold, MarkFontBold, False, @HandleFontClick);
    AddLine;
    AddItem('Other font ...', TagOther, False, False, @HandleFontClick);
  end
  else
  begin
    Current := MarkFontPt;
    if Current = 0 then
      Current := StandardPt;
    for I := Low(Sizes) to High(Sizes) do
      if Sizes[I] = StandardPt then
        AddItem(IntToStr(Sizes[I]) + ' pt  (standard)', Sizes[I], Current = Sizes[I], True,
          @HandleSizeClick)
      else
        AddItem(IntToStr(Sizes[I]) + ' pt', Sizes[I], Current = Sizes[I], True, @HandleSizeClick);
  end;
  PopUp(AScreen);
end;

{ A new number whenever the rows would look different (or come / go). }
function TMarkStyleSection.Version: Cardinal;
var
  Key: string;
begin
  Key := BoolToStr(ToolOn, True) + '|' + ColourText + '|' + FontText + '|' + SizeText;
  if Key <> FKey then
  begin
    FKey := Key;
    Inc(FVersion);
  end;
  Result := FVersion;
end;

initialization
  RegisterPanelSection(TMarkStyleSection.Create);
end.
