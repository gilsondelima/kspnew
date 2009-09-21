{
  $Project$
  $Workfile$
  $Revision$
  $DateUTC$
  $Id$

  This file is part of the Indy (Internet Direct) project, and is offered
  under the dual-licensing agreement described on the Indy website.
  (http://www.indyproject.org/)

  Copyright:
   (c) 1993-2005, Chad Z. Hower and the Indy Pit Crew. All rights reserved.
}
{
  $Log$
}
{
  Rev 1.1    1/25/2004 2:17:52 PM  JPMugaas
  Should work better.  Removed one GPF in S/Key.

  Rev 1.0    11/13/2002 08:00:36 AM  JPMugaas

  PLAIN mechanism
  This is of type TIdSASLUserPass because it needs a username/password,
  additionally it has a LoginAs property - this is the "effective username"
  after connecting, which could be different as your "real" username
  (eg. root logging in as someone else on a unix system)
}

unit IdSASLPlain;

interface
{$i IdCompilerDefines.inc}
uses
  IdSASL,
  IdSASLUserPass;

type
  TIdSASLPlain = class(TIdSASLUserPass)
  protected
    FLoginAs: String;
    procedure InitComponent; override;
  public
    class function ServiceName: TIdSASLServiceName; override;
    function StartAuthenticate(const AChallenge:string) : String; override;
  published
    property LoginAs  : String read FLoginAs write FLoginAs;
  end;

implementation

{ TIdSASLPlain }

procedure TIdSASLPlain.InitComponent;
begin
  inherited InitComponent;

end;

class function TIdSASLPlain.ServiceName: TIdSASLServiceName;
begin
  Result := 'PLAIN';  {Do not translate}
end;

function TIdSASLPlain.StartAuthenticate(const AChallenge: string): String;
var
  fusr, flogas: string;
begin
  fusr := GetUsername;
  flogas := LoginAs;
  if fusr = '' then begin
    fusr := flogas;
  end;
  Result := flogas+#0+fusr+#0+GetPassword;  {Do not translate}
end;

end.