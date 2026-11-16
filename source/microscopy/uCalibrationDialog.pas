unit uCalibrationDialog;

{
  Unit: uCalibrationDialog

  Purpose
  -------
  The dialog after a reference measurement (M3b, Day 25; spec
  "Microscopy edition" §7.1): the measured line's length in pixels is
  known; the user types the known length (the one place the keyboard is
  used), confirms or edits the name, microscope and objective (filled
  in from the file when it says), "Confocal" and the zoom. When the
  image has a scale of its own, its length for the same line is shown
  and pre-filled: OK then simply keeps the file's scale as a record.

  Owns
  ----
  The form while it is open (built in code, no .lfm).

  Does NOT
  --------
  - Save the record (uMeasureLine does: calibrations.ini, chosen).

  Threads
  -------
  UI thread.

  Uses (MView units)
  ------------------
  interface:      uCalibrations
  implementation: uImageScale (ConfocalMode)
  Libraries:      Classes, SysUtils, Math, Controls, Forms, StdCtrls,
                  Graphics

  Used by
  -------
  uMeasureLine
}

{$mode ObjFPC}{$H+}

interface

uses
  uCalibrations;

{ True and ACal filled in when the user confirms. AMeasuredPx: the
  line's length in image pixels; AImageWidth: the image's width;
  AMicroscope / AObjective / AZoom: from the file ('' / 0 = unknown);
  AFileMicrons > 0: the same line by the file's own scale (AFileSource
  says where it is from). }
function AskReferenceCalibration(AMeasuredPx: Double; AImageWidth: Integer;
  const AMicroscope, AObjective: string; AZoom: Double;
  AFileMicrons: Double; const AFileSource: string; out ACal: TCalibration): Boolean;

implementation

uses
  Classes,
  SysUtils,
  Math,
  Controls,
  Forms,
  StdCtrls,
  Graphics,
  uImageScale;

type
  TCalibrationForm = class(TForm)
  private
    FLengthEdit, FNameEdit, FMicroscopeEdit, FObjectiveEdit, FZoomEdit, FNoteEdit: TEdit;
    FConfocalBox: TCheckBox;
    FZoomLabel, FErrorLabel: TLabel;
    procedure HandleConfocalClick(Sender: TObject);
    procedure HandleCloseQuery(Sender: TObject; var ACanClose: Boolean);
  public
    Microns, Zoom: Double;
  end;

var
  Dot: TFormatSettings;

{ A number typed by hand: '.' or ','. }
function ParseNumber(const AText: string; out AValue: Double): Boolean;
begin
  Result := TryStrToFloat(StringReplace(Trim(AText), ',', '.', []), AValue, Dot);
end;

procedure TCalibrationForm.HandleConfocalClick(Sender: TObject);
begin
  FZoomEdit.Enabled := FConfocalBox.Checked;
  FZoomLabel.Enabled := FConfocalBox.Checked;
end;

procedure TCalibrationForm.HandleCloseQuery(Sender: TObject; var ACanClose: Boolean);
begin
  if ModalResult <> mrOK then
    Exit;
  ACanClose := False;
  if not ParseNumber(FLengthEdit.Text, Microns) or (Microns <= 0) then
  begin
    FErrorLabel.Caption := 'Type the known length in µm (a number above 0).';
    FLengthEdit.SetFocus;
    Exit;
  end;
  if Trim(FNameEdit.Text) = '' then
  begin
    FErrorLabel.Caption := 'Give the calibration a name.';
    FNameEdit.SetFocus;
    Exit;
  end;
  Zoom := 0;
  if FConfocalBox.Checked and (Trim(FZoomEdit.Text) <> '')
    and (not ParseNumber(FZoomEdit.Text, Zoom) or (Zoom < 0)) then
  begin
    FErrorLabel.Caption := 'The zoom is a number (empty: not known).';
    FZoomEdit.SetFocus;
    Exit;
  end;
  ACanClose := True;
end;

function AskReferenceCalibration(AMeasuredPx: Double; AImageWidth: Integer;
  const AMicroscope, AObjective: string; AZoom: Double;
  AFileMicrons: Double; const AFileSource: string; out ACal: TCalibration): Boolean;
var
  Form: TCalibrationForm;
  S, Gap, Y, LabelW, EditW: Integer;
  Info, RowLabel: TLabel;
  Lines: Integer;
  OkButton, CancelButton: TButton;

  function Px(AValue: Integer): Integer;
  begin
    Result := Round(AValue * S / 100);
  end;

  function AddRow(const ACaption, AText: string; out ALabel: TLabel): TEdit;
  var
    Lbl: TLabel;
  begin
    Lbl := TLabel.Create(Form);
    ALabel := Lbl;
    Lbl.Parent := Form;
    Lbl.Caption := ACaption;
    Lbl.Left := Gap;
    Lbl.Top := Y + Px(4);
    Result := TEdit.Create(Form);
    Result.Parent := Form;
    Result.Left := Gap + LabelW;
    Result.Top := Y;
    Result.Width := EditW;
    Result.Text := AText;
    Inc(Y, Result.Height + Px(8));
  end;

begin
  ACal := Default(TCalibration);
  Result := False;
  S := Max(100, Round(Screen.PixelsPerInch / 96 * 100));
  Gap := Px(12);
  LabelW := Px(150);
  EditW := Px(340);
  Form := TCalibrationForm.CreateNew(nil);
  try
    Form.Caption := 'Reference measurement';
    Form.BorderStyle := bsDialog;
    Form.Position := poMainFormCenter;
    Form.ClientWidth := Gap * 2 + LabelW + EditW;
    Form.OnCloseQuery := @Form.HandleCloseQuery;
    Y := Gap;

    Info := TLabel.Create(Form);
    Info.Parent := Form;
    Info.Left := Gap;
    Info.Top := Y;
    Info.WordWrap := False;
    Info.AutoSize := False;
    Info.Width := LabelW + EditW;
    Lines := 2;
    Info.Caption := Format('The line is %s px long; the calibration holds for an image %d px wide.',
      [FormatFloat('0.0', AMeasuredPx), AImageWidth]);
    if AFileMicrons > 0 then
    begin
      Info.Caption := Info.Caption + LineEnding + 'By the scale of ' + AFileSource + ':'
        + LineEnding + FormatFloat('0.###', AFileMicrons) + ' µm (filled in below).';
      Inc(Lines, 2);
    end;
    Info.Caption := Info.Caption + LineEnding + 'How long is it really?';
    Info.Height := Lines * Px(18);
    Inc(Y, Info.Height + Px(12));

    if AFileMicrons > 0 then
      Form.FLengthEdit := AddRow('Known length (µm):', FormatFloat('0.###', AFileMicrons), RowLabel)
    else
      Form.FLengthEdit := AddRow('Known length (µm):', '', RowLabel);
    if AObjective <> '' then
      Form.FNameEdit := AddRow('Name:', Trim(Trim(AMicroscope) + ' ' + AObjective), RowLabel)
    else
      Form.FNameEdit := AddRow('Name:', '', RowLabel);
    Form.FMicroscopeEdit := AddRow('Microscope:', AMicroscope, RowLabel);
    Form.FObjectiveEdit := AddRow('Objective:', AObjective, RowLabel);

    Form.FConfocalBox := TCheckBox.Create(Form);
    Form.FConfocalBox.Parent := Form;
    Form.FConfocalBox.Left := Gap + LabelW;
    Form.FConfocalBox.Top := Y;
    Form.FConfocalBox.Caption := 'Confocal (scales with image width and zoom)';
    Form.FConfocalBox.Checked := ConfocalMode or (AZoom > 0);
    Form.FConfocalBox.OnClick := @Form.HandleConfocalClick;
    Inc(Y, Form.FConfocalBox.Height + Px(8));

    if AZoom > 0 then
      Form.FZoomEdit := AddRow('Zoom:', FormatFloat('0.###', AZoom), RowLabel)
    else
      Form.FZoomEdit := AddRow('Zoom:', '', RowLabel);
    Form.FZoomLabel := RowLabel;     { enabled with "Confocal" }
    Form.FNoteEdit := AddRow('Note:', 'stage micrometer', RowLabel);
    Form.HandleConfocalClick(nil);

    Form.FErrorLabel := TLabel.Create(Form);
    Form.FErrorLabel.Parent := Form;
    Form.FErrorLabel.Left := Gap;
    Form.FErrorLabel.Top := Y;
    Form.FErrorLabel.Font.Color := clRed;
    Form.FErrorLabel.Caption := '';
    Inc(Y, Px(22));

    OkButton := TButton.Create(Form);
    OkButton.Parent := Form;
    OkButton.Caption := 'Save calibration';
    OkButton.ModalResult := mrOK;
    OkButton.Default := True;
    OkButton.Width := Px(130);
    OkButton.Top := Y;
    CancelButton := TButton.Create(Form);
    CancelButton.Parent := Form;
    CancelButton.Caption := 'Cancel';
    CancelButton.ModalResult := mrCancel;
    CancelButton.Cancel := True;
    CancelButton.Width := Px(90);
    CancelButton.Top := Y;
    CancelButton.Left := Form.ClientWidth - Gap - CancelButton.Width;
    OkButton.Left := CancelButton.Left - Px(8) - OkButton.Width;
    Form.ClientHeight := Y + OkButton.Height + Gap;
    Form.ActiveControl := Form.FLengthEdit;

    if Form.ShowModal <> mrOK then
      Exit;
    ACal.Name := Trim(Form.FNameEdit.Text);
    ACal.Microscope := Trim(Form.FMicroscopeEdit.Text);
    ACal.Objective := Trim(Form.FObjectiveEdit.Text);
    ACal.Confocal := Form.FConfocalBox.Checked;
    ACal.ReferenceMicrons := Form.Microns;
    ACal.ReferencePixels := AMeasuredPx;
    ACal.ReferenceWidth := AImageWidth;
    if ACal.Confocal then
      ACal.ReferenceZoom := Form.Zoom
    else
      ACal.ReferenceZoom := 0;
    ACal.Date := FormatDateTime('yyyy-mm-dd', Now);
    ACal.Note := Trim(Form.FNoteEdit.Text);
    SetConfocalMode(ACal.Confocal);
    Result := CalibrationValid(ACal);
  finally
    Form.Free;
  end;
end;

initialization
  Dot := DefaultFormatSettings;
  Dot.DecimalSeparator := '.';
end.
