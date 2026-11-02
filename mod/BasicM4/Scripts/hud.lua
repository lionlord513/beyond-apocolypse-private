-- Shared flight overlay, retained from the original menu UI.
return function(H,valid)
 local U={}
 local C={bg={R=.012,G=.014,B=.015,A=.98},text={R=.87,G=.86,B=.81,A=1}}
 local function new(k,outer)return StaticConstructObject(StaticFindObject('/Script/UMG.'..k),outer)end
 function U.hud(message)
  if not message then
   if valid(U.hudWidget)then U.hudWidget:RemoveFromParent()end;U.hudWidget=nil;U.hudLabel=nil;return
  end
  if not valid(U.hudWidget)then
   local pc=H.GetPlayerController();local wlib=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
   local w=wlib:Create(pc,StaticFindObject('/Script/UMG.UserWidget'),pc);local tree=w.WidgetTree
   if not valid(tree)then tree=new('WidgetTree',w);w.WidgetTree=tree end
   local canvas=new('CanvasPanel',tree);tree.RootWidget=canvas;w:AddToViewport(8000);w:SetVisibility(3)
   local panel=new('CanvasPanel',tree);local slot=canvas:AddChildToCanvas(panel)
   slot:SetAnchors({Minimum={X=1,Y=0},Maximum={X=1,Y=0}});slot:SetAlignment({X=1,Y=0});slot:SetPosition({X=-24,Y=170});slot:SetSize({X=330,Y=230})
   local bg=new('Image',tree);bg:SetColorAndOpacity(C.bg);local b=panel:AddChildToCanvas(bg);b:SetSize({X=330,Y=230})
   local label=new('TextBlock',tree);local font=label.Font;font.Size=14;label:SetFont(font);label:SetColorAndOpacity({SpecifiedColor=C.text,ColorUseRule=0})
   local s=panel:AddChildToCanvas(label);s:SetPosition({X=16,Y=12});s:SetSize({X=304,Y=210})
   U.hudWidget=w;U.hudLabel=label
  end
  U.hudLabel:SetText(FText(message))
 end
 -- Reuse the flight overlay's lifetime; the gauge cannot survive leaving it.
 return function(message,collective,hover,climb)
  U.hud(message)
  if not message then U.gauge=nil;return end
  if type(collective)~='number' then
   if U.gauge then if valid(U.gauge.panel)then U.gauge.panel:RemoveFromParent()end;U.gauge=nil end
   return
  end
  if not U.gauge or U.gauge.owner~=U.hudWidget or not valid(U.gauge.panel)then
   local tree=U.hudWidget.WidgetTree;local panel=new('CanvasPanel',tree)
   local slot=tree.RootWidget:AddChildToCanvas(panel)
   slot:SetAnchors({Minimum={X=1,Y=1},Maximum={X=1,Y=1}});slot:SetAlignment({X=1,Y=1})
   slot:SetPosition({X=-28,Y=-100});slot:SetSize({X=108,Y=176})
   local function box(x,y,w,h,color)
    local img=new('Image',tree);img:SetColorAndOpacity(color)
    local s=panel:AddChildToCanvas(img);s:SetPosition({X=x,Y=y});s:SetSize({X=w,Y=h});return s
   end
   local function label(x,y,w,h,size)
    local t=new('TextBlock',tree);local font=t.Font;font.Size=size;t:SetFont(font)
    t:SetColorAndOpacity({SpecifiedColor=C.text,ColorUseRule=0})
    local s=panel:AddChildToCanvas(t);s:SetPosition({X=x,Y=y});s:SetSize({X=w,Y=h});return t
   end
   box(0,0,108,176,{R=.012,G=.014,B=.015,A=.8})
   label(10,8,94,18,10):SetText(FText('COLLECTIVE'))
   box(20,38,2,104,{R=.4,G=.42,B=.43,A=1})
   for _,y in ipairs({38,90,142})do box(16,y,10,1,C.text)end
   local hoverLine=box(12,90,27,1,{R=.5,G=.62,B=.66,A=1})
   local hoverLabel=label(42,82,64,18,9)
   local needle=box(13,142,18,4,{R=.95,G=.8,B=.35,A=1})
   U.gauge={owner=U.hudWidget,panel=panel,needle=needle,hoverLine=hoverLine,hoverLabel=hoverLabel,
    value=label(42,40,64,22,15),climb=label(10,152,98,18,10)}
  end
  local g=U.gauge;collective=math.max(0,math.min(1,collective))
  g.value:SetText(FText(('%.1f%%'):format(collective*100)))
  local canHover=type(hover)=='number'and hover>0 and hover<=1
  g.needle:SetPosition({X=13,Y=142-104*collective})
  g.hoverLine:SetPosition({X=12,Y=142-104*(canHover and hover or .5)})
  g.hoverLabel:SetText(FText(canHover and ('H %.1f%%'):format(hover*100)or 'HOVER --'))
  g.climb:SetText(FText(('%+.1f m/s'):format(climb or 0)))
 end
end
