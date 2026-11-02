-- An immutable sidecar for each native save revision. Never load a world's
-- newest record when the player selects an older save. No native actor data is
-- copied or serialized by Lua; vehicles/parts remain the game's responsibility.
return function(root,valid,log,statePath)
 local J={state={},ready=false};local kinds={light=2,scope=1,scopeItem=0}
 local function guid(g)return ('%08x:%08x:%08x:%08x'):format(g.A&0xffffffff,g.B&0xffffffff,g.C&0xffffffff,g.D&0xffffffff)end
 local function isguid(s)return type(s)=='string'and #s==35 and s:match('^%x+:%x+:%x+:%x+$')~=nil end
 local function key(meta)
  local s=meta.SaveName;local world,revision=guid(s.Guid),guid(s.GuidUnique)
  if world=='00000000:00000000:00000000:00000000'or revision=='00000000:00000000:00000000:00000000'then return end
  return world:gsub(':','')..'-'..revision:gsub(':','')..'-'..tostring(s.Iterator),world
 end
 local function path(k)local name='weapon-light-'..k..'.txt';return statePath and statePath(name)or root..'/state/'..name end
 function J.empty()return {light={},scope={},scopeItem={}}end
 function J.encode(state)
  local lines={'BWL1'}
  for kind,n in pairs(kinds)do for id,v in pairs(state[kind]or{})do
   assert(isguid(id),'Invalid weapon light identity')
   local row=kind..' '..id
   if n==3 then assert(type(v)=='number'and v>=25 and v<=5000);row=row..' '..('%.6f'):format(v)
   else
    if n>0 then assert(isguid(v[1]));row=row..' '..v[1]end
    if n>1 then assert(v[2]==1 or v[2]==2);row=row..' '..v[2]end
   end
   lines[#lines+1]=row
  end end
  table.sort(lines);return table.concat(lines,'\n')..'\n'
 end
 function J.decode(s)
  assert(s:sub(1,5)=='BWL1\n','Invalid weapon light snapshot');local state=J.empty()
  for line in s:sub(6):gmatch('[^\n]+')do
   local words={};for w in line:gmatch('%S+')do words[#words+1]=w end
   local kind,id=words[1],words[2];local n=kinds[kind]
   assert(n and #words==(n==3 and 3 or n+2) and isguid(id),'Damaged weapon light snapshot')
   assert(not state[kind][id],'Duplicate weapon light snapshot entry')
   if n==3 then local mass=tonumber(words[3]);assert(mass and mass>=25 and mass<=5000);state[kind][id]=mass
   elseif n==0 then state[kind][id]=true else
    assert(isguid(words[3]));local side=tonumber(words[4]);if n==2 then assert(side==1 or side==2)end
    state[kind][id]={words[3],side}
   end
  end
  return state
 end
 function J.load(save)
  if J.ready then return end
  J.state=J.empty();J.ready=true;J.loadKey=nil;J.error=nil
  if not valid(save)then return end
  local k,world=key(save.SaveGameMetadata);J.world=world;J.loadKey=k
  if not k then return end
  local f=io.open(path(k),'rb');if not f then return end;local bytes=f:read('*a');f:close()
  local ok,result=pcall(J.decode,bytes)
  if ok then J.state=result;log('Weapon light loaded native save revision '..k)
  else J.error=tostring(result);log('Weapon light snapshot rejected; original actors left recoverable: '..J.error)end
 end
 function J.writable()
  assert(J.ready and not J.error,J.error or 'Waiting for native save inventory')
  local file=root..'/state/weapon-light-write-check.tmp';local f=assert(io.open(file,'wb'),'Cannot write weapon light save records')
  assert(f:write('BWL1\n'));assert(f:close());os.remove(file)
 end
 function J.capture(save)
  if not J.ready or not valid(save)or not save:IsA(StaticFindObject('/Script/DriveBeyondHorizons.DBHSaveGame'))then return end
  assert(not J.error,J.error)
  local k,world=key(save.SaveGameMetadata);if not k then error('Native save has no revision identity')end
  if J.world and J.world~=world then return end
  J.world=world;local bytes=J.encode(J.state);local target=path(k)
  local existing=io.open(target,'rb')
  if existing then local old=existing:read('*a');existing:close();assert(old==bytes,'Native save reused a weapon light revision; refusing to overwrite an older record');return end
  local f=assert(io.open(target..'.tmp','wb'));assert(f:write(bytes));assert(f:close())
  assert(os.rename(target..'.tmp',target));J.savedKey=k;log('Weapon light snapshot saved '..k)
 end
 function J.install()
  if J.hooks then return end
  -- The game uses its own async save helper, not GameplayStatics' save node.
  J.hooks={RegisterHook('/Script/DriveBeyondHorizons.DBHHelper:SaveGameToSlotAsyncReal',function(_,save)
   local ok,e=pcall(J.capture,save:get());if not ok then J.error=tostring(e);log('Weapon light save error: '..J.error)end
  end)}
 end
 function J.reset()J.ready=false;J.world=nil;J.state=J.empty();J.error=nil;J.loadKey=nil end
 J.guid=guid;J.key=key;J.state=J.empty();J.install();return J
end
