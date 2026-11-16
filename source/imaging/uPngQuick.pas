unit uPngQuick;

{
  Unit: uPngQuick

  Purpose
  -------
  The quick view of a large PNG without WIC (1.4, Linux port). WIC reads
  a large PNG scaled down on Windows; BGRABitmap's reader decodes every
  pixel (a 21600 x 21600 PNG: 466 MP, about 2 GB and tens of seconds),
  and its inflate (paszlib, Pascal) is the slow part. Here the system's
  zlib (libz.so.1, in every Linux) inflates, the rows are unfiltered one
  at a time, and F x F blocks are averaged on the way: only the reduced
  picture is ever held.

  Owns
  ----
  - The libz handle (loaded once, on first use, never freed).

  Knows
  -----
  - TCancelCheck (uTypes).

  Responsibilities
  ----------------
  - DecodePngReduced: the PNG in memory, reduced by a whole factor F
    (each pixel the average of an F x F block of the file).
  - PngQuickAvailable: libz could be loaded.

  Does NOT
  --------
  - Read the file (the caller does, with the I/O gate), or fit the
    result to the screen (ShrinkToSize does that).
  - Handle interlaced PNGs, grey or palette images below 8 bits per
    pixel, or animation: nil, and the caller uses BGRABitmap's reader.
    Gamma and a single transparent colour (tRNS for grey / RGB) are
    ignored: a quick view.

  Threads
  -------
  Any; no shared state but the libz handle, loaded under a lock.

  Uses (MView units)
  ------------------
  interface:      uTypes
  Libraries:      Classes, SysUtils, Math, SyncObjs, ctypes, dynlibs, BGRABitmap,
                  BGRABitmapTypes

  Used by
  -------
  uMediaLoader (LoadPngScreen)
}

{$mode ObjFPC}{$H+}
{$R-}{$Q-}

interface

uses
  Classes,
  SysUtils,
  BGRABitmap,
  BGRABitmapTypes,
  uTypes;

{ AData: the whole PNG file. Returns (Width div F) x (Height div F), F
  the largest whole factor (at most MaxFactor) that still leaves at
  least AMinWidth x AMinHeight, at least 1. AFullWidth / AFullHeight:
  the size in the file. nil if this reader can't (see Does NOT, or
  damaged data) or if ACancel said stop (ACancelled then True). }
function DecodePngReduced(AData: TMemoryStream; AMinWidth, AMinHeight: Integer;
  ACancel: TCancelCheck; out AFullWidth, AFullHeight: Integer;
  out ACancelled: Boolean): TBGRABitmap;

function PngQuickAvailable: Boolean;

implementation

uses
  Math,
  SyncObjs,
  ctypes,
  dynlibs;

const
  { F x F x 255 must fit the 32-bit block sums. }
  MaxFactor = 1024;
  { Rows between two cancel checks. }
  CancelEveryRows = 64;

{ ---- libz, loaded at run time ---- }

{$PACKRECORDS C}
type
  TZStream = record
    next_in: PByte;
    avail_in: cuint;
    total_in: culong;
    next_out: PByte;
    avail_out: cuint;
    total_out: culong;
    msg: PAnsiChar;
    state: Pointer;
    zalloc: Pointer;
    zfree: Pointer;
    opaque: Pointer;
    data_type: cint;
    adler: culong;
    reserved: culong;
  end;
{$PACKRECORDS DEFAULT}

  TInflateInit = function(var AStream: TZStream; AVersion: PAnsiChar;
    AStreamSize: cint): cint; cdecl;
  TInflate = function(var AStream: TZStream; AFlush: cint): cint; cdecl;
  TInflateEnd = function(var AStream: TZStream): cint; cdecl;

const
  Z_OK = 0;
  Z_STREAM_END = 1;
  Z_BUF_ERROR = -5;
  Z_NO_FLUSH = 0;

var
  ZLock: TCriticalSection;
  ZTried: Boolean = False;
  ZLib: TLibHandle = NilHandle;
  ZInflateInit: TInflateInit = nil;
  ZInflate: TInflate = nil;
  ZInflateEnd: TInflateEnd = nil;

procedure LoadZLib;
begin
  ZLock.Acquire;
  try
    if ZTried then
      Exit;
    ZTried := True;
    {$IFDEF UNIX}
    ZLib := LoadLibrary('libz.so.1');
    if ZLib = NilHandle then
      ZLib := LoadLibrary('libz.so');
    {$ENDIF}
    if ZLib = NilHandle then
      Exit;
    Pointer(ZInflateInit) := GetProcedureAddress(ZLib, 'inflateInit_');
    Pointer(ZInflate) := GetProcedureAddress(ZLib, 'inflate');
    Pointer(ZInflateEnd) := GetProcedureAddress(ZLib, 'inflateEnd');
    if not (Assigned(ZInflateInit) and Assigned(ZInflate) and Assigned(ZInflateEnd)) then
    begin
      ZInflateInit := nil;
      ZInflate := nil;
      ZInflateEnd := nil;
    end;
  finally
    ZLock.Release;
  end;
end;

function PngQuickAvailable: Boolean;
begin
  if not ZTried then
    LoadZLib;
  Result := Assigned(ZInflate);
end;

{ ---- The reader ---- }

function BE32(P: PByte): Cardinal; inline;
begin
  Result := (Cardinal(P[0]) shl 24) or (Cardinal(P[1]) shl 16)
    or (Cardinal(P[2]) shl 8) or Cardinal(P[3]);
end;

procedure Unfilter(AFilter: Byte; ACur, APrev: PByte; ALength, ABpp: Integer); inline;
var
  I, A, B, C, Pa, Pb, Pc, Pr: Integer;
begin
  case AFilter of
    1:
      for I := ABpp to ALength - 1 do
        ACur[I] := Byte(ACur[I] + ACur[I - ABpp]);
    2:
      for I := 0 to ALength - 1 do
        ACur[I] := Byte(ACur[I] + APrev[I]);
    3:
      begin
        for I := 0 to ABpp - 1 do
          ACur[I] := Byte(ACur[I] + (APrev[I] shr 1));
        for I := ABpp to ALength - 1 do
          ACur[I] := Byte(ACur[I] + ((Integer(ACur[I - ABpp]) + APrev[I]) shr 1));
      end;
    4:
      begin
        for I := 0 to ABpp - 1 do
          ACur[I] := Byte(ACur[I] + APrev[I]);
        for I := ABpp to ALength - 1 do
        begin
          A := ACur[I - ABpp];
          B := APrev[I];
          C := APrev[I - ABpp];
          Pr := A + B - C;
          Pa := Abs(Pr - A);
          Pb := Abs(Pr - B);
          Pc := Abs(Pr - C);
          if (Pa <= Pb) and (Pa <= Pc) then
            Pr := A
          else if Pb <= Pc then
            Pr := B
          else
            Pr := C;
          ACur[I] := Byte(ACur[I] + Pr);
        end;
      end;
  end;
end;

function DecodePngReduced(AData: TMemoryStream; AMinWidth, AMinHeight: Integer;
  ACancel: TCancelCheck; out AFullWidth, AFullHeight: Integer;
  out ACancelled: Boolean): TBGRABitmap;
var
  Mem: PByte;
  Size, Pos, ChunkEnd: Int64;
  ChunkLen: Cardinal;
  ChunkType: string[4];
  W, H: Int64;
  BitDepth, ColorType, Interlace: Byte;
  Channels, SampleBytes, Bpp, RowBytes: Integer;
  Palette: array[0..255] of TBGRAPixel;
  F, OutW, OutH, X, Y, BX, K, OutY: Integer;
  Z: TZStream;
  ZOpen, Failed: Boolean;
  IdatPos: Int64;        { the next IDAT chunk to feed, or -1 }
  Cur, Prev, Swap, S: PByte;
  Sums: array of Cardinal;
  SumP: PCardinal;
  Dst: PBGRAPixel;
  Div2: Cardinal;
  R, G, B, A: Cardinal;
  I: Integer;

  { Points Z at the next IDAT's data; False if there is none. }
  function FeedNextIdat: Boolean;
  var
    L: Cardinal;
    T: string[4];
  begin
    Result := False;
    while (IdatPos >= 0) and (IdatPos + 8 <= Size) do
    begin
      L := BE32(Mem + IdatPos);
      SetLength(T, 4);
      Move((Mem + IdatPos + 4)^, T[1], 4);
      if IdatPos + 12 + Int64(L) > Size then
      begin
        IdatPos := -1;
        Exit;
      end;
      if T = 'IDAT' then
      begin
        Z.next_in := Mem + IdatPos + 8;
        Z.avail_in := L;
        IdatPos := IdatPos + 12 + Int64(L);
        if L > 0 then
          Exit(True);
      end
      else if T = 'IEND' then
      begin
        IdatPos := -1;
        Exit;
      end
      else
        IdatPos := IdatPos + 12 + Int64(L);
    end;
    IdatPos := -1;
  end;

  { Fills ACount bytes at ADest from the deflate stream. }
  function Fill(ADest: PByte; ACount: Integer): Boolean;
  var
    Ret: cint;
  begin
    Result := False;
    while ACount > 0 do
    begin
      if Z.avail_in = 0 then
        if not FeedNextIdat then
          Exit;
      Z.next_out := ADest;
      Z.avail_out := ACount;
      Ret := ZInflate(Z, Z_NO_FLUSH);
      Inc(ADest, ACount - Integer(Z.avail_out));
      ACount := Z.avail_out;
      if Ret = Z_STREAM_END then
        Exit(ACount = 0);
      if (Ret <> Z_OK) and (Ret <> Z_BUF_ERROR) then
        Exit;
    end;
    Result := True;
  end;

begin
  Result := nil;
  ACancelled := False;
  AFullWidth := 0;
  AFullHeight := 0;
  if not PngQuickAvailable then
    Exit;

  Mem := PByte(AData.Memory);
  Size := AData.Size;
  if (Size < 8 + 25) or (Mem[0] <> $89) or (Mem[1] <> Ord('P')) or (Mem[2] <> Ord('N'))
    or (Mem[3] <> Ord('G')) then
    Exit;

  { The chunks before the image data: IHDR, PLTE, tRNS. }
  W := 0;
  H := 0;
  BitDepth := 0;
  ColorType := 0;
  Interlace := 0;
  FillChar(Palette, SizeOf(Palette), 0);
  for I := 0 to 255 do
    Palette[I].alpha := 255;
  IdatPos := -1;
  Pos := 8;
  SetLength(ChunkType, 4);
  while Pos + 12 <= Size do
  begin
    ChunkLen := BE32(Mem + Pos);
    Move((Mem + Pos + 4)^, ChunkType[1], 4);
    ChunkEnd := Pos + 12 + Int64(ChunkLen);
    if ChunkEnd > Size then
      Exit;
    if ChunkType = 'IHDR' then
    begin
      if ChunkLen < 13 then
        Exit;
      W := BE32(Mem + Pos + 8);
      H := BE32(Mem + Pos + 12);
      BitDepth := Mem[Pos + 16];
      ColorType := Mem[Pos + 17];
      Interlace := Mem[Pos + 20];
    end
    else if ChunkType = 'PLTE' then
    begin
      for I := 0 to Integer(ChunkLen div 3) - 1 do
        if I <= 255 then
        begin
          Palette[I].red := Mem[Pos + 8 + I * 3];
          Palette[I].green := Mem[Pos + 8 + I * 3 + 1];
          Palette[I].blue := Mem[Pos + 8 + I * 3 + 2];
        end;
    end
    else if (ChunkType = 'tRNS') and (ColorType = 3) then
    begin
      for I := 0 to Integer(ChunkLen) - 1 do
        if I <= 255 then
          Palette[I].alpha := Mem[Pos + 8 + I];
    end
    else if ChunkType = 'IDAT' then
    begin
      IdatPos := Pos;
      Break;
    end
    else if ChunkType = 'IEND' then
      Break;
    Pos := ChunkEnd;
  end;
  if (IdatPos < 0) or (W <= 0) or (H <= 0) or (W > High(Integer) div 8)
    or (H > High(Integer)) or (Interlace <> 0) then
    Exit;

  case ColorType of
    0: Channels := 1;
    2: Channels := 3;
    3: Channels := 1;
    4: Channels := 2;
    6: Channels := 4;
  else
    Exit;
  end;
  if ColorType = 3 then
  begin
    if BitDepth <> 8 then
      Exit;
  end
  else if (BitDepth <> 8) and (BitDepth <> 16) then
    Exit;
  SampleBytes := BitDepth div 8;
  Bpp := Channels * SampleBytes;
  RowBytes := Integer(W) * Bpp;

  F := 1;
  if (AMinWidth > 0) and (AMinHeight > 0) then
    F := Max(1, Min(Integer(W) div AMinWidth, Integer(H) div AMinHeight));
  if F > MaxFactor then
    F := MaxFactor;
  OutW := Integer(W) div F;
  OutH := Integer(H) div F;
  if (OutW <= 0) or (OutH <= 0) then
    Exit;
  Div2 := Cardinal(F) * Cardinal(F);

  AFullWidth := Integer(W);
  AFullHeight := Integer(H);

  FillChar(Z, SizeOf(Z), 0);
  ZOpen := False;
  Failed := True;
  Cur := nil;
  Prev := nil;
  try
    if ZInflateInit(Z, '1.2.11', SizeOf(Z)) <> Z_OK then
      Exit;
    ZOpen := True;
    { The filter byte, then the row; Prev starts as a row of zeros. }
    Cur := AllocMem(RowBytes + 1);
    Prev := AllocMem(RowBytes + 1);
    SetLength(Sums, OutW * 4);
    Result := TBGRABitmap.Create(OutW, OutH);

    for Y := 0 to Integer(H) - 1 do
    begin
      if (Y mod CancelEveryRows = 0) and Assigned(ACancel) and ACancel() then
      begin
        ACancelled := True;
        Exit;
      end;
      if not Fill(Cur, RowBytes + 1) then
        Exit;
      if Cur[0] > 4 then
        Exit;
      Unfilter(Cur[0], Cur + 1, Prev + 1, RowBytes, Bpp);

      OutY := Y div F;
      if OutY < OutH then
      begin
        { This row into its blocks. 16 bits: the high byte. }
        S := Cur + 1;
        SumP := @Sums[0];
        for BX := 0 to OutW - 1 do
        begin
          R := 0;
          G := 0;
          B := 0;
          A := 0;
          for K := 1 to F do
          begin
            case ColorType of
              0:
                begin
                  Inc(R, S[0]);
                  Inc(A, 255);
                end;
              2:
                begin
                  Inc(R, S[0]);
                  Inc(G, S[SampleBytes]);
                  Inc(B, S[2 * SampleBytes]);
                  Inc(A, 255);
                end;
              3:
                begin
                  Inc(R, Palette[S[0]].red);
                  Inc(G, Palette[S[0]].green);
                  Inc(B, Palette[S[0]].blue);
                  Inc(A, Palette[S[0]].alpha);
                end;
              4:
                begin
                  Inc(R, S[0]);
                  Inc(A, S[SampleBytes]);
                end;
              6:
                begin
                  Inc(R, S[0]);
                  Inc(G, S[SampleBytes]);
                  Inc(B, S[2 * SampleBytes]);
                  Inc(A, S[3 * SampleBytes]);
                end;
            end;
            Inc(S, Bpp);
          end;
          if (ColorType = 0) or (ColorType = 4) then
          begin
            G := R;
            B := R;
          end;
          Inc(SumP[0], R);
          Inc(SumP[1], G);
          Inc(SumP[2], B);
          Inc(SumP[3], A);
          Inc(SumP, 4);
        end;

        { The block row is complete: out it goes. }
        if (Y + 1) mod F = 0 then
        begin
          Dst := Result.ScanLine[OutY];
          SumP := @Sums[0];
          for X := 0 to OutW - 1 do
          begin
            Dst^.red := Byte(SumP[0] div Div2);
            Dst^.green := Byte(SumP[1] div Div2);
            Dst^.blue := Byte(SumP[2] div Div2);
            Dst^.alpha := Byte(SumP[3] div Div2);
            Inc(Dst);
            Inc(SumP, 4);
          end;
          FillChar(Sums[0], Length(Sums) * SizeOf(Cardinal), 0);
        end;
      end
      else
        Break;   { the rows below the last whole block: not needed }

      Swap := Prev;
      Prev := Cur;
      Cur := Swap;
    end;
    Result.InvalidateBitmap;
    Failed := False;
  finally
    if ZOpen then
      ZInflateEnd(Z);
    FreeMem(Cur);
    FreeMem(Prev);
    if Failed then
      FreeAndNil(Result);
  end;
end;

initialization
  ZLock := TCriticalSection.Create;

finalization
  { Not freed: a decode may still be running while the process ends;
    the library stays loaded for the same reason. }

end.
