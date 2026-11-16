unit uSvgExport;

{
  Unit: uSvgExport

  Purpose
  -------
  "Export figure (SVG) ..." (1.1; spec "Microscopy edition" §9c): the
  image as shown, with the measuring lines, the scale bar and the text
  labels as vectors and text, for Inkscape / Illustrator / CorelDRAW -
  where a label can still be moved, edited or removed.
  - The image: as "Apply filters to a copy" makes it (filters, mirror,
    turn; uExtensions' figure source, TMView), embedded as a lossless
    PNG (self-contained: a linked file breaks when files move).
  - Each edition layer that has something for this image (its
    SvgMarkup) as its own Inkscape layer ("Measurements", "Scale bar",
    "Labels"); all inside one layer "Figure", so scaling the figure keeps
    image and marks together. Illustrator / Corel see named groups.
  - The page: the image's pixels at 300 dpi (a sensible print size).
  - A note inside (<desc>): the pixel size of the figure's pixels, where
    it is from, the source image, the date - a figure can be traced back.
  - A reference line (1.1, user): with a scale, the embedded picture gets
    a thin black strip below the image with a white line of the scale
    bar's length (without a bar: a round length, about a fifth of the
    width) in its bottom left corner: from the very left edge, on the
    bottom edge (user, Day 27: no gap to either), so it is measured from
    the picture's corner; its length is in the note. It is part of the picture's
    pixels, so it stays right however the picture is resized later on
    its own (a vector bar only while scaled together with it); crop the
    strip off at the end. The marks' coordinates are unchanged (the
    strip is below).

  Does NOT
  --------
  - Change the image or the marks; write anything but the .svg chosen.

  Threads
  -------
  UI thread (the menu).

  Uses (MView units)
  ------------------
  implementation: uExtensions, uImageScale, uScaleBar, uSafeFile,
                  uEdition
  Libraries:      Classes, SysUtils, Math, Forms, Controls, Dialogs, LCLType,
                  base64, BGRABitmap

  Used by
  -------
  VersariteImageLab.lpr (its uses list)
}

{$mode ObjFPC}{$H+}

interface

{ The SVG text of a figure (for the test): APng the image's PNG bytes,
  AWidth x AHeight its pixels; ALayers: the layers' markup, ALayerNames
  their names; ADesc the note. }
function BuildFigureSvg(const APng: string; AWidth, AHeight: Integer; const ATitle, ADesc: string;
  const ALayerNames, ALayers: array of string): string;

implementation

uses
  Classes,
  SysUtils,
  Math,
  Forms,
  Controls,
  Dialogs,
  LCLType,
  base64,
  BGRABitmap,
  BGRABitmapTypes,
  uExtensions,
  uImageScale,
  uScaleBar,
  uSafeFile,
  uEdition;

const
  FigureDpi = 300;

{ The figure's µm per pixel (its own pixels: a quick view's are fewer);
  0 = no scale. }
function FigureUmPerPixel(const AImageName: string; const AMap: TBurnInMap): Double;
var
  Scale: TImageScale;
  FullW, FullH: Integer;
begin
  Result := 0;
  FullW := Max(1, Round(AMap.SourceWidth / Max(1e-9, AMap.ScaleX)));
  FullH := Max(1, Round(AMap.SourceHeight / Max(1e-9, AMap.ScaleY)));
  if ScaleFor(AImageName, FullW, FullH, Scale) then
    Result := (Scale.UmPerPixelX / Max(1e-9, AMap.ScaleX)
      + Scale.UmPerPixelY / Max(1e-9, AMap.ScaleY)) / 2;
end;

{ ABitmap with the reference strip below it (a new bitmap), or nil when
  it can't have one. The line only, no text (user: the strip is cropped
  off at the end; its length is in the figure's note): ALengthPx long,
  fractions kept (antialiased right end), in the strip's bottom left
  corner - from x = 0, its bottom on the picture's bottom edge (user,
  Day 27). The image's own pixels are not covered. }
function WithReferenceStrip(ABitmap: TBGRABitmap; ALengthPx: Double;
  out AStripH: Integer): TBGRABitmap;
var
  LineH, Y1: Double;
begin
  Result := nil;
  AStripH := 0;
  if (ALengthPx < 2) or (ALengthPx > ABitmap.Width) then
    Exit;
  AStripH := Max(6, Round(Min(ABitmap.Width, ABitmap.Height) / 120));
  { Whole pixels high, so the line's top and bottom are sharp. }
  LineH := Max(2, Round(AStripH / 3));
  Result := TBGRABitmap.Create(ABitmap.Width, ABitmap.Height + AStripH, BGRA(0, 0, 0, 255));
  Result.PutImage(0, 0, ABitmap, dmSet);
  Y1 := Result.Height;
  { Coordinates on pixel edges (not centres): the corner pixel is white,
    only the right end is partly covered. }
  Result.FillRectAntialias(0, Y1 - LineH, ALengthPx, Y1, BGRA(255, 255, 255, 255), False);
end;

function LayerId(const AName: string): string;
var
  I: Integer;
begin
  Result := 'layer-';
  for I := 1 to Length(AName) do
    if AName[I] in ['A'..'Z', 'a'..'z', '0'..'9'] then
      Result := Result + LowerCase(AName[I])
    else
      Result := Result + '-';
end;

function BuildFigureSvg(const APng: string; AWidth, AHeight: Integer; const ATitle, ADesc: string;
  const ALayerNames, ALayers: array of string): string;
var
  I: Integer;
  MmW, MmH: Double;
  Parts: TStringList;
begin
  MmW := AWidth / FigureDpi * 25.4;
  MmH := AHeight / FigureDpi * 25.4;
  Parts := TStringList.Create;
  try
    Parts.Add('<?xml version="1.0" encoding="UTF-8" standalone="no"?>');
    Parts.Add('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"');
    Parts.Add('     xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape"');
    Parts.Add('     version="1.1" width="' + SvgNum(MmW) + 'mm" height="' + SvgNum(MmH) + 'mm"');
    Parts.Add('     viewBox="0 0 ' + IntToStr(AWidth) + ' ' + IntToStr(AHeight) + '">');
    Parts.Add('<title>' + SvgEscape(ATitle) + '</title>');
    Parts.Add('<desc>' + SvgEscape(ADesc) + '</desc>');
    Parts.Add('<g inkscape:groupmode="layer" inkscape:label="Figure" id="layer-figure">');
    Parts.Add('<g inkscape:groupmode="layer" inkscape:label="Image" id="layer-image">');
    Parts.Add('<image x="0" y="0" width="' + IntToStr(AWidth) + '" height="' + IntToStr(AHeight)
      + '" preserveAspectRatio="none" xlink:href="data:image/png;base64,'
      + EncodeStringBase64(APng) + '"/>');
    Parts.Add('</g>');
    for I := 0 to Min(High(ALayerNames), High(ALayers)) do
      if ALayers[I] <> '' then
      begin
        Parts.Add('<g inkscape:groupmode="layer" inkscape:label="' + SvgEscape(ALayerNames[I])
          + '" id="' + LayerId(ALayerNames[I]) + '">');
        Parts.Add(TrimRight(ALayers[I]));
        Parts.Add('</g>');
      end;
    Parts.Add('</g>');
    Parts.Add('</svg>');
    Result := Parts.Text;
  finally
    Parts.Free;
  end;
end;

function PngBytes(ABitmap: TBGRABitmap): string;
var
  Stream: TStringStream;
begin
  Stream := TStringStream.Create('');
  try
    ABitmap.SaveToStreamAsPng(Stream);
    Result := Stream.DataString;
  finally
    Stream.Free;
  end;
end;

{ The note: what a figure pixel is in µm, from where, which image. }
function FigureNote(const AImageName: string; const AMap: TBurnInMap; AQuick: Boolean): string;
var
  Scale: TImageScale;
  FullW, FullH: Integer;
  UmX, UmY: Double;
  Source: string;
begin
  Result := 'Exported by ' + EditionTitle + ' on ' + FormatDateTime('yyyy-mm-dd hh:nn', Now)
    + LineEnding + 'Image: ' + AImageName;
  FullW := Max(1, Round(AMap.SourceWidth / Max(1e-9, AMap.ScaleX)));
  FullH := Max(1, Round(AMap.SourceHeight / Max(1e-9, AMap.ScaleY)));
  if ScaleFor(AImageName, FullW, FullH, Scale) then
  begin
    { The figure's pixels may be a quick view's (fewer): the same µm over
      fewer pixels. A turn keeps square pixels square. }
    UmX := Scale.UmPerPixelX / Max(1e-9, AMap.ScaleX);
    UmY := Scale.UmPerPixelY / Max(1e-9, AMap.ScaleY);
    Source := Scale.Source;
    if Source = '' then
      Source := 'the file''s metadata';
    if Abs(UmX - UmY) < 1e-9 then
      Result := Result + LineEnding + 'Pixel size: ' + FormatFloat('0.#####', UmX) + ' µm'
    else
      Result := Result + LineEnding + 'Pixel size: ' + FormatFloat('0.#####', UmX) + ' x '
        + FormatFloat('0.#####', UmY) + ' µm';
    Result := Result + ' (from ' + Source + ')';
  end
  else
    Result := Result + LineEnding + 'No scale (pixels only)';
  if AMap.Angle <> 0 then
    Result := Result + LineEnding + 'Turned by ' + FormatFloat('0.#', AMap.Angle) + '°';
  if AQuick then
    Result := Result + LineEnding + 'From the quick view (the full image was not loaded yet)';
end;

procedure ExportFigure(AViewer: TObject);
var
  Bmp: TBGRABitmap;
  Map: TBurnInMap;
  ImageName, SourceName, Folder, Error, FileName, Svg, Markup, Name: string;
  Quick: Boolean;
  Dialog: TSaveDialog;
  Names, Layers: array of string;
  I, N: Integer;
  Layer: TOverlayLayer;
  Strip: TBGRABitmap;
  UmPerPx, RefMicrons, RefX0, RefLen: Double;
  StripH: Integer;
begin
  if not MakeFigure(Bmp, Map, ImageName, SourceName, Folder, Error, Quick) then
  begin
    Application.MessageBox(PChar('No figure: ' + Error), 'Export figure (SVG)', MB_OK or MB_ICONWARNING);
    Exit;
  end;
  try
    Dialog := TSaveDialog.Create(nil);
    try
      Dialog.Title := 'Export figure (SVG)';
      Dialog.Filter := 'SVG figure (*.svg)|*.svg';
      Dialog.DefaultExt := 'svg';
      Dialog.InitialDir := Folder;
      Dialog.FileName := SourceName + '_figure.svg';
      Dialog.Options := Dialog.Options + [ofOverwritePrompt, ofPathMustExist];
      NoteMenuOpen(True);
      try
        if not Dialog.Execute then
          Exit;
      finally
        NoteMenuOpen(False);
      end;
      FileName := Dialog.FileName;
    finally
      Dialog.Free;
    end;

    { The layers' marks for this image, each its own layer. }
    Names := nil;
    Layers := nil;
    for I := 0 to OverlayLayerCount - 1 do
    begin
      Layer := OverlayLayer(I);
      if Layer = nil then
        Continue;
      try
        Name := Layer.SvgLayerName;
        if Name = '' then
          Continue;
        Markup := Layer.SvgMarkup(ImageName, Map);
      except
        Markup := '';     { a layer's fault costs its marks, not the figure }
      end;
      if Markup = '' then
        Continue;
      N := Length(Names);
      SetLength(Names, N + 1);
      SetLength(Layers, N + 1);
      Names[N] := Name;
      Layers[N] := Markup;
    end;

    Screen.Cursor := crHourGlass;
    Strip := nil;
    try
      { The reference line below the image (user; [ScaleBar]
        SvgReferenceBar, default on): the scale bar's length (in the
        bottom left corner, wherever the bar is); without a bar a round
        length about a fifth of the width. }
      if SvgReferenceBar then
      begin
        UmPerPx := FigureUmPerPixel(ImageName, Map);
        if not ScaleBarReference(ImageName, Map, RefX0, RefLen, RefMicrons) and (UmPerPx > 0) then
        begin
          RefMicrons := RoundScaleLength(Bmp.Width / 5 * UmPerPx);
          RefLen := RefMicrons / UmPerPx;
        end;
        if RefMicrons > 0 then
          Strip := WithReferenceStrip(Bmp, RefLen, StripH);
      end;
      if Strip <> nil then
        Svg := BuildFigureSvg(PngBytes(Strip), Strip.Width, Strip.Height, SourceName,
          FigureNote(ImageName, Map, Quick) + LineEnding + Format('Reference line: the bottom %d px '
          + 'of the picture are a strip with a white line of %s (%s px) in its bottom left corner '
          + '- it keeps the scale when the picture alone is resized; crop the strip off when done.',
          [StripH, ScaleBarText(RefMicrons), SvgNum(RefLen)]), Names, Layers)
      else
        Svg := BuildFigureSvg(PngBytes(Bmp), Bmp.Width, Bmp.Height, SourceName,
          FigureNote(ImageName, Map, Quick), Names, Layers);
    finally
      Strip.Free;
      Screen.Cursor := crDefault;
    end;
    if not WriteTextFileSafely(FileName, Svg, Error) then
    begin
      Application.MessageBox(PChar('The figure could not be written: ' + Error),
        'Export figure (SVG)', MB_OK or MB_ICONWARNING);
      Exit;
    end;
    if Length(Names) = 0 then
      ViewerNote('figure saved (the image only: nothing measured or labelled): ' + FileName, 8000)
    else
    begin
      Markup := '';
      for I := 0 to High(Names) do
      begin
        if I > 0 then
          Markup := Markup + ', ';
        Markup := Markup + LowerCase(Names[I]);
      end;
      ViewerNote('figure saved, with ' + Markup + ': ' + FileName, 8000);
    end;
  finally
    Bmp.Free;
  end;
end;

function ExportEnabled(AViewer: TObject): Boolean;
begin
  Result := FigureSourceAvailable and (ShownImageName <> '');
end;

initialization
  RegisterMenuEntry('Export figure (SVG) ...', @ExportFigure, @ExportEnabled);
end.
