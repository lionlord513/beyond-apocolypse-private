-- Native computer window and product cards, with Hangar-only contents.
return function(A,M,root,valid,enqueue)
 local U={hits={},pendingHits={},history={},greenButtons={},buyCards={},generation=0};local lib=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
 local function new(k,outer)return StaticConstructObject(StaticFindObject('/Script/UMG.'..k),outer)end
 local function fill(slot)slot:SetHorizontalAlignment(0);slot:SetVerticalAlignment(0);return slot end
 local function place(parent,o,x,y,w,h)
  local s=parent:AddChildToCanvas(o);s:SetPosition({X=x,Y=y});s:SetSize({X=w,Y=h});return s
 end
 local function label(parent,t,x,y,w,h,size)
  local o=new('TextBlock',parent);o:SetText(FText(t));local f=o.Font;f.Size=size;o:SetFont(f);o:SetVisibility(3);place(parent,o,x,y,w,h);return o
 end
 local function surface(parent,fn)
  local s=lib:Create(U.pc,LoadAsset('/Game/BP/Garage/PaintStation/UI/ColorElement.ColorElement_C'),U.pc)
  fill(parent:AddChildToOverlay(s));s:SetRenderOpacity(.001);s:SetVisibility(0);s.SelfBaseReference=s;s.Border_47:SetVisibility(0);s.Border_160:SetVisibility(0)
  s:SetCursor(9);s.Border_47:SetCursor(9);s.Border_160:SetCursor(9)
  U.hits[s:GetAddress()]=fn;if U.buildingCards then U.cardHits[#U.cardHits+1]=s:GetAddress()end;return s
 end
 local function cover(button,fn,nativeClick)
  button:SetCursor(9)
  local parent=button:GetParent();local slot=button.Slot;local kind=slot:GetClass():GetFName():ToString();local layout
  if kind=='CanvasPanelSlot'then local d=slot.LayoutData;layout={Offsets={Left=d.Offsets.Left,Top=d.Offsets.Top,Right=d.Offsets.Right,Bottom=d.Offsets.Bottom},Anchors={Minimum={X=d.Anchors.Minimum.X,Y=d.Anchors.Minimum.Y},Maximum={X=d.Anchors.Maximum.X,Y=d.Anchors.Maximum.Y}},Alignment={X=d.Alignment.X,Y=d.Alignment.Y}}end
  button:RemoveFromParent();local o=new('Overlay',U.ui.WidgetTree)
  if layout then parent:AddChildToCanvas(o):SetLayout(layout)else parent:AddChild(o)end
  fill(o:AddChildToOverlay(button))
  if U.greenButtons[button:GetAddress()]then
   button:SetRenderOpacity(0);local bg=new('Image',U.ui.WidgetTree);bg:SetColorAndOpacity({R=.12,G=.52,B=.25,A=1});bg:SetVisibility(3);fill(o:AddChildToOverlay(bg))
   local source=button:GetChildAt(0)
   if valid(source)and source:IsA(StaticFindObject('/Script/UMG.TextBlock'))then local t=new('TextBlock',U.ui.WidgetTree);t:SetText(source:GetText());t:SetFont(source.Font);t:SetVisibility(3);local slot=o:AddChildToOverlay(t);slot:SetHorizontalAlignment(2);slot:SetVerticalAlignment(2)end
  end
  -- Native product buttons receive Slate mouse input directly. A ColorElement
  -- with SelfHitTestInvisible still exposes its child Borders to hit testing.
  if not nativeClick then surface(o,fn)end
 end
 local green={R=.12,G=.52,B=.25,A=1}
 function U.status(text)
  U.message=tostring(text)
  if valid(U.statusText)then U.statusText:SetText(FText(U.message))end
  M.backpack.notify(U.message)
 end
 -- Custom orders use only our existing validated purchase path. Native cards
 -- keep their own purchasing callback and populated ItemIndex.
 function U.purchase(card,alreadyQueued)
  if M.features==false or not valid(card)or not valid(U.hud)then return end
  local order=U.buyCards[card:GetAddress()];if not order or order.queued then return end
  order.queued=true;local function commit()
   if order.generation~=U.generation or U.buyCards[card:GetAddress()]~=order then return end
   local ok,result=pcall(A.buy,order.index);order.queued=false
   if ok then U.history[#U.history+1]=order.index;if #U.history>100 then table.remove(U.history,1)end else U.status(tostring(result):gsub('^.-:%d+: ',''))end
  end
  if alreadyQueued then commit()else enqueue(commit)end
 end
 local function solid(image,color)
  image:SetBrush({DrawAs=1,TintColor={SpecifiedColor=color,ColorUseRule=0}})
 end
 local function buttonGreen(b)
  U.greenButtons[b:GetAddress()]=true
 end
 function U.close()
  if valid(U.ui)then U.ui:RemoveFromParent()end;U.ui=nil;U.hits={};U.pendingHits={};U.cards={};U.greenButtons={};U.buyCards={};U.generation=U.generation+1
  if valid(U.hud)then U.hud:SetVisibility(0);lib:SetInputMode_UIOnlyEx(U.pc,U.hud,0,false)end
 end
 function U.show(category,history)
  local c=U.ui;if not valid(c)then return end
  local scroll=c.GP_ItemContainer:GetParent();scroll:SetClipping(1);c.GP_ItemContainer.Slot:SetPadding({Left=0,Top=8,Right=0,Bottom=24});scroll:SetScrollOffset(0);for i=0,scroll:GetChildrenCount()-1 do local child=scroll:GetChildAt(i);if child:GetAddress()~=c.GP_ItemContainer:GetAddress()then child:SetVisibility(1)end end
  for _,id in ipairs(U.cardHits or{})do U.hits[id]=nil end;U.cardHits={};U.buyCards={};U.buildingCards=true
  U.category=category or U.category or 'gyro';U.historyMode=history==true;c.GP_ItemContainer:ClearChildren();U.cards={}
  local map=U.pc.PlayerControlled.AC_EbaySystem.PrimaryData.Structure;local list={}
  if history then for i=#U.history,1,-1 do list[#list+1]=U.history[i]end
  else for index,item in ipairs(A.items)do if (item.category or 'gyro')==U.category then list[#list+1]=index end end end
  for n,index in ipairs(list)do
   local item=A.items[index];local card=lib:Create(U.pc,LoadAsset('/Game/BP/EbaySystem/HUD_EbayCarItem.HUD_EbayCarItem_C'),U.pc)
   c.GP_ItemContainer:AddChildToUniformGrid(card,math.floor((n-1)/3),(n-1)%3);U.cards[#U.cards+1]=card
   card.BuyMenuRef=U.hud;local price=item.price
   if item.key and map:Contains(FName(item.key))then local d=map:Find(FName(item.key)):get();card.ItemIndex=d;price=d.ItemPrice;card.IMG_ItemIcon:SetBrushFromTexture(d.Icon,false)
   elseif item.iconKey and map:Contains(FName(item.iconKey))then card.IMG_ItemIcon:SetBrushFromTexture(map:Find(FName(item.iconKey)):get().Icon,false)
   else
    U.itemIcons=U.itemIcons or{};local icon=U.itemIcons[item.id]
    if not valid(icon)then icon=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(c,root..'/assets/shop/'..item.id..'.png');U.itemIcons[item.id]=icon end
    if valid(icon)then card.IMG_ItemIcon:SetBrushFromTexture(icon,false)else card.IMG_ItemIcon:SetVisibility(1)end
   end
   card.TB_ItemName:SetText(FText(item.name));card.TB_ItemDesc_1:SetText(FText(item.description or ''));card.TB_Price:SetText(FText(('$%.0f'):format(price or 0)));card.TB_Acheter:SetText(FText('Buy'))
   -- Native card geometry and fonts stay intact; only its pink outline changes.
   local accent=(item.category or 'gyro')=='gyro'and green or {R=.22,G=.48,B=.35,A=1}
   card.Image_217:SetBrush({DrawAs=4,TintColor={SpecifiedColor={R=.035,G=.045,B=.055,A=1},ColorUseRule=0},OutlineSettings={Color={SpecifiedColor=accent,ColorUseRule=0},Width=2,CornerRadii={X=22,Y=22,Z=22,W=22},RoundingType=0}});buttonGreen(card.BT_Buy)
   if history then card.BT_Buy:SetVisibility(1)else
    if item.key then cover(card.BT_Buy,nil,true)else
     U.buyCards[card:GetAddress()]={index=index,generation=U.generation}
     card.BuyMenuRef=nil;card.BT_Buy:SetIsEnabled(false)
     cover(card.BT_Buy,function(queued)U.purchase(card,queued)end,false)
    end
   end
  end
  U.buildingCards=false
 end
 function U.fit()
  if not valid(U.ui)then return end
  local layout=StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary');local size=layout:GetViewportSize(U.pc);local dpi=layout:GetViewportScale(U.pc)
  local scale=math.min(1,(size.X/dpi-32)/1600,(size.Y/dpi-32)/960)
  if U.scale~=scale then U.scale=scale;local c=U.ui.CP_RSPartWindow;c.Slot:SetAnchors({Minimum={X=.5,Y=.5},Maximum={X=.5,Y=.5}});c.Slot:SetPosition({X=-800,Y=-480});c.Slot:SetSize({X=1600,Y=960});c:SetRenderTransformPivot({X=.5,Y=.5});c:SetRenderScale({X=scale,Y=scale})end
 end
 function U.open()
  if valid(U.ui)then U.close();return end
  local c=lib:Create(U.pc,U.hud:GetClass(),U.pc);U.ui=c;c:AddToViewport(10);c:SetVisibility(0);c.MainMenuSwitcher:SetActiveWidget(c.CP_RSPartWindow:GetParent())
  c:BndEvt__HUDBuyMenu_BT_CarPart_K2Node_ComponentBoundEvent_1_OnButtonClickedEvent__DelegateSignature()
  c.CP_HomePanel:SetVisibility(1);c.CP_MainMenu:SetVisibility(1);c.CP_RSPartWindow:SetVisibility(4);U.hud:SetVisibility(1)
  -- Reuse the native window, category buttons, scroll container and close controls.
  local categories=c.BT_Filter_Musgoat:GetParent():GetParent();local a=c.BT_Filter_Musgoat:GetParent();local b=c.BT_Filter_Golf:GetParent();a:RemoveFromParent();b:RemoveFromParent();categories:ClearChildren();categories:AddChild(a);categories:AddChild(b)
  local function rename(o,value)
   if o:IsA(StaticFindObject('/Script/UMG.TextBlock'))then o:SetText(FText(value));local f=o.Font;f.Size=19;o:SetFont(f)
   elseif o:IsA(StaticFindObject('/Script/UMG.PanelWidget'))then for i=0,o:GetChildrenCount()-1 do rename(o:GetChildAt(i),value)end end
  end
  rename(a,'Vehicles and parts');rename(b,'Apocalypse items');buttonGreen(c.BT_Filter_Musgoat);buttonGreen(c.BT_Filter_Golf)
  cover(c.BT_Filter_Musgoat,function()U.show('gyro',false)end);cover(c.BT_Filter_Golf,function()U.show('apocalypse',false)end)
  cover(c.BT_CloseCarWindow,U.close);cover(c.BT_SideCarWindow,U.close);cover(c.BT_Buy,function()U.show(nil,false)end);cover(c.BT_HISTORY,function()U.show(nil,true)end)
  c.BT_FAVORITE:SetVisibility(1);c.IMG_UnderLineFavorite:SetVisibility(1)
  for i=0,c.CP_RSPartWindow:GetChildrenCount()-1 do local o=c.CP_RSPartWindow:GetChildAt(i);local name=o:GetFName():ToString()
   if name=='Image_935'then solid(o,{R=.04,G=.045,B=.065,A=1})
   elseif name=='CanvasPanel_0'then o:SetVisibility(1)
   elseif name=='Image_674'then o:SetVisibility(1)
   elseif name=='Image_756'then solid(o,{R=.075,G=.09,B=.12,A=1});o.Slot:SetSize({X=330,Y=850})end
  end
  local header=new('Image',c.WidgetTree);header:SetColorAndOpacity(green);local slot=place(c.CP_RSPartWindow,header,-767,-440,1534,50);slot:SetAnchors({Minimum={X=.5,Y=.5},Maximum={X=.5,Y=.5}});slot:SetZOrder(1);header:SetVisibility(3)
  c.BT_CloseCarWindow:GetParent().Slot:SetZOrder(3);c.BT_SideCarWindow:GetParent().Slot:SetZOrder(3);c.BT_RSPartWindow.Slot:SetZOrder(2)
  local title=label(c.CP_RSPartWindow,'HANGAR',-710,-432,350,42,25);title.Slot:SetZOrder(2);title.Slot:SetAnchors({Minimum={X=.5,Y=.5},Maximum={X=.5,Y=.5}})
  if valid(U.iconTexture)then
   local logo=new('Image',c.WidgetTree);logo:SetBrushFromTexture(U.iconTexture,false);logo:SetVisibility(3)
   local logoSlot=place(c.CP_RSPartWindow,logo,-757,-436,42,42);logoSlot:SetZOrder(2);logoSlot:SetAnchors({Minimum={X=.5,Y=.5},Maximum={X=.5,Y=.5}})
  end
  U.statusText=label(c.CP_RSPartWindow,U.message or '',-425,368,1160,35,14);U.statusText.Slot:SetZOrder(4);U.statusText.Slot:SetAnchors({Minimum={X=.5,Y=.5},Maximum={X=.5,Y=.5}})
  local box=c.GP_ItemContainer:GetParent():GetParent();box.Slot:SetPosition({X=-440,Y=-304});box.Slot:SetSize({X=1185,Y=664});box:SetHeightOverride(664);box:SetClipping(1)
  U.scale=nil;U.fit();U.show('gyro',false);lib:SetInputMode_UIOnlyEx(U.pc,c,0,false)
 end
 function U.build(hud,pc)
  U.pc=pc;U.hits={};local desktop=hud.BT_CarPart:GetParent():GetParent();local box=new('SizeBox',hud.WidgetTree);box:SetWidthOverride(200);box:SetHeightOverride(200);desktop:AddChildToHorizontalBox(box);U.app=box
  local overlay=new('Overlay',hud.WidgetTree);box:AddChild(overlay);local canvas=new('CanvasPanel',hud.WidgetTree);fill(overlay:AddChildToOverlay(canvas))
  U.iconTexture=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(hud,root..'/assets/hangar.png')
  local image=new('Image',hud.WidgetTree);image:SetBrushFromTexture(U.iconTexture,false);image:SetVisibility(3);place(canvas,image,30,6,140,140);label(canvas,'HANGAR',45,154,155,36,19)
  U.icon=surface(overlay,U.open);U.iconAction=U.open
  if not U.hook then U.hook={RegisterHook('/Game/BP/Garage/PaintStation/UI/ColorElement.ColorElement_C:OnMouseButtonDown',function(ctx,_,mouse)
   if M.features==false then return end;local target=ctx:get();local fn=U.hits[target:GetAddress()]
   if valid(U.icon)and target:GetAddress()==U.icon:GetAddress()then fn=U.open end
   if not fn then return end
   if StaticFindObject('/Script/Engine.Default__KismetInputLibrary'):PointerEvent_GetEffectingButton(mouse:get()).KeyName:ToString()=='LeftMouseButton'then
    local id=target:GetAddress();local pending=U.pendingHits
    if not pending[id]then
     pending[id]=true;local generation=U.generation
     enqueue(function()
      if generation==U.generation then local ok,e=pcall(fn,true);if not ok then M.backpack.notify(tostring(e))end end
      pending[id]=nil
     end)
    end
   end
   return lib:Handled()
  end)}end
  -- Commit this HUD only after all widgets and public callbacks are ready.
  U.hud=hud
 end
 function U.tick(hud,pc)
  if not valid(hud.BT_CarPart)or not valid(hud.WidgetTree)then return end
  if not valid(U.hud)or U.hud:GetAddress()~=hud:GetAddress()or not valid(U.pc)or U.pc:GetAddress()~=pc:GetAddress()or not valid(U.icon)then
   U.reset();local ok,e=pcall(U.build,hud,pc);if not ok then U.reset();local message=tostring(e);if U.buildError~=message then U.buildError=message;M.backpack.notify('Hangar is loading: '..message)end;return end;U.buildError=nil
  end
  if valid(U.ui)then U.fit();if not hud:IsInViewport()then U.close()end end
 end
 function U.reset()if valid(U.ui)then U.ui:RemoveFromParent()end;if valid(U.app)then U.app:RemoveFromParent()end;U.ui=nil;U.app=nil;U.hud=nil;U.pc=nil;U.icon=nil;U.hits={};U.pendingHits={};U.history={};U.buyCards={};U.generation=U.generation+1 end
 return U
end
