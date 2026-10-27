program TestGifJoin;

{
  Checks "Combine GIFs" (1.3), uGifJoin:
  - the LZW encoder: random data (the code table fills and starts
    again), one pixel, a large plain area - each decoded back by
    uGifDecoder's decoder unchanged;
  - ReadGifInfo: size and frame count; a still GIF has 1 frame; a
    file that is no GIF is refused;
  - JoinGifs: the canvas is the larger of the two, the frames of both
    plus two clearing frames (each the whole canvas, transparent,
    shown for the pause, then cleared), the smaller one centred, the
    loop count kept; the result decodes; the last frame of each keeps
    its picture through the pause; a file that is no GIF fails without
    leaving a file behind.
  - GifFrameDecode (1.3): decodes what GifLzwEncode wrote, also when
    the code table fills; a stream cut short is filled up.
  - JoinGifs with gjScaleToLarger (1.3): the smaller picture scaled to
    fit the larger one (shape kept), centred; its pictures whole-canvas
    frames; the result decodes; two of the same size come out as with
    gjOriginal; the progress is reported per frame scaled, and a cancel
    stops it without leaving a file.

  Writes its test files to the temp folder. Build and run with
  build_test.bat (needs lazbuild: BGRABitmap, through uGifDecoder).
}

{$mode ObjFPC}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces,   { the LCL's widget set: BGRABitmap links the LCL (as TestGif) }
  Classes,
  SysUtils,
  uTypes,
  uGifDecoder,
  Math,
  uGifJoin;

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

procedure PutB(S: TStream; B: Byte);
begin
  S.WriteBuffer(B, 1);
end;

procedure PutW(S: TStream; W: Integer);
begin
  PutB(S, W and $FF);
  PutB(S, W shr 8);
end;

{ A GIF of AW x AH with AFrames frames (a band moving right), a global
  4-colour table, delay 1/10 s, looping forever if ALoop. }
procedure WriteTestGif(const AFileName: string; AW, AH, AFrames: Integer; ALoop: Boolean);
var
  S: TFileStream;
  F, X, Y: Integer;
  Px: array of Byte;
  Data: TBytes;
begin
  S := TFileStream.Create(AFileName, fmCreate);
  try
    S.WriteBuffer(PAnsiChar('GIF89a')^, 6);
    PutW(S, AW);
    PutW(S, AH);
    PutB(S, $F1);            { global table, 4 colours }
    PutB(S, 0);
    PutB(S, 0);
    PutB(S, 0); PutB(S, 0); PutB(S, 0);
    PutB(S, 255); PutB(S, 0); PutB(S, 0);
    PutB(S, 0); PutB(S, 0); PutB(S, 255);
    PutB(S, 255); PutB(S, 255); PutB(S, 255);
    if ALoop then
    begin
      PutB(S, $21); PutB(S, $FF); PutB(S, 11);
      S.WriteBuffer(PAnsiChar('NETSCAPE2.0')^, 11);
      PutB(S, 3); PutB(S, 1); PutW(S, 0); PutB(S, 0);
    end;
    SetLength(Px, AW * AH);
    for F := 0 to AFrames - 1 do
    begin
      for Y := 0 to AH - 1 do
        for X := 0 to AW - 1 do
          if X div Max(1, AW div AFrames) = F then
            Px[Y * AW + X] := 1
          else
            Px[Y * AW + X] := 0;
      PutB(S, $21); PutB(S, $F9); PutB(S, 4);
      PutB(S, 0); PutW(S, 10); PutB(S, 0); PutB(S, 0);
      PutB(S, $2C);
      PutW(S, 0); PutW(S, 0); PutW(S, AW); PutW(S, AH);
      PutB(S, 0);
      Data := GifLzwEncode(Px, 2);
      S.WriteBuffer(Data[0], Length(Data));
    end;
    PutB(S, $3B);
  finally
    S.Free;
  end;
end;

function LoadGif(const AFileName: string; out AError: string): TGifAnimation;
var
  S: TFileStream;
  D: TBytes;
  More, Incomplete: Boolean;
begin
  S := TFileStream.Create(AFileName, fmOpenRead);
  try
    SetLength(D, S.Size);
    S.ReadBuffer(D[0], S.Size);
  finally
    S.Free;
  end;
  Result := DecodeGif(@D[0], Length(D), True, False, Int64(1) shl 30, nil, More, Incomplete, AError);
end;

procedure FrameRoundTrip(const ALabel: string; const APixels: array of Byte; AMin: Integer);
var
  Back: TBytes;
begin
  Back := GifFrameDecode(GifLzwEncode(APixels, AMin), Length(APixels), 0);
  Check(ALabel, (Length(Back) = Length(APixels))
    and CompareMem(@APixels[0], @Back[0], Length(APixels)));
end;

function SameFiles(const A, B: string): Boolean;
var
  L: TStringList;
  SA, SB: string;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(A);
    SA := L.Text;
    L.LoadFromFile(B);
    SB := L.Text;
  finally
    L.Free;
  end;
  Result := SA = SB;
end;

procedure LzwRoundTrip(const ALabel: string; const APixels: array of Byte; AMin: Integer);
var
  Enc, Payload: TBytes;
  Back: array of Byte;
  P, L, Got: Integer;
begin
  Enc := GifLzwEncode(APixels, AMin);
  SetLength(Payload, Length(Enc));
  L := 0;
  P := 1;
  while (P < Length(Enc)) and (Enc[P] <> 0) do
  begin
    Move(Enc[P + 1], Payload[L], Enc[P]);
    Inc(L, Enc[P]);
    Inc(P, Enc[P] + 1);
  end;
  SetLength(Back, Length(APixels) + 1);
  Got := GifLzwDecode(@Payload[0], L, AMin, @Back[0], Length(APixels), nil);
  Check(ALabel, (Enc[0] = AMin) and (Got = Length(APixels))
    and CompareMem(@APixels[0], @Back[0], Length(APixels)), Format('%d of %d', [Got, Length(APixels)]));
end;

type
  { Counts the progress calls; asks to stop at frame CancelAt (-1: never). }
  TProgressProbe = class
    Calls, Frames, CancelAt: Integer;
    procedure Progress(ADone, AFrames: Integer; var ACancel: Boolean);
  end;

procedure TProgressProbe.Progress(ADone, AFrames: Integer; var ACancel: Boolean);
begin
  Inc(Calls);
  Frames := AFrames;
  ACancel := (CancelAt >= 0) and (ADone >= CancelAt);
end;

var
  Probe: TProgressProbe;
  Dir, A, B, Still, Bad, Output, Error: string;
  Px: array of Byte;
  I: Integer;
  Info: TGifInfo;
  Anim: TGifAnimation;
  L: TStringList;
  Ok: Boolean;

begin
  PassCount := 0;
  FailCount := 0;
  Dir := IncludeTrailingPathDelimiter(GetTempDir) + 'vv_testgifjoin' + PathDelim;
  ForceDirectories(Dir);
  A := Dir + 'a.gif';
  B := Dir + 'b.gif';
  Still := Dir + 'still.gif';
  Bad := Dir + 'bad.gif';
  Output := Dir + 'a_b.gif';
  DeleteFile(Output);

  WriteLn('LZW');
  RandSeed := 7;
  SetLength(Px, 200000);
  for I := 0 to High(Px) do
    Px[I] := Random(16);
  LzwRoundTrip('random, 200000 pixels (the table fills)', Px, 4);
  SetLength(Px, 1);
  Px[0] := 3;
  LzwRoundTrip('one pixel', Px, 2);
  SetLength(Px, 640 * 480);
  FillChar(Px[0], Length(Px), 0);
  LzwRoundTrip('640 x 480 of one colour', Px, 2);
  Check('... and small', Length(GifLzwEncode(Px, 2)) < 4000, IntToStr(Length(GifLzwEncode(Px, 2))));
  FrameRoundTrip('frame decode: 640 x 480 of one colour', Px, 2);
  SetLength(Px, 200000);
  for I := 0 to High(Px) do
    Px[I] := Random(256);
  FrameRoundTrip('frame decode: random, 256 colours (the table fills)', Px, 8);
  Check('frame decode: a stream cut short is filled up',
    Length(GifFrameDecode(GifLzwEncode([1, 2, 3], 2), 10, 7)) = 10);

  WriteLn('Reading');
  WriteTestGif(A, 120, 80, 5, True);
  WriteTestGif(B, 60, 100, 4, False);
  WriteTestGif(Still, 30, 30, 1, False);
  L := TStringList.Create;
  L.Add('no gif');
  L.SaveToFile(Bad);
  L.Free;
  Check('a: 120 x 80, 5 frames', ReadGifInfo(A, Info) and (Info.Width = 120) and (Info.Height = 80)
    and (Info.Frames = 5), Format('%d x %d, %d', [Info.Width, Info.Height, Info.Frames]));
  Check('a still GIF: 1 frame', ReadGifInfo(Still, Info) and (Info.Frames = 1));
  Check('no GIF: refused', not ReadGifInfo(Bad, Info));

  WriteLn('Joining');
  Check('a + b joined', JoinGifs(A, B, Output, 500, Error), Error);
  Check('the result: 120 x 100, 5 + 4 + 2 frames', ReadGifInfo(Output, Info) and (Info.Width = 120)
    and (Info.Height = 100) and (Info.Frames = 11), Format('%d x %d, %d', [Info.Width, Info.Height,
    Info.Frames]));
  Anim := LoadGif(Output, Error);
  Check('the result decodes', Anim <> nil, Error);
  if Anim <> nil then
  try
    Check('loops as the first one (forever)', Anim.PlayCount = 0, IntToStr(Anim.PlayCount));
    Check('a centred: its frames 10 lower', (Anim.Frames(0).X = 0) and (Anim.Frames(0).Y = 10));
    Check('b centred: its frames 30 to the right', (Anim.Frames(6).X = 30) and (Anim.Frames(6).Y = 0));
    Check('clearing frames: the whole canvas, transparent, the pause, cleared',
      (Anim.Frames(5).W = 120) and (Anim.Frames(5).H = 100) and (Anim.Frames(5).Transparent = 0)
      and (Anim.Frames(5).Disposal = 2) and (Anim.FrameDelayMs(5) = 500)
      and (Anim.Frames(10).Disposal = 2) and (Anim.FrameDelayMs(10) = 500));
    Check('the last frame of each stays through the pause',
      (Anim.Frames(4).Disposal = 1) and (Anim.Frames(9).Disposal = 1));
    Ok := True;
    for I := 0 to 3 do
      if Anim.FrameDelayMs(I) <> 100 then
        Ok := False;
    Check('the frames keep their delays', Ok);
  finally
    Anim.Free;
  end;
  DeleteFile(Output);
  Check('no GIF: fails', not JoinGifs(A, Bad, Output, 500, Error), Error);
  Check('... and leaves no file', not FileExists(Output) and not FileExists(Output + '.part'));

  WriteLn('Joining, scaled to the larger');
  { a: 120 x 80 (the larger picture), b: 60 x 100 -> 48 x 80, centred. }
  Check('a + b joined, scaled', JoinGifs(A, B, Output, 500, gjScaleToLarger, Error), Error);
  Check('the result: 120 x 80, 5 + 4 + 2 frames', ReadGifInfo(Output, Info) and (Info.Width = 120)
    and (Info.Height = 80) and (Info.Frames = 11), Format('%d x %d, %d', [Info.Width, Info.Height,
    Info.Frames]));
  Anim := LoadGif(Output, Error);
  Check('the scaled result decodes', Anim <> nil, Error);
  if Anim <> nil then
  try
    Check('a as it was: whole canvas, not moved', (Anim.Frames(0).X = 0) and (Anim.Frames(0).Y = 0)
      and (Anim.Frames(0).W = 120) and (Anim.Frames(0).H = 80));
    Check('b scaled to 48 x 80, centred (36 to the right)', (Anim.Frames(6).X = 36)
      and (Anim.Frames(6).Y = 0) and (Anim.Frames(6).W = 48) and (Anim.Frames(6).H = 80),
      Format('%d, %d, %d x %d', [Anim.Frames(6).X, Anim.Frames(6).Y, Anim.Frames(6).W,
      Anim.Frames(6).H]));
    Check('b keeps its delays', Anim.FrameDelayMs(6) = 100, IntToStr(Anim.FrameDelayMs(6)));
  finally
    Anim.Free;
  end;
  { Progress and cancel (1.3: the scaling runs on a thread). }
  DeleteFile(Output);
  Probe := TProgressProbe.Create;
  try
    Probe.CancelAt := -1;
    Check('scaled with progress', JoinGifs(A, B, Output, 500, gjScaleToLarger, Error,
      @Probe.Progress), Error);
    Check('progress: once per frame of b (4)', (Probe.Calls = 4) and (Probe.Frames = 4),
      Format('%d calls, %d frames', [Probe.Calls, Probe.Frames]));
    DeleteFile(Output);
    Probe.Calls := 0;
    Probe.CancelAt := 2;
    Check('cancelled at frame 2: fails, "Cancelled"', (not JoinGifs(A, B, Output, 500,
      gjScaleToLarger, Error, @Probe.Progress)) and (Error = 'Cancelled'), Error);
    Check('... and leaves no file', not FileExists(Output) and not FileExists(Output + '.part'));
  finally
    Probe.Free;
  end;

  { The same size twice: nothing to scale, the same file as without. }
  DeleteFile(Output);
  JoinGifs(A, A, Output, 500, Error);
  JoinGifs(A, A, Output + '2.gif', 500, gjScaleToLarger, Error);
  Check('the same size: as without scaling', FileExists(Output) and SameFiles(Output, Output + '2.gif'));
  DeleteFile(Output);
  DeleteFile(Output + '2.gif');

  DeleteFile(A);
  DeleteFile(B);
  DeleteFile(Still);
  DeleteFile(Bad);

  WriteLn;
  WriteLn('=====================');
  WriteLn(PassCount, ' passed, ', FailCount, ' failed');
  if FailCount > 0 then
    ExitCode := 1;
end.
