-- Two selectable portraits and a larger rendered model preview. No live capture
-- camera/render target is kept running while the player is driving or fighting.
return function(M,root,valid)
 local V={textures={}}
 function V.render(U,draw)
  local C=M.playerModels;local rect,text,button,place,new=draw.rect,draw.text,draw.button,draw.place,draw.new
  U.modelChoice=U.modelChoice or C.selected;local choice=C.catalog[U.modelChoice+1]
  text('PLAYER MODELS',270,145,1000,40,25,'gold')
  text('Choose an appearance. Your movement, equipment and stats stay the same.',270,198,1110,32,16,'muted')
  local function picture(file,x,y,w,h)
   local image=new('Image',U.tree)
   local texture=V.textures[file]
   if not valid(texture)then texture=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(U.pc,root..'/assets/player_models/'..file);V.textures[file]=texture end
   assert(valid(texture),'Missing model preview: '..file);image:SetBrushFromTexture(texture,false);image:SetVisibility(3);place(image,x,y,w,h)
   return image
  end
  for i,d in ipairs(C.catalog)do
   local x=270+(i-1)*285;local chosen=U.modelChoice==d.id
   rect(x,250,270,262,chosen and 'red'or'card');rect(x+3,253,264,256,'panel')
   picture(d.portrait,x+71,272,128,128)
   text(d.id==0 and 'DEFAULT GAME'or'SCIFI SOLDIER',x+22,420,246,30,19)
   text(C.selected==d.id and 'CURRENT APPEARANCE'or(chosen and 'PREVIEW SELECTED'or'CLICK TO PREVIEW'),x+22,465,246,28,12,C.selected==d.id and 'gold'or'muted')
   U.buttons[#U.buttons+1]={x=x,y=250,w=270,h=262,fn=function()U.modelChoice=d.id;U.message='';U.render()end}
  end
  text(choice.name,285,552,540,38,24,'gold')
  text(choice.id==0 and 'Restores your original character and chosen clothing.'or'Fitted armour and matching arms. Equipped clothing stays hidden.',285,603,540,62,16,'muted')
  local label=C.pending and 'WAITING FOR HOST...'or(C.selected==choice.id and 'SELECTED'or'USE THIS APPEARANCE')
  button(label,270,694,555,58,function()
   if C.pending or C.selected==U.modelChoice then return end
   local ok,e=pcall(C.select,U.modelChoice);U.message=ok and(C.status or'Applying appearance...')or tostring(e):gsub('^.-:%d+: ','');U.render()
  end,C.selected==choice.id and 'card'or'red')
  text('Co-op: every player needs this version of Beyond Apocalypse.',285,773,1080,26,13,'muted')
  rect(855,250,540,502,'panel');text('MODEL PREVIEW',877,268,495,30,13,'muted')
  picture(choice.preview,988,300,270,405)
  text(choice.id==0 and 'Default appearance follows your in-game customization.'or'SciFi Soldier',877,718,500,26,13,'muted')
  -- Hidden image brushes keep already-loaded alternate previews referenced by
  -- native UPROPERTYs while this menu is open. Lua references alone do not.
  for _,texture in pairs(V.textures)do if valid(texture)then local image=new('Image',U.tree);image:SetBrushFromTexture(texture,false);place(image,0,0,1,1);image:SetVisibility(1)end end
  U.modelRevision=C.revision
 end
 return V
end
