-- Preserve the native hitch, articulation, replication and manual Unhitch path.
return function(M,valid,enqueue,log)
 local T={nextAt=0,hooks={},ready=false}
 function T.protect(h)
  if M.features==false or not valid(h)or not valid(h.HitchConstraint)then return end
  h.HitchConstraint:SetLinearBreakable(false,0)
  h.HitchConstraint:SetAngularBreakable(false,0)
 end
 function T.tick()
  if T.ready or M.features==false or os.clock()<T.nextAt then return end
  T.nextAt=os.clock()+1
  local cls=FindObject('BlueprintGeneratedClass','Vehicle_Hitch_C');if not valid(cls)then return end
  local base=cls:GetFullName():gsub('^%S+ ','')..':'
  for _,event in ipairs({'CreateHitchConstraint','ApplyHitchConstraint','HitchAnimationFinished','ApplyHitchFromNetwork'})do
   if not T.hooks[event]and valid(StaticFindObject(base..event))then
    T.hooks[event]={RegisterHook(base..event,function(ctx)
     local h=ctx:get();enqueue(function()T.protect(h)end)
    end)}
   end
  end
  if not T.hooks.CreateHitchConstraint then return end
  for _,h in ipairs(FindAllOf('Vehicle_Hitch_C')or{})do T.protect(h)end
  T.ready=true
 end
 function T.reset()T.ready=false;T.nextAt=0 end
 return T
end
