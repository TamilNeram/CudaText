(*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.

Copyright (c) Alexey Torgashin
*)
unit proc_py;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Variants, Controls,
  Forms,
  ATSynEdit,
  PythonEngine,
  proc_globdata;

procedure Py_SetSysPath(const Dirs: array of string; DoAdd: boolean);
function Py_RunPlugin_Command(const AModule, AMethod: string; const AParams: array of string): string;
function Py_RunPlugin_Event(const AModule, ACmd: string;
  AEd: TATSynEdit; const AParams: array of string; ALazy: boolean): string;
function Py_RunModuleFunction(const AModule, AFunc: string; AParams: array of string): PPyObject;
function Py_RunModuleFunction2(const AModule, AFunc: string; AParams: array of PPyObject): PPyObject;

function Py_rect(const R: TRect): PPyObject; cdecl;
function Py_rect_monitor(N: Integer): PPyObject; cdecl;
function Py_rect_control(C: TControl): PPyObject; cdecl;

const
  cPyTrue = 'True';
  cPyFalse = 'False';
  cPyNone = 'None';

implementation

procedure Py_SetSysPath(const Dirs: array of string; DoAdd: boolean);
var
  Str, Sign: string;
  i: Integer;
begin
  Str:= '';
  for i:= 0 to Length(Dirs)-1 do
    Str:= Str + 'r"' + Dirs[i] + '"' + ',';
  if DoAdd then
    Sign:= '+='
  else
    Sign:= '=';
  Str:= Format('sys.path %s [%s]', [Sign, Str]);
  GetPythonEngine.ExecString(Str);
end;


function Py_ArgListToString(const AParams: array of string): string;
var
  i: integer;
begin
  Result:= '';
  for i:= 0 to Length(AParams)-1 do
  begin
    if Result<>'' then
      Result:= Result+', ';
    Result:= Result+AParams[i];
  end;
end;


function Py_RunPlugin_Command(const AModule, AMethod: string;
  const AParams: array of string): string;
var
  SObj: string;
  SCmd1, SCmd2: string;
begin
  SObj:= '_cudacmd_' + AModule;

  SCmd1:=
    Format('import %s               ', [AModule]) + SLineBreak +
    Format('if "%s" not in locals():', [SObj]) + SLineBreak +
    Format('    %s = %s.Command()   ', [SObj, AModule]) + SLineBreak;
  if UiOps.PyInitLog then
    SCmd1:= SCmd1+
    Format('    print("Init: %s")',    [AModule]);

  SCmd2:=
    Format('%s.%s(%s)', [SObj, AMethod, Py_ArgListToString(AParams)]);

  try
    GetPythonEngine.ExecString(SCmd1);
    Result:= GetPythonEngine.EvalStringAsStr(SCmd2);
  except
  end;
end;

function Py_EvalStringAsString(const command: string): string;
begin
  Result:= GetPythonEngine.EvalStringAsStr(command);
end;

//var
//  _EventBusy: boolean = false;

function Py_RunPlugin_Event(const AModule, ACmd: string;
  AEd: TATSynEdit; const AParams: array of string;
  ALazy: boolean): string;
var
  SObj, Str1, Str2, SParams: string;
  H: PtrInt;
  i: integer;
begin
  H:= PtrInt(Pointer(AEd));
  SParams:= Format('cudatext.Editor(%d)', [H]);
  for i:= 0 to Length(AParams)-1 do
    SParams:= SParams + ', ' + AParams[i];

  SObj:= '_cudacmd_' + AModule;

  if not ALazy then
  begin
    Str1:= 'import cudatext' + SLineBreak +
      Format('import %s',                [AModule]) + SLineBreak +
      Format('if "%s" not in locals():', [SObj]) + SLineBreak +
      Format('    %s = %s.Command()',    [SObj, AModule]) + SLineBreak;
    if UiOps.PyInitLog then
      Str1:= Str1+
      Format('    print("Init: %s")',    [AModule]);
    Str2:=
      Format('%s.%s(%s)', [SObj, ACmd, SParams]);

    try
      GetPythonEngine.ExecString(Str1);
      Result:= Py_EvalStringAsString(Str2);
    except
    end;
  end
  else
  begin
    Str1:=
      'import cudatext' + SLineBreak +
      '_ = None' + SLineBreak +
      Format('if "%s" in locals():', [SObj]) + SLineBreak +
      Format('    _ = %s.%s(%s)',    [SObj, ACmd, SParams]);

    try
      GetPythonEngine.ExecString(Str1);
      Result:= Py_EvalStringAsString('_');
    except
    end;
  end;
end;

function Py_rect(const R: TRect): PPyObject; cdecl;
begin
  with GetPythonEngine do
    Result:= Py_BuildValue('(iiii)', R.Left, R.Top, R.Right, R.Bottom);
end;

function Py_rect_monitor(N: Integer): PPyObject; cdecl;
begin
  if (N>=0) and (N<Screen.MonitorCount) then
    Result:= Py_rect(Screen.Monitors[N].BoundsRect)
  else
    Result:= GetPythonEngine.ReturnNone;
end;


function Py_rect_control(C: TControl): PPyObject; cdecl;
var
  P1, P2: TPoint;
  R: TRect;
begin
  P1:= C.ClientToScreen(Point(0, 0));
  P2:= C.ClientToScreen(Point(C.Width, C.Height));
  R.Left:= P1.X;
  R.Top:= P1.Y;
  R.Right:= P2.X;
  R.Bottom:= P2.Y;
  Result:= Py_rect(R);
end;


function Py_RunModuleFunction(const AModule, AFunc: string; AParams: array of string): PPyObject;
var
  SCmd1, SCmd2: string;
begin
  SCmd1:= Format('import %s', [AModule]);
  SCmd2:= Format('%s.%s(%s)', [AModule, AFunc, Py_ArgListToString(AParams)]);

  try
    with GetPythonEngine do
    begin
      ExecString(SCmd1);
      Result:= EvalString(SCmd2);
    end;
  except
  end;
end;

(*
// bug: it dont return result, always gets Py_None
function Py_RunModuleFunction(const AModule, AFunc: string; AParams: array of string): PPyObject;
var
  ObjParams: array of PPyObject;
  i: integer;
begin
  with GetPythonEngine do
  begin
    SetLength(ObjParams, Length(AParams));
    for i:= 0 to Length(AParams)-1 do
      ObjParams[i]:= PyString_FromString(PChar(AParams[i]));

    Result:= Py_RunModuleFunction2(AModule, AFunc, ObjParams);

    ////no need:
    //for i:= Length(AParams)-1 downto 0 do
    //  Py_DECREF(ObjParams[i]);
  end;
end;
*)

// By Artem:
// https://github.com/Alexey-T/CudaText/issues/2366
function Py_RunModuleFunction2(const AModule, AFunc: string; AParams: array of PPyObject): PPyObject;
var
  Module,ModuleDic,Func,Params:PPyObject;
  i:integer;
begin
  Result:=nil;
  with GetPythonEngine do
  begin
    Module:=PyImport_ImportModule(PChar(AModule));
    if Assigned(Module) then
    try
      ModuleDic:=PyModule_GetDict(Module);
      if Assigned(ModuleDic) then
      begin
        Func:=PyDict_GetItemString(ModuleDic,PChar(AFunc));
        if Assigned(Func) then
        begin
          Params:=PyTuple_New(Length(AParams));
          try
            for i:=0 to Length(AParams)-1 do
              if PyTuple_SetItem(Params,i,AParams[i])<>0 then
                RaiseError;
            Result:=PyObject_Call(Func,Params,nil);
          finally
            Py_DECREF(Params);
          end;
        end;
      end;
    finally
      Py_DECREF(Module);
    end;
  end;
end;

end.

