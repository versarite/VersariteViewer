unit uMarkMemory;

{
  Unit: uMarkMemory

  Purpose
  -------
  The marks remembered per image (Day 29, user: "the mouse wheel erases
  everything when accidentally used"): when another image comes, each
  mark tool (uScaleBar, uMeasureLine, uTextLabel) hands in its marks
  for the image it leaves; when an image comes back, the tool takes
  them out again. For this session (not written to disk).
  - One entry per tool and image (ATool + the image's name); a new one
    replaces the old.
  - At most MaxEntries in all; the oldest go first.
  - Recall takes the entry out (the tool holds the marks again; deleted
    or undone marks don't come back).

  Owns
  ----
  The entries and their objects.

  Threads
  -------
  UI thread.

  Uses (MView units)
  ------------------
  none
  Libraries:      Classes, SysUtils

  Used by
  -------
  uScaleBar, uMeasureLine, uTextLabel
}

{$mode ObjFPC}{$H+}

interface

{ AData: the tool's marks for AImage (the store owns it from now on). }
procedure RememberMarks(const ATool, AImage: string; AData: TObject);
{ The marks kept for AImage, taken out (the caller owns them), or nil. }
function RecallMarks(const ATool, AImage: string): TObject;
{ Anything kept for AImage (by any tool)? }
function HasRememberedMarks(const AImage: string): Boolean;

implementation

uses
  Classes,
  SysUtils;

const
  MaxEntries = 600;

var
  Entries: TStringList = nil;   { 'tool|image', Objects = the marks, oldest first }

function KeyOf(const ATool, AImage: string): string;
begin
  { File names: as Windows compares them. }
  Result := LowerCase(ATool) + '|' + LowerCase(AImage);
end;

procedure DropEntry(AIndex: Integer);
begin
  Entries.Objects[AIndex].Free;
  Entries.Delete(AIndex);
end;

procedure RememberMarks(const ATool, AImage: string; AData: TObject);
var
  I: Integer;
begin
  if AData = nil then
    Exit;
  if AImage = '' then
  begin
    AData.Free;
    Exit;
  end;
  if Entries = nil then
    Entries := TStringList.Create;
  I := Entries.IndexOf(KeyOf(ATool, AImage));
  if I >= 0 then
    DropEntry(I);
  while Entries.Count >= MaxEntries do
    DropEntry(0);
  Entries.AddObject(KeyOf(ATool, AImage), AData);
end;

function RecallMarks(const ATool, AImage: string): TObject;
var
  I: Integer;
begin
  Result := nil;
  if (Entries = nil) or (AImage = '') then
    Exit;
  I := Entries.IndexOf(KeyOf(ATool, AImage));
  if I < 0 then
    Exit;
  Result := Entries.Objects[I];
  Entries.Delete(I);
end;

function HasRememberedMarks(const AImage: string): Boolean;
var
  I: Integer;
  Tail: string;
begin
  Result := False;
  if (Entries = nil) or (AImage = '') then
    Exit;
  Tail := '|' + LowerCase(AImage);
  for I := 0 to Entries.Count - 1 do
    if Copy(Entries[I], Length(Entries[I]) - Length(Tail) + 1, MaxInt) = Tail then
      Exit(True);
end;

procedure FreeEntries;
var
  I: Integer;
begin
  if Entries = nil then
    Exit;
  for I := 0 to Entries.Count - 1 do
    Entries.Objects[I].Free;
  FreeAndNil(Entries);
end;

finalization
  FreeEntries;
end.
