unit uCalibrationPanel;

{
  Unit: uCalibrationPanel

  Purpose
  -------
  The calibration's two rows at the bottom of the left (filter) panel
  (M3b, Day 25, user; spec "Microscopy edition" §7.1), a panel section
  (uExtensions):
  - "Scale": where the shown image's µm come from, with the value - the
    file's own metadata ("lif metadata 0.1173 µm/px" inside a .lif, a
    stack and its frames too; "file metadata ..." for a TIFF that says
    it; Day 26, user: say so, measuring on a .lif uses its metadata), a
    matching .lif ('221119.lif › Series084'), a crop's or copy's parent
    ('from Series009 (crop)', Day 26), the chosen calibration's name, or
    "none (pixels)". A click opens the list: none, every
    calibration of calibrations.ini (with its value), and "Reference
    measurement (calibrate)". The choice sticks for the next images
    (and is kept in the edition's ini).
  - "Confocal" (a check box): a reference measurement made now keeps
    the image width and zoom (a scanner) or is a fixed px/µm (a camera).

  Owns
  ----
  Its popup menu (made again before each opening).

  Does NOT
  --------
  - Keep the choice itself (uImageScale does), or measure (uMeasureLine).

  Threads
  -------
  UI thread.

  Uses (MView units)
  ------------------
  implementation: uCommands, uExtensions, uImageScale, uCalibrations,
                  uMeasureLine
  Libraries:      Classes, SysUtils, Types, Math, Menus, BGRABitmap,
                  BGRABitmapTypes, LazUTF8

  Used by
  -------
  VersariteImageLab.lpr (its uses list only)
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
  BGRABitmap,
  BGRABitmapTypes,
  LazUTF8,
  uCommands,
  uExtensions,
  uContainers,
  uImageScale,
  uCalibrations,
  uMeasureLine;

type
  TValueKind = (vkNone, vkFile, vkCalibration);

  TCalibrationSection = class(TPanelSection)
  private
    FMenu: TPopupMenu;
    FKey: string;
    FVersion: Cardinal;
    function ScaleText(out AKind: TValueKind): string;
    procedure HandleMenuClick(Sender: TObject);
  public
    destructor Destroy; override;
    function RowCount: Integer; override;
    procedure DrawRow(ARow: Integer; ABitmap: TBGRABitmap; const ARect: TRect;
      AHover: Boolean; AScale: Double); override;
    function Hint(ARow: Integer): string; override;
    procedure Click(ARow: Integer; AButton: TOverlayButton; const AScreen: TPoint); override;
    function Version: Cardinal; override;
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

destructor TCalibrationSection.Destroy;
begin
  FMenu.Free;
  inherited Destroy;
end;

function TCalibrationSection.RowCount: Integer;
begin
  Result := 2;
end;

{ What the selector shows for the image shown. }
{ '0.1173 µm/px' }
function ValueText(const AScale: TImageScale): string;
begin
  Result := FloatToStrF(AScale.UmPerPixelX, ffGeneral, 4, 0) + ' µm/px';
end;

function TCalibrationSection.ScaleText(out AKind: TValueKind): string;
const
  CalPrefix = 'calibration: ';
var
  Scale: TImageScale;
  Ext: string;
begin
  AKind := vkNone;
  if ShownImageName = '' then
    Exit('no image');
  if not ScaleFor(ShownImageName, ShownImageWidth, ShownImageHeight, Scale) then
    Exit('none (pixels)');
  if Scale.Source = '' then
  begin
    AKind := vkFile;
    { Its own metadata: inside a container ('lif metadata', a stack's
      frame too), or the file's. }
    if IsVirtualName(ShownImageName) then
    begin
      Ext := LowerCase(ExtractFileExt(ContainerFileOf(ShownImageName)));
      Delete(Ext, 1, 1);
      Result := Ext + ' metadata  ' + ValueText(Scale);
    end
    else
      Result := 'file metadata  ' + ValueText(Scale);
  end
  else if Pos(CalPrefix, Scale.Source) = 1 then
  begin
    AKind := vkCalibration;
    Result := Copy(Scale.Source, Length(CalPrefix) + 1, MaxInt);
  end
  else
  begin
    AKind := vkFile;
    Result := 'from ' + Scale.Source;
  end;
end;

procedure TCalibrationSection.DrawRow(ARow: Integer; ABitmap: TBGRABitmap; const ARect: TRect;
  AHover: Boolean; AScale: Double);
var
  Pad, TextY, BoxS, BoxX, BoxY, ArrowW, X: Integer;
  Text, Dim, Lit, Col: TBGRAPixel;
  Kind: TValueKind;
  Value, Caption: string;
begin
  Text := BGRA(235, 235, 235, 255);
  Dim := BGRA(160, 160, 160, 255);
  Lit := BGRA(255, 190, 60, 255);
  Pad := Max(1, Round(10 * AScale));
  ABitmap.FontHeight := Max(9, Min(Round(13 * AScale), ARect.Height * 2 div 5));
  TextY := ARect.Top + (ARect.Height - ABitmap.TextSize('Xg').cy) div 2;
  case ARow of
    0:
      begin
        { 'Scale  <value>  v' }
        Caption := 'Scale';
        ABitmap.TextOut(ARect.Left + Pad, TextY, Caption, Dim);
        X := ARect.Left + Pad + ABitmap.TextSize(Caption).cx + Pad;
        ArrowW := Max(6, Round(8 * AScale));
        Value := ScaleText(Kind);
        case Kind of
          vkCalibration: Col := Lit;
          vkFile: Col := Text;
        else
          Col := Dim;
        end;
        Value := FitText(ABitmap, Value, ARect.Right - Pad - ArrowW - Pad div 2 - X);
        ABitmap.TextOut(X, TextY, Value, Col);
        { A small triangle: a list opens. }
        ABitmap.FillPolyAntialias([
          PointF(ARect.Right - Pad - ArrowW, ARect.Top + ARect.Height / 2 - ArrowW / 4),
          PointF(ARect.Right - Pad, ARect.Top + ARect.Height / 2 - ArrowW / 4),
          PointF(ARect.Right - Pad - ArrowW / 2, ARect.Top + ARect.Height / 2 + ArrowW / 4)],
          Dim);
      end;
    1:
      begin
        { '[x] Confocal' }
        BoxS := Max(9, Min(Round(13 * AScale), ARect.Height div 2));
        BoxX := ARect.Left + Pad;
        BoxY := ARect.Top + (ARect.Height - BoxS) div 2;
        if ConfocalMode then
          Col := Lit
        else
          Col := Dim;
        ABitmap.RectangleAntialias(BoxX, BoxY, BoxX + BoxS, BoxY + BoxS, Col, Max(1, AScale));
        if ConfocalMode then
        begin
          ABitmap.DrawLineAntialias(BoxX + BoxS * 0.2, BoxY + BoxS * 0.55, BoxX + BoxS * 0.42,
            BoxY + BoxS * 0.78, Col, Max(1.5, AScale * 1.5));
          ABitmap.DrawLineAntialias(BoxX + BoxS * 0.42, BoxY + BoxS * 0.78, BoxX + BoxS * 0.82,
            BoxY + BoxS * 0.22, Col, Max(1.5, AScale * 1.5));
        end;
        ABitmap.TextOut(BoxX + BoxS + Pad, TextY, 'Confocal', Text);
      end;
  end;
end;

function TCalibrationSection.Hint(ARow: Integer): string;
var
  Kind: TValueKind;
  Index: Integer;
  Scale: TImageScale;
begin
  Result := '';
  case ARow of
    0:
      begin
        ScaleText(Kind);
        if (Kind = vkFile) and ScaleFor(ShownImageName, ShownImageWidth, ShownImageHeight, Scale) then
          Result := 'measured with ' + ValueText(Scale) + LineEnding
            + '(calibrations: for images without)'
        else
        begin
          Index := Calibrations.IndexOfName(ChosenCalibration);
          if Index >= 0 then
            Result := 'click: choose a calibration' + LineEnding
              + CalibrationValueText(Calibrations.Item(Index))
          else
            Result := 'click: choose a calibration' + LineEnding
              + 'none yet: reference measurement';
        end;
      end;
    1:
      if ConfocalMode then
        Result := 'calibrations made now scale' + LineEnding + 'with image width and zoom'
      else
        Result := 'calibrations made now: a fixed' + LineEnding + 'px per µm (a camera)';
  end;
end;

procedure TCalibrationSection.HandleMenuClick(Sender: TObject);
var
  Tag: PtrInt;
begin
  Tag := TMenuItem(Sender).Tag;
  if Tag = -2 then
    StartReferenceMeasurement
  else if Tag = -1 then
    ChooseCalibration('')
  else if (Tag >= 0) and (Tag < Calibrations.Count) then
    ChooseCalibration(Calibrations.Item(Tag).Name);
  { The panel's row and any line in µm: draw again. }
  OverlayChanged(nil);
end;

procedure TCalibrationSection.Click(ARow: Integer; AButton: TOverlayButton; const AScreen: TPoint);
var
  Item: TMenuItem;
  I: Integer;
  Chosen: string;
begin
  case ARow of
    0:
      begin
        if FMenu = nil then
          FMenu := TPopupMenu.Create(nil);
        FMenu.Items.Clear;
        Chosen := ChosenCalibration;
        Item := TMenuItem.Create(FMenu);
        Item.Caption := 'None (pixels only)';
        Item.Tag := -1;
        Item.RadioItem := True;
        Item.Checked := Chosen = '';
        Item.OnClick := @HandleMenuClick;
        FMenu.Items.Add(Item);
        for I := 0 to Calibrations.Count - 1 do
        begin
          Item := TMenuItem.Create(FMenu);
          Item.Caption := StringReplace(Calibrations.Item(I).Name, '&', '&&', [rfReplaceAll])
            + '      ' + CalibrationValueText(Calibrations.Item(I));
          Item.Tag := I;
          Item.RadioItem := True;
          Item.Checked := SameText(Calibrations.Item(I).Name, Chosen);
          Item.OnClick := @HandleMenuClick;
          FMenu.Items.Add(Item);
        end;
        Item := TMenuItem.Create(FMenu);
        Item.Caption := '-';
        FMenu.Items.Add(Item);
        Item := TMenuItem.Create(FMenu);
        Item.Caption := 'Reference measurement (calibrate) ...';
        Item.Tag := -2;
        Item.Enabled := ShownImageName <> '';
        Item.OnClick := @HandleMenuClick;
        FMenu.Items.Add(Item);
        { The pointer stays while the list is open (Day 26: it vanished
          outside the list). }
        NoteMenuOpen(True);
        try
          FMenu.PopUp(AScreen.X, AScreen.Y);
        finally
          NoteMenuOpen(False);
        end;
      end;
    1:
      begin
        SetConfocalMode(not ConfocalMode);
        OverlayChanged(nil);
      end;
  end;
end;

{ A new number whenever the rows would look different. }
function TCalibrationSection.Version: Cardinal;
var
  Key: string;
begin
  Key := ShownImageName + '|' + IntToStr(ShownImageWidth) + 'x' + IntToStr(ShownImageHeight)
    + '|' + ChosenCalibration + '|' + BoolToStr(ConfocalMode, True)
    + '|' + IntToStr(Calibrations.Count);
  if Key <> FKey then
  begin
    FKey := Key;
    Inc(FVersion);
  end;
  Result := FVersion;
end;

initialization
  RegisterPanelSection(TCalibrationSection.Create);
end.
