program TestStl;

{
  Checks the 3D models (1.3): uStlModel and uStlPanel.
  - Reading: a binary and an ASCII cube (12 triangles, 10 x 10 x 10);
    a file that is neither is refused; the cache gives the same model
    for the same file.
  - Drawing: the picture's size; the model in the middle, the
    background in the corner; cut through the middle and seen from
    above, the cut face is closed (the same colour everywhere inside);
    a plane above the model leaves nothing; smoothing and the edges
    draw without trouble.
  - The panel rows: none without a model, nine with one; the sliders
    (drag position, wheel, double-click back), moving the plane turns
    the section on, the boxes; grid / edges / smoothing kept for the
    next model.

  Writes its test files to the temp folder. Build and run with
  build_test.bat (needs lazbuild: BGRABitmap).
}

{$mode ObjFPC}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces,   { the LCL's widget set: BGRABitmap links the LCL (as TestGif) }
  Classes,
  SysUtils,
  Types,
  BGRABitmap,
  BGRABitmapTypes,
  uTypes,
  uCommands,
  uDecodedImage,
  uExtensions,
  uStlModel,
  uStlPanel;

var
  PassCount, FailCount: Integer;

procedure Check(const ALabel: string; ACondition: Boolean; const ADetail: string = '');
begin
  if ACondition then
  begin
    Inc(PassCount);
    WriteLn('  PASS  ', ALabel);
  end
  else
  begin
    Inc(FailCount);
    WriteLn('  FAIL  ', ALabel);
    if ADetail <> '' then
      WriteLn('         got: ', ADetail);
  end;
end;

type
  TTri = array[0..2, 0..2] of Single;

{ A cube 0 .. 10, two triangles per face. }
function CubeTriangles: specialize TArray<TTri>;
const
  Faces: array[0..5, 0..3, 0..2] of Single = (
    ((0,0,0), (10,0,0), (10,10,0), (0,10,0)),
    ((0,0,10), (0,10,10), (10,10,10), (10,0,10)),
    ((0,0,0), (0,0,10), (10,0,10), (10,0,0)),
    ((0,10,0), (10,10,0), (10,10,10), (0,10,10)),
    ((0,0,0), (0,10,0), (0,10,10), (0,0,10)),
    ((10,0,0), (10,0,10), (10,10,10), (10,10,0)));
var
  F, K: Integer;
begin
  SetLength(Result, 12);
  for F := 0 to 5 do
    for K := 0 to 2 do
    begin
      Result[F * 2][0][K] := Faces[F, 0, K];
      Result[F * 2][1][K] := Faces[F, 1, K];
      Result[F * 2][2][K] := Faces[F, 2, K];
      Result[F * 2 + 1][0][K] := Faces[F, 0, K];
      Result[F * 2 + 1][1][K] := Faces[F, 2, K];
      Result[F * 2 + 1][2][K] := Faces[F, 3, K];
    end;
end;

procedure WriteBinary(const AFileName: string);
var
  S: TFileStream;
  Header: array[0..79] of Byte;
  Tris: specialize TArray<TTri>;
  Count: LongWord;
  I: Integer;
  Zero: array[0..2] of Single;
  Attr: Word;
begin
  Tris := CubeTriangles;
  FillChar(Header, SizeOf(Header), 0);
  Move(PAnsiChar('solid but binary')^, Header[0], 16);   { binary files may start so too }
  FillChar(Zero, SizeOf(Zero), 0);
  Attr := 0;
  S := TFileStream.Create(AFileName, fmCreate);
  try
    S.WriteBuffer(Header, 80);
    Count := Length(Tris);
    S.WriteBuffer(Count, 4);
    for I := 0 to High(Tris) do
    begin
      S.WriteBuffer(Zero, 12);
      S.WriteBuffer(Tris[I], 36);
      S.WriteBuffer(Attr, 2);
    end;
  finally
    S.Free;
  end;
end;

procedure WriteAscii(const AFileName: string);
var
  L: TStringList;
  Tris: specialize TArray<TTri>;
  I, K: Integer;
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Tris := CubeTriangles;
  L := TStringList.Create;
  try
    L.Add('solid cube');
    for I := 0 to High(Tris) do
    begin
      L.Add('  facet normal 0 0 0');
      L.Add('    outer loop');
      for K := 0 to 2 do
        L.Add(Format('      vertex %.6e %g %g', [Tris[I][K][0], Tris[I][K][1], Tris[I][K][2]], FS));
      L.Add('    endloop');
      L.Add('  endfacet');
    end;
    L.Add('endsolid cube');
    L.SaveToFile(AFileName);
  finally
    L.Free;
  end;
end;

function Px(B: TBGRABitmap; X, Y: Integer): TBGRAPixel;
begin
  Result := B.GetPixel(X, Y);
end;

function SamePx(const A, B: TBGRAPixel): Boolean;
begin
  Result := (A.red = B.red) and (A.green = B.green) and (A.blue = B.blue);
end;

function PxText(const A: TBGRAPixel): string;
begin
  Result := Format('%d,%d,%d', [A.red, A.green, A.blue]);
end;

var
  Dir, BinName, AsciiName, BadName: string;
  Model, Again: IStlModel;
  V: TStlView;
  B: TBGRABitmap;
  Back, Mid, P: TBGRAPixel;
  Ok, Raised: Boolean;
  X, Y: Integer;
  Section: TStlSection;
  L: TStringList;

begin
  PassCount := 0;
  FailCount := 0;
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'vv_teststl' + PathDelim;
  ForceDirectories(Dir);
  BinName := Dir + 'cube_bin.stl';
  AsciiName := Dir + 'cube_ascii.stl';
  BadName := Dir + 'not_a_model.stl';
  WriteBinary(BinName);
  WriteAscii(AsciiName);
  L := TStringList.Create;
  L.Add('hello, this is no model');
  L.SaveToFile(BadName);
  L.Free;

  WriteLn('Reading');
  Model := StlModelFor(MakeImageKey(BinName));
  Check('binary: 12 triangles', Model.TriangleCount = 12, IntToStr(Model.TriangleCount));
  Check('binary: 10 x 10 x 10', Model.SizeText = '10.0 x 10.0 x 10.0', Model.SizeText);
  Again := StlModelFor(MakeImageKey(BinName));
  Check('the same file: the same model (cache)', Again = Model);
  Again := StlModelFor(MakeImageKey(AsciiName));
  Check('ASCII: 12 triangles', Again.TriangleCount = 12, IntToStr(Again.TriangleCount));
  Check('ASCII: 10 x 10 x 10', Again.SizeText = '10.0 x 10.0 x 10.0', Again.SizeText);
  Raised := False;
  try
    StlModelFor(MakeImageKey(BadName));
  except
    Raised := True;
  end;
  Check('neither binary nor ASCII: refused', Raised);
  Check('IsStlFileName: .STL yes, .stla no', IsStlFileName('a.STL') and not IsStlFileName('a.stla'));

  WriteLn('Drawing');
  V := DefaultStlView;
  B := Model.Render(V, 200, 150);
  Check('the picture has the size asked for', (B.Width = 200) and (B.Height = 150));
  Back := Px(B, 1, 1);
  Mid := Px(B, 100, 75);
  Check('background in the corner', SamePx(Back, BGRA(31, 36, 43)), PxText(Back));
  Check('the model in the middle', not SamePx(Mid, Back), PxText(Mid));
  B.Free;

  { Cut through the middle, the upper half left out, seen from above:
    only the cut face is seen, closed and evenly lit. }
  V := DefaultStlView;
  V.Tilt := 90;
  V.Grid := False;
  V.Edges := False;
  V.Section := True;
  V.Flip := True;
  B := Model.Render(V, 200, 200);
  { (Off the middle: the Z axis is seen end-on there.) }
  Mid := Px(B, 115, 115);
  Ok := not SamePx(Mid, BGRA(31, 36, 43));
  for Y := 106 to 130 do
    for X := 106 to 130 do
      if not SamePx(Px(B, X, Y), Mid) then
        Ok := False;
  Check('the cut face is closed (one colour inside)', Ok, PxText(Mid));
  B.Free;

  { The plane above the model, the part above kept: nothing left. }
  V.Flip := False;
  V.PlanePos := 100;
  B := Model.Render(V, 200, 200);
  P := Px(B, 115, 115);
  Check('a plane above the model keeps nothing of it', SamePx(P, BGRA(31, 36, 43)), PxText(P));
  B.Free;

  V := DefaultStlView;
  V.Smooth := 10;
  V.Edges := True;
  B := Again.Render(V, 120, 90, 2);
  Check('smoothing 10 and edges: drawn', (B <> nil) and (B.Width = 120));
  B.Free;

  WriteLn('Panel rows');
  Section := TStlSection.Create;
  try
    Check('no model: no rows', Section.RowCount = 0);
    Section.Active := True;
    Check('a model: nine rows', Section.RowCount = StlRowCount);
    Check('kinds: Section a box, Plane X a slider',
      (Section.RowKind(StlRowSection) = srkToggle) and (Section.RowKind(StlRowPlaneX) = srkSlider));
    Section.View := DefaultStlView;
    Section.SetSliderPos(StlRowPlanePos, 1.0);
    Check('plane position at the end: 100 %, section on',
      (Section.View.PlanePos = 100) and Section.View.Section);
    Section.SetSliderPos(StlRowPlaneX, 0.5);
    Check('Plane X in the middle: 0', Section.View.PlaneX = 0, IntToStr(Section.View.PlaneX));
    Section.Wheel(StlRowSmooth, 1);
    Check('wheel on smoothing: 2', Section.View.Smooth = 2, IntToStr(Section.View.Smooth));
    Section.Wheel(StlRowElevation, -1);
    Check('wheel down on elevation: 25', Round(Section.View.Tilt) = 25);
    Section.ResetRow(StlRowElevation);
    Check('double-click: elevation back to 30', Round(Section.View.Tilt) = 30);
    Section.Click(StlRowSection, obLeft, Point(0, 0));
    Check('click on Section: off', not Section.View.Section);
    Section.Click(StlRowGrid, obLeft, Point(0, 0));
    Check('click on Grid: off', not Section.View.Grid);
    Check('grid off and smoothing 2 kept for the next model',
      (not StlStartView.Grid) and (StlStartView.Smooth = 2) and not StlStartView.Section);
    Section.Active := False;
    Check('the model gone: no rows', Section.RowCount = 0);
  finally
    Section.Free;
  end;

  Model := nil;
  Again := nil;
  DeleteFile(BinName);
  DeleteFile(AsciiName);
  DeleteFile(BadName);

  WriteLn;
  WriteLn('=====================');
  WriteLn(PassCount, ' passed, ', FailCount, ' failed');
  if FailCount > 0 then
    ExitCode := 1;
end.
