-- Colour only nitrous rows; ordinary fuel and warning colours remain native.
return function(N,valid)
 local P={};local blue={R=.08,G=.42,B=1,A=1};local purple={R=.62,G=.16,B=1,A=1}
 local function row(w,color)
  if not valid(w)or w['Fluid Type']~=6 then return end
  local slate={SpecifiedColor=color,ColorUseRule=0}
  if valid(w.PercentageTextBlock)then w.PercentageTextBlock:SetColorAndOpacity(slate)end
  if valid(w.FuildTypeTextBlock)then w.FuildTypeTextBlock:SetColorAndOpacity(slate)end
 end
 function P.install()
  local path='/Game/UI/Inputs/WBP_OnFocusElement.WBP_OnFocusElement_C:SetFluidElement'
  if not P.rowHook and valid(StaticFindObject(path))then P.rowHook={RegisterHook(path,function(ctx,kind)
   if kind:get()==6 then row(ctx:get(),blue)end
  end)}end
  path='/Game/UI/Inputs/WBP_OnFocus.WBP_OnFocus_C:SetItemTank'
  if not P.tankHook and valid(StaticFindObject(path))then P.tankHook={RegisterHook(path,function(ctx,tank)
   local w,t=ctx:get(),tank:get();if not valid(w)or not valid(t)then return end
   local d=N.info(t:GetOwner());local color=d and d.tier==2 and purple or blue
   if valid(w.ProgressBar)then w.ProgressBar:SetFillColorAndOpacity(d and color or {R=1,G=1,B=1,A=1})end
   local rows=w.VerticalBoxFluidMap
   if valid(rows)then for i=0,rows:GetChildrenCount()-1 do row(rows:GetChildAt(i),color)end end
  end)}end
  return P.rowHook and P.tankHook
 end
 return P
end
