unit uEdition;

{
  Unit: uEdition

  Purpose
  -------
  Which program this is (M0, Day 25): VersariteViewer, or an edition
  built from the same source tree (Versarite Image Lab, the microscopy
  edition). Named so in 1.1 (formerly MView / MView Image Lab). The two
  programs share every unit; they differ in what their .lpr lists, and
  in the names set here: their settings file, their single-instance
  names, their window title. So both can run at the same time, from the
  same folder or not, without touching each other's settings.

  Owns
  ----
  Three strings, set once at start-up.

  Knows
  -----
  Nothing else.

  Responsibilities
  ----------------
  - EditionId: a short name without spaces ('VersariteViewer'), the base
    of the file and object names: <EditionId>.ini, the exe, the mutex
    and the shared memory block of the single instance.
  - EditionOldId: the name before 1.1 ('MView'): its ini is taken over
    at the first start (uConfig).
  - EditionTitle: the name shown ('VersariteViewer'): About box, texts.
  - EditionCaption: the window's title.
  - EditionText: a text written with "VersariteViewer" for this edition
    (its name, its ini file, its exe).
  - EditionVersion: shown in the About box.
  - SetEdition: the edition's .lpr calls it first thing (before any
    TConfig is made); MView's .lpr doesn't need to (the defaults are
    MView's).

  Does NOT
  --------
  - Decide any behaviour: the edition's own units plug themselves in
    (uExtensions).

  Threads
  -------
  Set on the main thread before any other thread exists; read anywhere.

  Uses (MView units)
  ------------------
  (none)

  Used by
  -------
  uConfig, uSingleInstance, uMainForm, uIniEditor, the program files
}

{$mode ObjFPC}{$H+}

interface

const
  MViewVersion = '1.2';

var
  EditionId: string = 'VersariteViewer';
  EditionOldId: string = 'MView';
  EditionTitle: string = 'VersariteViewer';
  EditionVersion: string = MViewVersion;
  { The window's title (user, Day 25). }
  EditionCaption: string = 'VersariteViewer';

{ Call first in an edition's .lpr: AId without spaces
  ('VersariteImageLab'), AOldId its name before 1.1 ('MViewLab').
  ACaption '' = the title. }
procedure SetEdition(const AId, AOldId, ATitle, AVersion: string; const ACaption: string = '');

{ <folder of the exe>\<EditionId>.ini }
function EditionIniFileName: string;
{ <folder of the exe>\<EditionOldId>.ini (taken over at the first start). }
function EditionOldIniFileName: string;
{ AText as this edition says it: "VersariteViewer.ini", "VersariteViewer.exe"
  and "VersariteViewer" become its own ini, exe and name. }
function EditionText(const AText: string): string;

{ An edition's own ini keys (1.1): registered in its units'
  initialization sections. The settings save (uConfig) writes a key that
  is missing with its default when AWrite (so the key can be found on the
  settings screen); the settings screen shows AHelp for it. }
procedure RegisterEditionKey(const ASection, AKey, ADefault, AHelp: string; AWrite: Boolean = True);
function EditionKeyCount: Integer;
procedure EditionKey(AIndex: Integer; out ASection, AKey, ADefault: string; out AWrite: Boolean);
{ The help of a registered key, '' if none. }
function EditionKeyHelp(const ASection, AKey: string): string;

implementation

uses
  SysUtils;

procedure SetEdition(const AId, AOldId, ATitle, AVersion: string; const ACaption: string);
begin
  EditionId := AId;
  EditionOldId := AOldId;
  EditionTitle := ATitle;
  EditionVersion := AVersion;
  if ACaption <> '' then
    EditionCaption := ACaption
  else
    EditionCaption := ATitle;
end;

type
  TEditionKey = record
    Section, Key, Default, Help: string;
    Write: Boolean;
  end;

var
  Keys: array of TEditionKey;

procedure RegisterEditionKey(const ASection, AKey, ADefault, AHelp: string; AWrite: Boolean);
var
  I: Integer;
begin
  for I := 0 to High(Keys) do
    if SameText(Keys[I].Section, ASection) and SameText(Keys[I].Key, AKey) then
      Exit;
  SetLength(Keys, Length(Keys) + 1);
  Keys[High(Keys)].Section := ASection;
  Keys[High(Keys)].Key := AKey;
  Keys[High(Keys)].Default := ADefault;
  Keys[High(Keys)].Help := AHelp;
  Keys[High(Keys)].Write := AWrite;
end;

function EditionKeyCount: Integer;
begin
  Result := Length(Keys);
end;

procedure EditionKey(AIndex: Integer; out ASection, AKey, ADefault: string; out AWrite: Boolean);
begin
  ASection := Keys[AIndex].Section;
  AKey := Keys[AIndex].Key;
  ADefault := Keys[AIndex].Default;
  AWrite := Keys[AIndex].Write;
end;

function EditionKeyHelp(const ASection, AKey: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Keys) do
    if SameText(Keys[I].Section, ASection) and SameText(Keys[I].Key, AKey) then
      Exit(Keys[I].Help);
end;

function EditionIniFileName: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + EditionId + '.ini';
end;

function EditionOldIniFileName: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + EditionOldId + '.ini';
end;

function EditionText(const AText: string): string;
begin
  Result := AText;
  if EditionId = 'VersariteViewer' then
    Exit;
  Result := StringReplace(Result, 'VersariteViewer.ini', EditionId + '.ini', [rfReplaceAll]);
  Result := StringReplace(Result, 'VersariteViewer.exe', EditionId + '.exe', [rfReplaceAll]);
  Result := StringReplace(Result, 'VersariteViewer', EditionTitle, [rfReplaceAll]);
end;

end.
