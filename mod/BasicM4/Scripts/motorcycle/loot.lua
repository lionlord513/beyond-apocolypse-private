-- Re-skin a very rare native POI Caddie in place. No additional vehicle,
-- actor deletion, spawn-table rewrite or client-owned world mutation.
return function(B,M,valid,log)
 local L={checked={}}
 function L.variant(key)
  local n=2166136261
  for i=1,#key do n=((n~key:byte(i))*16777619)&0xffffffff end
  local roll=n%128
  return roll==0 and 'classic'or roll==1 and 'suzuki'or nil
 end
 function L.consider(a,p,key)
  if not key or L.checked[key]or B.known[key]or not p:HasAuthority()or not a:HasAuthority()then return end
  if a['From Level Spawn']~=true or a.FromSaveVar or valid(a.Driver)then return end
  local game=StaticFindObject('/Script/Engine.Default__GameplayStatics')
  local instance=game:GetGameInstance(p);if not valid(instance)or instance.IsSaving then return end
  local state={};a:GetInitializationState(state);if not state.Initialized then return end
  local at=a:K2_GetActorLocation();local site=false
  for _,q in ipairs(M.apocalypse.locations or{})do local v=q.pos
   if (at.X-v.X)^2+(at.Y-v.Y)^2<4500^2 then site=true;break end
  end
  if not site then return end
  local gs=game:GetGameState(p);if not valid(gs)then return end
  local near=false
  gs.Players:ForEach(function(_,v)local player=v:get();if valid(player)then local q=player:K2_GetActorLocation()
   if (at.X-q.X)^2+(at.Y-q.Y)^2<10000^2 then near=true end
  end end)
  if near then return end
  local variant=L.variant(key)
  if not variant then L.checked[key]=true;return end
  local ok,r=pcall(B.adopt,a,true,variant)
  if ok and r then L.checked[key]=true;log('Rare native POI vehicle: '..variant)
  elseif not ok then log('Motorcycle loot deferred: '..tostring(r))end
 end
 function L.reset()L.checked={}end
 return L
end
