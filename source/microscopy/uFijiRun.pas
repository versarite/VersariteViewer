unit uFijiRun;

{
  Unit: uFijiRun

  Purpose
  -------
  "Run in Fiji ..." (Day 28, user: "do most of the work in the Lab and
  use Fiji remotely"): a right-click entry. A small dialog offers a list
  of favourite Fiji commands, each an ImageJ macro line (as Fiji's
  Plugins > Macros > Record writes them: run("Gaussian Blur...",
  "sigma=2");), editable before it runs, and new ones can be remembered
  or forgotten. On Run:
  - the image's own pixels (as "Save original to Fiji": no display
    filter, mirror or turn) are written as a calibrated TIFF
    (uFijiLink's WriteFijiTiff);
  - the running Fiji (the link, uFijiChannel) opens it in batch mode
    (no Fiji window), runs the macro, makes the result RGB if it isn't
    (the Lab shows 8-bit RGB), saves it as a TIFF and closes only the
    images it made (the user's own images in Fiji stay);
  - meanwhile the Lab stays usable (the wait is on a thread); then the
    result is shown as a new image (uExtensions' ShowImageInViewer, as a
    crop: "Save image" writes it), its scale the parent's, adjusted for
    a changed size (NoteDerivedImage).
  No Fiji listening: it is started (StartFijiForLink); the command is
  given again once it is up.
  The favourites: [FijiCommands] in the edition's ini, Name=macro (the
  first time, a few useful ones are written there).

  Does NOT
  --------
  - Ask Fiji's own parameter dialogs (the macro carries the
    parameters); a macro that makes Fiji ask or fails shows Fiji's
    dialog there, and the Lab waits for it.
  - Send the marks (ROIs: later).
  - Run two commands at once.

  Threads
  -------
  UI thread; the wait for Fiji's answer on a thread of its own
  (TFijiRunThread, Synchronize for the result).

  Uses (MView units)
  ------------------
  implementation: uExtensions, uImageScale, uFijiLink, uFijiChannel,
                  uFijiFind
  Libraries:      Classes, SysUtils, Math, IniFiles, Forms, Controls,
                  StdCtrls, ExtCtrls, Dialogs, Graphics, BGRABitmap

  Used by
  -------
  VersariteImageLab.lpr (its uses list, after uFijiLink: the menu entry
  comes after the "Save ... to Fiji" ones)
}

{$mode ObjFPC}{$H+}

interface

{ The macro run for AInFile -> AOutFile with AUserMacro in between
  (for the test): batch mode, the result RGB, only its own images
  closed; it returns 'done' or 'no image'. }
function BuildFijiRunMacro(const AInFile, AOutFile, AUserMacro: string): string;

implementation

uses
  Classes,
  SysUtils,
  Math,
  IniFiles,
  Forms,
  Controls,
  StdCtrls,
  ExtCtrls,
  Dialogs,
  Graphics,
  LCLType,
  BGRABitmap,
  uExtensions,
  uImageScale,
  uFijiLink,
  uFijiChannel,
  uFijiFind;

const
  CommandsSection = 'FijiCommands';
  RunTimeoutMs = 30 * 60 * 1000;   { a long deconvolution may take a while }

type
  TFijiCommand = record
    Name: string;
    Macro: string;
  end;
  TFijiCommands = array of TFijiCommand;

  TFijiRunThread = class(TThread)
  private
    FCommand: string;
    FAnswer: TFijiAnswer;
    FReply: string;
    procedure Finished;
  protected
    procedure Execute; override;
  end;

var
  Running: Boolean = False;
  { What is under way: shown in the result's name and title. }
  RunName, RunOutFile, RunParentName, RunSourceName, RunNote: string;
  RunMacro: string;           { the user's command (its lines, for an error) }
  RunFullW, RunFullH: Integer;

{ ---- The macro ---- }

{ A path in an ImageJ macro string: forward slashes (Fiji takes them on
  Windows; no backslash escapes), a quote escaped. }
function MacroPath(const APath: string): string;
begin
  Result := StringReplace(StringReplace(APath, '\', '/', [rfReplaceAll]), '"', '\"',
    [rfReplaceAll]);
end;

const
  { The lines BuildFijiRunMacro puts before the user's command (an
    error's line number counts from the macro's first line). }
  MacroLinesBefore = 3;

function BuildFijiRunMacro(const AInFile, AOutFile, AUserMacro: string): string;
begin
  Result :=
    'setBatchMode(true);' + LineEnding +
    'open("' + MacroPath(AInFile) + '");' + LineEnding +
    { Images made from here on have this ID or a lower (more negative)
      one; the user's own images in Fiji have higher ones. }
    'versariteFirst = getImageID();' + LineEnding +
    AUserMacro + LineEnding +
    'if (nImages > 0) {' + LineEnding +
    '  if (bitDepth() != 24) run("RGB Color");' + LineEnding +
    '  saveAs("Tiff", "' + MacroPath(AOutFile) + '");' + LineEnding +
    '}' + LineEnding +
    'versariteSaved = File.exists("' + MacroPath(AOutFile) + '");' + LineEnding +
    'for (versariteI = nImages; versariteI >= 1; versariteI--) {' + LineEnding +
    '  selectImage(versariteI);' + LineEnding +
    '  if (getImageID() <= versariteFirst) close();' + LineEnding +
    '}' + LineEnding +
    'setBatchMode(false);' + LineEnding +
    'if (versariteSaved) return "done";' + LineEnding +
    'return "no image";';
end;

{ ---- The favourites ([FijiCommands]) ---- }

procedure DefaultCommands(out ACommands: TFijiCommands);

  procedure Add(const AName, AMacro: string);
  begin
    SetLength(ACommands, Length(ACommands) + 1);
    ACommands[High(ACommands)].Name := AName;
    ACommands[High(ACommands)].Macro := AMacro;
  end;

begin
  ACommands := nil;
  Add('Gaussian blur, sigma 2 px', 'run("Gaussian Blur...", "sigma=2");');
  Add('Median, radius 2 px', 'run("Median...", "radius=2");');
  Add('Despeckle', 'run("Despeckle");');
  Add('Unsharp mask, radius 2 px', 'run("Unsharp Mask...", "radius=2 mask=0.60");');
  Add('Subtract background, ball 50 px', 'run("Subtract Background...", "rolling=50");');
  Add('Enhance contrast, 0.35 % saturated', 'run("Enhance Contrast...", "saturated=0.35");');
  Add('Find edges', 'run("Find Edges");');
  Add('8-bit grey', 'run("8-bit");');
end;

procedure LoadCommands(out ACommands: TFijiCommands);
var
  Ini: TMemIniFile;
  Keys: TStringList;
  I: Integer;
begin
  ACommands := nil;
  Ini := OpenEditionIni;
  Keys := TStringList.Create;
  try
    if not Ini.SectionExists(CommandsSection) then
    begin
      { The first time: a few useful ones, written there to edit. }
      DefaultCommands(ACommands);
      for I := 0 to High(ACommands) do
        Ini.WriteString(CommandsSection, ACommands[I].Name, ACommands[I].Macro);
      SaveEditionIni(Ini);
      Exit;
    end;
    Ini.ReadSection(CommandsSection, Keys);
    for I := 0 to Keys.Count - 1 do
    begin
      SetLength(ACommands, Length(ACommands) + 1);
      ACommands[High(ACommands)].Name := Keys[I];
      ACommands[High(ACommands)].Macro := Ini.ReadString(CommandsSection, Keys[I], '');
    end;
  finally
    Keys.Free;
    Ini.Free;
  end;
end;

procedure SaveCommands(const ACommands: TFijiCommands);
var
  Ini: TMemIniFile;
  I: Integer;
begin
  Ini := OpenEditionIni;
  try
    Ini.EraseSection(CommandsSection);
    for I := 0 to High(ACommands) do
      Ini.WriteString(CommandsSection, ACommands[I].Name, ACommands[I].Macro);
    { An empty list stays empty (not the defaults again). }
    if Length(ACommands) = 0 then
      Ini.WriteString(CommandsSection, '', '');
    SaveEditionIni(Ini);
  finally
    Ini.Free;
  end;
end;

{ One line for the ini: the macro's lines joined (statements end in ;). }
function OneLine(const AText: string): string;
begin
  Result := Trim(StringReplace(StringReplace(StringReplace(AText, #13#10, ' ', [rfReplaceAll]),
    #10, ' ', [rfReplaceAll]), #13, ' ', [rfReplaceAll]));
end;

{ ---- The dialog ---- }

type
  TRunDialog = class(TForm)
  private
    FList: TListBox;
    FMacro: TMemo;
    FCommands: TFijiCommands;
    procedure ListClick(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
    procedure RememberClick(Sender: TObject);
    procedure ForgetClick(Sender: TObject);
    procedure FillList;
  public
    constructor CreateDialog;
    function ChosenName: string;
    function ChosenMacro: string;
  end;

constructor TRunDialog.CreateDialog;
var
  LTop, LInfo: TLabel;
  LBottom, LRight, LBox: TPanel;
  B: TButton;
begin
  inherited CreateNew(nil);
  Caption := 'Run in Fiji';
  Position := poScreenCenter;
  Width := 640;
  Height := 380;
  BorderIcons := [biSystemMenu];

  LTop := TLabel.Create(Self);
  LTop.Parent := Self;
  LTop.Align := alTop;
  LTop.Top := 0;
  LTop.BorderSpacing.Around := 8;
  LTop.WordWrap := True;
  LTop.Caption := 'Runs on the image''s own pixels in the Fiji that is open, without Fiji''s '
    + 'windows; the result comes back here as a new image.';

  LBottom := TPanel.Create(Self);
  LBottom.Parent := Self;
  LBottom.Align := alBottom;
  LBottom.Height := 44;
  LBottom.BevelOuter := bvNone;
  { Run / Cancel on the right: a panel of their own (laid out with the
    form, not at creation). }
  LRight := TPanel.Create(Self);
  LRight.Parent := LBottom;
  LRight.Align := alRight;
  LRight.Width := 190;
  LRight.BevelOuter := bvNone;

  B := TButton.Create(Self);
  B.Parent := LBottom;
  B.Caption := 'Remember ...';
  B.SetBounds(8, 8, 110, 28);
  B.OnClick := @RememberClick;
  B := TButton.Create(Self);
  B.Parent := LBottom;
  B.Caption := 'Forget';
  B.SetBounds(124, 8, 80, 28);
  B.OnClick := @ForgetClick;
  B := TButton.Create(Self);
  B.Parent := LRight;
  B.Caption := 'Run';
  B.SetBounds(6, 8, 84, 28);
  B.ModalResult := mrOk;
  B.Default := True;
  B := TButton.Create(Self);
  B.Parent := LRight;
  B.Caption := 'Cancel';
  B.SetBounds(98, 8, 84, 28);
  B.ModalResult := mrCancel;
  B.Cancel := True;

  FList := TListBox.Create(Self);
  FList.Parent := Self;
  FList.Align := alLeft;
  FList.Width := 250;
  FList.BorderSpacing.Left := 8;
  FList.BorderSpacing.Bottom := 4;
  FList.OnClick := @ListClick;
  FList.OnDblClick := @ListDblClick;

  { The macro and its caption, right of the list. }
  LBox := TPanel.Create(Self);
  LBox.Parent := Self;
  LBox.Align := alClient;
  LBox.BevelOuter := bvNone;

  LInfo := TLabel.Create(Self);
  LInfo.Parent := LBox;
  LInfo.Align := alTop;
  LInfo.BorderSpacing.Left := 8;
  LInfo.BorderSpacing.Right := 8;
  LInfo.WordWrap := True;
  LInfo.Caption := 'ImageJ macro (edit it, or paste a line from Fiji''s Plugins > Macros > '
    + 'Record):';

  FMacro := TMemo.Create(Self);
  FMacro.Parent := LBox;
  FMacro.Align := alClient;
  FMacro.BorderSpacing.Around := 8;
  FMacro.BorderSpacing.Top := 4;
  FMacro.ScrollBars := ssAutoBoth;
  FMacro.WordWrap := False;
  FMacro.Font.Name := 'Consolas';
  FMacro.Font.Size := 10;

  LoadCommands(FCommands);
  FillList;
  if FList.Items.Count > 0 then
  begin
    FList.ItemIndex := 0;
    ListClick(nil);
  end;
end;

procedure TRunDialog.FillList;
var
  I: Integer;
begin
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for I := 0 to High(FCommands) do
      if FCommands[I].Name <> '' then
        FList.Items.Add(FCommands[I].Name);
  finally
    FList.Items.EndUpdate;
  end;
end;

procedure TRunDialog.ListClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to High(FCommands) do
    if (FList.ItemIndex >= 0) and (FCommands[I].Name = FList.Items[FList.ItemIndex]) then
      FMacro.Text := FCommands[I].Macro;
end;

procedure TRunDialog.ListDblClick(Sender: TObject);
begin
  ListClick(nil);
  ModalResult := mrOk;
end;

procedure TRunDialog.RememberClick(Sender: TObject);
var
  LName: string;
  I: Integer;
begin
  if OneLine(FMacro.Text) = '' then
    Exit;
  LName := ChosenName;
  if not InputQuery('Remember the command', 'Its name in the list:', LName) then
    Exit;
  LName := Trim(StringReplace(StringReplace(LName, '=', '-', [rfReplaceAll]), ']', ')',
    [rfReplaceAll]));
  if LName = '' then
    Exit;
  for I := 0 to High(FCommands) do
    if SameText(FCommands[I].Name, LName) then
    begin
      FCommands[I].Macro := OneLine(FMacro.Text);
      SaveCommands(FCommands);
      FillList;
      FList.ItemIndex := FList.Items.IndexOf(FCommands[I].Name);
      Exit;
    end;
  SetLength(FCommands, Length(FCommands) + 1);
  FCommands[High(FCommands)].Name := LName;
  FCommands[High(FCommands)].Macro := OneLine(FMacro.Text);
  SaveCommands(FCommands);
  FillList;
  FList.ItemIndex := FList.Items.IndexOf(LName);
end;

procedure TRunDialog.ForgetClick(Sender: TObject);
var
  I, J: Integer;
begin
  if FList.ItemIndex < 0 then
    Exit;
  for I := 0 to High(FCommands) do
    if FCommands[I].Name = FList.Items[FList.ItemIndex] then
    begin
      for J := I to High(FCommands) - 1 do
        FCommands[J] := FCommands[J + 1];
      SetLength(FCommands, Length(FCommands) - 1);
      Break;
    end;
  SaveCommands(FCommands);
  FillList;
end;

{ The list's name when the macro is still that entry's, else a short
  form of the macro itself. }
function TRunDialog.ChosenName: string;
var
  I: Integer;
begin
  if FList.ItemIndex >= 0 then
    for I := 0 to High(FCommands) do
      if (FCommands[I].Name = FList.Items[FList.ItemIndex])
        and (OneLine(FCommands[I].Macro) = OneLine(FMacro.Text)) then
        Exit(FCommands[I].Name);
  Result := OneLine(FMacro.Text);
  if Length(Result) > 40 then
    Result := Copy(Result, 1, 38) + '...';
end;

function TRunDialog.ChosenMacro: string;
begin
  Result := Trim(FMacro.Text);
end;

{ ---- Running it ---- }

procedure TFijiRunThread.Execute;
begin
  FAnswer := FijiSend(FCommand, FReply, RunTimeoutMs);
  Synchronize(@Finished);
end;

{ A name part from a command's name: letters and digits, '-' between. }
function Slug(const AText: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(AText) do
    if AText[I] in ['A'..'Z', 'a'..'z', '0'..'9'] then
      Result := Result + LowerCase(AText[I])
    else if (Result <> '') and (Result[Length(Result)] <> '-') then
      Result := Result + '-';
  while (Result <> '') and (Result[Length(Result)] = '-') do
    Delete(Result, Length(Result), 1);
  if Length(Result) > 30 then
    Result := Copy(Result, 1, 30);
  if Result = '' then
    Result := 'fiji';
end;

{ Day 29 (user): the macro's error shown in the Lab - ImageJ's message,
  the line of the command it was in, what the macro wrote to the Log
  (the link script; an older one says only "macro aborted"). }
procedure ShowRunError(const AReply: string);
var
  Line, UserLine: Integer;
  Why, First, Text: string;
  Lines: TStringList;
begin
  FijiErrorParts(AReply, Line, Why);
  if Why = '' then
    Why := 'the command stopped';
  First := Why;
  if Pos(LineEnding, First) > 0 then
    First := Copy(First, 1, Pos(LineEnding, First) - 1);
  if (Line = 0) and (Pos('aborted', Why) > 0) then
  begin
    { The link script of 1.1: the reason is in Fiji's own message. }
    ViewerNote('Fiji: the command stopped - see Fiji''s message (restart Fiji once for the '
      + 'messages in the Lab)', 8000);
    Exit;
  end;
  ViewerNote('Fiji: ' + First, 8000);
  Text := 'Fiji could not run "' + RunName + '":' + LineEnding + LineEnding + Why;
  UserLine := Line - MacroLinesBefore;
  Lines := TStringList.Create;
  try
    Lines.Text := RunMacro;
    if (Line > 0) and (UserLine >= 1) and (UserLine <= Lines.Count) then
      Text := Text + LineEnding + LineEnding + Format('In line %d of the command:', [UserLine])
        + LineEnding + '    ' + Trim(Lines[UserLine - 1])
    else if Line > 0 then
      Text := Text + LineEnding + LineEnding + '(while the result was saved for the Lab)';
  finally
    Lines.Free;
  end;
  Text := Text + LineEnding + LineEnding + 'The image in the Lab is unchanged.';
  Application.MessageBox(PChar(Text), 'Run in Fiji', MB_OK or MB_ICONWARNING);
end;

{ UI thread: Fiji answered (or the wait ended). }
procedure TFijiRunThread.Finished;
var
  Bmp: TBGRABitmap;
  NewName, Title: string;
begin
  Running := False;
  case FAnswer of
    faOk:
      if Trim(FReply) <> 'done' then
      begin
        ViewerNote('Fiji: the command left no image (' + Trim(FReply) + ')', 6000);
        Exit;
      end;
    faError:
      begin
        ShowRunError(FReply);
        Exit;
      end;
  else
    ViewerNote('Fiji: the link went away', 6000);
    Exit;
  end;
  try
    Bmp := TBGRABitmap.Create(RunOutFile);
  except
    on E: Exception do
    begin
      ViewerNote('Fiji''s result could not be read (' + E.Message + ')', 8000);
      Exit;
    end;
  end;
  if (Bmp.Width <= 0) or (Bmp.Height <= 0) then
  begin
    Bmp.Free;
    ViewerNote('Fiji''s result is empty', 6000);
    Exit;
  end;
  NewName := RunSourceName + '_' + Slug(RunName);
  { The scale is the parent's, over the new size (a command may have
    made it smaller or larger). }
  if (RunFullW > 0) and (RunFullH > 0) then
    NoteDerivedImage(NewName, RunParentName, 'fiji', RunFullW, RunFullH,
      RunFullW / Bmp.Width, RunFullH / Bmp.Height, 0);
  Title := 'Fiji: ' + RunName + ' of ' + RunSourceName + RunNote;
  if not ShowImageInViewer(Bmp, NewName, Title, NewName) then
    ViewerNote('Fiji''s result is in ' + RunOutFile, 8000)
  else
    ViewerNote('from Fiji: ' + RunName, 4000);
end;

procedure RunInFiji(AViewer: TObject);
var
  Dialog: TRunDialog;
  Name, Macro, ImageName, SourceName, Folder, Err, InFile, Note: string;
  Bmp: TBGRABitmap;
  FullW, FullH: Integer;
  Quick: Boolean;
  Scale: TImageScale;
  UmX, UmY: Double;
  T: TFijiRunThread;
begin
  if Running then
  begin
    ViewerNote('Fiji is still working on the last command', 4000);
    Exit;
  end;
  { Fiji first: without it, it is started (the command again once up). }
  if not FijiListening then
  begin
    StartFijiForLink(Note);
    ViewerNote(Note, 6000);
    Exit;
  end;

  NoteMenuOpen(True);
  Dialog := TRunDialog.CreateDialog;
  try
    if Dialog.ShowModal <> mrOk then
      Exit;
    Name := Dialog.ChosenName;
    Macro := Dialog.ChosenMacro;
  finally
    Dialog.Free;
    NoteMenuOpen(False);
  end;
  if Trim(Macro) = '' then
    Exit;

  if not GetImagePixels(Bmp, ImageName, SourceName, Folder, Err, FullW, FullH, Quick) then
  begin
    ViewerNote('Run in Fiji: ' + Err, 4000);
    Exit;
  end;
  try
    UmX := 0;
    UmY := 0;
    if ScaleFor(ImageName, FullW, FullH, Scale) and (Scale.UmPerPixelX > 0)
      and (Scale.UmPerPixelY > 0) then
    begin
      UmX := Scale.UmPerPixelX * FullW / Bmp.Width;
      UmY := Scale.UmPerPixelY * FullH / Bmp.Height;
    end;
    if not WriteFijiTiff(Bmp, SourceName + '_in', UmX, UmY, InFile, Err) then
    begin
      ViewerNote('Run in Fiji: the TIFF could not be written (' + Err + ')', 6000);
      Exit;
    end;
    Note := '';
    if Quick or (Bmp.Width < FullW) then
      Note := Format('  (from a %d x %d copy: the full image was not loaded)', [Bmp.Width, Bmp.Height]);
  finally
    Bmp.Free;
  end;

  RunName := Name;
  RunParentName := ImageName;
  RunSourceName := SourceName;
  RunFullW := FullW;
  RunFullH := FullH;
  RunNote := Note;
  RunMacro := Macro;
  RunOutFile := FijiTempFolder + FijiTiffName(SourceName + '_fiji',
    FormatDateTime('_hhnnss_zzz', Now));
  Running := True;
  T := TFijiRunThread.Create(True);
  T.FreeOnTerminate := True;
  T.FCommand := 'EVAL ' + FijiEscape(BuildFijiRunMacro(InFile, RunOutFile, Macro));
  T.Start;
  ViewerNote('Fiji: ' + Name + ' ...', 60000);
end;

function RunInFijiEnabled(AViewer: TObject): Boolean;
begin
  Result := (ShownImageName <> '') and not Running;
end;

initialization
  RegisterMenuEntry('Run in Fiji ...', @RunInFiji, @RunInFijiEnabled, nil);
end.
