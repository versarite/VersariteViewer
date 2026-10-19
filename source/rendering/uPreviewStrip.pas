unit uPreviewStrip;

{
  Unit: uPreviewStrip

  Purpose
  -------
  The scan bar (Day 27, testers, after Hamana's quick-view bar; the
  user: "a type of progress bar, just thicker and transparent"): a bar
  at the top of the view, in the middle, half the view wide, that stands
  for the folder's images 1 .. n from left to right. The mouse over it
  shows the image at that place as a large thumbnail under the bar (at
  50 % of the bar: about the middle image), so a time lapse or a series
  is scanned in a moment. A click opens the image. An image not made yet
  shows black with "754 / 1005" (the user's wish; Hamana: "printing").
  Opened by the mouse resting at the top edge or by the command
  TogglePreview; it closes 1 s after the mouse has left it.

  Owns
  ----
  - FBitmap: the bar and the preview under it (drawn by the renderers
    at Left, Top; transparent outside them).
  - FThumbs: the thumbnails it was given (file name -> TBGRABitmap,
    nil = could not be read), at most StripMaxThumbs; the ones farthest
    from the image under the mouse go first.

  Knows
  -----
  - Nothing of files or threads: TMView gives it the folder's files,
    the current one and the thumbnails, and asks which files it would
    like (WantedFiles: the one under the mouse first, then its
    neighbours).

  Responsibilities
  ----------------
  - The bar: the part up to the current image lighter (a progress bar),
    the current image's place yellow, the place under the mouse white,
    "18 / 34" in it.
  - Under the mouse: the image's index by its place on the bar; the
    wheel steps one image back / on from there (fine steps where a long
    list has several images per pixel). The preview stays while the
    mouse moves down onto it (a click there opens it too).
  - Closing: NoteMouse (every mouse move over the view) and Tick (the
    viewer's timer): 1 s (StripCloseDelayMs) after the mouse left it.
    Opened by the command with the mouse elsewhere: it waits until the
    mouse has been over it once. Pinned (opened from the right-click
    menu or a key, 1.1, user): it stays until closed the same way or
    with Esc.

  Does NOT
  --------
  - Read the disk or make thumbnails (uFolderThumbs, through TMView).

  Threads
  -------
  UI thread only.

  Uses (MView units)
  ------------------
  None.
  Libraries:      Classes, SysUtils, Math, Types, Graphics, BGRABitmap,
                  BGRABitmapTypes

  Used by
  -------
  uMView
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  Math,
  Types,
  Graphics,
  BGRABitmap,
  BGRABitmapTypes;

const
  StripCloseDelayMs = 1000;
  StripMaxThumbs = 400;
  { The name under the preview scrolls (when longer than the preview is
    wide) after the mouse has rested this long, at this speed. }
  MarqueeDelayMs = 600;
  MarqueePxPerSec = 45;

type

  TPreviewStrip = class(TObject)
  private
    FBitmap: TBGRABitmap;
    FVersion: Cardinal;
    FDirty: Boolean;
    FPinned: Boolean;
    FVisible: Boolean;
    FViewW, FViewH: Integer;
    FScale: Double;
    FBarW, FBarH, FThumbSize, FPad, FTextH, FHeight: Integer;
    FLeft: Integer;              { the bar's left edge in the view }
    FFiles: array of string;
    FCurrent: Integer;
    FHover: Integer;             { the image under the mouse; -1 = none }
    FHoverX: Integer;            { where the preview hangs (view x) }
    FThumbs: TStringList;        { sorted, no case; Objects: TBGRABitmap or nil }
    FMouseInside: Boolean;
    FWasInside: Boolean;
    FLeftAtMs: Double;
    FOutline: TBGRAPixel;
    FFontName: string;           { the info line's font ('' = standard) }
    FFontPx: Integer;            { ... and its height in pixels }
    FSteadySinceMs: Double;      { the image under the mouse since; 0 = to be set }
    FMarquee: Integer;           { how far the name has scrolled (px) }
    FMarqueeW: Integer;          { the name's width (last drawn); 0 = fits }
    procedure Layout;
    procedure PreviewSize(out AW, AH: Integer);
    procedure SetOutline(AValue: TBGRAPixel);
    function BarRect: TRect;
    function PreviewRect: TRect;
    function IndexAtX(AX: Integer): Integer;
    function XOfIndex(AIndex: Integer): Integer;
    procedure Redraw;
    procedure TrimThumbs(AKeep: Integer);
  public
    constructor Create;
    destructor Destroy; override;

    procedure SetViewSize(AWidth, AHeight: Integer; AScale: Double);
    { The folder's files and the current one's index (-1 = none). }
    procedure SetItems(const AFiles: array of string; ACurrent: Integer);
    { Only the current one changed (the same list). }
    procedure SetCurrent(AIndex: Integer);
    { ABitmap becomes the strip's (nil = could not be read). }
    procedure SetThumb(const AFileName: string; ABitmap: TBGRABitmap);
    { The one under the mouse first, then a few on either side; without
      those it has. Empty while the mouse is not over the bar. }
    function WantedFiles: TStringArray;

    { APinned: it stays when the mouse leaves (the menu / a key). }
    procedure Show(AMouseInside: Boolean; APinned: Boolean = False);
    procedure Hide;
    { The bar, or the preview under it while one is shown. }
    function Contains(AX, AY: Integer): Boolean;
    { The image at the point (the bar, or the preview), -1 = none. }
    function HitTest(AX, AY: Integer): Integer;
    { Every mouse move over the view; True = to be drawn again (the
      image under the mouse changed). }
    function NoteMouse(AX, AY: Integer; ANowMs: Double): Boolean;
    procedure MouseGone(ANowMs: Double);
    { Closes it 1 s after the mouse left, scrolls the name; True = to
      be drawn again (or closed). }
    function Tick(ANowMs: Double): Boolean;
    { The wheel over it: one image back (+) / on (-) from the one under
      the mouse. True = changed. }
    function Scroll(ANotches: Integer): Boolean;
    function Bitmap: TBGRABitmap;
    function FileAt(AIndex: Integer): string;

    property Visible: Boolean read FVisible;
    { Stays when the mouse leaves (until Hide); may be set while shown. }
    property Pinned: Boolean read FPinned write FPinned;
    property Version: Cardinal read FVersion;
    property ThumbSize: Integer read FThumbSize;
    property Hover: Integer read FHover;
    { The bar's outline, its marks and text: the info line's and the
      on-screen messages' colour ([View] OverlayColor; user, Day 27). }
    property OutlineColor: TBGRAPixel read FOutline write SetOutline;
    { The info line's font (name, height in px) for the name under the
      preview (user, Day 27: "in status bar font"). }
    procedure SetTextFont(const AName: string; APixels: Integer);
    { Where the renderers draw Bitmap (view pixels). }
    property Left: Integer read FLeft;
    function Top: Integer;
  end;

implementation

uses
  uTypes;

function FitStripText(ABitmap: TBGRABitmap; const AText: string; AWidth: Integer): string;
var
  N: Integer;
begin
  Result := AText;
  if ABitmap.TextSize(Result).cx <= AWidth then
    Exit;
  N := Length(AText);
  while (N > 1) and (ABitmap.TextSize(Copy(AText, 1, N) + '...').cx > AWidth) do
    Dec(N);
  Result := Copy(AText, 1, N) + '...';
end;

constructor TPreviewStrip.Create;
begin
  inherited Create;
  FThumbs := TStringList.Create;
  FThumbs.Sorted := True;
  FThumbs.CaseSensitive := False;
  FThumbs.Duplicates := dupIgnore;
  FScale := 1;
  FCurrent := -1;
  FHover := -1;
  FOutline := BGRA(255, 255, 255, 255);
  FFontPx := 13;
  Layout;
end;

procedure TPreviewStrip.SetTextFont(const AName: string; APixels: Integer);
begin
  APixels := Max(9, APixels);
  if (AName = FFontName) and (APixels = FFontPx) then
    Exit;
  FFontName := AName;
  FFontPx := APixels;
  Layout;
  FDirty := True;
end;

procedure TPreviewStrip.SetOutline(AValue: TBGRAPixel);
begin
  if (AValue.red = FOutline.red) and (AValue.green = FOutline.green)
    and (AValue.blue = FOutline.blue) then
    Exit;
  FOutline := AValue;
  FDirty := True;
end;

destructor TPreviewStrip.Destroy;
var
  I: Integer;
begin
  for I := 0 to FThumbs.Count - 1 do
    FThumbs.Objects[I].Free;
  FThumbs.Free;
  FBitmap.Free;
  inherited Destroy;
end;

{ The bar: half the view, in the middle, at the top; the preview hangs
  under it (the bitmap is as wide as the view, so the preview can stand
  at the bar's ends too). }
procedure TPreviewStrip.Layout;
begin
  FPad := Max(4, Round(6 * FScale));
  FBarH := Max(16, Round(24 * FScale));
  { 165: three quarters of the first 220 (user, Day 27). }
  FThumbSize := Max(72, Round(165 * FScale));
  FTextH := FFontPx + Max(4, Round(6 * FScale));
  FBarW := Max(100, FViewW div 2);
  FLeft := 0;
  FHeight := FPad + FBarH + FPad + FThumbSize + FTextH + FPad;
end;

function TPreviewStrip.Top: Integer;
begin
  Result := 0;
end;

function TPreviewStrip.BarRect: TRect;
var
  X: Integer;
begin
  X := (FViewW - FBarW) div 2;
  Result := Rect(X, FPad, X + FBarW, FPad + FBarH);
end;

{ The picture's size: the thumbnail's own (no frame around it, user,
  Day 27); not made yet: a 4:3 box. }
procedure TPreviewStrip.PreviewSize(out AW, AH: Integer);
var
  Idx: Integer;
  Thumb: TBGRABitmap;
begin
  AW := FThumbSize;
  AH := FThumbSize * 3 div 4;
  if (FHover < 0) or (FHover > High(FFiles)) then
    Exit;
  if FThumbs.Find(FFiles[FHover], Idx) then
  begin
    Thumb := TBGRABitmap(FThumbs.Objects[Idx]);
    if Thumb <> nil then
    begin
      AW := Max(Round(48 * FScale), Thumb.Width);
      AH := Thumb.Height;
    end;
  end;
end;

{ The preview under the bar, centred on the place under the mouse (kept
  inside the view): the picture, then a line for its name. }
function TPreviewStrip.PreviewRect: TRect;
var
  X, W, H: Integer;
begin
  PreviewSize(W, H);
  X := EnsureRange(FHoverX - W div 2, 0, Max(0, FViewW - W));
  Result := Rect(X, BarRect.Bottom + FPad, X + W, BarRect.Bottom + FPad + H + FTextH);
end;

function TPreviewStrip.IndexAtX(AX: Integer): Integer;
var
  R: TRect;
begin
  Result := -1;
  if Length(FFiles) = 0 then
    Exit;
  R := BarRect;
  Result := EnsureRange(Trunc((AX - R.Left) / Max(1, R.Width) * Length(FFiles)), 0, High(FFiles));
end;

function TPreviewStrip.XOfIndex(AIndex: Integer): Integer;
var
  R: TRect;
begin
  R := BarRect;
  if Length(FFiles) = 0 then
    Exit(R.Left);
  Result := R.Left + Round((AIndex + 0.5) / Length(FFiles) * R.Width);
end;

procedure TPreviewStrip.SetViewSize(AWidth, AHeight: Integer; AScale: Double);
begin
  if (AWidth = FViewW) and (AHeight = FViewH) and (AScale = FScale) then
    Exit;
  FViewW := AWidth;
  FViewH := AHeight;
  FScale := AScale;
  Layout;
  FDirty := True;
end;

procedure TPreviewStrip.SetItems(const AFiles: array of string; ACurrent: Integer);
var
  I: Integer;
  Same: Boolean;
begin
  Same := Length(AFiles) = Length(FFiles);
  if Same then
    for I := 0 to High(AFiles) do
      if AFiles[I] <> FFiles[I] then
      begin
        Same := False;
        Break;
      end;
  if not Same then
  begin
    SetLength(FFiles, Length(AFiles));
    for I := 0 to High(AFiles) do
      FFiles[I] := AFiles[I];
    FHover := -1;
    FDirty := True;
  end;
  SetCurrent(ACurrent);
end;

procedure TPreviewStrip.SetCurrent(AIndex: Integer);
begin
  if AIndex = FCurrent then
    Exit;
  FCurrent := AIndex;
  FDirty := True;
end;

procedure TPreviewStrip.TrimThumbs(AKeep: Integer);
var
  Lo, Hi, I, Idx, Mid: Integer;
  Keep: TStringList;
begin
  if FThumbs.Count <= AKeep then
    Exit;
  Keep := TStringList.Create;
  try
    Keep.Sorted := True;
    Keep.CaseSensitive := False;
    Mid := FHover;
    if Mid < 0 then
      Mid := Max(0, FCurrent);
    Lo := Max(0, Mid - AKeep div 2);
    Hi := Min(High(FFiles), Lo + AKeep - 1);
    for I := Lo to Hi do
      Keep.Add(FFiles[I]);
    for I := FThumbs.Count - 1 downto 0 do
      if not Keep.Find(FThumbs[I], Idx) then
      begin
        FThumbs.Objects[I].Free;
        FThumbs.Delete(I);
      end;
  finally
    Keep.Free;
  end;
end;

procedure TPreviewStrip.SetThumb(const AFileName: string; ABitmap: TBGRABitmap);
var
  Idx: Integer;
begin
  if FThumbs.Find(AFileName, Idx) then
  begin
    FThumbs.Objects[Idx].Free;
    FThumbs.Objects[Idx] := ABitmap;
  end
  else
    FThumbs.AddObject(AFileName, ABitmap);
  if FThumbs.Count > StripMaxThumbs then
    TrimThumbs(StripMaxThumbs * 3 div 4);
  { Drawn again only if it is the one shown. }
  if (FHover >= 0) and SameText(FFiles[FHover], AFileName) then
    FDirty := True;
end;

function TPreviewStrip.WantedFiles: TStringArray;
var
  Count, Idx, I: Integer;

  procedure Want(AIndex: Integer);
  begin
    if (AIndex < 0) or (AIndex > High(FFiles)) then
      Exit;
    if FThumbs.Find(FFiles[AIndex], Idx) then
      Exit;
    SetLength(Result, Count + 1);
    Result[Count] := FFiles[AIndex];
    Inc(Count);
  end;

begin
  Result := nil;
  Count := 0;
  if (FHover < 0) or not FVisible then
    Exit;
  Want(FHover);
  for I := 1 to 3 do
  begin
    Want(FHover + I);
    Want(FHover - I);
  end;
end;

procedure TPreviewStrip.Show(AMouseInside: Boolean; APinned: Boolean);
begin
  if FVisible then
    Exit;
  FVisible := True;
  FPinned := APinned;
  FMouseInside := AMouseInside;
  FWasInside := AMouseInside;
  FLeftAtMs := 0;
  FHover := -1;
  FDirty := True;
end;

procedure TPreviewStrip.Hide;
begin
  if not FVisible then
    Exit;
  FVisible := False;
  FPinned := False;
  FHover := -1;
  FDirty := True;
end;

function TPreviewStrip.Contains(AX, AY: Integer): Boolean;
var
  R: TRect;
begin
  Result := False;
  if not FVisible then
    Exit;
  { The bar, with a little room around it (it is easy to slip off). }
  R := BarRect;
  InflateRect(R, FPad, FPad);
  R.Top := 0;
  if PtInRect(R, Point(AX, AY)) then
    Exit(True);
  if FHover >= 0 then
    Result := PtInRect(PreviewRect, Point(AX, AY));
end;

function TPreviewStrip.HitTest(AX, AY: Integer): Integer;
var
  R: TRect;
begin
  Result := -1;
  if not FVisible then
    Exit;
  R := BarRect;
  InflateRect(R, FPad, FPad);
  R.Top := 0;
  if PtInRect(R, Point(AX, AY)) then
    Exit(IndexAtX(AX));
  if (FHover >= 0) and PtInRect(PreviewRect, Point(AX, AY)) then
    Result := FHover;
end;

function TPreviewStrip.NoteMouse(AX, AY: Integer; ANowMs: Double): Boolean;
var
  Inside, OnBar: Boolean;
  NewHover: Integer;
  R: TRect;
begin
  Result := False;
  if not FVisible then
    Exit;
  Inside := Contains(AX, AY);
  if Inside then
  begin
    FWasInside := True;
    FLeftAtMs := 0;
  end
  else if FMouseInside or (FWasInside and (FLeftAtMs = 0)) then
    FLeftAtMs := Max(1.0, ANowMs);
  FMouseInside := Inside;
  { Over the bar: the image there; over the preview: it stays. }
  R := BarRect;
  InflateRect(R, FPad, FPad);
  R.Top := 0;
  OnBar := PtInRect(R, Point(AX, AY));
  if OnBar then
  begin
    NewHover := IndexAtX(AX);
    if (NewHover <> FHover) or (AX <> FHoverX) then
    begin
      if NewHover <> FHover then
      begin
        FSteadySinceMs := ANowMs;
        FMarquee := 0;
      end;
      FHover := NewHover;
      FHoverX := EnsureRange(AX, BarRect.Left, BarRect.Right);
      FDirty := True;
      Result := True;
    end;
  end
  else if not Inside and (FHover >= 0) then
  begin
    FHover := -1;
    FDirty := True;
    Result := True;
  end;
end;

procedure TPreviewStrip.MouseGone(ANowMs: Double);
begin
  if FVisible and FMouseInside then
  begin
    FMouseInside := False;
    FLeftAtMs := Max(1.0, ANowMs);
  end;
  if FHover >= 0 then
  begin
    FHover := -1;
    FDirty := True;
  end;
end;

function TPreviewStrip.Tick(ANowMs: Double): Boolean;
var
  Offset: Integer;
begin
  Result := False;
  if FVisible and not FPinned and FWasInside and not FMouseInside and (FLeftAtMs > 0)
    and (ANowMs - FLeftAtMs >= StripCloseDelayMs) then
  begin
    Hide;
    Exit(True);
  end;
  { The name scrolls, round and round, while the mouse rests. }
  if not FVisible or (FHover < 0) then
    Exit;
  if FSteadySinceMs <= 0 then
    FSteadySinceMs := ANowMs;
  if (FMarqueeW <= 0) or (ANowMs - FSteadySinceMs < MarqueeDelayMs) then
    Exit;
  Offset := Round((ANowMs - FSteadySinceMs - MarqueeDelayMs) / 1000 * MarqueePxPerSec * FScale)
    mod (FMarqueeW + 3 * FTextH);
  if Offset <> FMarquee then
  begin
    FMarquee := Offset;
    FDirty := True;
    Result := True;
  end;
end;

function TPreviewStrip.Scroll(ANotches: Integer): Boolean;
var
  Old: Integer;
begin
  Result := False;
  if (FHover < 0) or (ANotches = 0) then
    Exit;
  Old := FHover;
  FHover := EnsureRange(FHover - ANotches, 0, High(FFiles));
  Result := FHover <> Old;
  if Result then
  begin
    FHoverX := XOfIndex(FHover);
    FSteadySinceMs := 0;          { from the next Tick }
    FMarquee := 0;
    FDirty := True;
  end;
end;

function TPreviewStrip.FileAt(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex <= High(FFiles)) then
    Result := FFiles[AIndex]
  else
    Result := '';
end;

procedure TPreviewStrip.Redraw;
var
  R, P, Inner: TRect;
  X, Idx, TW, TH: Integer;
  Thumb, TextBmp: TBGRABitmap;
  Have: Boolean;
  Line: string;
  TS: TSize;
  Col: TBGRAPixel;
begin
  FDirty := False;
  Inc(FVersion);
  if (FViewW <= 0) or not FVisible then
    Exit;
  if FBitmap = nil then
    FBitmap := TBGRABitmap.Create(FViewW, FHeight)
  else
    FBitmap.SetSize(FViewW, FHeight);
  FBitmap.FontQuality := fqSystem;
  FBitmap.Fill(BGRAPixelTransparent);

  { The bar: dark and transparent, lighter up to the current image. }
  R := BarRect;
  FBitmap.FillRoundRectAntialias(R.Left, R.Top, R.Right, R.Bottom, FBarH / 3, FBarH / 3,
    BGRA(20, 20, 26, PanelAlpha(150)));
  if (FCurrent >= 0) and (Length(FFiles) > 0) then
  begin
    X := XOfIndex(FCurrent);
    FBitmap.FillRoundRectAntialias(R.Left, R.Top, X, R.Bottom, FBarH / 3, FBarH / 3,
      BGRA(200, 200, 210, 70));
    FBitmap.FillRectAntialias(X - 1.5, R.Top, X + 1.5, R.Bottom, BGRA(255, 210, 60, 255));
  end;
  FBitmap.RoundRectAntialias(R.Left, R.Top, R.Right, R.Bottom, FBarH / 3, FBarH / 3,
    BGRA(FOutline.red, FOutline.green, FOutline.blue, 230), Max(1.5, 1.5 * FScale));
  if FHover >= 0 then
    FBitmap.FillRectAntialias(FHoverX - 1, R.Top - 2, FHoverX + 1, R.Bottom + 2,
      BGRA(FOutline.red, FOutline.green, FOutline.blue, 240));
  { "18 / 34" in the bar, at its right end. }
  if FFontName <> '' then
    FBitmap.FontName := FFontName;
  FBitmap.FontHeight := Max(10, Round(FBarH * 0.6));
  if FCurrent >= 0 then
    Line := Format('%d / %d', [FCurrent + 1, Length(FFiles)])
  else
    Line := Format('%d images', [Length(FFiles)]);
  TS := FBitmap.TextSize(Line);
  FBitmap.TextOut(R.Right - TS.cx - FPad, R.Top + (R.Height - TS.cy) div 2, Line,
    BGRA(FOutline.red, FOutline.green, FOutline.blue, 230));

  { The preview of the image under the mouse: the picture without a
    frame, its name under it on a solid line. }
  FMarqueeW := 0;
  if (FHover < 0) or (FHover > High(FFiles)) then
    Exit;
  P := PreviewRect;
  Inner := Rect(P.Left, P.Top, P.Right, P.Bottom - FTextH);
  Thumb := nil;
  Have := FThumbs.Find(FFiles[FHover], Idx);
  if Have then
    Thumb := TBGRABitmap(FThumbs.Objects[Idx]);
  if Thumb <> nil then
  begin
    FBitmap.FillRect(Inner, BGRABlack, dmSet);
    FBitmap.PutImage(Inner.Left + (Inner.Width - Thumb.Width) div 2, Inner.Top, Thumb, dmSet);
  end
  else
  begin
    { Not made yet (or unreadable): black, with where it is. }
    FBitmap.FillRect(Inner, BGRABlack, dmSet);
    if Have then
      Line := 'cannot be shown'
    else
      Line := Format('%d / %d', [FHover + 1, Length(FFiles)]);
    if FFontName <> '' then
      FBitmap.FontName := FFontName;
    FBitmap.FontHeight := Max(12, Inner.Height div 7);
    TS := FBitmap.TextSize(Line);
    FBitmap.TextOut(Inner.Left + (Inner.Width - TS.cx) div 2, Inner.Top + (Inner.Height - TS.cy) div 2,
      Line, BGRA(200, 200, 200, 255));
  end;
  if FHover = FCurrent then
    FBitmap.RectangleAntialias(Inner.Left + 0.5, Inner.Top + 0.5, Inner.Right - 1.5,
      Inner.Bottom - 1.5, BGRA(255, 210, 60, 255), Max(2.0, 2 * FScale));
  { The name, in the info line's font and colour; longer than the
    preview is wide: it scrolls round (Tick). }
  Line := Format('%d / %d   %s', [FHover + 1, Length(FFiles), ExtractFileName(FFiles[FHover])]);
  TextBmp := TBGRABitmap.Create(P.Width, FTextH, BGRA(12, 12, 16, 255));
  try
    TextBmp.FontQuality := fqSystem;
    if FFontName <> '' then
      TextBmp.FontName := FFontName;
    TextBmp.FontHeight := FFontPx;
    TS := TextBmp.TextSize(Line);
    Col := BGRA(FOutline.red, FOutline.green, FOutline.blue, 255);
    if TS.cx <= P.Width - 2 * FPad then
      TextBmp.TextOut((P.Width - TS.cx) div 2, (FTextH - TS.cy) div 2, Line, Col)
    else
    begin
      FMarqueeW := TS.cx;
      X := FPad - FMarquee;
      TextBmp.TextOut(X, (FTextH - TS.cy) div 2, Line, Col);
      TextBmp.TextOut(X + TS.cx + 3 * FTextH, (FTextH - TS.cy) div 2, Line, Col);
    end;
    FBitmap.PutImage(P.Left, P.Bottom - FTextH, TextBmp, dmSet);
  finally
    TextBmp.Free;
  end;
end;

function TPreviewStrip.Bitmap: TBGRABitmap;
begin
  if not FVisible then
    Exit(nil);
  if FDirty or (FBitmap = nil) then
    Redraw;
  Result := FBitmap;
end;

end.
