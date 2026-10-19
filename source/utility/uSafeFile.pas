unit uSafeFile;

{
  Unit: uSafeFile

  Purpose
  -------
  Writes a settings file so that it is never left half written (1.1,
  tester report: MView hung while saving MView.ini after a folder
  button was removed; the process was ended, the ini was found cut
  short and the next start replaced it with defaults).

  The text goes into "<name>.tmp" next to the file, is flushed to the
  disk, and then replaces the file in one step of the file system
  (Windows: MoveFileExW with REPLACE_EXISTING and WRITE_THROUGH; else
  rename, which replaces atomically). Whatever happens on the way, the
  old complete file or the new complete file is there, never a part.

  Owns
  ----
  Nothing (plain functions).

  Responsibilities
  ----------------
  - ReadTextFile: a file's text (shared reading; a UTF-8 BOM dropped).
  - WriteTextFileSafely: as above; False (with the reason) if the folder
    is read-only or the file can't be replaced; the .tmp is removed.
  - The ini's end line (IniEndLine): every save of a settings file ends
    with it, so a file cut short is told from a complete one (uConfig);
    IniTextWithEndLine / IniTextWithoutEndLine / HasEndLine.

  Threads
  -------
  Any thread; no state.

  Uses (MView units)
  ------------------
  (none)
  Libraries:      Classes, SysUtils, Windows (on Windows), Unix (else)

  Used by
  -------
  uConfig, uIniEditor, uMousePage, uMView, the Lab's uImageScale and
  uCalibrations
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils;

function ReadTextFile(const AFileName: string; out AText: string): Boolean;
function WriteTextFileSafely(const AFileName, AText: string; out AError: string): Boolean;
{ As above; raises EInOutError on failure (for callers that report
  exceptions). }
procedure WriteTextFileSafe(const AFileName, AText: string);

const
  { The ini's last line, written by every save: a file without it (when
    its backup has it) was cut short. }
  IniEndLine = '; end of the settings (checked at the start: keep this line last)';
  { The same line as 1.1 wrote it before the rename (still recognised). }
  OldIniEndLine = '; end of the settings (MView checks this line: keep it last)';

{ AText without end lines, with one at its end (the settings editor's
  save, uConfig's own). }
function IniTextWithEndLine(const AText: string): string;
{ AText without end lines. }
function IniTextWithoutEndLine(const AText: string): string;
{ AText's last line that isn't empty is an end line. }
function HasEndLine(const AText: string): Boolean;

{ A file's modification time, to put back after it was rewritten
  (lossless rotation, 1.1: sorting by date keeps its place). Windows:
  the exact FILETIME; elsewhere FileAge's. }
function GetFileWriteTime(const AFileName: string; out ATime: Int64): Boolean;
function SetFileWriteTime(const AFileName: string; ATime: Int64): Boolean;

implementation

{$IFDEF WINDOWS}
uses
  Windows;

const
  MoveFileWriteThrough = $8;    { MOVEFILE_WRITE_THROUGH (not in every Windows unit) }
{$ELSE}
uses
  Unix;
{$ENDIF}

function ReadTextFile(const AFileName: string; out AText: string): Boolean;
var
  Stream: TFileStream;
  N: Int64;
begin
  AText := '';
  Result := False;
  try
    Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      N := Stream.Size;
      SetLength(AText, N);
      if N > 0 then
        Stream.ReadBuffer(AText[1], N);
    finally
      Stream.Free;
    end;
    if (Length(AText) >= 3) and (AText[1] = #$EF) and (AText[2] = #$BB) and (AText[3] = #$BF) then
      Delete(AText, 1, 3);
    Result := True;
  except
    AText := '';
    Result := False;
  end;
end;

function ReplaceFile(const ASource, ATarget: string): Boolean;
begin
  {$IFDEF WINDOWS}
  Result := MoveFileExW(PWideChar(UnicodeString(UTF8Decode(ASource))),
    PWideChar(UnicodeString(UTF8Decode(ATarget))),
    MOVEFILE_REPLACE_EXISTING or MoveFileWriteThrough);
  {$ELSE}
  Result := RenameFile(ASource, ATarget);   { rename(2): replaces in one step }
  {$ENDIF}
end;

function WriteTextFileSafely(const AFileName, AText: string; out AError: string): Boolean;
var
  Tmp: string;
  Stream: TFileStream;
begin
  Result := False;
  AError := '';
  Tmp := AFileName + '.tmp';
  try
    Stream := TFileStream.Create(Tmp, fmCreate);
    try
      if AText <> '' then
        Stream.WriteBuffer(AText[1], Length(AText));
      { On the disk before the old file is replaced. }
      {$IFDEF WINDOWS}
      FlushFileBuffers(Stream.Handle);
      {$ELSE}
      FpFsync(Stream.Handle);
      {$ENDIF}
    finally
      Stream.Free;
    end;
  except
    on E: Exception do
    begin
      AError := E.Message;
      SysUtils.DeleteFile(Tmp);
      Exit;
    end;
  end;
  if not ReplaceFile(Tmp, AFileName) then
  begin
    AError := 'could not replace ' + ExtractFileName(AFileName) + ' (' + SysErrorMessage(GetLastOSError) + ')';
    SysUtils.DeleteFile(Tmp);
    Exit;
  end;
  Result := True;
end;

function IniTextWithoutEndLine(const AText: string): string;
var
  Lines: TStringList;
  I: Integer;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := AText;
    for I := Lines.Count - 1 downto 0 do
      if (Trim(Lines[I]) = IniEndLine) or (Trim(Lines[I]) = OldIniEndLine) then
        Lines.Delete(I);
    while (Lines.Count > 0) and (Trim(Lines[Lines.Count - 1]) = '') do
      Lines.Delete(Lines.Count - 1);
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

function IniTextWithEndLine(const AText: string): string;
begin
  Result := IniTextWithoutEndLine(AText) + LineEnding + IniEndLine + LineEnding;
end;

function HasEndLine(const AText: string): Boolean;
var
  Lines: TStringList;
  I: Integer;
begin
  Result := False;
  Lines := TStringList.Create;
  try
    Lines.Text := AText;
    for I := Lines.Count - 1 downto 0 do
      if Trim(Lines[I]) <> '' then
        Exit((Trim(Lines[I]) = IniEndLine) or (Trim(Lines[I]) = OldIniEndLine));
  finally
    Lines.Free;
  end;
end;

function GetFileWriteTime(const AFileName: string; out ATime: Int64): Boolean;
{$IFDEF WINDOWS}
var
  H: THandle;
  T: TFileTime;
begin
  ATime := 0;
  H := CreateFileW(PWideChar(UnicodeString(UTF8Decode(AFileName))), FILE_READ_ATTRIBUTES,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING, 0, 0);
  Result := H <> INVALID_HANDLE_VALUE;
  if not Result then
    Exit;
  Result := GetFileTime(H, nil, nil, @T);
  CloseHandle(H);
  if Result then
    ATime := Int64(T.dwHighDateTime) shl 32 or T.dwLowDateTime;
end;
{$ELSE}
begin
  ATime := FileAge(AFileName);
  Result := ATime <> -1;
end;
{$ENDIF}

function SetFileWriteTime(const AFileName: string; ATime: Int64): Boolean;
{$IFDEF WINDOWS}
var
  H: THandle;
  T: TFileTime;
begin
  H := CreateFileW(PWideChar(UnicodeString(UTF8Decode(AFileName))), FILE_WRITE_ATTRIBUTES,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING, 0, 0);
  Result := H <> INVALID_HANDLE_VALUE;
  if not Result then
    Exit;
  T.dwLowDateTime := DWORD(ATime and $FFFFFFFF);
  T.dwHighDateTime := DWORD(ATime shr 32);
  Result := SetFileTime(H, nil, nil, @T);
  CloseHandle(H);
end;
{$ELSE}
begin
  Result := FileSetDate(AFileName, LongInt(ATime)) = 0;
end;
{$ENDIF}

procedure WriteTextFileSafe(const AFileName, AText: string);
var
  Error: string;
begin
  if not WriteTextFileSafely(AFileName, AText, Error) then
    raise EInOutError.Create(Error);
end;

end.
