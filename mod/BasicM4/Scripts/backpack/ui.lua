-- Inventory overlay, using native item icons and viewport-widget coordinates.
return function(B,root,H,valid)
 local U={opened=false,cells={}};local N=B.native;local lib,layout,slate
 local colors={bg={R=.018,G=.02,B=.022,A=.97},card={R=.045,G=.048,B=.05,A=1},quick={R=.063,G=.068,B=.071,A=1},gold={R=.42,G=.44,B=.43,A=1},accent={R=.28,G=.30,B=.29,A=1},text={R=.83,G=.84,B=.82,A=1},muted={R=.46,G=.49,B=.48,A=1},edge={R=.14,G=.15,B=.15,A=1}}
 local function new(c)return StaticConstructObject(StaticFindObject('/Script/UMG.'..c),U.tree)end
 local function place(o,x,y,w,h)local s=U.canvas:AddChildToCanvas(o);s:SetPosition({X=x*U.scale,Y=y*U.scale});s:SetSize({X=w*U.scale,Y=h*U.scale});o:SetVisibility(3);return o end
 local function rect(x,y,w,h,c)local o=new('Image');o:SetColorAndOpacity(colors[c]);return place(o,x,y,w,h)end
 local function text(t,x,y,w,h,size,c)local o=new('TextBlock');o:SetText(FText(t));local f=o.Font;f.Size=math.max(10,math.floor(size*U.scale));o:SetFont(f);o:SetColorAndOpacity({SpecifiedColor=colors[c or'text'],ColorUseRule=0});return place(o,x,y,w,h)end
 local function title(d)
  return N.title(d)
 end
 local function pointer(p)
  -- Keep this conversion native: FGeometry loses its opaque fields in Lua.
  -- Mouse events, polling and drag ghosts must share viewport-widget units.
  local pixel,q={},{};slate:AbsoluteToViewport(U.pc,p or layout:GetMousePositionOnPlatform(),pixel,q);return q
 end
 function U.close()
  U.opened=false;U.drag=nil;U.windowDrag=nil;U.ghost=nil
  if valid(U.widget)then U.widget:RemoveFromParent()end
  if U.blocked and valid(U.pc)then
   U.pc:SetIgnoreLookInput(false);U.pc:SetIgnoreMoveInput(false)
   if valid(U.pawn)then U.pawn:EnableInput(U.pc)end
   U.pc.bShowMouseCursor=U.oldCursor or false;lib:SetInputMode_GameOnly(U.pc,true)
   if valid(U.menu)then U.menu.CanOpenPauseMenu=U.oldPause end
  end
  U.blocked=false;U.widget=nil;U.canvas=nil;U.tree=nil;U.cells={};U.bag=nil
 end
 function U.render()
  U.root:ClearChildren();U.cells={};U.ghost=nil
  local vp=layout:GetViewportSize(U.pc);local dpi=layout:GetViewportScale(U.pc)
  U.scale=math.min(1,vp.X/1280,vp.Y/800)/dpi
  local tier=N.tier(U.bag);local data=N.data(U.bag)
  U.width=484;U.height=176+math.ceil(tier.cells/6)*72
  U.vw=vp.X/dpi;U.vh=vp.Y/dpi
  U.x=U.x or(U.vw-U.width*U.scale)*.82;U.y=U.y or(U.vh-U.height*U.scale)*.4
  U.canvas=new('CanvasPanel');U.canvas:SetVisibility(4)
  U.windowSlot=U.root:AddChildToCanvas(U.canvas);U.windowSlot:SetSize({X=U.width*U.scale,Y=U.height*U.scale});U.position(U.x,U.y)
  rect(0,0,U.width,U.height,'edge');rect(1,1,U.width-2,U.height-2,'bg');rect(1,3,U.width-2,45,'card')
  text(tier.name:upper(),16,12,350,28,18);text('x',450,10,25,30,20,'muted')
  text('INVENTORY  /  '..tier.hotbar..' QUICK SLOTS',16,54,450,22,11,'muted')
  U.cells.close={x=438,y=3,w=46,h=45};U.cells.title={x=0,y=3,w=438,h=45}
  local element=FindObject('WidgetBlueprintGeneratedClass','WBP_Inventory_Elementary_C')
  for k=0,tier.cells-1 do
   local x,y=16+(k%6)*76,82+math.floor(k/6)*72
   rect(x,y,72,68,'edge');rect(x+1,y+1,70,66,k<tier.hotbar and'quick'or'card')
   if k<tier.hotbar then rect(x,y,72,2,'gold')end
   if k<tier.hotbar then text(tostring(k+1),x+4,y+2,23,16,10,'muted')end
   local d=data[k];local token=N.token(d);local art
   if d then
    N.title(d,U.bag,k)
    local saved=d;if type(d)=='table'and d._token then saved=d.native end
    if valid(element)and saved then
     local icon=lib:Create(U.pc,element,U.pc);place(icon,x+8,y+12,56,37);icon:SetActorSave(saved)
     if valid(icon.ItemIcon)then
      art=icon.ItemIcon;art:RemoveFromParent();place(art,x+8,y+12,56,37);art:SetColorAndOpacity({R=1,G=1,B=1,A=1});art:SetRenderOpacity(1);icon:RemoveFromParent()
     end
     if valid(icon.IconInputAction)then icon.IconInputAction:SetVisibility(1)end
     if valid(icon.SlotIndexText)then icon.SlotIndexText:SetVisibility(1)end
    end
    local custom=N.icon and N.icon(d,U.pc);if valid(custom)then if not valid(art)then art=new('Image');place(art,x+8,y+12,56,37)end;art:SetBrushFromTexture(custom,false)end
    local name=title(d);text(#name>11 and name:sub(1,10)..'..'or name,x+4,y+51,68,16,10)
   end
   U.cells[k]={x=x,y=y,w=72,h=68,token=token,name=d and title(d)or'Empty cell',art=art,attachments=d and N.attachments(d,U.bag,k)or ''}
  end
  local handY=88+math.ceil(tier.cells/6)*72
  rect(16,handY,452,35,'card');text('HANDS',25,handY+9,62,20,11,'muted')
  local h=N.held(U.pc);local name=h and N.heldTitle(h)or'Empty - drag here to retrieve'
  text(name,90,handY+8,369,23,12)
  U.cells.hand={x=16,y=handY,w=452,h=35,token=h and B.guid(h)or'-',name=name}
  text('Drag outside to drop  |  Tab / Esc close',16,handY+43,452,20,11,'muted')
  U.status=text(B.message or'One item per cell.',16,handY+65,452,20,11)
  U.inspectBg=rect(-232,82,220,170,'card');U.inspectIcon=new('Image');place(U.inspectIcon,-212,94,176,70)
  U.inspectName=text('',-218,168,196,22,13);U.inspectParts=text('',-218,191,196,36,11,'muted');U.inspectAction=text('MMB: remove attachments',-218,226,202,20,11)
  for _,w in ipairs({U.inspectBg,U.inspectIcon,U.inspectName,U.inspectParts,U.inspectAction})do w:SetVisibility(1)end

  -- Preserve the native widget's own tree so Slate dispatches its mouse overrides.
  U.surface=lib:Create(U.pc,LoadAsset('/Game/BP/Garage/PaintStation/UI/ColorElement.ColorElement_C'),U.pc)
  -- Full viewport catches release outside the bag even when Slate declines capture.
  U.surface.SelfBaseReference=U.surface;local surfaceSlot=U.root:AddChildToCanvas(U.surface);surfaceSlot:SetPosition({X=0,Y=0});surfaceSlot:SetSize({X=U.vw,Y=U.vh});U.surface:SetVisibility(0);U.surface:SetRenderOpacity(.001)
  U.surface.Border_47:SetVisibility(0);U.surface.Border_160:SetVisibility(0)
  U.fingerprint=U.signature()
 end
 function U.signature()
  local parts={};for k,d in pairs(N.data(U.bag))do parts[#parts+1]=k..':'..N.token(d)end;table.sort(parts)
  local h=N.held(U.pc);parts[#parts+1]=h and B.guid(h)or'-';return table.concat(parts,';')
 end
 function U.open(b)
  U.pc=H.GetPlayerController();U.pawn=U.pc:K2_GetPawn();U.bag=b;U.oldCursor=U.pc.bShowMouseCursor
  lib=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary');layout=StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary');slate=StaticFindObject('/Script/UMG.Default__SlateBlueprintLibrary')
  U.widget=lib:Create(U.pc,StaticFindObject('/Script/UMG.UserWidget'),U.pc);U.tree=U.widget.WidgetTree
  if not valid(U.tree)then U.tree=StaticConstructObject(StaticFindObject('/Script/UMG.WidgetTree'),U.widget);U.widget.WidgetTree=U.tree end
  U.root=new('CanvasPanel');U.tree.RootWidget=U.root;U.widget:SetVisibility(4);U.root:SetVisibility(4);U.widget:AddToViewport(9500);U.render()
  if not U.hooks then
   U.hooks={}
   for _,event in ipairs({'OnMouseButtonDown','OnMouseButtonUp'})do
    local path='/Game/BP/Garage/PaintStation/UI/ColorElement.ColorElement_C:'..event
    U.hooks[#U.hooks+1]={RegisterHook(path,function(ctx,geometry,mouse)
     if not U.opened or not valid(U.widget)or not valid(U.surface)or ctx:get():GetAddress()~=U.surface:GetAddress()then return end
     local input=StaticFindObject('/Script/Engine.Default__KismetInputLibrary')
     local button=input:PointerEvent_GetEffectingButton(mouse:get()).KeyName:ToString();if button~='LeftMouseButton'and button~='MiddleMouseButton'then return lib:Handled()end
     local q=pointer(input:PointerEvent_GetScreenSpacePosition(mouse:get()))
     if button=='MiddleMouseButton'then
      if event=='OnMouseButtonDown'and not B.pending then local k=U.hit(q);if type(k)=='number'and U.cells[k].attachments~=''then
       local ok,e=pcall(N.request,U.bag,'detach',k,-1);if not ok then B.message=tostring(e)end
      end end;return lib:Handled()
     end
     if event=='OnMouseButtonDown'then U.press(q);if U.opened then return lib:CaptureMouse(lib:Handled(),U.surface)end
     else U.release(q);return lib:ReleaseMouseCapture(lib:Handled())end
     return lib:Handled()
    end)}
   end
  end
  U.blocked=true;U.pc:SetIgnoreLookInput(true);U.pc:SetIgnoreMoveInput(true);U.pawn:DisableInput(U.pc)
  U.menu=H.GetMenuComponent(U.pc);if valid(U.menu)then U.oldPause=U.menu.CanOpenPauseMenu;U.menu.CanOpenPauseMenu=false end
  U.pc.bShowMouseCursor=true;lib:SetInputMode_UIOnlyEx(U.pc,U.widget,0,true);U.opened=true
 end
 function U.position(x,y)
  U.x=math.max(0,math.min(x,math.max(0,U.vw-U.width*U.scale)))
  U.y=math.max(0,math.min(y,math.max(0,U.vh-U.height*U.scale)))
  U.windowSlot:SetPosition({X=U.x,Y=U.y})
 end
 function U.moveWindow(q)
  if U.windowDrag then U.position(q.X-U.windowDrag.x,q.Y-U.windowDrag.y)end
 end
 function U.frame()
  if not U.opened or not(U.drag or U.windowDrag)then return end
  local q=pointer()
  if U.windowDrag then U.moveWindow(q)end
  if valid(U.ghost)then U.ghost.Slot:SetPosition({X=q.X-28*U.scale,Y=q.Y-18*U.scale})end
 end
 local function endDrag()
  if U.drag then local cell=U.cells[U.drag.key];if cell and valid(cell.art)then cell.art:SetVisibility(3)end end
  if valid(U.ghost)then U.ghost:RemoveFromParent()end;U.ghost=nil
 end
 function U.hit(q)
  q=q or pointer();local x,y=(q.X-U.x)/U.scale,(q.Y-U.y)/U.scale
  for k,c in pairs(U.cells)do if x>=c.x and x<c.x+c.w and y>=c.y and y<c.y+c.h then return k end end
 end
 function U.press(q)
  if not U.opened or B.pending then return end
  local k=U.hit(q);if k=='close'then U.close();return end
  if k=='title'then U.windowDrag={x=q.X-U.x,y=q.Y-U.y};return end
  if k~=nil and U.cells[k].token~='-'then
   U.drag={key=k,token=U.cells[k].token};B.message='Release on a cell, hands, or outside to drop.';U.status:SetText(FText(B.message))
   local art=U.cells[k].art
   if valid(art)then
    U.ghost=new('Image');U.ghost:SetBrush(art.Brush);U.ghost:SetVisibility(3)
    local slot=U.root:AddChildToCanvas(U.ghost);slot:SetSize({X=56*U.scale,Y=37*U.scale});slot:SetZOrder(20)
    art:SetVisibility(1);U.frame()
   end
  end
 end
 function U.release(q)
  if U.windowDrag then U.moveWindow(q);U.windowDrag=nil;return end
  local drag=U.drag;endDrag();U.drag=nil;if not drag or not U.opened then return end
  local target=U.hit(q)
  local x,y=(q.X-U.x)/U.scale,(q.Y-U.y)/U.scale
  local outside=x<0 or y<0 or x>=U.width or y>=U.height
  if not outside and(target==nil or target=='close'or target=='title'or target==drag.key)then return end
  local now=U.signature();if now~=U.fingerprint then B.message='Inventory changed; try again';U.render();return end
  local ok,e=pcall(function()
   if outside then N.request(U.bag,drag.key=='hand'and'drophand'or'drop',drag.key=='hand'and -1 or drag.key,-1)
   elseif drag.key=='hand'then assert(type(target)=='number','Choose a storage cell');N.request(U.bag,'put',-1,target)
   elseif target=='hand'then N.request(U.bag,'take',drag.key,-1)
   else
    local data=N.data(U.bag);local sourceName=data[drag.key]and N.title(data[drag.key]);local targetName=data[target]and N.title(data[target])
    local attach=(sourceName=='Lampe Torche'or sourceName=='Flashlight'or sourceName=='2x Sight')and(targetName=='M4A1'or targetName=='Hunting Rifle'or targetName=='Lee-Enfield'or targetName=='Rifle'or targetName=='AK-47')
    N.request(U.bag,attach and'attach'or'move',drag.key,target)
   end
  end)
  if not ok then B.message=tostring(e):gsub('^.-:%d+: ','')end
  U.render()
 end
 function U.tick()
  if not U.opened then return end
  if not B.ready()or not N.access(U.pc,U.bag)then U.close();return end
  if U.windowDrag then U.moveWindow(pointer());return end
  local hover=U.hit();local c=U.cells[hover]
  local rifle=c and(c.name=='M4A1'or c.name=='Hunting Rifle'or c.name=='Lee-Enfield'or c.name=='AK-47'or c.name=='Rifle')and not U.drag
  if U.inspected~=hover or U.inspectVisible~=not not rifle then
   U.inspected=hover;U.inspectVisible=not not rifle
   for _,w in ipairs({U.inspectBg,U.inspectIcon,U.inspectName,U.inspectParts,U.inspectAction})do if valid(w)then w:SetVisibility(rifle and 3 or 1)end end
   if rifle then U.inspectName:SetText(FText(c.name));U.inspectParts:SetText(FText(c.attachments~=''and c.attachments or 'No attachments'));if valid(c.art)then U.inspectIcon:SetBrush(c.art.Brush)else U.inspectIcon:SetVisibility(1)end end
  end
  if not U.drag and not B.pending and valid(U.status)then U.status:SetText(FText(os.clock()<(B.feedbackUntil or 0)and B.message or c and(c.name..(c.attachments and c.attachments~=''and ' | '..c.attachments..' | MMB: remove attachments'or ''))or B.message or''))end
  local now=os.clock();if now<(U.next or 0)then return end;U.next=now+.25
  local vp=layout:GetViewportSize(U.pc);local dpi=layout:GetViewportScale(U.pc)
  if not U.drag and(math.abs(vp.X/dpi-U.vw)>1 or math.abs(vp.Y/dpi-U.vh)>1)then U.render();return end
  local changed=U.signature()~=U.fingerprint
  if not U.drag and changed then U.render()end
 end
 return U
end

