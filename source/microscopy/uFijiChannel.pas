unit uFijiChannel;

{
  Unit: uFijiChannel

  Purpose
  -------
  The Lab's line to a running Fiji (1.1; spec "Microscopy edition" §9c):
  Fiji's own single-instance listener is not started by the 2025 Fiji
  launcher, so the Lab ships a small JavaScript script
  (fiji\Versarite_Lab_Link.js, installed in <Fiji>\scripts\Plugins\
  AutoRun\) that listens on 127.0.0.1:57317. This unit talks to it: one
  command line out, one reply line back.
  - PING          -> OK <ImageJ version>
  - OPEN <file>   -> OK <image title>
  - EVAL <macro>  -> OK <macro result>
                  -> ERR line=<n>; <why>  (the link of Day 29: ImageJ's
                     message, the line, what the macro wrote to the Log)
  - a failure     -> ERR <why>
  In EVAL text and replies a backslash is \\ and a line break \n
  (FijiEscape / FijiUnescape).

  Does NOT
  --------
  - Start Fiji or write the TIFF (uFijiLink).
  - Keep a connection open: one connection per command.

  Threads
  -------
  Any thread; no state. It blocks until Fiji answers (at most ATimeoutMs),
  a refused connection (no Fiji listening) returns at once.

  Uses (MView units)
  ------------------
  none
  Libraries:      Classes, SysUtils, ssockets (fcl-net)

  Used by
  -------
  uFijiLink
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils;

const
  FijiLinkPort = 57317;    // must match PORT in Versarite_Lab_Link.js
  FijiLinkHost = '127.0.0.1';

type
  TFijiAnswer = (
    faNoFiji,   // nobody listening (Fiji not running, or without the script)
    faOk,       // Fiji did it; the reply text after 'OK '
    faError     // Fiji answered with an error, or stopped answering
  );

{ Sends one command line (UTF-8) and waits for the reply line. AReply is
  the text after 'OK ' / 'ERR ' (unescaped), or why it failed. }
function FijiSend(const ACommand: string; out AReply: string;
  ATimeoutMs: Integer = 20000): TFijiAnswer;

{ A Fiji with the Lab's script running? (PING, short timeout.) }
function FijiListening: Boolean;

{ An EVAL's error reply (AReply as FijiSend gave it): 'line=12; why'
  -> ALine 12 (0 = not said: an older link script), AWhy the rest. }
procedure FijiErrorParts(const AReply: string; out ALine: Integer; out AWhy: string);

{ Macro text for EVAL, and replies: \ -> \\, line break -> \n. }
function FijiEscape(const S: string): string;
function FijiUnescape(const S: string): string;

implementation

uses
  ssockets;

function FijiEscape(const S: string): string;
begin
  Result := StringReplace(S, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
end;

function FijiUnescape(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    if (S[I] = '\') and (I < Length(S)) then
    begin
      if S[I + 1] = 'n' then
        Result := Result + LineEnding
      else
        Result := Result + S[I + 1];
      Inc(I, 2);
    end
    else
    begin
      Result := Result + S[I];
      Inc(I);
    end;
  end;
end;

{ The reply line, without its line end; False if the line did not come. }
function ReadReplyLine(AStream: TSocketStream; out ALine: string): Boolean;
var
  Buf: array[0..1023] of Byte;
  N, I: Integer;
  Got: RawByteString;
begin
  Got := '';
  ALine := '';
  repeat
    N := AStream.Read(Buf, SizeOf(Buf));
    if N <= 0 then
      Exit(False);
    for I := 0 to N - 1 do
    begin
      if Buf[I] = 10 then
      begin
        if (Got <> '') and (Got[Length(Got)] = #13) then
          SetLength(Got, Length(Got) - 1);
        SetCodePage(Got, CP_UTF8, False);
        ALine := string(Got);
        Exit(True);
      end;
      Got := Got + AnsiChar(Buf[I]);
    end;
  until False;
end;

function FijiSend(const ACommand: string; out AReply: string;
  ATimeoutMs: Integer): TFijiAnswer;
var
  Sock: TInetSocket;
  Line: UTF8String;
  Reply: string;
begin
  AReply := '';
  try
    Sock := TInetSocket.Create(FijiLinkHost, FijiLinkPort, 2000);
  except
    { Refused or no answer: no Fiji with the script. }
    Exit(faNoFiji);
  end;
  try
    try
      Sock.IOTimeout := ATimeoutMs;
      { UTF8String(): converts from the string's own code page, and leaves
        the Lab's UTF-8 strings as they are (UTF8Encode would encode them
        a second time: 'µ' -> 'Âµ'). }
      Line := UTF8String(StringReplace(StringReplace(ACommand, #13, ' ', [rfReplaceAll]),
        #10, ' ', [rfReplaceAll])) + #10;
      Sock.WriteBuffer(Line[1], Length(Line));
      if not ReadReplyLine(Sock, Reply) then
      begin
        AReply := 'Fiji did not answer in time';
        Exit(faError);
      end;
      if Copy(Reply, 1, 2) = 'OK' then
      begin
        AReply := FijiUnescape(Trim(Copy(Reply, 3, MaxInt)));
        Result := faOk;
      end
      else
      begin
        if Copy(Reply, 1, 3) = 'ERR' then
          AReply := FijiUnescape(Trim(Copy(Reply, 4, MaxInt)))
        else
          AReply := 'unexpected reply: ' + Reply;
        Result := faError;
      end;
    except
      on E: Exception do
      begin
        AReply := 'connection to Fiji lost (' + E.Message + ')';
        Result := faError;
      end;
    end;
  finally
    Sock.Free;
  end;
end;

procedure FijiErrorParts(const AReply: string; out ALine: Integer; out AWhy: string);
var
  P: Integer;
begin
  ALine := 0;
  AWhy := Trim(AReply);
  if Copy(AWhy, 1, 5) <> 'line=' then
    Exit;
  P := Pos(';', AWhy);
  if P = 0 then
    Exit;
  if not TryStrToInt(Copy(AWhy, 6, P - 6), ALine) then
    ALine := 0;
  AWhy := Trim(Copy(AWhy, P + 1, MaxInt));
end;

function FijiListening: Boolean;
var
  Reply: string;
begin
  Result := FijiSend('PING', Reply, 2000) = faOk;
end;

end.
