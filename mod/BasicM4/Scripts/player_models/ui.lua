-- Two selectable portraits and a larger rendered model preview. No live capture
-- camera/render target is kept running while the player is driving or fighting.
return function(M,root,valid)
 local V={textures={}}
 function V.render(U,draw)
  local C=M.playerModels;local rect,text,button,place,new=draw.rect,draw.text,draw.button,draw.place,draw.new
  U.modelChoice=U.modelChoice or C.selected;local choice=C.catalog[U.modelChoice+1]
  text('PLAYER MODELS',270,145,1000,40,25,'gold')
  text('Choose your appearance.',270,198,1110,32,16,'muted')
  local function picture(file,x,y,w,h)
   local image=new('Image',U.tree)
   local texture=V.textures[file]
   if not valid(texture)then texture=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(U.pc,root..'/assets/player_models/'..file);V.textures[file]=texture end
   assert(valid(texture),'Missing model preview: '..file);image:SetBrushFromTexture(texture,false);image:SetVisibility(3);place(image,x,y,w,h)
   return image
  end
  local P=C.policy
  local function rgbToHSV(hex)
   local r,g,b=tonumber(hex:sub(1,2),16)/255,tonumber(hex:sub(3,4),16)/255,tonumber(hex:sub(5,6),16)/255
   local hi,lo=math.max(r,g,b),math.min(r,g,b);local delta=hi-lo;local hue=0
   if delta>0 then
    if hi==r then hue=((g-b)/delta)%6 elseif hi==g then hue=(b-r)/delta+2 else hue=(r-g)/delta+4 end
   end
   return hue/6,hi==0 and 0 or delta/hi,hi
  end
  local function hex(h,s,v)
   local function component(n)local k=(n+h*6)%6;return math.floor(255*(v-v*s*math.max(0,math.min(k,4-k,1)))+.5)end
   return ('%02X%02X%02X'):format(component(5),component(3),component(1))
  end
  if U.modelEdit~=nil then
   local id=U.modelEdit;local index=U.colorRegion or 1;local def=P.regions[id][index]
   local draft=U.colorDraft or C.colors(id);local offset=(index-1)*7
   local code=draft:sub(offset+1,offset+6);local finish=draft:sub(offset+7,offset+7)
   local current=code=='------'and def[2]or code
   local h,sat,val=rgbToHSV(current)
   local function change(col,f)
    U.colorDraft=draft:sub(1,offset)..col..f..draft:sub(offset+8);U.render()
   end
   text('EDIT '..C.catalog[id+1].name:upper(),270,242,1070,38,23,'gold')
   picture('color-wheel.png',285,310,240,240)
   local function wheel(x,y)
    local dx,dy=(x-405)/120,(430-y)/120;local radius=math.sqrt(dx*dx+dy*dy)
    if radius<=1 then change(hex(math.atan(dy,dx)/(2*math.pi)%1,radius,val),finish)end
   end
   U.buttons[#U.buttons+1]={x=285,y=310,w=240,h=240,xy=true,fn=wheel}
   local angle=h*2*math.pi
   text('○',393+math.cos(angle)*sat*112,413-math.sin(angle)*sat*112,30,30,17)
   text('Brightness',283,567,295,29,16,'muted')
   picture('brightness.png',285,601,240,28)
   U.buttons[#U.buttons+1]={x=285,y=597,w=240,h=38,xy=true,fn=function(x)change(hex(h,sat,math.max(0,math.min(1,(x-285)/240))),finish)end}
   text(('%.0f%%'):format(val*100),543,600,90,28,15)
   for i,region in ipairs(P.regions[id])do
    button(region[1],665,307+(i-1)*56,307,47,function()U.colorRegion=i;U.render()end,i==index and 'red' or 'card')
   end
   text('Selected color',1015,308,330,30,16,'muted')
   local swatch=new('Image',U.tree);local rgb=M.playerModels.paintRGB(current);swatch:SetColorAndOpacity(rgb);swatch:SetVisibility(3);place(swatch,1015,350,195,68)
   text('#'..current,1015,431,260,32,18)
   if id==1 then
    button('Matte',665,561,145,45,function()change(code,'1')end,finish=='1'and'red'or'card')
    button('Metallic',825,561,145,45,function()change(code,'2')end,finish=='2'and'red'or'card')
   end
   button('Reset this part',1015,549,285,50,function()change('------','0')end,'card')
   button('Save colors',665,684,308,58,function()
    local ok,e=pcall(C.setColors,id,U.colorDraft);if ok then U.modelEdit=nil;U.message='Colors saved'else U.message=tostring(e)end;U.render()
   end,'red')
   button('Cancel',1015,684,285,58,function()U.modelEdit=nil;U.render()end,'card')
  else
   for i,d in ipairs(C.catalog)do
    local x=264+(i-1)*195;local chosen=U.modelChoice==d.id
    rect(x,250,184,236,chosen and 'red'or'card');rect(x+3,253,178,230,'panel')
    picture(d.portrait,x+22,264,140,140)
    text(d.id==0 and 'Default' or d.name,x+12,413,166,28,17)
    text(C.selected==d.id and 'IN USE' or '',x+12,452,112,22,12,'muted')
    rect(x+142,445,34,33,'card');picture('pencil.png',x+147,449,24,24)
    U.buttons[#U.buttons+1]={x=x+137,y=440,w=45,h=43,fn=function()
     U.modelEdit=d.id;U.modelChoice=d.id;U.colorDraft=C.colors(d.id);U.colorRegion=1;U.message='';U.render()
    end}
    U.buttons[#U.buttons+1]={x=x,y=250,w=184,h=236,fn=function()U.modelChoice=d.id;U.message='';U.render()end}
   end
   text(choice.name,270,541,550,42,23,'gold');text(choice.description,270,598,550,60,15,'muted')
   button(C.pending and 'Applying…'or(C.selected==choice.id and 'Selected' or 'Use appearance'),270,697,555,56,function()
    if C.pending or C.selected==U.modelChoice then return end
    local ok,e=pcall(C.select,U.modelChoice);U.message=ok and ''or tostring(e):gsub('^.-:%d+: ','');U.render()
   end,C.selected==choice.id and 'card'or'red')
   rect(865,250,530,507,'panel');text('PREVIEW',887,269,480,26,14,'muted');picture(choice.preview,991,310,272,401)
  end
  -- Hidden image brushes keep already-loaded alternate previews referenced by
  -- native UPROPERTYs while this menu is open. Lua references alone do not.
  for _,texture in pairs(V.textures)do if valid(texture)then local image=new('Image',U.tree);image:SetBrushFromTexture(texture,false);place(image,0,0,1,1);image:SetVisibility(1)end end
  U.modelRevision=C.revision
 end
 return V
end
