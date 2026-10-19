unit uImageFormats;

{
  Unit: uImageFormats

  Purpose
  -------
  The one list of file formats MView can display (spec §16 #10).
  Directory listing and the loader both use it, so a file that shows
  up in navigation is always a file the loader will try to decode.

  Owns
  ----
  - Nothing: a constant list (SupportedImageExtensions) and one
    stateless routine.

  Knows
  -----
  - Nothing else.

  Responsibilities
  ----------------
  - Know which file extensions are supported: .tif .tiff .jpg .jpeg
    .jpe .png .bmp .gif; since 1.1 (Day 27, testers) also the formats
    Windows' own codecs read (WicOnlyExtensions): WebP, HEIC / HEIF,
    AVIF, JPEG XL, JPEG XR, DDS, icons (.ico: the largest picture in
    the file) and camera raw files. Some need a codec from the Microsoft
    Store (HEIF, AV1, JPEG XL, Raw Image Extension); without it the
    file is listed and says which one is missing (CodecHint).
  - IsSupportedImageFile: True if a file name ends in one of them
    (case does not matter).
  - IsVideoFile (Day 24): a video, by its extension only. MView never
    opens one; folders count them for the info line ("3 videos").

  Does NOT
  --------
  - Decode anything (uMediaLoader).
  - Check file contents. (Movies, later, are detected by content; see
    spec §8.7.)

  Threads
  -------
  Any thread: a constant and a pure function, no shared state. Used
  while directories are listed (uDirectoryTree, uDirectoryImages) and
  on the decode workers (uMediaLoader).

  Uses (MView units)
  ------------------
  None: depends only on the libraries below.
  Libraries:      SysUtils

  Used by
  -------
  uDirectoryImages, uDirectoryTree, uMediaLoader

  Notes
  -----
  Only formats that v1 decodes are listed (spec §3.1). Add a format
  here only together with the decoder for it.
}

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils;

const
  SupportedImageExtensions: array[0..7] of string = (
    '.tif', '.tiff',
    '.jpg', '.jpeg', '.jpe',
    '.png',
    '.bmp',
    '.gif'
  );

  { Read only through WIC, Windows' codecs (1.1). }
  WicOnlyExtensions: array[0..26] of string = (
    '.webp', '.heic', '.heif', '.hif', '.avif', '.jxl', '.jxr', '.wdp', '.hdp', '.dds',
    '.ico',
    '.dng', '.cr2', '.cr3', '.crw', '.nef', '.nrw', '.arw', '.sr2', '.srf',
    '.orf', '.rw2', '.raf', '.pef', '.srw', '.erf', '.3fr'
  );

  { Videos (never opened, only counted; user, Day 24). }
  VideoExtensions: array[0..14] of string = (
    '.mp4', '.m4v', '.mov', '.avi', '.mkv', '.webm', '.wmv', '.mpg',
    '.mpeg', '.flv', '.3gp', '.mts', '.m2ts', '.vob', '.ser'
  );

function IsSupportedImageFile(const AFileName: string): Boolean;
function IsVideoFile(const AFileName: string): Boolean;
{ One of WicOnlyExtensions. }
function IsWicOnlyFile(const AFileName: string): Boolean;
{ What to install when Windows can't read such a file ('' = nothing
  known). }
function CodecHint(const AFileName: string): string;

implementation

function IsSupportedImageFile(const AFileName: string): Boolean;
var
  Ext: string;
  I: Integer;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  for I := Low(SupportedImageExtensions) to High(SupportedImageExtensions) do
    if Ext = SupportedImageExtensions[I] then
      Exit(True);
  Result := IsWicOnlyFile(AFileName);
end;

function IsWicOnlyFile(const AFileName: string): Boolean;
var
  Ext: string;
  I: Integer;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  for I := Low(WicOnlyExtensions) to High(WicOnlyExtensions) do
    if Ext = WicOnlyExtensions[I] then
      Exit(True);
  Result := False;
end;

function CodecHint(const AFileName: string): string;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  if (Ext = '.heic') or (Ext = '.heif') or (Ext = '.hif') then
    Result := 'Windows can''t read this file (HEIC / HEIF needs "HEIF Image Extensions" from the Microsoft Store)'
  else if Ext = '.avif' then
    Result := 'Windows can''t read this file (AVIF needs "AV1 Video Extension" from the Microsoft Store)'
  else if Ext = '.jxl' then
    Result := 'Windows can''t read this file (JPEG XL needs "JPEG XL Image Extension" from the Microsoft Store, Windows 11)'
  else if Ext = '.webp' then
    Result := 'Windows can''t read this file (WebP needs "WebP Image Extensions" from the Microsoft Store)'
  else if (Ext = '.jxr') or (Ext = '.wdp') or (Ext = '.hdp') or (Ext = '.dds')
    or (Ext = '.ico') then
    Result := ''
  else
    Result := 'Windows can''t read this file (camera raw files need "Raw Image Extension" from the Microsoft Store)';
end;

function IsVideoFile(const AFileName: string): Boolean;
var
  Ext: string;
  I: Integer;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  for I := Low(VideoExtensions) to High(VideoExtensions) do
    if Ext = VideoExtensions[I] then
      Exit(True);
  Result := False;
end;

end.
