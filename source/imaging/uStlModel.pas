unit uStlModel;

{
  Unit: uStlModel

  Purpose
  -------
  3D models (.stl, 1.3): reads binary and ASCII STL files and draws
  them in software into a TBGRABitmap - turned, tilted, cut by a
  plane with the cut face shown closed, on a grid, with the triangle
  edges. The same look as the user's own STL viewer
  (C:\projects\lazarus_stl_viewer), without OpenGL, so the decode
  workers can draw the first view and TMView every later one.

  Owns
  ----
  - TStlModel: the triangles (three corners each, as in the file), the
    bounds, the welded corners (sorted once, on the first smoothing
    above 1) and the corner normals of the last smoothing level.
  - A small cache of the last models read (key: name, size, time), so
    the decode worker and TMView share one copy.

  Knows
  -----
  uTypes (TImageKey, TCancelCheck), BGRABitmap.

  Responsibilities
  ----------------
  - Read: binary when the size is 84 + 50 x the count in the header,
    ASCII when the file starts with "solid" (every "vertex" line).
  - Draw (Render): orthographic, Z up as in slicers; Turn around Z,
    Tilt = elevation (0: from the side, 90: from above). A z-buffer;
    the light at the eye (two-sided); smooth corner normals for the
    smoothing level (faces closer than its angle are averaged, sharp
    edges stay sharp).
  - Section: the part behind the plane (or in front, Flip) is left
    out per pixel; the cut face is closed: a pixel's point on the plane
    is inside the solid when an odd number of surfaces lie between it
    and the eye (counted for all triangles, cut or not).
  - Grid (the build plate at the lowest Z), the axes, the plane's frame,
    the edges (light lines, slightly in front of their faces).

  Threads
  -------
  Any. A model is not changed after reading, except the smoothing
  cache (its own lock). Render allocates its own buffers.
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  Math,
  SyncObjs,
  BGRABitmap,
  BGRABitmapTypes,
  uTypes;

type
  TStlVec = record
    X, Y, Z: Single;
  end;
  TStlVecArray = array of TStlVec;

  { How a model is shown. }
  TStlView = record
    Turn: Double;            { degrees around the vertical (Z) axis }
    Tilt: Double;            { degrees: 0 = from the side, 90 = from above }
    Section: Boolean;        { cut by the plane }
    Flip: Boolean;           { keep the other side of the plane }
    PlaneX, PlaneY: Integer; { the plane's tilt around X / Y, -90 .. 90 }
    PlanePos: Integer;       { along its normal, -100 .. 100 % of the radius }
    Grid: Boolean;
    Edges: Boolean;
    Smooth: Integer;         { 1 (flat) .. 10 }
  end;

  { A model read from a file; shared by the decode worker and TMView
    (counted references: it lives while someone uses it). }
  IStlModel = interface
    ['{6B0E54C2-7A3D-4F1B-9E55-3C1A2B8D9F10}']
    function TriangleCount: Integer;
    { "120.0 x 80.0 x 45.0" (the file's units, usually mm). }
    function SizeText: string;
    { A new picture of AWidth x AHeight. APixelScale: screen pixels per
      picture pixel (2: drawn at twice the size, lines twice as wide).
      nil when cancelled. }
    function Render(const AView: TStlView; AWidth, AHeight: Integer;
      APixelScale: Double = 1; ACancel: TCancelCheck = nil): TBGRABitmap;
    { For drawing on the graphics card (uGLStlDraw, 1.3): the corners (3
      per triangle, as read), their normals for smoothing level ASmooth,
      and how the model is scaled: Q = (P - ACenter) / ARadius; AGridZ:
      the build plate's height in Q. The arrays are shared, not to be
      changed. }
    procedure MeshData(ASmooth: Integer; out ACorners, ANormals: TStlVecArray;
      out ACenter: TStlVec; out ARadius, AGridZ: Double);
  end;

  TStlModel = class(TInterfacedObject, IStlModel)
  private
    FCorners: TStlVecArray;       { 3 per triangle }
    FMin, FMax, FCenter: TStlVec;
    FRadius: Double;              { half the diagonal of the bounds }
    FLock: TCriticalSection;
    FFaceN: TStlVecArray;
    FOrder: array of Integer;     { the corners sorted by position }
    FGroupEnd: array of Integer;  { per sorted corner: the end of its group }
    FShadeLevel: Integer;
    FCornerN: TStlVecArray;
    procedure ComputeBounds;
    procedure BuildFaceNormals;
    procedure BuildWeld;
    function CornerNormals(ALevel: Integer): TStlVecArray;
  public
    constructor Create;
    destructor Destroy; override;
    { An exception with the reason if it can't be read. }
    procedure LoadFromFile(const AFileName: string; ACancel: TCancelCheck = nil);
    function TriangleCount: Integer;
    function SizeText: string;
    function Render(const AView: TStlView; AWidth, AHeight: Integer;
      APixelScale: Double = 1; ACancel: TCancelCheck = nil): TBGRABitmap;
    procedure MeshData(ASmooth: Integer; out ACorners, ANormals: TStlVecArray;
      out ACenter: TStlVec; out ARadius, AGridZ: Double);
  end;

  { The eye matrix: eye = M * Q; x right, y up, z towards the eye. }
  TStlMat3 = array[0..2, 0..2] of Double;

const
  { The look, shared by Render and the graphics card (uGLStlDraw). }
  StlBaseR = 0.92;
  StlBaseG = 0.90;
  StlBaseB = 0.80;
  StlBackR = 31;
  StlBackG = 36;
  StlBackB = 43;
  { The radius (1 after scaling) fills this part of half the picture. }
  StlFitPart = 0.88;

{ Rx(Tilt - 90) * Rz(Turn), as Render. }
function StlEyeMatrix(const AView: TStlView): TStlMat3;
{ The section's plane in Q: the kept side is PN . Q - PC >= 0 (Flip
  turned in). }
procedure StlPlaneOf(const AView: TStlView; out ANX, ANY, ANZ, APC: Double);
{ The light, eye space (unit length). }
procedure StlLight(out ALX, ALY, ALZ: Double);
{ Picture pixels per unit of Q for a picture of AWidth x AHeight. }
function StlPixelsPerUnit(AWidth, AHeight: Integer): Double;

function IsStlFileName(const AFileName: string): Boolean;
function DefaultStlView: TStlView;
function SameStlView(const A, B: TStlView): Boolean;
{ The view a model starts with: the default, with grid, edges and
  smoothing as last set (KeepStlSettings). Any thread. }
function StlStartView: TStlView;
procedure KeepStlSettings(const AView: TStlView);

{ The model of AKey's file, from the cache or read now (then kept). An
  exception if it can't be read. The last few stay in the cache. }
function StlModelFor(const AKey: TImageKey; ACancel: TCancelCheck = nil): IStlModel;

implementation

const
  { The colours of the STL viewer. }
  BaseR = StlBaseR;
  BaseG = StlBaseG;
  BaseB = StlBaseB;
  BackR = StlBackR;
  BackG = StlBackG;
  BackB = StlBackB;
  FitPart = StlFitPart;
  MaxFileBytes = Int64(1536) * 1024 * 1024;
  CacheSize = 3;

type
  TCacheEntry = record
    Key: TImageKey;
    Model: IStlModel;
    Used: QWord;
  end;

var
  KeptView: TStlView;
  CacheLock: TCriticalSection = nil;
  Cache: array[0..CacheSize - 1] of TCacheEntry;
  CacheClock: QWord = 0;

function IsStlFileName(const AFileName: string): Boolean;
begin
  Result := LowerCase(ExtractFileExt(AFileName)) = '.stl';
end;

function DefaultStlView: TStlView;
begin
  Result.Turn := -30;
  Result.Tilt := 30;
  Result.Section := False;
  Result.Flip := False;
  Result.PlaneX := 0;
  Result.PlaneY := 0;
  Result.PlanePos := 0;
  Result.Grid := True;
  Result.Edges := True;
  Result.Smooth := 1;
end;

function SameStlView(const A, B: TStlView): Boolean;
begin
  Result := (A.Turn = B.Turn) and (A.Tilt = B.Tilt) and (A.Section = B.Section)
    and (A.Flip = B.Flip) and (A.PlaneX = B.PlaneX) and (A.PlaneY = B.PlaneY)
    and (A.PlanePos = B.PlanePos) and (A.Grid = B.Grid) and (A.Edges = B.Edges)
    and (A.Smooth = B.Smooth);
end;

function StlStartView: TStlView;
begin
  Result := DefaultStlView;
  CacheLock.Acquire;
  try
    Result.Grid := KeptView.Grid;
    Result.Edges := KeptView.Edges;
    Result.Smooth := KeptView.Smooth;
  finally
    CacheLock.Release;
  end;
end;

procedure KeepStlSettings(const AView: TStlView);
begin
  CacheLock.Acquire;
  try
    KeptView := AView;
  finally
    CacheLock.Release;
  end;
end;

function Vec(AX, AY, AZ: Single): TStlVec; inline;
begin
  Result.X := AX;
  Result.Y := AY;
  Result.Z := AZ;
end;

function Cancelled(ACancel: TCancelCheck): Boolean; inline;
begin
  Result := Assigned(ACancel) and ACancel();
end;

{ ---- Reading ---- }

constructor TStlModel.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FShadeLevel := 0;
  FRadius := 1;
end;

destructor TStlModel.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

procedure TStlModel.LoadFromFile(const AFileName: string; ACancel: TCancelCheck);
var
  Stream: TFileStream;
  Data: TBytes;
  Size: Int64;
  Count, I, J, P: Integer;
  Text: AnsiString;
  N: Integer;

  function F32(AOffset: Integer): Single;
  begin
    Move(Data[AOffset], Result, 4);
  end;

  { ASCII: the numbers after every "vertex". }
  procedure ReadAscii;
  var
    Len, K, Start, Code, Got: Integer;
    Token: string;
    Values: array[0..2] of Single;
    V: Single;

    function NextToken: string;
    begin
      while (K <= Len) and (Text[K] <= ' ') do
        Inc(K);
      Start := K;
      while (K <= Len) and (Text[K] > ' ') do
        Inc(K);
      Result := Copy(Text, Start, K - Start);
    end;

  begin
    Len := Length(Text);
    K := 1;
    N := 0;
    SetLength(FCorners, 3 * 1024);
    while K <= Len do
    begin
      Token := NextToken;
      if Token = '' then
        Break;
      if (Length(Token) = 6) and SameText(Token, 'vertex') then
      begin
        Got := 0;
        while Got < 3 do
        begin
          Token := NextToken;
          Val(Token, V, Code);
          if (Token = '') or (Code <> 0) then
            raise Exception.Create('Damaged STL file (a vertex without 3 numbers)');
          Values[Got] := V;
          Inc(Got);
        end;
        if N >= Length(FCorners) then
        begin
          SetLength(FCorners, Length(FCorners) * 2);
          if Cancelled(ACancel) then
            raise Exception.Create('Cancelled');
        end;
        FCorners[N] := Vec(Values[0], Values[1], Values[2]);
        Inc(N);
      end;
    end;
    SetLength(FCorners, N - N mod 3);
  end;

begin
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    Size := Stream.Size;
    if Size > MaxFileBytes then
      raise Exception.Create('STL file too large');
    SetLength(Data, Size);
    if Size > 0 then
      Stream.ReadBuffer(Data[0], Size);
  finally
    Stream.Free;
  end;
  if Cancelled(ACancel) then
    raise Exception.Create('Cancelled');
  if Size < 15 then
    raise Exception.Create('Not an STL file');

  Count := -1;
  if Size >= 84 then
  begin
    Move(Data[80], Count, 4);
    if (Count < 0) or (84 + Int64(Count) * 50 <> Size) then
      Count := -1;
  end;

  if Count >= 0 then
  begin
    SetLength(FCorners, Count * 3);
    for I := 0 to Count - 1 do
    begin
      P := 84 + I * 50 + 12;   { past the file's normal (computed here) }
      for J := 0 to 2 do
        FCorners[I * 3 + J] := Vec(F32(P + J * 12), F32(P + J * 12 + 4), F32(P + J * 12 + 8));
    end;
  end
  else
  begin
    SetString(Text, PAnsiChar(@Data[0]), Size);
    SetLength(Data, 0);
    if not SameText(Copy(TrimLeft(Copy(Text, 1, 512)), 1, 5), 'solid') then
      raise Exception.Create('Not an STL file');
    ReadAscii;
  end;
  { Not a number (damaged files): to 0, so the bounds stay sane. }
  for I := 0 to High(FCorners) do
    with FCorners[I] do
    begin
      if IsNan(X) or IsInfinite(X) then X := 0;
      if IsNan(Y) or IsInfinite(Y) then Y := 0;
      if IsNan(Z) or IsInfinite(Z) then Z := 0;
    end;
  ComputeBounds;
  BuildFaceNormals;
end;

procedure TStlModel.MeshData(ASmooth: Integer; out ACorners, ANormals: TStlVecArray;
  out ACenter: TStlVec; out ARadius, AGridZ: Double);
begin
  ACorners := FCorners;
  ANormals := CornerNormals(ASmooth);
  ACenter := FCenter;
  ARadius := FRadius;
  AGridZ := (FMin.Z - FCenter.Z) / FRadius;
end;

function StlEyeMatrix(const AView: TStlView): TStlMat3;
var
  CT, ST, CE, SE, Tilt: Double;
begin
  CT := Cos(DegToRad(AView.Turn));
  ST := Sin(DegToRad(AView.Turn));
  Tilt := DegToRad(AView.Tilt - 90);
  CE := Cos(Tilt);
  SE := Sin(Tilt);
  Result[0, 0] := CT;        Result[0, 1] := -ST;       Result[0, 2] := 0;
  Result[1, 0] := CE * ST;   Result[1, 1] := CE * CT;   Result[1, 2] := -SE;
  Result[2, 0] := SE * ST;   Result[2, 1] := SE * CT;   Result[2, 2] := CE;
end;

procedure StlPlaneOf(const AView: TStlView; out ANX, ANY, ANZ, APC: Double);
begin
  ANX := Sin(DegToRad(AView.PlaneY));
  ANY := -Sin(DegToRad(AView.PlaneX)) * Cos(DegToRad(AView.PlaneY));
  ANZ := Cos(DegToRad(AView.PlaneX)) * Cos(DegToRad(AView.PlaneY));
  APC := AView.PlanePos / 100;
  if AView.Flip then
  begin
    ANX := -ANX;
    ANY := -ANY;
    ANZ := -ANZ;
    APC := -APC;
  end;
end;

procedure StlLight(out ALX, ALY, ALZ: Double);
var
  Len: Double;
begin
  Len := Sqrt(0.3 * 0.3 + 0.5 * 0.5 + 1);
  ALX := 0.3 / Len;
  ALY := 0.5 / Len;
  ALZ := 1 / Len;
end;

function StlPixelsPerUnit(AWidth, AHeight: Integer): Double;
begin
  Result := Min(AWidth, AHeight) / 2 * StlFitPart;
end;

function TStlModel.TriangleCount: Integer;
begin
  Result := Length(FCorners) div 3;
end;

function TStlModel.SizeText: string;
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := Format('%.1f x %.1f x %.1f', [FMax.X - FMin.X, FMax.Y - FMin.Y, FMax.Z - FMin.Z], FS);
end;

procedure TStlModel.ComputeBounds;
var
  I: Integer;
begin
  if Length(FCorners) = 0 then
  begin
    FMin := Vec(-1, -1, 0);
    FMax := Vec(1, 1, 1);
  end
  else
  begin
    FMin := FCorners[0];
    FMax := FCorners[0];
    for I := 1 to High(FCorners) do
      with FCorners[I] do
      begin
        if X < FMin.X then FMin.X := X;
        if Y < FMin.Y then FMin.Y := Y;
        if Z < FMin.Z then FMin.Z := Z;
        if X > FMax.X then FMax.X := X;
        if Y > FMax.Y then FMax.Y := Y;
        if Z > FMax.Z then FMax.Z := Z;
      end;
  end;
  FCenter := Vec((FMin.X + FMax.X) / 2, (FMin.Y + FMax.Y) / 2, (FMin.Z + FMax.Z) / 2);
  FRadius := Sqrt(Sqr(Double(FMax.X) - FMin.X) + Sqr(Double(FMax.Y) - FMin.Y)
    + Sqr(Double(FMax.Z) - FMin.Z)) / 2;
  if FRadius < 1e-9 then
    FRadius := 1;
end;

procedure TStlModel.BuildFaceNormals;
var
  I: Integer;
  AX, AY, AZ, BX, BY, BZ, NX, NY, NZ, Len: Double;
begin
  SetLength(FFaceN, TriangleCount);
  for I := 0 to High(FFaceN) do
  begin
    AX := Double(FCorners[I * 3 + 1].X) - FCorners[I * 3].X;
    AY := Double(FCorners[I * 3 + 1].Y) - FCorners[I * 3].Y;
    AZ := Double(FCorners[I * 3 + 1].Z) - FCorners[I * 3].Z;
    BX := Double(FCorners[I * 3 + 2].X) - FCorners[I * 3].X;
    BY := Double(FCorners[I * 3 + 2].Y) - FCorners[I * 3].Y;
    BZ := Double(FCorners[I * 3 + 2].Z) - FCorners[I * 3].Z;
    NX := AY * BZ - AZ * BY;
    NY := AZ * BX - AX * BZ;
    NZ := AX * BY - AY * BX;
    Len := Sqrt(NX * NX + NY * NY + NZ * NZ);
    if Len > 1e-30 then
      FFaceN[I] := Vec(NX / Len, NY / Len, NZ / Len)
    else
      FFaceN[I] := Vec(0, 0, 1);
  end;
end;

{ The corners at the same place (to a tolerance) next to each other:
  FOrder sorted by the quantised position, FGroupEnd per sorted index
  the index after its group. Once per model (under FLock). }
procedure TStlModel.BuildWeld;
type
  TKey = record
    QX, QY, QZ: Int64;
  end;
var
  Keys: array of TKey;
  Tol: Double;
  I, G0, G1: Integer;

  function Less(A, B: Integer): Boolean; inline;
  begin
    if Keys[A].QX <> Keys[B].QX then
      Exit(Keys[A].QX < Keys[B].QX);
    if Keys[A].QY <> Keys[B].QY then
      Exit(Keys[A].QY < Keys[B].QY);
    Result := Keys[A].QZ < Keys[B].QZ;
  end;

  function Same(A, B: Integer): Boolean; inline;
  begin
    Result := (Keys[A].QX = Keys[B].QX) and (Keys[A].QY = Keys[B].QY)
      and (Keys[A].QZ = Keys[B].QZ);
  end;

  procedure Sort(L, R: Integer);
  var
    I, J, P, T: Integer;
  begin
    while L < R do
    begin
      I := L;
      J := R;
      P := FOrder[(L + R) shr 1];
      repeat
        while Less(FOrder[I], P) do Inc(I);
        while Less(P, FOrder[J]) do Dec(J);
        if I <= J then
        begin
          T := FOrder[I]; FOrder[I] := FOrder[J]; FOrder[J] := T;
          Inc(I);
          Dec(J);
        end;
      until I > J;
      { The smaller part first (recursion), the larger by the loop. }
      if J - L < R - I then
      begin
        if L < J then Sort(L, J);
        L := I;
      end
      else
      begin
        if I < R then Sort(I, R);
        R := J;
      end;
    end;
  end;

begin
  Tol := Max(1e-9, FRadius * 1e-5);
  SetLength(Keys, Length(FCorners));
  SetLength(FOrder, Length(FCorners));
  for I := 0 to High(Keys) do
  begin
    Keys[I].QX := Round(FCorners[I].X / Tol);
    Keys[I].QY := Round(FCorners[I].Y / Tol);
    Keys[I].QZ := Round(FCorners[I].Z / Tol);
    FOrder[I] := I;
  end;
  if Length(FOrder) > 1 then
    Sort(0, High(FOrder));
  SetLength(FGroupEnd, Length(FOrder));
  G0 := 0;
  while G0 <= High(FOrder) do
  begin
    G1 := G0 + 1;
    while (G1 <= High(FOrder)) and Same(FOrder[G1], FOrder[G0]) do
      Inc(G1);
    for I := G0 to G1 - 1 do
      FGroupEnd[I] := G1;
    G0 := G1;
  end;
end;

{ Per corner the normal for ALevel: 1 the face's own; higher levels
  average the faces at the corner whose angle to this face is small
  enough (as the STL viewer). The result is not changed afterwards
  (a new array for another level), so it can be used outside the lock. }
function TStlModel.CornerNormals(ALevel: Integer): TStlVecArray;
var
  N: TStlVecArray;
  Threshold, SX, SY, SZ, Len: Double;
  G0, G1, I, J, Face, Other: Integer;
begin
  ALevel := EnsureRange(ALevel, 1, 10);
  FLock.Acquire;
  try
    if (FShadeLevel = ALevel) and (Length(FCornerN) = Length(FCorners)) then
      Exit(FCornerN);
    SetLength(N, Length(FCorners));
    for I := 0 to High(N) do
      N[I] := FFaceN[I div 3];
    if (ALevel > 1) and (Length(N) > 0) then
    begin
      if Length(FOrder) <> Length(FCorners) then
        BuildWeld;
      Threshold := 1.0 - ((ALevel - 1) / 9.0) * 0.65;
      G0 := 0;
      while G0 <= High(FOrder) do
      begin
        G1 := FGroupEnd[G0];
        if G1 - G0 > 1 then
          for I := G0 to G1 - 1 do
          begin
            Face := FOrder[I] div 3;
            SX := 0;
            SY := 0;
            SZ := 0;
            for J := G0 to G1 - 1 do
            begin
              Other := FOrder[J] div 3;
              if FFaceN[Other].X * FFaceN[Face].X + FFaceN[Other].Y * FFaceN[Face].Y
                + FFaceN[Other].Z * FFaceN[Face].Z >= Threshold then
              begin
                SX := SX + FFaceN[Other].X;
                SY := SY + FFaceN[Other].Y;
                SZ := SZ + FFaceN[Other].Z;
              end;
            end;
            Len := Sqrt(SX * SX + SY * SY + SZ * SZ);
            if Len > 1e-12 then
              N[FOrder[I]] := Vec(SX / Len, SY / Len, SZ / Len);
          end;
        G0 := G1;
      end;
    end;
    FCornerN := N;
    FShadeLevel := ALevel;
    Result := N;
  finally
    FLock.Release;
  end;
end;

{ ---- Drawing ---- }

type
  TMat3 = array[0..2, 0..2] of Double;

  { One picture being drawn. Model coordinates are scaled first:
    Q = (P - centre) / radius. Eye: M * Q; x right, y up, z towards the
    eye (larger = nearer). }
  TRaster = record
    W, H: Integer;
    S: Double;                    { picture pixels per unit }
    M: TMat3;
    ZBuf: array of Single;
    Col: array of TBGRAPixel;
    Par: array of Byte;           { the section's surface count, odd = inside }
    Section: Boolean;
    PN: array[0..2] of Double;    { the kept side's normal (scaled space) }
    PC: Double;                   { distance = PN . Q - PC; kept: >= 0 }
    FrontPositive: Boolean;       { a positive distance is towards the eye }
    LX, LY, LZ: Double;           { the light, eye space }
  end;

procedure EyeOf(const R: TRaster; QX, QY, QZ: Double; out EX, EY, EZ: Double); inline;
begin
  EX := R.M[0, 0] * QX + R.M[0, 1] * QY + R.M[0, 2] * QZ;
  EY := R.M[1, 0] * QX + R.M[1, 1] * QY + R.M[1, 2] * QZ;
  EZ := R.M[2, 0] * QX + R.M[2, 1] * QY + R.M[2, 2] * QZ;
end;

function Shade(const R: TRaster; NX, NY, NZ: Double): Double; inline;
var
  EX, EY, EZ: Double;
begin
  EyeOf(R, NX, NY, NZ, EX, EY, EZ);
  { Two-sided: the side looked at is lit. }
  Result := 0.30 + 0.75 * Abs(EX * R.LX + EY * R.LY + EZ * R.LZ);
end;

function ShadeColour(AIntensity: Double): TBGRAPixel; inline;
begin
  Result.red := Min(255, Round(255 * BaseR * AIntensity));
  Result.green := Min(255, Round(255 * BaseG * AIntensity));
  Result.blue := Min(255, Round(255 * BaseB * AIntensity));
  Result.alpha := 255;
end;

{ A line from A to B (scaled model space), depth tested with ABias,
  blended with AAlpha; AClip: left out where the section cuts. }
procedure DrawLine3(var R: TRaster; AX, AY, AZ, BX, BY, BZ: Double; const AColour: TBGRAPixel;
  AAlpha: Double; AWidth: Integer; ABias: Double; AClip: Boolean);
var
  EX0, EY0, EZ0, EX1, EY1, EZ1: Double;
  X0, Y0, X1, Y1, DA, DB, T, X, Y, Z, D: Double;
  Steps, I, PX, PY, OX, OY, Half, Idx: Integer;
  A256, B256: Integer;
  C: TBGRAPixel;
begin
  EyeOf(R, AX, AY, AZ, EX0, EY0, EZ0);
  EyeOf(R, BX, BY, BZ, EX1, EY1, EZ1);
  X0 := R.W / 2 + EX0 * R.S;
  Y0 := R.H / 2 - EY0 * R.S;
  X1 := R.W / 2 + EX1 * R.S;
  Y1 := R.H / 2 - EY1 * R.S;
  if (Max(X0, X1) < -AWidth) or (Min(X0, X1) > R.W + AWidth) or (Max(Y0, Y1) < -AWidth)
    or (Min(Y0, Y1) > R.H + AWidth) then
    Exit;
  DA := 0;
  DB := 0;
  if AClip and R.Section then
  begin
    DA := R.PN[0] * AX + R.PN[1] * AY + R.PN[2] * AZ - R.PC;
    DB := R.PN[0] * BX + R.PN[1] * BY + R.PN[2] * BZ - R.PC;
    if (DA < 0) and (DB < 0) then
      Exit;
  end;
  Steps := Ceil(Max(Abs(X1 - X0), Abs(Y1 - Y0)));
  if Steps < 1 then
    Steps := 1;
  if Steps > 20000 then
    Steps := 20000;
  Half := (AWidth - 1) div 2;
  A256 := EnsureRange(Round(AAlpha * 256), 0, 256);
  B256 := 256 - A256;
  for I := 0 to Steps do
  begin
    T := I / Steps;
    if AClip and R.Section then
    begin
      D := DA + (DB - DA) * T;
      if D < 0 then
        Continue;
    end;
    X := X0 + (X1 - X0) * T;
    Y := Y0 + (Y1 - Y0) * T;
    Z := EZ0 + (EZ1 - EZ0) * T;
    for OY := -Half to AWidth - 1 - Half do
    begin
      PY := Floor(Y) + OY;
      if (PY < 0) or (PY >= R.H) then
        Continue;
      for OX := -Half to AWidth - 1 - Half do
      begin
        PX := Floor(X) + OX;
        if (PX < 0) or (PX >= R.W) then
          Continue;
        Idx := PY * R.W + PX;
        if Z + ABias < R.ZBuf[Idx] then
          Continue;
        C := R.Col[Idx];
        C.red := (C.red * B256 + AColour.red * A256) shr 8;
        C.green := (C.green * B256 + AColour.green * A256) shr 8;
        C.blue := (C.blue * B256 + AColour.blue * A256) shr 8;
        R.Col[Idx] := C;
      end;
    end;
  end;
end;

{ A triangle's edge, already on the picture (pixels, depth, the plane's
  distance): the quick path for the many short edges of a mesh. }
procedure DrawEdge(var R: TRaster; X0, Y0, Z0, D0, X1, Y1, Z1, D1: Double;
  const AColour: TBGRAPixel; A256, AWidth: Integer; ABias: Double);
var
  Steps, I, PX, PY, OX, OY, Half, Idx, B256: Integer;
  DX, DY, DZ, DD, X, Y, Z, D: Double;
  C: TBGRAPixel;
begin
  if R.Section and (D0 < 0) and (D1 < 0) then
    Exit;
  if (Max(X0, X1) < -AWidth) or (Min(X0, X1) > R.W + AWidth) or (Max(Y0, Y1) < -AWidth)
    or (Min(Y0, Y1) > R.H + AWidth) then
    Exit;
  Steps := Trunc(Max(Abs(X1 - X0), Abs(Y1 - Y0))) + 1;
  if Steps > 20000 then
    Steps := 20000;
  DX := (X1 - X0) / Steps;
  DY := (Y1 - Y0) / Steps;
  DZ := (Z1 - Z0) / Steps;
  DD := (D1 - D0) / Steps;
  X := X0;
  Y := Y0;
  Z := Z0 + ABias;
  D := D0;
  B256 := 256 - A256;
  Half := (AWidth - 1) div 2;
  for I := 0 to Steps do
  begin
    if (not R.Section) or (D >= 0) then
    begin
      if AWidth = 1 then
      begin
        if (X >= 0) and (Y >= 0) and (X < R.W) and (Y < R.H) then
        begin
          Idx := Trunc(Y) * R.W + Trunc(X);
          if Z >= R.ZBuf[Idx] then
          begin
            C := R.Col[Idx];
            C.red := (C.red * B256 + AColour.red * A256) shr 8;
            C.green := (C.green * B256 + AColour.green * A256) shr 8;
            C.blue := (C.blue * B256 + AColour.blue * A256) shr 8;
            R.Col[Idx] := C;
          end;
        end;
      end
      else
        for OY := -Half to AWidth - 1 - Half do
        begin
          PY := Floor(Y) + OY;
          if (PY < 0) or (PY >= R.H) then
            Continue;
          for OX := -Half to AWidth - 1 - Half do
          begin
            PX := Floor(X) + OX;
            if (PX < 0) or (PX >= R.W) then
              Continue;
            Idx := PY * R.W + PX;
            if Z < R.ZBuf[Idx] then
              Continue;
            C := R.Col[Idx];
            C.red := (C.red * B256 + AColour.red * A256) shr 8;
            C.green := (C.green * B256 + AColour.green * A256) shr 8;
            C.blue := (C.blue * B256 + AColour.blue * A256) shr 8;
            R.Col[Idx] := C;
          end;
        end;
    end;
    X := X + DX;
    Y := Y + DY;
    Z := Z + DZ;
    D := D + DD;
  end;
end;

{ One triangle (scaled model space corners, their shading), z-buffered;
  the section's count for every pixel it covers, before the cut. }
procedure DrawTriangle(var R: TRaster; const Q0, Q1, Q2: TStlVec; I0, I1, I2: Double);
var
  E: array[0..2, 0..2] of Double;   { eye space per corner }
  SX, SY: array[0..2] of Int64;     { 1/16 pixel }
  Z, Ints, Dist: array[0..2] of Double;
  Area, T64, Ea, Eb, Ec, RowA, RowB, RowC: Int64;
  StepXA, StepXB, StepXC, StepYA, StepYB, StepYC: Int64;
  BiasA, BiasB, BiasC: Int64;
  MinX, MaxX, MinY, MaxY, PX, PY, Idx, K: Integer;
  InvArea, W0, W1, W2, ZV, D, IV: Double;
  Tmp: Double;
  C: TBGRAPixel;
  Q: array[0..2] of TStlVec;

  procedure SwapCorners(A, B: Integer);
  var
    T: Int64;
    TD: Double;
  begin
    T := SX[A]; SX[A] := SX[B]; SX[B] := T;
    T := SY[A]; SY[A] := SY[B]; SY[B] := T;
    TD := Z[A]; Z[A] := Z[B]; Z[B] := TD;
    TD := Ints[A]; Ints[A] := Ints[B]; Ints[B] := TD;
    TD := Dist[A]; Dist[A] := Dist[B]; Dist[B] := TD;
  end;

  { Edge A -> B: the pixels exactly on it belong to one of the two
    triangles sharing it (the one that runs it this way). }
  function TieBias(A, B: Integer): Int64;
  begin
    if (SY[B] > SY[A]) or ((SY[B] = SY[A]) and (SX[B] < SX[A])) then
      Result := 0
    else
      Result := 1;
  end;

begin
  Q[0] := Q0;
  Q[1] := Q1;
  Q[2] := Q2;
  Ints[0] := I0;
  Ints[1] := I1;
  Ints[2] := I2;
  for K := 0 to 2 do
  begin
    EyeOf(R, Q[K].X, Q[K].Y, Q[K].Z, E[K, 0], E[K, 1], E[K, 2]);
    Tmp := (R.W / 2 + E[K, 0] * R.S) * 16;
    if Abs(Tmp) > 1e9 then
      Exit;
    SX[K] := Round(Tmp);
    Tmp := (R.H / 2 - E[K, 1] * R.S) * 16;
    if Abs(Tmp) > 1e9 then
      Exit;
    SY[K] := Round(Tmp);
    Z[K] := E[K, 2];
    if R.Section then
      Dist[K] := R.PN[0] * Q[K].X + R.PN[1] * Q[K].Y + R.PN[2] * Q[K].Z - R.PC
    else
      Dist[K] := 1;
  end;
  Area := (SX[1] - SX[0]) * (SY[2] - SY[0]) - (SY[1] - SY[0]) * (SX[2] - SX[0]);
  if Area = 0 then
    Exit;
  if Area < 0 then
  begin
    SwapCorners(1, 2);
    Area := -Area;
  end;

  MinX := Max(0, Integer((Min(SX[0], Min(SX[1], SX[2])) - 8 + 15) div 16));
  MaxX := Min(R.W - 1, Integer(Floor((Max(SX[0], Max(SX[1], SX[2])) - 8) / 16)));
  MinY := Max(0, Integer((Min(SY[0], Min(SY[1], SY[2])) - 8 + 15) div 16));
  MaxY := Min(R.H - 1, Integer(Floor((Max(SY[0], Max(SY[1], SY[2])) - 8) / 16)));
  { (div rounds towards 0: a negative start is clamped to 0 anyway.) }
  if (MinX > MaxX) or (MinY > MaxY) then
    Exit;

  { E_ab(p) = (b.x - a.x) (p.y - a.y) - (b.y - a.y) (p.x - a.x); inside:
    all three >= 0 (with the tie rule). Ea: edge 1 -> 2 (weight of
    corner 0), Eb: 2 -> 0 (corner 1), Ec: 0 -> 1 (corner 2). }
  StepXA := -(SY[2] - SY[1]) * 16;  StepYA := (SX[2] - SX[1]) * 16;
  StepXB := -(SY[0] - SY[2]) * 16;  StepYB := (SX[0] - SX[2]) * 16;
  StepXC := -(SY[1] - SY[0]) * 16;  StepYC := (SX[1] - SX[0]) * 16;
  T64 := MinX * 16 + 8;
  RowA := (SX[2] - SX[1]) * (MinY * 16 + 8 - SY[1]) - (SY[2] - SY[1]) * (T64 - SX[1]);
  RowB := (SX[0] - SX[2]) * (MinY * 16 + 8 - SY[2]) - (SY[0] - SY[2]) * (T64 - SX[2]);
  RowC := (SX[1] - SX[0]) * (MinY * 16 + 8 - SY[0]) - (SY[1] - SY[0]) * (T64 - SX[0]);
  BiasA := TieBias(1, 2);
  BiasB := TieBias(2, 0);
  BiasC := TieBias(0, 1);
  InvArea := 1 / Area;

  for PY := MinY to MaxY do
  begin
    Ea := RowA;
    Eb := RowB;
    Ec := RowC;
    Idx := PY * R.W + MinX;
    for PX := MinX to MaxX do
    begin
      if (Ea - BiasA >= 0) and (Eb - BiasB >= 0) and (Ec - BiasC >= 0) then
      begin
        W0 := Ea * InvArea;
        W1 := Eb * InvArea;
        W2 := Ec * InvArea;
        if R.Section then
        begin
          D := W0 * Dist[0] + W1 * Dist[1] + W2 * Dist[2];
          { A surface between the plane and the eye: counted. }
          if (D <> 0) and ((D > 0) = R.FrontPositive) then
            R.Par[Idx] := R.Par[Idx] xor 1;
          if D < 0 then
          begin
            Inc(Ea, StepXA);
            Inc(Eb, StepXB);
            Inc(Ec, StepXC);
            Inc(Idx);
            Continue;
          end;
        end;
        ZV := W0 * Z[0] + W1 * Z[1] + W2 * Z[2];
        if ZV > R.ZBuf[Idx] then
        begin
          R.ZBuf[Idx] := ZV;
          IV := W0 * Ints[0] + W1 * Ints[1] + W2 * Ints[2];
          C := ShadeColour(IV);
          R.Col[Idx] := C;
        end;
      end;
      Inc(Ea, StepXA);
      Inc(Eb, StepXB);
      Inc(Ec, StepXC);
      Inc(Idx);
    end;
    Inc(RowA, StepYA);
    Inc(RowB, StepYB);
    Inc(RowC, StepYC);
  end;
end;

function TStlModel.Render(const AView: TStlView; AWidth, AHeight: Integer;
  APixelScale: Double; ACancel: TCancelCheck): TBGRABitmap;
var
  R: TRaster;
  N: TStlVecArray;
  CT, ST, CE, SE, Tilt, Len, InvR, PX, PY, PZ, VX, VY, VZ, NX, NY, NZ: Double;
  I, K, X, Y, Idx, LineW: Integer;
  Q: array[0..2] of TStlVec;
  Sh: array[0..2] of Double;
  SXs, SYs, SZs, SDs: array[0..2] of Double;
  GridZ, EX, EY, ZP, Bias, Size, RX, RY, RZ, UX, UY, UZ, OX, OY, OZ: Double;
  Back, Lines: TBGRAPixel;
  P: PBGRAPixel;

  function Scaled(const V: TStlVec): TStlVec; inline;
  begin
    Result.X := (V.X - FCenter.X) * InvR;
    Result.Y := (V.Y - FCenter.Y) * InvR;
    Result.Z := (V.Z - FCenter.Z) * InvR;
  end;

begin
  Result := nil;
  AWidth := Max(1, AWidth);
  AHeight := Max(1, AHeight);
  if APixelScale <= 0 then
    APixelScale := 1;
  R.W := AWidth;
  R.H := AHeight;
  R.S := Min(AWidth, AHeight) / 2 * FitPart;
  InvR := 1 / FRadius;

  { M = Rx(Tilt - 90) * Rz(Turn): first around the vertical axis, then
    tilted towards the eye (the STL viewer's glRotatef pair). }
  CT := Cos(DegToRad(AView.Turn));
  ST := Sin(DegToRad(AView.Turn));
  Tilt := DegToRad(AView.Tilt - 90);
  CE := Cos(Tilt);
  SE := Sin(Tilt);
  R.M[0, 0] := CT;        R.M[0, 1] := -ST;       R.M[0, 2] := 0;
  R.M[1, 0] := CE * ST;   R.M[1, 1] := CE * CT;   R.M[1, 2] := -SE;
  R.M[2, 0] := SE * ST;   R.M[2, 1] := SE * CT;   R.M[2, 2] := CE;

  Len := Sqrt(0.3 * 0.3 + 0.5 * 0.5 + 1);
  R.LX := 0.3 / Len;
  R.LY := 0.5 / Len;
  R.LZ := 1 / Len;

  { The plane: its normal from the two tilts; through the centre moved
    along the normal by PlanePos % of the radius (1 here). Flip keeps
    the other side (the same plane). }
  R.Section := AView.Section and (Length(FCorners) > 0);
  PX := Sin(DegToRad(AView.PlaneY));
  PY := -Sin(DegToRad(AView.PlaneX)) * Cos(DegToRad(AView.PlaneY));
  PZ := Cos(DegToRad(AView.PlaneX)) * Cos(DegToRad(AView.PlaneY));
  R.PC := AView.PlanePos / 100;
  if AView.Flip then
  begin
    PX := -PX;
    PY := -PY;
    PZ := -PZ;
    R.PC := -R.PC;
  end;
  R.PN[0] := PX;
  R.PN[1] := PY;
  R.PN[2] := PZ;
  { The eye looks along -z (eye space): towards the eye in model space
    is the third row of M. }
  VX := R.M[2, 0];
  VY := R.M[2, 1];
  VZ := R.M[2, 2];
  R.FrontPositive := PX * VX + PY * VY + PZ * VZ > 0;

  SetLength(R.ZBuf, R.W * R.H);
  SetLength(R.Col, R.W * R.H);
  Back := BGRA(BackR, BackG, BackB, 255);
  for I := 0 to High(R.ZBuf) do
  begin
    R.ZBuf[I] := -1e30;
    R.Col[I] := Back;
  end;
  if R.Section then
  begin
    SetLength(R.Par, R.W * R.H);
    FillChar(R.Par[0], Length(R.Par), 0);
  end;

  { The model. }
  if Length(FCorners) > 0 then
  begin
    N := CornerNormals(AView.Smooth);
    for I := 0 to TriangleCount - 1 do
    begin
      if (I and $3FFF = 0) and Cancelled(ACancel) then
        Exit;
      for K := 0 to 2 do
      begin
        Q[K] := Scaled(FCorners[I * 3 + K]);
        Sh[K] := Shade(R, N[I * 3 + K].X, N[I * 3 + K].Y, N[I * 3 + K].Z);
      end;
      DrawTriangle(R, Q[0], Q[1], Q[2], Sh[0], Sh[1], Sh[2]);
    end;
  end;

  { The cut face: where the count is odd, at the plane's depth. }
  if R.Section then
  begin
    EyeOf(R, PX, PY, PZ, NX, NY, NZ);
    if Abs(NZ) > 1e-6 then
    begin
      Lines := ShadeColour(0.30 + 0.75 * Abs(NX * R.LX + NY * R.LY + NZ * R.LZ));
      for Y := 0 to R.H - 1 do
      begin
        EY := (R.H / 2 - (Y + 0.5)) / R.S;
        Idx := Y * R.W;
        for X := 0 to R.W - 1 do
        begin
          if R.Par[Idx] <> 0 then
          begin
            EX := (X + 0.5 - R.W / 2) / R.S;
            ZP := (R.PC - NX * EX - NY * EY) / NZ;
            if ZP > R.ZBuf[Idx] then
            begin
              R.ZBuf[Idx] := ZP;
              R.Col[Idx] := Lines;
            end;
          end;
          Inc(Idx);
        end;
      end;
    end;
  end;
  if Cancelled(ACancel) then
    Exit;

  LineW := Max(1, Round(APixelScale));
  { The build plate and the axes (never cut). }
  GridZ := (FMin.Z - FCenter.Z) * InvR;
  if AView.Grid then
    for I := -5 to 5 do
    begin
      DrawLine3(R, I / 5, -1, GridZ, I / 5, 1, GridZ, BGRA(64, 71, 82), 1, LineW, 0, False);
      DrawLine3(R, -1, I / 5, GridZ, 1, I / 5, GridZ, BGRA(64, 71, 82), 1, LineW, 0, False);
    end;
  DrawLine3(R, 0, 0, GridZ, 0.7, 0, GridZ, BGRA(255, 51, 51), 1, 2 * LineW, 0, False);
  DrawLine3(R, 0, 0, GridZ, 0, 0.7, GridZ, BGRA(51, 255, 51), 1, 2 * LineW, 0, False);
  DrawLine3(R, 0, 0, GridZ, 0, 0, GridZ + 0.7, BGRA(51, 128, 255), 1, 2 * LineW, 0, False);

  { The edges: light lines a little in front of their faces. }
  if AView.Edges and (Length(FCorners) > 0) then
  begin
    Lines := BGRA(Round(255 * 0.614), Round(255 * 0.62), Round(255 * 0.615));
    Bias := 1.5 / R.S * LineW;
    for I := 0 to TriangleCount - 1 do
    begin
      if (I and $3FFF = 0) and Cancelled(ACancel) then
        Exit;
      for K := 0 to 2 do
      begin
        Q[K] := Scaled(FCorners[I * 3 + K]);
        EyeOf(R, Q[K].X, Q[K].Y, Q[K].Z, EX, EY, ZP);
        SXs[K] := R.W / 2 + EX * R.S;
        SYs[K] := R.H / 2 - EY * R.S;
        SZs[K] := ZP;
        if R.Section then
          SDs[K] := R.PN[0] * Q[K].X + R.PN[1] * Q[K].Y + R.PN[2] * Q[K].Z - R.PC
        else
          SDs[K] := 0;
      end;
      for K := 0 to 2 do
        DrawEdge(R, SXs[K], SYs[K], SZs[K], SDs[K], SXs[(K + 1) mod 3], SYs[(K + 1) mod 3],
          SZs[(K + 1) mod 3], SDs[(K + 1) mod 3], Lines, 141, LineW, Bias);
    end;
  end;

  { The plane's frame. }
  if R.Section then
  begin
    if Abs(PX) < 0.9 then
    begin
      { Right = (1, 0, 0) x N }
      RX := 0; RY := -PZ; RZ := PY;
    end
    else
    begin
      { Right = (0, 1, 0) x N }
      RX := PZ; RY := 0; RZ := -PX;
    end;
    Len := Sqrt(RX * RX + RY * RY + RZ * RZ);
    RX := RX / Len; RY := RY / Len; RZ := RZ / Len;
    UX := PY * RZ - PZ * RY;
    UY := PZ * RX - PX * RZ;
    UZ := PX * RY - PY * RX;
    OX := PX * R.PC;
    OY := PY * R.PC;
    OZ := PZ * R.PC;
    Size := 1.05;
    Lines := BGRA(115, 179, 255);
    DrawLine3(R, OX - (RX + UX) * Size, OY - (RY + UY) * Size, OZ - (RZ + UZ) * Size,
      OX + (RX - UX) * Size, OY + (RY - UY) * Size, OZ + (RZ - UZ) * Size, Lines, 0.7, LineW, 0, False);
    DrawLine3(R, OX + (RX - UX) * Size, OY + (RY - UY) * Size, OZ + (RZ - UZ) * Size,
      OX + (RX + UX) * Size, OY + (RY + UY) * Size, OZ + (RZ + UZ) * Size, Lines, 0.7, LineW, 0, False);
    DrawLine3(R, OX + (RX + UX) * Size, OY + (RY + UY) * Size, OZ + (RZ + UZ) * Size,
      OX - (RX - UX) * Size, OY - (RY - UY) * Size, OZ - (RZ - UZ) * Size, Lines, 0.7, LineW, 0, False);
    DrawLine3(R, OX - (RX - UX) * Size, OY - (RY - UY) * Size, OZ - (RZ - UZ) * Size,
      OX - (RX + UX) * Size, OY - (RY + UY) * Size, OZ - (RZ + UZ) * Size, Lines, 0.7, LineW, 0, False);
  end;

  Result := TBGRABitmap.Create(R.W, R.H);
  for Y := 0 to R.H - 1 do
  begin
    P := Result.ScanLine[Y];
    Move(R.Col[Y * R.W], P^, R.W * SizeOf(TBGRAPixel));
  end;
  Result.InvalidateBitmap;
end;

{ ---- The cache ---- }

function StlModelFor(const AKey: TImageKey; ACancel: TCancelCheck): IStlModel;
var
  I, Oldest: Integer;
  Model: TStlModel;
  Ref: IStlModel;
begin
  CacheLock.Acquire;
  try
    for I := 0 to CacheSize - 1 do
      if (Cache[I].Model <> nil) and SameImageKey(Cache[I].Key, AKey) then
      begin
        Inc(CacheClock);
        Cache[I].Used := CacheClock;
        Exit(Cache[I].Model);
      end;
  finally
    CacheLock.Release;
  end;

  Model := TStlModel.Create;
  Ref := Model;      { freed with the last reference, also on an error }
  Model.LoadFromFile(AKey.FileName, ACancel);

  CacheLock.Acquire;
  try
    { Read twice at the same time (two workers): the first one stays. }
    for I := 0 to CacheSize - 1 do
      if (Cache[I].Model <> nil) and SameImageKey(Cache[I].Key, AKey) then
      begin
        Inc(CacheClock);
        Cache[I].Used := CacheClock;
        Exit(Cache[I].Model);
      end;
    Oldest := 0;
    for I := 1 to CacheSize - 1 do
      if Cache[I].Used < Cache[Oldest].Used then
        Oldest := I;
    { The oldest goes (still alive while being drawn elsewhere). }
    Cache[Oldest].Key := AKey;
    Cache[Oldest].Model := Ref;
    Inc(CacheClock);
    Cache[Oldest].Used := CacheClock;
    Result := Ref;
  finally
    CacheLock.Release;
  end;
end;

procedure FreeCache;
var
  I: Integer;
begin
  for I := 0 to CacheSize - 1 do
    Cache[I].Model := nil;
end;

initialization
  CacheLock := TCriticalSection.Create;
  KeptView := DefaultStlView;

finalization
  FreeCache;
  FreeAndNil(CacheLock);

end.
