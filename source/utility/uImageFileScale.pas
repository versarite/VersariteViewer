unit uImageFileScale;

{
  Unit: uImageFileScale

  Purpose
  -------
  The scale of a saved image, in the file itself (Day 26, user: "the
  scale travels with the image" - a saved crop keeps its µm):
  - TIFF: an uncompressed RGB TIFF (baseline, one strip) with the
    ImageJ convention - ImageDescription "ImageJ=1.54f\nunit=micron\n",
    XResolution / YResolution = pixels per micron, ResolutionUnit 1
    (none) - so ImageJ / Fiji open it calibrated in µm.
  - PNG: a pHYs chunk (pixels per metre, for other programs) and a tEXt
    chunk "Versarite scale" (before 1.1 "MView scale", still read) = "um_per_pixel=0.1173,0.1173" (the exact value,
    and the mark that the pHYs is a scale, not a print resolution) after
    IHDR.
  - Reading both back: ReadImageFileScale (an ImageJ TIFF's unit and
    resolution - also one saved by Fiji -, a PNG's "MView scale").
    A TIFF without an ImageJ unit (Leica exports: 72 dpi) and a PNG with
    a pHYs only (300 dpi from an image program) have none.

  Owns
  ----
  Nothing.

  Does NOT
  --------
  - Encode or decode pixels beyond the plain RGB strip (the PNG itself
    comes from FPWritePNG, uImageSaver).

  Threads
  -------
  Pure functions: any thread.

  Uses (MView units)
  ------------------
  (none)
  Libraries:      Classes, SysUtils, Math

  Used by
  -------
  uImageSaver (writing); the microscopy edition's uImageScale (reading);
  test\TestCalibrations.lpr
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils;

{ An RGB TIFF of AWidth x AHeight from ARGB (R G B per pixel, rows top
  down). AUmX / AUmY > 0: its scale (µm per pixel, ImageJ's way); else
  72 dpi as usual. }
function MakeRgbTiff(AWidth, AHeight: Integer; const ARGB: TBytes; AUmX, AUmY: Double): TBytes;

{ APng with a pHYs chunk (µm per pixel as pixels per metre) after its
  IHDR; APng unchanged if it isn't a PNG or AUmX / AUmY <= 0. }
function AddPngPixelSize(const APng: TBytes; AUmX, AUmY: Double): TBytes;

{ The scale a file states: an ImageJ TIFF's (unit micron, µm, um, nm,
  mm), a PNG's pHYs (unit metre). False if none (or not such a file). }
function ReadImageFileScale(const AFileName: string; out AUmX, AUmY: Double): Boolean;
function ReadStreamScale(AStream: TStream; out AUmX, AUmY: Double): Boolean;

implementation

uses
  Math;

{ ---- CRC-32 (PNG chunks) ---- }

var
  CrcTable: array[0..255] of LongWord;
  CrcReady: Boolean = False;

procedure MakeCrcTable;
var
  N, K: Integer;
  C: LongWord;
begin
  for N := 0 to 255 do
  begin
    C := LongWord(N);
    for K := 0 to 7 do
      if (C and 1) <> 0 then
        C := $EDB88320 xor (C shr 1)
      else
        C := C shr 1;
    CrcTable[N] := C;
  end;
  CrcReady := True;
end;

function Crc32Of(const AData: TBytes; AFrom, ACount: Integer): LongWord;
var
  I: Integer;
  C: LongWord;
begin
  if not CrcReady then
    MakeCrcTable;
  C := $FFFFFFFF;
  for I := AFrom to AFrom + ACount - 1 do
    C := CrcTable[(C xor AData[I]) and $FF] xor (C shr 8);
  Result := C xor $FFFFFFFF;
end;

{ ---- Writing ---- }

procedure PutU16LE(var AData: TBytes; APos: Integer; AValue: Word);
begin
  AData[APos] := AValue and $FF;
  AData[APos + 1] := AValue shr 8;
end;

procedure PutU32LE(var AData: TBytes; APos: Integer; AValue: LongWord);
begin
  AData[APos] := AValue and $FF;
  AData[APos + 1] := (AValue shr 8) and $FF;
  AData[APos + 2] := (AValue shr 16) and $FF;
  AData[APos + 3] := AValue shr 24;
end;

procedure PutU32BE(var AData: TBytes; APos: Integer; AValue: LongWord);
begin
  AData[APos] := AValue shr 24;
  AData[APos + 1] := (AValue shr 16) and $FF;
  AData[APos + 2] := (AValue shr 8) and $FF;
  AData[APos + 3] := AValue and $FF;
end;

{ AValue as a TIFF rational: the largest denominator (a power of ten up
  to a million) that keeps the numerator in 32 bits. }
procedure Rational(AValue: Double; out ANum, ADen: LongWord);
var
  Den: Double;
begin
  if AValue > 4.29e9 then
    AValue := 4.29e9;
  Den := 1000000;
  while (Den > 1) and (AValue * Den > 4294967295.0) do
    Den := Den / 10;
  ANum := LongWord(Min(Round(AValue * Den), Int64(4294967295)));
  ADen := LongWord(Round(Den));
  if ANum = 0 then
    ANum := 1;
end;

function MakeRgbTiff(AWidth, AHeight: Integer; const ARGB: TBytes; AUmX, AUmY: Double): TBytes;
const
  TypeShort = 3;
  TypeLong = 4;
  TypeAscii = 2;
  TypeRational = 5;
var
  Scaled: Boolean;
  Desc: AnsiString;
  Count, IfdAt, EntryAt, ExtraAt, BpsAt, XResAt, YResAt, DescAt, DataAt, DataSize, I: Integer;
  XNum, XDen, YNum, YDen: LongWord;

  procedure Entry(ATag, AType: Word; ACount, AValue: LongWord);
  begin
    PutU16LE(Result, EntryAt, ATag);
    PutU16LE(Result, EntryAt + 2, AType);
    PutU32LE(Result, EntryAt + 4, ACount);
    if (AType = TypeShort) and (ACount = 1) then
    begin
      PutU16LE(Result, EntryAt + 8, AValue);
      PutU16LE(Result, EntryAt + 10, 0);
    end
    else
      PutU32LE(Result, EntryAt + 8, AValue);
    Inc(EntryAt, 12);
  end;

begin
  Result := nil;
  if (AWidth <= 0) or (AHeight <= 0) or (Length(ARGB) < Int64(AWidth) * AHeight * 3) then
    Exit;
  Scaled := (AUmX > 0) and (AUmY > 0);
  if Scaled then
  begin
    Desc := 'ImageJ=1.54f'#10'unit=micron'#10#0;
    Rational(1 / AUmX, XNum, XDen);
    Rational(1 / AUmY, YNum, YDen);
  end
  else
  begin
    Desc := '';
    XNum := 72;
    XDen := 1;
    YNum := 72;
    YDen := 1;
  end;
  { Header, the IFD, then its values (BitsPerSample, the rationals, the
    description), then the pixels. }
  Count := 13;
  if Scaled then
    Inc(Count);
  IfdAt := 8;
  ExtraAt := IfdAt + 2 + Count * 12 + 4;
  BpsAt := ExtraAt;
  XResAt := BpsAt + 6;
  YResAt := XResAt + 8;
  DescAt := YResAt + 8;
  DataAt := DescAt + Length(Desc);
  if Odd(DataAt) then
    Inc(DataAt);
  DataSize := AWidth * AHeight * 3;
  SetLength(Result, DataAt + DataSize);
  FillChar(Result[0], DataAt, 0);
  Result[0] := Ord('I');
  Result[1] := Ord('I');
  PutU16LE(Result, 2, 42);
  PutU32LE(Result, 4, IfdAt);
  PutU16LE(Result, IfdAt, Count);
  EntryAt := IfdAt + 2;
  { In ascending tag order. }
  Entry(256, TypeLong, 1, AWidth);                 { ImageWidth }
  Entry(257, TypeLong, 1, AHeight);                { ImageLength }
  Entry(258, TypeShort, 3, BpsAt);                 { BitsPerSample 8,8,8 }
  Entry(259, TypeShort, 1, 1);                     { Compression: none }
  Entry(262, TypeShort, 1, 2);                     { Photometric: RGB }
  if Scaled then
    Entry(270, TypeAscii, Length(Desc), DescAt);   { ImageDescription }
  Entry(273, TypeLong, 1, DataAt);                 { StripOffsets }
  Entry(277, TypeShort, 1, 3);                     { SamplesPerPixel }
  Entry(278, TypeLong, 1, AHeight);                { RowsPerStrip }
  Entry(279, TypeLong, 1, DataSize);               { StripByteCounts }
  Entry(282, TypeRational, 1, XResAt);             { XResolution }
  Entry(283, TypeRational, 1, YResAt);             { YResolution }
  Entry(284, TypeShort, 1, 1);                     { PlanarConfiguration: chunky }
  if Scaled then
    Entry(296, TypeShort, 1, 1)                    { ResolutionUnit: none (ImageJ: the unit is in the description) }
  else
    Entry(296, TypeShort, 1, 2);                   { inch }
  PutU32LE(Result, EntryAt, 0);                    { no next IFD }
  PutU16LE(Result, BpsAt, 8);
  PutU16LE(Result, BpsAt + 2, 8);
  PutU16LE(Result, BpsAt + 4, 8);
  PutU32LE(Result, XResAt, XNum);
  PutU32LE(Result, XResAt + 4, XDen);
  PutU32LE(Result, YResAt, YNum);
  PutU32LE(Result, YResAt + 4, YDen);
  for I := 1 to Length(Desc) do
    Result[DescAt + I - 1] := Ord(Desc[I]);
  Move(ARGB[0], Result[DataAt], DataSize);
end;

function IsPng(const AData: TBytes): Boolean;
const
  Sig: array[0..7] of Byte = (137, 80, 78, 71, 13, 10, 26, 10);
var
  I: Integer;
begin
  Result := Length(AData) >= 33;
  if Result then
    for I := 0 to 7 do
      if AData[I] <> Sig[I] then
        Exit(False);
end;

const
  ScaleKeyword = 'Versarite scale';
  { The keyword before the rename (1.1): still read. }
  OldScaleKeyword = 'MView scale';

{ A number with a point, whatever the locale. }
function PointText(AValue: Double): string;
var
  Fmt: TFormatSettings;
begin
  Fmt := DefaultFormatSettings;
  Fmt.DecimalSeparator := '.';
  Result := FloatToStrF(AValue, ffGeneral, 10, 0, Fmt);
end;

{ A chunk: length, type, data, CRC (of type and data). }
function PngChunk(const AType: AnsiString; const AData: TBytes): TBytes;
var
  I: Integer;
begin
  SetLength(Result, 12 + Length(AData));
  PutU32BE(Result, 0, Length(AData));
  for I := 1 to 4 do
    Result[3 + I] := Ord(AType[I]);
  if Length(AData) > 0 then
    Move(AData[0], Result[8], Length(AData));
  PutU32BE(Result, 8 + Length(AData), Crc32Of(Result, 4, 4 + Length(AData)));
end;

function AddPngPixelSize(const APng: TBytes; AUmX, AUmY: Double): TBytes;
const
  At = 33;                      { after the signature and IHDR (13 bytes of data) }
var
  Phys, Text, Chunks: TBytes;
  Value: AnsiString;
  I: Integer;
  PX, PY: Double;
begin
  if (AUmX <= 0) or (AUmY <= 0) or not IsPng(APng)
    or (APng[12] <> Ord('I')) or (APng[13] <> Ord('H')) or (APng[14] <> Ord('D'))
    or (APng[15] <> Ord('R')) then
    Exit(APng);
  { pHYs: pixels per metre (kept in 32 bits). }
  SetLength(Phys, 9);
  PX := Min(4294967295.0, Max(1.0, 1e6 / AUmX));
  PY := Min(4294967295.0, Max(1.0, 1e6 / AUmY));
  PutU32BE(Phys, 0, LongWord(Round(PX)));
  PutU32BE(Phys, 4, LongWord(Round(PY)));
  Phys[8] := 1;                 { unit: metre }
  { tEXt: keyword, NUL, text. }
  Value := ScaleKeyword + #0 + 'um_per_pixel=' + PointText(AUmX) + ',' + PointText(AUmY);
  SetLength(Text, Length(Value));
  for I := 1 to Length(Value) do
    Text[I - 1] := Ord(Value[I]);
  Phys := PngChunk('pHYs', Phys);
  Text := PngChunk('tEXt', Text);
  SetLength(Chunks, Length(Phys) + Length(Text));
  Move(Phys[0], Chunks[0], Length(Phys));
  Move(Text[0], Chunks[Length(Phys)], Length(Text));
  Result := nil;
  SetLength(Result, Length(APng) + Length(Chunks));
  Move(APng[0], Result[0], At);
  Move(Chunks[0], Result[At], Length(Chunks));
  Move(APng[At], Result[At + Length(Chunks)], Length(APng) - At);
end;

{ ---- Reading ---- }

function ReadBytesAt(AStream: TStream; APos: Int64; ACount: Integer; out AData: TBytes): Boolean;
begin
  AData := nil;
  Result := False;
  if (APos < 0) or (ACount <= 0) or (APos + ACount > AStream.Size) then
    Exit;
  SetLength(AData, ACount);
  AStream.Position := APos;
  Result := AStream.Read(AData[0], ACount) = ACount;
end;

function PngScale(AStream: TStream; out AUmX, AUmY: Double): Boolean;
var
  ChunkPos: Int64;
  Head, Body: TBytes;
  Len: LongWord;
  Kind, Text, Part: AnsiString;
  Chunks, Comma: Integer;
  Fmt: TFormatSettings;
begin
  Result := False;
  AUmX := 0;
  AUmY := 0;
  Fmt := DefaultFormatSettings;
  Fmt.DecimalSeparator := '.';
  ChunkPos := 8;
  Chunks := 0;
  { The chunks before the pixels (MView writes its own after IHDR). }
  while (Chunks < 64) and ReadBytesAt(AStream, ChunkPos, 8, Head) do
  begin
    Inc(Chunks);
    Len := (LongWord(Head[0]) shl 24) or (LongWord(Head[1]) shl 16) or (LongWord(Head[2]) shl 8)
      or Head[3];
    Kind := Chr(Head[4]) + Chr(Head[5]) + Chr(Head[6]) + Chr(Head[7]);
    if (Kind = 'IDAT') or (Kind = 'IEND') then
      Exit;
    if (Kind = 'tEXt') and (Len > Length(OldScaleKeyword) + 1) and (Len < 1000) then
    begin
      if not ReadBytesAt(AStream, ChunkPos + 8, Len, Body) then
        Exit;
      SetLength(Text, Len);
      Move(Body[0], Text[1], Len);
      Part := '';
      if Copy(Text, 1, Length(ScaleKeyword) + 1) = ScaleKeyword + #0 then
        Part := Copy(Text, Length(ScaleKeyword) + 2, MaxInt)
      else if Copy(Text, 1, Length(OldScaleKeyword) + 1) = OldScaleKeyword + #0 then
        Part := Copy(Text, Length(OldScaleKeyword) + 2, MaxInt);
      if Part <> '' then
      begin
        { "um_per_pixel=0.1173,0.1173" }
        if Copy(Part, 1, 13) <> 'um_per_pixel=' then
          Exit;
        Delete(Part, 1, 13);
        Comma := Pos(',', Part);
        if Comma = 0 then
          Exit;
        if not TryStrToFloat(Copy(Part, 1, Comma - 1), AUmX, Fmt)
          or not TryStrToFloat(Copy(Part, Comma + 1, MaxInt), AUmY, Fmt) then
          Exit;
        Result := (AUmX > 0) and (AUmY > 0);
        if not Result then
        begin
          AUmX := 0;
          AUmY := 0;
        end;
        Exit;
      end;
    end;
    ChunkPos := ChunkPos + 12 + Len;
  end;
end;

function TiffScale(AStream: TStream; out AUmX, AUmY: Double): Boolean;
var
  Head, Ifd, Val: TBytes;
  Little: Boolean;
  IfdPos, ValPos, ValCount: Int64;
  I, Count: Integer;
  Tag, Kind: Word;
  XRes, YRes, Factor: Double;
  Desc, UnitText, Line: string;
  P: Integer;

  function U16(const A: TBytes; AAt: Integer): Word;
  begin
    if Little then
      Result := A[AAt] or (Word(A[AAt + 1]) shl 8)
    else
      Result := (Word(A[AAt]) shl 8) or A[AAt + 1];
  end;

  function U32(const A: TBytes; AAt: Integer): LongWord;
  begin
    if Little then
      Result := A[AAt] or (LongWord(A[AAt + 1]) shl 8) or (LongWord(A[AAt + 2]) shl 16)
        or (LongWord(A[AAt + 3]) shl 24)
    else
      Result := (LongWord(A[AAt]) shl 24) or (LongWord(A[AAt + 1]) shl 16)
        or (LongWord(A[AAt + 2]) shl 8) or A[AAt + 3];
  end;

  function RationalAt(AOffset: LongWord): Double;
  var
    R: TBytes;
  begin
    Result := 0;
    if ReadBytesAt(AStream, AOffset, 8, R) and (U32(R, 4) <> 0) then
      Result := U32(R, 0) / U32(R, 4);
  end;

begin
  Result := False;
  AUmX := 0;
  AUmY := 0;
  if not ReadBytesAt(AStream, 0, 8, Head) then
    Exit;
  if (Head[0] = Ord('I')) and (Head[1] = Ord('I')) then
    Little := True
  else if (Head[0] = Ord('M')) and (Head[1] = Ord('M')) then
    Little := False
  else
    Exit;
  if U16(Head, 2) <> 42 then
    Exit;
  IfdPos := U32(Head, 4);
  if not ReadBytesAt(AStream, IfdPos, 2, Ifd) then
    Exit;
  Count := U16(Ifd, 0);
  if (Count <= 0) or (Count > 1000) or not ReadBytesAt(AStream, IfdPos + 2, Count * 12, Ifd) then
    Exit;
  XRes := 0;
  YRes := 0;
  Desc := '';
  for I := 0 to Count - 1 do
  begin
    Tag := U16(Ifd, I * 12);
    Kind := U16(Ifd, I * 12 + 2);
    ValCount := U32(Ifd, I * 12 + 4);
    case Tag of
      270:
        if (Kind = 2) and (ValCount > 0) and (ValCount < 1000000) then
        begin
          if ValCount <= 4 then
            Continue;           { too short for "unit=" }
          ValPos := U32(Ifd, I * 12 + 8);
          if ReadBytesAt(AStream, ValPos, Integer(ValCount), Val) then
          begin
            SetLength(Desc, Integer(ValCount));
            Move(Val[0], Desc[1], ValCount);
          end;
        end;
      282:
        if Kind = 5 then
          XRes := RationalAt(U32(Ifd, I * 12 + 8));
      283:
        if Kind = 5 then
          YRes := RationalAt(U32(Ifd, I * 12 + 8));
    end;
  end;
  { ImageJ's description: "unit=micron" (or µm, µm, um, nm, mm). }
  if Copy(Desc, 1, 7) <> 'ImageJ=' then
    Exit;
  UnitText := '';
  Desc := StringReplace(Desc, #13, #10, [rfReplaceAll]) + #10;
  while Desc <> '' do
  begin
    P := Pos(#10, Desc);
    Line := Trim(Copy(Desc, 1, P - 1));
    Delete(Desc, 1, P);
    if Copy(Line, 1, 5) = 'unit=' then
    begin
      UnitText := LowerCase(Copy(Line, 6, MaxInt));
      Break;
    end;
  end;
  { µ in UTF-8, in Latin-1, as Greek mu, or ImageJ's escape. }
  if (UnitText = 'micron') or (UnitText = 'microns') or (UnitText = 'um')
    or (UnitText = #$C2#$B5'm') or (UnitText = #$B5'm') or (UnitText = #$CE#$BC'm')
    or (UnitText = '\u00b5m') then
    Factor := 1
  else if UnitText = 'nm' then
    Factor := 0.001
  else if UnitText = 'mm' then
    Factor := 1000
  else
    Exit;
  if (XRes <= 0) then
    Exit;
  if YRes <= 0 then
    YRes := XRes;
  AUmX := Factor / XRes;
  AUmY := Factor / YRes;
  Result := True;
end;

function ReadStreamScale(AStream: TStream; out AUmX, AUmY: Double): Boolean;
var
  Head: TBytes;
begin
  Result := False;
  AUmX := 0;
  AUmY := 0;
  if not ReadBytesAt(AStream, 0, 8, Head) then
    Exit;
  if (Head[0] = 137) and (Head[1] = Ord('P')) and (Head[2] = Ord('N')) and (Head[3] = Ord('G')) then
    Result := PngScale(AStream, AUmX, AUmY)
  else if ((Head[0] = Ord('I')) and (Head[1] = Ord('I'))) or ((Head[0] = Ord('M')) and (Head[1] = Ord('M'))) then
    Result := TiffScale(AStream, AUmX, AUmY);
end;

function ReadImageFileScale(const AFileName: string; out AUmX, AUmY: Double): Boolean;
var
  Stream: TFileStream;
begin
  Result := False;
  AUmX := 0;
  AUmY := 0;
  try
    Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      Result := ReadStreamScale(Stream, AUmX, AUmY);
    finally
      Stream.Free;
    end;
  except
    Result := False;
  end;
end;

end.
