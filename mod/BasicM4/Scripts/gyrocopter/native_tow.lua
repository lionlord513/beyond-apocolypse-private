-- Native AVS towing only. Custom transport docking has its own hold path.
-- Keep native hitch replication, articulation, mass and manual release intact.
return function(G,valid)
 local N={}
 local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
 function N.active(a)
  for _,name in ipairs({'Vehicle_Hitch_Front','Vehicle_Hitch_Back'})do local h=a[name]
   if valid(h)and h.isHitched and same(h.TrailerHitch,h)and valid(h.TowHitch)and
    valid(h.TowHitch.ParentVehicle)and not same(h.TowHitch.ParentVehicle,a)then return true end
  end
  return false
 end
 function N.restore(r)
  local s=r.nativeTow
  -- Restore a locally borrowed setting even if native ownership changed while
  -- hitched. Observers that never borrowed damping have no snapshot to write.
  if s and valid(s.mesh)then
   s.mesh:SetAngularDamping(s.angular);s.mesh:SetLinearDamping(s.linear)
  end
  r.nativeTow=nil;r.towed=nil
 end
 function N.hold(r,now)
  local a=r.actor
  if not N.active(a)then if r.towed then N.restore(r)end;return false end
  r.towed=true;r.result=nil;r.throttle=0
  -- Native input callbacks must not resurrect cached flight forces.
  a.RotorThrust=0;a.RotorInput=0;a.BoostForce=0;a.BoostInput=0
  a.AirPitchInput=0;a.AirRollInput=0;a.AirYawInput=0
  if G.simulates(a)then
   local ok,e=pcall(function()
   if not r.nativeTow then local mesh=a.VehicleMesh
    r.nativeTow={mesh=mesh,angular=mesh:GetAngularDamping(),linear=mesh:GetLinearDamping()}
    mesh:SetAngularDamping(math.max(r.nativeTow.angular,2.5))
    mesh:SetLinearDamping(math.max(r.nativeTow.linear,.15))
   end
   a:SetThrottleInput(0)
   end)
   if not ok then N.restore(r);error(e)end
  end
  -- Ground transport is not rotor-driven flight or a flight damage event.
  -- The existing visual/audio systems remain active in the controller.
  return true
 end
 return N
end
