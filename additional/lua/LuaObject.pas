unit LuaObject;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, lua;

type
  TLuaObject = class;
  TVariantArray =array of Variant;
  PVariantArray =^TVariantArray;

  { TLuaObject }

  TLuaObject = class
  protected
    L : PLua_State;
    FLuaReference : integer;
    FParent : TLuaObject;
    FChildren : TList;
    
    function  GetLuaProp(PropName : AnsiString): Variant;
    procedure SetLuaProp(PropName : AnsiString; const AValue: Variant);
    function  GetPropValue(propName : AnsiString): Variant; virtual;
    function  GetPropObject(propName: AnsiString) : Boolean; virtual;
    function  SetPropValue(PropName : AnsiString; const AValue: Variant) : Boolean; virtual;
    function  SetPropObject(propName: AnsiString) : Boolean; virtual;
    function  PropIsObject(propName : AnsiString): Boolean; virtual;
  public
    constructor Create(LuaState : PLua_State; AParent : TLuaObject = nil); virtual;
    destructor Destroy; override;

    procedure PushSelf;

    procedure CallEvent(EventName : AnsiString); overload;
    function  CallEvent(EventName : AnsiString; args : Array of Variant; Results: PVariantArray = nil) : Integer; overload;
    function  EventExists(EventName: AnsiString): Boolean;

    property LState : PLua_State read L;

    property LuaProp[PropName : AnsiString] : Variant read GetLuaProp write SetLuaProp;
  end;

  TLuaObjectRegisterMethodsCallback = procedure(L : Plua_State; classTable : Integer);
  TLuaObjectNewCallback = function(L : PLua_State; AParent : TLuaObject=nil):TLuaObject;

var
  LuaObjects : TList;

procedure ClearObjects;
procedure LuaCopyTable(L: Plua_State; IdxFrom, IdxTo, MtTo : Integer);
function  LuaToTLuaObject(L: Plua_State; Idx : Integer) : TLuaObject;
procedure RegisterLuaObject(L: Plua_State);

procedure RegisterTLuaObject(L : Plua_State; ObjectName : AnsiString; CreateFunc : lua_CFunction; MethodsCallback : TLuaObjectRegisterMethodsCallback = nil);
procedure RegisterObjectInstance(L : Plua_State; aClassName, InstanceName : AnsiString; ObjectInstance : TLuaObject);
procedure RegisterMethod(L : Plua_State; TheMethodName : AnsiString; TheMethodAddress : lua_CFunction; classTable : Integer);
function  new_LuaObject(L : PLua_State; aClassName : AnsiString; NewCallback : TLuaObjectNewCallback) : Integer; cdecl;

procedure PushTLuaObject(L : PLua_State; ObjectInstance : TLuaObject);

function  new_TLuaObject(L : PLua_State) : Integer; cdecl;
function  index_TLuaObject(L : PLua_State) : Integer; cdecl;
function  newindex_TLuaObject(L : PLua_State) : Integer; cdecl;
function  gc_TLuaObject(L : PLua_State) : Integer; cdecl;
procedure RegisterClassTLuaObject(L : Plua_State);

implementation

uses
  typinfo, LuaUtils;

const
  LuaTLuaObjectClassName = 'TLuaObject';

constructor TLuaObject.Create(LuaState : PLua_State; AParent : TLuaObject = nil);
begin
  L := LuaState;
  FParent := AParent;
  if assigned(FParent) then
    FParent.FChildren.Add(Self);
  FChildren := TList.Create;
  // Create a reference to the object table, this way lua won't GC its version
  FLuaReference := luaL_ref(L, LUA_REGISTRYINDEX);
  lua_rawgeti (L, LUA_REGISTRYINDEX, FLuaReference);
  LuaObjects.Add(Self);
end;

destructor TLuaObject.Destroy;
var
  lo : TLuaObject;
begin
  LuaObjects.Remove(Self);
  if assigned(FParent) then
    FParent.FChildren.Remove(Self);
  while FChildren.Count > 0 do
    begin
      lo := TLuaObject(FChildren[FChildren.Count-1]);
      FChildren.Delete(FChildren.Count-1);
      lo.Free;
    end;
  FChildren.Free;
  luaL_unref(L, LUA_REGISTRYINDEX, FLuaReference);
  inherited Destroy;
end;

procedure TLuaObject.PushSelf;
begin
  lua_rawgeti(L, LUA_REGISTRYINDEX, FLuaReference);
end;

procedure TLuaObject.CallEvent(EventName: AnsiString);
begin
  CallEvent(EventName, []);
end;

function TLuaObject.CallEvent(EventName : AnsiString; args: array of Variant; Results: PVariantArray) : Integer;
var
   NArgs,
   NResults,
   i :Integer;
  idx :Integer;
begin
  if not EventExists(EventName) then
    exit;
  lua_rawgeti (L, LUA_REGISTRYINDEX, FLuaReference); // Place our object on the stack
  idx := lua_gettop(L);
  lua_pushliteral(L, PChar(EventName)); // Place the event name on the stack
  lua_gettable(L, idx); // try to get the item
  //Put self on the stack
  lua_rawgeti(L, LUA_REGISTRYINDEX, FLuaReference);
  //lua_pushvalue(L, fti);
  //Put Parameters on the Stack
  NArgs := High(Args)+1;
  for i:=0 to (NArgs-1) do
    LuaPushVariant(L, Args[i]);

  NResults := LUA_MULTRET;
  //Call the Function
  LuaPcall(L, NArgs+1, NResults, 0); // NArgs+1 for self + args
  CallEvent :=lua_gettop(L);   //Get Number of Results

  if (Results<>Nil) then
    begin
      //Get Results in the right order
      SetLength(Results^, CallEvent);
      for i:=0 to CallEvent-1 do
        Results^[CallEvent-(i+1)] :=LuaToVariant(L, -(i+1));
    end;
end;

function TLuaObject.EventExists(EventName: AnsiString): Boolean;
var
  idx :Integer;
begin
  lua_rawgeti (L, LUA_REGISTRYINDEX, FLuaReference); // Place our object on the stack
  idx := lua_gettop(L);
  lua_pushliteral(L, PChar(EventName)); // Place the event name on the stack
  lua_gettable(L, idx); // try to get the item
  result := lua_isfunction(L, lua_gettop(L));// item at the top of the stack
  if result then
    lua_pop(L, 2);
end;

function TLuaObject.GetLuaProp(PropName : AnsiString): Variant;
var
  idx : Integer;
begin
  lua_rawgeti (L, LUA_REGISTRYINDEX, FLuaReference); // Place our object on the stack
  idx := lua_gettop(L);
  lua_pushliteral(L, PChar(PropName)); // Place the event name on the stack
  lua_gettable(L, idx); // try to get the item
  result := LuaToVariant(L, lua_gettop(L));
  lua_pop(L, 2);
end;

procedure TLuaObject.SetLuaProp(PropName : AnsiString; const AValue: Variant);
var
  idx : Integer;
begin
  lua_rawgeti (L, LUA_REGISTRYINDEX, FLuaReference); // Place our object on the stack
  idx := lua_gettop(L);
  lua_pushstring(L, PChar(propName));
  LuaPushVariant(L, AValue);
  lua_rawset(L, idx);
end;

function TLuaObject.GetPropValue(propName: AnsiString): Variant;
begin
  if IsPublishedProp(self, propName) then
    result := typinfo.GetPropValue(self, propName)
  else
    result := NULL;
end;

function TLuaObject.GetPropObject(propName: AnsiString) : Boolean;
begin
 result := false;
end;

function TLuaObject.SetPropValue(PropName: AnsiString; const AValue: Variant) : Boolean;
begin
  result := IsPublishedProp(self, propName);
  if result then
    typinfo.SetPropValue(self, propName, AValue);
end;

function TLuaObject.SetPropObject(propName: AnsiString) : Boolean;
begin
  result := false;
end;

function TLuaObject.PropIsObject(propName: AnsiString): Boolean;
begin
  result := false;
end;

{ Global LUA Methods }

procedure LuaCopyTable(L: Plua_State; IdxFrom, IdxTo, MtTo : Integer);
var
  id:Integer;
  tbl : Integer;
  key, val : Variant;
  cf : lua_CFunction;
begin
  lua_pushnil(L);
  while(lua_next(L, IdxFrom)<>0)do
    begin
      key := LuaToVariant(L, -2);
      if CompareText(key, '__') = 1 then
        tbl := MtTo
      else
        tbl := IdxTo;
      case lua_type(L, -1) of
        LUA_TFUNCTION : begin
          cf := lua_tocfunction(L, -1);
          LuaPushVariant(L, key);
          lua_pushcfunction(L, cf);
          lua_rawset(L, tbl);
        end;
        LUA_TTABLE    : begin
          id := lua_gettop(L);
          LuaCopyTable(L, id, IdxTo, MtTo);
        end;
      else
        val := LuaToVariant(L, -1);
        LuaPushVariant(L, key);
        LuaPushVariant(L, val);
        lua_rawset(L, tbl);
      end;
      lua_pop(L, 1);
    end;
end;

function LuaToTLuaObject(L: Plua_State; Idx : Integer) : TLuaObject;
begin
  result := nil;
  if lua_type(L, Idx) = LUA_TTABLE then
    result := TLuaObject(LuaGetTableInteger(L, Idx, '_Self'))
  else
    luaL_error(L, PChar('Class table expected.'));
end;

procedure PushTLuaObject(L: PLua_State; ObjectInstance: TLuaObject);
begin
  lua_rawgeti(L, LUA_REGISTRYINDEX, ObjectInstance.FLuaReference);
end;

function new_TLuaObject(L : PLua_State) : Integer; cdecl;
var
  P, E : TLuaObject;
  n, idx, idx2, mt : Integer;
begin
  n := lua_gettop(L);
  if lua_type(L, 1) <> LUA_TTABLE then
    lua_remove(L, 1);
  if n = 1 then
    P := LuaToTLuaObject(L, 1)
  else
    P := nil;
    
  lua_newtable(L);
  E := TLuaObject.Create(L, P);
  idx := lua_gettop(L);

  lua_pushliteral(L, '_Self');
  lua_pushinteger(L, Integer(Pointer(E)));
  lua_rawset(L, idx);

  lua_newtable(L);
  mt := lua_gettop(L);

  lua_pushliteral(L, LuaTLuaObjectClassName);
  lua_gettable(L, LUA_GLOBALSINDEX);
  idx2 := lua_gettop(L);

  LuaCopyTable(L, idx2, idx, mt);
  lua_setmetatable(L, idx);
  
  lua_pop(L, 1);

  result := 1;
end;

function index_TLuaObject(L : PLua_State) : Integer; cdecl;
var
  E : TLuaObject;
  propName : AnsiString;
  v : Variant;
begin
  E := LuaToTLuaObject(L, 1);
  lua_remove(L, 1);
  if E = nil then
    begin
      result := 0;
      exit;
    end;
  propName := LuaToString(L, 1);
  index_TLuaObject := 1;
  if E.PropIsObject(propName) then
    begin
      if not E.GetPropObject(propName) then
        index_TLuaObject := 0;
    end
  else
    begin
      v := E.GetPropValue(propName);
      if v = NULL then
        index_TLuaObject := 0
      else
        LuaPushVariant(L, v);
    end;
end;

function newindex_TLuaObject(L : PLua_State) : Integer; cdecl;
var
  TableIndex, ValueIndex : Integer;
  E : TLuaObject;
  propName : AnsiString;
begin
  result := 0;
  E := LuaToTLuaObject(L, 1);
  if E = nil then
    begin
      exit;
    end;
  propName := LuaToString(L, 2);
  if E.PropIsObject(propName) and E.SetPropObject(propName) then
  else if not E.SetPropValue(propName, LuaToVariant(L, 3)) then
    begin
    // This is a standard handler, no value was found in the object instance
    // so we push the value into the Lua Object reference.
      TableIndex := LuaAbsIndex(L, 1);
      ValueIndex := LuaAbsIndex(L, 3);
      lua_pushstring(L, PChar(propName));
      lua_pushvalue(L, ValueIndex);
      lua_rawset(L, TableIndex);
    end;
end;

function gc_TLuaObject(L : PLua_State) : Integer; cdecl;
var
  E : TLuaObject;
begin
  E := LuaToTLuaObject(L, 1);
  // Release the object
  if assigned(E) then
    E.Free;
  result := 0;
end;

procedure RegisterObjectInstance(L: Plua_State; aClassName, InstanceName: AnsiString; ObjectInstance : TLuaObject);
var
  P, E : TLuaObject;
  n, idx, idx2, mt : Integer;
begin
  n := lua_gettop(L);
  if lua_type(L, 1) <> LUA_TTABLE then
    lua_remove(L, 1);
  if n = 1 then
    P := LuaToTLuaObject(L, 1)
  else
    P := nil;

  lua_newtable(L);
  E := ObjectInstance; //NewCallback(L, P);
  idx := lua_gettop(L);

  lua_pushliteral(L, '_Self');
  lua_pushinteger(L, Integer(Pointer(E)));
  lua_rawset(L, idx);

  lua_newtable(L);
  mt := lua_gettop(L);

  lua_pushliteral(L, PChar(aClassName));
  lua_gettable(L, LUA_GLOBALSINDEX);
  idx2 := lua_gettop(L);

  LuaCopyTable(L, idx2, idx, mt);
  lua_setmetatable(L, idx);

  lua_pop(L, 1);

  lua_settable(L, LUA_GLOBALSINDEX);
end;

procedure RegisterMethod(L : Plua_State; TheMethodName : AnsiString; TheMethodAddress : lua_CFunction; classTable : Integer);
begin
  lua_pushliteral(L, PChar(TheMethodName));
  lua_pushcfunction(L, TheMethodAddress);
  lua_rawset(L, classTable);
end;

function new_LuaObject(L : PLua_State; aClassName : AnsiString; NewCallback : TLuaObjectNewCallback): Integer; cdecl;
var
  P, E : TLuaObject;
  n, idx, idx2, mt : Integer;
begin
  n := lua_gettop(L);
  if lua_type(L, 1) <> LUA_TTABLE then
    lua_remove(L, 1);
  if n > 1 then
    P := LuaToTLuaObject(L, 2)
  else
    P := nil;

  lua_newtable(L);
  E := NewCallback(L, P);
  idx := lua_gettop(L);

  lua_pushliteral(L, '_Self');
  lua_pushinteger(L, Integer(Pointer(E)));
  lua_rawset(L, idx);

  lua_newtable(L);
  mt := lua_gettop(L);

  lua_pushliteral(L, PChar(aClassName));
  lua_gettable(L, LUA_GLOBALSINDEX);
  idx2 := lua_gettop(L);

  LuaCopyTable(L, idx2, idx, mt);
  lua_setmetatable(L, idx);

  lua_pop(L, 1);

  result := 1;
end;

procedure RegisterClassTLuaObject(L : Plua_State);
var
  classTable : Integer;
begin
  lua_pushstring(L, LuaTLuaObjectClassName);
  lua_newtable(L);
  classTable := lua_gettop(L);

  RegisterMethod(L, '__index', @index_TLuaObject, classTable);
  RegisterMethod(L, '__newindex', @newindex_TLuaObject, classTable);
  RegisterMethod(L, '__call', @new_TLuaObject, classTable);
  RegisterMethod(L, '__gc', @gc_TLuaObject, classTable);
  RegisterMethod(L, 'release', @gc_TLuaObject, classTable);
  RegisterMethod(L, 'new', @new_TLuaObject, classTable);

  lua_settable(L, LUA_GLOBALSINDEX);
end;

{ Global Management Methods }

procedure RegisterTLuaObject(L: Plua_State; ObjectName : AnsiString;
  CreateFunc : lua_CFunction;
  MethodsCallback: TLuaObjectRegisterMethodsCallback);
var
  classTable : Integer;
begin
  lua_pushstring(L, PChar(ObjectName));
  lua_newtable(L);
  classTable := lua_gettop(L);

  RegisterMethod(L, '__index', @index_TLuaObject, classTable);
  RegisterMethod(L, '__newindex', @newindex_TLuaObject, classTable);
  RegisterMethod(L, '__call', CreateFunc, classTable);
  RegisterMethod(L, '__gc', @gc_TLuaObject, classTable);
  RegisterMethod(L, 'release', @gc_TLuaObject, classTable);
  RegisterMethod(L, 'new', CreateFunc, classTable);

  if Assigned(MethodsCallback) then
    MethodsCallback(L, classTable);

  lua_settable(L, LUA_GLOBALSINDEX);
end;

procedure ClearObjects;
begin
  while LuaObjects.Count > 0 do
    TLuaObject(LuaObjects[LuaObjects.Count-1]).Free;
end;

procedure RegisterLuaObject(L: Plua_State);
begin
  RegisterClassTLuaObject(L);
end;

initialization
  LuaObjects := TList.Create;

finalization
  ClearObjects;
  LuaObjects.Free;

end.
