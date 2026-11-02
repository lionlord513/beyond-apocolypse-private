-- Shared edition artwork for the native loading/title screen and home menu.
return function(root,release,H,valid)
 local B={enabled=true}
 local function dispose()
  if valid(B.widget)then B.widget:RemoveFromParent()end
  B.widget=nil;B.texture=nil;B.image=nil;B.label=nil;B.size=nil;B.home=nil;B.splash=nil;B.loading=nil
 end
 B.reset=dispose
 local function texture(pc)
  if not valid(B.texture)then
   B.texture=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(pc,root..'/assets/beyond-apocolypse-edition.png')
   assert(valid(B.texture),'Missing edition logo')
  end
 return B.texture
 end
 local function replaceLogo(screen)
  if not valid(screen)or not valid(screen.Logo)then return end
  local pc=H.GetPlayerController();if not valid(pc)then return end
  local t=texture(pc);local current=screen.Logo.Brush.ResourceObject
  if not valid(current)or current:GetAddress()~=t:GetAddress()then
   screen.Logo:SetBrushFromTexture(t,true)
  end
 end
 function B.tick()
  if not B.enabled then if B.widget then dispose()end;return end
  local world=H.GetWorld()
  if not valid(world)then
   if B.widget or B.splash or B.loading then dispose()end;return
  end
  -- Saved-world loading can remain visible after the destination map is active.
  if not valid(B.loading)or not B.loading:IsInViewport()then
   B.loading=nil
   for _,screen in ipairs(FindAllOf('LoadGameUI_C')or{})do
    if valid(screen)and screen:IsInViewport()then B.loading=screen;break end
   end
  end
  replaceLogo(B.loading)
  if not world:GetFullName():find('L_SplashScreenTest',1,true)then
   if valid(B.widget)then B.widget:RemoveFromParent()end
   B.widget=nil;B.image=nil;B.label=nil;B.size=nil;B.home=nil
   return
  end
  -- Keep native ScaleBoxes, animations, progress indicators and buttons unchanged.
  if not valid(B.splash)then B.splash=FindFirstOf('WBP_SplashScreen_C')end
  replaceLogo(B.splash)
  if not valid(B.home)then B.home=FindFirstOf('W_Home_C')end
  local home=B.home
  if not valid(home)or not home:IsInViewport()or not home:IsVisible()then return end
  -- The native Main canvas hides our children on Options, Load, Join, etc.
  local panel=home.Main;local button=home.Button_Continue
  if not valid(panel)or not valid(button)then return end
  local holder=button:GetParent();local container=holder
  -- Bounded parent walk: use the existing centered menu group's own anchors.
  for i=1,6 do
   if not valid(container)then return end
   local parent=container:GetParent()
   if valid(parent)and parent:GetAddress()==panel:GetAddress()then break end
   container=parent
  end
  if not valid(container)or container:GetParent():GetAddress()~=panel:GetAddress()then return end
  local groupSize=container:GetDesiredSize();local buttonSize=holder:GetDesiredSize()
  if groupSize.X<=0 or groupSize.Y<=0 or buttonSize.X<=0 then return end
  local nativeSlot=container.Slot
  if not valid(nativeSlot)or not nativeSlot:GetFullName():match('^CanvasPanelSlot ')then return end
  local d=nativeSlot.LayoutData
  local pc=H.GetPlayerController();if not valid(pc)then return end
  local layout=StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
  local vp=layout:GetViewportSize(pc);local dpi=layout:GetViewportScale(pc)
  if vp.X<=0 or vp.Y<=0 or dpi<=0 then return end
  if not valid(B.widget)then
   local function new(class)return StaticConstructObject(StaticFindObject('/Script/UMG.'..class),home.WidgetTree)end
   B.widget=new('CanvasPanel');B.widget:SetVisibility(3)
   B.slot=panel:AddChildToCanvas(B.widget) -- Native parent roots it before texture loading.
   B.image=new('Image');B.image:SetBrushFromTexture(texture(pc),false);B.image:SetVisibility(3)
   B.imageSlot=B.widget:AddChildToCanvas(B.image)
   B.label=new('TextBlock');B.label:SetText(FText('v'..release.Version..' '..release.Channel));B.label:SetVisibility(3)
   B.label:SetJustification(1)
   B.label:SetColorAndOpacity({SpecifiedColor={R=.94,G=.94,B=.92,A=1},ColorUseRule=0})
   local font=B.label.Font;font.Size=14;B.label:SetFont(font)
   B.textSlot=B.widget:AddChildToCanvas(B.label)
  end
  local key=table.concat({groupSize.X,groupSize.Y,buttonSize.X,d.Offsets.Left,d.Offsets.Top,d.Alignment.X,d.Alignment.Y,vp.X,vp.Y,dpi},':')
  if key~=B.size then
   B.size=key
   local originX=vp.X/dpi*d.Anchors.Minimum.X;local originY=vp.Y/dpi*d.Anchors.Minimum.Y
   local x=d.Offsets.Left-groupSize.X*d.Alignment.X
   local y=d.Offsets.Top-groupSize.Y*d.Alignment.Y-8
   -- Native menu itself overflows at 4:3; keep our added artwork inside the screen.
   local room=originY+y-12-24
   local width=math.min(buttonSize.X,vp.X/dpi-24,math.max(0,room)*1983/793)
   if width<80 then B.widget:SetVisibility(1);B.size=nil;return end
   local height=width*793/1983
   x=math.max(12-originX,math.min(x,vp.X/dpi-12-originX-width))
   B.widget:SetVisibility(3)
   B.slot:SetAnchors(d.Anchors);B.slot:SetAlignment({X=0,Y=1})
   B.slot:SetPosition({X=x,Y=y})
   B.slot:SetSize({X=width,Y=height+24})
   B.imageSlot:SetPosition({X=0,Y=0});B.imageSlot:SetSize({X=width,Y=height})
   B.textSlot:SetPosition({X=0,Y=height+2});B.textSlot:SetSize({X=width,Y=22})
  end
 end
 return B
end
