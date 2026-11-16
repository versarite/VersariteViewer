unit uFijiFind;

{
  Unit: uFijiFind

  Purpose
  -------
  Finding Fiji for "Open in Fiji" (1.1; spec "Microscopy edition" §9c):
  where its program is, and the file names the Lab hands it. No LCL (for
  the tests); the menu entry and the dialog are in uFijiLink.

  Knows
  -----
  - Fiji's launchers: ImageJ-win64.exe (Fiji.app, the classic one) and
    fiji-windows-x64.exe (the 2025 Fiji), fiji-windows-arm64.exe, a
    plain fiji.exe / ImageJ.exe.
  - Where Fiji is usually unpacked: C:\Fiji.app, C:\Fiji, and Fiji.app /
    Fiji in the user's folder, Desktop, Documents, Downloads, AppData\
    Local and Program Files.

  Does NOT
  --------
  - Start Fiji or write anything (uFijiLink).

  Threads
  -------
  Any thread; no state.

  Uses (MView units)
  ------------------
  none
  Libraries:      Classes, SysUtils

  Used by
  -------
  uFijiLink, TestCalibrations
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils;

{ Fiji's program in AFolder (a Fiji.app or Fiji folder): its full path, or
  '' if there is none. }
function FijiProgramIn(const AFolder: string): string;
{ AName a Fiji program's file name (ImageJ-win64.exe, fiji-windows-x64.exe
  ...)? }
function IsFijiProgramName(const AName: string): Boolean;
{ The folders looked in, in order: AHome the user's folder, ALocal
  %LOCALAPPDATA%, AProgramFiles %ProgramFiles% ('' = left out). }
function FijiCandidateFolders(const AHome, ALocal, AProgramFiles: string): TStringArray;
{ The first Fiji program in the candidate folders, '' if none. }
function FindFijiProgram(const AHome, ALocal, AProgramFiles: string): string;
{ A file name made of AName (no path, no characters Windows refuses, at
  most 80 long; '' -> 'image'), with ASuffix and '.tif'. }
function FijiTiffName(const AName, ASuffix: string): string;

implementation

const
  ProgramNames: array[0..5] of string = ('ImageJ-win64.exe', 'fiji-windows-x64.exe',
    'fiji-windows-arm64.exe', 'fiji.exe', 'ImageJ.exe', 'ImageJ-win32.exe');

function IsFijiProgramName(const AName: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(ProgramNames) do
    if SameText(ExtractFileName(AName), ProgramNames[I]) then
      Exit(True);
  Result := False;
end;

function FijiProgramIn(const AFolder: string): string;
var
  I: Integer;
  Dir: string;
begin
  Result := '';
  if (AFolder = '') or not DirectoryExists(AFolder) then
    Exit;
  Dir := IncludeTrailingPathDelimiter(AFolder);
  for I := 0 to High(ProgramNames) do
    if FileExists(Dir + ProgramNames[I]) then
      Exit(Dir + ProgramNames[I]);
end;

function FijiCandidateFolders(const AHome, ALocal, AProgramFiles: string): TStringArray;
var
  List: TStringList;
  Base: string;

  procedure AddBase(const ABase: string);
  var
    B: string;
  begin
    if ABase = '' then
      Exit;
    B := IncludeTrailingPathDelimiter(ABase);
    List.Add(B + 'Fiji.app');
    List.Add(B + 'Fiji');
  end;

begin
  List := TStringList.Create;
  try
    AddBase('C:\');
    if AHome <> '' then
    begin
      Base := IncludeTrailingPathDelimiter(AHome);
      AddBase(AHome);
      AddBase(Base + 'Desktop');
      AddBase(Base + 'Documents');
      AddBase(Base + 'Downloads');
    end;
    AddBase(ALocal);
    AddBase(AProgramFiles);
    Result := List.ToStringArray;
  finally
    List.Free;
  end;
end;

function FindFijiProgram(const AHome, ALocal, AProgramFiles: string): string;
var
  Folders: TStringArray;
  I: Integer;
begin
  Result := '';
  Folders := FijiCandidateFolders(AHome, ALocal, AProgramFiles);
  for I := 0 to High(Folders) do
  begin
    Result := FijiProgramIn(Folders[I]);
    if Result <> '' then
      Exit;
  end;
end;

function FijiTiffName(const AName, ASuffix: string): string;
var
  I: Integer;
  S: string;
begin
  S := ExtractFileName(StringReplace(AName, '/', '\', [rfReplaceAll]));
  { A name inside a container ('221107.lif|Series009'): both parts. }
  S := StringReplace(S, '|', '_', [rfReplaceAll]);
  if SameText(ExtractFileExt(S), '.tif') or SameText(ExtractFileExt(S), '.tiff') then
    S := ChangeFileExt(S, '');
  for I := 1 to Length(S) do
    if S[I] in ['\', '/', ':', '*', '?', '"', '<', '>', '|', #0..#31] then
      S[I] := '_';
  S := Trim(S);
  while (S <> '') and (S[Length(S)] = '.') do
    Delete(S, Length(S), 1);
  if Length(S) > 80 then
    S := Copy(S, 1, 80);
  if S = '' then
    S := 'image';
  Result := S + ASuffix + '.tif';
end;

end.
