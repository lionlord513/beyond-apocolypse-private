-- Separate, revision-bound ammo records; native actor/item bytes stay native.
return function(root,T,valid,log,statePath)
 local J={ready=false,state={kill={},site={}}}
 local function path(key)local name='ammo-'..key..'.txt';return statePath and statePath(name)or root..'/state/'..name end
 function J.encode(state)
  local rows={'BAM1'}
  for kind,values in pairs(state)do assert(kind=='kill'or kind=='site')
   for key in pairs(values)do assert(type(key)=='string'and #key<=512 and not key:find('%s'));rows[#rows+1]=kind..' '..key end
  end
  table.sort(rows);return table.concat(rows,'\n')..'\n'
 end
 function J.decode(bytes)
  assert(bytes:sub(1,5)=='BAM1\n','Invalid ammo snapshot');local state={kill={},site={}}
  for line in bytes:sub(6):gmatch('[^\n]+')do local kind,key=line:match('^(%w+) (%S+)$')
   assert(state[kind]and #key<=512 and not state[kind][key],'Damaged ammo snapshot');state[kind][key]=true
  end;return state
 end
 function J.load(save)
  if J.ready then return end
  J.ready=true;J.state={kill={},site={}};J.error=nil
  if not valid(save)then return end
  local key,world=T.key(save.SaveGameMetadata);J.world=world;if not key then return end
  local f=io.open(path(key),'rb');if not f then return end
  local bytes=f:read('*a');f:close();local ok,state=pcall(J.decode,bytes)
  if ok then J.state=state else J.error=tostring(state);log('Ammo snapshot rejected: '..J.error)end
 end
 function J.writable()
  assert(J.ready and not J.error,J.error or 'Waiting for native ammo save context')
  local file=root..'/state/ammo-write-check.tmp';local f=assert(io.open(file,'wb'),'Cannot write ammo records');assert(f:write('BAM1\n'));assert(f:close());os.remove(file)
 end
 function J.capture(save)
  if not J.ready or not valid(save)or not save:IsA(StaticFindObject('/Script/DriveBeyondHorizons.DBHSaveGame'))then return end
  assert(not J.error,J.error);local key,world=T.key(save.SaveGameMetadata);assert(key,'Native save has no revision identity')
  if J.world and J.world~=world then return end;J.world=world
  local target=path(key);local bytes=J.encode(J.state);local old=io.open(target,'rb')
  if old then local previous=old:read('*a');old:close();assert(previous==bytes,'Native save reused an ammo revision');return end
  local f=assert(io.open(target..'.tmp','wb'));assert(f:write(bytes));assert(f:close());assert(os.rename(target..'.tmp',target))
 end
 J.hooks={RegisterHook('/Script/DriveBeyondHorizons.DBHHelper:SaveGameToSlotAsyncReal',function(_,save)
  local ok,e=pcall(J.capture,save:get());if not ok then J.error=tostring(e);log('Ammo save error: '..J.error)end
 end)}
 function J.reset()J.ready=false;J.world=nil;J.error=nil;J.state={kill={},site={}}end
 return J
end
