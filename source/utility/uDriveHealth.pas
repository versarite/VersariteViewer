unit uDriveHealth;

{
  Unit: uDriveHealth

  Purpose
  -------
  1.4 (Day 40, a user's report: reading from a failing memory stick,
  Windows said a file was "corrupt and unreadable", then hung and had to
  be reset). A failing drive retries every bad sector for seconds; each
  further read VV starts there (preloads of the neighbours, a worker
  replaced after a stuck read that goes on with the next file) adds to
  the pile. So:
  - a drive that returns a media error (CRC, corrupt, device I/O,
    sector not found, timeout ...) or doesn't answer a read for a long
    time is "in trouble" for BackOffMs after the last such event;
  - meanwhile VV doesn't preload from it (the loader asks
    DriveInTrouble before touching the disk); the image the user goes
    to is still read;
  - the UI shows a notice once per drive and trouble (TakeDriveNotice);
  - Windows' own message boxes for drive errors ("insert a disk", "the
    drive is not ready") are switched off for VV at the start
    (SetErrorMode). The NTFS notice "file or directory is corrupt and
    unreadable" comes from Windows itself and can't be switched off by a
    program.

  Threads
  -------
  NoteDriveTrouble / DriveInTrouble: any thread (decode workers, the UI
  thread); TakeDriveNotice: the UI thread. One critical section.

  Uses (MView units)
  ------------------
  none
}

{$mode ObjFPC}{$H+}
{$modeswitch typehelpers}

interface

uses
  SysUtils;

const
  { How long a drive stays "in trouble" after the last error (ms). }
  BackOffMs = 120000;
  { The error text of a preload skipped for a drive in trouble: not an
    error of the file (not cached, asked for again later). }
  DriveSkippedMessage = 'Skipped: the drive has read errors';

{ A read on AFileName's drive failed with a media error or hung. AWhat:
  what happened, for the notice. }
procedure NoteDriveTrouble(const AFileName, AWhat: string);
{ AFileName's drive had trouble within BackOffMs. }
function DriveInTrouble(const AFileName: string): Boolean;
{ A drive newly in trouble, once: its name and what happened. UI thread. }
function TakeDriveNotice(out ADrive, AWhat: string): Boolean;
{ An OS error code that means the medium / device failed (not "file not
  found", "access denied", "in use"). }
function IsMediaErrorCode(ACode: Integer): Boolean;
{ "D:", "\\server\share", "/media/user/STICK" ... }
function DriveOf(const AFileName: string): string;

implementation

type
  TTrouble = record
    Drive: string;
    LastMs: QWord;
    What: string;
    Noticed: Boolean;
  end;

var
  Lock: TRTLCriticalSection;
  Troubles: array of TTrouble;

function DriveOf(const AFileName: string): string;
var
  Path: string;
  Parts: TStringArray;
begin
  Result := ExtractFileDrive(AFileName);
  {$IFNDEF WINDOWS}
  { Linux: the mount point of a removable drive (/media/<user>/<name>,
    /run/media/<user>/<name>, /mnt/<name>); else the root. }
  if Result = '' then
  begin
    Path := ExcludeLeadingPathDelimiter(AFileName);
    Parts := Path.Split(['/']);
    if (Length(Parts) >= 3) and (Parts[0] = 'media') then
      Result := '/media/' + Parts[1] + '/' + Parts[2]
    else if (Length(Parts) >= 4) and (Parts[0] = 'run') and (Parts[1] = 'media') then
      Result := '/run/media/' + Parts[2] + '/' + Parts[3]
    else if (Length(Parts) >= 2) and (Parts[0] = 'mnt') then
      Result := '/mnt/' + Parts[1]
    else
      Result := '/';
  end;
  {$ENDIF}
end;

function IndexOfDrive(const ADrive: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Troubles) do
    if SameText(Troubles[I].Drive, ADrive) then
      Exit(I);
  Result := -1;
end;

procedure NoteDriveTrouble(const AFileName, AWhat: string);
var
  Drive: string;
  I: Integer;
  Fresh: Boolean;
begin
  Drive := DriveOf(AFileName);
  if Drive = '' then
    Exit;
  EnterCriticalSection(Lock);
  try
    I := IndexOfDrive(Drive);
    if I < 0 then
    begin
      I := Length(Troubles);
      SetLength(Troubles, I + 1);
      Troubles[I].Drive := Drive;
      Troubles[I].LastMs := 0;
    end;
    { New trouble (none before, or the last one long ago): noticed again. }
    Fresh := (Troubles[I].LastMs = 0) or (GetTickCount64 - Troubles[I].LastMs > BackOffMs);
    Troubles[I].LastMs := GetTickCount64;
    if Fresh then
    begin
      Troubles[I].What := AWhat;
      Troubles[I].Noticed := False;
    end;
  finally
    LeaveCriticalSection(Lock);
  end;
end;

function DriveInTrouble(const AFileName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  EnterCriticalSection(Lock);
  try
    if Length(Troubles) = 0 then
      Exit;
    I := IndexOfDrive(DriveOf(AFileName));
    Result := (I >= 0) and (Troubles[I].LastMs > 0)
      and (GetTickCount64 - Troubles[I].LastMs <= BackOffMs);
  finally
    LeaveCriticalSection(Lock);
  end;
end;

function TakeDriveNotice(out ADrive, AWhat: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  ADrive := '';
  AWhat := '';
  EnterCriticalSection(Lock);
  try
    for I := 0 to High(Troubles) do
      if not Troubles[I].Noticed and (Troubles[I].LastMs > 0) then
      begin
        Troubles[I].Noticed := True;
        ADrive := Troubles[I].Drive;
        AWhat := Troubles[I].What;
        Exit(True);
      end;
  finally
    LeaveCriticalSection(Lock);
  end;
end;

function IsMediaErrorCode(ACode: Integer): Boolean;
begin
  {$IFDEF WINDOWS}
  case ACode of
    21,     { ERROR_NOT_READY }
    23,     { ERROR_CRC }
    25,     { ERROR_SEEK }
    27,     { ERROR_SECTOR_NOT_FOUND }
    30,     { ERROR_READ_FAULT }
    31,     { ERROR_GEN_FAILURE }
    55,     { ERROR_DEV_NOT_EXIST }
    121,    { ERROR_SEM_TIMEOUT }
    483,    { ERROR_DEVICE_HARDWARE_ERROR }
    1005,   { ERROR_UNRECOGNIZED_VOLUME }
    1117,   { ERROR_IO_DEVICE }
    1167,   { ERROR_DEVICE_NOT_CONNECTED }
    1392,   { ERROR_FILE_CORRUPT }
    1393:   { ERROR_DISK_CORRUPT }
      Result := True;
  else
    Result := False;
  end;
  {$ELSE}
  case ACode of
    5,      { EIO }
    6,      { ENXIO }
    19,     { ENODEV }
    74,     { EBADMSG }
    110,    { ETIMEDOUT }
    117:    { EUCLEAN (file system needs cleaning) }
      Result := True;
  else
    Result := False;
  end;
  {$ENDIF}
end;

{$IFDEF WINDOWS}
function DHSetErrorMode(uMode: LongWord): LongWord; stdcall;
  external 'kernel32.dll' name 'SetErrorMode';

procedure QuietDriveErrors;
const
  SEM_FAILCRITICALERRORS = $0001;
  SEM_NOOPENFILEERRORBOX = $8000;
var
  Old: LongWord;
begin
  { Keeps what was set, adds: no "insert a disk" / "not ready" boxes, the
    call just fails (and VV says so). }
  Old := DHSetErrorMode(SEM_FAILCRITICALERRORS or SEM_NOOPENFILEERRORBOX);
  DHSetErrorMode(Old or SEM_FAILCRITICALERRORS or SEM_NOOPENFILEERRORBOX);
end;
{$ENDIF}

initialization
  InitCriticalSection(Lock);
  {$IFDEF WINDOWS}
  QuietDriveErrors;
  {$ENDIF}

finalization
  DoneCriticalSection(Lock);

end.
