﻿unit AST.Pascal.Project;

interface

uses System.SysUtils, System.Classes, System.Types, Generics.Collections, System.IOUtils,
     AVL,
     AST.Intf,
     AST.Delphi.DataTypes,
     AST.Parser.Options,
     AST.Targets,
     AST.Delphi.Intf,
     AST.Delphi.Classes,
     AST.Parser.Messages,
     AST.Parser.Utils,
     AST.Pascal.Intf,
     AST.Classes;

type
  TUnits = TList<TASTModule>;
  TTypes = TList<TIDType>;
  TEnumDeclProc = procedure (Module: TASTModule; Decl: TASTDeclaration);

  TPascalProjectSettings = class(TASTProjectSettings, IPascalProjectSettings)

  end;


  TPascalProject = class(TASTProject, IASTProject, IASTPascalProject)
  type
    TStrConstKey = record
      StrTypeID: TDataTypeID;
      StrValue: string;
    end;
    TConstInfo = record
      Decl: TIDConstant;
      Index: Integer;
    end;
    TStrLiterals = TAVLTree<TStrConstKey, TConstInfo>;
  private
    FName: string;
    FUnits: TUnits;
    FTargetName: string;
    FTarget: TNPLTarget;
    FDefines: TDefines;
    FStrLiterals: TStrLiterals;
    FIncludeDebugInfo: Boolean;
    FUnitSearchPathes: TStrings;
    FMessages: ICompilerMessages;
    FRTTICharset: TRTTICharset;
    FOptions: TPackageOptions;
    function GetIncludeDebugInfo: Boolean;
    function OpenUnit(const UnitName: string): TASTModule;
    function RefCount: Integer;
    function GetRTTICharset: TRTTICharset;
    function GetUnitsCount: Integer;
    function GetUnit(Index: Integer): TObject; overload;
    function GetUnit(const UnitName: string): TObject; overload;
    function GetSearchPathes: TStrings;
    function GetOptions: TPackageOptions;
    function GetTarget: string;
    function GetDefines: TDefines;

    function GetSysUnit: TASTModule;
    procedure SetIncludeDebugInfo(const Value: Boolean);
    procedure SetRTTICharset(const Value: TRTTICharset);
    procedure SetTarget(const Value: string);
    class function StrListCompare(const Left, Right: TStrConstKey): NativeInt; static;
  protected
    fSysUnit: TASTModule;
    function GetUnitClass: TASTUnitClass; override;
    function GetSystemUnitClass: TASTUnitClass; virtual; abstract;
    function GetSystemUnitFileName: string; virtual;
    function GetPointerSize: Integer; override;
    function GetNativeIntSize: Integer; override;
    procedure InitSystemUnit; virtual;
  public
    constructor Create(const Name: string); override;
    destructor Destroy; override;
    ////////////////////////////////////////
    procedure SaveToStream(Stream: TStream);
    procedure PrepareStrLiterals;
    procedure SaveStrLiterals(Stream: TStream);
    procedure AddUnit(aUnit, BeforeUnit: TASTModule); overload;
    procedure AddUnit(const FileName: string); overload;
    procedure AddUnitSource(const Source: string);
    procedure AddUnitSearchPath(const Path: string; IncludeSubDirectories: Boolean);
    procedure Clear;
    property IncludeDebugInfo: Boolean read GetIncludeDebugInfo write SetIncludeDebugInfo;
    property RTTICharset: TRTTICharset read GetRTTICharset write SetRTTICharset;
    property Units: TUnits read FUnits;
    property SysUnit: TASTModule read fSysUnit;
    property Options: TPackageOptions read GetOptions;
    function GetStringConstant(const Value: string): Integer; overload;
    function GetStringConstant(const StrConst: TIDStringConstant): Integer; overload;
    function FindUnitFile(const UnitName: string): string;
    function UsesUnit(const UnitName: string; AfterUnit: TASTModule): TASTModule;
    function GetMessages: ICompilerMessages;
    function Compile: TCompilerResult; virtual;
    function CompileInterfacesOnly: TCompilerResult; virtual;
    procedure EnumIntfDeclarations(const EnumProc: TEnumASTDeclProc);
  end;

implementation

uses AST.Parser.Errors,
     AST.Delphi.Errors,
     AST.Pascal.Parser;

function TPascalProject.GetOptions: TPackageOptions;
begin
  Result := FOptions;
end;

function TPascalProject.GetDefines: TDefines;
begin
  Result := FDefines;
end;

function TPascalProject.GetIncludeDebugInfo: Boolean;
begin
  Result := FIncludeDebugInfo;
end;

function TPascalProject.GetMessages: ICompilerMessages;
var
  i: Integer;
  UnitMessages: ICompilerMessages;
begin
  FMessages.Clear;
  for i := 0 to FUnits.Count - 1 do begin
    UnitMessages := TNPUnit(FUnits[i]).Messages;
    FMessages.CopyFrom(UnitMessages);
  end;
  Result := FMessages;
end;

function TPascalProject.GetRTTICharset: TRTTICharset;
begin
  Result := FRTTICharset;
end;

function TPascalProject.GetSearchPathes: TStrings;
begin
  Result := FUnitSearchPathes;
end;

function TPascalProject.GetStringConstant(const Value: string): Integer;
var
  Node: TStrLiterals.PAVLNode;
  Data: TConstInfo;
  Key: TStrConstKey;
begin
  case FRTTICharset of
    RTTICharsetASCII: Key.StrTypeID := dtAnsiString;
  else
    Key.StrTypeID := dtString;
  end;

  Key.StrValue := Value;
  Node := FStrLiterals.Find(Key);
  if Assigned(Node) then
    Result := Node.Data.Index
  else begin
    Result := FStrLiterals.Count;
    Data.Decl := nil;
    Data.Index := Result;
    FStrLiterals.InsertNode(Key, Data);
  end;
end;

function TPascalProject.GetStringConstant(const StrConst: TIDStringConstant): Integer;
var
  Node: TStrLiterals.PAVLNode;
  Data: TConstInfo;
  Key: TStrConstKey;
begin
  Key.StrTypeID := StrConst.DataTypeID;
  Key.StrValue := StrConst.Value;
  Node := FStrLiterals.Find(Key);
  if Assigned(Node) then
    Result := Node.Data.Index
  else begin
    Result := FStrLiterals.Count;
    Data.Decl := StrConst;
    Data.Index := Result;
    FStrLiterals.InsertNode(Key, Data);
  end;
end;

function TPascalProject.GetSystemUnitFileName: string;
begin
  Result := 'System.pas';
end;

function TPascalProject.GetSysUnit: TASTModule;
begin
  Result := fSysUnit;
end;

function TPascalProject.GetTarget: string;
begin
  Result := FTargetName;
end;

function TPascalProject.GetUnit(Index: Integer): TObject;
begin
  Result := FUnits[Index];
end;

function TPascalProject.GetUnit(const UnitName: string): TObject;
var
  i: Integer;
begin
  for i := 0 to FUnits.Count - 1 do
  begin
    Result := FUnits[i];
    if TNPUnit(Result).Name = UnitName then
      Exit;
  end;
  Result := nil;
end;

function TPascalProject.GetUnitClass: TASTUnitClass;
begin
  Result := TNPUnit;
end;

function TPascalProject.GetUnitsCount: Integer;
begin
  Result := FUnits.Count;
end;

procedure StringStreamLoadFromFile(const FileName: string; Stream: TStringStream);
var
  FStream: TStream;
begin
  FStream := TFileStream.Create(FileName, fmOpenRead);
  try
    FStream.Position := 0;
    Stream.CopyFrom(FStream, FStream.Size);
  finally
    FStream.Free;
  end;
end;

procedure TPascalProject.InitSystemUnit;
var
  Stream: TStringStream;
  SysFileName, SysSource: string;
begin
  try
    if not Assigned(fSysUnit) then
    begin
      SysFileName := FindUnitFile('system');
      if FileExists(SysFileName) then
      begin
        Stream := TStringStream.Create('');
        try
          StringStreamLoadFromFile(SysFileName, Stream);
          SysSource := Stream.DataString;
        finally
          Stream.Free;
        end;
      end else
        SysSource := 'unit system; end.';

      fSysUnit := GetSystemUnitClass.Create(Self, SysFileName, SysSource);
      FUnits.Insert(0, fSysUnit);
    end;
  except
    on e: exception do
      raise Exception.Create('Internal ERROR: ' + e.Message);
  end;
end;

procedure TPascalProject.AddUnit(aUnit, BeforeUnit: TASTModule);
var
  i: Integer;
begin
  if FUnits.IndexOf(aUnit) > -1 then
    raise ECompilerInternalError.CreateFmt(sUnitAlreadyExistFmt, [AnsiUpperCase(TNPUnit(aUnit).Name)]);

  TNPUnit(aUnit).UnitID := FUnits.Count;

  for i := 0 to FUnits.Count - 1 do
  begin
    if FUnits[i] = BeforeUnit then
    begin
      FUnits.Insert(i, aUnit);
      Exit;
    end;
  end;
  FUnits.Add(aUnit);
end;

class function TPascalProject.StrListCompare(const Left, Right: TStrConstKey): NativeInt;
begin
  Result := Ord(Left.StrTypeID) - Ord(Right.StrTypeID);
  if Result = 0 then
    Result := AnsiCompareStr(Left.StrValue, Right.StrValue);
end;

function TPascalProject.UsesUnit(const UnitName: string; AfterUnit: TASTModule): TASTModule;
var
  i: Integer;
  SUnitName: string;
begin
  // поиск в текущем пакете
  for i := 0 to FUnits.Count - 1 do
  begin
    SUnitName := TNPUnit(FUnits[i]).Name;
    if AnsiCompareText(SUnitName, UnitName) = 0 then
      Exit(FUnits[i]);
  end;
  // ищем на файловой системе
  SUnitName := FindUnitFile(UnitName);
  if SUnitName <> '' then
  begin
    Result := OpenUnit(SUnitName);
    AddUnit(Result, AfterUnit);
  end else
    Result := nil;
end;

constructor TPascalProject.Create(const Name: string);
begin
  FName := Name;
  FUnits := TUnits.Create;
  FDefines := TDefines.Create();
  FOptions := TPackageOptions.Create(nil);
  FUnitSearchPathes := TStringList.Create;
  FMessages := TCompilerMessages.Create;
  FRTTICharset := RTTICharset;
  FStrLiterals := TStrLiterals.Create(StrListCompare);
  SetTarget('ANY');
end;

procedure TPascalProject.AddUnitSource(const Source: string);
var
  UN: TNPUnit;
begin
  UN := TNPUnit.Create(Self, Source);
  AddUnit(UN, nil);
end;

procedure TPascalProject.AddUnit(const FileName: string);
begin
  AddUnit(GetUnitClass().CreateFromFile(Self, FileName), nil);
end;

procedure TPascalProject.AddUnitSearchPath(const Path: string; IncludeSubDirectories: Boolean);
begin
  FUnitSearchPathes.AddObject(Path, TObject(IncludeSubDirectories));
end;

procedure TPascalProject.Clear;
var
  i: Integer;
begin
  for i := 0 to FUnits.Count - 1 do
    if FUnits[i] <> SYSUnit then
      FUnits[i].Free;
  FUnits.Clear;
  FStrLiterals.Free;
  FStrLiterals := TStrLiterals.Create(StrListCompare);
end;

function TPascalProject.Compile: TCompilerResult;
var
  i: Integer;
begin
  Result := CompileSuccess;
  // компиляция модулей
  InitSystemUnit;
  for i := 0 to FUnits.Count - 1 do
  begin
    var UN := FUnits[i];
    Result := TNPUnit(UN).Compile;
    if Result = CompileFail then
      Exit;
  end;
end;

destructor TPascalProject.Destroy;
begin
  Clear;
  FUnits.Free;
  FDefines.Free;
  FStrLiterals.Free;
  FUnitSearchPathes.Free;
  FOptions.Free;
  inherited;
end;

procedure TPascalProject.EnumIntfDeclarations(const EnumProc: TEnumASTDeclProc);
var
  i: Integer;
  Module: TASTModule;
begin
  for i := 0 to FUnits.Count - 1 do
  begin
    Module := FUnits[i];
    Module.EnumIntfDeclarations(EnumProc);
  end;
end;

function TPascalProject.OpenUnit(const UnitName: string): TASTModule;
var
  Stream: TStringStream;
  UnitClass: TASTUnitClass;
begin
  Stream := TStringStream.Create('');
  try
    StringStreamLoadFromFile(UnitName, Stream);
    UnitClass := GetUnitClass();
    Result := UnitClass.Create(Self, UnitName, Stream.DataString);
  finally
    Stream.Free;
  end;
end;

procedure TPascalProject.PrepareStrLiterals;
var
  Idx: Integer;
  Constant: TIDConstant;
  Node: TStrLiterals.PAVLNode;
begin
  {переупорядочиваем литералы по индексам}
  Node := FStrLiterals.First;
  while Assigned(Node) do begin
    Idx := Node.Data.Index;
    Constant := Node.Data.Decl;
    if Assigned(Constant) then
      Constant.Index := Idx;
    Node := FStrLiterals.Next(Node);
  end;
end;

function TPascalProject.RefCount: Integer;
begin
  Result := FRefCount;
end;

function FindInSubDirs(const RootDir, UnitName: string): string;
var
  i: Integer;
  SearchPath, SearchUnitName: string;
  Dirs: TStringDynArray;
begin
  Dirs := TDirectory.GetDirectories(RootDir);
  for i := 0 to Length(Dirs) - 1 do
  begin
    SearchPath := IncludeTrailingPathDelimiter(Dirs[i]);
    SearchUnitName := SearchPath + UnitName + '.pas';
    if FileExists(SearchUnitName) then
      Exit(SearchUnitName);

    Result := FindInSubDirs(SearchPath, UnitName);
    if Result <> '' then
      Exit;
  end;
  Result := '';
end;

function TPascalProject.FindUnitFile(const UnitName: string): string;
var
  i: Integer;
  SearchPath, SearchUnitName: string;

begin
  // поиск по файловой системе
  for i := 0 to FUnitSearchPathes.Count - 1 do
  begin
    SearchPath := IncludeTrailingPathDelimiter(FUnitSearchPathes[i]);
    SearchUnitName := SearchPath + UnitName + '.pas';
    if FileExists(SearchUnitName) then
      Exit(SearchUnitName);

    // поиск в поддиректориях
    if Boolean(FUnitSearchPathes.Objects[i]) then
    begin
      Result := FindInSubDirs(SearchPath, UnitName);
      if Result <> '' then
        Exit;
    end;
  end;
  Result := '';
end;

procedure TPascalProject.SaveStrLiterals(Stream: TStream);
begin

end;

procedure TPascalProject.SaveToStream(Stream: TStream);
begin

end;

procedure TPascalProject.SetIncludeDebugInfo(const Value: Boolean);
begin
  FIncludeDebugInfo := Value;
end;

procedure TPascalProject.SetRTTICharset(const Value: TRTTICharset);
begin
  FRTTICharset := Value;
end;

procedure TPascalProject.SetTarget(const Value: string);
begin
  FTargetName := Value;
  FTarget := FindTarget(Value);
  if not Assigned(FTarget) then
    AbortWorkInternal('Unknwon target: ' + Value);
end;

function TPascalProject.CompileInterfacesOnly: TCompilerResult;
var
  i: Integer;
begin
  Result := CompileSuccess;
  // компиляция модулей
  for i := 0 to FUnits.Count - 1 do
  begin
    Result := TNPUnit(FUnits[i]).CompileIntfOnly;
    if Result = CompileFail then
      Exit;
  end;
end;

function TPascalProject.GetPointerSize: Integer;
begin
  Result := FTarget.PointerSize;
end;

function TPascalProject.GetNativeIntSize: Integer;
begin
  Result := FTarget.NativeIntSize;
end;

end.

