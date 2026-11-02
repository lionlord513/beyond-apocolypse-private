-- Append one value before MAX; never renumber any native fluid or widen its net byte.
return function(valid)
 local F={id=6}
 function F.install()
  if F.ready then return true end
  local e=StaticFindObject('/Game/BP/Items/Enums/FluidTypeEnum.FluidTypeEnum')
  local path='/Game/BP/Helper/HelperFunction.HelperFunction_C:GetLocalizedFluidName'
  if not valid(e)or not valid(StaticFindObject(path))then return false end
  local names={};e:ForEachName(function(n,v)names[v]=n:ToString()end)
  if names[6]~='FluidTypeEnum::Nitrous'then
   assert(names[6]=='FluidTypeEnum::FluidTypeEnum_MAX'and names[7]==nil,'Native fluid enum changed; nitrous is disabled to protect saves')
   e:InsertIntoNames('FluidTypeEnum::Nitrous',6,6,true)
  end
  F.hook={RegisterHook(path,function(_,kind,world,name)if kind:get()==6 then name:set(FText('Nitrous'))end end)}
  F.ready=true;return true
 end
 function F.quantity(t)
  if not valid(t)then return 0 end
  return t.FluidMap:Contains(6)and math.max(0,t.FluidMap:Find(6):get())or 0
 end
 function F.set(t,litres,p)
  assert(valid(t)and t:GetOwner():HasAuthority(),'Only the host can change nitrous')
  t:UpdateFluidMap({FluidType_2_3FEF52254C42CACD89BCB090838F9BEB=6,Value_5_22AE2EBC4B5FE6FECBBC58B9FD6C03CC=math.max(0,litres)},true,false,t,true,false,p,true)
 end
 return F
end
