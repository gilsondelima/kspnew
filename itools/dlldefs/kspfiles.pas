unit kspfiles;

interface

uses LResources, ID3Mgmnt, Classes, FileSupportLst, KSPMessages, {$IFDEF WINDOWS}WinInet, {$ENDIF}DateUtils, Dialogs,
  {$IFDEF KSP_STATIC}KSPDLLFileUtils{$ENDIF};

const
{$IFDEF WINDOWS}
  LIB_SUFFIX = '.dll';
{$ELSE}
  LIB_SUFFIX = '.so';
{$ENDIF}

{$DEFINE KSP_SPECIAL_BUILD}

{$IFDEF KSP_SPECIAL_BUILD}
const KSPSpecialInfo = 'R2';
{$ENDIF}
const KSPMajorVersion = '2009';

const Version = 0;
  Major = 2;
  Minor = 50;
  Build = 0;

{$IFNDEF KSP_STATIC}
function ProduceFormatedString(Input: ShortString; Tag: TID3Tag; LengthVal: Cardinal;
  PlsIndex: integer): ShortString; external 'kspfiles'+LIB_SUFFIX;
procedure RemoveForbiddenChars(var Str: String; ReplaceWith: Char); external 'kspfiles'+LIB_SUFFIX;

function IsStream(str: string): boolean; external 'kspfiles'+LIB_SUFFIX;
function IsCD(str: string): boolean; external 'kspfiles'+LIB_SUFFIX;

{$ELSE}
procedure RemoveForbiddenChars(var Str: String; ReplaceWith: Char);
function ProduceFormatedString(Input: ShortString; Tag: TID3Tag; LengthVal: Cardinal;
  PlsIndex: integer): ShortString;
function IsCD(str: string): boolean;
function IsStream(str: string): boolean;
{$ENDIF}

function GetKSPVersion(AppPath: TPathChar): ShortString;
function GetKSPVersion2(AppPath: TPathChar): ShortString;

//FileUtils

function PrepareString(str: string): string;// external 'kspfiles.dll';

function DownloadURLi(const aUrl: string; var Output: TStringList): Boolean;
procedure SearchForFilesFS(Path: string; Rec: boolean; var s: TStringList); overload;
procedure SearchForFiles(Path: string; Rec: boolean; var s: TStringList; DateM: TDateTime); overload;
procedure KSPDeleteFolder(Path: string);
procedure ListFolders(Path: string; s: TStringList; OlderThan: integer);

function IsPlaylist(FileName: string): boolean;



implementation

uses SysUtils;

{$IFDEF KSP_STATIC}
procedure RemoveForbiddenChars(var Str: String; ReplaceWith: Char);
begin
  KSPDLLFileUtils.RemoveForbiddenChars(Str, ReplaceWith);
end;

function ProduceFormatedString(Input: ShortString; Tag: TID3Tag; LengthVal: Cardinal;
  PlsIndex: integer): ShortString;
begin
  Result:=KSPDLLFileUtils.ProduceFormatedString(Input, Tag, LengthVal, PlsIndex);
end;

function IsCD(str: string): boolean;
begin
  Result:=KSPDLLFileUtils.IsCD(str);
end;

function IsStream(str: string): boolean;
begin
 Result:=KSPDLLFileUtils.IsStream(str);
end;
{$ENDIF}

procedure KSPDeleteFolder(Path: string);
var
  i: integer;
  sr: TSearchRec;
  FileAttrs: Integer;
begin
  FileAttrs := faAnyFile;//+faDirectory;

  if FindFirst(Path+'\*.*', FileAttrs, sr) = 0 then
  begin
    repeat
      if (sr.Name<>'') and (sr.Name<>'.') and (sr.Name<>'..') then begin
        if (sr.Attr and faDirectory) = sr.Attr then
          KSPDeleteFolder(Path+'\'+sr.Name) else
        if FileExists(Path+'\'+sr.Name) then DeleteFile(Path+'\'+sr.Name);
      end;
    until FindNext(sr) <> 0;
      FindClose(sr);
  end;

  if DirectoryExists(Path) then
    try
      RmDir(Path)
    except
      ShowMessage(Path);
    end;


end;

procedure ListFolders(Path: string; s: TStringList; OlderThan: integer);
var
  i: integer;
  sr: TSearchRec;
  FileAttrs: Integer;
begin
  FileAttrs := faDirectory;
  if FindFirst(Path+'\*.*', FileAttrs, sr) = 0 then
  begin
    repeat
      if (sr.Name<>'') and (sr.Name<>'.') and (sr.Name<>'..') then begin
        if ((sr.Attr and faDirectory) = sr.Attr) and (DaysBetween(Now, FileDateToDateTime(sr.Time))>OlderThan) then
          s.Add(Path+'\'+sr.Name);
      end;
    until FindNext(sr) <> 0;
      FindClose(sr);
  end;
end;

function IsPlaylist(FileName: string): boolean;
begin
  Result:=(UpperCase(ExtractFileExt(FileName))='.KPL') or
    (UpperCase(ExtractFileExt(FileName))='.M3U') or
    (UpperCase(ExtractFileExt(FileName))='.PLS');
end;

procedure SearchForFiles(Path: string; Rec: boolean; var s: TStringList; DateM: TDateTime); overload;
var
  sr: TSearchRec;
  FileAttrs: Integer;
  s2: TStringList;
  i: integer;
begin
  FileAttrs := faAnyFile;//+faDirectory;
  s2:=TStringList.Create;

    if FindFirst(Path+'\*.*', FileAttrs, sr) = 0 then

    begin
      repeat
        //if (sr.Attr and FileAttrs) = sr.Attr then
        begin
        if (sr.Name<>'') and (sr.Name<>'.') and (sr.Name<>'..') then begin
            //ShowMessage(ExtractFileExt(sr.Name));

            if ((sr.Attr and faDirectory) <> sr.Attr)and
              (FileDateToDateTime(sr.Time)>DateM) then
                s.Add(Path+'\'+sr.Name);

            if Rec and ((sr.Attr and faDirectory) = sr.Attr) then
              s2.Add(Path+'\'+sr.Name);
          end;

        end;
      until FindNext(sr) <> 0;
      FindClose(sr);
    end;

  if s2.Count> 0 then
    for i:=0 to s2.Count-1 do
      SearchForFiles(s2.Strings[i], Rec, s, DateM);

  s2.Free;

end;

procedure SearchForFilesFS(Path: string; Rec: boolean; var s: TStringList); overload;
var
  sr: TSearchRec;
  FileAttrs: Integer;
  s2: TStringList;
  i: integer;
begin
  FileAttrs := faAnyFile;//+faDirectory;
  s2:=TStringList.Create;

    if FindFirst(Path+'\*.*', FileAttrs, sr) = 0 then

    begin
      repeat
        //if (sr.Attr and FileAttrs) = sr.Attr then
        begin
        if (sr.Name<>'') and (sr.Name<>'.') and (sr.Name<>'..') then begin
            //ShowMessage(ExtractFileExt(sr.Name));

            if ((sr.Attr and faDirectory) <> sr.Attr) then
                s.Add(Path+'\'+sr.Name);

            if Rec and ((sr.Attr and faDirectory) = sr.Attr) then
              s2.Add(Path+'\'+sr.Name);
          end;

        end;
      until FindNext(sr) <> 0;
      FindClose(sr);
    end;

  if s2.Count> 0 then
    for i:=0 to s2.Count-1 do
      SearchForFilesFS(s2.Strings[i], Rec, s);

  s2.Free;

end;

function PrepareString(str: string): string;
var
  i: integer;
begin
  Result:='';
  if str='' then Exit;
  Result:=str;

  for i:=Length(Result) downto 1 do
    if Result[i]='''' then System.Insert('''', Result, i);

end;


function DownloadURLi(const aUrl: string; var Output: TStringList): Boolean;
{$IFDEF WINDOWS}
var
  hSession: HINTERNET;
  hService: HINTERNET;
  lpBuffer: array[0..1024 + 1] of Char;
  dwBytesRead: DWORD;
begin
  Result := False;
  // hSession := InternetOpen( 'MyApp', INTERNET_OPEN_TYPE_DIRECT, nil, nil, 0);
  hSession := InternetOpen('MyApp', INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  try
    if Assigned(hSession) then
    begin
      hService := InternetOpenUrl(hSession, PChar(aUrl), nil, 0, 0, 0);
      if Assigned(hService) then
        try
          while True do
          begin
            dwBytesRead := 1024;
            InternetReadFile(hService, @lpBuffer, 1024, dwBytesRead);
            if dwBytesRead = 0 then break;
            lpBuffer[dwBytesRead] := #0;
            Output.Add(lpBuffer);
          end;
          Result := True;
        finally
          InternetCloseHandle(hService);
        end;
    end;
  finally
    InternetCloseHandle(hSession);
  end;
end;
{$ELSE}
begin

end;
{$ENDIF}


function GetKSPVersion(AppPath: TPathChar): ShortString;
begin
  result := KSPMajorVersion;
{$IFDEF KSP_SPECIAL_BUILD}
  Result:=Result+' '+KSPSpecialInfo;
{$ENDIF}
end;

function GetKSPVersion2(AppPath: TPathChar): ShortString;
begin
  Result:=IntToStr(Version)+'.'+
    IntToStr(Major)+'.'+
    IntToStr(Minor)+'.'+
    IntToStr(Build);//GetKSPVersion(AppPath);
end;

end.