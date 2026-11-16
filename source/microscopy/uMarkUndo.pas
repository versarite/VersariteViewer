unit uMarkUndo;

{
  Unit: uMarkUndo

  Purpose
  -------
  Undo for the marks (Day 28, user: "the drawing operations, text
  label, measurements, scale bars should be undoable"). Each mark tool
  (uMeasureLine, uScaleBar, uTextLabel) hands in what it looked like
  before a change (a TMarkSnapshot of its own); Undo puts the newest
  back. It joins the viewer's Undo (the menu's first entry, the mouse
  profile's Undo, the sort panel's bottom line): uExtensions'
  RegisterEditionUndo, ordered with the file undos by NextUndoStamp, so
  Undo always takes back what came last.
  - One list for all three tools, newest last, at most MaxEntries.
  - The marks belong to their image: Undo takes back the newest entry of
    the image shown; the others wait (Day 29: the marks come back with
    their image, uMarkMemory, and so does their Undo).

  Owns
  ----
  The entries and their snapshots.

  Does NOT
  --------
  - Redo.
  - Undo a calibration made by a reference measurement (that is in
    calibrations.ini; only the line comes back).

  Threads
  -------
  UI thread.

  Uses (MView units)
  ------------------
  implementation: uExtensions
  Libraries:      Classes, SysUtils

  Used by
  -------
  uMeasureLine, uScaleBar, uTextLabel
}

{$mode ObjFPC}{$H+}

interface

type
  { What one tool's marks were before a change; Restore puts them back
    (and ends the tool's mode). The list owns it. }
  TMarkSnapshot = class
  public
    procedure Restore; virtual; abstract;
  end;

{ Before a change of the marks of AImageName: ASnapshot the way they
  were; ACaption what Undo then says ('Undo scale bar'). }
procedure PushMarkUndo(ASnapshot: TMarkSnapshot; const AImageName, ACaption: string);

implementation

uses
  Classes,
  SysUtils,
  uExtensions;

const
  MaxEntries = 200;          { all images together }

type
  TMarkEntry = record
    Snapshot: TMarkSnapshot;
    ImageName: string;
    Caption: string;
    Stamp: Int64;
  end;

var
  Entries: array of TMarkEntry;

procedure DropEntry(AIndex: Integer);
var
  I: Integer;
begin
  if (AIndex < 0) or (AIndex > High(Entries)) then
    Exit;
  Entries[AIndex].Snapshot.Free;
  for I := AIndex to High(Entries) - 1 do
    Entries[I] := Entries[I + 1];
  SetLength(Entries, Length(Entries) - 1);
end;

{ The newest entry of the image shown, -1 = none. }
function NewestOfShown: Integer;
var
  I: Integer;
  Shown: string;
begin
  Result := -1;
  Shown := ShownImageName;
  if Shown = '' then
    Exit;
  for I := High(Entries) downto 0 do
    if SameText(Entries[I].ImageName, Shown) then
      Exit(I);
end;

procedure PushMarkUndo(ASnapshot: TMarkSnapshot; const AImageName, ACaption: string);
var
  N: Integer;
begin
  if ASnapshot = nil then
    Exit;
  if AImageName = '' then
  begin
    ASnapshot.Free;
    Exit;
  end;
  if Length(Entries) >= MaxEntries then
    DropEntry(0);
  N := Length(Entries);
  SetLength(Entries, N + 1);
  Entries[N].Snapshot := ASnapshot;
  Entries[N].ImageName := AImageName;
  Entries[N].Caption := ACaption;
  Entries[N].Stamp := NextUndoStamp;
end;

function MarkUndoCaption: string;
var
  I: Integer;
begin
  I := NewestOfShown;
  if I < 0 then
    Result := ''
  else
    Result := Entries[I].Caption;
end;

function MarkUndoStamp: Int64;
var
  I: Integer;
begin
  I := NewestOfShown;
  if I < 0 then
    Result := 0
  else
    Result := Entries[I].Stamp;
end;

procedure MarkUndo;
var
  S: TMarkSnapshot;
  Caption: string;
  I: Integer;
begin
  I := NewestOfShown;
  if I < 0 then
    Exit;
  S := Entries[I].Snapshot;
  Caption := Entries[I].Caption;
  { Off the list first: Restore must not find itself there. }
  Entries[I].Snapshot := nil;
  DropEntry(I);
  try
    S.Restore;
  finally
    S.Free;
  end;
  ViewerNote(LowerCase(Copy(Caption, 1, 1)) + Copy(Caption, 2, MaxInt) + ': done', 3000);
end;

procedure FreeEntries;
var
  I: Integer;
begin
  for I := 0 to High(Entries) do
    Entries[I].Snapshot.Free;
  Entries := nil;
end;

initialization
  RegisterEditionUndo(@MarkUndoCaption, @MarkUndoStamp, @MarkUndo);
finalization
  FreeEntries;
end.
