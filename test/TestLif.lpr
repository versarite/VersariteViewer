program TestLif;

{
  Checks the Leica .lif reader of the microscopy edition (M2a, Day 25),
  uLifFile:
  - a small .lif made here (a folder with a 4 x 3 two-channel stack of
    2 z-planes, an element without pixels): the images found and their
    paths, sizes, pixel size and z step, channels and colours, the
    panel's lines, one channel's plane, a plane and the maximum
    projection in colour;
  - damaged files: not a .lif, cut off;
  - stacks (Day 26): a "fake z" (3 planes filed as z with step 0, time
    stamps 2.6 s apart) is time; a cut-off last frame (a short last step
    and a black tail) is left out of the projection, a complete one is
    not; one frame; StackSummary;
  - a stack's frames as container entries (Day 26, uLifContainer through
    uContainers): frame ids, the frames' list, a frame decoded, the
    note;
  - exported names (M3a): which .lif and image a TIFF's name means
    (LifExportGuesses, LifImageForExport);
  - the user's own 221107.lif, if it is in test\images\Microscope images
    (private: never in the repository): 24 images, sizes, pixel sizes,
    the z-stack, and the pixel sums of a few planes, as a Python
    reference reader computed them.

  Build and run with build_test.bat (plain fpc).
}

{$mode ObjFPC}{$H+}

uses
  Classes,
  SysUtils,
  uLifFile,
  uContainers,
  uLifContainer;

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

function Near(A, B: Double): Boolean;
begin
  Result := Abs(A - B) < 1e-6 * Abs(B) + 1e-9;
end;

{ ---- a .lif made here ---- }

const
  SmallXml =
    '<LMSDataContainerHeader Version="2"><Element Name="small.lif"><Data><Experiment/></Data>' +
    '<Memory Size="0" MemoryBlockID="MemBlock_1"/><Children>' +
    '<Element Name="Folder"><Data><Collection/></Data><Memory Size="0" MemoryBlockID="MemBlock_2"/><Children>' +
    '<Element Name="Stack"><Data><Image><ImageDescription><Channels>' +
    '<ChannelDescription Resolution="8" LUTName="Red" BytesInc="0"/>' +
    '<ChannelDescription Resolution="8" LUTName="Green" BytesInc="24"/>' +
    '</Channels><Dimensions>' +
    '<DimensionDescription DimID="1" NumberOfElements="4" Length="3.0e-006" Unit="m" BytesInc="1"/>' +
    '<DimensionDescription DimID="2" NumberOfElements="3" Length="1.0e-006" Unit="m" BytesInc="4"/>' +
    '<DimensionDescription DimID="3" NumberOfElements="2" Length="5.0e-007" Unit="m" BytesInc="12"/>' +
    '</Dimensions></ImageDescription>' +
    '<Attachment Name="HardwareSetting" Software="LAS X 3.5" SystemTypeName="TCS SP8">' +
    '<ATLConfocalSettingDefinition ObjectiveName="HC PL APO   40x/1.30 OIL " Magnification="40" ' +
    'NumericalAperture="1.3" Immersion="OIL" Zoom="2" PinholeAiry="1" MicroscopeModel="DMI8-CS"/>' +
    '</Attachment>' +
    '<TimeStampList NumberOfTimeStamps="1">1d8f2a459ae8ec0 </TimeStampList>' +
    '</Image></Data><Memory Size="48" MemoryBlockID="MemBlock_3"/><Children/></Element>' +
    '</Children></Element>' +
    '<Element Name="Empty"><Data><Image><ImageDescription/></Image></Data>' +
    '<Memory Size="0" MemoryBlockID="MemBlock_4"/></Element>' +
    '</Children></Element></LMSDataContainerHeader>';

procedure WriteInt32(AStream: TStream; AValue: LongWord);
begin
  AValue := NtoLE(AValue);
  AStream.WriteBuffer(AValue, 4);
end;

procedure WriteByte(AStream: TStream; AValue: Byte);
begin
  AStream.WriteBuffer(AValue, 1);
end;

procedure WriteUtf16(AStream: TStream; const AText: string);
var
  U: UnicodeString;
begin
  U := UnicodeString(AText);
  if Length(U) > 0 then
    AStream.WriteBuffer(U[1], Length(U) * 2);
end;

{ ACutAt > 0: only so many bytes are written. }
procedure MakeSmallLif(const AFileName: string; ACutAt: Integer = 0);
var
  Stream: TMemoryStream;
  Size64: Int64;
  I: Integer;
  B: Byte;
  Id: string;
  Fs: TFileStream;
begin
  Stream := TMemoryStream.Create;
  try
    WriteInt32(Stream, $70);
    WriteInt32(Stream, Length(SmallXml) * 2 + 5);
    WriteByte(Stream, $2A);
    WriteInt32(Stream, Length(SmallXml));
    WriteUtf16(Stream, SmallXml);
    Id := 'MemBlock_3';
    WriteInt32(Stream, $70);
    WriteInt32(Stream, 0);
    WriteByte(Stream, $2A);
    Size64 := NtoLE(Int64(48));
    Stream.WriteBuffer(Size64, 8);
    WriteByte(Stream, $2A);
    WriteInt32(Stream, Length(Id));
    WriteUtf16(Stream, Id);
    { Sample i = i * 5: channel c, plane z, (x, y) at c*24 + z*12 + y*4 + x. }
    for I := 0 to 47 do
    begin
      B := I * 5;
      Stream.WriteBuffer(B, 1);
    end;
    Fs := TFileStream.Create(AFileName, fmCreate);
    try
      Fs.CopyFrom(Stream, 0);
      if ACutAt > 0 then
        Fs.Size := ACutAt;
    finally
      Fs.Free;
    end;
  finally
    Stream.Free;
  end;
end;

function Pixel(const ARGBA: TBytes; AWidth, AX, AY: Integer): string;
var
  P: Integer;
begin
  P := (AY * AWidth + AX) * 4;
  Result := Format('%d,%d,%d,%d', [ARGBA[P], ARGBA[P + 1], ARGBA[P + 2], ARGBA[P + 3]]);
end;

function HasLine(const AImage: TLifImage; const AText: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(AImage.Lines) do
    if AImage.Lines[I] = AText then
      Exit(True);
  Result := False;
end;

function AllLines(const AImage: TLifImage): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(AImage.Lines) do
    Result := Result + ' | ' + AImage.Lines[I];
end;

procedure TestSmall(const ADir: string);
var
  Lif: TLifFile;
  Img: TLifImage;
  Values: TWordArrayLif;
  Sum, I: Integer;
  RGBA: TBytes;
  W, H: Integer;
  FileName: string;
begin
  WriteLn('A .lif made here');
  FileName := ADir + 'small.lif';
  MakeSmallLif(FileName);
  Check('IsLifFile', IsLifFile(FileName));
  Lif := TLifFile.Create;
  try
    Check('opens', Lif.Open(FileName), Lif.ErrorText);
    Check('one image (the element without pixels is left out)', Lif.ImageCount = 1,
      IntToStr(Lif.ImageCount));
    if Lif.ImageCount <> 1 then
      Exit;
    Img := Lif.Images[0];
    Check('name and path in its folder', (Img.Name = 'Stack') and (Img.Path = 'Folder/Stack'),
      Img.Path);
    Check('IndexOfPath', Lif.IndexOfPath('folder/stack') = 0);
    Check('4 x 3, 2 z-planes, 1 time point',
      (Img.Width = 4) and (Img.Height = 3) and (Img.ZCount = 2) and (Img.TCount = 1),
      Format('%d x %d, z %d, t %d', [Img.Width, Img.Height, Img.ZCount, Img.TCount]));
    Check('pixel size = Length / (N - 1): 1 x 0.5 µm',
      Near(Img.PixelSizeX, 1.0) and Near(Img.PixelSizeY, 0.5),
      Format('%g x %g', [Img.PixelSizeX, Img.PixelSizeY]));
    Check('z step 0.5 µm', Near(Img.ZStep, 0.5), FloatToStr(Img.ZStep));
    Check('two channels, Red and Green',
      (Length(Img.Channels) = 2) and (Img.Channels[0].Red = 255) and (Img.Channels[0].Green = 0)
      and (Img.Channels[1].Green = 255) and (Img.Channels[1].Red = 0));
    Check('block found', (Img.BlockOffset > 0) and (Img.BlockSize = 48),
      Format('%d, %d', [Img.BlockOffset, Img.BlockSize]));
    Check('objective, squeezed', Img.ObjectiveName = 'HC PL APO 40x/1.30 OIL', Img.ObjectiveName);
    Check('magnification, NA, immersion, zoom',
      Near(Img.Magnification, 40) and Near(Img.NumericalAperture, 1.3) and (Img.Immersion = 'OIL')
      and Near(Img.Zoom, 2));
    Check('line: pixel size', HasLine(Img, 'Pixel size: 1.0000 x 0.5000 µm'), AllLines(Img));
    Check('line: stack', HasLine(Img, 'Stack: 2 z-planes, step 0.500 µm'), AllLines(Img));
    Check('line: channels', HasLine(Img, 'Channels: Red, Green (8 bit)'), AllLines(Img));
    Check('line: system', HasLine(Img, 'System: TCS SP8 (DMI8-CS), LAS X 3.5'), AllLines(Img));
    Check('line: objective', HasLine(Img, 'Objective: HC PL APO 40x/1.30 OIL'), AllLines(Img));
    Check('line: zoom', HasLine(Img, 'Zoom: 2'), AllLines(Img));
    Check('acquired: 2022-11-07', FormatDateTime('yyyy-mm-dd', Img.Acquired) = '2022-11-07',
      FormatDateTime('yyyy-mm-dd hh:nn:ss', Img.Acquired));

    Check('channel 1, plane 1', Lif.ReadChannelPlane(0, 1, 1, 0, Values), Lif.ErrorText);
    Sum := 0;
    for I := 0 to High(Values) do
      Inc(Sum, Values[I]);
    Check('  12 values, sum 2490', (Length(Values) = 12) and (Sum = 2490),
      Format('%d values, sum %d', [Length(Values), Sum]));
    Check('  first (36 * 5) and last (47 * 5)', (Values[0] = 180) and (Values[11] = 235));
    Check('plane outside the stack: False', not Lif.ReadChannelPlane(0, 0, 2, 0, Values));
    Check('channel outside: False', not Lif.ReadChannelPlane(0, 2, 0, 0, Values));

    Check('colour, plane 0', Lif.RenderRGBA(0, 0, 0, W, H, RGBA), Lif.ErrorText);
    Check('  4 x 3', (W = 4) and (H = 3));
    Check('  (1, 2): red 45, green 165', Pixel(RGBA, W, 1, 2) = '45,165,0,255', Pixel(RGBA, W, 1, 2));
    Check('maximum projection', Lif.RenderRGBA(0, -1, 0, W, H, RGBA), Lif.ErrorText);
    Check('  (1, 2): red 105, green 225', Pixel(RGBA, W, 1, 2) = '105,225,0,255', Pixel(RGBA, W, 1, 2));
    Check('  (0, 0): red 60, green 180', Pixel(RGBA, W, 0, 0) = '60,180,0,255', Pixel(RGBA, W, 0, 0));
  finally
    Lif.Free;
  end;
end;

{ A time series filed as z (Day 26): 4 x 4, one Gray channel, 3 planes
  of step 0; stamps at 0, 2.6 s and AThird s. Plane 0 all 10; plane 1
  all 20, (1, 1) = 200; plane 2: rows 0-1 = 30, rows 2-3 = 0 (cut off). }
procedure MakeTimeLif(const AFileName: string; AThird: Double);
const
  Base = Int64($1D8F2A459AE8EC0);
var
  Xml, Id: string;
  Stream: TMemoryStream;
  Size64: Int64;
  I, X, Y: Integer;
  B: Byte;
begin
  Xml :=
    '<LMSDataContainerHeader Version="2"><Element Name="time.lif"><Data><Experiment/></Data>' +
    '<Memory Size="0" MemoryBlockID="MemBlock_1"/><Children>' +
    '<Element Name="Series009"><Data><Image><ImageDescription><Channels>' +
    '<ChannelDescription Resolution="8" LUTName="Gray" BytesInc="0"/>' +
    '</Channels><Dimensions>' +
    '<DimensionDescription DimID="1" NumberOfElements="4" Length="3.0e-006" Unit="m" BytesInc="1"/>' +
    '<DimensionDescription DimID="2" NumberOfElements="4" Length="3.0e-006" Unit="m" BytesInc="4"/>' +
    '<DimensionDescription DimID="3" NumberOfElements="3" Length="0.000000e+000" Unit="m" BytesInc="16"/>' +
    '</Dimensions></ImageDescription>' +
    '<TimeStampList NumberOfTimeStamps="3">' + IntToHex(Base, 15) + ' '
    + IntToHex(Base + 26000000, 15) + ' ' + IntToHex(Base + Round(AThird * 1e7), 15) +
    '</TimeStampList>' +
    '</Image></Data><Memory Size="48" MemoryBlockID="MemBlock_2"/><Children/></Element>' +
    '</Children></Element></LMSDataContainerHeader>';
  Stream := TMemoryStream.Create;
  try
    WriteInt32(Stream, $70);
    WriteInt32(Stream, Length(Xml) * 2 + 5);
    WriteByte(Stream, $2A);
    WriteInt32(Stream, Length(Xml));
    WriteUtf16(Stream, Xml);
    Id := 'MemBlock_2';
    WriteInt32(Stream, $70);
    WriteInt32(Stream, 0);
    WriteByte(Stream, $2A);
    Size64 := NtoLE(Int64(48));
    Stream.WriteBuffer(Size64, 8);
    WriteByte(Stream, $2A);
    WriteInt32(Stream, Length(Id));
    WriteUtf16(Stream, Id);
    for I := 0 to 2 do
      for Y := 0 to 3 do
        for X := 0 to 3 do
        begin
          case I of
            0: B := 10;
            1: if (X = 1) and (Y = 1) then B := 200 else B := 20;
          else
            if Y < 2 then B := 30 else B := 0;
          end;
          Stream.WriteBuffer(B, 1);
        end;
    Stream.SaveToFile(AFileName);
  finally
    Stream.Free;
  end;
end;

procedure TestStacks(const ADir: string);
var
  FileName: string;
  Lif: TLifFile;
  Img: TLifImage;
  RGBA: TBytes;
  W, H: Integer;
begin
  WriteLn('Stacks (Day 26)');
  FileName := ADir + 'time.lif';
  MakeTimeLif(FileName, 3.6);
  Lif := TLifFile.Create;
  try
    Check('time series opens', Lif.Open(FileName), Lif.ErrorText);
    Img := Lif.Images[0];
    Check('filed as z, step 0: time (a fake z)', (Img.StackKind = lsTime) and Img.FakeZ
      and (Img.FrameCount = 3), Format('kind %d, fake %s, frames %d',
      [Ord(Img.StackKind), BoolToStr(Img.FakeZ, True), Img.FrameCount]));
    Check('frame times 0, 2.6, 3.6 s', (Length(Img.FrameTimes) = 3) and Near(Img.FrameTimes[1], 2.6)
      and Near(Img.FrameTimes[2], 3.6));
    Check('interval 2.6 s (the short last step doesn''t count)', Near(Img.FrameInterval, 2.6),
      FloatToStr(Img.FrameInterval));
    Check('line: time', HasLine(Img, 'Time: 3 points, every 2.600 s (filed as 3 z-planes at one depth)'),
      AllLines(Img));
    Check('the cut-off last frame is left out: 2 usable', Lif.UsableFrameCount(0) = 2,
      IntToStr(Lif.UsableFrameCount(0)));
    Check('summary: t 2 × 2.6 s', StackSummary(Img, 2) = 't 2 × 2.6 s', StackSummary(Img, 2));
    Check('projection', Lif.RenderRGBA(0, -1, 0, W, H, RGBA), Lif.ErrorText);
    Check('  (0, 0): 20, not the cut frame''s 30', Pixel(RGBA, W, 0, 0) = '20,20,20,255',
      Pixel(RGBA, W, 0, 0));
    Check('  (1, 1): 200', Pixel(RGBA, W, 1, 1) = '200,200,200,255', Pixel(RGBA, W, 1, 1));
    Check('frame 2 alone', Lif.RenderFrameRGBA(0, 2, W, H, RGBA), Lif.ErrorText);
    Check('  (0, 0) 30, (0, 3) 0', (Pixel(RGBA, W, 0, 0) = '30,30,30,255')
      and (Pixel(RGBA, W, 0, 3) = '0,0,0,255'));
    Check('no frame 3', not Lif.RenderFrameRGBA(0, 3, W, H, RGBA));
  finally
    Lif.Free;
  end;

  { The same black tail after a full step: a complete frame (dark at the
    bottom), kept. }
  MakeTimeLif(FileName, 5.2);
  Lif := TLifFile.Create;
  try
    Check('full last step opens', Lif.Open(FileName), Lif.ErrorText);
    Check('  all 3 usable', Lif.UsableFrameCount(0) = 3, IntToStr(Lif.UsableFrameCount(0)));
  finally
    Lif.Free;
  end;

  { The small stack (z step 0.5 µm, one stamp): depth. }
  FileName := ADir + 'small.lif';
  MakeSmallLif(FileName);
  Lif := TLifFile.Create;
  try
    Check('small stack opens', Lif.Open(FileName), Lif.ErrorText);
    Img := Lif.Images[0];
    Check('  depth, 2 frames, no times', (Img.StackKind = lsDepth) and (Img.FrameCount = 2)
      and not Img.FakeZ and (Length(Img.FrameTimes) = 0));
    Check('  2 usable', Lif.UsableFrameCount(0) = 2, IntToStr(Lif.UsableFrameCount(0)));
    Check('  summary: z 2 × 0.5 µm', StackSummary(Img, 2) = 'z 2 × 0.5 µm', StackSummary(Img, 2));
  finally
    Lif.Free;
  end;
end;

procedure TestFrameEntries(const ADir: string);
var
  FileName, Base, Error: string;
  Frame, W, H: Integer;
  Entries: TContainerEntryArray;
  RGBA: TBytes;
  Lif: TLifFile;
begin
  WriteLn('A stack''s frames as entries (Day 26)');
  Check('frame id: Series009|#t03 -> Series009, frame 2',
    LifSplitFrame('Series009|#t03', Base, Frame) and (Base = 'Series009') and (Frame = 2),
    Base + ' ' + IntToStr(Frame));
  Check('nested: Folder|Series009|#z10 -> frame 9',
    LifSplitFrame('Folder|Series009|#z10', Base, Frame) and (Base = 'Folder|Series009')
    and (Frame = 9));
  Check('no frame: Series009, a|#x3, a|#t, a|#t0, #t3',
    not LifSplitFrame('Series009', Base, Frame) and not LifSplitFrame('a|#x3', Base, Frame)
    and not LifSplitFrame('a|#t', Base, Frame) and not LifSplitFrame('a|#t0', Base, Frame)
    and not LifSplitFrame('#t3', Base, Frame));

  FileName := ADir + 'frames.lif';
  MakeTimeLif(FileName, 3.6);
  Check('the .lif lists one entry, a stack of 3', ListContainerEntries(FileName, Entries)
    and (Length(Entries) = 1) and (Entries[0].Id = 'Series009') and (Entries[0].Frames = 3));
  Check('its frames: the 2 usable', ListContainerEntries(MakeVirtualName(FileName, 'Series009'),
    Entries) and (Length(Entries) = 2), IntToStr(Length(Entries)));
  if Length(Entries) = 2 then
  begin
    Check('  ids Series009|#t01, |#t02', (Entries[0].Id = 'Series009|#t01')
      and (Entries[1].Id = 'Series009|#t02'), Entries[0].Id + ', ' + Entries[1].Id);
    Check('  names with their time', (Entries[0].Name = 't 1    0.0 s')
      and (Entries[1].Name = 't 2    2.6 s'), Entries[0].Name + ' / ' + Entries[1].Name);
  end;
  Check('a frame decodes', DecodeContainerEntry(MakeVirtualName(FileName, 'Series009|#t02'), nil,
    W, H, RGBA, Error), Error);
  if Length(RGBA) > 0 then
    Check('  (1, 1): 200', Pixel(RGBA, W, 1, 1) = '200,200,200,255', Pixel(RGBA, W, 1, 1));
  Check('the stack still decodes (its projection)',
    DecodeContainerEntry(MakeVirtualName(FileName, 'Series009'), nil, W, H, RGBA, Error)
    and (Pixel(RGBA, W, 0, 0) = '20,20,20,255'), Error);
  Check('note: t 2 × 2.6 s (projection)',
    ContainerEntryNote(MakeVirtualName(FileName, 'Series009')) = 't 2 × 2.6 s (projection)',
    ContainerEntryNote(MakeVirtualName(FileName, 'Series009')));
  Check('a frame has no note', ContainerEntryNote(MakeVirtualName(FileName, 'Series009|#t01')) = '');
  Check('no frames of a frame', not ListContainerEntries(
    MakeVirtualName(FileName, 'Series009|#t01'), Entries));
  Lif := TLifFile.Create;
  try
    Check('LifIndexOfId: a frame -> its stack', Lif.Open(FileName)
      and (LifIndexOfId(Lif, 'Series009|#t02') = 0) and (LifIndexOfId(Lif, 'Series009|#t09') = 0)
      and (LifIndexOfId(Lif, 'Other|#t01') = -1));
  finally
    Lif.Free;
  end;
end;

procedure TestDamaged(const ADir: string);
var
  Lif: TLifFile;
  FileName: string;
  Fs: TFileStream;
  Junk: array[0..99] of Byte;
  Values: TWordArrayLif;
begin
  WriteLn('Damaged files');
  FileName := ADir + 'junk.lif';
  FillChar(Junk, SizeOf(Junk), 7);
  Fs := TFileStream.Create(FileName, fmCreate);
  try
    Fs.WriteBuffer(Junk, SizeOf(Junk));
  finally
    Fs.Free;
  end;
  Check('not a .lif: IsLifFile False', not IsLifFile(FileName));
  Lif := TLifFile.Create;
  try
    Check('not a .lif: Open False', not Lif.Open(FileName));
    Check('  says why', Lif.ErrorText <> '', Lif.ErrorText);

    FileName := ADir + 'cut_xml.lif';
    MakeSmallLif(FileName, 200);
    Check('cut inside the description: False', not Lif.Open(FileName), Lif.ErrorText);

    FileName := ADir + 'cut_data.lif';
    { header 13 + description + block header 22 + id 20 + 20 of the 48 pixel bytes }
    MakeSmallLif(FileName, 13 + Length(SmallXml) * 2 + 42 + 20);
    Check('cut inside the pixels: opens', Lif.Open(FileName), Lif.ErrorText);
    Check('  the image is listed', Lif.ImageCount = 1);
    Check('  its plane can''t be read', not Lif.ReadChannelPlane(0, 1, 1, 0, Values));
  finally
    Lif.Free;
  end;
end;

{ ---- the user's file, if present ---- }

type
  TExpected = record
    Path: string;
    Width: Integer;
    PixelSize: Double;
    ZCount: Integer;
    Sum0: Integer;      { channel 0, plane 0: sum of the values mod 65536 }
  end;

const
  Expected: array[0..5] of TExpected = (
    (Path: 'Image001'; Width: 512; PixelSize: 0.56874; ZCount: 1; Sum0: 55588),
    (Path: 'Image003'; Width: 1024; PixelSize: 0.28409; ZCount: 1; Sum0: 12470),
    (Path: 'Image005'; Width: 1024; PixelSize: 0.12548; ZCount: 1; Sum0: 60460),
    (Path: 'Series009'; Width: 1024; PixelSize: 0.11730; ZCount: 12; Sum0: 33578),
    (Path: 'Image014'; Width: 1024; PixelSize: 0.06589; ZCount: 1; Sum0: 58571),
    (Path: 'Image027'; Width: 1024; PixelSize: 0.12177; ZCount: 1; Sum0: 3418)
  );

procedure TestUserFile;
var
  FileName: string;
  Lif: TLifFile;
  Img: TLifImage;
  I, Index, J: Integer;
  Values: TWordArrayLif;
  Sum: LongWord;
  RGBA: TBytes;
  W, H: Integer;
begin
  WriteLn('221107.lif (the user''s, if present)');
  FileName := ExtractFilePath(ParamStr(0)) + 'images' + PathDelim + 'Microscope images'
    + PathDelim + '221107.lif';
  if not FileExists(FileName) then
  begin
    WriteLn('  (not there: skipped)');
    Exit;
  end;
  Lif := TLifFile.Create;
  try
    Check('opens', Lif.Open(FileName), Lif.ErrorText);
    Check('24 images', Lif.ImageCount = 24, IntToStr(Lif.ImageCount));
    for I := 0 to High(Expected) do
    begin
      Index := Lif.IndexOfPath(Expected[I].Path);
      Check(Expected[I].Path + ' found', Index >= 0);
      if Index < 0 then
        Continue;
      Img := Lif.Images[Index];
      Check(Format('  %d px, %.5f µm, z %d', [Expected[I].Width, Expected[I].PixelSize,
        Expected[I].ZCount]),
        (Img.Width = Expected[I].Width) and (Abs(Img.PixelSizeX - Expected[I].PixelSize) < 0.00001)
        and (Img.ZCount = Expected[I].ZCount),
        Format('%d px, %.5f µm, z %d', [Img.Width, Img.PixelSizeX, Img.ZCount]));
      if Lif.ReadChannelPlane(Index, 0, 0, 0, Values) then
      begin
        Sum := 0;
        for J := 0 to High(Values) do
          Inc(Sum, Values[J]);
        Check(Format('  pixels as the reference (%d)', [Expected[I].Sum0]),
          (Sum mod 65536) = LongWord(Expected[I].Sum0), IntToStr(Sum mod 65536));
      end
      else
        Check('  plane read', False, Lif.ErrorText);
    end;
    Index := Lif.IndexOfPath('Series009');
    if Index >= 0 then
    begin
      Img := Lif.Images[Index];
      Check('Series009: objective 40x/1.30 oil', Pos('40x/1.30 OIL', Img.ObjectiveName) > 0,
        Img.ObjectiveName);
      Check('Series009: Magenta and Green', (Length(Img.Channels) = 2)
        and (Img.Channels[0].LutName = 'Magenta') and (Img.Channels[1].LutName = 'Green'));
      Check('Series009: filed as z, a time series at one plane',
        (Img.StackKind = lsTime) and Img.FakeZ and (Img.FrameCount = 12));
      Check('  every 2.59 s', Abs(Img.FrameInterval - 2.593) < 0.01, FloatToStr(Img.FrameInterval));
      Check('  its last frame is cut off: 11 usable', Lif.UsableFrameCount(Index) = 11,
        IntToStr(Lif.UsableFrameCount(Index)));
      Check('  summary: t 11 × 2.6 s', StackSummary(Img, 11) = 't 11 × 2.6 s',
        StackSummary(Img, 11));
      Check('Series009: maximum projection of 11 frames', Lif.RenderRGBA(Index, -1, 0, W, H, RGBA),
        Lif.ErrorText);
      Check('  1024 x 1024', (W = 1024) and (H = 1024));
      WriteLn('  Series009 lines:', AllLines(Img));
    end;
  finally
    Lif.Free;
  end;
end;

{ M3a: an exported TIFF's name -> the .lif and the image. }
procedure TestExportNames(const ADir: string);
var
  G: TLifExportGuesses;
  Lif: TLifFile;
  FileName: string;
begin
  WriteLn('Exported names (M3a)');
  G := LifExportGuesses('221119_Series084_t242_ch01');
  Check('221119_Series084_t242_ch01: one guess', Length(G) = 1, IntToStr(Length(G)));
  if Length(G) = 1 then
    Check('  221119.lif, Series084', (G[0].LifBase = '221119') and (G[0].ImageName = 'Series084'),
      G[0].LifBase + ' / ' + G[0].ImageName);
  G := LifExportGuesses('221119_Image089_ch00');
  Check('221119_Image089_ch00: 221119.lif, Image089', (Length(G) = 1)
    and (G[0].LifBase = '221119') and (G[0].ImageName = 'Image089'));
  G := LifExportGuesses('my_project_Folder_Series1_z03_c2');
  Check('my_project_Folder_Series1_z03_c2: 3 guesses, longest project first', (Length(G) = 3)
    and (G[0].LifBase = 'my_project_Folder') and (G[0].ImageName = 'Series1')
    and (G[2].LifBase = 'my') and (G[2].ImageName = 'project_Folder_Series1'));
  G := LifExportGuesses('221119_t242');
  Check('221119_t242: the last part stays the image', (Length(G) = 1) and (G[0].ImageName = 't242'));
  Check('no "_": no guess', Length(LifExportGuesses('Image001')) = 0);
  G := LifExportGuesses('a_b_ch');
  Check('"_ch": not a suffix (no digits)', (Length(G) = 2) and (G[0].ImageName = 'ch')
    and (G[1].ImageName = 'b_ch'));
  Check('"_Tower7": not a suffix', LifExportGuesses('a_Tower7')[0].ImageName = 'Tower7');

  FileName := ADir + 'proj.lif';
  MakeSmallLif(FileName);
  Lif := TLifFile.Create;
  try
    Check('small .lif opens', Lif.Open(FileName), Lif.ErrorText);
    Check('image by its name: Stack', LifImageForExport(Lif, 'stack') = 0);
    Check('image by its path with "_": Folder_Stack', LifImageForExport(Lif, 'Folder_Stack') = 0);
    Check('unknown name: -1', LifImageForExport(Lif, 'Series084') = -1);
  finally
    Lif.Free;
  end;
end;

var
  TempDir: string;
begin
  PassCount := 0;
  FailCount := 0;
  WriteLn('Versarite Image Lab .lif reader test (M2a)');
  TempDir := IncludeTrailingPathDelimiter(GetTempDir) + 'mviewlab_lif_test' + PathDelim;
  ForceDirectories(TempDir);
  TestSmall(TempDir);
  TestDamaged(TempDir);
  TestStacks(TempDir);
  TestFrameEntries(TempDir);
  TestExportNames(TempDir);
  TestUserFile;
  WriteLn;
  WriteLn(Format('%d passed, %d failed', [PassCount, FailCount]));
  if FailCount > 0 then
    ExitCode := 1;
end.
