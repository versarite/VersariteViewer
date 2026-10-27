unit uSortFolders;

{
  Unit: uSortFolders

  Purpose
  -------
  The folders of the sort panel (Phase G, G1): the slots the user sorts
  images into (left click on the panel = copy, right click = move), and
  the folders used recently. Only the list and its place in MView.ini;
  no drawing, no file work.

  Owns
  ----
  - FSlots: the slots (folder, name, colour, icon file), in panel order.
  - FRecent: the recently assigned folders, newest first, at most
    MaxRecentFolders.

  Knows
  -----
  - The TCustomIniFile handed to LoadFromIni / SaveToIni (TConfig's).

  Responsibilities
  ----------------
  - Slots: add (a folder dropped on "+"), replace a slot's folder, set
    its colour or icon, remove it. A new slot gets the folder's own name
    ("D:\Sorted\Good" -> "Good") and the first colour not in use.
  - Recent folders: every folder assigned to a slot goes to the front of
    the list (no duplicates).
  - Several lists (Day 27, testers): the slots above are the current
    list's; CycleList goes to the next / previous one, past the last a
    new empty list, then round again. Empty lists are dropped when left.
  - Dynamic lists and pinned folders (Day 32, user): a list can be
    dynamic ([DirList<n>] Dynamic=1): a folder copied or moved into goes
    up one place (NoteUsed), but only when ApplyUse is called - TMView
    does that once the mouse has left the panel, so the list never moves
    under a resting mouse. A pinned folder (Slot<n>Pinned=1, in any list)
    stays on top in the order given; the pinned ones come first, the
    others never climb above them, and Move keeps each in its part
    (SlotRange).
  - Rapid Selection (Day 27, testers): a fixed list of ten slots
    (Selection1 .. Selection9, Selection0 in one folder; keys 1 .. 0),
    shown instead of the current list while on; not one of the cycled
    lists and never written.
  - Read and write each list's [DirList<n>] keys Slot<n>Folder / Name /
    Color / Icon, and [Sort] List (the current one) and Recent<n>: one
    key per value, so any folder name is safe. Old keys of removed slots
    and sections of removed lists are deleted when writing. Slots in
    [Sort] itself (before Day 27) are read as list 1 and moved.
  - Slot colours by name (Green, Blue, Red, Yellow, Orange, Purple,
    Cyan, Grey) and as RGB for drawing.

  Does NOT
  --------
  - Check whether a folder exists (that reads the disk: the file mover
    does it on its thread).
  - Draw the panel, copy or move files, or read the other [Sort] keys
    (TConfig: EdgeDelayMs, Pinned, DeletedFolder, IconFolder,
    TotalCommander).

  Threads
  -------
  UI thread only.

  Uses (MView units)
  ------------------
  None: depends only on the libraries below.
  Libraries:      Classes, SysUtils, IniFiles

  Used by
  -------
  uConfig, uMView, uSortPanel, umainform
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  IniFiles,
  Math;

const
  SortSection = 'Sort';
  MaxSortSlots = 64;
  MaxSortLists = 99;
  ListSectionPrefix = 'DirList';
  { [Sort] List: the folder list shown (1-based). }
  KEY_LIST = 'List';
  { [DirList<n>] Dynamic=1 (Day 32): used folders go up. }
  KEY_DYNAMIC = 'Dynamic';
  { Rapid Selection: ten slots, keys 1 .. 9, 0. }
  RapidSlots = 10;
  MaxRecentFolders = 8;
  { An old section (M2c pinned containers to the side panel; since Day 25
    they are transient): only erased, never written. }
  ContainersSection = 'Containers';

type

  { Pink and Brown (Day 27): ten colours, one for each Rapid Selection key. }
  TSlotColor = (scGreen, scBlue, scRed, scYellow, scOrange, scPurple, scCyan, scGrey,
    scPink, scBrown);

  TSortSlot = record
    Folder: string;     { full path, without trailing delimiter }
    Name: string;       { shown on the panel }
    Color: TSlotColor;
    Icon: string;       { icon file (name in the icon folder, or a full path); '' = none }
    Pinned: Boolean;    { on top, in the order given (Day 32) }
  end;

  TSortSlots = array of TSortSlot;
  TSortSlotLists = array of TSortSlots;

  TSortFolders = class(TObject)
  private
    FSlots: TSortSlots;          { the list shown: the current one, or Rapid Selection's }
    FLists: TSortSlotLists;      { all lists; FLists[FCurrent] is behind FSlots }
    FDynamic: array of Boolean;  { per list (as FLists): dynamic (Day 32) }
    FUsed: TStringList;          { folders used, to go up at the next ApplyUse }
    FCurrent: Integer;
    FRapid: Boolean;
    FRecent: TStringList;
    { Copy / cut / paste of a button (1.1): the entry, cut or copied, and
      the list it was cut from. }
    FClip: TSortSlot;
    FHasClip: Boolean;
    FClipCut: Boolean;
    FClipList: Integer;
    function ClipMatches(const ASlot: TSortSlot): Boolean;
    function FirstFreeColor: TSlotColor;
    procedure StoreCurrent;
    procedure ReadSlots(AIni: TCustomIniFile; const ASection: string; out ASlots: TSortSlots);
    procedure WriteSlots(AIni: TCustomIniFile; const ASection: string; const ASlots: TSortSlots);
    procedure SyncDynamic;
    procedure MoveSlot(AFrom, ATo: Integer);
  public
    constructor Create;
    destructor Destroy; override;

    function Count: Integer;
    function Slot(AIndex: Integer): TSortSlot;
    { The number on slot AIndex's folder: 1, 2, ...; Rapid Selection:
      its key (1 .. 9, 0). }
    function SlotLabel(AIndex: Integer): string;

    { Several lists (Day 27): how many there are (an empty new one
      counts while shown), which one is shown (0-based). }
    function ListCount: Integer;
    property ListIndex: Integer read FCurrent;
    { ADir = 1: the next list, -1: the previous one; past the last
      occupied list a new empty one, then round again. }
    procedure CycleList(ADir: Integer);
    { CycleList(ADir) would show a new, empty list (the arrow is drawn red,
      Day 27). False while there is no occupied list at all. }
    function NextIsNew(ADir: Integer): Boolean;

    { Rapid Selection (Day 27): on = the ten fixed slots, AFolders[0] for
      key 1 .. AFolders[9] for key 0 (full paths; [Sort] RapidFolder1 ..
      RapidFolder0, 1.1); off = the list before (AFolders not used). }
    procedure SetRapid(AOn: Boolean; const AFolders: array of string);
    property Rapid: Boolean read FRapid;

    { AIndex = Count adds a slot (when there is room); otherwise the
      slot's folder is replaced (its name follows the new folder, its
      colour and icon stay). Returns the slot's index, -1 if not done. }
    function SetFolder(AIndex: Integer; const AFolder: string): Integer;
    procedure SetColor(AIndex: Integer; AColor: TSlotColor);
    procedure SetIcon(AIndex: Integer; const AIcon: string);
    procedure SetName(AIndex: Integer; const AName: string);
    procedure Remove(AIndex: Integer);
    { ATo is kept within AFrom's part of the list (SlotRange). }
    procedure Move(AFrom, ATo: Integer);

    { Dynamic sorting and pinning (Day 32, user). Dynamic: the list shown
      (never Rapid Selection). }
    function Dynamic: Boolean;
    procedure SetDynamic(AOn: Boolean);
    function PinnedCount: Integer;
    { Pins (on top, below the last pinned one) or unpins (first below the
      pinned ones) slot AIndex; its new index. }
    function SetPinned(AIndex: Integer; AOn: Boolean): Integer;
    { Where slot AIndex may go: the pinned part or the rest. }
    procedure SlotRange(AIndex: Integer; out ALow, AHigh: Integer);
    { A copy / move into AFolder is done: in a dynamic list it goes up
      one place at the next ApplyUse (not pinned ones, never above them). }
    procedure NoteUsed(const AFolder: string);
    function HasUse: Boolean;
    { Moves them; True if the list changed. Also done before another
      list is shown and before Rapid Selection. }
    function ApplyUse: Boolean;

    { Copy / cut / paste of a button between the lists (1.1, testers).
      Copy and Cut remember the entry; a cut one stays where it is,
      dimmed (IsCutSlot), until it is pasted (then it leaves its place)
      or the cut is cancelled. PasteSlot puts it after AAfter (-1 = on
      top) in the list shown: its index, or -1 with the reason. A copy
      can be pasted again; a folder the list has already is not added. }
    procedure CopySlot(AIndex: Integer; ACut: Boolean);
    function PasteSlot(AAfter: Integer; out AReason: string): Integer;
    procedure CancelCut;
    function HasClip: Boolean;
    function ClipIsCut: Boolean;
    function ClipName: string;
    function IsCutSlot(AIndex: Integer): Boolean;

    procedure AddRecent(const AFolder: string);
    function Recent: TStrings;

    procedure Assign(ASource: TSortFolders);
    { No slots, no recent folders. }
    procedure Clear;
    procedure LoadFromIni(AIni: TCustomIniFile);
    procedure SaveToIni(AIni: TCustomIniFile);
  end;


function SlotColorName(AColor: TSlotColor): string;
function ParseSlotColor(const AName: string; ADefault: TSlotColor): TSlotColor;
{ $00BBGGRR, as TColor. }
function SlotColorValue(AColor: TSlotColor): LongWord;
{ The last part of a folder: "D:\Sorted\Good" -> "Good" ("D:\" -> "D:"). }
function FolderDisplayName(const AFolder: string): string;
{ The icon name a slot finds by itself (stage 2): its folder's last part
  without characters a file name can't have ("D:\" -> "D"); 'icon' if
  nothing is left. "D:\Sorted\Good" -> "Good" (Good.ico / Good.png). }
function IconBaseName(const AFolder: string): string;

implementation

const
  ColorNames: array[TSlotColor] of string =
    ('Green', 'Blue', 'Red', 'Yellow', 'Orange', 'Purple', 'Cyan', 'Grey', 'Pink', 'Brown');
  { $00BBGGRR }
  ColorValues: array[TSlotColor] of LongWord =
    ($0040A040, $00D07030, $003838D0, $0020C8E0, $002090F0, $00B04890, $00C0B030, $00909090,
     $00A060E8, $00305C8C);

function SlotColorName(AColor: TSlotColor): string;
begin
  Result := ColorNames[AColor];
end;

function ParseSlotColor(const AName: string; ADefault: TSlotColor): TSlotColor;
var
  C: TSlotColor;
begin
  for C := Low(TSlotColor) to High(TSlotColor) do
    if SameText(Trim(AName), ColorNames[C]) then
      Exit(C);
  Result := ADefault;
end;

function SlotColorValue(AColor: TSlotColor): LongWord;
begin
  Result := ColorValues[AColor];
end;

function FolderDisplayName(const AFolder: string): string;
var
  F: string;
begin
  F := ExcludeTrailingPathDelimiter(Trim(AFolder));
  Result := ExtractFileName(F);
  if Result = '' then
    Result := F;
end;

{ TSortFolders }

{ The pinned slots first, each part in its order (Day 32). }
procedure PinnedFirst(var ASlots: TSortSlots);
var
  Sorted: TSortSlots;
  I, N: Integer;
begin
  SetLength(Sorted, Length(ASlots));
  N := 0;
  for I := 0 to High(ASlots) do
    if ASlots[I].Pinned then
    begin
      Sorted[N] := ASlots[I];
      Inc(N);
    end;
  for I := 0 to High(ASlots) do
    if not ASlots[I].Pinned then
    begin
      Sorted[N] := ASlots[I];
      Inc(N);
    end;
  ASlots := Sorted;
end;

constructor TSortFolders.Create;
begin
  inherited Create;
  FRecent := TStringList.Create;
  FUsed := TStringList.Create;
  SetLength(FLists, 1);
  SyncDynamic;
  FCurrent := 0;
end;

destructor TSortFolders.Destroy;
begin
  FUsed.Free;
  FRecent.Free;
  inherited Destroy;
end;

{ FDynamic as long as FLists (a new list: not dynamic). }
procedure TSortFolders.SyncDynamic;
var
  I, Old: Integer;
begin
  Old := Length(FDynamic);
  SetLength(FDynamic, Length(FLists));
  for I := Old to High(FDynamic) do
    FDynamic[I] := False;
end;

function TSortFolders.Dynamic: Boolean;
begin
  Result := (not FRapid) and (FCurrent >= 0) and (FCurrent <= High(FDynamic))
    and FDynamic[FCurrent];
end;

procedure TSortFolders.SetDynamic(AOn: Boolean);
begin
  if FRapid then
    Exit;
  SyncDynamic;
  if (FCurrent >= 0) and (FCurrent <= High(FDynamic)) then
    FDynamic[FCurrent] := AOn;
  if not AOn then
    FUsed.Clear;
end;

function TSortFolders.PinnedCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  if FRapid then
    Exit;
  for I := 0 to High(FSlots) do
    if FSlots[I].Pinned then
      Inc(Result);
end;

function TSortFolders.SetPinned(AIndex: Integer; AOn: Boolean): Integer;
var
  N: Integer;
begin
  Result := AIndex;
  if FRapid or (AIndex < 0) or (AIndex >= Length(FSlots)) or (FSlots[AIndex].Pinned = AOn) then
    Exit;
  N := PinnedCount;
  FSlots[AIndex].Pinned := AOn;
  { Pinned: below the last pinned one (N, before this one counts); unpinned:
    the first of the rest (the pinned ones are now N - 1). }
  if AOn then
    Result := N
  else
    Result := N - 1;
  MoveSlot(AIndex, Result);
  StoreCurrent;
end;

procedure TSortFolders.SlotRange(AIndex: Integer; out ALow, AHigh: Integer);
var
  N: Integer;
begin
  N := PinnedCount;
  if (AIndex >= 0) and (AIndex < Length(FSlots)) and FSlots[AIndex].Pinned then
  begin
    ALow := 0;
    AHigh := N - 1;
  end
  else
  begin
    ALow := N;
    AHigh := High(FSlots);
  end;
end;

procedure TSortFolders.NoteUsed(const AFolder: string);
begin
  if Dynamic and (Trim(AFolder) <> '') then
    FUsed.Add(ExcludeTrailingPathDelimiter(AFolder));
end;

function TSortFolders.HasUse: Boolean;
begin
  Result := FUsed.Count > 0;
end;

function TSortFolders.ApplyUse: Boolean;
var
  K, I, Here, N: Integer;
  S: TSortSlot;
begin
  Result := False;
  if FUsed.Count = 0 then
    Exit;
  if Dynamic then
  begin
    N := PinnedCount;
    for K := 0 to FUsed.Count - 1 do
    begin
      Here := -1;
      for I := 0 to High(FSlots) do
        if SameText(FSlots[I].Folder, FUsed[K]) then
        begin
          Here := I;
          Break;
        end;
      { One place up; pinned ones stay, the others not above them. }
      if (Here > N) and not FSlots[Here].Pinned then
      begin
        S := FSlots[Here - 1];
        FSlots[Here - 1] := FSlots[Here];
        FSlots[Here] := S;
        Result := True;
      end;
    end;
    if Result then
      StoreCurrent;
  end;
  FUsed.Clear;
end;

function TSortFolders.Count: Integer;
begin
  Result := Length(FSlots);
end;

function TSortFolders.Slot(AIndex: Integer): TSortSlot;
begin
  Result := FSlots[AIndex];
end;

function TSortFolders.SlotLabel(AIndex: Integer): string;
begin
  if FRapid then
    Result := IntToStr((AIndex + 1) mod 10)
  else
    Result := IntToStr(AIndex + 1);
end;

{ The shown list back into FLists (it is worked on in FSlots). }
procedure TSortFolders.StoreCurrent;
begin
  if not FRapid then
    FLists[FCurrent] := Copy(FSlots, 0, Length(FSlots));
end;

function TSortFolders.ListCount: Integer;
begin
  Result := Length(FLists);
end;

procedure TSortFolders.CycleList(ADir: Integer);
var
  Kept: TSortSlotLists;
  KeptDynamic: array of Boolean;
  I, Pos, Occupied, NewClip: Integer;
begin
  NewClip := -1;
  if FRapid or (ADir = 0) then
    Exit;
  ApplyUse;
  StoreCurrent;
  SyncDynamic;
  { Empty lists go; the empty one shown stands for "new". }
  Kept := nil;
  KeptDynamic := nil;
  Pos := -1;
  for I := 0 to High(FLists) do
    if Length(FLists[I]) > 0 then
    begin
      if I = FCurrent then
        Pos := Length(Kept);
      if I = FClipList then
        NewClip := Length(Kept);         { the cut one's list, renumbered }
      SetLength(Kept, Length(Kept) + 1);
      Kept[High(Kept)] := FLists[I];
      SetLength(KeptDynamic, Length(Kept));
      KeptDynamic[High(KeptDynamic)] := FDynamic[I];
    end;
  FClipList := NewClip;
  Occupied := Length(Kept);
  if Pos < 0 then
    Pos := Occupied;                  { on the new, empty list }
  { Positions 0 .. Occupied - 1, and Occupied = a new empty list. }
  if ADir > 0 then
    Pos := (Pos + 1) mod (Occupied + 1)
  else
    Pos := (Pos + Occupied) mod (Occupied + 1);
  if (Pos = Occupied) and (Occupied >= MaxSortLists) then
    Pos := 0;
  if Pos = Occupied then
  begin
    SetLength(Kept, Occupied + 1);
    Kept[Occupied] := nil;
  end;
  if Length(Kept) = 0 then
    SetLength(Kept, 1);
  FLists := Kept;
  FDynamic := KeptDynamic;
  SyncDynamic;
  FCurrent := Pos;
  FSlots := Copy(FLists[FCurrent], 0, Length(FLists[FCurrent]));
end;

function TSortFolders.NextIsNew(ADir: Integer): Boolean;
var
  I, Pos, Occupied: Integer;
begin
  Result := False;
  if FRapid or (ADir = 0) then
    Exit;
  { As CycleList counts: the occupied lists, the shown one by FSlots. }
  Occupied := 0;
  Pos := -1;
  for I := 0 to High(FLists) do
  begin
    if I = FCurrent then
    begin
      if Length(FSlots) = 0 then
        Continue;
      Pos := Occupied;
    end
    else if Length(FLists[I]) = 0 then
      Continue;
    Inc(Occupied);
  end;
  if Occupied = 0 then
    Exit;
  if Pos < 0 then
    Pos := Occupied;
  if ADir > 0 then
    Pos := (Pos + 1) mod (Occupied + 1)
  else
    Pos := (Pos + Occupied) mod (Occupied + 1);
  Result := (Pos = Occupied) and (Occupied < MaxSortLists);
end;

procedure TSortFolders.SetRapid(AOn: Boolean; const AFolders: array of string);
const
  Colors: array[0..RapidSlots - 1] of TSlotColor =
    (scGreen, scBlue, scRed, scYellow, scOrange, scPurple, scCyan, scGrey, scPink, scBrown);
var
  I: Integer;
  Folder: string;
begin
  if AOn then
  begin
    ApplyUse;
    StoreCurrent;
    SetLength(FSlots, RapidSlots);
    for I := 0 to RapidSlots - 1 do
    begin
      if I <= High(AFolders) then
        Folder := ExcludeTrailingPathDelimiter(Trim(AFolders[I]))
      else
        Folder := '';
      FSlots[I].Folder := Folder;
      FSlots[I].Name := ExtractFileName(Folder);
      if FSlots[I].Name = '' then
        FSlots[I].Name := Folder;
      FSlots[I].Color := Colors[I];
      FSlots[I].Icon := '-';           { the numbered folder, never an icon }
      FSlots[I].Pinned := False;
    end;
    FRapid := True;
  end
  else if FRapid then
  begin
    FRapid := False;
    FSlots := Copy(FLists[FCurrent], 0, Length(FLists[FCurrent]));
  end;
end;

function TSortFolders.FirstFreeColor: TSlotColor;
var
  C: TSlotColor;
  I: Integer;
  Used: Boolean;
begin
  for C := Low(TSlotColor) to High(TSlotColor) do
  begin
    Used := False;
    for I := 0 to High(FSlots) do
      if FSlots[I].Color = C then
        Used := True;
    if not Used then
      Exit(C);
  end;
  { All in use: go round. }
  Result := TSlotColor(Length(FSlots) mod (Ord(High(TSlotColor)) + 1));
end;

function TSortFolders.SetFolder(AIndex: Integer; const AFolder: string): Integer;
var
  F: string;
begin
  Result := -1;
  F := ExcludeTrailingPathDelimiter(Trim(AFolder));
  if (F = '') or FRapid then
    Exit;
  if (AIndex = Length(FSlots)) and (Length(FSlots) < MaxSortSlots) then
  begin
    SetLength(FSlots, Length(FSlots) + 1);
    FSlots[AIndex].Color := FirstFreeColor;
    FSlots[AIndex].Icon := '';
    FSlots[AIndex].Pinned := False;
  end
  else if (AIndex < 0) or (AIndex >= Length(FSlots)) then
    Exit;
  FSlots[AIndex].Folder := F;
  FSlots[AIndex].Name := FolderDisplayName(F);
  AddRecent(F);
  Result := AIndex;
end;

procedure TSortFolders.SetColor(AIndex: Integer; AColor: TSlotColor);
begin
  if not FRapid and (AIndex >= 0) and (AIndex < Length(FSlots)) then
    FSlots[AIndex].Color := AColor;
end;

procedure TSortFolders.SetIcon(AIndex: Integer; const AIcon: string);
begin
  if not FRapid and (AIndex >= 0) and (AIndex < Length(FSlots)) then
    FSlots[AIndex].Icon := Trim(AIcon);
end;

procedure TSortFolders.SetName(AIndex: Integer; const AName: string);
begin
  if not FRapid and (AIndex >= 0) and (AIndex < Length(FSlots)) and (Trim(AName) <> '') then
    FSlots[AIndex].Name := Trim(AName);
end;

procedure TSortFolders.Remove(AIndex: Integer);
var
  I: Integer;
begin
  if FRapid or (AIndex < 0) or (AIndex >= Length(FSlots)) then
    Exit;
  for I := AIndex to High(FSlots) - 1 do
    FSlots[I] := FSlots[I + 1];
  SetLength(FSlots, Length(FSlots) - 1);
end;

procedure TSortFolders.Move(AFrom, ATo: Integer);
var
  Low_, High_: Integer;
begin
  if FRapid or (AFrom < 0) or (AFrom >= Length(FSlots)) then
    Exit;
  { Within its part (Day 32): pinned among the pinned, the rest below. }
  SlotRange(AFrom, Low_, High_);
  MoveSlot(AFrom, EnsureRange(ATo, Low_, Max(Low_, High_)));
end;

procedure TSortFolders.MoveSlot(AFrom, ATo: Integer);
var
  S: TSortSlot;
  I: Integer;
begin
  if FRapid or (AFrom < 0) or (AFrom >= Length(FSlots)) or (ATo < 0) or (ATo >= Length(FSlots))
    or (AFrom = ATo) then
    Exit;
  S := FSlots[AFrom];
  if AFrom < ATo then
    for I := AFrom to ATo - 1 do
      FSlots[I] := FSlots[I + 1]
  else
    for I := AFrom downto ATo + 1 do
      FSlots[I] := FSlots[I - 1];
  FSlots[ATo] := S;
end;

function TSortFolders.ClipMatches(const ASlot: TSortSlot): Boolean;
begin
  Result := SameText(ASlot.Folder, FClip.Folder) and (ASlot.Name = FClip.Name);
end;

procedure TSortFolders.CopySlot(AIndex: Integer; ACut: Boolean);
begin
  if FRapid or (AIndex < 0) or (AIndex >= Length(FSlots)) then
    Exit;
  FClip := FSlots[AIndex];
  FHasClip := True;
  FClipCut := ACut;
  FClipList := FCurrent;
end;

procedure TSortFolders.CancelCut;
begin
  if FHasClip and FClipCut then
    FHasClip := False;
end;

function TSortFolders.HasClip: Boolean;
begin
  Result := FHasClip and not FRapid;
end;

function TSortFolders.ClipIsCut: Boolean;
begin
  Result := FHasClip and FClipCut;
end;

function TSortFolders.ClipName: string;
begin
  if FHasClip then
    Result := FClip.Name
  else
    Result := '';
end;

function TSortFolders.IsCutSlot(AIndex: Integer): Boolean;
begin
  Result := FHasClip and FClipCut and not FRapid and (FClipList = FCurrent)
    and (AIndex >= 0) and (AIndex < Length(FSlots)) and ClipMatches(FSlots[AIndex]);
end;

function TSortFolders.PasteSlot(AAfter: Integer; out AReason: string): Integer;
var
  I, J, L, Here: Integer;
  Found: Boolean;
begin
  Result := -1;
  AReason := '';
  if not FHasClip or FRapid then
  begin
    AReason := 'nothing to paste';
    Exit;
  end;
  AAfter := EnsureRange(AAfter, -1, High(FSlots));
  { The folder in this list already: a cut one from this list moves; a
    copy (or one cut elsewhere) is not added twice. }
  Here := -1;
  for I := 0 to High(FSlots) do
    if SameText(FSlots[I].Folder, FClip.Folder) then
      Here := I;
  if Here >= 0 then
  begin
    if FClipCut and (FClipList = FCurrent) and ClipMatches(FSlots[Here]) then
    begin
      { A move within the list. }
      if Here <= AAfter then
        Dec(AAfter);
      for I := Here to High(FSlots) - 1 do
        FSlots[I] := FSlots[I + 1];
      SetLength(FSlots, Length(FSlots) - 1);
    end
    else
    begin
      AReason := FClip.Name + ' is in this list already';
      Exit;
    end;
  end
  else
  begin
    if Length(FSlots) >= MaxSortSlots then
    begin
      AReason := Format('this list is full (%d buttons)', [MaxSortSlots]);
      Exit;
    end;
    { A cut one leaves the list it was cut from (that one first, else
      wherever it is). }
    if FClipCut then
    begin
      StoreCurrent;
      Found := False;
      for J := -1 to High(FLists) do
      begin
        if J = -1 then
          L := FClipList
        else
          L := J;
        if (L < 0) or (L > High(FLists)) or (L = FCurrent) then
          Continue;
        for I := 0 to High(FLists[L]) do
          if ClipMatches(FLists[L][I]) then
          begin
            Delete(FLists[L], I, 1);
            Found := True;
            Break;
          end;
        if Found then
          Break;
      end;
    end;
  end;
  { In after AAfter. }
  SetLength(FSlots, Length(FSlots) + 1);
  for I := High(FSlots) downto AAfter + 2 do
    FSlots[I] := FSlots[I - 1];
  FSlots[AAfter + 1] := FClip;
  Result := AAfter + 1;
  { A pinned one stays among the pinned, an unpinned one below them. }
  PinnedFirst(FSlots);
  for I := 0 to High(FSlots) do
    if SameText(FSlots[I].Folder, FClip.Folder) and (FSlots[I].Name = FClip.Name) then
      Result := I;
  StoreCurrent;
  if FClipCut then
    FHasClip := False;
end;

procedure TSortFolders.AddRecent(const AFolder: string);
var
  F: string;
  I: Integer;
begin
  F := ExcludeTrailingPathDelimiter(Trim(AFolder));
  if F = '' then
    Exit;
  for I := FRecent.Count - 1 downto 0 do
    if SameText(FRecent[I], F) then
      FRecent.Delete(I);
  FRecent.Insert(0, F);
  while FRecent.Count > MaxRecentFolders do
    FRecent.Delete(FRecent.Count - 1);
end;

function TSortFolders.Recent: TStrings;
begin
  Result := FRecent;
end;

procedure TSortFolders.Assign(ASource: TSortFolders);
var
  I: Integer;
begin
  SetLength(FLists, Length(ASource.FLists));
  for I := 0 to High(FLists) do
    FLists[I] := Copy(ASource.FLists[I], 0, Length(ASource.FLists[I]));
  FSlots := Copy(ASource.FSlots, 0, Length(ASource.FSlots));
  FDynamic := Copy(ASource.FDynamic, 0, Length(ASource.FDynamic));
  SyncDynamic;
  FUsed.Assign(ASource.FUsed);
  FCurrent := ASource.FCurrent;
  FRapid := ASource.FRapid;
  FRecent.Assign(ASource.FRecent);
end;

procedure TSortFolders.Clear;
begin
  FHasClip := False;
  SetLength(FSlots, 0);
  SetLength(FLists, 1);
  FLists[0] := nil;
  FDynamic := nil;
  SyncDynamic;
  FUsed.Clear;
  FCurrent := 0;
  FRapid := False;
  FRecent.Clear;
end;

procedure TSortFolders.ReadSlots(AIni: TCustomIniFile; const ASection: string;
  out ASlots: TSortSlots);
var
  I: Integer;
  F, Key: string;
begin
  ASlots := nil;
  { Slots are numbered 1..n without gaps when MView writes them; a gap
    left by hand is skipped over. }
  for I := 1 to MaxSortSlots do
  begin
    Key := 'Slot' + IntToStr(I);
    F := ExcludeTrailingPathDelimiter(Trim(AIni.ReadString(ASection, Key + 'Folder', '')));
    if F = '' then
      Continue;
    SetLength(ASlots, Length(ASlots) + 1);
    with ASlots[High(ASlots)] do
    begin
      Folder := F;
      Name := Trim(AIni.ReadString(ASection, Key + 'Name', ''));
      if Name = '' then
        Name := FolderDisplayName(F);
      Color := ParseSlotColor(AIni.ReadString(ASection, Key + 'Color', ''),
        TSlotColor((Length(ASlots) - 1) mod (Ord(High(TSlotColor)) + 1)));
      Icon := Trim(AIni.ReadString(ASection, Key + 'Icon', ''));
      Pinned := AIni.ReadBool(ASection, Key + 'Pinned', False);
    end;
  end;
  { Pinned ones on top (also when edited by hand). }
  PinnedFirst(ASlots);
end;

procedure TSortFolders.LoadFromIni(AIni: TCustomIniFile);
var
  I, N: Integer;
  F: string;
  List: TSortSlots;
begin
  FRapid := False;
  FHasClip := False;
  FRecent.Clear;
  FUsed.Clear;
  FLists := nil;
  FDynamic := nil;
  { [DirList1], [DirList2], ... (Day 27); before: the slots in [Sort]. }
  for N := 1 to MaxSortLists do
  begin
    if not AIni.SectionExists(ListSectionPrefix + IntToStr(N)) then
      Continue;
    ReadSlots(AIni, ListSectionPrefix + IntToStr(N), List);
    if Length(List) > 0 then
    begin
      SetLength(FLists, Length(FLists) + 1);
      FLists[High(FLists)] := List;
      SetLength(FDynamic, Length(FLists));
      FDynamic[High(FDynamic)] := AIni.ReadBool(ListSectionPrefix + IntToStr(N), KEY_DYNAMIC, False);
    end;
  end;
  if Length(FLists) = 0 then
  begin
    SetLength(FLists, 1);
    ReadSlots(AIni, SortSection, FLists[0]);
  end;
  SyncDynamic;
  FCurrent := EnsureRange(AIni.ReadInteger(SortSection, KEY_LIST, 1) - 1, 0, High(FLists));
  FSlots := Copy(FLists[FCurrent], 0, Length(FLists[FCurrent]));
  for I := 1 to MaxRecentFolders do
  begin
    F := ExcludeTrailingPathDelimiter(Trim(AIni.ReadString(SortSection, 'Recent' + IntToStr(I), '')));
    if (F <> '') and (FRecent.IndexOf(F) < 0) then
      FRecent.Add(F);
  end;
end;

procedure TSortFolders.WriteSlots(AIni: TCustomIniFile; const ASection: string;
  const ASlots: TSortSlots);
var
  I: Integer;
  Key: string;
begin
  { Keys of slots that no longer exist go. }
  for I := Length(ASlots) + 1 to MaxSortSlots do
  begin
    Key := 'Slot' + IntToStr(I);
    if AIni.ValueExists(ASection, Key + 'Folder') then
    begin
      AIni.DeleteKey(ASection, Key + 'Folder');
      AIni.DeleteKey(ASection, Key + 'Name');
      AIni.DeleteKey(ASection, Key + 'Color');
      AIni.DeleteKey(ASection, Key + 'Icon');
      AIni.DeleteKey(ASection, Key + 'Pinned');
    end;
  end;
  for I := 0 to High(ASlots) do
  begin
    Key := 'Slot' + IntToStr(I + 1);
    AIni.WriteString(ASection, Key + 'Folder', ASlots[I].Folder);
    AIni.WriteString(ASection, Key + 'Name', ASlots[I].Name);
    AIni.WriteString(ASection, Key + 'Color', ColorNames[ASlots[I].Color]);
    AIni.WriteString(ASection, Key + 'Icon', ASlots[I].Icon);
    if ASlots[I].Pinned then
      AIni.WriteBool(ASection, Key + 'Pinned', True)
    else if AIni.ValueExists(ASection, Key + 'Pinned') then
      AIni.DeleteKey(ASection, Key + 'Pinned');
  end;
end;

procedure TSortFolders.SaveToIni(AIni: TCustomIniFile);
var
  I, N, Current: Integer;
  NoSlots: TSortSlots;
begin
  StoreCurrent;
  { The slots of the old layout in [Sort] go (now [DirList1]). }
  NoSlots := nil;
  WriteSlots(AIni, SortSection, NoSlots);
  { The occupied lists, numbered without gaps; an empty one is not kept. }
  N := 0;
  Current := 0;
  for I := 0 to High(FLists) do
  begin
    if Length(FLists[I]) = 0 then
      Continue;
    Inc(N);
    if I <= FCurrent then
      Current := N;
    AIni.EraseSection(ListSectionPrefix + IntToStr(N));
    WriteSlots(AIni, ListSectionPrefix + IntToStr(N), FLists[I]);
    if (I <= High(FDynamic)) and FDynamic[I] then
      AIni.WriteBool(ListSectionPrefix + IntToStr(N), KEY_DYNAMIC, True);
  end;
  for I := N + 1 to MaxSortLists do
    if AIni.SectionExists(ListSectionPrefix + IntToStr(I)) then
      AIni.EraseSection(ListSectionPrefix + IntToStr(I));
  AIni.WriteInteger(SortSection, KEY_LIST, Max(1, Current));
  for I := 1 to MaxRecentFolders do
    if I <= FRecent.Count then
      AIni.WriteString(SortSection, 'Recent' + IntToStr(I), FRecent[I - 1])
    else if AIni.ValueExists(SortSection, 'Recent' + IntToStr(I)) then
      AIni.DeleteKey(SortSection, 'Recent' + IntToStr(I));
end;

function IconBaseName(const AFolder: string): string;
var
  I: Integer;
begin
  Result := FolderDisplayName(AFolder);
  for I := Length(Result) downto 1 do
    if Result[I] in ['\', '/', ':', '*', '?', '"', '<', '>', '|'] then
      Delete(Result, I, 1);
  Result := Trim(Result);
  if Result = '' then
    Result := 'icon';
end;

end.
