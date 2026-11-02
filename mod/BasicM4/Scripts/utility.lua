-- Public local settings and personal statistics. No host actions or admin RPCs.
return function(M,root,H,valid,enqueue,log)
 local U={opened=false,tab='Settings',settingsTab='Keybinds',buttons={},session=0,total=0};local Ctl=M.controls;local lib,layout,slate
 local game=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local C={bg={R=.012,G=.014,B=.015,A=.98},panel={R=.025,G=.028,B=.029,A=1},card={R=.049,G=.052,B=.052,A=1},red={R=.34,G=.021,B=.017,A=1},accent={R=.72,G=.19,B=.12,A=1},text={R=.87,G=.86,B=.81,A=1},muted={R=.48,G=.50,B=.47,A=1},gold={R=.68,G=.55,B=.32,A=1}}
 local statsFile=root..'/state/personal-distance.txt'
 do local f=io.open(statsFile,'r');if f then for line in f:lines()do local n=tonumber(line);if n and n>=0 and n<1e12 then U.total=math.max(U.total,n)end end;f:close()end end
 function U.saveStats()
  if U.total==(U.savedTotal or 0)then return end
  local f=io.open(statsFile,'a');if f then f:write(('%.3f\n'):format(U.total));f:close();U.savedTotal=U.total end
 end
 local function new(k,outer)return StaticConstructObject(StaticFindObject('/Script/UMG.'..k),outer)end
 local function place(o,x,y,w,h)
  local s=U.canvas:AddChildToCanvas(o);s:SetPosition({X=U.x+x*U.scale,Y=U.y+y*U.scale});s:SetSize({X=w*U.scale,Y=h*U.scale});return o
 end
 local function rect(x,y,w,h,c)
  local o=new('Image',U.tree);o:SetColorAndOpacity(C[c]);place(o,x,y,w,h);o:SetVisibility(3);return o
 end
 local function text(t,x,y,w,h,size,color)
  local o=new('TextBlock',U.tree);o:SetText(FText(t));local f=o.Font;f.Size=math.max(10,math.floor(size*U.scale));o:SetFont(f)
  o:SetColorAndOpacity({SpecifiedColor=C[color or 'text'],ColorUseRule=0});place(o,x,y,w,h);o:SetVisibility(3);return o
 end
 local function button(t,x,y,w,h,fn,c,description)
  rect(x,y,w,h,c or 'card');text(t,x+16,y+(h<=36 and 5 or 12),w-32,30,h<=36 and 14 or 18)
  if description then text(description,x+16,y+46,w-32,34,13,'muted')end
  U.buttons[#U.buttons+1]={x=x,y=y,w=w,h=h,fn=fn}
 end
 function U.close()
  U.opened=false;U.capture=nil;if U.saveStats then U.saveStats()end
  if valid(U.child)then U.child:RemoveFromParent()end;U.child=nil
  if valid(U.widget)then U.widget:RemoveFromParent()end
  if U.blocked and valid(U.pc)then
   -- Balance exactly the ignore-input pushes made by this overlay.
   U.pc:SetIgnoreLookInput(false);U.pc:SetIgnoreMoveInput(false)
   if valid(U.pawn)then U.pawn:EnableInput(U.pc)end
   U.pc.bShowMouseCursor=U.cursorBefore or false
   lib:SetInputMode_GameOnly(U.pc,true)
  end
  U.blocked=false;U.widget=nil;U.tree=nil;U.canvas=nil;U.buttons={};U.fields={}
 end

 function U.stats()
  local pc,p=H.GetPlayerController(),H.GetPlayer();if not valid(pc)or not valid(p)then return {}end
  local money={};pc:GetCurrentMoney(money);local state=pc.PlayerState
  return {{'Money',('$%.0f'):format(money.NewParam or 0)},{'Session distance ~',('%.3f km'):format(U.session/1000)},
   {'Tracked total distance ~',('%.3f km'):format(U.total/1000)},{'Frame rate',U.fps and ('%.0f FPS'):format(U.fps)or '--'},
   {'Ping',valid(state)and ('%.0f ms'):format(state:GetPingInMilliseconds())or '--'},{'Health',('%.0f'):format(p.BP_PlayerStats.Life)}}
 end
 function U.render()
  U.canvas:ClearChildren();U.buttons={};U.statCells={}
  local vp=layout:GetViewportSize(U.pc);local dpi=layout:GetViewportScale(U.pc)
  U.scale=math.min(vp.X/1440,vp.Y/840)/dpi;U.x=(vp.X/dpi-1440*U.scale)/2;U.y=(vp.Y/dpi-840*U.scale)/2
  rect(0,0,1440,840,'bg');rect(0,0,1440,5,'red');rect(20,132,218,654,'panel')
  text('BEYOND APOCOLYPSE',30,40,1100,48,30);text('PLAYER UTILITY  /  '..M.version,32,92,1000,30,14,'muted')
  button('CLOSE [F8]',1230,35,184,52,function()U.close()end)
  for i,name in ipairs({'Settings','Stats'})do button(name:upper(),30,146+(i-1)*63,198,52,function()U.tab=name;U.capture=nil;U.render()end,U.tab==name and 'red'or'panel')end
  if U.tab=='Settings'then
   for i,name in ipairs({'Keybinds','Gameplay'})do button(name:upper(),270+(i-1)*240,145,226,36,function()U.settingsTab=name;U.capture=nil;U.message='';U.render()end,U.settingsTab==name and 'red'or'card')end
   if U.settingsTab=='Gameplay'then
    text('GAMEPLAY',270,205,1000,40,25,'gold')
    button((Ctl.simpleFlight and '[X] 'or '[ ] ')..'Simple flight',270,265,520,54,function()
     local ok,e=pcall(Ctl.setSimpleFlight,not Ctl.simpleFlight);U.message=ok and 'Gameplay settings saved.'or tostring(e):gsub('^.-:%d+: ','');U.render()
    end)
    text('Automatic hover and leveling. Hold raise / lower to climb / descend.',286,340,1070,32,17,'muted')
    text('Applies only when you pilot a gyrocopter. Saved across sessions.',286,384,1070,32,17,'muted')
    button((M.performance.gameplayMode and '[X] 'or '[ ] ')..'Gameplay Performance Mode',270,452,700,54,function()
     local ok,result,message=pcall(M.performance.setGameplayMode,not M.performance.gameplayMode)
     U.message=ok and (result and(message or 'Performance Mode updated.')or message)or tostring(result):gsub('^.-:%d+: ','');U.render()
    end)
    text('Scenery target: 160 m. Removes safe decorative grass, bushes and clutter.',286,526,1080,32,17,'muted')
    text('Saved on this PC. Turn off to restore previous render settings. Roads and interactions stay.',286,570,1080,32,17,'muted')
   else
   text('GYROCOPTER KEYBINDINGS',270,195,1000,40,25,'gold')
   text('Click a key, then press its replacement. Escape cancels; Backspace clears an alternate.',270,235,1120,28,14,'muted')
   text('ACTION',280,269,510,26,14,'muted');text('PRIMARY',850,269,220,26,14,'muted');text('ALTERNATE',1130,269,220,26,14,'muted')
   for i,r in ipairs(Ctl.rows)do local id=r[1];local y=300+(i-1)*31;rect(270,y,1125,29,'panel');local label=r[2];if Ctl.simpleFlight then if id=='collectiveUp'then label='Climb'elseif id=='collectiveDown'then label='Descend'end end;text(label,282,y+4,520,27,15)
    for index=1,2 do local slot=index;local waiting=U.capture and U.capture.id==id and U.capture.slot==slot
     button(waiting and 'PRESS A KEY...'or U.draft[id][slot],820+(slot-1)*280,y,268,29,function()U.capture={id=id,slot=slot};U.message='';U.render()end,waiting and 'red'or'card')
    end
   end
   text('Native seat entry/exit and item interactions keep the game settings.',280,712,1000,28,13,'muted')
   button('DEFAULTS',270,746,210,48,function()for _,r in ipairs(Ctl.rows)do U.draft[r[1]]={r[3],r[4]}end;U.capture=nil;U.render()end)
   button('APPLY',1170,746,224,48,function()local ok,e=pcall(Ctl.apply,U.draft);U.capture=nil;U.message=ok and 'Controls saved.'or tostring(e):gsub('^.-:%d+: ','');U.render()end,'red')
   end
  else
   text('PERSONAL STATS',270,145,1000,40,25,'gold')
   for i,r in ipairs(U.stats())do local y=223+(i-1)*69;rect(270,y,1125,58,'card');text(r[1],290,y+16,590,36,18);U.statCells[i]=text(r[2],970,y+16,410,36,18,'gold')end
   text('Distance is sampled locally. Total starts with this update; large teleports are excluded.',280,696,1110,36,14,'muted')
  end
  text(U.message or '',30,806,1360,28,14,'gold')
 end
 function U.open()
  local player=H.GetPlayer();assert(valid(player)and player.IsLoaded,'Join a game first')
  local pc=H.GetPlayerController();if pc.HUD.ChatUI.TypeInChat or H.IsPauseMenu(pc)or M.devmenu.ui.opened or M.backpack.ui.opened then return end
  Ctl.readNative();U.draft=Ctl.copy();U.capture=nil;U.message=''
  U.tab='Settings'
  U.pc=H.GetPlayerController();U.pawn=U.pc:K2_GetPawn();U.cursorBefore=U.pc.bShowMouseCursor
  lib=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary');layout=StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary');slate=StaticFindObject('/Script/UMG.Default__SlateBlueprintLibrary')
  U.widget=lib:Create(U.pc,StaticFindObject('/Script/UMG.UserWidget'),U.pc)
  U.tree=U.widget.WidgetTree;if not valid(U.tree)then U.tree=new('WidgetTree',U.widget);U.widget.WidgetTree=U.tree end
  U.canvas=new('CanvasPanel',U.tree);U.tree.RootWidget=U.canvas;U.widget:AddToViewport(10000)
  U.render();U.blocked=true;U.pc:SetIgnoreLookInput(true);U.pc:SetIgnoreMoveInput(true)
  if valid(U.pawn)then U.pawn:DisableInput(U.pc)end
  U.pc.bShowMouseCursor=true;lib:SetInputMode_UIOnlyEx(U.pc,U.widget,0,true);U.opened=true
 end
 function U.toggle()
  if U.opened then U.close()else local ok,e=pcall(U.open);if not ok then U.close();error(e)end end
 end
 function U.click()
  if not U.opened or U.child then return end
  -- Native conversion returns AddToViewport widget units, including DPI/window
  -- transforms. Do not pass opaque FGeometry through UE4SS's Lua table copier.
  local pixel,q={},{};slate:AbsoluteToViewport(U.pc,layout:GetMousePositionOnPlatform(),pixel,q)
  local x,y=(q.X-U.x)/U.scale,(q.Y-U.y)/U.scale
  for _,b in ipairs(U.buttons)do if x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h then b.fn();return end end
 end

 function U.accept(key)
  if not U.opened or not U.capture then return end
  local c=U.capture
  if key=='BackSpace'and c.slot==2 then key='None'end
  U.draft[c.id][c.slot]=key;U.capture=nil;U.message='Press Apply to save.';U.render()
 end
 function U.tick()
  Ctl.tick()
  local pc,p=H.GetPlayerController(),H.GetPlayer()
  if not valid(pc)or not valid(p)or not p.IsLoaded then U.position=nil;if U.opened then U.close()end;return end
  if U.opened and(p.BP_PlayerStats.IsDead or not valid(U.widget))then U.close()end
  local delta=game:GetWorldDeltaSeconds(p);if delta>0 and delta<1 then U.fps=U.fps and U.fps*.9+.1/delta or 1/delta end
  local now=game:GetTimeSeconds(p)
  if now<(U.nextSample or 0)then return end;U.nextSample=now+.5
  local q=p:K2_GetActorLocation();local id=p:GetAddress()
  if U.position and U.pawnId==id then local old=U.position;local distance=math.sqrt((q.X-old.X)^2+(q.Y-old.Y)^2+(q.Z-old.Z)^2)/100
   if distance<250 and not p.BP_PlayerStats.IsDead then U.total=U.total+distance;U.session=U.session+distance end
  end
  U.position={X=q.X,Y=q.Y,Z=q.Z};U.pawnId=id
  if now>=(U.nextSave or 0)then U.nextSave=now+5;U.saveStats()end
  if U.opened and U.tab=='Stats'then for i,row in ipairs(U.stats())do if valid(U.statCells[i])then U.statCells[i]:SetText(FText(row[2]))end end end
 end
 function U.reset()U.close();Ctl.restore();U.position=nil;U.pawnId=nil;U.session=0;U.nextSample=0;U.nextSave=0 end
 RegisterKeyBind(Key.F8,function()enqueue(function()U.toggle()end)end)
 for code,key in pairs(Ctl.codes)do local name=key;RegisterKeyBind(code,function()
  if not U.opened then return end
  if U.capture then enqueue(function()U.accept(name)end)
  elseif name=='LeftMouseButton'then enqueue(function()U.click()end)end
 end)end
 return U
end
