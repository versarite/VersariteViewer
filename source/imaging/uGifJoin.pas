unit uGifJoin;

{
  Unit: uGifJoin

  Purpose
  -------
  "Combine GIFs" (1.3, user): two animated GIFs into one - the first
  one's frames, a short pause, the second one's frames, a short pause,
  round again. The frames are copied as they are (no new colours, no
  quality lost, fast); only the frames' places, the timing and the
  clearing between the two are written anew.

  Owns
  ----
  Nothing between calls: the files' bytes and the frame lists of one
  call.

  Knows
  -----
  The GIF format (GIF87a / GIF89a): header, logical screen, colour
  tables, extensions (graphic control, NETSCAPE2.0 loop), image
  descriptors with their LZW data.

  Responsibilities
  ----------------
  - ReadGifInfo: the size and the frame count of a GIF (False: not a
    GIF, or damaged before its first frame).
  - JoinGifs: the canvas is the larger of the two (each animation
    centred on it); every frame gets its own colour table (its own, or
    its file's global one), so nothing is converted.
    With gjScaleToLarger (1.3, user: "Scaled to largest GIF"), the GIF
    with the smaller picture is first scaled to fit the larger one's
    (aspect ratio kept; centred, so a different shape leaves a border):
    its frames are decoded (LZW), resampled (bilinear when enlarged, the
    average of the pixels covered when made smaller; the transparent
    pixels from the nearest one, so edges stay sharp), mapped back to
    their own colour table and encoded again. Same colour tables, but
    the pixels are new: resolution is lost (said so in the menu). Between the two,
    and at the end before the loop, a "clearing" frame: the whole
    canvas, all transparent (the picture before stays on screen for the
    pause), disposed to the background afterwards, so nothing of the
    first animation shows through the second. The frame before it keeps
    its picture (disposal "leave"). The loop count is the first file's
    (else the second's; none: played once).

  Does NOT
  --------
  Check that the files are animated or different (the caller says why
  not, TMView.CombineGifs). Decode pixels only for gjScaleToLarger.

  Threads
  -------
  Any (no shared state).
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  Math;

type
  TGifInfo = record
    Width, Height: Integer;
    Frames: Integer;
  end;

  { The two sizes as they are (the frames copied unchanged), or the
    smaller picture scaled to fit the larger one (1.3). }
  TGifJoinSize = (gjOriginal, gjScaleToLarger);

  { Progress while scaling (1.3: it can take a while - a worker thread
    does it, TMView shows how far): frame ADone of AFrames; ACancel set
    True stops it (JoinGifs then fails with "Cancelled"). Called on the
    joining thread. }
  TGifJoinProgress = procedure(ADone, AFrames: Integer; var ACancel: Boolean) of object;

{ The size and frame count of AFileName; False if it is no GIF that can
  be read. }
function ReadGifInfo(const AFileName: string; out AInfo: TGifInfo): Boolean;

{ AFirst's frames, then ASecond's, into AOutput (overwritten). APauseMs:
  the pause after each of the two (rounded to 1/100 s). False with the
  reason in AError. }
function JoinGifs(const AFirst, ASecond, AOutput: string; APauseMs: Integer;
  out AError: string): Boolean; overload;
function JoinGifs(const AFirst, ASecond, AOutput: string; APauseMs: Integer;
  ASize: TGifJoinSize; out AError: string; AProgress: TGifJoinProgress = nil): Boolean; overload;

{ LZW for GIF (the clearing frame; public for the tests): APixels (each
  < 2^AMinCodeSize) as sub-blocks, the minimum code size byte first,
  ending with the 0 block. }
function GifLzwEncode(const APixels: array of Byte; AMinCodeSize: Integer): TBytes;
{ The other way (public for the tests): AData as in a frame (the minimum
  code size byte, the sub-blocks); ACount pixels, those missing in a
  short or damaged stream set to AFill. }
function GifFrameDecode(const AData: TBytes; ACount: Integer; AFill: Byte): TBytes;

implementation

type
  TGifFrameBytes = record
    HasControl: Boolean;
    Disposal: Integer;            { 0 .. 7 }
    UserInput: Boolean;
    HasTransparent: Boolean;
    Transparent: Byte;
    Delay: Integer;               { 1/100 s }
    Left, Top, Width, Height: Integer;
    Interlaced: Boolean;
    Table: TBytes;                { its colour table (its own, else the file's) }
    TableBits: Integer;           { the size field: 2^(TableBits + 1) entries }
    Data: TBytes;                 { LZW minimum code size and the sub-blocks with the 0 block }
  end;

  TGifFile = record
    Width, Height: Integer;
    Loop: TBytes;                 { the whole NETSCAPE2.0 extension, or empty }
    Frames: array of TGifFrameBytes;
  end;

  EGifJoin = class(Exception);

function ReadAll(const AFileName: string): TBytes;
var
  S: TFileStream;
begin
  Result := nil;
  S := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, S.Size);
    if S.Size > 0 then
      S.ReadBuffer(Result[0], S.Size);
  finally
    S.Free;
  end;
end;

{ Reads the frames. AFrameLimit > 0: stops after that many (the info). A
  file cut off after some whole frames keeps them (as the viewer plays
  it); one without any frame is refused. }
procedure ParseGif(const AData: TBytes; out AFile: TGifFile; AFrameLimit: Integer = 0);
var
  P, Size, Count, N, Start, BlockLen: Integer;
  GlobalTable: TBytes;
  GlobalBits: Integer;
  Control: TGifFrameBytes;
  ControlSet: Boolean;
  Frame: TGifFrameBytes;
  Bits, Lzw, Kind: Byte;

  function Need(ACount: Integer): Boolean;
  begin
    Result := P + ACount <= Size;
  end;

  function Word16(AAt: Integer): Integer;
  begin
    Result := AData[AAt] or (AData[AAt + 1] shl 8);
  end;

  function IsNetscape(AAt: Integer): Boolean;
  const
    Id: string = 'NETSCAPE2.0';
  var
    K: Integer;
  begin
    for K := 1 to 11 do
      if AData[AAt + K - 1] <> Ord(Id[K]) then
        Exit(False);
    Result := True;
  end;

  { Past the sub-blocks from P (to after the 0 block); False: cut off. }
  function SkipBlocks: Boolean;
  begin
    Result := False;
    while P < Size do
    begin
      BlockLen := AData[P];
      Inc(P);
      if BlockLen = 0 then
        Exit(True);
      if not Need(BlockLen) then
        Exit;
      Inc(P, BlockLen);
    end;
  end;

begin
  AFile.Width := 0;
  AFile.Height := 0;
  AFile.Loop := nil;
  AFile.Frames := nil;
  Size := Length(AData);
  if (Size < 13) or (AData[0] <> Ord('G')) or (AData[1] <> Ord('I')) or (AData[2] <> Ord('F')) then
    raise EGifJoin.Create('not a GIF file');
  AFile.Width := Word16(6);
  AFile.Height := Word16(8);
  Bits := AData[10];
  P := 13;
  GlobalTable := nil;
  GlobalBits := 0;
  if Bits and $80 <> 0 then
  begin
    GlobalBits := Bits and 7;
    N := 3 * (1 shl (GlobalBits + 1));
    if not Need(N) then
      raise EGifJoin.Create('damaged GIF file');
    SetLength(GlobalTable, N);
    Move(AData[P], GlobalTable[0], N);
    Inc(P, N);
  end;

  Count := 0;
  ControlSet := False;
  Control := Default(TGifFrameBytes);
  while P < Size do
  begin
    Kind := AData[P];
    Inc(P);
    case Kind of
      $3B:
        Break;
      $21:
        begin
          if not Need(1) then
            Break;
          Start := P - 1;
          if (AData[P] = $F9) and Need(7) and (AData[P + 1] = 4) then
          begin
            { Graphic control: for the next image. }
            Control := Default(TGifFrameBytes);
            Control.HasControl := True;
            Bits := AData[P + 2];
            Control.Disposal := (Bits shr 2) and 7;
            Control.UserInput := Bits and 2 <> 0;
            Control.HasTransparent := Bits and 1 <> 0;
            Control.Delay := Word16(P + 3);
            Control.Transparent := AData[P + 5];
            ControlSet := True;
            Inc(P, 1);
            if not SkipBlocks then
              Break;
          end
          else if (AData[P] = $FF) and Need(13) and (AData[P + 1] = 11)
            and IsNetscape(P + 2) then
          begin
            Inc(P, 1);
            if not SkipBlocks then
              Break;
            if Length(AFile.Loop) = 0 then
            begin
              SetLength(AFile.Loop, P - Start);
              Move(AData[Start], AFile.Loop[0], P - Start);
            end;
          end
          else
          begin
            { Comments, text, other applications: left out. }
            Inc(P, 1);
            if not SkipBlocks then
              Break;
          end;
        end;
      $2C:
        begin
          if not Need(9) then
            Break;
          if ControlSet then
            Frame := Control
          else
            Frame := Default(TGifFrameBytes);
          ControlSet := False;
          Frame.Left := Word16(P);
          Frame.Top := Word16(P + 2);
          Frame.Width := Word16(P + 4);
          Frame.Height := Word16(P + 6);
          Bits := AData[P + 8];
          Frame.Interlaced := Bits and $40 <> 0;
          Inc(P, 9);
          if Bits and $80 <> 0 then
          begin
            Frame.TableBits := Bits and 7;
            N := 3 * (1 shl (Frame.TableBits + 1));
            if not Need(N) then
              Break;
            SetLength(Frame.Table, N);
            Move(AData[P], Frame.Table[0], N);
            Inc(P, N);
          end
          else
          begin
            Frame.Table := Copy(GlobalTable);
            Frame.TableBits := GlobalBits;
          end;
          if not Need(1) then
            Break;
          Lzw := AData[P];
          if (Lzw < 2) or (Lzw > 11) then
            Break;
          Start := P;
          Inc(P);
          if not SkipBlocks then
            Break;
          { A frame without colours (no table anywhere): grey levels, as
            viewers do. }
          if Length(Frame.Table) = 0 then
          begin
            Frame.TableBits := 7;
            SetLength(Frame.Table, 768);
            for N := 0 to 255 do
            begin
              Frame.Table[N * 3] := N;
              Frame.Table[N * 3 + 1] := N;
              Frame.Table[N * 3 + 2] := N;
            end;
          end;
          SetLength(Frame.Data, P - Start);
          Move(AData[Start], Frame.Data[0], P - Start);
          SetLength(AFile.Frames, Count + 1);
          AFile.Frames[Count] := Frame;
          Inc(Count);
          if (AFrameLimit > 0) and (Count >= AFrameLimit) then
            Break;
        end;
    else
      Break;     { garbage: what was read so far }
    end;
  end;
  if Count = 0 then
    raise EGifJoin.Create('no picture in the GIF file');
end;

function ReadGifInfo(const AFileName: string; out AInfo: TGifInfo): Boolean;
var
  G: TGifFile;
begin
  AInfo.Width := 0;
  AInfo.Height := 0;
  AInfo.Frames := 0;
  try
    ParseGif(ReadAll(AFileName), G);
    AInfo.Width := G.Width;
    AInfo.Height := G.Height;
    AInfo.Frames := Length(G.Frames);
    Result := True;
  except
    Result := False;
  end;
end;

{ ---- Writing ---- }

type
  TByteWriter = record
    Data: TBytes;
    Count: Integer;
  end;

procedure PutByte(var W: TByteWriter; AValue: Byte);
begin
  if W.Count >= Length(W.Data) then
    SetLength(W.Data, Max(1024, Length(W.Data) * 2));
  W.Data[W.Count] := AValue;
  Inc(W.Count);
end;

procedure PutWord(var W: TByteWriter; AValue: Integer);
begin
  PutByte(W, AValue and $FF);
  PutByte(W, (AValue shr 8) and $FF);
end;

procedure PutBytes(var W: TByteWriter; const ABytes: TBytes);
begin
  if Length(ABytes) = 0 then
    Exit;
  if W.Count + Length(ABytes) > Length(W.Data) then
    SetLength(W.Data, Max(W.Count + Length(ABytes), Length(W.Data) * 2));
  Move(ABytes[0], W.Data[W.Count], Length(ABytes));
  Inc(W.Count, Length(ABytes));
end;

function GifLzwEncode(const APixels: array of Byte; AMinCodeSize: Integer): TBytes;
const
  HashSize = 5003;
  MaxCode = 4095;
var
  Out: TByteWriter;
  Block: array[0..254] of Byte;
  BlockLen: Integer;
  BitBuf: LongWord;
  BitCount: Integer;
  CodeSize, ClearCode, EndCode, NextCode, Prefix, I, H: Integer;
  HashKey: array[0..HashSize - 1] of LongInt;   { (prefix shl 8) or pixel; -1 empty }
  HashCode: array[0..HashSize - 1] of Integer;
  Key: LongInt;
  Found: Boolean;
  C: Byte;

  procedure FlushBlock;
  var
    K: Integer;
  begin
    if BlockLen = 0 then
      Exit;
    PutByte(Out, BlockLen);
    for K := 0 to BlockLen - 1 do
      PutByte(Out, Block[K]);
    BlockLen := 0;
  end;

  procedure Emit(ACode: Integer);
  begin
    BitBuf := BitBuf or (LongWord(ACode) shl BitCount);
    Inc(BitCount, CodeSize);
    while BitCount >= 8 do
    begin
      Block[BlockLen] := BitBuf and $FF;
      Inc(BlockLen);
      if BlockLen = 255 then
        FlushBlock;
      BitBuf := BitBuf shr 8;
      Dec(BitCount, 8);
    end;
  end;

  procedure ResetTable;
  begin
    FillChar(HashKey, SizeOf(HashKey), $FF);
    FillChar(HashCode, SizeOf(HashCode), 0);
    CodeSize := AMinCodeSize + 1;
    NextCode := EndCode + 1;
  end;

begin
  Out.Data := nil;
  Out.Count := 0;
  BlockLen := 0;
  BitBuf := 0;
  BitCount := 0;
  if AMinCodeSize < 2 then
    AMinCodeSize := 2;
  ClearCode := 1 shl AMinCodeSize;
  EndCode := ClearCode + 1;
  PutByte(Out, AMinCodeSize);
  ResetTable;
  Emit(ClearCode);
  if Length(APixels) > 0 then
  begin
    Prefix := APixels[0];
    for I := 1 to High(APixels) do
    begin
      C := APixels[I];
      Key := (LongInt(Prefix) shl 8) or C;
      H := (Key * 31 + C) mod HashSize;
      if H < 0 then
        Inc(H, HashSize);
      Found := False;
      while HashKey[H] <> -1 do
      begin
        if HashKey[H] = Key then
        begin
          Found := True;
          Break;
        end;
        Inc(H);
        if H = HashSize then
          H := 0;
      end;
      if Found then
      begin
        Prefix := HashCode[H];
        Continue;
      end;
      Emit(Prefix);
      if NextCode <= MaxCode then
      begin
        HashKey[H] := Key;
        HashCode[H] := NextCode;
        Inc(NextCode);
        { The decoder widens its codes once the next code needs a bit
          more; it adds its entry one code later than here. }
        if (NextCode > (1 shl CodeSize)) and (CodeSize < 12) then
          Inc(CodeSize);
      end
      else
      begin
        Emit(ClearCode);
        ResetTable;
      end;
      Prefix := C;
    end;
    Emit(Prefix);
  end;
  Emit(EndCode);
  if BitCount > 0 then
  begin
    Block[BlockLen] := BitBuf and $FF;
    Inc(BlockLen);
  end;
  FlushBlock;
  PutByte(Out, 0);
  SetLength(Out.Data, Out.Count);
  Result := Out.Data;
end;

function GifFrameDecode(const AData: TBytes; ACount: Integer; AFill: Byte): TBytes;
const
  MaxCodes = 4096;
var
  Prefix: array[0..MaxCodes - 1] of SmallInt;
  Suffix: array[0..MaxCodes - 1] of Byte;
  Stack: array[0..MaxCodes] of Byte;
  P, Size, BlockLeft, MinCode, CodeSize, ClearCode, EndCode, NextCode: Integer;
  Code, InCode, OldCode, Top, Written, I: Integer;
  BitBuf: LongWord;
  BitCount: Integer;
  First: Byte;
  Done: Boolean;

  { The next byte of the sub-blocks; -1 at their end. }
  function NextByte: Integer;
  begin
    while BlockLeft = 0 do
    begin
      if P >= Size then
        Exit(-1);
      BlockLeft := AData[P];
      Inc(P);
      if BlockLeft = 0 then
      begin
        P := Size;      { the 0 block: the end }
        Exit(-1);
      end;
    end;
    if P >= Size then
      Exit(-1);
    Result := AData[P];
    Inc(P);
    Dec(BlockLeft);
  end;

  function ReadCode: Integer;
  var
    B: Integer;
  begin
    while BitCount < CodeSize do
    begin
      B := NextByte;
      if B < 0 then
        Exit(-1);
      BitBuf := BitBuf or (LongWord(B) shl BitCount);
      Inc(BitCount, 8);
    end;
    Result := BitBuf and ((1 shl CodeSize) - 1);
    BitBuf := BitBuf shr CodeSize;
    Dec(BitCount, CodeSize);
  end;

  procedure Put(AValue: Byte);
  begin
    if Written < ACount then
    begin
      Result[Written] := AValue;
      Inc(Written);
    end;
  end;

begin
  Result := nil;
  if ACount <= 0 then
    Exit;
  SetLength(Result, ACount);
  FillChar(Result[0], ACount, AFill);
  Size := Length(AData);
  if Size < 2 then
    Exit;
  MinCode := AData[0];
  if (MinCode < 2) or (MinCode > 11) then
    Exit;
  P := 1;
  BlockLeft := 0;
  BitBuf := 0;
  BitCount := 0;
  ClearCode := 1 shl MinCode;
  EndCode := ClearCode + 1;
  CodeSize := MinCode + 1;
  NextCode := EndCode + 1;
  OldCode := -1;
  First := 0;
  Written := 0;
  for I := 0 to ClearCode - 1 do
  begin
    Prefix[I] := -1;
    Suffix[I] := I;
  end;
  Done := False;
  while (not Done) and (Written < ACount) do
  begin
    Code := ReadCode;
    if (Code < 0) or (Code = EndCode) then
      Break;
    if Code = ClearCode then
    begin
      CodeSize := MinCode + 1;
      NextCode := EndCode + 1;
      OldCode := -1;
      Continue;
    end;
    if OldCode < 0 then
    begin
      if Code >= ClearCode then
        Break;           { damaged: a string before any }
      Put(Code);
      OldCode := Code;
      First := Code;
      Continue;
    end;
    InCode := Code;
    Top := 0;
    if Code >= NextCode then
    begin
      if Code > NextCode then
        Break;           { damaged }
      Stack[Top] := First;
      Inc(Top);
      Code := OldCode;
    end;
    while Code >= ClearCode do
    begin
      if (Code >= MaxCodes) or (Top >= MaxCodes) then
      begin
        Done := True;
        Break;
      end;
      Stack[Top] := Suffix[Code];
      Inc(Top);
      Code := Prefix[Code];
    end;
    if Done or (Code < 0) then
      Break;
    First := Code;
    Stack[Top] := First;
    Inc(Top);
    while Top > 0 do
    begin
      Dec(Top);
      Put(Stack[Top]);
    end;
    if NextCode < MaxCodes then
    begin
      Prefix[NextCode] := OldCode;
      Suffix[NextCode] := First;
      Inc(NextCode);
      if (NextCode >= (1 shl CodeSize)) and (CodeSize < 12) then
        Inc(CodeSize);
    end;
    OldCode := InCode;
  end;
end;

procedure PutFrame(var W: TByteWriter; const F: TGifFrameBytes; AOffsetX, AOffsetY: Integer);
var
  Bits: Byte;
begin
  { Graphic control: always (the disposal and the delay are ours). }
  PutByte(W, $21);
  PutByte(W, $F9);
  PutByte(W, 4);
  Bits := (F.Disposal and 7) shl 2;
  if F.UserInput then
    Bits := Bits or 2;
  if F.HasTransparent then
    Bits := Bits or 1;
  PutByte(W, Bits);
  PutWord(W, EnsureRange(F.Delay, 0, 65535));
  PutByte(W, F.Transparent);
  PutByte(W, 0);
  { The image with its own colour table. }
  PutByte(W, $2C);
  PutWord(W, EnsureRange(F.Left + AOffsetX, 0, 65535));
  PutWord(W, EnsureRange(F.Top + AOffsetY, 0, 65535));
  PutWord(W, F.Width);
  PutWord(W, F.Height);
  Bits := $80 or (F.TableBits and 7);
  if F.Interlaced then
    Bits := Bits or $40;
  PutByte(W, Bits);
  PutBytes(W, F.Table);
  PutBytes(W, F.Data);
end;

{ The whole canvas, all transparent, shown APause long, then cleared. }
function ClearingFrame(AWidth, AHeight, APause: Integer): TGifFrameBytes;
var
  Pixels: array of Byte;
begin
  Result := Default(TGifFrameBytes);
  Result.HasControl := True;
  Result.Disposal := 2;
  Result.HasTransparent := True;
  Result.Transparent := 0;
  Result.Delay := APause;
  Result.Width := AWidth;
  Result.Height := AHeight;
  Result.TableBits := 0;                 { 2 colours }
  SetLength(Result.Table, 6);
  FillChar(Result.Table[0], 6, 0);
  SetLength(Pixels, AWidth * AHeight);   { all index 0 }
  if Length(Pixels) > 0 then
    FillChar(Pixels[0], Length(Pixels), 0);
  Result.Data := GifLzwEncode(Pixels, 2);
end;

{ ---- Scaling (1.3) ---- }

{ A frame's colour indices, rows top down (an interlaced frame's rows put
  in order). }
function FrameIndices(const F: TGifFrameBytes): TBytes;
var
  Raw: TBytes;
  Fill: Byte;
  Row, Pass, Y, Step: Integer;
const
  PassStart: array[0..3] of Integer = (0, 4, 2, 1);
  PassStep: array[0..3] of Integer = (8, 8, 4, 2);
begin
  if F.HasTransparent then
    Fill := F.Transparent
  else
    Fill := 0;
  Raw := GifFrameDecode(F.Data, F.Width * F.Height, Fill);
  if (not F.Interlaced) or (F.Height <= 1) then
    Exit(Raw);
  SetLength(Result, Length(Raw));
  Row := 0;
  for Pass := 0 to 3 do
  begin
    Y := PassStart[Pass];
    Step := PassStep[Pass];
    while Y < F.Height do
    begin
      Move(Raw[Row * F.Width], Result[Y * F.Width], F.Width);
      Inc(Row);
      Inc(Y, Step);
    end;
  end;
end;

type
  { The nearest colour of one table, remembered by colour (6 bits per
    channel; -1 = not asked yet). }
  TNearestCache = record
    Table: TBytes;
    Entries: array of SmallInt;
  end;

  TCanvasPixels = array of LongWord;   { $AARRGGBB }
  TCanvasList = array of TCanvasPixels;

function NearestIndex(var ACache: TNearestCache; const ATable: TBytes; AColors,
  ATransparent: Integer; R, G, B: Integer): Byte;
var
  Key, I, D, Best, BestD, DR, DG, DB: Integer;
begin
  if (Length(ACache.Entries) = 0) or (Length(ACache.Table) <> Length(ATable))
    or ((Length(ATable) > 0) and not CompareMem(@ACache.Table[0], @ATable[0], Length(ATable))) then
  begin
    ACache.Table := Copy(ATable);
    SetLength(ACache.Entries, 1 shl 18);
    for I := 0 to High(ACache.Entries) do
      ACache.Entries[I] := -1;
  end;
  Key := ((R shr 2) shl 12) or ((G shr 2) shl 6) or (B shr 2);
  if ACache.Entries[Key] >= 0 then
    Exit(ACache.Entries[Key]);
  Best := 0;
  BestD := MaxInt;
  for I := 0 to AColors - 1 do
  begin
    if I = ATransparent then
      Continue;
    DR := ATable[I * 3] - R;
    DG := ATable[I * 3 + 1] - G;
    DB := ATable[I * 3 + 2] - B;
    { Weighted a little like the eye (green most). }
    D := 2 * DR * DR + 4 * DG * DG + 3 * DB * DB;
    if D < BestD then
    begin
      BestD := D;
      Best := I;
    end;
  end;
  ACache.Entries[Key] := Best;
  Result := Best;
end;

{ The pictures as they are seen, one per call of Next: each frame drawn
  onto the canvas (its transparent pixels leave what is there), the
  canvas copied, then the frame's disposal done (2: its area cleared, 3:
  the canvas before it back). Alpha 0 = transparent, else 255. }
type
  TFrameComposer = class
  private
    FG: TGifFile;
    FCanvas: TCanvasPixels;
    FIndex: Integer;
  public
    constructor Create(const G: TGifFile);
    function Next: TCanvasPixels;
  end;

constructor TFrameComposer.Create(const G: TGifFile);
begin
  inherited Create;
  FG := G;
  SetLength(FCanvas, G.Width * G.Height);
  if Length(FCanvas) > 0 then
    FillChar(FCanvas[0], Length(FCanvas) * SizeOf(LongWord), 0);
  FIndex := 0;
end;

function TFrameComposer.Next: TCanvasPixels;
var
  Saved, Canvas: TCanvasPixels;
  X, Y, CX, CY, Colors, Transp, Idx: Integer;
  F: TGifFrameBytes;
  Src: TBytes;
  G: TGifFile;
begin
  Result := nil;
  if FIndex > High(FG.Frames) then
    Exit;
  G := FG;
  Canvas := FCanvas;
  begin
    F := G.Frames[FIndex];
    Inc(FIndex);
    Saved := nil;
    if F.Disposal = 3 then
      Saved := Copy(Canvas);
    Colors := Length(F.Table) div 3;
    if F.HasTransparent then
      Transp := F.Transparent
    else
      Transp := -1;
    Src := FrameIndices(F);
    if Colors > 0 then
      for Y := 0 to F.Height - 1 do
      begin
        CY := F.Top + Y;
        if (CY < 0) or (CY >= G.Height) then
          Continue;
        for X := 0 to F.Width - 1 do
        begin
          CX := F.Left + X;
          if (CX < 0) or (CX >= G.Width) then
            Continue;
          Idx := Src[Y * F.Width + X];
          if Idx = Transp then
            Continue;
          if Idx >= Colors then
            Idx := Colors - 1;
          Canvas[CY * G.Width + CX] := LongWord($FF000000) or (LongWord(F.Table[Idx * 3]) shl 16)
            or (LongWord(F.Table[Idx * 3 + 1]) shl 8) or F.Table[Idx * 3 + 2];
        end;
      end;
    Result := Copy(Canvas);
    case F.Disposal of
      2:
        for Y := Max(0, F.Top) to Min(G.Height, F.Top + F.Height) - 1 do
          for X := Max(0, F.Left) to Min(G.Width, F.Left + F.Width) - 1 do
            Canvas[Y * G.Width + X] := 0;
      3:
        if Length(Saved) = Length(Canvas) then
          Canvas := Saved;
    end;
  end;
  FCanvas := Canvas;
end;

{ APixels (AW x AH) scaled to ANewW x ANewH, AFactor = ANewW / AW (the
  shape kept). Transparent where the nearest pixel is (sharp edges);
  the colour bilinear when enlarged, the average of the pixels covered
  when made smaller, from the opaque pixels only. Alpha 1: the pixel is
  one source colour exactly (no new colour made); 255: a mixed one. }
function ScalePixels(const APixels: TCanvasPixels; AW, AH, ANewW, ANewH: Integer;
  AFactor: Double): TCanvasPixels;
var
  X, Y, X0, Y0, X1, Y1, IX, IY: Integer;
  SX, SY, FX, FY, WSum, SumR, SumG, SumB: Double;
  C, First: LongWord;
  AllSame, Any: Boolean;

  function At(AX, AY: Integer): LongWord;
  begin
    Result := APixels[EnsureRange(AY, 0, AH - 1) * AW + EnsureRange(AX, 0, AW - 1)];
  end;

  procedure Add(AColor: LongWord; AWeight: Double);
  begin
    if (AColor shr 24 = 0) or (AWeight <= 0) then
      Exit;
    if not Any then
    begin
      First := AColor;
      Any := True;
    end
    else if AColor <> First then
      AllSame := False;
    SumR := SumR + AWeight * ((AColor shr 16) and $FF);
    SumG := SumG + AWeight * ((AColor shr 8) and $FF);
    SumB := SumB + AWeight * (AColor and $FF);
    WSum := WSum + AWeight;
  end;

begin
  Result := nil;
  SetLength(Result, ANewW * ANewH);
  First := 0;
  for Y := 0 to ANewH - 1 do
    for X := 0 to ANewW - 1 do
    begin
      SX := (X + 0.5) / AFactor - 0.5;
      SY := (Y + 0.5) / AFactor - 0.5;
      C := At(Round(SX), Round(SY));
      if C shr 24 = 0 then
      begin
        Result[Y * ANewW + X] := 0;
        Continue;
      end;
      SumR := 0;
      SumG := 0;
      SumB := 0;
      WSum := 0;
      Any := False;
      AllSame := True;
      if AFactor >= 1 then
      begin
        X0 := Floor(SX);
        Y0 := Floor(SY);
        FX := SX - X0;
        FY := SY - Y0;
        Add(At(X0, Y0), (1 - FX) * (1 - FY));
        Add(At(X0 + 1, Y0), FX * (1 - FY));
        Add(At(X0, Y0 + 1), (1 - FX) * FY);
        Add(At(X0 + 1, Y0 + 1), FX * FY);
      end
      else
      begin
        X0 := EnsureRange(Floor(X / AFactor), 0, AW - 1);
        X1 := EnsureRange(Ceil((X + 1) / AFactor) - 1, X0, AW - 1);
        Y0 := EnsureRange(Floor(Y / AFactor), 0, AH - 1);
        Y1 := EnsureRange(Ceil((Y + 1) / AFactor) - 1, Y0, AH - 1);
        for IY := Y0 to Y1 do
          for IX := X0 to X1 do
            Add(APixels[IY * AW + IX], 1);
      end;
      { One source colour (alpha 1 marks it): exactly that one; mixed
        colours alpha 255. }
      if WSum <= 0 then
        Result[Y * ANewW + X] := (C and $00FFFFFF) or $01000000
      else if AllSame then
        Result[Y * ANewW + X] := (First and $00FFFFFF) or $01000000
      else
        Result[Y * ANewW + X] := LongWord($FF000000)
          or (LongWord(EnsureRange(Round(SumR / WSum), 0, 255)) shl 16)
          or (LongWord(EnsureRange(Round(SumG / WSum), 0, 255)) shl 8)
          or LongWord(EnsureRange(Round(SumB / WSum), 0, 255));
    end;
end;

type
  TColorCount = record
    Color: LongWord;
    Count: Integer;
  end;
  TColorCountArray = array of TColorCount;

{ Median cut: AColors into at most AMax boxes, each giving its weighted
  mean (only when a picture has more colours than a GIF table holds:
  frames that had tables of their own, seen together). }
function MedianCut(var AColors: TColorCountArray; AMax: Integer): TCanvasPixels;
type
  TBox = record
    First, Last: Integer;
  end;
var
  Boxes: array of TBox;
  I, J, B, Best, Channel, Mid: Integer;
  Lo, Hi: array[0..2] of Integer;
  Range, BestRange: Integer;
  Total, Half: Int64;
  SR, SG, SB, SN: Double;
  T: TColorCount;

  function Part(AColor: LongWord; AChannel: Integer): Integer;
  begin
    Result := (AColor shr (16 - 8 * AChannel)) and $FF;
  end;

  procedure SortBox(AFirst, ALast, AChannel: Integer);
  var
    L, R: Integer;
    Pivot: Integer;
  begin
    while AFirst < ALast do
    begin
      L := AFirst;
      R := ALast;
      Pivot := Part(AColors[(AFirst + ALast) div 2].Color, AChannel);
      repeat
        while Part(AColors[L].Color, AChannel) < Pivot do
          Inc(L);
        while Part(AColors[R].Color, AChannel) > Pivot do
          Dec(R);
        if L <= R then
        begin
          T := AColors[L];
          AColors[L] := AColors[R];
          AColors[R] := T;
          Inc(L);
          Dec(R);
        end;
      until L > R;
      if R - AFirst < ALast - L then
      begin
        SortBox(AFirst, R, AChannel);
        AFirst := L;
      end
      else
      begin
        SortBox(L, ALast, AChannel);
        ALast := R;
      end;
    end;
  end;

begin
  Result := nil;
  Boxes := nil;
  SetLength(Boxes, 1);
  Boxes[0].First := 0;
  Boxes[0].Last := High(AColors);
  while Length(Boxes) < AMax do
  begin
    { The box with the widest channel (that has two colours at least). }
    Best := -1;
    BestRange := 0;
    Channel := 0;
    for B := 0 to High(Boxes) do
    begin
      if Boxes[B].Last <= Boxes[B].First then
        Continue;
      for J := 0 to 2 do
      begin
        Lo[J] := 255;
        Hi[J] := 0;
      end;
      for I := Boxes[B].First to Boxes[B].Last do
        for J := 0 to 2 do
        begin
          Lo[J] := Min(Lo[J], Part(AColors[I].Color, J));
          Hi[J] := Max(Hi[J], Part(AColors[I].Color, J));
        end;
      for J := 0 to 2 do
      begin
        Range := Hi[J] - Lo[J];
        if Range > BestRange then
        begin
          BestRange := Range;
          Best := B;
          Channel := J;
        end;
      end;
    end;
    if Best < 0 then
      Break;
    SortBox(Boxes[Best].First, Boxes[Best].Last, Channel);
    { Split where half of the pixels are on each side. }
    Total := 0;
    for I := Boxes[Best].First to Boxes[Best].Last do
      Inc(Total, AColors[I].Count);
    Half := 0;
    Mid := Boxes[Best].First;
    for I := Boxes[Best].First to Boxes[Best].Last - 1 do
    begin
      Inc(Half, AColors[I].Count);
      Mid := I;
      if Half * 2 >= Total then
        Break;
    end;
    SetLength(Boxes, Length(Boxes) + 1);
    Boxes[High(Boxes)].First := Mid + 1;
    Boxes[High(Boxes)].Last := Boxes[Best].Last;
    Boxes[Best].Last := Mid;
  end;
  SetLength(Result, Length(Boxes));
  for B := 0 to High(Boxes) do
  begin
    SR := 0;
    SG := 0;
    SB := 0;
    SN := 0;
    for I := Boxes[B].First to Boxes[B].Last do
    begin
      SR := SR + AColors[I].Count * Part(AColors[I].Color, 0);
      SG := SG + AColors[I].Count * Part(AColors[I].Color, 1);
      SB := SB + AColors[I].Count * Part(AColors[I].Color, 2);
      SN := SN + AColors[I].Count;
    end;
    if SN <= 0 then
      SN := 1;
    Result[B] := (LongWord(Round(SR / SN)) shl 16) or (LongWord(Round(SG / SN)) shl 8)
      or LongWord(Round(SB / SN));
  end;
end;

{ The colours of a seen picture (alpha <> 0) with how often each comes. }
function CountColors(const APixels: TCanvasPixels): TColorCountArray;
var
  Sorted: TCanvasPixels;
  I, N: Integer;
  T: LongWord;

  procedure Sort(L, R: Integer);
  var
    I2, J2: Integer;
    P: LongWord;
  begin
    while L < R do
    begin
      I2 := L;
      J2 := R;
      P := Sorted[(L + R) div 2];
      repeat
        while Sorted[I2] < P do
          Inc(I2);
        while Sorted[J2] > P do
          Dec(J2);
        if I2 <= J2 then
        begin
          T := Sorted[I2];
          Sorted[I2] := Sorted[J2];
          Sorted[J2] := T;
          Inc(I2);
          Dec(J2);
        end;
      until I2 > J2;
      if J2 - L < R - I2 then
      begin
        Sort(L, J2);
        L := I2;
      end
      else
      begin
        Sort(I2, R);
        R := J2;
      end;
    end;
  end;

begin
  Result := nil;
  N := 0;
  SetLength(Sorted, Length(APixels));
  for I := 0 to High(APixels) do
    if APixels[I] shr 24 <> 0 then
    begin
      Sorted[N] := APixels[I] and $00FFFFFF;
      Inc(N);
    end;
  SetLength(Sorted, N);
  if N = 0 then
    Exit;
  Sort(0, N - 1);
  for I := 0 to N - 1 do
    if (I = 0) or (Sorted[I] <> Sorted[I - 1]) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)].Color := Sorted[I];
      Result[High(Result)].Count := 1;
    end
    else
      Inc(Result[High(Result)].Count);
end;

{ One scaled picture as a whole-canvas frame with its own table: the
  source picture's colours (exact, when they fit in 255; else reduced
  by median cut), index 0 transparent when the picture has transparent
  pixels. AScaled marks exact source colours with alpha 1, mixed ones
  with 255 (both opaque). }
function EncodePicture(const ASource, AScaled: TCanvasPixels; AW, AH: Integer;
  const ATemplate: TGifFrameBytes; var ACache: TNearestCache): TGifFrameBytes;
var
  Counts: TColorCountArray;
  Palette: TCanvasPixels;
  HasTransparent: Boolean;
  Table, Indices: TBytes;
  I, Base, N, Bits, Entries, Lo, Hi, Mid: Integer;
  C: LongWord;
  Exact: Boolean;
begin
  Result := ATemplate;
  HasTransparent := False;
  for I := 0 to High(AScaled) do
    if AScaled[I] shr 24 = 0 then
    begin
      HasTransparent := True;
      Break;
    end;
  Counts := CountColors(ASource);
  Exact := Length(Counts) <= 255;
  if Exact then
  begin
    SetLength(Palette, Length(Counts));
    for I := 0 to High(Counts) do
      Palette[I] := Counts[I].Color;
  end
  else
    Palette := MedianCut(Counts, 255);
  if Length(Palette) = 0 then
  begin
    SetLength(Palette, 1);
    Palette[0] := 0;
  end;
  Base := Ord(HasTransparent);        { index 0: transparent }
  N := Length(Palette) + Base;
  Bits := 0;
  while (1 shl (Bits + 1)) < N do
    Inc(Bits);
  Entries := 1 shl (Bits + 1);
  SetLength(Table, Entries * 3);
  FillChar(Table[0], Length(Table), 0);
  for I := 0 to High(Palette) do
  begin
    Table[(I + Base) * 3] := (Palette[I] shr 16) and $FF;
    Table[(I + Base) * 3 + 1] := (Palette[I] shr 8) and $FF;
    Table[(I + Base) * 3 + 2] := Palette[I] and $FF;
  end;
  SetLength(Indices, AW * AH);
  for I := 0 to High(AScaled) do
  begin
    C := AScaled[I];
    if C shr 24 = 0 then
      Indices[I] := 0
    else if Exact and (C shr 24 = 1) then
    begin
      { A source colour: its own entry (the palette is sorted). }
      C := C and $00FFFFFF;
      Lo := 0;
      Hi := High(Palette);
      Mid := 0;
      while Lo <= Hi do
      begin
        Mid := (Lo + Hi) div 2;
        if Palette[Mid] = C then
          Break
        else if Palette[Mid] < C then
          Lo := Mid + 1
        else
          Hi := Mid - 1;
      end;
      if (Lo <= Hi) then
        Indices[I] := Mid + Base
      else
        Indices[I] := NearestIndex(ACache, Table, N, Base - 1,
          (C shr 16) and $FF, (C shr 8) and $FF, C and $FF);
    end
    else
      Indices[I] := NearestIndex(ACache, Table, N, Base - 1,
        (C shr 16) and $FF, (C shr 8) and $FF, C and $FF);
  end;
  Result.HasControl := True;
  Result.HasTransparent := HasTransparent;
  Result.Transparent := 0;
  Result.Left := 0;
  Result.Top := 0;
  Result.Width := AW;
  Result.Height := AH;
  Result.Interlaced := False;
  Result.Table := Table;
  Result.TableBits := Bits;
  Result.Data := GifLzwEncode(Indices, Max(2, Bits + 1));
end;

{ G scaled by AFactor. Its frames often draw only what changes over the
  frame before, through transparent pixels; scaled one by one their
  edges would not meet (seams, remains of the old picture). So each
  picture as it is seen is scaled whole and written as a whole-canvas
  frame: disposal 2 when the animation has transparent pixels (each
  picture replaces the one before), else 1. }
procedure ScaleGif(var G: TGifFile; AFactor: Double; AProgress: TGifJoinProgress);
var
  Seen, Scaled: TCanvasPixels;
  K, NewW, NewH: Integer;
  Cache: TNearestCache;
  Frames: array of TGifFrameBytes;
  F: TGifFrameBytes;
  Composer: TFrameComposer;
  Cancel: Boolean;
begin
  NewW := Max(1, Round(G.Width * AFactor));
  NewH := Max(1, Round(G.Height * AFactor));
  { The factor that gives exactly that width (the height follows). }
  AFactor := NewW / G.Width;
  Cache.Table := nil;
  Cache.Entries := nil;
  SetLength(Frames, Length(G.Frames));
  { One picture at a time (1.3: all of them at once took the memory of a
    long animation many times over). }
  Composer := TFrameComposer.Create(G);
  try
    for K := 0 to High(G.Frames) do
    begin
      Cancel := False;
      if Assigned(AProgress) then
        AProgress(K, Length(G.Frames), Cancel);
      if Cancel then
        raise EGifJoin.Create('Cancelled');
      Seen := Composer.Next;
      Scaled := ScalePixels(Seen, G.Width, G.Height, NewW, NewH, AFactor);
      F := EncodePicture(Seen, Scaled, NewW, NewH, G.Frames[K], Cache);
      if F.HasTransparent then
        F.Disposal := 2
      else
        F.Disposal := 1;
      Frames[K] := F;
    end;
  finally
    Composer.Free;
  end;
  G.Frames := Frames;
  G.Width := NewW;
  G.Height := NewH;
end;

function JoinGifs(const AFirst, ASecond, AOutput: string; APauseMs: Integer;
  out AError: string): Boolean;
begin
  Result := JoinGifs(AFirst, ASecond, AOutput, APauseMs, gjOriginal, AError);
end;

function JoinGifs(const AFirst, ASecond, AOutput: string; APauseMs: Integer;
  ASize: TGifJoinSize; out AError: string; AProgress: TGifJoinProgress): Boolean;
var
  A, B: TGifFile;
  W: TByteWriter;
  Width, Height, Pause, I: Integer;
  Last: TGifFrameBytes;
  S: TFileStream;
  Temp: string;

  procedure PutAll(const G: TGifFile);
  var
    K, OX, OY: Integer;
    F: TGifFrameBytes;
  begin
    OX := (Width - G.Width) div 2;
    OY := (Height - G.Height) div 2;
    for K := 0 to High(G.Frames) do
    begin
      F := G.Frames[K];
      { The last one stays on screen through the pause; the clearing
        frame then clears the whole canvas. }
      if K = High(G.Frames) then
        F.Disposal := 1;
      PutFrame(W, F, OX, OY);
    end;
    Last := ClearingFrame(Width, Height, Pause);
    PutFrame(W, Last, 0, 0);
  end;

begin
  Result := False;
  AError := '';
  Temp := '';
  try
    ParseGif(ReadAll(AFirst), A);
    ParseGif(ReadAll(ASecond), B);
    if (A.Width <= 0) or (A.Height <= 0) or (B.Width <= 0) or (B.Height <= 0) then
      raise EGifJoin.Create('a GIF without a size');
    { The smaller picture (by area; equal: the second) scaled to fit the
      larger one, its shape kept. }
    if (ASize = gjScaleToLarger) and ((A.Width <> B.Width) or (A.Height <> B.Height)) then
    begin
      if Int64(A.Width) * A.Height >= Int64(B.Width) * B.Height then
        ScaleGif(B, Min(A.Width / B.Width, A.Height / B.Height), AProgress)
      else
        ScaleGif(A, Min(B.Width / A.Width, B.Height / A.Height), AProgress);
    end;
    Width := Max(A.Width, B.Width);
    Height := Max(A.Height, B.Height);
    if (Width <= 0) or (Height <= 0) then
      raise EGifJoin.Create('a GIF without a size');
    { At least 2/100 s (browsers make shorter delays 1/10 s). }
    Pause := Max(2, Round(APauseMs / 10));

    W.Data := nil;
    W.Count := 0;
    for I := 1 to 6 do
      PutByte(W, Ord('GIF89a'[I]));
    PutWord(W, Width);
    PutWord(W, Height);
    PutByte(W, $70);       { no global table; 8 bits per colour }
    PutByte(W, 0);
    PutByte(W, 0);
    if Length(A.Loop) > 0 then
      PutBytes(W, A.Loop)
    else if Length(B.Loop) > 0 then
      PutBytes(W, B.Loop);
    PutAll(A);
    PutAll(B);
    PutByte(W, $3B);
    SetLength(W.Data, W.Count);

    { Written beside it first: a full disk leaves no half file. }
    Temp := AOutput + '.part';
    S := TFileStream.Create(Temp, fmCreate);
    try
      S.WriteBuffer(W.Data[0], Length(W.Data));
    finally
      S.Free;
    end;
    if FileExists(AOutput) and not DeleteFile(AOutput) then
      raise EGifJoin.Create('can''t replace ' + ExtractFileName(AOutput));
    if not RenameFile(Temp, AOutput) then
      raise EGifJoin.Create('can''t write ' + ExtractFileName(AOutput));
    Result := True;
  except
    on E: Exception do
    begin
      AError := E.Message;
      if (Temp <> '') and FileExists(Temp) then
        DeleteFile(Temp);
    end;
  end;
end;

end.
