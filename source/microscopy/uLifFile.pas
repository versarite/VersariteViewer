unit uLifFile;

{
  Unit: uLifFile

  Purpose
  -------
  Reads Leica LAS AF / LAS X project files (.lif), M2a (Day 25): which
  images a file holds, what the microscope says about each (pixel size,
  objective, zoom, channels, stack, detectors, time), and their pixels:
  one channel's plane, or all channels in their colours as one RGBA
  picture, a single plane or the maximum projection of a z-stack.

  The file
  --------
  - Header: int32 $70, int32 size, byte $2A, int32 n, then the XML
    description, n UTF-16 characters.
  - Memory blocks, one after the other: int32 $70, int32 size, byte
    $2A, the block size (int64 in version 2, int32 in version 1), byte
    $2A, int32 n, the block's id (n UTF-16 characters), then the data.
  - The XML: LMSDataContainerHeader / Element (the file) / Children /
    Element ... (folders nest); an element with Data/Image and a Memory
    of size > 0 is an image. ImageDescription: Channels
    (ChannelDescription: LUTName, Resolution in bits, BytesInc) and
    Dimensions (DimensionDescription: DimID 1 = x, 2 = y, 3 = z, 4 = t,
    NumberOfElements, Length in metres, BytesInc). A sample of channel
    c at (x, y, z, t) is at c.BytesInc + x * X.BytesInc + y * Y.BytesInc
    + z * Z.BytesInc + t * T.BytesInc in the block, 1 byte (8 bit) or 2
    (more), little-endian.
  - Pixel size = Length / (NumberOfElements - 1), as readlif and LAS X
    (Bio-Formats too since 5.x); spec "Microscopy edition" §6.3 keeps
    the check against a burned-in scale bar open.

  Owns
  ----
  - The list of images (records), the block index. Pixels are read on
    request, from the file, and not kept.

  Knows
  -----
  - Nothing of MView: no LCL, no BGRABitmap (TestLif builds with plain
    fpc).

  Responsibilities
  ----------------
  - Open: header, XML, block index (a few ms for a 70 MB file: the
    pixel data is skipped). False and ErrorText for anything else.
  - ReadChannelPlane: one channel, one plane, as Words (0 .. 2^bits-1).
  - RenderRGBA: the channels added in their LUT colours (Red, Green,
    Blue, Cyan, Magenta, Yellow, Gray / Grey / White; unknown: grey),
    each scaled to 8 bits; one plane (AZ >= 0) or the maximum
    projection of the stack (AZ = -1: over its usable frames). A cancel
    test is asked between planes.
  - Stacks (Day 26, spec "Microscopy edition" §6.5): the frames along z
    or t (FrameCount), what they are (StackKind: a z filed with step 0
    and running time stamps is time at one plane - a "fake z"), when
    each was taken (FrameTimes, FrameInterval). UsableFrameCount: the
    frames without a cut-off last one (a short last time step and a
    black tail; read from the pixels once, then kept). RenderFrameRGBA:
    one frame (projected over z when the stack is z and t).
    StackSummary: 'z 12 × 0.5 µm' / 't 11 × 2.6 s'.
  - IsLifFile: by extension and the first bytes.
  - LifExportGuesses / LifImageForExport (M3a): which .lif and which
    image an exported TIFF's name means (221119_Series084_t242_ch01).

  Does NOT
  --------
  - Read tiles (DimID 10) other than the first, or dimensions 5 .. 9
    (taken at index 0).
  - Apply the LAS X display settings (black / white per channel): the
    raw values are shown, scaled to 8 bits.

  Threads
  -------
  A TLifFile is used by one thread at a time; separate instances on
  separate threads are fine (each reads the file on its own).

  Uses (MView units)
  ------------------
  (none)
  Libraries:      Classes, SysUtils, Math, DOM, XMLRead (fcl-xml)

  Used by
  -------
  The microscopy edition's container reader (M2b); test\TestLif.lpr
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils;

type
  TQWordArrayLif = array of QWord;

  TLifDimension = record
    Id: Integer;              { 1 x, 2 y, 3 z, 4 t, 5 lambda, ... 10 tiles }
    Count: Integer;
    LengthM: Double;          { metres (seconds for t), as in the file }
    BytesInc: Int64;
    UnitName: string;
  end;

  TLifChannel = record
    LutName: string;
    Resolution: Integer;      { bits }
    BytesInc: Int64;
    Red, Green, Blue: Byte;   { the LUT's colour at full value }
  end;

  { What a stack's frames are (Day 26). }
  TLifStackKind = (lsNone, lsDepth, lsTime);

  TLifImage = record
    Name: string;             { 'Series009' }
    Path: string;             { 'Series009', or 'Folder/Series009' when nested }
    Width, Height: Integer;
    ZCount, TCount: Integer;  { 1 when there is no such dimension }
    PixelSizeX, PixelSizeY: Double;   { µm; 0 = unknown }
    ZStep: Double;            { µm; 0 = unknown }
    TimeStep: Double;         { s between time points; 0 = unknown }
    Dimensions: array of TLifDimension;
    Channels: array of TLifChannel;
    BlockId: string;
    BlockOffset: Int64;       { of the data in the file; -1 = block not found }
    BlockSize: Int64;
    Acquired: TDateTime;      { UTC; 0 = unknown }
    { For the metadata panel: 'Objective: HC PL APO CS2 40x/1.30 OIL' }
    Lines: TStringArray;
    { The facts the panel and the info line use. }
    SystemName: string;       { 'TCS SP8' }
    ObjectiveName: string;
    Magnification: Double;
    NumericalAperture: Double;
    Immersion: string;
    Zoom: Double;
    { The stack (Day 26): its frames run along t when there is a time
      dimension, else along z; 1 = no stack. }
    StackKind: TLifStackKind;
    FrameCount: Integer;
    FakeZ: Boolean;           { filed as z (step 0), taken as time at one plane }
    FrameTimes: array of Double;  { s since the first frame; empty = unknown }
    FrameInterval: Double;    { s, the median step; 0 = unknown }
    { UsableFrameCount's answer; -1 = not looked at yet. }
    Usable: Integer;
  end;

  TWordArrayLif = array of Word;

  { True = stop (the image is no longer wanted). }
  TLifCancel = function: Boolean of object;

  TLifFile = class
  private
    FFileName: string;
    FVersion: Integer;
    FImages: array of TLifImage;
    FBlockIds: array of string;
    FBlockOffsets: array of Int64;
    FBlockSizes: array of Int64;
    FErrorText: string;
    function GetImage(AIndex: Integer): TLifImage;
    function FindBlock(const AId: string; out AOffset, ASize: Int64): Boolean;
    procedure ReadBlockIndex(AStream: TStream);
    procedure ParseXml(const AXml: UTF8String);
    function ZeroTailRows(AIndex, AFrame: Integer; out ARows: Integer): Boolean;
    { The planes (z, t) a frame takes; AZ = -1: all z. }
    procedure FramePlane(const AImage: TLifImage; AFrame: Integer; out AZ, AT: Integer);
    function RenderPlanes(AIndex: Integer; const AZs, ATs: array of Integer;
      out AWidth, AHeight: Integer; out ARGBA: TBytes; ACancel: TLifCancel): Boolean;
  public
    { False (ErrorText says why) if it isn't a .lif this reader knows. }
    function Open(const AFileName: string): Boolean;
    function ImageCount: Integer;
    function IndexOfPath(const APath: string): Integer;
    { One channel, one plane: Width * Height values, row by row. }
    function ReadChannelPlane(AIndex, AChannel, AZ, AT: Integer;
      out AValues: TWordArrayLif): Boolean;
    { All channels in their colours, R G B A per pixel, row by row.
      AZ >= 0: that plane at AT. AZ = -1: the maximum projection of the
      stack's usable frames (AT is then ignored). }
    function RenderRGBA(AIndex, AZ, AT: Integer; out AWidth, AHeight: Integer;
      out ARGBA: TBytes; ACancel: TLifCancel = nil): Boolean;
    { One frame of the stack (0 .. FrameCount - 1), projected over z when
      the stack runs along t and has z too. }
    function RenderFrameRGBA(AIndex, AFrame: Integer; out AWidth, AHeight: Integer;
      out ARGBA: TBytes; ACancel: TLifCancel = nil): Boolean;
    { The frames to show and play: FrameCount without a cut-off last
      frame (spec §6.5: scanning stopped mid-frame - a last time step
      shorter than the others, or none known, and rows at the bottom
      that are all 0 in every channel, a sixteenth of the height more
      than the frame before; without times nothing is left out). Reads
      one or two planes the first time. }
    function UsableFrameCount(AIndex: Integer): Integer;
    property FileName: string read FFileName;
    property Images[AIndex: Integer]: TLifImage read GetImage;
    property ErrorText: string read FErrorText;
  end;

function IsLifFile(const AFileName: string): Boolean;
{ For the info line (Day 26): 'z 12 × 0.5 µm', 't 11 × 2.6 s', 'z 12',
  't 11'; '' for no stack. ACount: the frames to name (UsableFrameCount,
  or FrameCount). }
function StackSummary(const AImage: TLifImage; ACount: Integer): string;
{ The LUT name's colour; False for an unknown name (grey then). }
function LutColor(const ALutName: string; out ARed, AGreen, ABlue: Byte): Boolean;

type
  { One way to read an exported file's name (M3a): the .lif's name
    without extension, and the image's name inside it. }
  TLifExportGuess = record
    LifBase: string;     { '221119' }
    ImageName: string;   { 'Series084' ('Folder_Series084' when nested) }
  end;
  TLifExportGuesses = array of TLifExportGuess;

{ LAS X names an exported image <project>_<image>[_t242][_z03][_ch01]
  (the project = the .lif's name; '_' joins folders too). The ways to
  split ABaseName (no folder, no extension), the longest project name
  first; the t / z / ch / c parts at the end are dropped. Empty if it
  has no '_'. Pure: the caller checks which .lif exists. }
function LifExportGuesses(const ABaseName: string): TLifExportGuesses;
{ The image of ALif an exported name means: its Name, or its Path with
  '/' as '_' (case ignored); -1 if none. }
function LifImageForExport(ALif: TLifFile; const AImageName: string): Integer;

implementation

uses
  Math,
  DOM,
  XMLRead;

const
  LifMagic = $70;
  LifSeparator = $2A;
  { Larger blocks are refused (a tile scan of many GB): later, in parts. }
  MaxPlaneBytes = Int64(1024) * 1024 * 1024;

var
  LifFormat: TFormatSettings;

function LutColor(const ALutName: string; out ARed, AGreen, ABlue: Byte): Boolean;
var
  N: string;
begin
  N := LowerCase(Trim(ALutName));
  Result := True;
  ARed := 0;
  AGreen := 0;
  ABlue := 0;
  if N = 'red' then
    ARed := 255
  else if N = 'green' then
    AGreen := 255
  else if N = 'blue' then
    ABlue := 255
  else if N = 'cyan' then
  begin
    AGreen := 255;
    ABlue := 255;
  end
  else if N = 'magenta' then
  begin
    ARed := 255;
    ABlue := 255;
  end
  else if N = 'yellow' then
  begin
    ARed := 255;
    AGreen := 255;
  end
  else if (N = 'gray') or (N = 'grey') or (N = 'white') then
  begin
    ARed := 255;
    AGreen := 255;
    ABlue := 255;
  end
  else
  begin
    ARed := 255;
    AGreen := 255;
    ABlue := 255;
    Result := False;
  end;
end;

{ 't242', 'z03', 'ch01', 'c1': the parts LAS X appends to an export. }
function IsExportSuffix(const APart: string): Boolean;
var
  P, I: Integer;
  Low: string;
begin
  Result := False;
  Low := LowerCase(APart);
  if Copy(Low, 1, 2) = 'ch' then
    P := 3
  else if (Low <> '') and (Low[1] in ['t', 'z', 'c']) then
    P := 2
  else
    Exit;
  if P > Length(Low) then
    Exit;
  for I := P to Length(Low) do
    if not (Low[I] in ['0'..'9']) then
      Exit;
  Result := True;
end;

function LifExportGuesses(const ABaseName: string): TLifExportGuesses;
var
  Parts: TStringArray;
  K, Last, I, N: Integer;
  Prefix, Image: string;
begin
  Result := nil;
  { Split at '_' (by hand: no string helpers in this code base). }
  Parts := nil;
  Image := '';
  for I := 1 to Length(ABaseName) do
    if ABaseName[I] = '_' then
    begin
      SetLength(Parts, Length(Parts) + 1);
      Parts[High(Parts)] := Image;
      Image := '';
    end
    else
      Image := Image + ABaseName[I];
  SetLength(Parts, Length(Parts) + 1);
  Parts[High(Parts)] := Image;
  if Length(Parts) < 2 then
    Exit;
  { The suffixes at the end (at least one part stays for the image). }
  Last := High(Parts);
  while (Last >= 2) and IsExportSuffix(Parts[Last]) do
    Dec(Last);
  N := 0;
  { Project = Parts[0 .. K - 1], image = Parts[K .. Last]; longest first. }
  for K := Last downto 1 do
  begin
    Prefix := Parts[0];
    for I := 1 to K - 1 do
      Prefix := Prefix + '_' + Parts[I];
    Image := Parts[K];
    for I := K + 1 to Last do
      Image := Image + '_' + Parts[I];
    if (Prefix = '') or (Image = '') then
      Continue;
    SetLength(Result, N + 1);
    Result[N].LifBase := Prefix;
    Result[N].ImageName := Image;
    Inc(N);
  end;
end;

function LifImageForExport(ALif: TLifFile; const AImageName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to ALif.ImageCount - 1 do
    if SameText(ALif.Images[I].Name, AImageName)
      or SameText(StringReplace(ALif.Images[I].Path, '/', '_', [rfReplaceAll]), AImageName) then
      Exit(I);
  Result := -1;
end;

function IsLifFile(const AFileName: string): Boolean;
var
  Stream: TFileStream;
  Head: array[0..8] of Byte;
begin
  Result := False;
  if not SameText(ExtractFileExt(AFileName), '.lif') then
    Exit;
  try
    Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      if Stream.Read(Head, SizeOf(Head)) <> SizeOf(Head) then
        Exit;
    finally
      Stream.Free;
    end;
  except
    Exit;
  end;
  Result := (Head[0] = LifMagic) and (Head[1] = 0) and (Head[2] = 0) and (Head[3] = 0)
    and (Head[8] = LifSeparator);
end;

{ ---- small XML helpers ---- }

function ChildElement(ANode: TDOMNode; const AName: string): TDOMElement;
var
  N: TDOMNode;
begin
  Result := nil;
  if ANode = nil then
    Exit;
  N := ANode.FirstChild;
  while N <> nil do
  begin
    if (N.NodeType = ELEMENT_NODE) and (N.NodeName = DOMString(AName)) then
      Exit(TDOMElement(N));
    N := N.NextSibling;
  end;
end;

{ The child element AName whose attribute AAttr is AValue. }
function ChildElementWith(ANode: TDOMNode; const AName, AAttr, AValue: string): TDOMElement;
var
  N: TDOMNode;
begin
  Result := nil;
  if ANode = nil then
    Exit;
  N := ANode.FirstChild;
  while N <> nil do
  begin
    if (N.NodeType = ELEMENT_NODE) and (N.NodeName = DOMString(AName))
      and (TDOMElement(N).GetAttribute(DOMString(AAttr)) = DOMString(AValue)) then
      Exit(TDOMElement(N));
    N := N.NextSibling;
  end;
end;

function Attr(AElement: TDOMElement; const AName: string): string;
begin
  if AElement = nil then
    Exit('');
  Result := UTF8Encode(AElement.GetAttribute(DOMString(AName)));
end;

function AttrFloat(AElement: TDOMElement; const AName: string; ADefault: Double = 0): Double;
begin
  if not TryStrToFloat(Trim(Attr(AElement, AName)), Result, LifFormat) then
    Result := ADefault;
end;

function AttrInt64(AElement: TDOMElement; const AName: string; ADefault: Int64 = 0): Int64;
begin
  if not TryStrToInt64(Trim(Attr(AElement, AName)), Result) then
    Result := ADefault;
end;

function AttrInt(AElement: TDOMElement; const AName: string; ADefault: Integer = 0): Integer;
begin
  if not TryStrToInt(Trim(Attr(AElement, AName)), Result) then
    Result := ADefault;
end;

function ClampByte(AValue: LongWord): Byte;
begin
  if AValue > 255 then
    Result := 255
  else
    Result := AValue;
end;

function NodeText(ANode: TDOMNode): string;
begin
  if ANode = nil then
    Exit('');
  Result := UTF8Encode(ANode.TextContent);
end;

{ 'HC PL APO CS2    40x/1.30 OIL ' -> 'HC PL APO CS2 40x/1.30 OIL' }
function Squeeze(const AText: string): string;
var
  I: Integer;
  LastSpace: Boolean;
begin
  Result := '';
  LastSpace := False;
  for I := 1 to Length(AText) do
    if AText[I] in [' ', #9, #10, #13] then
      LastSpace := True
    else
    begin
      if LastSpace and (Result <> '') then
        Result := Result + ' ';
      Result := Result + AText[I];
      LastSpace := False;
    end;
end;

function FloatText(AValue: Double; ADigits: Integer): string;
begin
  Result := FloatToStrF(AValue, ffFixed, 15, ADigits, LifFormat);
end;

{ A Windows FILETIME (100 ns since 1601-01-01, UTC) as TDateTime. }
function LifTimeToDate(AValue: QWord): TDateTime;
const
  DaysFrom1601To1899 = 109205;
  TicksPerDay = 864000000000;
begin
  if AValue = 0 then
    Exit(0);
  Result := AValue / TicksPerDay - DaysFrom1601To1899;
end;

{ ---- TLifFile ---- }

function TLifFile.GetImage(AIndex: Integer): TLifImage;
begin
  Result := FImages[AIndex];
end;

function TLifFile.ImageCount: Integer;
begin
  Result := Length(FImages);
end;

function TLifFile.IndexOfPath(const APath: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FImages) do
    if SameText(FImages[I].Path, APath) then
      Exit(I);
  Result := -1;
end;

function TLifFile.FindBlock(const AId: string; out AOffset, ASize: Int64): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FBlockIds) do
    if FBlockIds[I] = AId then
    begin
      AOffset := FBlockOffsets[I];
      ASize := FBlockSizes[I];
      Exit(True);
    end;
  AOffset := -1;
  ASize := 0;
  Result := False;
end;

procedure TLifFile.ReadBlockIndex(AStream: TStream);
var
  Tag, Size, IdLength: LongWord;
  Sep: Byte;
  MemSize: Int64;
  MemSize32: LongWord;
  Id: UnicodeString;
  N: Integer;
begin
  try
  while AStream.Position + 8 <= AStream.Size do
  begin
    AStream.ReadBuffer(Tag, 4);
    if LEtoN(Tag) <> LifMagic then
      Break;                                { the end, or something we don't know }
    AStream.ReadBuffer(Size, 4);
    AStream.ReadBuffer(Sep, 1);
    if Sep <> LifSeparator then
      Break;
    if FVersion >= 2 then
    begin
      AStream.ReadBuffer(MemSize, 8);
      MemSize := LEtoN(MemSize);
    end
    else
    begin
      AStream.ReadBuffer(MemSize32, 4);
      MemSize := LEtoN(MemSize32);
    end;
    AStream.ReadBuffer(Sep, 1);
    if Sep <> LifSeparator then
      Break;
    AStream.ReadBuffer(IdLength, 4);
    IdLength := LEtoN(IdLength);
    if IdLength > 4096 then
      Break;
    SetLength(Id, IdLength);
    if IdLength > 0 then
      AStream.ReadBuffer(Id[1], IdLength * 2);
    N := Length(FBlockIds);
    SetLength(FBlockIds, N + 1);
    SetLength(FBlockOffsets, N + 1);
    SetLength(FBlockSizes, N + 1);
    FBlockIds[N] := UTF8Encode(Id);
    FBlockOffsets[N] := AStream.Position;
    FBlockSizes[N] := MemSize;
    if (MemSize < 0) or (AStream.Position + MemSize > AStream.Size) then
    begin
      { Cut off: what is there is kept, the rest is outside the block. }
      FBlockSizes[N] := Max(Int64(0), AStream.Size - AStream.Position);
      Break;
    end;
    AStream.Position := AStream.Position + MemSize;
  end;
  except
    { A block header cut off: the blocks before it are kept. }
  end;
end;

procedure TLifFile.ParseXml(const AXml: UTF8String);
var
  Doc: TXMLDocument;
  Source: TMemoryStream;

  procedure AddLine(var AImage: TLifImage; const AText: string);
  begin
    SetLength(AImage.Lines, Length(AImage.Lines) + 1);
    AImage.Lines[High(AImage.Lines)] := AText;
  end;

  procedure ReadHardware(AImageNode: TDOMElement; var AImage: TLifImage);
  var
    Hardware, Setting, Detectors, Det: TDOMElement;
    Node: TDOMNode;
    Software, Model, Line: string;
    Pinhole, Speed: Double;
  begin
    Hardware := ChildElementWith(AImageNode, 'Attachment', 'Name', 'HardwareSetting');
    if Hardware = nil then
      Exit;
    Setting := ChildElement(Hardware, 'ATLConfocalSettingDefinition');
    if Setting = nil then
      Setting := ChildElement(Hardware, 'ATLCameraSettingDefinition');
    AImage.SystemName := Attr(Hardware, 'SystemTypeName');
    Software := Attr(Hardware, 'Software');
    Model := Attr(Setting, 'MicroscopeModel');
    Line := AImage.SystemName;
    if Model <> '' then
      Line := Line + ' (' + Model + ')';
    if Software <> '' then
      Line := Line + ', ' + Software;
    if Trim(Line) <> '' then
      AddLine(AImage, 'System: ' + Trim(Line));
    if Setting = nil then
      Exit;
    AImage.ObjectiveName := Squeeze(Attr(Setting, 'ObjectiveName'));
    AImage.Magnification := AttrFloat(Setting, 'Magnification');
    AImage.NumericalAperture := AttrFloat(Setting, 'NumericalAperture');
    AImage.Immersion := Attr(Setting, 'Immersion');
    AImage.Zoom := AttrFloat(Setting, 'Zoom');
    if AImage.ObjectiveName <> '' then
      AddLine(AImage, 'Objective: ' + AImage.ObjectiveName);
    if AImage.Zoom > 0 then
      AddLine(AImage, 'Zoom: ' + FloatToStrF(AImage.Zoom, ffGeneral, 4, 0, LifFormat));
    Pinhole := AttrFloat(Setting, 'PinholeAiry');
    if Pinhole > 0 then
      AddLine(AImage, 'Pinhole: ' + FloatText(Pinhole, 2) + ' AU');
    Speed := AttrFloat(Setting, 'ScanSpeed');
    if Speed > 0 then
      AddLine(AImage, Format('Scan: %s Hz, line average %d, frame average %d',
        [FloatToStrF(Speed, ffGeneral, 6, 0, LifFormat), AttrInt(Setting, 'LineAverage', 1),
         AttrInt(Setting, 'FrameAverage', 1)]));
    { Active detectors with their gain. }
    Detectors := ChildElement(Setting, 'DetectorList');
    Line := '';
    if Detectors <> nil then
    begin
      Node := Detectors.FirstChild;
      while Node <> nil do
      begin
        if (Node.NodeType = ELEMENT_NODE) and (Node.NodeName = 'Detector') then
        begin
          Det := TDOMElement(Node);
          if Attr(Det, 'IsActive') = '1' then
          begin
            if Line <> '' then
              Line := Line + ', ';
            Line := Line + Attr(Det, 'Name') + ' (gain '
              + FloatToStrF(AttrFloat(Det, 'Gain'), ffFixed, 6, 0, LifFormat) + ')';
          end;
        end;
        Node := Node.NextSibling;
      end;
    end;
    if Line <> '' then
      AddLine(AImage, 'Detectors: ' + Line);
  end;

  { The time stamps (FILETIME, 100 ns): the first is when it was
    acquired; all of them in AStamps (the frames' times). }
  procedure ReadTime(AImageNode: TDOMElement; var AImage: TLifImage;
    out AStamps: TQWordArrayLif);
  var
    List: TDOMElement;
    Node: TDOMNode;
    Text, Part: string;
    Value: QWord;
    P, N: Integer;
  begin
    AStamps := nil;
    N := 0;
    List := ChildElement(AImageNode, 'TimeStampList');
    if List = nil then
      Exit;
    Text := Trim(NodeText(List));
    if Text <> '' then
    begin
      { Hex numbers, separated by spaces (or line breaks). }
      Text := StringReplace(StringReplace(StringReplace(Text, #13, ' ', [rfReplaceAll]), #10, ' ',
        [rfReplaceAll]), #9, ' ', [rfReplaceAll]) + ' ';
      repeat
        P := Pos(' ', Text);
        Part := Trim(Copy(Text, 1, P - 1));
        Delete(Text, 1, P);
        if (Part <> '') and TryStrToQWord('$' + Part, Value) then
        begin
          if N >= Length(AStamps) then
            SetLength(AStamps, Max(16, N * 2));
          AStamps[N] := Value;
          Inc(N);
        end;
      until (P = 0) or (Text = '');
    end
    else
    begin
      Node := List.FirstChild;
      while Node <> nil do
      begin
        if (Node.NodeType = ELEMENT_NODE) and (Node.NodeName = 'TimeStamp') then
        begin
          if N >= Length(AStamps) then
            SetLength(AStamps, Max(16, N * 2));
          AStamps[N] := (QWord(AttrInt64(TDOMElement(Node), 'HighInteger')) shl 32)
            or (QWord(AttrInt64(TDOMElement(Node), 'LowInteger')) and $FFFFFFFF);
          Inc(N);
        end;
        Node := Node.NextSibling;
      end;
    end;
    SetLength(AStamps, N);
    if N > 0 then
      AImage.Acquired := LifTimeToDate(AStamps[0]);
  end;

  { The frames (Day 26): along t if there is time, else along z; their
    times from the stamps (one per plane and channel, in the file's
    order: frame f's first stamp at f * (stamps / frames)); a z with
    step 0 and running times is time at one plane. }
  procedure ReadStack(var AImage: TLifImage; const AStamps: TQWordArrayLif);
  var
    Per, F, N: Integer;
    Steps: array of Double;
    T: Double;
  begin
    AImage.Usable := -1;
    AImage.FrameTimes := nil;
    AImage.FrameInterval := 0;
    AImage.FakeZ := False;
    if AImage.TCount > 1 then
      AImage.FrameCount := AImage.TCount
    else
      AImage.FrameCount := AImage.ZCount;
    if AImage.FrameCount <= 1 then
    begin
      AImage.FrameCount := 1;
      AImage.StackKind := lsNone;
      Exit;
    end;
    { The times, when there are stamps for every frame. }
    N := AImage.FrameCount;
    if (Length(AStamps) >= N) and (Length(AStamps) mod N = 0) then
    begin
      Per := Length(AStamps) div N;
      SetLength(AImage.FrameTimes, N);
      for F := 0 to N - 1 do
      begin
        if AStamps[F * Per] >= AStamps[0] then
          T := (AStamps[F * Per] - AStamps[0]) / 1e7
        else
          T := 0;
        AImage.FrameTimes[F] := T;
      end;
      { The median step (a short last one doesn't move it). }
      SetLength(Steps, N - 1);
      for F := 1 to N - 1 do
        Steps[F - 1] := AImage.FrameTimes[F] - AImage.FrameTimes[F - 1];
      for F := 1 to High(Steps) do
      begin
        T := Steps[F];
        Per := F - 1;
        while (Per >= 0) and (Steps[Per] > T) do
        begin
          Steps[Per + 1] := Steps[Per];
          Dec(Per);
        end;
        Steps[Per + 1] := T;
      end;
      AImage.FrameInterval := Steps[Length(Steps) div 2];   { the upper middle }
      if AImage.FrameInterval < 0 then
        AImage.FrameInterval := 0;
    end;
    if AImage.TCount > 1 then
    begin
      AImage.StackKind := lsTime;
      if (AImage.TimeStep <= 0) and (AImage.FrameInterval > 0) then
        AImage.TimeStep := AImage.FrameInterval;
    end
    else if (AImage.ZStep <= 0) and (AImage.FrameInterval > 0) then
    begin
      { Begin = End: the focus never moved, the planes are time points. }
      AImage.StackKind := lsTime;
      AImage.FakeZ := True;
    end
    else
      AImage.StackKind := lsDepth;
  end;

  procedure AddImage(AElement, AImageNode, AMemory: TDOMElement; const APath: string);
  var
    Img: TLifImage;
    Desc, Group: TDOMElement;
    Node: TDOMNode;
    Dim: TLifDimension;
    Ch: TLifChannel;
    I, Bits: Integer;
    ChannelNames: string;
    Stamps: TQWordArrayLif;
  begin
    Img := Default(TLifImage);
    Img.Name := Attr(AElement, 'Name');
    Img.Path := APath;
    Img.Width := 1;
    Img.Height := 1;
    Img.ZCount := 1;
    Img.TCount := 1;
    Img.BlockId := Attr(AMemory, 'MemoryBlockID');
    if not FindBlock(Img.BlockId, Img.BlockOffset, Img.BlockSize) then
      Img.BlockOffset := -1;
    Desc := ChildElement(AImageNode, 'ImageDescription');

    Group := ChildElement(Desc, 'Dimensions');
    if Group <> nil then
    begin
      Node := Group.FirstChild;
      while Node <> nil do
      begin
        if (Node.NodeType = ELEMENT_NODE) and (Node.NodeName = 'DimensionDescription') then
        begin
          Dim.Id := AttrInt(TDOMElement(Node), 'DimID');
          Dim.Count := Max(1, AttrInt(TDOMElement(Node), 'NumberOfElements', 1));
          { The size, not the direction: LAS X writes a negative Length for
            an axis scanned the other way (a z-stack from top to bottom);
            the step is the same (1.1). }
          Dim.LengthM := Abs(AttrFloat(TDOMElement(Node), 'Length'));
          Dim.BytesInc := AttrInt64(TDOMElement(Node), 'BytesInc');
          Dim.UnitName := Attr(TDOMElement(Node), 'Unit');
          SetLength(Img.Dimensions, Length(Img.Dimensions) + 1);
          Img.Dimensions[High(Img.Dimensions)] := Dim;
          case Dim.Id of
            1:
              begin
                Img.Width := Dim.Count;
                if (Dim.Count > 1) and (Dim.LengthM > 0) then
                  Img.PixelSizeX := Dim.LengthM / (Dim.Count - 1) * 1e6;
              end;
            2:
              begin
                Img.Height := Dim.Count;
                if (Dim.Count > 1) and (Dim.LengthM > 0) then
                  Img.PixelSizeY := Dim.LengthM / (Dim.Count - 1) * 1e6;
              end;
            3:
              begin
                Img.ZCount := Dim.Count;
                if (Dim.Count > 1) and (Dim.LengthM > 0) then
                  Img.ZStep := Dim.LengthM / (Dim.Count - 1) * 1e6;
              end;
            4:
              begin
                Img.TCount := Dim.Count;
                if (Dim.Count > 1) and (Dim.LengthM > 0) then
                  Img.TimeStep := Dim.LengthM / (Dim.Count - 1);
              end;
          end;
        end;
        Node := Node.NextSibling;
      end;
    end;

    Group := ChildElement(Desc, 'Channels');
    ChannelNames := '';
    Bits := 0;
    if Group <> nil then
    begin
      Node := Group.FirstChild;
      while Node <> nil do
      begin
        if (Node.NodeType = ELEMENT_NODE) and (Node.NodeName = 'ChannelDescription') then
        begin
          Ch.LutName := Attr(TDOMElement(Node), 'LUTName');
          Ch.Resolution := Max(1, AttrInt(TDOMElement(Node), 'Resolution', 8));
          Ch.BytesInc := AttrInt64(TDOMElement(Node), 'BytesInc');
          LutColor(Ch.LutName, Ch.Red, Ch.Green, Ch.Blue);
          SetLength(Img.Channels, Length(Img.Channels) + 1);
          Img.Channels[High(Img.Channels)] := Ch;
          if ChannelNames <> '' then
            ChannelNames := ChannelNames + ', ';
          if Ch.LutName <> '' then
            ChannelNames := ChannelNames + Ch.LutName
          else
            ChannelNames := ChannelNames + IntToStr(Length(Img.Channels));
          Bits := Max(Bits, Ch.Resolution);
        end;
        Node := Node.NextSibling;
      end;
    end;

    ReadTime(AImageNode, Img, Stamps);
    ReadStack(Img, Stamps);

    { The lines for the panel: what matters for looking and measuring
      first, then how it was taken. }
    if (Img.PixelSizeX > 0) and (Img.PixelSizeY > 0) then
    begin
      if Abs(Img.PixelSizeX - Img.PixelSizeY) < 1e-6 then
        AddLine(Img, 'Pixel size: ' + FloatText(Img.PixelSizeX, 4) + ' µm')
      else
        AddLine(Img, 'Pixel size: ' + FloatText(Img.PixelSizeX, 4) + ' x '
          + FloatText(Img.PixelSizeY, 4) + ' µm');
      AddLine(Img, Format('Size: %d x %d px = %s x %s µm', [Img.Width, Img.Height,
        FloatText(Img.PixelSizeX * (Img.Width - 1), 1),
        FloatText(Img.PixelSizeY * (Img.Height - 1), 1)]));
    end
    else
      AddLine(Img, Format('Size: %d x %d px (no pixel size in the file)', [Img.Width, Img.Height]));
    if Img.FakeZ then
      AddLine(Img, Format('Time: %d points, every %s s (filed as %d z-planes at one depth)',
        [Img.ZCount, FloatText(Img.FrameInterval, 3), Img.ZCount]))
    else if Img.ZCount > 1 then
    begin
      if Img.ZStep > 0 then
        AddLine(Img, Format('Stack: %d z-planes, step %s µm', [Img.ZCount, FloatText(Img.ZStep, 3)]))
      else
        AddLine(Img, Format('Stack: %d z-planes', [Img.ZCount]));
    end;
    if Img.TCount > 1 then
    begin
      if Img.TimeStep > 0 then
        AddLine(Img, Format('Time: %d points, every %s s', [Img.TCount, FloatText(Img.TimeStep, 3)]))
      else
        AddLine(Img, Format('Time: %d points', [Img.TCount]));
    end;
    if Length(Img.Channels) > 0 then
      AddLine(Img, Format('Channels: %s (%d bit)', [ChannelNames, Bits]));
    ReadHardware(AImageNode, Img);
    if Img.Acquired > 0 then
      AddLine(Img, 'Acquired: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Img.Acquired) + ' UTC');
    for I := 0 to High(Img.Lines) do
      Img.Lines[I] := Trim(Img.Lines[I]);

    SetLength(FImages, Length(FImages) + 1);
    FImages[High(FImages)] := Img;
  end;

  procedure Walk(AChildren: TDOMElement; const APrefix: string);
  var
    Node: TDOMNode;
    Element, Data, ImageNode, Memory: TDOMElement;
    Path: string;
  begin
    if AChildren = nil then
      Exit;
    Node := AChildren.FirstChild;
    while Node <> nil do
    begin
      if (Node.NodeType = ELEMENT_NODE) and (Node.NodeName = 'Element') then
      begin
        Element := TDOMElement(Node);
        Path := APrefix + Attr(Element, 'Name');
        Data := ChildElement(Element, 'Data');
        ImageNode := ChildElement(Data, 'Image');
        Memory := ChildElement(Element, 'Memory');
        if (ImageNode <> nil) and (Memory <> nil) and (AttrInt64(Memory, 'Size') > 0) then
          AddImage(Element, ImageNode, Memory, Path);
        Walk(ChildElement(Element, 'Children'), Path + '/');
      end;
      Node := Node.NextSibling;
    end;
  end;

var
  Root, Top: TDOMElement;
begin
  Doc := nil;
  { The UTF-8 bytes as they are (a string could be converted to the
    ANSI code page on the way, outside the LCL). }
  Source := TMemoryStream.Create;
  try
    if Length(AXml) > 0 then
      Source.WriteBuffer(Pointer(AXml)^, Length(AXml));
    Source.Position := 0;
    ReadXMLFile(Doc, Source);
    Root := Doc.DocumentElement;
    Top := ChildElement(Root, 'Element');
    Walk(ChildElement(Top, 'Children'), '');
  finally
    Doc.Free;
    Source.Free;
  end;
end;

function TLifFile.Open(const AFileName: string): Boolean;
var
  Stream: TFileStream;
  Tag, Size, CharCount: LongWord;
  Sep: Byte;
  Xml: UnicodeString;
  VersionAt: Integer;
  Text: UTF8String;
begin
  Result := False;
  FFileName := AFileName;
  FImages := nil;
  FBlockIds := nil;
  FBlockOffsets := nil;
  FBlockSizes := nil;
  FErrorText := '';
  try
    Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      if Stream.Size < 13 then
      begin
        FErrorText := 'too short for a .lif';
        Exit;
      end;
      Stream.ReadBuffer(Tag, 4);
      Stream.ReadBuffer(Size, 4);
      Stream.ReadBuffer(Sep, 1);
      if (LEtoN(Tag) <> LifMagic) or (Sep <> LifSeparator) then
      begin
        FErrorText := 'not a .lif (no LIF header)';
        Exit;
      end;
      Stream.ReadBuffer(CharCount, 4);
      CharCount := LEtoN(CharCount);
      if (CharCount = 0) or (Int64(CharCount) * 2 > Stream.Size - Stream.Position) then
      begin
        FErrorText := 'the description is cut off';
        Exit;
      end;
      SetLength(Xml, CharCount);
      Stream.ReadBuffer(Xml[1], Int64(CharCount) * 2);
      Text := UTF8Encode(Xml);
      { Version="2": block sizes are 8 bytes, else 4. }
      FVersion := 2;
      VersionAt := Pos('Version="', Text);
      if (VersionAt > 0) and (VersionAt < 200) and (Copy(Text, VersionAt + 9, 2) = '1"') then
        FVersion := 1;
      ReadBlockIndex(Stream);
    finally
      Stream.Free;
    end;
    ParseXml(Text);
    Result := True;
  except
    on E: Exception do
    begin
      FImages := nil;
      FErrorText := E.Message;
    end;
  end;
end;

{ Where channel AChannel's plane (AZ, AT) starts in the block, and the
  steps between its pixels and rows. }
procedure PlaneLayout(const AImage: TLifImage; AChannel, AZ, AT: Integer;
  out AStart, AXInc, AYInc: Int64; out ASampleBytes: Integer);
var
  I: Integer;
begin
  AStart := AImage.Channels[AChannel].BytesInc;
  if AImage.Channels[AChannel].Resolution > 8 then
    ASampleBytes := 2
  else
    ASampleBytes := 1;
  AXInc := ASampleBytes;
  AYInc := Int64(AImage.Width) * ASampleBytes;
  for I := 0 to High(AImage.Dimensions) do
    case AImage.Dimensions[I].Id of
      1: AXInc := AImage.Dimensions[I].BytesInc;
      2: AYInc := AImage.Dimensions[I].BytesInc;
      3: AStart := AStart + Int64(AZ) * AImage.Dimensions[I].BytesInc;
      4: AStart := AStart + Int64(AT) * AImage.Dimensions[I].BytesInc;
    end;
  if AXInc <= 0 then
    AXInc := ASampleBytes;
  if AYInc <= 0 then
    AYInc := Int64(AImage.Width) * AXInc;
end;

function TLifFile.ReadChannelPlane(AIndex, AChannel, AZ, AT: Integer;
  out AValues: TWordArrayLif): Boolean;
var
  Img: TLifImage;
  Start, XInc, YInc, Span: Int64;
  SampleBytes, X, Y: Integer;
  Buffer: TBytes;
  Stream: TFileStream;
  P: Int64;
begin
  Result := False;
  AValues := nil;
  if (AIndex < 0) or (AIndex > High(FImages)) then
    Exit;
  Img := FImages[AIndex];
  if (AChannel < 0) or (AChannel > High(Img.Channels)) or (AZ < 0) or (AZ >= Img.ZCount)
    or (AT < 0) or (AT >= Img.TCount) or (Img.BlockOffset < 0) then
    Exit;
  PlaneLayout(Img, AChannel, AZ, AT, Start, XInc, YInc, SampleBytes);
  { The bytes from the plane's first sample to its last. }
  Span := Int64(Img.Height - 1) * YInc + Int64(Img.Width - 1) * XInc + SampleBytes;
  if (Start < 0) or (Span <= 0) or (Span > MaxPlaneBytes) or (Start + Span > Img.BlockSize) then
  begin
    FErrorText := 'the plane lies outside its block';
    Exit;
  end;
  SetLength(Buffer, Span);
  try
    Stream := TFileStream.Create(FFileName, fmOpenRead or fmShareDenyNone);
    try
      Stream.Position := Img.BlockOffset + Start;
      Stream.ReadBuffer(Buffer[0], Span);
    finally
      Stream.Free;
    end;
  except
    on E: Exception do
    begin
      FErrorText := E.Message;
      Exit;
    end;
  end;
  SetLength(AValues, Int64(Img.Width) * Img.Height);
  for Y := 0 to Img.Height - 1 do
    for X := 0 to Img.Width - 1 do
    begin
      P := Int64(Y) * YInc + Int64(X) * XInc;
      if SampleBytes = 1 then
        AValues[Int64(Y) * Img.Width + X] := Buffer[P]
      else
        AValues[Int64(Y) * Img.Width + X] := Buffer[P] or (Word(Buffer[P + 1]) shl 8);
    end;
  Result := True;
end;

{ A frame's planes: along t (all z of it when there is z too), else
  along z. }
procedure TLifFile.FramePlane(const AImage: TLifImage; AFrame: Integer; out AZ, AT: Integer);
begin
  if AImage.TCount > 1 then
  begin
    AT := AFrame;
    if AImage.ZCount > 1 then
      AZ := -1
    else
      AZ := 0;
  end
  else
  begin
    AT := 0;
    AZ := AFrame;
  end;
end;

{ The maximum of the planes (AZs[i], ATs[i]) per channel, the channels
  added in their colours. }
function TLifFile.RenderPlanes(AIndex: Integer; const AZs, ATs: array of Integer;
  out AWidth, AHeight: Integer; out ARGBA: TBytes; ACancel: TLifCancel): Boolean;
var
  Img: TLifImage;
  Sums: array of LongWord;      { R G B per pixel, added over the channels }
  Best, Plane: TWordArrayLif;
  Ch, P, Shift, I: Integer;
  Count: Integer;
  V: LongWord;
begin
  Result := False;
  AWidth := 0;
  AHeight := 0;
  ARGBA := nil;
  if (AIndex < 0) or (AIndex > High(FImages)) or (Length(AZs) = 0)
    or (Length(AZs) <> Length(ATs)) then
    Exit;
  Img := FImages[AIndex];
  if Length(Img.Channels) = 0 then
    Exit;
  if Int64(Img.Width) * Img.Height > High(Integer) div 4 then
  begin
    FErrorText := 'too large to show at once';
    Exit;
  end;
  Count := Img.Width * Img.Height;
  SetLength(Sums, Count * 3);
  for Ch := 0 to High(Img.Channels) do
  begin
    Best := nil;
    for P := 0 to High(AZs) do
    begin
      if Assigned(ACancel) and ACancel() then
        Exit;
      if not ReadChannelPlane(AIndex, Ch, AZs[P], ATs[P], Plane) then
        Exit;
      if Best = nil then
        Best := Plane
      else
        for I := 0 to Count - 1 do
          if Plane[I] > Best[I] then
            Best[I] := Plane[I];
    end;
    { To 8 bits, then in the channel's colour. }
    Shift := Max(0, Min(8, Img.Channels[Ch].Resolution - 8));
    for I := 0 to Count - 1 do
    begin
      V := ClampByte(LongWord(Best[I]) shr Shift);
      Inc(Sums[I * 3], V * Img.Channels[Ch].Red div 255);
      Inc(Sums[I * 3 + 1], V * Img.Channels[Ch].Green div 255);
      Inc(Sums[I * 3 + 2], V * Img.Channels[Ch].Blue div 255);
    end;
  end;
  SetLength(ARGBA, Count * 4);
  for I := 0 to Count - 1 do
  begin
    ARGBA[I * 4] := ClampByte(Sums[I * 3]);
    ARGBA[I * 4 + 1] := ClampByte(Sums[I * 3 + 1]);
    ARGBA[I * 4 + 2] := ClampByte(Sums[I * 3 + 2]);
    ARGBA[I * 4 + 3] := 255;
  end;
  AWidth := Img.Width;
  AHeight := Img.Height;
  Result := True;
end;

function TLifFile.RenderRGBA(AIndex, AZ, AT: Integer; out AWidth, AHeight: Integer;
  out ARGBA: TBytes; ACancel: TLifCancel): Boolean;
var
  Img: TLifImage;
  Zs, Ts: array of Integer;
  F, Frames, Z, T, Zi, N: Integer;
begin
  AWidth := 0;
  AHeight := 0;
  ARGBA := nil;
  Result := False;
  if (AIndex < 0) or (AIndex > High(FImages)) then
    Exit;
  if AZ >= 0 then
    Exit(RenderPlanes(AIndex, [AZ], [AT], AWidth, AHeight, ARGBA, ACancel));
  { The projection of the usable frames (a cut-off last one left out). }
  Frames := UsableFrameCount(AIndex);
  Img := FImages[AIndex];
  SetLength(Zs, Frames * Max(1, Img.ZCount));
  SetLength(Ts, Length(Zs));
  N := 0;
  for F := 0 to Frames - 1 do
  begin
    FramePlane(Img, F, Z, T);
    if Z < 0 then
      for Zi := 0 to Img.ZCount - 1 do
      begin
        Zs[N] := Zi;
        Ts[N] := T;
        Inc(N);
      end
    else
    begin
      Zs[N] := Z;
      Ts[N] := T;
      Inc(N);
    end;
  end;
  SetLength(Zs, N);
  SetLength(Ts, N);
  Result := RenderPlanes(AIndex, Zs, Ts, AWidth, AHeight, ARGBA, ACancel);
end;

function TLifFile.RenderFrameRGBA(AIndex, AFrame: Integer; out AWidth, AHeight: Integer;
  out ARGBA: TBytes; ACancel: TLifCancel): Boolean;
var
  Img: TLifImage;
  Zs, Ts: array of Integer;
  Z, T, Zi: Integer;
begin
  AWidth := 0;
  AHeight := 0;
  ARGBA := nil;
  Result := False;
  if (AIndex < 0) or (AIndex > High(FImages)) then
    Exit;
  Img := FImages[AIndex];
  if (AFrame < 0) or (AFrame >= Img.FrameCount) then
  begin
    FErrorText := 'no such frame';
    Exit;
  end;
  FramePlane(Img, AFrame, Z, T);
  if Z >= 0 then
    Exit(RenderPlanes(AIndex, [Z], [T], AWidth, AHeight, ARGBA, ACancel));
  SetLength(Zs, Img.ZCount);
  SetLength(Ts, Img.ZCount);
  for Zi := 0 to Img.ZCount - 1 do
  begin
    Zs[Zi] := Zi;
    Ts[Zi] := T;
  end;
  Result := RenderPlanes(AIndex, Zs, Ts, AWidth, AHeight, ARGBA, ACancel);
end;

{ The rows at the bottom of a frame that are 0 in every channel (its
  last plane when the frame has several z: a stopped scan ends there). }
function TLifFile.ZeroTailRows(AIndex, AFrame: Integer; out ARows: Integer): Boolean;
var
  Img: TLifImage;
  Plane: TWordArrayLif;
  Ch, Z, T, Row, X, Rows: Integer;
  Zero: Boolean;
begin
  Result := False;
  ARows := 0;
  Img := FImages[AIndex];
  FramePlane(Img, AFrame, Z, T);
  if Z < 0 then
    Z := Img.ZCount - 1;
  ARows := Img.Height;
  for Ch := 0 to High(Img.Channels) do
  begin
    if not ReadChannelPlane(AIndex, Ch, Z, T, Plane) then
      Exit;
    Rows := 0;
    for Row := Img.Height - 1 downto 0 do
    begin
      Zero := True;
      for X := 0 to Img.Width - 1 do
        if Plane[Int64(Row) * Img.Width + X] <> 0 then
        begin
          Zero := False;
          Break;
        end;
      if not Zero then
        Break;
      Inc(Rows);
    end;
    ARows := Min(ARows, Rows);
    if ARows = 0 then
      Break;                     { one channel with light at the bottom: complete }
  end;
  Result := Length(Img.Channels) > 0;
end;

function TLifFile.UsableFrameCount(AIndex: Integer): Integer;
var
  Img: TLifImage;
  Last, Tail, PrevTail, Margin: Integer;
  ShortStep: Boolean;
begin
  Result := 0;
  if (AIndex < 0) or (AIndex > High(FImages)) then
    Exit;
  Img := FImages[AIndex];
  if Img.Usable >= 0 then
    Exit(Img.Usable);
  Result := Max(1, Img.FrameCount);
  Margin := Max(1, Img.Height div 16);
  { At most a few frames at the end (a stopped scan cuts one). }
  while Result > 1 do
  begin
    Last := Result - 1;
    { The time says whether it may be cut: a step clearly shorter than
      the usual one. Without times nothing is left out (a deep plane
      may well be dark at the bottom). }
    if (Length(Img.FrameTimes) <> Img.FrameCount) or (Img.FrameInterval <= 0) then
      Break;
    ShortStep := Img.FrameTimes[Last] - Img.FrameTimes[Last - 1] < 0.8 * Img.FrameInterval;
    if not ShortStep then
      Break;
    if not ZeroTailRows(AIndex, Last, Tail) or (Tail < Margin) then
      Break;
    if not ZeroTailRows(AIndex, Last - 1, PrevTail) or (Tail < PrevTail + Margin) then
      Break;
    Dec(Result);
  end;
  FImages[AIndex].Usable := Result;
end;

function StackSummary(const AImage: TLifImage; ACount: Integer): string;
begin
  Result := '';
  case AImage.StackKind of
    lsDepth:
      begin
        Result := 'z ' + IntToStr(ACount);
        if AImage.ZStep > 0 then
          Result := Result + ' × ' + FloatToStrF(AImage.ZStep, ffGeneral, 3, 0, LifFormat) + ' µm';
      end;
    lsTime:
      begin
        Result := 't ' + IntToStr(ACount);
        if AImage.FrameInterval > 0 then
          Result := Result + ' × ' + FloatToStrF(AImage.FrameInterval, ffGeneral, 2, 0, LifFormat)
            + ' s'
        else if AImage.TimeStep > 0 then
          Result := Result + ' × ' + FloatToStrF(AImage.TimeStep, ffGeneral, 2, 0, LifFormat) + ' s';
      end;
  end;
end;

initialization
  LifFormat := DefaultFormatSettings;
  LifFormat.DecimalSeparator := '.';
  LifFormat.ThousandSeparator := ',';
end.
