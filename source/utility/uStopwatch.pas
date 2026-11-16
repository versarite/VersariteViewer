unit uStopwatch;

{
  Unit: uStopwatch

  Purpose
  -------
  A precise clock for performance measurements (spec §12).

  Owns
  ----
  - CounterFrequency (Windows): the performance counter frequency,
    read once in the initialization section.

  Knows
  -----
  Nothing else.

  Responsibilities
  ----------------
  - NowMs: milliseconds from a fixed but arbitrary starting point, with
    sub-millisecond resolution. Only differences are meaningful.
  - ProcessAgeMs: milliseconds since this process was started, for the
    start-up measurement; 0 if unknown (always 0 outside Windows).

  Does NOT
  --------
  - Tell the time of day.

  Threads
  -------
  Safe to call from any thread: no state is written after the
  initialization section.

  Uses (MView units)
  ------------------
  None: depends only on the libraries below.
  Libraries:      Windows

  Used by
  -------
  uGLRenderer, uMView, uMainForm, uMediaLoader, uRenderer

  Notes
  -----
  On Windows this uses QueryPerformanceCounter, which resolves well
  below a microsecond. GetTickCount64 would only resolve about 15 ms,
  too coarse to measure a paint (it is what NowMs uses outside
  Windows).
}

{$mode ObjFPC}{$H+}

interface

function NowMs: Double;

{ Milliseconds since this process was started (start-up measurement);
  0 if unknown. }
function ProcessAgeMs: Double;

implementation

{$IFDEF WINDOWS}
uses
  Windows;

var
  CounterFrequency: Int64 = 0;

function NowMs: Double;
var
  Counter: Int64;
begin
  QueryPerformanceCounter(Counter);
  Result := Counter * 1000.0 / CounterFrequency;
end;

function ProcessAgeMs: Double;
var
  Creation, ExitTime, KernelTime, UserTime, NowTime: TFileTime;
  C, N: Int64;
begin
  Result := 0;
  if not GetProcessTimes(GetCurrentProcess, Creation, ExitTime, KernelTime, UserTime) then
    Exit;
  GetSystemTimeAsFileTime(NowTime);
  C := Int64(Creation.dwLowDateTime) or (Int64(Creation.dwHighDateTime) shl 32);
  N := Int64(NowTime.dwLowDateTime) or (Int64(NowTime.dwHighDateTime) shl 32);
  { 100 ns units. }
  Result := (N - C) / 10000.0;
end;

initialization
  QueryPerformanceFrequency(CounterFrequency);
  if CounterFrequency = 0 then
    CounterFrequency := 1;
{$ELSE}
uses
  SysUtils,
  Classes,
  Unix,
  Linux;

{ 1.4: the monotonic clock, nanoseconds. }
function NowMs: Double;
var
  T: TTimeSpec;
begin
  if clock_gettime(CLOCK_MONOTONIC, @T) = 0 then
    Result := T.tv_sec * 1000.0 + T.tv_nsec / 1000000.0
  else
    Result := GetTickCount64;
end;

{ 1.4: from /proc: the system's uptime and the process's start in clock
  ticks after boot (field 22 of /proc/self/stat; 100 ticks a second on
  every usual Linux). 0 if unknown. }
function ProcessAgeMs: Double;
const
  TicksPerSecond = 100;
var
  Lines: TStringList;
  S: string;
  P, Field: Integer;
  Uptime: Double;
  Start: Int64;
  Parts: TStringArray;
begin
  Result := 0;
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile('/proc/uptime');
      if Lines.Count = 0 then
        Exit;
      S := Lines[0];
      P := Pos(' ', S);
      if P > 0 then
        S := Copy(S, 1, P - 1);
      Uptime := StrToFloatDef(S, -1, DefaultFormatSettings);
      if Uptime < 0 then
        Exit;
      Lines.LoadFromFile('/proc/self/stat');
      if Lines.Count = 0 then
        Exit;
      { The name (field 2) is in brackets and may hold spaces. }
      S := Lines[0];
      P := LastDelimiter(')', S);
      if P = 0 then
        Exit;
      Parts := Trim(Copy(S, P + 1, MaxInt)).Split([' ']);
      Field := 22 - 3;           { Parts[0] is field 3 }
      if Length(Parts) <= Field then
        Exit;
      Start := StrToInt64Def(Parts[Field], -1);
      if Start < 0 then
        Exit;
      Result := (Uptime - Start / TicksPerSecond) * 1000.0;
      if Result < 0 then
        Result := 0;
    except
      Result := 0;
    end;
  finally
    Lines.Free;
  end;
end;
{$ENDIF}

end.
