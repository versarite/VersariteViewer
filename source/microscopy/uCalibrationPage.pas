unit uCalibrationPage;

{
  Unit: uCalibrationPage

  Purpose
  -------
  The "Calibrations" tab of the settings screen (M3b step 3, Day 25,
  user; spec "Microscopy edition" §7.1), plugged in as a settings page
  (uExtensions): the records of calibrations.ini listed - which one is
  in use, name, microscope, objective, confocal, value, date, note - and
  Use / None / Rename / Delete / Reload. Changes go to calibrations.ini
  at once (the file is the page's own, not the settings text's: the
  settings screen's Save is not needed).

  New calibrations are made in the viewer (reference measurement); this
  page only looks after them.

  Owns
  ----
  Its controls (made when the tab is first opened).

  Does NOT
  --------
  - Keep the list (uImageScale does: the same list the viewer uses).

  Threads
  -------
  UI thread.

  Uses (MView units)
  ------------------
  implementation: uExtensions, uCalibrations, uImageScale
  Libraries:      Classes, SysUtils, Controls, Graphics, StdCtrls, ExtCtrls,
                  ComCtrls, Dialogs

  Used by
  -------
  VersariteImageLab.lpr (its uses list only)
}

{$mode ObjFPC}{$H+}

interface

implementation

uses
  Classes,
  SysUtils,
  Controls,
  Graphics,
  StdCtrls,
  ExtCtrls,
  ComCtrls,
  Dialogs,
  uExtensions,
  uCalibrations,
  uImageScale;

type
  TCalibrationPage = class(TPanel)
  private
    FIntro: TLabel;
    FList: TListView;
    FBar: TPanel;
    FNote: TLabel;
    FNextLeft: Integer;
    function AddButton(const ACaption: string; AHandler: TNotifyEvent): TButton;
    function SelectedIndex: Integer;
    procedure Saved;
    procedure HandleUse(Sender: TObject);
    procedure HandleNone(Sender: TObject);
    procedure HandleRename(Sender: TObject);
    procedure HandleDelete(Sender: TObject);
    procedure HandleReload(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    { The list from Calibrations again; the selection kept by name. }
    procedure Fill;
  end;

constructor TCalibrationPage.Create(AOwner: TComponent);

  procedure AddColumn(const ACaption: string; AWidth: Integer);
  var
    Column: TListColumn;
  begin
    Column := FList.Columns.Add;
    Column.Caption := ACaption;
    Column.Width := AWidth;
  end;

begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';

  FIntro := TLabel.Create(Self);
  FIntro.Parent := Self;
  FIntro.Align := alTop;
  FIntro.BorderSpacing.Around := 8;
  FIntro.WordWrap := True;
  FIntro.Caption := 'Calibrations give images without a scale of their own (exported TIFFs, '
    + 'camera images) their µm. They are made in the viewer: a reference measurement over a '
    + 'known length (right-click menu "Reference measurement (calibrate)", or the "Scale" list '
    + 'at the bottom of the left panel). The one in use applies to every image without a scale '
    + 'from its file. Kept in ' + DefaultCalibrationFile + ' - copy that file to take them '
    + 'to another PC.';

  FBar := TPanel.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alBottom;
  FBar.BevelOuter := bvNone;
  FBar.Height := 48;
  FBar.Caption := '';
  { Left to right in the order they are made (as the settings screen's
    buttons: an increasing Left before alLeft). }
  AddButton('Use this one', @HandleUse);
  AddButton('Use none (pixels)', @HandleNone);
  AddButton('Rename ...', @HandleRename);
  AddButton('Delete', @HandleDelete);
  AddButton('Reload', @HandleReload);

  FNote := TLabel.Create(Self);
  FNote.Parent := FBar;
  FNote.Align := alClient;
  FNote.BorderSpacing.Left := 12;
  FNote.Layout := tlCenter;
  FNote.Caption := '';

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.BorderSpacing.Left := 8;
  FList.BorderSpacing.Right := 8;
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.OnDblClick := @HandleUse;
  AddColumn('In use', 60);
  AddColumn('Name', 200);
  AddColumn('Microscope', 130);
  AddColumn('Objective', 220);
  AddColumn('Confocal', 70);
  AddColumn('Value', 220);
  AddColumn('Date', 90);
  AddColumn('Note', 180);
end;

function TCalibrationPage.AddButton(const ACaption: string; AHandler: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := FBar;
  Result.Caption := ACaption;
  Result.AutoSize := True;
  Result.Left := FNextLeft;
  Result.Align := alLeft;
  Result.BorderSpacing.Around := 8;
  Result.OnClick := AHandler;
  Inc(FNextLeft, 1000);
end;

procedure TCalibrationPage.Fill;
var
  I, Keep: Integer;
  KeepName, Chosen: string;
  Item: TListItem;
  C: TCalibration;
begin
  { The selected row's name (the rows may no longer match the list:
    reloaded, or changed by the viewer). }
  KeepName := '';
  if (FList.Selected <> nil) and (FList.Selected.SubItems.Count > 0) then
    KeepName := FList.Selected.SubItems[0];
  Chosen := ChosenCalibration;
  Keep := -1;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for I := 0 to Calibrations.Count - 1 do
    begin
      C := Calibrations.Item(I);
      Item := FList.Items.Add;
      if SameText(C.Name, Chosen) then
        Item.Caption := 'yes'
      else
        Item.Caption := '';
      Item.SubItems.Add(C.Name);
      Item.SubItems.Add(C.Microscope);
      Item.SubItems.Add(C.Objective);
      if C.Confocal then
        Item.SubItems.Add('yes')
      else
        Item.SubItems.Add('no');
      Item.SubItems.Add(CalibrationValueText(C));
      Item.SubItems.Add(C.Date);
      Item.SubItems.Add(C.Note);
      if SameText(C.Name, KeepName) then
        Keep := I;
    end;
  finally
    FList.Items.EndUpdate;
  end;
  if Keep >= 0 then
    FList.ItemIndex := Keep;
  if Calibrations.Count = 0 then
    FNote.Caption := 'No calibrations yet: make one with a reference measurement in the viewer.'
  else if Chosen = '' then
    FNote.Caption := 'None in use: images without a scale of their own are measured in pixels.'
  else
    FNote.Caption := 'In use: ' + Chosen;
end;

{ The list's rows are the calibrations in their order. }
function TCalibrationPage.SelectedIndex: Integer;
begin
  Result := FList.ItemIndex;
  if (Result < 0) or (Result >= Calibrations.Count) then
    Result := -1;
end;

{ Written to calibrations.ini; the list and any µm on screen anew. }
procedure TCalibrationPage.Saved;
var
  Error: string;
begin
  if not SaveCalibrations(Error) then
    MessageDlg('Calibrations', 'calibrations.ini could not be written: ' + Error, mtWarning, [mbOK], 0);
  OverlayChanged(nil);
  Fill;
end;

procedure TCalibrationPage.HandleUse(Sender: TObject);
var
  Index: Integer;
begin
  Index := SelectedIndex;
  if Index < 0 then
    Exit;
  ChooseCalibration(Calibrations.Item(Index).Name);
  OverlayChanged(nil);
  Fill;
end;

procedure TCalibrationPage.HandleNone(Sender: TObject);
begin
  ChooseCalibration('');
  OverlayChanged(nil);
  Fill;
end;

procedure TCalibrationPage.HandleRename(Sender: TObject);
var
  Index: Integer;
  OldName, NewName: string;
  WasChosen: Boolean;
begin
  Index := SelectedIndex;
  if Index < 0 then
    Exit;
  OldName := Calibrations.Item(Index).Name;
  NewName := OldName;
  if not InputQuery('Rename calibration', 'New name:', NewName) then
    Exit;
  NewName := Trim(NewName);
  if (NewName = '') or (NewName = OldName) then
    Exit;
  if (Calibrations.IndexOfName(NewName) >= 0) and (Calibrations.IndexOfName(NewName) <> Index) then
  begin
    MessageDlg('Calibrations', 'There is a calibration of that name already.', mtInformation, [mbOK], 0);
    Exit;
  end;
  WasChosen := SameText(ChosenCalibration, OldName);
  Calibrations.Rename(Index, NewName);
  if WasChosen then
    ChooseCalibration(NewName);
  Saved;
end;

procedure TCalibrationPage.HandleDelete(Sender: TObject);
var
  Index: Integer;
  CalName: string;
begin
  Index := SelectedIndex;
  if Index < 0 then
    Exit;
  CalName := Calibrations.Item(Index).Name;
  if MessageDlg('Calibrations', 'Delete the calibration "' + CalName + '"?', mtConfirmation,
    [mbYes, mbNo], 0) <> mrYes then
    Exit;
  if SameText(ChosenCalibration, CalName) then
    ChooseCalibration('');
  Calibrations.Delete(Index);
  Saved;
end;

procedure TCalibrationPage.HandleReload(Sender: TObject);
begin
  ReloadCalibrations;
  OverlayChanged(nil);
  Fill;
end;

{ The settings page (uExtensions). }

function CreateCalibrationPage(AOwner: TComponent; AParent: TWinControl): TWinControl;
var
  Page: TCalibrationPage;
begin
  Page := TCalibrationPage.Create(AOwner);
  Page.Parent := AParent;
  Page.Align := alClient;
  Result := Page;
end;

procedure RefreshCalibrationPage(APage: TWinControl);
begin
  if APage is TCalibrationPage then
    TCalibrationPage(APage).Fill;
end;

initialization
  RegisterSettingsPage('Calibrations',
    'Calibrations for images without a scale of their own. Made by a reference measurement '
    + 'in the viewer; here: which one is in use, rename, delete.',
    @CreateCalibrationPage, @RefreshCalibrationPage);
end.
