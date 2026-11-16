unit uMediaLoader;

{
  Unit: uMediaLoader

  Purpose
  -------
  Decodes image files into IDecodedImage (spec §4.2, §7).

  Owns
  ----
  - Nothing. It keeps no state between calls, so the decode workers
    can call it from their own threads (spec §4.2: "stateless").
  - Its only fields are three settings (AutoRotate, UseWic,
    UseWicQuickView; all True by default), set by TMView before the
    workers start.
  - Per call, temporaries it frees itself: the file data
    (TMemoryStream or TBytes), a TProgressAdapter for BGRABitmap's
    reader, intermediate bitmaps. The finished bitmap, screen copy and
    animation go into the TDecodedImage it returns.

  Knows
  -----
  - The cancel callback handed to Load (the job's check).
  - The global IOGate (uIOGate): BeginPriorityRead / EndPriorityRead
    for display jobs, YieldToDisplay for preloads.
  - uMemoryGuard: DecodeFits, PhysicalMemoryBytes, EImageTooLarge.
  - The decoders it calls: uJpegDecoder, uJpegHeader,
    uExifOrientation, uGifDecoder, uTiffQuick, uWicDecoder, and
    BGRABitmap's readers; uImageScaling for the screen copies.
  - TMView creates and frees the loader; TJobScheduler's workers
    call it.

  Responsibilities
  ----------------
  - Decode a supported file into 32-bit BGRA pixels.
  - Honour a cancel check, so an obsolete decode can stop early
    (spec §5.6).
  - Make a screen-size copy on the calling (worker) thread, so the UI
    thread never has to scale a huge image down itself (spec §7.1).
  - Quality levels (spec §7.1). Asked for qlScreen, a JPEG is decoded
    at 1/2, 1/4 or 1/8 size, just large enough for the screen, which
    is several times faster (WIC scaling inside the codec, or the own
    decoder's DCT scaling). Other formats (and JPEGs that are not
    larger than the screen) are always decoded in full; the result
    then says qlFull.
  - Preview quality (Phase E): asked for qlPreview, a JPEG's EXIF
    thumbnail is decoded (uJpegHeader reads only the start of the
    file), turned upright and cut to the main image's shape. Files
    without one give an error entry with NoPreviewMessage, which the
    caller treats as "none", not as a broken file.
  - Preloads (not display jobs) let a display job read first: they
    wait at the I/O gate before reading, and between bands (spec §2.2).
  - Uncompressed strip TIFF, Screen quality: uTiffQuick reads only the
    rows it needs (2 of every S), a quarter of the file at S = 8.
  - LZW strip TIFF, both qualities: uTiffQuick's own LZW decoder
    (Day 19; WIC took about 4.5 s for a 108 MP file).
  - 3D models (.stl, 1.3, uStlModel): drawn as the model starts, at
    twice the screen size (at most about 4K) with a screen-size copy,
    as qlFull at once (RenderStlImage; TMView draws it again when it
    is turned or cut).
  - GIF (Day 19, uGifDecoder): Screen quality is the first frame only
    (read from the start of the file); it says qlScreen if more frames
    follow, qlFull for a still GIF. Full quality is every frame, as a
    TAnimation on the result (Bitmap = the first frame). Files that
    aren't really GIFs go to BGRABitmap.
  - TIFF, PNG and BMP (with UseWic): WIC reads the file directly, in
    bands (for TIFF whole strips), cancellable between bands. Screen
    quality is averaged down while the bands come in (only a
    screen-size bitmap is allocated, not 432 MB for a 108 MP image, or
    1.9 GB for NASA's 21600 x 21600 PNGs); Full is the whole image plus
    a screen copy, after the memory guard. If WIC can't read a file,
    BGRABitmap's reader takes over. (PNG and BMP went to BGRABitmap
    until Day 19: always in full, no size check before allocating, no
    cancel.)
  - EXIF orientation (AutoRotate): phone and camera JPEGs are turned
    upright on the worker, at both quality levels, before the screen
    copy is made. FullWidth/FullHeight are then the upright size.
  - The I/O gate (spec §5.5): for display jobs the file is read with
    the gate raised, so the directory scanner waits meanwhile.
  - Refuse early, with a clear message: a missing file, an
    unsupported extension, an empty file (0 bytes), a JPEG whose
    header claims more than 1000 pixels per byte of file, a GIF over
    1 GB, and any size uMemoryGuard says won't fit. Files named .jpg
    that aren't JPEGs go to BGRABitmap, which detects the format.
  - Turn every failure (missing, unreadable, corrupt, unsupported,
    cancelled) into an error entry instead of an exception, so
    navigation never stops on a bad file (spec §3.1, §7.4).

  Does NOT
  --------
  - Schedule, cache, or know about threads. (Two exceptions:
    ThreadStart / ThreadEnd set up COM for WIC on each worker, and
    uTiffQuick may run its own helper threads within one call.)
  - Draw anything.

  Threads
  -------
  Load runs on the decode workers (TDecodeWorker in uJobScheduler),
  several at once, never on the UI thread. No lock is needed: the
  settings are only read once the workers run, and every call works
  on its own objects. IOGate protects itself. Each worker calls
  ThreadStart before its first job and ThreadEnd after its last.

  Uses (MView units)
  ------------------
  interface:      uTypes, uImageFormats, uDecodedImage, uJpegDecoder,
                  uExifOrientation, uJpegHeader, uTiffQuick,
                  uAnimation, uGifDecoder, uImageScaling, uWicDecoder,
                  uIOGate, uMemoryGuard, uStopwatch
  implementation: uIconFile
  Libraries:      Classes, SysUtils, Math, FPImage, BGRABitmap,
                  BGRABitmapTypes

  Used by
  -------
  uJobScheduler, uMView

  Notes on cancellation
  ---------------------
  Cancellation is cooperative; each path checks in its own way:
  - JPEG through WIC (tried first): before and after the decode; the
    own decoder (uJpegDecoder, the fallback) every 16 rows.
  - TIFF / PNG / BMP in WIC bands (LoadWicBands): between bands.
  - TIFF through uTiffQuick: between rows / strips.
  - GIF (uGifDecoder): every 262144 pixels.
  - The rest goes through BGRABitmap / the FPC readers, which report
    progress through the bitmap's OnProgress event; answering
    Continue := False asks the reader to stop. Not every reader asks
    often (the FPC JPEG reader only at start and end, which is why
    JPEGs have their own decoder), so such a decode can still run to
    its end.
  The cancel check is also asked before the decode and before the
  screen-size copy.
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  Math,
  FPImage,
  BGRABitmap,
  BGRABitmapTypes,
  uTypes,
  uImageFormats,
  uDecodedImage,
  uStlModel,
  uJpegDecoder,
  uExifOrientation,
  uJpegHeader,
  uTiffQuick,
  uAnimation,
  uGifDecoder,
  uImageScaling,
  uWicDecoder,
  uIOGate,
  uMemoryGuard,
  uStopwatch,
  uContainers;

{ A picture of an .ico held in memory (1.1): the entry that fits ASize
  best (uIconFile.ChooseIconEntry; ASize 0 or larger than every entry:
  the largest), PNG entries through BGRABitmap, old-style ones through
  DecodeIconDib. nil if it can't be read. Any thread. Also used by
  uSortIcons. }
function DecodeIconBitmap(const ABytes: TBytes; ASize: Integer): TBGRABitmap;

const
  { The error text of a qlPreview result when the file has no cheap
    preview: not a failure of the file. }
  NoPreviewMessage = 'No preview in this file';

type

  TMediaLoader = class(TObject)
  private
    FAutoRotate: Boolean;
    FUseWic: Boolean;
    FUseWicQuickView: Boolean;
  public
    constructor Create;

    { Each decode worker thread calls these around its work (COM for
      WIC). }
    procedure ThreadStart;
    procedure ThreadEnd;
    { AQuality: qlPreview (the embedded thumbnail, or an error entry
      with NoPreviewMessage), qlScreen (enough to fit the screen) or
      qlFull. For qlScreen / qlFull the result may be better than
      asked for, never worse.
      APreviewWidth / APreviewHeight: the screen size. A full decode
      larger than that also gets a scaled-down copy of about that size.
      APriorityRead: raise the I/O gate while reading the file. }
    function Load(const AFileName: string; AQuality: TQualityLevel;
      ACancel: TCancelCheck = nil;
      APreviewWidth: Integer = 0; APreviewHeight: Integer = 0;
      APriorityRead: Boolean = False): IDecodedImage;

    { Turn JPEGs upright by their EXIF orientation. Set before the
      decode workers start; they only read it. }
    property AutoRotate: Boolean read FAutoRotate write FAutoRotate;

    { Full-size JPEGs with the Windows Imaging Component (much faster);
      the Pascal decoder remains the fallback. Set before the workers
      start. }
    property UseWic: Boolean read FUseWic write FUseWic;
    { Quick views (Screen quality) of JPEGs scaled inside the WIC codec
      (Phase E); the Pascal decoder remains the fallback. Set before
      the workers start. }
    property UseWicQuickView: Boolean read FUseWicQuickView write FUseWicQuickView;
  end;

{ A 3D model (.stl, 1.3) as a picture for a screen (or window) of
  AScreenWidth x AScreenHeight. AQuality: drawn at twice that size (at
  most about 4K) with a screen-size copy, as qlFull; else quickly at
  the screen size, as qlScreen (TMView while the model is turned). Both
  say the same full size, so the view stays when one replaces the
  other. An error entry if the file can't be read. Any thread. }
function RenderStlImage(const AKey: TImageKey; const AView: TStlView;
  AScreenWidth, AScreenHeight: Integer; AQuality: Boolean;
  ACancel: TCancelCheck = nil): IDecodedImage;

{ True if a qlPreview request can succeed for this file at all (JPEG
  by name; whether it has a thumbnail is only known after reading). }
function MayHavePreview(const AFileName: string): Boolean;

implementation

uses
  uIconFile,
  uPngQuick,
  uDriveHealth,
  BGRAReadPng;

type

  { Connects the FPImage progress event to a TCancelCheck. One per
    decode, so it needs no locking. }
  TProgressAdapter = class(TObject)
  public
    Cancel: TCancelCheck;
    procedure HandleProgress(Sender: TObject; Stage: TFPImgProgressStage;
      PercentDone: Byte; RedrawNow: Boolean; const R: TRect;
      const Msg: AnsiString; var Continue: Boolean);
  end;

procedure TProgressAdapter.HandleProgress(Sender: TObject; Stage: TFPImgProgressStage;
  PercentDone: Byte; RedrawNow: Boolean; const R: TRect;
  const Msg: AnsiString; var Continue: Boolean);
begin
  if Assigned(Cancel) and Cancel() then
    Continue := False;
end;

type
  { Linux port (1.4): BGRABitmap's PNG reader reports no progress, so a
    long decode from memory (a 21600 x 21600 PNG: WIC did it scaled on
    Windows) never came back to its cancel check, and after 20 s the
    worker was taken as stuck in a read: "Disk not responding". While
    a file already read into memory is decoded, this thread calls the
    cancel check every KeepAliveMs: the job's alive tick stays fresh.
    The disk read itself stays outside it, so a hung disk is still
    found. The check (TDecodeJob.WorkerCancelCheck) is safe from any
    thread. }
  TDecodeKeepAlive = class(TThread)
  private
    FCancel: TCancelCheck;
    FStop: PRTLEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(ACancel: TCancelCheck);
    destructor Destroy; override;
    { Stops the thread, waits for it, frees it. }
    procedure Finish;
  end;

const
  KeepAliveMs = 500;
  { Read in parts this large, with a cancel check after each. }
  ReadPartBytes = 8 * 1024 * 1024;

constructor TDecodeKeepAlive.Create(ACancel: TCancelCheck);
begin
  FCancel := ACancel;
  FStop := RTLEventCreate;
  FreeOnTerminate := False;
  inherited Create(False);
end;

destructor TDecodeKeepAlive.Destroy;
begin
  RTLEventDestroy(FStop);
  inherited Destroy;
end;

procedure TDecodeKeepAlive.Execute;
begin
  while not Terminated do
  begin
    RTLEventWaitFor(FStop, KeepAliveMs);
    if Terminated then
      Break;
    if Assigned(FCancel) then
      FCancel();
  end;
end;

procedure TDecodeKeepAlive.Finish;
begin
  Terminate;
  RTLEventSetEvent(FStop);
  WaitFor;
  Free;
end;

{ 1.4 (Day 40): opening and reading with the OS error kept. A media
  error (CRC, corrupt, device I/O ...) marks the drive as in trouble
  (uDriveHealth: no preloads from it for a while, a notice); every
  failure raises, so the loader makes an error entry with the reason
  (a failed read used to look like the end of the file). }
procedure DriveError(const AFileName, AAction: string; ACode: Integer);
begin
  if IsMediaErrorCode(ACode) then
    NoteDriveTrouble(AFileName, Format('%s while reading %s', [SysErrorMessage(ACode),
      ExtractFileName(AFileName)]));
  raise EInOutError.CreateFmt('%s "%s": %s', [AAction, ExtractFileName(AFileName),
    SysErrorMessage(ACode)]);
end;

function OpenForRead(const AFileName: string): THandle;
begin
  Result := FileOpen(AFileName, fmOpenRead or fmShareDenyNone);
  if Result = feInvalidHandle then
    DriveError(AFileName, 'Cannot open', GetLastOSError);
end;

function ReadChecked(AHandle: THandle; const AFileName: string; var ABuffer;
  ACount: Integer): Integer;
begin
  Result := FileRead(AHandle, ABuffer, ACount);
  if Result < 0 then
    DriveError(AFileName, 'Read error in', GetLastOSError);
end;

function HandleSize(AHandle: THandle): Int64;
begin
  Result := FileSeek(AHandle, Int64(0), fsFromEnd);
  FileSeek(AHandle, Int64(0), fsFromBeginning);
end;

{ Reads the whole file into AData in parts, checking ACancel between
  them (the alive tick, and a cancel). False if cancelled. }
function ReadWholeFile(const AFileName: string; AData: TMemoryStream;
  ACancel: TCancelCheck): Boolean;
var
  H: THandle;
  Total, Got: Int64;
  Part: Integer;
begin
  Result := False;
  H := OpenForRead(AFileName);
  try
    Total := HandleSize(H);
    if Total < 0 then
      Total := 0;
    AData.SetSize(Total);
    Got := 0;
    while Got < Total do
    begin
      if Assigned(ACancel) and ACancel() then
        Exit;
      Part := Integer(Min(Int64(ReadPartBytes), Total - Got));
      Part := ReadChecked(H, AFileName, (PByte(AData.Memory) + Got)^, Part);
      if Part <= 0 then
        Break;
      Inc(Got, Part);
    end;
    AData.SetSize(Got);
    AData.Position := 0;
    Result := True;
  finally
    FileClose(H);
  end;
end;

function IsCancelled(ACancel: TCancelCheck): Boolean;
begin
  Result := Assigned(ACancel) and ACancel();
end;

function IsJpegFileName(const AFileName: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  Result := (Ext = '.jpg') or (Ext = '.jpeg') or (Ext = '.jpe');
end;

{ The screen copy for a full image larger than the screen: exactly the
  size the image has when fitted into AWidth x AHeight, so the
  renderer draws it 1:1 (uImageScaling.FitSize). nil otherwise. }
function MakePreview(ABitmap: TBGRABitmap; AWidth, AHeight: Integer): TBGRACustomBitmap;
var
  FitW, FitH: Integer;
begin
  Result := nil;
  if (AWidth <= 0) or (AHeight <= 0) then
    Exit;
  FitSize(ABitmap.Width, ABitmap.Height, AWidth, AHeight, FitW, FitH);
  if (FitW < ABitmap.Width) or (FitH < ABitmap.Height) then
    Result := ShrinkToSize(ABitmap, FitW, FitH);
end;

function LoadOther(const AKey: TImageKey; ACancel: TCancelCheck;
  APreviewWidth, APreviewHeight: Integer; APriorityRead: Boolean): IDecodedImage; forward;

function RenderStlImage(const AKey: TImageKey; const AView: TStlView;
  AScreenWidth, AScreenHeight: Integer; AQuality: Boolean;
  ACancel: TCancelCheck): IDecodedImage;
const
  MaxFullPixels = 3840 * 2160;
var
  Model: IStlModel;
  Bitmap: TBGRABitmap;
  Preview: TBGRACustomBitmap;
  W, H, FullW, FullH: Integer;
  Scale, StartMs, DecodeMs, PreviewStartMs: Double;
begin
  StartMs := NowMs;
  W := AScreenWidth;
  H := AScreenHeight;
  if (W <= 0) or (H <= 0) then
  begin
    W := 1920;
    H := 1080;
  end;
  Scale := 2;
  if Double(W) * H * Scale * Scale > MaxFullPixels then
    Scale := Max(1, Sqrt(MaxFullPixels / (Double(W) * H)));
  FullW := Round(W * Scale);
  FullH := Round(H * Scale);
  Bitmap := nil;
  Preview := nil;
  try
    Model := StlModelFor(AKey, ACancel);
    if AQuality then
      Bitmap := Model.Render(AView, FullW, FullH, Scale, ACancel)
    else
      Bitmap := Model.Render(AView, W, H, 1, ACancel);
    if Bitmap = nil then
      Exit(TDecodedImage.CreateError(AKey, 'Cancelled'));
    DecodeMs := NowMs - StartMs;
    if AQuality then
    begin
      PreviewStartMs := NowMs;
      Preview := MakePreview(Bitmap, W, H);
      Result := TDecodedImage.Create(AKey, qlFull, Bitmap, Preview, DecodeMs,
        NowMs - PreviewStartMs);
    end
    else
      Result := TDecodedImage.Create(AKey, qlScreen, Bitmap, nil, DecodeMs, 0, FullW, FullH);
  except
    on E: Exception do
    begin
      Preview.Free;
      Bitmap.Free;
      Result := TDecodedImage.CreateError(AKey, E.Message, NowMs - StartMs);
    end;
  end;
end;
function OrientBitmap(ABitmap: TBGRABitmap; AOrientation: Integer): TBGRABitmap; forward;

function MayHavePreview(const AFileName: string): Boolean;
begin
  Result := IsJpegFileName(AFileName) and not IsVirtualName(AFileName);
end;

const
  { Thumbnails smaller than this (either side) are not worth showing. }
  MinPreviewSide = 40;
  { ... and larger ones are not thumbnails (4 MP; real ones are well
    under 1 MP). }
  MaxThumbnailPixels = 4000000;

  { Rows per WIC call for TIFF: whole strips of the common strip
    heights (IrfanView writes 1024-row strips). }
  TiffBandRows = 1024;

function IsTiffFileName(const AFileName: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  Result := (Ext = '.tif') or (Ext = '.tiff');
end;

{ Formats read through WIC in bands (see LoadWicBands). }
function IsWicBandFileName(const AFileName: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  Result := IsTiffFileName(AFileName) or (Ext = '.png') or (Ext = '.bmp');
end;

{ TIFF, PNG, BMP through WIC (TIFF: the own quick readers first). nil
  if WIC can't read the file (the caller then uses BGRABitmap's
  reader). }
function LoadWicBands(const AKey: TImageKey; AQuality: TQualityLevel;
  ACancel: TCancelCheck; APreviewWidth, APreviewHeight: Integer;
  APriorityRead: Boolean): IDecodedImage;
var
  Bitmap, Shrunk: TBGRABitmap;
  Preview: TBGRACustomBitmap;
  FullW, FullH, Scale, FitW, FitH: Integer;
  StartMs, DecodeMs, ShrinkStartMs: Double;
  Handled, IsTiff: Boolean;
  BandRows: Integer;
begin
  Result := nil;
  Bitmap := nil;
  Preview := nil;
  StartMs := NowMs;
  IsTiff := IsTiffFileName(AKey.FileName);
  { TIFF: whole strips per call. Others: about 8 MB per call. }
  if IsTiff then
    BandRows := TiffBandRows
  else
    BandRows := 0;
  try
    { The file is read while it is decoded: the gate stays raised for
      the whole decode of a display job. }
    if APriorityRead then
      IOGate.BeginPriorityRead;
    try
      Handled := False;
      { Quick view of an uncompressed TIFF: only the rows needed. }
      if IsTiff and (AQuality < qlFull) then
        Bitmap := LoadUncompressedTiffQuick(AKey.FileName, APreviewWidth, APreviewHeight,
          ACancel, not APriorityRead, Handled, FullW, FullH, Scale);
      { LZW strip TIFF: the own decoder, quick view or full size. }
      if IsTiff and not Handled then
      begin
        if AQuality >= qlFull then
          Bitmap := LoadLzwTiff(AKey.FileName, 0, 0, ACancel, not APriorityRead,
            Handled, FullW, FullH, Scale)
        else
          Bitmap := LoadLzwTiff(AKey.FileName, APreviewWidth, APreviewHeight, ACancel,
            not APriorityRead, Handled, FullW, FullH, Scale);
      end;
      { Everything else: WIC. }
      if not Handled then
      begin
        if AQuality >= qlFull then
          Bitmap := DecodeFileWithWic(AKey.FileName, 0, 0, BandRows, ACancel,
            not APriorityRead, FullW, FullH, Scale)
        else
          Bitmap := DecodeFileWithWic(AKey.FileName, APreviewWidth, APreviewHeight,
            BandRows, ACancel, not APriorityRead, FullW, FullH, Scale);
      end;
    finally
      if APriorityRead then
        IOGate.EndPriorityRead;
    end;
    if Bitmap = nil then
      Exit(TDecodedImage.CreateError(AKey, 'Cancelled'));
    DecodeMs := NowMs - StartMs;

    ShrinkStartMs := NowMs;
    if Scale > 1 then
    begin
      { Averaged down while reading; now exactly to the fitted size,
        so the renderer draws it 1:1. }
      FitSize(FullW, FullH, APreviewWidth, APreviewHeight, FitW, FitH);
      if (Bitmap.Width > FitW) or (Bitmap.Height > FitH) then
      begin
        Shrunk := ShrinkToSize(Bitmap, FitW, FitH);
        Bitmap.Free;
        Bitmap := Shrunk;
      end;
      Result := TDecodedImage.Create(AKey, qlScreen, Bitmap, nil,
        DecodeMs, NowMs - ShrinkStartMs, FullW, FullH);
    end
    else
    begin
      Preview := MakePreview(Bitmap, APreviewWidth, APreviewHeight);
      Result := TDecodedImage.Create(AKey, qlFull, Bitmap, Preview,
        DecodeMs, NowMs - ShrinkStartMs);
    end;
    Bitmap := nil;    { owned by the result now }
    Preview := nil;
  except
    on E: EOutOfMemory do
    begin
      Preview.Free;
      Bitmap.Free;
      Result := TDecodedImage.CreateError(AKey, E.Message, NowMs - StartMs);
    end;
    on E: EImageTooLarge do
    begin
      Preview.Free;
      Bitmap.Free;
      Result := TDecodedImage.CreateError(AKey, E.Message, NowMs - StartMs);
    end;
    on E: Exception do
    begin
      Preview.Free;
      Bitmap.Free;
      Result := nil;   { WIC can't: the other reader }
    end;
  end;
end;

{ The EXIF thumbnail as Preview quality. Reads only the start of the
  file. Any problem means "no preview": the Screen decode follows
  anyway and reports real errors. }
function LoadJpegPreview(const AKey: TImageKey; ACancel: TCancelCheck;
  APriorityRead, AAutoRotate: Boolean): IDecodedImage;
var
  Head: TJpegHead;
  Data: TMemoryStream;
  Bitmap, Part: TBGRABitmap;
  FullW, FullH, Tmp, X, Y, W, H, ThumbW, ThumbH: Integer;
  StartMs: Double;
  HeadOk: Boolean;
begin
  StartMs := NowMs;
  if APriorityRead then
    IOGate.BeginPriorityRead;
  try
    HeadOk := ReadJpegHead(AKey.FileName, Head);
  finally
    if APriorityRead then
      IOGate.EndPriorityRead;
  end;
  if (not HeadOk) or (Length(Head.Thumbnail) = 0) then
    Exit(TDecodedImage.CreateError(AKey, NoPreviewMessage));
  if IsCancelled(ACancel) then
    Exit(TDecodedImage.CreateError(AKey, 'Cancelled'));

  FullW := Head.Width;
  FullH := Head.Height;
  if not AAutoRotate then
    Head.Orientation := 1;
  if OrientationSwapsSize(Head.Orientation) then
  begin
    Tmp := FullW;
    FullW := FullH;
    FullH := Tmp;
  end;

  Bitmap := nil;
  Data := TMemoryStream.Create;
  try
    try
      Data.WriteBuffer(Head.Thumbnail[0], Length(Head.Thumbnail));
      Data.Position := 0;
      { A thumbnail is small; a corrupt one may claim anything. }
      if not ReadJpegSize(Data, ThumbW, ThumbH)
        or (Int64(ThumbW) * ThumbH > MaxThumbnailPixels) then
        Exit(TDecodedImage.CreateError(AKey, NoPreviewMessage));
      Data.Position := 0;
      Bitmap := DecodeJpeg(Data, 1, ACancel, True);
      if Bitmap = nil then
        Exit(TDecodedImage.CreateError(AKey, 'Cancelled'));

      if Head.Orientation <> 1 then
        Bitmap := OrientBitmap(Bitmap, Head.Orientation);

      { Black bars of a thumbnail in another shape: cut them off. }
      AspectCrop(Bitmap.Width, Bitmap.Height, FullW, FullH, X, Y, W, H);
      if (W <> Bitmap.Width) or (H <> Bitmap.Height) then
      begin
        Part := Bitmap.GetPart(Rect(X, Y, X + W, Y + H)) as TBGRABitmap;
        Bitmap.Free;
        Bitmap := Part;
      end;

      if (Bitmap.Width < MinPreviewSide) or (Bitmap.Height < MinPreviewSide) then
      begin
        FreeAndNil(Bitmap);
        Exit(TDecodedImage.CreateError(AKey, NoPreviewMessage));
      end;

      Result := TDecodedImage.Create(AKey, qlPreview, Bitmap, nil,
        NowMs - StartMs, 0, FullW, FullH);
      Bitmap := nil;   { owned by the result now }
    except
      on E: Exception do
      begin
        FreeAndNil(Bitmap);
        Result := TDecodedImage.CreateError(AKey, NoPreviewMessage);
      end;
    end;
  finally
    Data.Free;
  end;
end;

{ Turns ABitmap as EXIF orientation AOrientation asks (see
  uExifOrientation). Returns ABitmap itself, or a new bitmap, in which
  case ABitmap has been freed. }
function OrientBitmap(ABitmap: TBGRABitmap; AOrientation: Integer): TBGRABitmap;
var
  Turned: TBGRABitmap;
begin
  Result := ABitmap;
  case AOrientation of
    2: ABitmap.HorizontalFlip;
    3: begin
         ABitmap.HorizontalFlip;
         ABitmap.VerticalFlip;
       end;
    4: ABitmap.VerticalFlip;
    5, 7, 6, 8:
      begin
        if AOrientation in [5, 7] then
          ABitmap.HorizontalFlip;
        if AOrientation in [6, 7] then
          Turned := ABitmap.RotateCW as TBGRABitmap
        else
          Turned := ABitmap.RotateCCW as TBGRABitmap;
        ABitmap.Free;
        Result := Turned;
      end;
  end;
end;

{ JPEG: read the file into memory (gate raised only for that), then
  decode it with uJpegDecoder at the scale the quality needs, and turn
  it upright (EXIF orientation). }
function LoadJpeg(const AKey: TImageKey; AQuality: TQualityLevel;
  ACancel: TCancelCheck; APreviewWidth, APreviewHeight: Integer;
  APriorityRead, AAutoRotate, AUseWic, AUseWicQuick: Boolean): IDecodedImage;
var
  Data: TMemoryStream;
  Bitmap, Shrunk: TBGRABitmap;
  Preview: TBGRACustomBitmap;
  FullW, FullH, Scale, Orientation, Tmp, FitW, FitH: Integer;
  WicTried, Fits: Boolean;
  Reason: string;
  StartMs, DecodeMs, PreviewStartMs: Double;
begin
  StartMs := NowMs;
  Bitmap := nil;
  Preview := nil;
  Data := TMemoryStream.Create;
  try
    try
      if APriorityRead then
        IOGate.BeginPriorityRead
      else
        IOGate.YieldToDisplay(ACancel);
      try
        { In parts (1.4: was LoadFromFile): the OS error is kept, and a
          cancel stops it between parts. }
        if not ReadWholeFile(AKey.FileName, Data, ACancel) then
          Exit(TDecodedImage.CreateError(AKey, 'Cancelled'));
      finally
        if APriorityRead then
          IOGate.EndPriorityRead;
      end;

      if IsCancelled(ACancel) then
        Exit(TDecodedImage.CreateError(AKey, 'Cancelled'));

      { Named .jpg but something else (or a JPEG kind the decoder
        can't read the header of): let BGRABitmap try, it detects the
        format from the content. }
      if not (IsJpegStream(Data) and ReadJpegSize(Data, FullW, FullH)) then
      begin
        FreeAndNil(Data);
        Exit(LoadOther(AKey, ACancel, APreviewWidth, APreviewHeight, APriorityRead));
      end;

      { Upright size first: the scale for the screen depends on it. }
      Orientation := 1;
      if AAutoRotate then
        Orientation := ReadExifOrientation(PByte(Data.Memory), Data.Size);
      if OrientationSwapsSize(Orientation) then
      begin
        Tmp := FullW;
        FullW := FullH;
        FullH := Tmp;
      end;

      if AQuality >= qlFull then
        Scale := 1
      else
        Scale := ChooseJpegScale(FullW, FullH, APreviewWidth, APreviewHeight);

      { A damaged header can claim a size the file can't hold: even a
        plain black JPEG needs about a byte per 160 pixels. One byte
        per 1000 is far below anything real (a 108 MP photo would need
        108 KB; real ones are about 10 MB). }
      if Int64(FullW) * FullH > Int64(AKey.FileSize) * 1000 then
        Exit(TDecodedImage.CreateError(AKey, Format(
          'Damaged file: the header claims %d x %d pixels, but the file has only %d KB',
          [FullW, FullH, AKey.FileSize div 1024]), NowMs - StartMs));

      { A corrupt header can claim any size: refuse what can't fit
        instead of paging the whole computer to disk (uMemoryGuard). }
      if Scale = 1 then
        Fits := DecodeFits(FullW, FullH,
          Int64(Max(APreviewWidth, 0)) * Max(APreviewHeight, 0) * 4, Reason)
      else
        Fits := DecodeFits((FullW + Scale - 1) div Scale, (FullH + Scale - 1) div Scale,
          0, Reason);
      if not Fits then
        Exit(TDecodedImage.CreateError(AKey, Reason, NowMs - StartMs));

      { Full size: WIC first (several times faster), the own decoder
        if WIC fails. nil from WIC = cancelled. }
      WicTried := False;
      if (Scale = 1) and AUseWic and WicAvailable then
      begin
        WicTried := True;
        try
          Bitmap := DecodeWithWic(Data, ACancel);
        except
          { Out of memory: the own decoder would need the same memory. }
          on EOutOfMemory do
            raise;
          on Exception do
          begin
            Bitmap := nil;
            WicTried := False;   { failed: use the own decoder below }
          end;
        end;
        if WicTried and (Bitmap = nil) then
          Exit(TDecodedImage.CreateError(AKey, 'Cancelled'));
      end;

      { Quick view: WIC scales inside the codec, several times faster
        than pasjpeg on large files. Not cancellable while it runs
        (one call, ~0.1-0.3 s); the own decoder if WIC can't. }
      if (Scale > 1) and AUseWicQuick and WicAvailable then
      begin
        WicTried := True;
        try
          Bitmap := DecodeWithWicScaled(Data, Scale, ACancel);
        except
          on EOutOfMemory do
            raise;
          on Exception do
          begin
            Bitmap := nil;
            WicTried := False;
          end;
        end;
        if WicTried and (Bitmap = nil) then
          Exit(TDecodedImage.CreateError(AKey, 'Cancelled'));
      end;

      { Fast DCT for the reduced sizes: the difference is invisible
        there. Full images use the accurate one. }
      if Bitmap = nil then
        Bitmap := DecodeJpeg(Data, Scale, ACancel, Scale > 1);
      DecodeMs := NowMs - StartMs;
      FreeAndNil(Data);   { the compressed data isn't needed any more }

      { nil: cancelled while decoding. A bitmap is always complete; if
        the job was cancelled only after that, the image still goes
        into the cache. }
      if Bitmap = nil then
        Exit(TDecodedImage.CreateError(AKey, 'Cancelled'));

      if Orientation <> 1 then
      begin
        Bitmap := OrientBitmap(Bitmap, Orientation);
        DecodeMs := NowMs - StartMs;
      end;

      if Scale > 1 then
      begin
        { Exactly the fitted size (uImageScaling.FitSize), so the
          renderer draws the quick view 1:1 without resampling. }
        PreviewStartMs := NowMs;
        FitSize(FullW, FullH, APreviewWidth, APreviewHeight, FitW, FitH);
        if (Bitmap.Width > FitW) or (Bitmap.Height > FitH) then
        begin
          Shrunk := ShrinkToSize(Bitmap, FitW, FitH);
          Bitmap.Free;
          Bitmap := Shrunk;
        end;
        Result := TDecodedImage.Create(AKey, qlScreen, Bitmap, nil,
          DecodeMs, NowMs - PreviewStartMs, FullW, FullH);
      end
      else
      begin
        PreviewStartMs := NowMs;
        Preview := MakePreview(Bitmap, APreviewWidth, APreviewHeight);
        Result := TDecodedImage.Create(AKey, qlFull, Bitmap, Preview,
          DecodeMs, NowMs - PreviewStartMs, FullW, FullH);
      end;
    except
      on E: EJpegCancelled do
      begin
        Preview.Free;
        Bitmap.Free;
        Result := TDecodedImage.CreateError(AKey, 'Cancelled');
      end;
      on E: Exception do
      begin
        Preview.Free;
        Bitmap.Free;
        Result := TDecodedImage.CreateError(AKey, E.Message, NowMs - StartMs);
      end;
    end;
  finally
    Data.Free;
  end;
end;

const
  { Screen quality of a GIF reads this much of the file first; the
    whole file only if the first frame isn't complete in it. }
  GifFirstFrameBytes = 8 * 1024 * 1024;
  MaxGifFileBytes = Int64(1024) * 1024 * 1024;
  GifReadChunk = 1024 * 1024;

function IsGifFileName(const AFileName: string): Boolean;
begin
  Result := LowerCase(ExtractFileExt(AFileName)) = '.gif';
end;

{ Reads up to AMaxBytes of the file, in parts, asking ACancel between
  them. False if cancelled. AComplete: the whole file was read. }
function ReadFileStart(const AFileName: string; AMaxBytes: Int64;
  ACancel: TCancelCheck; APriorityRead: Boolean;
  out AData: TBytes; out AComplete: Boolean): Boolean;
var
  H: THandle;
  Total, Want, Got: Int64;
  Part: Integer;
begin
  Result := False;
  AData := nil;
  AComplete := False;
  if APriorityRead then
    IOGate.BeginPriorityRead
  else
    IOGate.YieldToDisplay(ACancel);
  try
    H := OpenForRead(AFileName);
    try
      Total := Max(Int64(0), HandleSize(H));
      Want := Min(Total, AMaxBytes);
      SetLength(AData, Want);
      Got := 0;
      while Got < Want do
      begin
        if IsCancelled(ACancel) then
          Exit;
        Part := Integer(Min(Int64(GifReadChunk), Want - Got));
        Part := ReadChecked(H, AFileName, AData[Got], Part);
        if Part <= 0 then
          Break;
        Inc(Got, Part);
      end;
      SetLength(AData, Got);
      AComplete := Got >= Total;
      Result := True;
    finally
      FileClose(H);
    end;
  finally
    if APriorityRead then
      IOGate.EndPriorityRead;
  end;
end;

{ GIF: nil if the file isn't a GIF after all (the caller then tries
  BGRABitmap). }
function LoadGif(const AKey: TImageKey; AQuality: TQualityLevel; ACancel: TCancelCheck;
  APreviewWidth, APreviewHeight: Integer; APriorityRead: Boolean): IDecodedImage;
var
  Data: TBytes;
  Complete, FirstOnly, More, Incomplete: Boolean;
  Anim: TAnimation;
  Cursor: TAnimationCursor;
  Bitmap: TBGRABitmap;
  Preview: TBGRACustomBitmap;
  Quality: TQualityLevel;
  Error: string;
  StartMs, DecodeMs, PreviewStartMs: Double;
  MaxBytes: Int64;
begin
  Result := nil;
  Anim := nil;
  Bitmap := nil;
  Preview := nil;
  StartMs := NowMs;
  if AKey.FileSize > MaxGifFileBytes then
    Exit(TDecodedImage.CreateError(AKey, Format('GIF file too large (%d MB, limit %d MB)',
      [AKey.FileSize div (1024 * 1024), MaxGifFileBytes div (1024 * 1024)])));
  FirstOnly := AQuality < qlFull;
  { The frames may use a quarter of the memory, at most 2 GB. }
  MaxBytes := Min(PhysicalMemoryBytes div 4, Int64(2048) * 1024 * 1024);
  try
    try
      if FirstOnly then
      begin
        if not ReadFileStart(AKey.FileName, GifFirstFrameBytes, ACancel, APriorityRead,
          Data, Complete) then
          Exit(TDecodedImage.CreateError(AKey, 'Cancelled'));
      end
      else if not ReadFileStart(AKey.FileName, MaxGifFileBytes, ACancel, APriorityRead,
        Data, Complete) then
        Exit(TDecodedImage.CreateError(AKey, 'Cancelled'));

      if (Length(Data) = 0) or not IsGifData(@Data[0], Length(Data)) then
        Exit(nil);

      Anim := DecodeGif(@Data[0], Length(Data), Complete, FirstOnly, MaxBytes, ACancel,
        More, Incomplete, Error);
      { The first frame didn't fit in the start of the file: read all. }
      if FirstOnly and Incomplete and not Complete then
      begin
        FreeAndNil(Anim);
        if not ReadFileStart(AKey.FileName, MaxGifFileBytes, ACancel, APriorityRead,
          Data, Complete) then
          Exit(TDecodedImage.CreateError(AKey, 'Cancelled'));
        Anim := DecodeGif(@Data[0], Length(Data), Complete, FirstOnly, MaxBytes, ACancel,
          More, Incomplete, Error);
      end;
      Data := nil;
      if Anim = nil then
        Exit(TDecodedImage.CreateError(AKey, 'GIF: ' + Error, NowMs - StartMs));

      Cursor := Anim.CreateCursor;
      try
        Bitmap := Cursor.Frame(0);
      finally
        Cursor.Free;
      end;
      DecodeMs := NowMs - StartMs;

      if IsCancelled(ACancel) then
      begin
        FreeAndNil(Anim);
        FreeAndNil(Bitmap);
        Exit(TDecodedImage.CreateError(AKey, 'Cancelled'));
      end;

      PreviewStartMs := NowMs;
      Preview := MakePreview(Bitmap, APreviewWidth, APreviewHeight);

      if FirstOnly and More then
        Quality := qlScreen
      else
        Quality := qlFull;
      { A single frame is a still image. }
      if FirstOnly or (Anim.FrameCount < 2) then
        FreeAndNil(Anim);

      Result := TDecodedImage.Create(AKey, Quality, Bitmap, Preview,
        DecodeMs, NowMs - PreviewStartMs, 0, 0, Anim);
      Anim := nil;
      Bitmap := nil;
      Preview := nil;
    except
      on E: EGifCancelled do
        Result := TDecodedImage.CreateError(AKey, 'Cancelled');
      on E: Exception do
        Result := TDecodedImage.CreateError(AKey, E.Message, NowMs - StartMs);
    end;
  finally
    Anim.Free;
    Preview.Free;
    Bitmap.Free;
  end;
end;

{ The size a PNG, BMP or GIF claims in its header (the formats that may
  end up in BGRABitmap's readers, which allocate first and ask nobody).
  False if unknown. }
function HeaderImageSize(const AFileName: string; out AWidth, AHeight: Int64): Boolean;
var
  Stream: TFileStream;
  B: array[0..31] of Byte;
  N: Integer;

  function BE32(I: Integer): Int64;
  begin
    Result := (Int64(B[I]) shl 24) or (Int64(B[I + 1]) shl 16)
      or (Int64(B[I + 2]) shl 8) or Int64(B[I + 3]);
  end;

  function LE32(I: Integer): Int64;
  begin
    Result := Int64(LongInt(LongWord(B[I]) or (LongWord(B[I + 1]) shl 8)
      or (LongWord(B[I + 2]) shl 16) or (LongWord(B[I + 3]) shl 24)));
  end;

  function LE16(I: Integer): Int64;
  begin
    Result := Int64(B[I]) or (Int64(B[I + 1]) shl 8);
  end;

begin
  Result := False;
  AWidth := 0;
  AHeight := 0;
  N := 0;
  FillChar(B, SizeOf(B), 0);
  try
    Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      N := Stream.Read(B[0], SizeOf(B));
    finally
      Stream.Free;
    end;
  except
    Exit;
  end;
  { PNG: the IHDR chunk comes first. }
  if (N >= 24) and (B[0] = $89) and (B[1] = Ord('P')) and (B[2] = Ord('N'))
    and (B[3] = Ord('G')) then
  begin
    AWidth := BE32(16);
    AHeight := BE32(20);
    Exit(True);
  end;
  { BMP: an OS/2 header (12 bytes) has 16-bit sizes; a negative height
    means top-down rows. }
  if (N >= 26) and (B[0] = Ord('B')) and (B[1] = Ord('M')) then
  begin
    if LE32(14) = 12 then
    begin
      AWidth := LE16(18);
      AHeight := LE16(20);
    end
    else
    begin
      AWidth := Abs(LE32(18));
      AHeight := Abs(LE32(22));
    end;
    Exit(True);
  end;
  { GIF: the logical screen. }
  if (N >= 10) and (B[0] = Ord('G')) and (B[1] = Ord('I')) and (B[2] = Ord('F')) then
  begin
    AWidth := LE16(6);
    AHeight := LE16(8);
    Exit(True);
  end;
end;

{ Every other format: BGRABitmap reads and decodes, always in full. }
function LoadOther(const AKey: TImageKey; ACancel: TCancelCheck;
  APreviewWidth, APreviewHeight: Integer; APriorityRead: Boolean): IDecodedImage;
var
  Bitmap: TBGRABitmap;
  Preview: TBGRACustomBitmap;
  Adapter: TProgressAdapter;
  StartMs, DecodeMs, PreviewStartMs: Double;
  HeaderW, HeaderH: Int64;
  Reason: string;
  Data: TMemoryStream;
  Reader: TFPCustomImageReader;
  KeepAlive: TDecodeKeepAlive;
  ReadOk: Boolean;
begin
  { The memory guard, before BGRABitmap allocates whatever the header
    claims (a corrupt or a NASA-sized PNG). }
  if HeaderImageSize(AKey.FileName, HeaderW, HeaderH)
    and not DecodeFits(HeaderW, HeaderH, 0, Reason) then
    Exit(TDecodedImage.CreateError(AKey, Reason));

  Bitmap := nil;
  Preview := nil;
  Adapter := TProgressAdapter.Create;
  try
    Adapter.Cancel := ACancel;
    StartMs := NowMs;
    try
      Bitmap := TBGRABitmap.Create;
      Bitmap.OnProgress := @Adapter.HandleProgress;
      { 1.4: first read (the gate raised only for the read), then decode
        from memory with the alive tick kept fresh (TDecodeKeepAlive).
        The same reader BGRABitmap's LoadFromFileUTF8 picks. }
      Data := TMemoryStream.Create;
      try
        if APriorityRead then
          IOGate.BeginPriorityRead
        else
          IOGate.YieldToDisplay(ACancel);
        try
          ReadOk := ReadWholeFile(AKey.FileName, Data, ACancel);
        finally
          if APriorityRead then
            IOGate.EndPriorityRead;
        end;
        if not ReadOk then
        begin
          FreeAndNil(Bitmap);
          Exit(TDecodedImage.CreateError(AKey, 'Cancelled'));
        end;
        Reader := CreateBGRAImageReader(DetectFileFormat(Data, ExtractFileExt(AKey.FileName)));
        try
          Data.Position := 0;
          KeepAlive := TDecodeKeepAlive.Create(ACancel);
          try
            Bitmap.LoadFromStream(Data, Reader, []);
          finally
            KeepAlive.Finish;
          end;
        finally
          Reader.Free;
        end;
      finally
        Data.Free;
      end;
      Bitmap.OnProgress := nil;
      DecodeMs := NowMs - StartMs;

      if IsCancelled(ACancel) then
      begin
        FreeAndNil(Bitmap);
        Exit(TDecodedImage.CreateError(AKey, 'Cancelled'));
      end;

      if (Bitmap.Width = 0) or (Bitmap.Height = 0) then
      begin
        FreeAndNil(Bitmap);
        Exit(TDecodedImage.CreateError(AKey, 'The file contains no image', DecodeMs));
      end;

      PreviewStartMs := NowMs;
      Preview := MakePreview(Bitmap, APreviewWidth, APreviewHeight);

      Result := TDecodedImage.Create(AKey, qlFull, Bitmap, Preview,
        DecodeMs, NowMs - PreviewStartMs);
    except
      on E: Exception do
      begin
        Preview.Free;
        Bitmap.Free;
        Result := TDecodedImage.CreateError(AKey, E.Message, NowMs - StartMs);
      end;
    end;
  finally
    Adapter.Free;
  end;
end;

{ ---- Large PNG without WIC (1.4, Linux port) ----

  On Windows WIC reads a large PNG scaled down for the quick view
  (LoadWicBands). Without WIC, BGRABitmap's reader decoded every pixel
  first (a 21600 x 21600 PNG: 466 MP, about 2 GB and tens of seconds)
  just to show a screen-sized picture. Here its reader keeps only every
  2^k-th row while it decodes (MinifyHeight: still inflated in full,
  but not converted or stored), the columns are then averaged by the
  same factor, and the rest is the usual ShrinkToSize. Faster still,
  and tried first: uPngQuick (the system's zlib, blocks averaged while
  the rows come); BGRABitmap's reader is the fallback. The result is
  the Screen quality with the full size noted, as from WIC; the Full
  decode follows as before (LoadOther), after a pause or on zooming. }

function IsPngFileName(const AFileName: string): Boolean;
begin
  Result := LowerCase(ExtractFileExt(AFileName)) = '.png';
end;

{ A new bitmap AFactor times narrower: each row's AFactor neighbouring
  pixels averaged (the last Width mod AFactor columns left out). }
function ShrinkColumns(ASource: TBGRABitmap; AFactor: Integer): TBGRABitmap;
var
  W, X, Y, K: Integer;
  Src, Dst: PBGRAPixel;
  SR, SG, SB, SA, F: Cardinal;
begin
  W := Max(1, ASource.Width div AFactor);
  F := Cardinal(AFactor);
  Result := TBGRABitmap.Create(W, ASource.Height);
  try
    for Y := 0 to ASource.Height - 1 do
    begin
      Src := ASource.ScanLine[Y];
      Dst := Result.ScanLine[Y];
      for X := 0 to W - 1 do
      begin
        SR := 0;
        SG := 0;
        SB := 0;
        SA := 0;
        for K := 1 to AFactor do
        begin
          Inc(SR, Src^.red);
          Inc(SG, Src^.green);
          Inc(SB, Src^.blue);
          Inc(SA, Src^.alpha);
          Inc(Src);
        end;
        Dst^.red := Byte(SR div F);
        Dst^.green := Byte(SG div F);
        Dst^.blue := Byte(SB div F);
        Dst^.alpha := Byte(SA div F);
        Inc(Dst);
      end;
    end;
    Result.InvalidateBitmap;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

{ The Screen quality of a PNG at least 4 times taller than its fitted
  size; nil if it isn't (or the reader fails: LoadOther then tries and
  reports). }
function LoadPngScreen(const AKey: TImageKey; ACancel: TCancelCheck;
  APreviewWidth, APreviewHeight: Integer; APriorityRead: Boolean): IDecodedImage;
var
  HeaderW, HeaderH: Int64;
  FitW, FitH, Factor: Integer;
  Data: TMemoryStream;
  Png: TBGRAReaderPNG;
  Bitmap, Narrow, Shrunk: TBGRABitmap;
  KeepAlive: TDecodeKeepAlive;
  StartMs, DecodeMs, ShrinkStartMs: Double;
  Reason: string;
  ReadOk, Cancelled: Boolean;
  QuickW, QuickH: Integer;
begin
  Result := nil;
  if (APreviewWidth <= 0) or (APreviewHeight <= 0) then
    Exit;
  if not HeaderImageSize(AKey.FileName, HeaderW, HeaderH) then
    Exit;
  if (HeaderW <= 0) or (HeaderH <= 0) or (HeaderW > High(Integer)) or (HeaderH > High(Integer)) then
    Exit;
  FitSize(Integer(HeaderW), Integer(HeaderH), APreviewWidth, APreviewHeight, FitW, FitH);
  { Less than 4 x: the full decode is quick enough (LoadOther). }
  if HeaderH < 4 * Int64(FitH) then
    Exit;
  { At most this much is kept: full width, below 4 x the fitted height. }
  if not DecodeFits(HeaderW, 4 * Int64(FitH), 0, Reason) then
    Exit;

  StartMs := NowMs;
  Bitmap := nil;
  Narrow := nil;
  Data := TMemoryStream.Create;
  Png := TBGRAReaderPNG.Create;
  try
    try
      if APriorityRead then
        IOGate.BeginPriorityRead
      else
        IOGate.YieldToDisplay(ACancel);
      try
        ReadOk := ReadWholeFile(AKey.FileName, Data, ACancel);
      finally
        if APriorityRead then
          IOGate.EndPriorityRead;
      end;
      if not ReadOk then
        Exit(TDecodedImage.CreateError(AKey, 'Cancelled'));

      { First the own reader: the system's zlib, F x F blocks averaged
        while the rows come (uPngQuick). }
      Bitmap := DecodePngReduced(Data, FitW, FitH, ACancel, QuickW, QuickH, Cancelled);
      if Cancelled then
        Exit(TDecodedImage.CreateError(AKey, 'Cancelled'));
      if Bitmap <> nil then
      begin
        DecodeMs := NowMs - StartMs;
        ShrinkStartMs := NowMs;
      end
      else
      begin
        { Else BGRABitmap's reader. Rows kept: every 2^k-th, k as large
          as leaves at least twice the fitted height (so ShrinkToSize
          still averages). }
        Data.Position := 0;
        Png.MinifyHeight := 2 * FitH;
        Bitmap := TBGRABitmap.Create;
        KeepAlive := TDecodeKeepAlive.Create(ACancel);
        try
          Bitmap.LoadFromStream(Data, Png, []);
        finally
          KeepAlive.Finish;
        end;
        DecodeMs := NowMs - StartMs;
        if IsCancelled(ACancel) then
          Exit(TDecodedImage.CreateError(AKey, 'Cancelled'));
        if (Bitmap.Width = 0) or (Bitmap.Height = 0) then
          Exit(nil);

        ShrinkStartMs := NowMs;
        { The columns by the factor the rows were thinned by: the
          proportions are right again. }
        Factor := Png.VerticalShrinkFactor;
        if (Factor > 1) and (Factor <= Bitmap.Width) then
        begin
          Narrow := ShrinkColumns(Bitmap, Factor);
          FreeAndNil(Bitmap);
          Bitmap := Narrow;
          Narrow := nil;
        end;
      end;
      Shrunk := ShrinkToSize(Bitmap, FitW, FitH);
      FreeAndNil(Bitmap);
      Result := TDecodedImage.Create(AKey, qlScreen, Shrunk, nil,
        DecodeMs, NowMs - ShrinkStartMs, Integer(HeaderW), Integer(HeaderH));
    except
      on E: EOutOfMemory do
        Result := TDecodedImage.CreateError(AKey, E.Message, NowMs - StartMs);
      on E: Exception do
        Result := nil;     { LoadOther tries, and reports what is wrong }
    end;
  finally
    Bitmap.Free;
    Narrow.Free;
    Png.Free;
    Data.Free;
  end;
end;

{ An image inside a container (M2b): the edition's reader decodes it
  (a stack: its maximum projection) to RGBA; here it becomes a bitmap
  and its screen copy, like any other full image. }
function LoadContainerEntry(const AKey: TImageKey; ACancel: TCancelCheck;
  APreviewWidth, APreviewHeight: Integer; APriorityRead: Boolean): IDecodedImage;
var
  Bitmap: TBGRABitmap;
  Preview: TBGRACustomBitmap;
  RGBA: TBytes;
  W, H, X, Y: Integer;
  Error: string;
  Ok: Boolean;
  StartMs, DecodeMs, PreviewStartMs: Double;
  Row: PBGRAPixel;
  P: PtrInt;
  Reason: string;
begin
  StartMs := NowMs;
  if APriorityRead then
    IOGate.BeginPriorityRead
  else
    IOGate.YieldToDisplay(ACancel);
  try
    Ok := DecodeContainerEntry(AKey.FileName, ACancel, W, H, RGBA, Error);
  finally
    if APriorityRead then
      IOGate.EndPriorityRead;
  end;
  if IsCancelled(ACancel) then
    Exit(TDecodedImage.CreateError(AKey, 'Cancelled'));
  if not Ok then
    Exit(TDecodedImage.CreateError(AKey, Error, NowMs - StartMs));
  if (W <= 0) or (H <= 0) or (Int64(Length(RGBA)) < Int64(W) * H * 4) then
    Exit(TDecodedImage.CreateError(AKey, 'The entry contains no image', NowMs - StartMs));
  { The memory guard, before the bitmap (the reader's own buffers are
    gone again by now). }
  if not DecodeFits(W, H, 0, Reason) then
    Exit(TDecodedImage.CreateError(AKey, Reason, NowMs - StartMs));

  Bitmap := nil;
  Preview := nil;
  try
    Bitmap := TBGRABitmap.Create(W, H);
    P := 0;
    for Y := 0 to H - 1 do
    begin
      Row := Bitmap.ScanLine[Y];
      for X := 0 to W - 1 do
      begin
        Row^.red := RGBA[P];
        Row^.green := RGBA[P + 1];
        Row^.blue := RGBA[P + 2];
        Row^.alpha := RGBA[P + 3];
        Inc(Row);
        Inc(P, 4);
      end;
    end;
    Bitmap.InvalidateBitmap;
    RGBA := nil;
    DecodeMs := NowMs - StartMs;
    PreviewStartMs := NowMs;
    Preview := MakePreview(Bitmap, APreviewWidth, APreviewHeight);
    Result := TDecodedImage.Create(AKey, qlFull, Bitmap, Preview,
      DecodeMs, NowMs - PreviewStartMs);
  except
    on E: Exception do
    begin
      Preview.Free;
      Bitmap.Free;
      Result := TDecodedImage.CreateError(AKey, E.Message, NowMs - StartMs);
    end;
  end;
end;

constructor TMediaLoader.Create;
begin
  inherited Create;
  FAutoRotate := True;
  FUseWic := True;
  FUseWicQuickView := True;
end;

procedure TMediaLoader.ThreadStart;
begin
  WicThreadStart;
end;

procedure TMediaLoader.ThreadEnd;
begin
  WicThreadEnd;
end;

function DecodeIconBitmap(const ABytes: TBytes; ASize: Integer): TBGRABitmap;
var
  Entries: TIconEntries;
  Idx, X, Y: Integer;
  Stream: TMemoryStream;
  Pixels: TIconPixels;
  P: PBGRAPixel;
  C: LongWord;
begin
  Result := nil;
  Stream := nil;
  try
    try
      if not ReadIconDirectory(ABytes, Entries) then
        Exit;
      if ASize <= 0 then
        ASize := MaxInt;
      Idx := ChooseIconEntry(Entries, ASize);
      if Idx < 0 then
        Exit;
      if Entries[Idx].IsPng then
      begin
        Stream := TMemoryStream.Create;
        Stream.WriteBuffer(ABytes[Entries[Idx].Offset], Entries[Idx].Size);
        Stream.Position := 0;
        Result := TBGRABitmap.Create;
        Result.LoadFromStream(Stream);
      end
      else if DecodeIconDib(ABytes, Entries[Idx], Pixels) then
      begin
        Result := TBGRABitmap.Create(Pixels.Width, Pixels.Height);
        for Y := 0 to Pixels.Height - 1 do
        begin
          P := Result.ScanLine[Y];
          for X := 0 to Pixels.Width - 1 do
          begin
            C := Pixels.Data[Y * Pixels.Width + X];
            P^ := BGRA((C shr 16) and $FF, (C shr 8) and $FF, C and $FF, C shr 24);
            Inc(P);
          end;
        end;
        Result.InvalidateBitmap;
      end;
    except
      FreeAndNil(Result);
    end;
  finally
    Stream.Free;
  end;
  if (Result <> nil) and ((Result.Width <= 0) or (Result.Height <= 0)) then
    FreeAndNil(Result);
end;

{ An .ico: read by MView itself (the largest picture), as Windows' codec
  refuses PNG entries without alpha (icons made by MView before 1.1.1,
  and others). nil: not an icon after all (then WIC is asked). }
function LoadIcon(const AKey: TImageKey; ACancel: TCancelCheck;
  APreviewWidth, APreviewHeight: Integer; APriorityRead: Boolean): IDecodedImage;
const
  MaxIconFileBytes = 64 * 1024 * 1024;
var
  Data: TBytes;
  Complete: Boolean;
  Bitmap: TBGRABitmap;
  Preview: TBGRACustomBitmap;
  StartMs, DecodeMs, PreviewStartMs: Double;
begin
  Result := nil;
  StartMs := NowMs;
  if not ReadFileStart(AKey.FileName, MaxIconFileBytes, ACancel, APriorityRead, Data, Complete)
    or not Complete then
    Exit;
  if IsCancelled(ACancel) then
    Exit(TDecodedImage.CreateError(AKey, 'Cancelled'));
  Bitmap := DecodeIconBitmap(Data, 0);
  if Bitmap = nil then
    Exit;
  DecodeMs := NowMs - StartMs;
  Preview := nil;
  try
    PreviewStartMs := NowMs;
    Preview := MakePreview(Bitmap, APreviewWidth, APreviewHeight);
    Result := TDecodedImage.Create(AKey, qlFull, Bitmap, Preview,
      DecodeMs, NowMs - PreviewStartMs);
  except
    on E: Exception do
    begin
      Preview.Free;
      Bitmap.Free;
      Result := TDecodedImage.CreateError(AKey, E.Message, NowMs - StartMs);
    end;
  end;
end;

function TMediaLoader.Load(const AFileName: string; AQuality: TQualityLevel;
  ACancel: TCancelCheck; APreviewWidth: Integer; APreviewHeight: Integer;
  APriorityRead: Boolean): IDecodedImage;
var
  Key: TImageKey;
begin
  { 1.4 (Day 40): a preload from a drive that had read errors or didn't
    answer a little while ago: not even its size is asked for (each look
    adds to a failing drive's retries). Not an error of the file: the
    viewer asks again later. The image the user goes to is read. }
  if (not APriorityRead) and DriveInTrouble(AFileName) then
  begin
    Key.FileName := AFileName;
    Key.FileSize := 0;
    Key.FileTime := 0;
    Exit(TDecodedImage.CreateError(Key, DriveSkippedMessage));
  end;

  Key := MakeImageKey(AFileName);

  if IsCancelled(ACancel) then
    Exit(TDecodedImage.CreateError(Key, 'Cancelled'));

  { An image inside a container (.lif, M2b; never in MView): the
    edition's reader. No preview level: the full picture. }
  if IsVirtualName(AFileName) then
  begin
    if not FileExists(ContainerFileOf(AFileName)) then
      Exit(TDecodedImage.CreateError(Key, 'File not found'));
    if AQuality = qlPreview then
      Exit(TDecodedImage.CreateError(Key, NoPreviewMessage));
    Exit(LoadContainerEntry(Key, ACancel, APreviewWidth, APreviewHeight, APriorityRead));
  end;

  if not FileExists(AFileName) then
    Exit(TDecodedImage.CreateError(Key, 'File not found'));

  if not IsSupportedImageFile(AFileName) then
    Exit(TDecodedImage.CreateError(Key, 'Unsupported file format'));

  { An empty file (a copy or download that was cut off, a placeholder
    left by a sync tool): say so at once instead of letting the
    readers guess. For every quality, so it isn't asked for again. }
  if Key.FileSize = 0 then
    Exit(TDecodedImage.CreateError(Key, 'Empty file (0 bytes)'));

  if AQuality = qlPreview then
  begin
    if MayHavePreview(AFileName) then
      Result := LoadJpegPreview(Key, ACancel, APriorityRead, FAutoRotate)
    else
      Result := TDecodedImage.CreateError(Key, NoPreviewMessage);
  end
  { A 3D model (1.3): drawn as the model starts (StlStartView). }
  else if IsStlFileName(AFileName) then
    Result := RenderStlImage(Key, StlStartView, APreviewWidth, APreviewHeight, True, ACancel)
  else if IsJpegFileName(AFileName) then
    Result := LoadJpeg(Key, AQuality, ACancel, APreviewWidth, APreviewHeight,
      APriorityRead, FAutoRotate, FUseWic, FUseWicQuickView)
  else if IsGifFileName(AFileName) then
  begin
    Result := LoadGif(Key, AQuality, ACancel, APreviewWidth, APreviewHeight, APriorityRead);
    if Result = nil then
      Result := LoadOther(Key, ACancel, APreviewWidth, APreviewHeight, APriorityRead);
  end
  { The formats only Windows' codecs read (1.1): WIC, or a clear note
    which codec is missing. }
  else if IsWicOnlyFile(AFileName) then
  begin
    Result := nil;
    if LowerCase(ExtractFileExt(AFileName)) = '.ico' then
      Result := LoadIcon(Key, ACancel, APreviewWidth, APreviewHeight, APriorityRead);
    if (Result = nil) and WicAvailable then
      Result := LoadWicBands(Key, AQuality, ACancel, APreviewWidth, APreviewHeight,
        APriorityRead);
    if Result = nil then
    begin
      if CodecHint(AFileName) <> '' then
        Result := TDecodedImage.CreateError(Key, CodecHint(AFileName))
      else
        Result := TDecodedImage.CreateError(Key, 'Windows can''t read this file');
    end;
  end
  else if IsWicBandFileName(AFileName) and FUseWic and WicAvailable then
  begin
    Result := LoadWicBands(Key, AQuality, ACancel, APreviewWidth, APreviewHeight,
      APriorityRead);
    if Result = nil then
      Result := LoadOther(Key, ACancel, APreviewWidth, APreviewHeight, APriorityRead);
  end
  else
  begin
    Result := nil;
    { 1.4: without WIC, a large PNG's quick view decoded smaller. }
    if (AQuality < qlFull) and IsPngFileName(AFileName) then
      Result := LoadPngScreen(Key, ACancel, APreviewWidth, APreviewHeight, APriorityRead);
    if Result = nil then
      Result := LoadOther(Key, ACancel, APreviewWidth, APreviewHeight, APriorityRead);
  end;
end;

end.
