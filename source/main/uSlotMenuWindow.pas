unit uSlotMenuWindow;

{
  Unit: uSlotMenuWindow

  Purpose
  -------
  The sort panel's folder menu (the "..." of a folder, Day 27, testers)
  as MView's own small window instead of a Windows popup menu: a Windows
  menu closes on the first click, so "Move up" could not be clicked
  again and again, nor held. This window stays open while a folder is
  moved, repeats Move up / Move down while the button is held, and
  stands left of the panel so the folders stay in sight.

  Owns
  ----
  - Nothing of the menu: it shows a TMenuItem tree that stays its
    owner's (umainform's FSortMenu), and runs the items' OnClick.

  Responsibilities
  ----------------
  - Rows for the root's items: separators ("-"), disabled lines,
    checked and radio items (a tick / a dot), an item's bitmap.
  - An item with sub-items opens below itself, indented (one at a time);
    a second click closes it again. Too tall for the screen: the wheel
    scrolls.
  - A click on an item: the window closes, then the item runs. Items
    whose Hint is SlotMenuRepeatHint run without closing, and again and
    again while the button is held (first after RepeatFirstMs, then
    every RepeatEveryMs).
  - Closes on Esc, on a click elsewhere (it loses focus); Up / Down /
    Enter work as in a menu. OnClosed tells the owner.

  Does NOT
  --------
  - Build the menu, or know what the items do.

  Threads
  -------
  UI thread only.

  Uses (MView units)
  ------------------
  None.
  Libraries:      Classes, SysUtils, Math, Types, Controls, Forms,
                  Graphics, Menus, ExtCtrls, LCLType

  Used by
  -------
  umainform
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  Math,
  Types,
  Controls,
  Forms,
  Graphics,
  Menus,
  ExtCtrls,
  LCLType;

const
  { An item with this Hint runs without closing the window, and repeats
    while held (Move up / Move down). }
  SlotMenuRepeatHint = 'repeat';
  { An item with this Tag is drawn bold, in deep green: an entry used
    often (1.1, user: "Choose icon file ..."), as the right-click menu's. }
  SlotMenuStrongTag = -200002;

type

  TSlotMenuRow = record
    Item: TMenuItem;
    Level: Integer;     { 0 = the root's item, 1 = an open sub-item }
    Top: Integer;       { in the list, without the scroll }
    Height: Integer;
  end;

  TSlotMenuWindow = class(TForm)
  private
    FRoot: TMenuItem;
    FRows: array of TSlotMenuRow;
    FOpenSub: TMenuItem;          { the item whose sub-items are shown; nil = none }
    FHover: Integer;
    FPressed: Integer;
    FScroll: Integer;
    FListH: Integer;
    FRowH, FSepH, FCheckW, FIndentW, FArrowW: Integer;
    FRepeatTimer: TTimer;
    FClosing: Boolean;
    FAnchorRight, FAnchorY: Integer;
    FOnClosed: TNotifyEvent;
    procedure Layout;
    procedure PlaceWindow;
    function RowAt(AY: Integer): Integer;
    function Selectable(ARow: Integer): Boolean;
    procedure Choose(ARow: Integer);
    procedure HandleRepeat(Sender: TObject);
    procedure HandleDeactivate(Sender: TObject);
    procedure DrawRow(ARow: Integer; const R: TRect);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseLeave; override;
  public
    constructor CreateMenu(AOwner: TComponent);
    destructor Destroy; override;
    { Shows ARoot's items with the window's right edge at ARightX (left
      of the panel; to its right if there is no room) and its first row
      at AY (screen pixels). }
    procedure ShowMenu(ARoot: TMenuItem; ARightX, AY: Integer);
    { The items changed (enabled, checked): drawn again. }
    procedure RefreshItems;
    { Hidden; OnClosed runs (once). }
    procedure CloseMenu;
    property OnClosed: TNotifyEvent read FOnClosed write FOnClosed;
  end;

implementation

const
  { Slow enough to stop on the place wanted (user, Day 27: 90 ms ran
    too fast). }
  RepeatFirstMs = 500;
  RepeatEveryMs = 280;

function MenuCaption(AItem: TMenuItem): string;
begin
  { "&&" is an "&" in a menu; a single "&" marks a key: dropped. }
  Result := StringReplace(AItem.Caption, '&&', #1, [rfReplaceAll]);
  Result := StringReplace(Result, '&', '', [rfReplaceAll]);
  Result := StringReplace(Result, #1, '&', [rfReplaceAll]);
end;

function IsSeparator(AItem: TMenuItem): Boolean;
begin
  Result := AItem.Caption = '-';
end;

{ TSlotMenuWindow }

constructor TSlotMenuWindow.CreateMenu(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  BorderStyle := bsNone;
  FormStyle := fsStayOnTop;
  ShowInTaskBar := stNever;
  KeyPreview := True;
  Color := clMenu;
  DoubleBuffered := True;
  Font.Assign(Screen.MenuFont);
  FHover := -1;
  FPressed := -1;
  FRepeatTimer := TTimer.Create(Self);
  FRepeatTimer.Enabled := False;
  FRepeatTimer.OnTimer := @HandleRepeat;
  OnDeactivate := @HandleDeactivate;
end;

destructor TSlotMenuWindow.Destroy;
begin
  FRepeatTimer.Enabled := False;
  inherited Destroy;
end;

procedure TSlotMenuWindow.ShowMenu(ARoot: TMenuItem; ARightX, AY: Integer);
begin
  FRoot := ARoot;
  FOpenSub := nil;
  FHover := -1;
  FPressed := -1;
  FScroll := 0;
  FClosing := False;
  FAnchorRight := ARightX;
  FAnchorY := AY;
  Canvas.Font.Assign(Font);
  FRowH := Canvas.TextHeight('Ag') + Scale96ToForm(8);
  FSepH := Scale96ToForm(7);
  FCheckW := Max(Scale96ToForm(22), FRowH);
  FIndentW := Scale96ToForm(16);
  FArrowW := Scale96ToForm(18);
  Layout;
  PlaceWindow;
  Show;
  SetFocus;
end;

procedure TSlotMenuWindow.RefreshItems;
begin
  Layout;
  Invalidate;
end;

procedure TSlotMenuWindow.Layout;
var
  I, J, Y, W, MaxW: Integer;

  procedure AddRow(AItem: TMenuItem; ALevel: Integer);
  var
    TW: Integer;
  begin
    SetLength(FRows, Length(FRows) + 1);
    FRows[High(FRows)].Item := AItem;
    FRows[High(FRows)].Level := ALevel;
    FRows[High(FRows)].Top := Y;
    if IsSeparator(AItem) then
      FRows[High(FRows)].Height := FSepH
    else
      FRows[High(FRows)].Height := FRowH;
    Inc(Y, FRows[High(FRows)].Height);
    if not IsSeparator(AItem) then
    begin
      if AItem.Tag = SlotMenuStrongTag then
        Canvas.Font.Style := [fsBold];
      TW := FCheckW + ALevel * FIndentW + Canvas.TextWidth(MenuCaption(AItem)) + FArrowW
        + Scale96ToForm(12);
      Canvas.Font.Style := [];
      MaxW := Max(MaxW, TW);
    end;
  end;

begin
  FRows := nil;
  if FRoot = nil then
    Exit;
  Canvas.Font.Assign(Font);
  Y := 0;
  MaxW := Scale96ToForm(160);
  for I := 0 to FRoot.Count - 1 do
  begin
    if not FRoot.Items[I].Visible then
      Continue;
    AddRow(FRoot.Items[I], 0);
    if (FRoot.Items[I] = FOpenSub) then
      for J := 0 to FOpenSub.Count - 1 do
        if FOpenSub.Items[J].Visible then
          AddRow(FOpenSub.Items[J], 1);
  end;
  FListH := Y;
  W := Min(MaxW, Scale96ToForm(560));
  if Width <> W + 2 then
    Width := W + 2;
end;

procedure TSlotMenuWindow.PlaceWindow;
var
  Work: TRect;
  H, L, T: Integer;
begin
  Work := Screen.MonitorFromPoint(Point(FAnchorRight, FAnchorY)).WorkareaRect;
  H := Min(FListH + 2, Work.Height);
  L := FAnchorRight - Width;
  if L < Work.Left then
    L := FAnchorRight;          { no room on the left: to the right }
  L := EnsureRange(L, Work.Left, Max(Work.Left, Work.Right - Width));
  T := EnsureRange(FAnchorY, Work.Top, Max(Work.Top, Work.Bottom - H));
  SetBounds(L, T, Width, H);
  FScroll := EnsureRange(FScroll, 0, Max(0, FListH + 2 - H));
end;

function TSlotMenuWindow.RowAt(AY: Integer): Integer;
var
  I, Y: Integer;
begin
  Result := -1;
  Y := AY - 1 + FScroll;
  for I := 0 to High(FRows) do
    if (Y >= FRows[I].Top) and (Y < FRows[I].Top + FRows[I].Height) then
      Exit(I);
end;

function TSlotMenuWindow.Selectable(ARow: Integer): Boolean;
begin
  Result := (ARow >= 0) and (ARow <= High(FRows)) and not IsSeparator(FRows[ARow].Item)
    and FRows[ARow].Item.Enabled;
end;

procedure TSlotMenuWindow.DrawRow(ARow: Integer; const R: TRect);
var
  Item: TMenuItem;
  X, CX, CY, S: Integer;
  TextCol: TColor;
  Pic: TBitmap;
begin
  Item := FRows[ARow].Item;
  if IsSeparator(Item) then
  begin
    Canvas.Pen.Color := clBtnShadow;
    Canvas.Line(R.Left + FCheckW div 2, (R.Top + R.Bottom) div 2,
      R.Right - FCheckW div 2, (R.Top + R.Bottom) div 2);
    Exit;
  end;
  X := R.Left + FRows[ARow].Level * FIndentW;
  if (ARow = FHover) and Item.Enabled then
  begin
    Canvas.Brush.Color := clHighlight;
    Canvas.FillRect(R);
    TextCol := clHighlightText;
  end
  else if Item.Enabled then
    TextCol := clMenuText
  else
    TextCol := clGrayText;
  { The tick, the dot, or the item's picture. }
  CX := X + FCheckW div 2;
  CY := (R.Top + R.Bottom) div 2;
  S := Max(3, FRowH div 6);
  Pic := nil;
  if (not Item.Bitmap.Empty) then
    Pic := Item.Bitmap;
  if Pic <> nil then
    Canvas.Draw(CX - Pic.Width div 2, CY - Pic.Height div 2, Pic);
  if Item.Checked then
  begin
    Canvas.Pen.Color := TextCol;
    Canvas.Brush.Color := TextCol;
    if Item.RadioItem then
    begin
      if Pic <> nil then
        Canvas.Frame(Rect(CX - Pic.Width div 2 - 2, CY - Pic.Height div 2 - 2,
          CX + Pic.Width div 2 + 2, CY + Pic.Height div 2 + 2))
      else
        Canvas.Ellipse(CX - S, CY - S, CX + S, CY + S);
    end
    else
    begin
      Canvas.Pen.Width := Max(2, S div 2);
      Canvas.Line(CX - S - 1, CY, CX - 1, CY + S);
      Canvas.Line(CX - 1, CY + S, CX + S + 2, CY - S - 1);
      Canvas.Pen.Width := 1;
    end;
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := TextCol;
  if Item.Tag = SlotMenuStrongTag then
  begin
    Canvas.Font.Style := [fsBold];
    if (ARow <> FHover) and Item.Enabled then
      Canvas.Font.Color := $006400;     { deep green }
  end;
  Canvas.TextOut(X + FCheckW, R.Top + (R.Height - Canvas.TextHeight('Ag')) div 2, MenuCaption(Item));
  Canvas.Font.Style := [];
  { Sub-items: an arrow, pointing down while open. }
  if Item.Count > 0 then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := TextCol;
    Canvas.Pen.Color := TextCol;
    CX := R.Right - FArrowW div 2 - 2;
    S := Max(3, FRowH div 6);
    if Item = FOpenSub then
      Canvas.Polygon([Point(CX - S, CY - S div 2), Point(CX + S, CY - S div 2), Point(CX, CY + S)])
    else
      Canvas.Polygon([Point(CX - S div 2, CY - S), Point(CX - S div 2, CY + S), Point(CX + S, CY)]);
  end;
  Canvas.Brush.Style := bsSolid;
end;

procedure TSlotMenuWindow.Paint;
var
  I: Integer;
  R: TRect;
begin
  Canvas.Font.Assign(Font);
  Canvas.Brush.Color := clMenu;
  Canvas.FillRect(ClientRect);
  for I := 0 to High(FRows) do
  begin
    R := Rect(1, 1 + FRows[I].Top - FScroll, ClientWidth - 1,
      1 + FRows[I].Top - FScroll + FRows[I].Height);
    if (R.Bottom < 0) or (R.Top > ClientHeight) then
      Continue;
    DrawRow(I, R);
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := clBtnShadow;
  Canvas.Rectangle(0, 0, ClientWidth, ClientHeight);
  Canvas.Brush.Style := bsSolid;
end;

procedure TSlotMenuWindow.CloseMenu;
begin
  if FClosing then
    Exit;
  FClosing := True;
  FRepeatTimer.Enabled := False;
  Hide;
  if Assigned(FOnClosed) then
    FOnClosed(Self);
end;

{ An item: a sub-menu opens / closes; a repeating item runs and the
  window stays; any other closes the window first, then runs (it may
  open a dialog). }
procedure TSlotMenuWindow.Choose(ARow: Integer);
var
  Item: TMenuItem;
begin
  if not Selectable(ARow) then
    Exit;
  Item := FRows[ARow].Item;
  if Item.Count > 0 then
  begin
    if FOpenSub = Item then
      FOpenSub := nil
    else
      FOpenSub := Item;
    Layout;
    PlaceWindow;
    Invalidate;
    Exit;
  end;
  if Item.Hint = SlotMenuRepeatHint then
  begin
    Item.Click;
    RefreshItems;
    Exit;
  end;
  CloseMenu;
  Item.Click;
end;

procedure TSlotMenuWindow.HandleRepeat(Sender: TObject);
begin
  FRepeatTimer.Interval := RepeatEveryMs;
  if (FPressed < 0) or (FPressed <> FHover) or not Selectable(FPressed) then
    Exit;                       { pressed, but the mouse is off the row: waits }
  FRows[FPressed].Item.Click;
  RefreshItems;
end;

procedure TSlotMenuWindow.HandleDeactivate(Sender: TObject);
begin
  CloseMenu;
end;

procedure TSlotMenuWindow.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Row: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  Row := RowAt(Y);
  FHover := Row;
  if Selectable(Row) and (FRows[Row].Item.Hint = SlotMenuRepeatHint)
    and (FRows[Row].Item.Count = 0) then
  begin
    { Runs now, and again while held. }
    FPressed := Row;
    FRows[Row].Item.Click;
    RefreshItems;
    FRepeatTimer.Interval := RepeatFirstMs;
    FRepeatTimer.Enabled := True;
  end
  else
    FPressed := -1;
end;

procedure TSlotMenuWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Row: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  Row := RowAt(Y);
  if Row <> FHover then
  begin
    FHover := Row;
    Invalidate;
  end;
end;

procedure TSlotMenuWindow.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Row, WasPressed: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  FRepeatTimer.Enabled := False;
  WasPressed := FPressed;
  FPressed := -1;
  if WasPressed >= 0 then
    Exit;                       { a repeating item: it already ran }
  Row := RowAt(Y);
  if (X >= 0) and (X < ClientWidth) then
    Choose(Row);
end;

procedure TSlotMenuWindow.MouseLeave;
begin
  inherited MouseLeave;
  if FPressed < 0 then
  begin
    FHover := -1;
    Invalidate;
  end;
end;

function TSlotMenuWindow.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  Result := True;
  FScroll := EnsureRange(FScroll - Sign(WheelDelta) * FRowH * 3, 0,
    Max(0, FListH + 2 - ClientHeight));
  Invalidate;
end;

procedure TSlotMenuWindow.KeyDown(var Key: Word; Shift: TShiftState);
var
  Row, Tries: Integer;
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_ESCAPE:
      CloseMenu;
    VK_UP, VK_DOWN:
      begin
        Row := FHover;
        Tries := Length(FRows);
        repeat
          if Key = VK_DOWN then
            Row := (Row + 1 + Length(FRows)) mod Max(1, Length(FRows))
          else
            Row := (Row - 1 + Length(FRows)) mod Max(1, Length(FRows));
          Dec(Tries);
        until Selectable(Row) or (Tries <= 0);
        FHover := Row;
        Invalidate;
      end;
    VK_RETURN, VK_SPACE:
      Choose(FHover);
  else
    Exit;
  end;
  Key := 0;
end;

end.
