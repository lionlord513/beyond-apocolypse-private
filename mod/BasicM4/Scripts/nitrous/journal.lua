-- Bottle variants and rare loot belong to the exact native save revision.
-- Quantities stay in native ItemTankComponent bytes, including inventory/parcel saves.
return function(root,T,valid,log,statePath)
 local J={ready=false,state={bottle={},site={}}}
 local function path(k)return statePath('nitrous-'..k..'.txt')end
 local function guid(s)return type(s)=='string'and #s==35 and s:match('^%x+:%x+:%x+:%x+$')end
 function J.encode(state)
  local rows={'BAN1'}
  for k,v in pairs(state.bottle)do assert(guid(k)and type(v)=='number'and v>=1 and v<=6 and v%1==0);rows[#rows+1]='bottle '..k..' '..v end
  for k in pairs(state.site)do assert(type(k)=='string'and #k<=512 and not k:find('%s'));rows[#rows+1]='site '..k end
  table.sort(rows);return table.concat(rows,'\n')..'\n'
 end
 function J.decode(bytes)
  assert(bytes:sub(1,5)=='BAN1\n','Invalid nitrous snapshot');local state={bottle={},site={}}
  for line in bytes:sub(6):gmatch('[^\n]+')do
   local k,v=line:match('^bottle (%S+) (%d+)$');v=tonumber(v)
   if k then assert(guid(k)and v>=1 and v<=6 and not state.bottle[k]);state.bottle[k]=v
   else k=line:match('^site (%S+)$');assert(k and #k<=512 and not state.site[k],'Damaged nitrous snapshot');state.site[k]=true end
  end;return state
 end
 function J.load(save)
  if J.ready then return end;J.ready=true;J.state={bottle={},site={}};J.error=nil
  if not valid(save)then return end;local k,world=T.key(save.SaveGameMetadata);J.world=world;if not k then return end
  local f=io.open(path(k),'rb');if not f then return end;local bytes=f:read('*a');f:close()
  local ok,s=pcall(J.decode,bytes);if ok then J.state=s else J.error=tostring(s);log('Nitrous snapshot rejected: '..J.error)end
 end
 function J.writable()assert(J.ready and not J.error,J.error or 'Waiting for native nitrous save context')end
 function J.capture(save)
  if not J.ready or not valid(save)or not save:IsA(StaticFindObject('/Script/DriveBeyondHorizons.DBHSaveGame'))then return end
  J.writable();local k,world=T.key(save.SaveGameMetadata);assert(k,'Native save has no revision identity')
  if J.world and J.world~=world then return end;J.world=world
  local target=path(k);local bytes=J.encode(J.state);local old=io.open(target,'rb')
  if old then local before=old:read('*a');old:close();assert(before==bytes,'Native save reused a nitrous revision');return end
  local f=assert(io.open(target..'.tmp','wb'));assert(f:write(bytes));assert(f:close());assert(os.rename(target..'.tmp',target))
 end
 J.hooks={RegisterHook('/Script/DriveBeyondHorizons.DBHHelper:SaveGameToSlotAsyncReal',function(_,save)
  local ok,e=pcall(J.capture,save:get());if not ok then J.error=tostring(e);log('Nitrous save error: '..J.error)end
 end)}
 function J.reset()J.ready=false;J.world=nil;J.error=nil;J.state={bottle={},site={}}end
 return J
end
