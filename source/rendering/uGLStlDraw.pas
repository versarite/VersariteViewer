unit uGLStlDraw;

{
  Unit: uGLStlDraw

  Purpose
  -------
  3D models (.stl) drawn by the graphics card (1.3, user: "apart from the
  speed it is excellent"). The software picture (uStlModel.Render) took
  its time for every turn, tilt or slider step; here the triangles go up
  to the card once, and every change is just the next frame. Same look
  as Render: the same matrix, light, colours, plane, grid, axes, edges
  and plane frame (uStlModel's shared helpers and constants), drawn into
  the same place of the picture, so zoom, pan, the picture's rotation and
  the mirror filter work as they do for the picture. Being drawn as
  lines and triangles, the model stays sharp at any zoom.

  Owns
  ----
  - The model's buffers on the card (corners, the normals of the last
    smoothing level; vertex buffer objects, else plain client arrays)
    and the reference to the model they belong to.
  - One small shader (GLSL 1.10, vertex and fragment): it places the
    model into the picture, lights it (per pixel, two-sided, the light at
    the eye as Render), cuts it at the section's plane and keeps it
    inside the picture's rectangle.

  Knows
  -----
  uStlModel (the model's data and the shared view geometry).

  Responsibilities
  ----------------
  - Draw: the picture's background, the model (z-buffered), the cut face
    closed, the grid and axes, the edges, the plane's frame.
  - The closed cut face: as Render, a point of the plane is inside the
    solid when an odd number of surfaces lie between it and the eye.
    Here: those surfaces (the eye's side of the plane) are drawn into the
    stencil buffer, each flipping its bit; then a square on the plane is
    drawn where the bit is set, depth tested like everything else.

  Does NOT
  --------
  - Read files, make pictures, decide when to draw (uGLRenderer.Paint).
  - Make GL calls outside Draw / Release (the context must be current).

  Threads
  -------
  UI thread, inside the renderer's paint.

  Used by
  -------
  uGLRenderer
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  Math,
  GL,
  uStlModel;

type
  { An OpenGL function by name (nil: not there). }
  TGLProcLoader = function(const AName: AnsiString): Pointer;

  TGLStlPainter = class(TObject)
  private
    FLoader: TGLProcLoader;
    FApiLoaded, FApiTried: Boolean;
    FProgram: GLuint;
    FTried: Boolean;
    FNote: string;
    { The model on the card. }
    FModel: IStlModel;
    FSmooth: Integer;
    FCount: Integer;             { corners }
    FVboCorners, FVboNormals: GLuint;
    FUseVbo: Boolean;
    FCorners, FNormals: TStlVecArray;   { client arrays (no VBO), or kept for a re-upload }
    FCenter: TStlVec;
    FRadius, FGridZ: Double;
    { Uniform locations. }
    FToPic, FRot, FCenterLoc, FInvR, FZScale, FZBias, FPlane, FPicW, FPicH,
      FClipOn, FSideSign, FLit, FBase, FLight: GLint;
    { Two programs (1.3, speed): True = with the fragment tests (the
      section's cut, the picture's edges: "discard"), False = without -
      a shader that can discard keeps the card from skipping hidden
      fragments early, so the plain one is used whenever it can be (no
      section, the picture's edges kept by the scissor test). FProgram
      and the locations above are the one chosen for this frame. }
    FProgs: array[Boolean] of GLuint;
    FLocs: array[Boolean] of array[0..13] of GLint;
    procedure SelectProgram(AClip: Boolean);
    function LoadApi: Boolean;
    function EnsureProgram: Boolean;
    function EnsureMesh(const AModel: IStlModel; ASmooth: Integer): Boolean;
    procedure DeleteBuffers;
    procedure BindArrays;
    procedure UnbindArrays;
  public
    constructor Create(ALoader: TGLProcLoader);
    { The card can draw models (the shader made; tried at the first call,
      the context current). }
    function Ready: Boolean;
    { AModel as AView says, into the picture of APicW x APicH pixels: the
      modelview matrix maps picture pixels to the screen (as for the
      picture's tiles), the projection is the screen's (z -1 .. 1).
      AScreenPerPic: screen pixels per picture pixel. False: could not
      (Note says why). }
    function Draw(const AModel: IStlModel; const AView: TStlView; APicW, APicH: Integer;
      AScreenPerPic: Double; AScissored: Boolean = False): Boolean;
    { The model's buffers deleted (the context current): another model. }
    procedure Release;
    { The context is gone with all it held: forgotten, no GL calls. }
    procedure ContextLost;
    property Note: string read FNote;
  end;

implementation

const
  MV_GL_VERTEX_SHADER = $8B31;
  MV_GL_FRAGMENT_SHADER = $8B30;
  MV_GL_COMPILE_STATUS = $8B81;
  MV_GL_LINK_STATUS = $8B82;
  MV_GL_ARRAY_BUFFER = $8892;
  MV_GL_STATIC_DRAW = $88E4;

  { Eye depth (about -1.5 .. 1.5 for the model, the grid's corners and
    the axes) into the screen projection's -1 .. 1. }
  ZScale = 0.3;
  { The cut face's square: half its side (the model lies within 1). }
  CapHalf = 2.0;

  VertexSource: AnsiString =
    'uniform mat4 toPic;' + LineEnding +
    'uniform mat3 rot;' + LineEnding +
    'uniform vec3 center;' + LineEnding +
    'uniform float invR, zScale, zBias;' + LineEnding +
    'uniform vec4 plane;' + LineEnding +
    'varying vec3 nEye;' + LineEnding +
    'varying vec2 pic;' + LineEnding +
    'varying float dist;' + LineEnding +
    'void main() {' + LineEnding +
    '  vec3 q = (gl_Vertex.xyz - center) * invR;' + LineEnding +
    '  vec4 p = toPic * vec4(q, 1.0);' + LineEnding +
    '  pic = p.xy;' + LineEnding +
    '  dist = dot(plane.xyz, q) - plane.w;' + LineEnding +
    '  nEye = rot * gl_Normal;' + LineEnding +
    '  gl_FrontColor = gl_Color;' + LineEnding +
    '  gl_Position = gl_ModelViewProjectionMatrix * vec4(p.x, p.y, (p.z + zBias) * zScale, 1.0);' + LineEnding +
    '}' + LineEnding;

  FragmentSource: AnsiString =
    'uniform float picW, picH, clipOn, sideSign, lit;' + LineEnding +
    'uniform vec3 base, light;' + LineEnding +
    'varying vec3 nEye;' + LineEnding +
    'varying vec2 pic;' + LineEnding +
    'varying float dist;' + LineEnding +
    'void main() {' + LineEnding +
    '  if (pic.x < 0.0 || pic.y < 0.0 || pic.x > picW || pic.y > picH) discard;' + LineEnding +
    '  if (clipOn > 0.5 && dist < 0.0) discard;' + LineEnding +
    '  if (sideSign != 0.0 && dist * sideSign <= 0.0) discard;' + LineEnding +
    '  if (lit > 0.5) {' + LineEnding +
    '    float i = 0.30 + 0.75 * abs(dot(normalize(nEye), light));' + LineEnding +
    '    gl_FragColor = vec4(min(base * i, vec3(1.0)), 1.0);' + LineEnding +
    '  } else' + LineEnding +
    '    gl_FragColor = gl_Color;' + LineEnding +
    '}' + LineEnding;

  { The same without any fragment test (see FProgs). }
  FragmentPlainSource: AnsiString =
    'uniform float lit;' + LineEnding +
    'uniform vec3 base, light;' + LineEnding +
    'varying vec3 nEye;' + LineEnding +
    'void main() {' + LineEnding +
    '  if (lit > 0.5) {' + LineEnding +
    '    float i = 0.30 + 0.75 * abs(dot(normalize(nEye), light));' + LineEnding +
    '    gl_FragColor = vec4(min(base * i, vec3(1.0)), 1.0);' + LineEnding +
    '  } else' + LineEnding +
    '    gl_FragColor = gl_Color;' + LineEnding +
    '}' + LineEnding;

type
  TCreateShader = function(AType: GLenum): GLuint; {$IFDEF WINDOWS}stdcall;{$ELSE}cdecl;{$ENDIF}
  TShaderSource = procedure(AShader: GLuint; ACount: GLsizei; AStrings: PPAnsiChar;
    ALengths: PGLint); {$IFDEF WINDOWS}stdcall;{$ELSE}cdecl;{$ENDIF}
  TObjectProc = procedure(AObject: GLuint); {$IFDEF WINDOWS}stdcall;{$ELSE}cdecl;{$ENDIF}
  TGetiv = procedure(AObject: GLuint; AName: GLenum; AParams: PGLint); {$IFDEF WINDOWS}stdcall;{$ELSE}cdecl;{$ENDIF}
  TCreateProgram = function: GLuint; {$IFDEF WINDOWS}stdcall;{$ELSE}cdecl;{$ENDIF}
  TAttachShader = procedure(AProgram, AShader: GLuint); {$IFDEF WINDOWS}stdcall;{$ELSE}cdecl;{$ENDIF}
  TGetUniformLocation = function(AProgram: GLuint; AName: PAnsiChar): GLint; {$IFDEF WINDOWS}stdcall;{$ELSE}cdecl;{$ENDIF}
  TUniform1f = procedure(ALocation: GLint; A: GLfloat); {$IFDEF WINDOWS}stdcall;{$ELSE}cdecl;{$ENDIF}
  TUniform3f = procedure(ALocation: GLint; A, B, C: GLfloat); {$IFDEF WINDOWS}stdcall;{$ELSE}cdecl;{$ENDIF}
  TUniform4f = procedure(ALocation: GLint; A, B, C, D: GLfloat); {$IFDEF WINDOWS}stdcall;{$ELSE}cdecl;{$ENDIF}
  TUniformMatrixfv = procedure(ALocation: GLint; ACount: GLsizei; ATranspose: GLboolean;
    AValue: PGLfloat); {$IFDEF WINDOWS}stdcall;{$ELSE}cdecl;{$ENDIF}
  TGenBuffers = procedure(ACount: GLsizei; ABuffers: PGLuint); {$IFDEF WINDOWS}stdcall;{$ELSE}cdecl;{$ENDIF}
  TBindBuffer = procedure(ATarget: GLenum; ABuffer: GLuint); {$IFDEF WINDOWS}stdcall;{$ELSE}cdecl;{$ENDIF}
  TBufferData = procedure(ATarget: GLenum; ASize: PtrInt; AData: Pointer; AUsage: GLenum); {$IFDEF WINDOWS}stdcall;{$ELSE}cdecl;{$ENDIF}
  TDeleteBuffers = procedure(ACount: GLsizei; ABuffers: PGLuint); {$IFDEF WINDOWS}stdcall;{$ELSE}cdecl;{$ENDIF}

var
  glCreateShaderX: TCreateShader;
  glShaderSourceX: TShaderSource;
  glCompileShaderX: TObjectProc;
  glGetShaderivX: TGetiv;
  glDeleteShaderX: TObjectProc;
  glCreateProgramX: TCreateProgram;
  glAttachShaderX: TAttachShader;
  glLinkProgramX: TObjectProc;
  glGetProgramivX: TGetiv;
  glUseProgramX: TObjectProc;
  glDeleteProgramX: TObjectProc;
  glGetUniformLocationX: TGetUniformLocation;
  glUniform1fX: TUniform1f;
  glUniform3fX: TUniform3f;
  glUniform4fX: TUniform4f;
  glUniformMatrix3fvX: TUniformMatrixfv;
  glUniformMatrix4fvX: TUniformMatrixfv;
  glGenBuffersX: TGenBuffers;
  glBindBufferX: TBindBuffer;
  glBufferDataX: TBufferData;
  glDeleteBuffersX: TDeleteBuffers;

constructor TGLStlPainter.Create(ALoader: TGLProcLoader);
begin
  inherited Create;
  FLoader := ALoader;
  FSmooth := -1;
end;

function TGLStlPainter.LoadApi: Boolean;
begin
  if FApiTried then
    Exit(FApiLoaded);
  FApiTried := True;
  Pointer(glCreateShaderX) := FLoader('glCreateShader');
  Pointer(glShaderSourceX) := FLoader('glShaderSource');
  Pointer(glCompileShaderX) := FLoader('glCompileShader');
  Pointer(glGetShaderivX) := FLoader('glGetShaderiv');
  Pointer(glDeleteShaderX) := FLoader('glDeleteShader');
  Pointer(glCreateProgramX) := FLoader('glCreateProgram');
  Pointer(glAttachShaderX) := FLoader('glAttachShader');
  Pointer(glLinkProgramX) := FLoader('glLinkProgram');
  Pointer(glGetProgramivX) := FLoader('glGetProgramiv');
  Pointer(glUseProgramX) := FLoader('glUseProgram');
  Pointer(glDeleteProgramX) := FLoader('glDeleteProgram');
  Pointer(glGetUniformLocationX) := FLoader('glGetUniformLocation');
  Pointer(glUniform1fX) := FLoader('glUniform1f');
  Pointer(glUniform3fX) := FLoader('glUniform3f');
  Pointer(glUniform4fX) := FLoader('glUniform4f');
  Pointer(glUniformMatrix3fvX) := FLoader('glUniformMatrix3fv');
  Pointer(glUniformMatrix4fvX) := FLoader('glUniformMatrix4fv');
  { Vertex buffers (OpenGL 1.5): without them, plain client arrays. }
  Pointer(glGenBuffersX) := FLoader('glGenBuffers');
  Pointer(glBindBufferX) := FLoader('glBindBuffer');
  Pointer(glBufferDataX) := FLoader('glBufferData');
  Pointer(glDeleteBuffersX) := FLoader('glDeleteBuffers');
  FUseVbo := Assigned(glGenBuffersX) and Assigned(glBindBufferX) and Assigned(glBufferDataX)
    and Assigned(glDeleteBuffersX);
  FApiLoaded := Assigned(glCreateShaderX) and Assigned(glShaderSourceX)
    and Assigned(glCompileShaderX) and Assigned(glGetShaderivX) and Assigned(glDeleteShaderX)
    and Assigned(glCreateProgramX) and Assigned(glAttachShaderX) and Assigned(glLinkProgramX)
    and Assigned(glGetProgramivX) and Assigned(glUseProgramX) and Assigned(glDeleteProgramX)
    and Assigned(glGetUniformLocationX) and Assigned(glUniform1fX) and Assigned(glUniform3fX)
    and Assigned(glUniform4fX) and Assigned(glUniformMatrix3fvX) and Assigned(glUniformMatrix4fvX);
  if not FApiLoaded then
    FNote := 'no shader functions (OpenGL 2.0)';
  Result := FApiLoaded;
end;

function TGLStlPainter.EnsureProgram: Boolean;

  function Compile(AType: GLenum; const ASource: AnsiString): GLuint;
  var
    Src: PAnsiChar;
    Status: GLint;
  begin
    Result := glCreateShaderX(AType);
    if Result = 0 then
      Exit;
    Src := PAnsiChar(ASource);
    glShaderSourceX(Result, 1, @Src, nil);
    glCompileShaderX(Result);
    Status := 0;
    glGetShaderivX(Result, MV_GL_COMPILE_STATUS, @Status);
    if Status = 0 then
    begin
      glDeleteShaderX(Result);
      Result := 0;
    end;
  end;

  { A program from the vertex source and AFragment; 0 if it fails. }
  function Build(const AFragment: AnsiString; AClip: Boolean): GLuint;
  const
    Names: array[0..13] of PAnsiChar = ('toPic', 'rot', 'center', 'invR', 'zScale',
      'zBias', 'plane', 'picW', 'picH', 'clipOn', 'sideSign', 'lit', 'base', 'light');
  var
    VS, FS: GLuint;
    Status: GLint;
    K: Integer;
  begin
    Result := 0;
    VS := Compile(MV_GL_VERTEX_SHADER, VertexSource);
    FS := Compile(MV_GL_FRAGMENT_SHADER, AFragment);
    if (VS = 0) or (FS = 0) then
    begin
      if VS <> 0 then
        glDeleteShaderX(VS);
      if FS <> 0 then
        glDeleteShaderX(FS);
      FNote := '3D shader did not compile';
      Exit;
    end;
    Result := glCreateProgramX();
    if Result = 0 then
    begin
      glDeleteShaderX(VS);
      glDeleteShaderX(FS);
      FNote := '3D shader not made';
      Exit;
    end;
    glAttachShaderX(Result, VS);
    glAttachShaderX(Result, FS);
    glLinkProgramX(Result);
    glDeleteShaderX(VS);
    glDeleteShaderX(FS);
    Status := 0;
    glGetProgramivX(Result, MV_GL_LINK_STATUS, @Status);
    if Status = 0 then
    begin
      glDeleteProgramX(Result);
      Result := 0;
      FNote := '3D shader did not link';
      Exit;
    end;
    { -1 for a name the program hasn't got: those calls do nothing. }
    for K := 0 to High(Names) do
      FLocs[AClip][K] := glGetUniformLocationX(Result, Names[K]);
  end;

begin
  Result := FProgs[True] <> 0;
  if Result or FTried then
    Exit;
  FTried := True;
  if not LoadApi then
    Exit;
  FProgs[True] := Build(FragmentSource, True);
  if FProgs[True] = 0 then
    Exit;
  FProgs[False] := Build(FragmentPlainSource, False);
  { Without the plain one: the other one always. }
  if FProgs[False] = 0 then
  begin
    FProgs[False] := FProgs[True];
    FLocs[False] := FLocs[True];
  end;
  SelectProgram(True);
  FNote := '';
  Result := True;
end;

procedure TGLStlPainter.SelectProgram(AClip: Boolean);
begin
  FProgram := FProgs[AClip];
  FToPic := FLocs[AClip][0];
  FRot := FLocs[AClip][1];
  FCenterLoc := FLocs[AClip][2];
  FInvR := FLocs[AClip][3];
  FZScale := FLocs[AClip][4];
  FZBias := FLocs[AClip][5];
  FPlane := FLocs[AClip][6];
  FPicW := FLocs[AClip][7];
  FPicH := FLocs[AClip][8];
  FClipOn := FLocs[AClip][9];
  FSideSign := FLocs[AClip][10];
  FLit := FLocs[AClip][11];
  FBase := FLocs[AClip][12];
  FLight := FLocs[AClip][13];
end;

function TGLStlPainter.Ready: Boolean;
begin
  Result := EnsureProgram;
end;

procedure TGLStlPainter.DeleteBuffers;
begin
  if FUseVbo and Assigned(glDeleteBuffersX) then
  begin
    if FVboCorners <> 0 then
      glDeleteBuffersX(1, @FVboCorners);
    if FVboNormals <> 0 then
      glDeleteBuffersX(1, @FVboNormals);
  end;
  FVboCorners := 0;
  FVboNormals := 0;
end;

procedure TGLStlPainter.Release;
begin
  DeleteBuffers;
  FModel := nil;
  FCorners := nil;
  FNormals := nil;
  FCount := 0;
  FSmooth := -1;
end;

procedure TGLStlPainter.ContextLost;
begin
  { The buffers and the program died with the context. }
  FVboCorners := 0;
  FVboNormals := 0;
  FProgram := 0;
  FProgs[False] := 0;
  FProgs[True] := 0;
  FTried := False;
  FModel := nil;
  FCorners := nil;
  FNormals := nil;
  FCount := 0;
  FSmooth := -1;
end;

{ The model's corners on the card once; the normals again when the
  smoothing level changes. }
function TGLStlPainter.EnsureMesh(const AModel: IStlModel; ASmooth: Integer): Boolean;
var
  Corners, Normals: TStlVecArray;
  NewModel: Boolean;
  Err: GLenum;
  K: Integer;
begin
  Result := True;
  NewModel := FModel <> AModel;
  if (not NewModel) and (ASmooth = FSmooth) then
    Exit;
  if NewModel then
    Release;
  AModel.MeshData(ASmooth, Corners, Normals, FCenter, FRadius, FGridZ);
  FModel := AModel;
  FSmooth := ASmooth;
  FCount := Length(Corners);
  FCorners := Corners;
  FNormals := Normals;
  if (FCount = 0) or not FUseVbo then
    Exit;
  for K := 1 to 16 do
    if glGetError() = GL_NO_ERROR then
      Break;
  if FVboCorners = 0 then
  begin
    glGenBuffersX(1, @FVboCorners);
    glBindBufferX(MV_GL_ARRAY_BUFFER, FVboCorners);
    glBufferDataX(MV_GL_ARRAY_BUFFER, PtrInt(FCount) * SizeOf(TStlVec), @FCorners[0],
      MV_GL_STATIC_DRAW);
  end;
  if FVboNormals = 0 then
    glGenBuffersX(1, @FVboNormals);
  glBindBufferX(MV_GL_ARRAY_BUFFER, FVboNormals);
  glBufferDataX(MV_GL_ARRAY_BUFFER, PtrInt(FCount) * SizeOf(TStlVec), @FNormals[0],
    MV_GL_STATIC_DRAW);
  glBindBufferX(MV_GL_ARRAY_BUFFER, 0);
  Err := glGetError();
  if Err <> GL_NO_ERROR then
  begin
    { Out of video memory, say: the client arrays from main memory. }
    DeleteBuffers;
    FUseVbo := False;
  end;
end;

procedure TGLStlPainter.BindArrays;
begin
  glEnableClientState(GL_VERTEX_ARRAY);
  glEnableClientState(GL_NORMAL_ARRAY);
  if FUseVbo and (FVboCorners <> 0) then
  begin
    glBindBufferX(MV_GL_ARRAY_BUFFER, FVboCorners);
    glVertexPointer(3, GL_FLOAT, 0, nil);
    glBindBufferX(MV_GL_ARRAY_BUFFER, FVboNormals);
    glNormalPointer(GL_FLOAT, 0, nil);
    glBindBufferX(MV_GL_ARRAY_BUFFER, 0);
  end
  else
  begin
    glVertexPointer(3, GL_FLOAT, 0, @FCorners[0]);
    glNormalPointer(GL_FLOAT, 0, @FNormals[0]);
  end;
end;

procedure TGLStlPainter.UnbindArrays;
begin
  glDisableClientState(GL_NORMAL_ARRAY);
  glDisableClientState(GL_VERTEX_ARRAY);
end;

function TGLStlPainter.Draw(const AModel: IStlModel; const AView: TStlView; APicW,
  APicH: Integer; AScreenPerPic: Double; AScissored: Boolean): Boolean;
var
  M: TStlMat3;
  S, PX, PY, PZ, PC, LX, LY, LZ, Len, OX, OY, OZ, RX, RY, RZ, UX, UY, UZ, H: Double;
  ToPic: array[0..15] of GLfloat;
  Rot: array[0..8] of GLfloat;
  R, C, I: Integer;
  Section, FrontPositive: Boolean;
  StencilBits: GLint;

  { Model space as it is (the mesh), or Q itself (lines, the cap). }
  procedure ModelSpace(AMesh: Boolean);
  begin
    if AMesh then
    begin
      glUniform3fX(FCenterLoc, FCenter.X, FCenter.Y, FCenter.Z);
      glUniform1fX(FInvR, 1 / FRadius);
    end
    else
    begin
      glUniform3fX(FCenterLoc, 0, 0, 0);
      glUniform1fX(FInvR, 1);
    end;
  end;

  procedure Line(AX, AY, AZ, BX, BY, BZ: Double);
  begin
    glVertex3f(AX, AY, AZ);
    glVertex3f(BX, BY, BZ);
  end;

begin
  Result := False;
  if (AModel = nil) or (APicW <= 0) or (APicH <= 0) then
    Exit;
  if not EnsureProgram then
    Exit;
  if not EnsureMesh(AModel, EnsureRange(AView.Smooth, 1, 10)) then
    Exit;
  if FRadius <= 0 then
    FRadius := 1;

  { Q -> picture pixels (x, y) and eye depth (z), as Render: x = W/2 +
    S * eye.x, y = H/2 - S * eye.y. Column by column for GL. }
  M := StlEyeMatrix(AView);
  S := StlPixelsPerUnit(APicW, APicH);
  for C := 0 to 2 do
  begin
    ToPic[C * 4 + 0] := S * M[0, C];
    ToPic[C * 4 + 1] := -S * M[1, C];
    ToPic[C * 4 + 2] := M[2, C];
    ToPic[C * 4 + 3] := 0;
  end;
  ToPic[12] := APicW / 2;
  ToPic[13] := APicH / 2;
  ToPic[14] := 0;
  ToPic[15] := 1;
  for R := 0 to 2 do
    for C := 0 to 2 do
      Rot[C * 3 + R] := M[R, C];

  StlPlaneOf(AView, PX, PY, PZ, PC);
  Section := AView.Section and (FCount > 0);
  { A positive distance is towards the eye (the third row of M). }
  FrontPositive := PX * M[2, 0] + PY * M[2, 1] + PZ * M[2, 2] > 0;
  if Section then
  begin
    StencilBits := 0;
    glGetIntegerv(GL_STENCIL_BITS, @StencilBits);
    if StencilBits <= 0 then
    begin
      FNote := 'no stencil buffer for the cut face';
      Exit;
    end;
  end;
  StlLight(LX, LY, LZ);
  { The plain program unless a fragment must be thrown away: the cut,
    or the picture's edges where no scissor keeps them (see FProgs). }
  SelectProgram(Section or not AScissored);

  glPushAttrib(GL_ENABLE_BIT or GL_DEPTH_BUFFER_BIT or GL_STENCIL_BUFFER_BIT
    or GL_COLOR_BUFFER_BIT or GL_LINE_BIT or GL_POLYGON_BIT or GL_CURRENT_BIT);
  try
    glDisable(GL_TEXTURE_2D);
    glDisable(GL_LIGHTING);
    glDisable(GL_CULL_FACE);
    glDisable(GL_BLEND);
    glClearDepth(1);
    glClearStencil(0);
    glClear(GL_DEPTH_BUFFER_BIT or GL_STENCIL_BUFFER_BIT);

    { The picture's background (its rectangle, under everything). }
    glDisable(GL_DEPTH_TEST);
    glDepthMask(GL_FALSE);
    glColor3ub(StlBackR, StlBackG, StlBackB);
    glBegin(GL_QUADS);
    glVertex2f(0, 0);
    glVertex2f(APicW, 0);
    glVertex2f(APicW, APicH);
    glVertex2f(0, APicH);
    glEnd;

    glUseProgramX(FProgram);
    glUniformMatrix4fvX(FToPic, 1, GL_FALSE, @ToPic[0]);
    glUniformMatrix3fvX(FRot, 1, GL_FALSE, @Rot[0]);
    glUniform1fX(FZScale, ZScale);
    glUniform1fX(FZBias, 0);
    glUniform4fX(FPlane, PX, PY, PZ, PC);
    glUniform1fX(FPicW, APicW);
    glUniform1fX(FPicH, APicH);
    glUniform3fX(FBase, StlBaseR, StlBaseG, StlBaseB);
    glUniform3fX(FLight, LX, LY, LZ);
    glUniform1fX(FSideSign, 0);

    { The model. }
    if FCount > 0 then
    begin
      ModelSpace(True);
      glUniform1fX(FLit, 1);
      if Section then
        glUniform1fX(FClipOn, 1)
      else
        glUniform1fX(FClipOn, 0);
      glEnable(GL_DEPTH_TEST);
      glDepthFunc(GL_LESS);
      glDepthMask(GL_TRUE);
      BindArrays;
      glDrawArrays(GL_TRIANGLES, 0, FCount);

      { The cut face, closed: the surfaces between the plane and the eye
        flip the stencil bit; the plane is drawn where it is odd. }
      if Section then
      begin
        glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
        glDepthMask(GL_FALSE);
        glDisable(GL_DEPTH_TEST);
        glEnable(GL_STENCIL_TEST);
        glStencilFunc(GL_ALWAYS, 0, 1);
        glStencilOp(GL_KEEP, GL_KEEP, GL_INVERT);
        glUniform1fX(FLit, 0);
        glUniform1fX(FClipOn, 0);
        if FrontPositive then
          glUniform1fX(FSideSign, 1)
        else
          glUniform1fX(FSideSign, -1);
        glDrawArrays(GL_TRIANGLES, 0, FCount);
        UnbindArrays;

        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
        glDepthMask(GL_TRUE);
        glEnable(GL_DEPTH_TEST);
        glDepthFunc(GL_LESS);
        glStencilFunc(GL_NOTEQUAL, 0, 1);
        glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);
        glUniform1fX(FSideSign, 0);
        glUniform1fX(FLit, 1);
        ModelSpace(False);
        { A square on the plane, around its point nearest the centre. }
        if Abs(PX) < 0.9 then
        begin
          RX := 0; RY := -PZ; RZ := PY;
        end
        else
        begin
          RX := PZ; RY := 0; RZ := -PX;
        end;
        Len := Sqrt(RX * RX + RY * RY + RZ * RZ);
        RX := RX / Len; RY := RY / Len; RZ := RZ / Len;
        UX := PY * RZ - PZ * RY;
        UY := PZ * RX - PX * RZ;
        UZ := PX * RY - PY * RX;
        OX := PX * PC;
        OY := PY * PC;
        OZ := PZ * PC;
        H := CapHalf;
        glNormal3f(PX, PY, PZ);
        glBegin(GL_QUADS);
        glVertex3f(OX + (-RX - UX) * H, OY + (-RY - UY) * H, OZ + (-RZ - UZ) * H);
        glVertex3f(OX + (RX - UX) * H, OY + (RY - UY) * H, OZ + (RZ - UZ) * H);
        glVertex3f(OX + (RX + UX) * H, OY + (RY + UY) * H, OZ + (RZ + UZ) * H);
        glVertex3f(OX + (-RX + UX) * H, OY + (-RY + UY) * H, OZ + (-RZ + UZ) * H);
        glEnd;
        glDisable(GL_STENCIL_TEST);
      end
      else
        UnbindArrays;
    end;

    { The build plate and the axes (never cut), depth tested, not
      written. }
    ModelSpace(False);
    glUniform1fX(FLit, 0);
    glUniform1fX(FClipOn, 0);
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LEQUAL);
    glDepthMask(GL_FALSE);
    if AView.Grid then
    begin
      glLineWidth(1);
      glColor3ub(64, 71, 82);
      glBegin(GL_LINES);
      for I := -5 to 5 do
      begin
        Line(I / 5, -1, FGridZ, I / 5, 1, FGridZ);
        Line(-1, I / 5, FGridZ, 1, I / 5, FGridZ);
      end;
      glEnd;
    end;
    glLineWidth(2);
    glBegin(GL_LINES);
    glColor3ub(255, 51, 51);
    Line(0, 0, FGridZ, 0.7, 0, FGridZ);
    glColor3ub(51, 255, 51);
    Line(0, 0, FGridZ, 0, 0.7, FGridZ);
    glColor3ub(51, 128, 255);
    Line(0, 0, FGridZ, 0, 0, FGridZ + 0.7);
    glEnd;
    glLineWidth(1);

    { The edges: light lines a little in front of their faces (about 1.5
      screen pixels, as Render's bias), blended, cut with the model. }
    if AView.Edges and (FCount > 0) then
    begin
      ModelSpace(True);
      if Section then
        glUniform1fX(FClipOn, 1);
      if AScreenPerPic > 0 then
        glUniform1fX(FZBias, 1.5 / (S * AScreenPerPic))
      else
        glUniform1fX(FZBias, 1.5 / S);
      glEnable(GL_BLEND);
      glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
      glColor4f(0.614, 0.62, 0.615, 141 / 256);
      glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
      BindArrays;
      glDrawArrays(GL_TRIANGLES, 0, FCount);
      UnbindArrays;
      glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
      glUniform1fX(FZBias, 0);
      glUniform1fX(FClipOn, 0);
      glDisable(GL_BLEND);
    end;

    { The plane's frame. }
    if Section then
    begin
      ModelSpace(False);
      if Abs(PX) < 0.9 then
      begin
        RX := 0; RY := -PZ; RZ := PY;
      end
      else
      begin
        RX := PZ; RY := 0; RZ := -PX;
      end;
      Len := Sqrt(RX * RX + RY * RY + RZ * RZ);
      RX := RX / Len; RY := RY / Len; RZ := RZ / Len;
      UX := PY * RZ - PZ * RY;
      UY := PZ * RX - PX * RZ;
      UZ := PX * RY - PY * RX;
      OX := PX * PC;
      OY := PY * PC;
      OZ := PZ * PC;
      H := 1.05;
      glEnable(GL_BLEND);
      glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
      glColor4f(115 / 255, 179 / 255, 1, 0.7);
      glBegin(GL_LINE_LOOP);
      glVertex3f(OX - (RX + UX) * H, OY - (RY + UY) * H, OZ - (RZ + UZ) * H);
      glVertex3f(OX + (RX - UX) * H, OY + (RY - UY) * H, OZ + (RZ - UZ) * H);
      glVertex3f(OX + (RX + UX) * H, OY + (RY + UY) * H, OZ + (RZ + UZ) * H);
      glVertex3f(OX - (RX - UX) * H, OY - (RY - UY) * H, OZ - (RZ - UZ) * H);
      glEnd;
      glDisable(GL_BLEND);
    end;
    Result := True;
  finally
    glUseProgramX(0);
    glPopAttrib;
    glColor4f(1, 1, 1, 1);
  end;
end;

end.
