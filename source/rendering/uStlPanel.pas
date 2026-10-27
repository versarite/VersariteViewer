unit uStlPanel;

{
  Unit: uStlPanel

  Purpose
  -------
  The controls of a 3D model (.stl, 1.3) in the left (filter) panel,
  below Auto / Reset all, while a model is shown: on / off boxes and
  sliders as the filter rows, no buttons (user, Day 33).

  Owns
  ----
  The view of the model (uStlModel.TStlView) as set in the rows; the
  settings kept for the next models (grid, edges, smoothing).

  Knows
  -----
  uExtensions (TPanelSection), uFilterPanel (the rows' look),
  uStlModel (TStlView).

  Responsibilities
  ----------------
  - Rows: Section, Flip side, Plane X, Plane Y, Plane position,
    Elevation, Smoothing, Grid, Edges. Moving the plane turns the
    section on (as in the STL viewer).
  - OnChange after every change by the user (TMView draws the model
    again).

  Does NOT
  --------
  Draw the model, or turn it (the rotate mode does: TMView, Turn).

  Threads
  -------
  UI thread only.
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  Math,
  Types,
  BGRABitmap,
  BGRABitmapTypes,
  uCommands,
  uExtensions,
  uFilterPanel,
  uStlModel;

type
  TStlSection = class(TPanelSection)
  private
    FActive: Boolean;
    FView: TStlView;
    FVersion: Cardinal;
    FOnChange: TNotifyEvent;
    procedure SetActive(AValue: Boolean);
    procedure SetView(const AValue: TStlView);
    procedure Changed;
    function GetValue(ARow: Integer): Integer;
    procedure SetValue(ARow, AValue: Integer);
  public
    constructor Create;
    function RowCount: Integer; override;
    function RowKind(ARow: Integer): TSectionRowKind; override;
    procedure DrawRow(ARow: Integer; ABitmap: TBGRABitmap; const ARect: TRect;
      AHover: Boolean; AScale: Double); override;
    function Hint(ARow: Integer): string; override;
    procedure Click(ARow: Integer; AButton: TOverlayButton; const AScreen: TPoint); override;
    function SliderPos(ARow: Integer): Double; override;
    procedure SetSliderPos(ARow: Integer; APos: Double); override;
    procedure Wheel(ARow: Integer; ANotches: Double); override;
    procedure ResetRow(ARow: Integer); override;
    function Version: Cardinal; override;

    { The view for a new model: the start view with the kept settings. }
    function StartView: TStlView;
    { A model is shown: the rows are there. }
    property Active: Boolean read FActive write SetActive;
    property View: TStlView read FView write SetView;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

const
  StlRowSection = 0;
  StlRowFlip = 1;
  StlRowPlaneX = 2;
  StlRowPlaneY = 3;
  StlRowPlanePos = 4;
  StlRowElevation = 5;
  StlRowSmooth = 6;
  StlRowGrid = 7;
  StlRowEdges = 8;
  StlRowCount = 9;

implementation

type
  TSliderRange = record
    Lo, Hi, Step: Integer;
  end;

function SliderRange(ARow: Integer): TSliderRange;
begin
  Result.Step := 5;
  case ARow of
    StlRowPlanePos:
      begin
        Result.Lo := -100;
        Result.Hi := 100;
      end;
    StlRowSmooth:
      begin
        Result.Lo := 1;
        Result.Hi := 10;
        Result.Step := 1;
      end;
  else
    Result.Lo := -90;
    Result.Hi := 90;
  end;
end;

constructor TStlSection.Create;
begin
  inherited Create;
  FView := DefaultStlView;
end;

function TStlSection.StartView: TStlView;
begin
  Result := StlStartView;
end;

procedure TStlSection.SetActive(AValue: Boolean);
begin
  if FActive = AValue then
    Exit;
  FActive := AValue;
  Inc(FVersion);
end;

procedure TStlSection.SetView(const AValue: TStlView);
var
  Shown: Boolean;
begin
  if SameStlView(FView, AValue) then
    Exit;
  { Drawn again only if a row looks different (1.3, speed: the turn is
    in no row, and a drag changes the elevation by fractions of a
    degree - the panel was drawn again for every mouse move). }
  Shown := (FView.Section <> AValue.Section) or (FView.Flip <> AValue.Flip)
    or (FView.PlaneX <> AValue.PlaneX) or (FView.PlaneY <> AValue.PlaneY)
    or (FView.PlanePos <> AValue.PlanePos) or (Round(FView.Tilt) <> Round(AValue.Tilt))
    or (FView.Smooth <> AValue.Smooth) or (FView.Grid <> AValue.Grid)
    or (FView.Edges <> AValue.Edges);
  FView := AValue;
  if Shown then
    Inc(FVersion);
end;

procedure TStlSection.Changed;
begin
  Inc(FVersion);
  { Grid, edges, smoothing: for the next models too. }
  KeepStlSettings(FView);
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

function TStlSection.RowCount: Integer;
begin
  if FActive then
    Result := StlRowCount
  else
    Result := 0;
end;

function TStlSection.RowKind(ARow: Integer): TSectionRowKind;
begin
  case ARow of
    StlRowPlaneX, StlRowPlaneY, StlRowPlanePos, StlRowElevation, StlRowSmooth:
      Result := srkSlider;
  else
    Result := srkToggle;
  end;
end;

function TStlSection.GetValue(ARow: Integer): Integer;
begin
  case ARow of
    StlRowPlaneX:    Result := FView.PlaneX;
    StlRowPlaneY:    Result := FView.PlaneY;
    StlRowPlanePos:  Result := FView.PlanePos;
    StlRowElevation: Result := Round(FView.Tilt);
    StlRowSmooth:    Result := FView.Smooth;
  else
    Result := 0;
  end;
end;

procedure TStlSection.SetValue(ARow, AValue: Integer);
var
  Range: TSliderRange;
begin
  Range := SliderRange(ARow);
  AValue := EnsureRange(AValue, Range.Lo, Range.Hi);
  if AValue = GetValue(ARow) then
    Exit;
  case ARow of
    StlRowPlaneX:    FView.PlaneX := AValue;
    StlRowPlaneY:    FView.PlaneY := AValue;
    StlRowPlanePos:  FView.PlanePos := AValue;
    StlRowElevation: FView.Tilt := AValue;
    StlRowSmooth:    FView.Smooth := AValue;
  end;
  { Moving the plane shows the cut (as in the STL viewer). }
  if ARow in [StlRowPlaneX, StlRowPlaneY, StlRowPlanePos] then
    FView.Section := True;
  Changed;
end;

{ The start values: the neutral ticks. }
function StartValue(ARow: Integer): Integer;
var
  V: TStlView;
begin
  V := DefaultStlView;
  case ARow of
    StlRowElevation: Result := Round(V.Tilt);
    StlRowSmooth:    Result := V.Smooth;
  else
    Result := 0;
  end;
end;

function TStlSection.SliderPos(ARow: Integer): Double;
var
  Range: TSliderRange;
begin
  Range := SliderRange(ARow);
  Result := (GetValue(ARow) - Range.Lo) / (Range.Hi - Range.Lo);
end;

procedure TStlSection.SetSliderPos(ARow: Integer; APos: Double);
var
  Range: TSliderRange;
begin
  if RowKind(ARow) <> srkSlider then
    Exit;
  Range := SliderRange(ARow);
  SetValue(ARow, Round(Range.Lo + EnsureRange(APos, 0, 1) * (Range.Hi - Range.Lo)));
end;

procedure TStlSection.Wheel(ARow: Integer; ANotches: Double);
var
  Range: TSliderRange;
  Steps: Integer;
begin
  if RowKind(ARow) <> srkSlider then
    Exit;
  Range := SliderRange(ARow);
  Steps := Round(ANotches);
  if Steps = 0 then
    Steps := Sign(ANotches);
  SetValue(ARow, GetValue(ARow) + Steps * Range.Step);
end;

procedure TStlSection.ResetRow(ARow: Integer);
begin
  if RowKind(ARow) = srkSlider then
    SetValue(ARow, StartValue(ARow));
end;

procedure TStlSection.Click(ARow: Integer; AButton: TOverlayButton; const AScreen: TPoint);
begin
  case ARow of
    StlRowSection: FView.Section := not FView.Section;
    StlRowFlip:
      begin
        FView.Flip := not FView.Flip;
        FView.Section := True;
      end;
    StlRowGrid:    FView.Grid := not FView.Grid;
    StlRowEdges:   FView.Edges := not FView.Edges;
  else
    Exit;
  end;
  Changed;
end;

procedure TStlSection.DrawRow(ARow: Integer; ABitmap: TBGRABitmap; const ARect: TRect;
  AHover: Boolean; AScale: Double);

  function OnOff(AOn: Boolean): string;
  begin
    if AOn then
      Result := 'on'
    else
      Result := 'off';
  end;

  procedure Slider(const AName, AValue: string);
  var
    Range: TSliderRange;
  begin
    Range := SliderRange(ARow);
    DrawPanelSlider(ABitmap, ARect, AName, AValue, SliderPos(ARow),
      (StartValue(ARow) - Range.Lo) / (Range.Hi - Range.Lo), AHover, AScale);
  end;

begin
  case ARow of
    StlRowSection:   DrawPanelToggle(ABitmap, ARect, 'Section', OnOff(FView.Section), FView.Section, AScale);
    StlRowFlip:      DrawPanelToggle(ABitmap, ARect, 'Flip side', OnOff(FView.Flip), FView.Flip, AScale);
    StlRowPlaneX:    Slider('Plane X', IntToStr(FView.PlaneX) + '°');
    StlRowPlaneY:    Slider('Plane Y', IntToStr(FView.PlaneY) + '°');
    StlRowPlanePos:  Slider('Plane position', IntToStr(FView.PlanePos) + ' %');
    StlRowElevation: Slider('Elevation', IntToStr(Round(FView.Tilt)) + '°');
    StlRowSmooth:    Slider('Smoothing', IntToStr(FView.Smooth));
    StlRowGrid:      DrawPanelToggle(ABitmap, ARect, 'Grid', OnOff(FView.Grid), FView.Grid, AScale);
    StlRowEdges:     DrawPanelToggle(ABitmap, ARect, 'Edges', OnOff(FView.Edges), FView.Edges, AScale);
  end;
end;

function TStlSection.Hint(ARow: Integer): string;
const
  SliderHelp = LineEnding + 'wheel, drag    double-click: reset';
begin
  case ARow of
    StlRowSection:   Result := 'click: cut by the plane' + LineEnding + 'the cut face is shown closed';
    StlRowFlip:      Result := 'click: keep the other side' + LineEnding + 'of the plane';
    StlRowPlaneX:    Result := 'the plane tilted around X' + SliderHelp;
    StlRowPlaneY:    Result := 'the plane tilted around Y' + SliderHelp;
    StlRowPlanePos:  Result := 'the plane along its normal' + SliderHelp;
    StlRowElevation: Result := 'seen from above / below' + SliderHelp;
    StlRowSmooth:    Result := 'curved faces softer' + SliderHelp;
    StlRowGrid:      Result := 'click: the build plate' + LineEnding + 'under the model';
    StlRowEdges:     Result := 'click: the triangles'' edges';
  else
    Result := '';
  end;
end;

function TStlSection.Version: Cardinal;
begin
  Result := FVersion;
end;

end.
