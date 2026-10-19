unit uExifRotate;

{
  Unit: uExifRotate

  Purpose
  -------
  Lossless rotation of JPEGs by their EXIF orientation tag (1.1, user):
  the pixels stay as they are, only the tag (0x0112) that says how to
  turn them changes, so nothing is decoded and compressed again. Every
  current viewer, Windows and the browsers follow the tag.

  Owns
  ----
  Nothing (plain functions on byte arrays).

  Knows
  -----
  - The eight orientations as the turns and mirrors they stand for.
  - The JPEG markers and the EXIF (TIFF) layout of the first APP1.

  Responsibilities
  ----------------
  - OrientationAfter: the tag after turning or mirroring the picture as
    it is seen now.
  - SetJpegOrientation: the tag written into a JPEG in memory:
      - the tag is there: its value is changed in place;
      - EXIF without the tag: IFD0 is copied to the end of the EXIF block
        with the tag added (the old one stays unused; all other offsets
        keep pointing where they did);
      - no EXIF: a small EXIF block with the tag alone goes after the
        JFIF block (or right after the start).
    False with the reason when the data isn't a JPEG one can write to.

  Does NOT
  --------
  - Read or write files (TMView: written safely, the file's date kept).
  - Touch the pixels, the embedded thumbnail or other tags.

  Threads
  -------
  Any thread; no state.

  Uses (MView units)
  ------------------
  (none)
  Libraries:      SysUtils

  Used by
  -------
  uMView, TestExif
}

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils;

type
  TOrientOp = (ooRotateRight, ooRotateLeft, ooRotate180, ooFlipHorizontal, ooFlipVertical);

{ The orientation (1 .. 8) after AOp on the picture as it is seen with
  AOld. }
function OrientationAfter(AOld: Integer; AOp: TOrientOp): Integer;
function SetJpegOrientation(var AData: TBytes; AOrientation: Integer; out AError: string): Boolean;

implementation

type
  { How the stored pixels are shown: x' = A*x + B*y, y' = C*x + D*y
    (x to the right, y down). }
  TMat = record
    A, B, C, D: Integer;
  end;

const
  { EXIF 1 .. 8. }
  OrientMat: array[1..8] of TMat = (
    (A: 1; B: 0; C: 0; D: 1),      { 1 upright }
    (A: -1; B: 0; C: 0; D: 1),     { 2 mirrored left-right }
    (A: -1; B: 0; C: 0; D: -1),    { 3 upside down }
    (A: 1; B: 0; C: 0; D: -1),     { 4 mirrored top-bottom }
    (A: 0; B: 1; C: 1; D: 0),      { 5 transposed }
    (A: 0; B: -1; C: 1; D: 0),     { 6 turned 90 clockwise }
    (A: 0; B: -1; C: -1; D: 0),    { 7 transversed }
    (A: 0; B: 1; C: -1; D: 0));    { 8 turned 90 anticlockwise }

  OpMat: array[TOrientOp] of TMat = (
    (A: 0; B: -1; C: 1; D: 0),     { right: 90 clockwise }
    (A: 0; B: 1; C: -1; D: 0),     { left }
    (A: -1; B: 0; C: 0; D: -1),    { 180 }
    (A: -1; B: 0; C: 0; D: 1),     { mirror left-right }
    (A: 1; B: 0; C: 0; D: -1));    { mirror top-bottom }

function Mul(const P, Q: TMat): TMat;      { P after Q }
begin
  Result.A := P.A * Q.A + P.B * Q.C;
  Result.B := P.A * Q.B + P.B * Q.D;
  Result.C := P.C * Q.A + P.D * Q.C;
  Result.D := P.C * Q.B + P.D * Q.D;
end;

function OrientationAfter(AOld: Integer; AOp: TOrientOp): Integer;
var
  M: TMat;
  I: Integer;
begin
  if (AOld < 1) or (AOld > 8) then
    AOld := 1;
  M := Mul(OpMat[AOp], OrientMat[AOld]);
  for I := 1 to 8 do
    if (OrientMat[I].A = M.A) and (OrientMat[I].B = M.B) and (OrientMat[I].C = M.C)
      and (OrientMat[I].D = M.D) then
      Exit(I);
  Result := 1;
end;

function Get16(const AData: TBytes; APos: Integer; ALittle: Boolean): Integer;
begin
  if ALittle then
    Result := AData[APos] or (AData[APos + 1] shl 8)
  else
    Result := (AData[APos] shl 8) or AData[APos + 1];
end;

function Get32(const AData: TBytes; APos: Integer; ALittle: Boolean): Int64;
begin
  if ALittle then
    Result := Int64(AData[APos]) or (Int64(AData[APos + 1]) shl 8) or (Int64(AData[APos + 2]) shl 16)
      or (Int64(AData[APos + 3]) shl 24)
  else
    Result := (Int64(AData[APos]) shl 24) or (Int64(AData[APos + 1]) shl 16)
      or (Int64(AData[APos + 2]) shl 8) or Int64(AData[APos + 3]);
end;

procedure Put16(var AData: TBytes; APos, AValue: Integer; ALittle: Boolean);
begin
  if ALittle then
  begin
    AData[APos] := AValue and $FF;
    AData[APos + 1] := (AValue shr 8) and $FF;
  end
  else
  begin
    AData[APos] := (AValue shr 8) and $FF;
    AData[APos + 1] := AValue and $FF;
  end;
end;

procedure Put32(var AData: TBytes; APos: Integer; AValue: Int64; ALittle: Boolean);
begin
  if ALittle then
  begin
    AData[APos] := AValue and $FF;
    AData[APos + 1] := (AValue shr 8) and $FF;
    AData[APos + 2] := (AValue shr 16) and $FF;
    AData[APos + 3] := (AValue shr 24) and $FF;
  end
  else
  begin
    AData[APos] := (AValue shr 24) and $FF;
    AData[APos + 1] := (AValue shr 16) and $FF;
    AData[APos + 2] := (AValue shr 8) and $FF;
    AData[APos + 3] := AValue and $FF;
  end;
end;

{ ACount bytes of zeros at APos. }
procedure InsertBytes(var AData: TBytes; APos, ACount: Integer);
var
  OldLen: Integer;
begin
  OldLen := Length(AData);
  SetLength(AData, OldLen + ACount);
  if APos < OldLen then
    Move(AData[APos], AData[APos + ACount], OldLen - APos);
  FillChar(AData[APos], ACount, 0);
end;

function SetJpegOrientation(var AData: TBytes; AOrientation: Integer; out AError: string): Boolean;
const
  OrientTag = $0112;
var
  P, SegLen, Marker, AfterApp0, ExifSeg, Tiff, TiffLen, Ifd, N, I, E, NewIfd, Pad, Grow: Integer;
  Little: Boolean;
  Tag: Integer;
  NextIfd: Int64;
  Entries: TBytes;
begin
  Result := False;
  AError := '';
  if (AOrientation < 1) or (AOrientation > 8) then
  begin
    AError := 'no such orientation';
    Exit;
  end;
  if (Length(AData) < 4) or (AData[0] <> $FF) or (AData[1] <> $D8) then
  begin
    AError := 'not a JPEG';
    Exit;
  end;
  { The markers up to the image data: the first EXIF block, and where a
    new one would go. }
  P := 2;
  AfterApp0 := 2;
  ExifSeg := -1;
  while P + 4 <= Length(AData) do
  begin
    if AData[P] <> $FF then
    begin
      AError := 'the JPEG''s markers are damaged';
      Exit;
    end;
    Marker := AData[P + 1];
    if Marker = $FF then
    begin
      Inc(P);                   { fill byte }
      Continue;
    end;
    if (Marker = $DA) or (Marker = $D9) then
      Break;                    { the image data (or the end) }
    if (Marker >= $D0) and (Marker <= $D7) or (Marker = $01) then
    begin
      Inc(P, 2);
      Continue;
    end;
    SegLen := (AData[P + 2] shl 8) or AData[P + 3];
    if (SegLen < 2) or (P + 2 + SegLen > Length(AData)) then
    begin
      AError := 'the JPEG''s markers are damaged';
      Exit;
    end;
    if (Marker = $E0) and (P = AfterApp0) then
      AfterApp0 := P + 2 + SegLen;
    if (Marker = $E1) and (ExifSeg < 0) and (SegLen >= 2 + 6 + 8)
      and (AData[P + 4] = Ord('E')) and (AData[P + 5] = Ord('x')) and (AData[P + 6] = Ord('i'))
      and (AData[P + 7] = Ord('f')) and (AData[P + 8] = 0) and (AData[P + 9] = 0) then
      ExifSeg := P;
    Inc(P, 2 + SegLen);
  end;

  if ExifSeg < 0 then
  begin
    { No EXIF: a block with the tag alone, after JFIF's (EXIF 2.3:
      APP1 follows the start; with JFIF, after its APP0). }
    if AOrientation = 1 then
      Exit(True);               { upright already: nothing to write }
    InsertBytes(AData, AfterApp0, 36);
    P := AfterApp0;
    AData[P] := $FF;
    AData[P + 1] := $E1;
    AData[P + 2] := 0;
    AData[P + 3] := 34;          { length: 2 + 6 + 8 + 2 + 12 + 4 }
    AData[P + 4] := Ord('E');
    AData[P + 5] := Ord('x');
    AData[P + 6] := Ord('i');
    AData[P + 7] := Ord('f');
    Tiff := P + 10;
    AData[Tiff] := Ord('I');
    AData[Tiff + 1] := Ord('I');
    Put16(AData, Tiff + 2, 42, True);
    Put32(AData, Tiff + 4, 8, True);
    Put16(AData, Tiff + 8, 1, True);           { one entry }
    Put16(AData, Tiff + 10, OrientTag, True);
    Put16(AData, Tiff + 12, 3, True);          { SHORT }
    Put32(AData, Tiff + 14, 1, True);          { one value }
    Put16(AData, Tiff + 18, AOrientation, True);
    Put32(AData, Tiff + 22, 0, True);          { no next IFD }
    Exit(True);
  end;

  { The EXIF block's TIFF structure. }
  SegLen := (AData[ExifSeg + 2] shl 8) or AData[ExifSeg + 3];
  Tiff := ExifSeg + 10;
  TiffLen := SegLen - 2 - 6;
  if (AData[Tiff] = Ord('I')) and (AData[Tiff + 1] = Ord('I')) then
    Little := True
  else if (AData[Tiff] = Ord('M')) and (AData[Tiff + 1] = Ord('M')) then
    Little := False
  else
  begin
    AError := 'the EXIF block is damaged';
    Exit;
  end;
  Ifd := Get32(AData, Tiff + 4, Little);
  if (Ifd < 8) or (Ifd + 2 > TiffLen) then
  begin
    AError := 'the EXIF block is damaged';
    Exit;
  end;
  N := Get16(AData, Tiff + Ifd, Little);
  if Ifd + 2 + 12 * N + 4 > TiffLen then
  begin
    AError := 'the EXIF block is damaged';
    Exit;
  end;
  for I := 0 to N - 1 do
  begin
    E := Tiff + Ifd + 2 + 12 * I;
    if Get16(AData, E, Little) = OrientTag then
    begin
      { There: the value in place (a SHORT in the entry). }
      if (Get16(AData, E + 2, Little) <> 3) or (Get32(AData, E + 4, Little) < 1) then
      begin
        AError := 'the EXIF orientation entry is not a number';
        Exit;
      end;
      Put16(AData, E + 8, AOrientation, Little);
      Exit(True);
    end;
  end;

  { EXIF without the tag: IFD0 again at the block's end, with the tag. }
  Pad := TiffLen and 1;
  Grow := Pad + 2 + 12 * (N + 1) + 4;
  if SegLen + Grow > $FFFF then
  begin
    AError := 'the EXIF block is full';
    Exit;
  end;
  NextIfd := Get32(AData, Tiff + Ifd + 2 + 12 * N, Little);
  { The old entries with the new one in the order of their tags. }
  SetLength(Entries, 12 * (N + 1));
  E := 0;
  for I := 0 to N - 1 do
  begin
    Tag := Get16(AData, Tiff + Ifd + 2 + 12 * I, Little);
    if (Tag > OrientTag) and (E = 12 * I) then
      Inc(E, 12);               { the new one's place }
    Move(AData[Tiff + Ifd + 2 + 12 * I], Entries[E], 12);
    Inc(E, 12);
  end;
  { Its place: the first gap left (or the end). }
  E := 12 * N;
  for I := 0 to N - 1 do
    if Get16(AData, Tiff + Ifd + 2 + 12 * I, Little) > OrientTag then
    begin
      E := 12 * I;
      Break;
    end;
  Put16(Entries, E, OrientTag, Little);
  Put16(Entries, E + 2, 3, Little);
  Put32(Entries, E + 4, 1, Little);
  Put32(Entries, E + 8, 0, Little);
  Put16(Entries, E + 8, AOrientation, Little);

  NewIfd := TiffLen + Pad;
  InsertBytes(AData, Tiff + TiffLen, Grow);
  P := Tiff + NewIfd;
  Put16(AData, P, N + 1, Little);
  Move(Entries[0], AData[P + 2], Length(Entries));
  Put32(AData, P + 2 + 12 * (N + 1), NextIfd, Little);
  Put32(AData, Tiff + 4, NewIfd, Little);
  AData[ExifSeg + 2] := ((SegLen + Grow) shr 8) and $FF;
  AData[ExifSeg + 3] := (SegLen + Grow) and $FF;
  Result := True;
end;

end.
