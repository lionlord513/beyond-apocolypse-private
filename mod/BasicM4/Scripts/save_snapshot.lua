-- DBH can create a named save with a zero revision GUID. That file may be
-- overwritten. A numbered revision stays immutable and belongs to one save.
local function activeSave(save)
 local engine=FindFirstOf('GameEngine')
 if not engine or not engine:IsValid()or not engine.GameViewport:IsValid()then return false end
 local game=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local pc=game:GetPlayerController(engine.GameViewport,0)
 if not pc or not pc:IsValid()or not pc:HasAuthority()then return false end
 local active=game:GetGameInstance(pc).MainSaveGame
 if not active or not active:IsValid()then return false end
 local a,b=active.SaveGameMetadata.SaveName.Guid,save.SaveGameMetadata.SaveName.Guid
 return active:GetAddress()==save:GetAddress()or (a.A==b.A and a.B==b.B and a.C==b.C and a.D==b.D)
end
local function read(path)
 local f=io.open(path,'rb')or io.open(path..'.bak','rb')
 if not f then return end
 local bytes=f:read('*a');f:close();return bytes
end
local function commit(path,key,bytes)
 local previous=read(path)
 if previous==bytes then return end
 if previous then assert(key:find('-'..string.rep('0',32)..'-',1,true),'Native save reused a revision with different records')end
 local f=assert(io.open(path..'.tmp','wb'));assert(f:write(bytes));assert(f:close())
 local old=io.open(path,'rb')
 if old then old:close();os.remove(path..'.bak');assert(os.rename(path,path..'.bak'))end
 local ok,err=os.rename(path..'.tmp',path)
 if not ok then if old then os.rename(path..'.bak',path)end;error(err)end
end
return {active=activeSave,read=read,commit=commit}
