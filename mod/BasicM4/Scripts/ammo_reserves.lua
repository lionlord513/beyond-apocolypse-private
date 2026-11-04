-- PlayerBase owns the reserve shown on the gun HUD. Its map contains a
-- BulletPlayer struct per type. AddBulletToPlayer updates the replicated list.
return function(M,valid,log)
 local R={players={},seen={}}
 local journal=M.gyrocopter.transport.journal
 local game=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local steam=StaticFindObject('/Script/SteamCorePro.Default__SteamUtilities')
 local kind='Type_2_D1852F5542FBC45F942DBAA0973C21D3'
 local amount='NbBullet_7_9635697947FC4A8ADC5190856DA85E1C'
 local function owner(pc)
  if pc:IsLocalPlayerController() then return 'host' end
  if not valid(pc.PlayerState) then return end
  local value=steam:BreakSteamID(steam:GetSteamIdFromPlayerState(pc.PlayerState))
  local id=type(value)=='string' and value or value:ToString()
  if id:match('^%d+$') and #id>=15 and #id<=20 then return 'steam-'..id end
 end
 local function inventory(p)
  local counts={}
  p.MapNbbullet:ForEach(function(k,v)
   local t=k:get();local n=v:get()[amount]
   if type(t)=='number' and type(n)=='number' and n>=0 then counts[t]=n end
  end)
  return counts
 end
 local function restore(p,saved)
  local current=inventory(p)
  for t in pairs(current)do if saved[t]==nil then saved[t]=0 end end
  for t,n in pairs(saved)do
   local delta=n-(current[t]or 0)
   if delta~=0 then p:AddBulletToPlayer({[kind]=t,[amount]=delta}) end
  end
  p:ForceNetUpdate()
 end
 local function encode()
  local rows={'BAR1'}
  for id,types in pairs(R.players)do
   rows[#rows+1]=id
   for t,n in pairs(types)do rows[#rows+1]=('%s %d %d'):format(id,t,n)end
  end
  table.sort(rows);return table.concat(rows,'\n')..'\n'
 end
 local function decode(bytes)
  assert(bytes:sub(1,5)=='BAR1\n','Invalid ammo reserve file')
  local players={}
  for line in bytes:sub(6):gmatch('[^\n]+')do
   local id,t,n=line:match('^([%w%-]+) (%d+) (%d+)$')
   id=id or line:match('^([%w%-]+)$')
   assert(id=='host' or (id and id:match('^steam%-%d+$')),'Invalid reserve owner')
   players[id]=players[id] or {}
   if t then t,n=tonumber(t),tonumber(n);assert(t<=254 and n<=2147483647);players[id][t]=n end
  end
  return players
 end
 local function path(key)return M.statePath('reserves-'..key..'.txt')end
 function R.load(save)
  if R.world or not valid(save)then return end
  local key,world=journal.key(save.SaveGameMetadata)
  world=world or journal.guid(save.SaveGameMetadata.SaveName.Guid)
  if world=='00000000:00000000:00000000:00000000' then return end
  local players={}
  if key then
   local f=io.open(path(key),'rb') or io.open(path(key)..'.bak','rb')
   if f then local s=f:read('*a');f:close();players=decode(s)end
  end
  R.world=world;R.players=players;R.seen={}
 end
 function R.update()
  if not R.world then return end
  for _,pc in ipairs(FindAllOf('PlayerControllerBase_C')or{})do
   local p=valid(pc)and pc.PlayerControlled
   if valid(p)and pc:HasAuthority() and p.IsLoaded and p.IsInitialized then
    local id=owner(pc)
    if id then
     if R.seen[id]~=pc:GetAddress() and R.players[id]then restore(p,R.players[id])end
     R.seen[id]=pc:GetAddress();R.players[id]=inventory(p)
    end
   end
  end
 end
 function R.capture(save)
  if not R.world or not valid(save)or not save:IsA(StaticFindObject('/Script/DriveBeyondHorizons.DBHSaveGame'))then return end
  local key,world=journal.key(save.SaveGameMetadata);if not key or world~=R.world then return end
  R.update()
  local p=path(key);local bytes=encode();local old=io.open(p,'rb')
  if old then local previous=old:read('*a');old:close();if bytes==previous then return end end
  local f=assert(io.open(p..'.tmp','wb'));assert(f:write(bytes));assert(f:close())
  if old then os.remove(p..'.bak');assert(os.rename(p,p..'.bak'))end
  local ok,e=os.rename(p..'.tmp',p);if not ok then if old then os.rename(p..'.bak',p)end;error(e)end
 end
 R.hook={RegisterHook('/Script/DriveBeyondHorizons.DBHHelper:SaveGameToSlotAsyncReal',function(_,s)
  local ok,e=pcall(R.capture,s:get());if not ok then log('Ammo reserve save failed: '..tostring(e))end
 end)}
 function R.reset()R.world=nil;R.players={};R.seen={}end
 return R
end
