unit uClipboardImage;

{
  Unit: uClipboardImage

  Purpose
  -------
  Copy image (Day 25): puts a picture on the Windows clipboard the way
  every program understands - a device-independent bitmap (CF_DIB, 24
  bit, bottom-up rows), from which Windows also makes CF_BITMAP for the
  programs that want that. The LCL's own Clipboard.Assign hands the
  picture out on request in its own wrapping, which some programs did
  not take (user, Day 25).

  Owns
  ----
  Nothing (the clipboard owns the memory once it is set).

  Responsibilities
  ----------------
  - CopyBitmapToClipboard: transparent pixels are laid on white (no
    alpha in a 24-bit bitmap). False and a reason if the memory or the
    clipboard can't be had.

  Threads
  -------
  UI thread (the clipboard belongs to a window).

  Uses (MView units)
  ------------------
  (none)
  Libraries:      SysUtils, BGRABitmap, BGRABitmapTypes; Windows

  Used by
  -------
  uMView
}

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils,
  BGRABitmap;

{ AWindow: a window of this program (the clipboard's owner). }
function CopyBitmapToClipboard(ABitmap: TBGRABitmap; AWindow: THandle;
  out AReason: string): Boolean;

implementation

{$IFDEF WINDOWS}
uses
  Windows,
  BGRABitmapTypes;

type
  TDibHeader = packed record
    biSize: LongWord;
    biWidth: LongInt;
    biHeight: LongInt;
    biPlanes: Word;
    biBitCount: Word;
    biCompression: LongWord;
    biSizeImage: LongWord;
    biXPelsPerMeter: LongInt;
    biYPelsPerMeter: LongInt;
    biClrUsed: LongWord;
    biClrImportant: LongWord;
  end;

const
  ClipboardDib = 8;          { CF_DIB }

function CopyBitmapToClipboard(ABitmap: TBGRABitmap; AWindow: THandle;
  out AReason: string): Boolean;
var
  W, H, X, Y, Stride: Integer;
  Bytes: Int64;
  Mem: HGLOBAL;
  Base: PByte;
  Header: TDibHeader;
  Row: PByte;
  Src: PBGRAPixel;
  A: Integer;
  Opened: Boolean;
begin
  Result := False;
  AReason := '';
  if (ABitmap = nil) or (ABitmap.Width <= 0) or (ABitmap.Height <= 0) then
  begin
    AReason := 'no picture';
    Exit;
  end;
  W := ABitmap.Width;
  H := ABitmap.Height;
  Stride := (W * 3 + 3) and not 3;
  Bytes := Int64(Stride) * H;
  if Bytes + SizeOf(Header) > High(LongInt) then
  begin
    AReason := 'too large for the clipboard';
    Exit;
  end;
  Mem := GlobalAlloc(GMEM_MOVEABLE, SizeOf(Header) + Bytes);
  if Mem = 0 then
  begin
    AReason := 'not enough memory';
    Exit;
  end;
  try
    Base := GlobalLock(Mem);
    if Base = nil then
    begin
      AReason := 'not enough memory';
      GlobalFree(Mem);
      Exit;
    end;
    try
      FillChar(Header, SizeOf(Header), 0);
      Header.biSize := SizeOf(Header);
      Header.biWidth := W;
      Header.biHeight := H;           { positive: the last row first }
      Header.biPlanes := 1;
      Header.biBitCount := 24;
      Header.biCompression := 0;      { BI_RGB }
      Header.biSizeImage := Bytes;
      Header.biXPelsPerMeter := 3780; { 96 dpi }
      Header.biYPelsPerMeter := 3780;
      Move(Header, Base^, SizeOf(Header));
      for Y := 0 to H - 1 do
      begin
        Row := Base + SizeOf(Header) + Int64(H - 1 - Y) * Stride;
        Src := ABitmap.ScanLine[Y];
        for X := 0 to W - 1 do
        begin
          A := Src^.alpha;
          if A = 255 then
          begin
            Row[0] := Src^.blue;
            Row[1] := Src^.green;
            Row[2] := Src^.red;
          end
          else
          begin
            { On white. }
            Row[0] := (Src^.blue * A + 255 * (255 - A)) div 255;
            Row[1] := (Src^.green * A + 255 * (255 - A)) div 255;
            Row[2] := (Src^.red * A + 255 * (255 - A)) div 255;
          end;
          Inc(Row, 3);
          Inc(Src);
        end;
      end;
    finally
      GlobalUnlock(Mem);
    end;
  except
    on E: Exception do
    begin
      AReason := E.Message;
      GlobalFree(Mem);
      Exit;
    end;
  end;

  Opened := OpenClipboard(AWindow);
  if not Opened then
  begin
    AReason := 'the clipboard is busy (another program has it open)';
    GlobalFree(Mem);
    Exit;
  end;
  try
    EmptyClipboard;
    if SetClipboardData(ClipboardDib, Mem) = 0 then
    begin
      AReason := 'the clipboard did not take the picture';
      GlobalFree(Mem);
      Exit;
    end;
    Result := True;     { the clipboard owns Mem now }
  finally
    CloseClipboard;
  end;
end;

{$ELSE}

function CopyBitmapToClipboard(ABitmap: TBGRABitmap; AWindow: THandle;
  out AReason: string): Boolean;
begin
  Result := False;
  AReason := 'only on Windows';
end;

{$ENDIF}

end.
