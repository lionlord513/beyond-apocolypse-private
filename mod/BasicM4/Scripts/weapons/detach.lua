return function(M,R,valid)
 local J=R.journal;local game=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local function guid(s)local t={};for v in s:gmatch('%x+')do t[#t+1]=tonumber(v,16)end;return {A=t[1],B=t[2],C=t[3],D=t[4]}end
 function R.attachments(id)
  local names={};if J.state.light[id]then names[#names+1]='Flashlight'end;if J.state.scope[id]then names[#names+1]='2x sight'end;return table.concat(names,', ')
 end
 function R.detach(gun,pc)
  assert(gun:HasAuthority()and pc:HasAuthority()and R.definition(gun),'Choose a rifle');J.writable()
  local id=assert(M.guid(gun));local old={light=J.state.light[id],scope=J.state.scope[id]};local made={}
  assert(old.light or old.scope,'No attachments fitted')
  local ok,e=pcall(function()
   for _,kind in ipairs({'light','scope'})do local row=old[kind];if row then
    local path=kind=='light'and '/Game/BP/Items/Movable/ActivableInHand/LampeTorche.LampeTorche_C'or '/Game/BP/Items/Movable/Binocular/Binocular.Binocular_C'
    local cls=LoadAsset(path);assert(valid(cls),'Attachment model unavailable')
    local q=pc.PlayerControlled:K2_GetActorLocation();local forward=pc.PlayerControlled:GetActorForwardVector()
    local tr={Translation={X=q.X+forward.X*85,Y=q.Y+forward.Y*85+#made*25,Z=q.Z-10},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
    local a=game:BeginDeferredActorSpawnFromClass(pc,cls,tr,2,nil,0);assert(valid(a),'No room to remove attachments');made[#made+1]=a
    game:FinishSpawningActor(a,tr,0);a.GuidUnique=guid(row[1])
    if kind=='scope'then R.optic.markItem(a)end
   end end
   J.state.light[id]=nil;J.state.scope[id]=nil;R.update(gun,R.definition(gun))
  end)
  if not ok then
   J.state.light[id]=old.light;J.state.scope[id]=old.scope
   for _,a in ipairs(made)do if valid(a)then a:K2_DestroyActor()end end
   error(e)
  end
  return made,old
 end
end
