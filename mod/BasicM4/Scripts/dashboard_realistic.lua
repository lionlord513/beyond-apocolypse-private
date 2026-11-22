-- Retained analog instrument cluster; needles only move when their value changes.
return function(D,box,label,text,colors)
 local cream={R=.80,G=.79,B=.65,A=1};local dim={R=.22,G=.24,B=.20,A=1}
 local rim={R=.18,G=.19,B=.18,A=1};local face={R=.014,G=.017,B=.014,A=1}
 box(0,0,720,238,{R=.027,G=.029,B=.025,A=.97},22)
 box(8,8,704,222,{R=.07,G=.074,B=.063,A=1},16)
 box(14,31,692,183,face,16)
 label('title',24,10,460,18,10,cream)
 label('grip',484,10,210,18,9,colors.muted,2);text('grip','RIGHT ALT / DRAG HEADER')
 D.needles={}
 local function dial(id,cx,cy,r,max,step,caption)
  box(cx-r-3,cy-r-3,2*r+6,2*r+6,rim,r+3);box(cx-r,cy-r,2*r,2*r,face,r)
  for i=0,max/step do
   local a=math.rad(135+i/(max/step)*270)
   local t=box(cx+math.cos(a)*(r-11)-1,cy+math.sin(a)*(r-11)-5,2,10,cream)
   t:SetRenderTransformPivot({X=.5,Y=.5});t:SetRenderTransformAngle(math.deg(a)-90)
   label(id..'Mark'..i,cx+math.cos(a)*(r-28)-17,cy+math.sin(a)*(r-28)-8,34,18,9,cream,1);text(id..'Mark'..i,tostring(i*step))
  end
  label(id..'Caption',cx-r,cy+20,2*r,18,9,cream,1);text(id..'Caption',caption)
  local n=box(cx,cy-1,r-17,2,colors.red);n:SetRenderTransformPivot({X=0,Y=.5});n:SetRenderTransformAngle(135)
  box(cx-6,cy-6,12,12,rim,6)
  D.needles[id]={image=n,value=0,target=0}
 end
 dial('speedDial',145,122,81,240,30,'KM/H')
 dial('rpmDial',575,122,81,8,1,'RPM x 1000')
 label('speed',110,165,70,24,15,cream,1);label('unit',180,174,20,12,7,cream);text('unit','')
 label('rpm',529,165,92,21,10,cream,1)
 label('gear',328,56,64,37,25,cream,1)
 label('temperature',300,94,120,18,10,cream,1)
 for i,key in ipairs({'fuel','oil','coolant','battery','nitrous'})do
  local y=119+(i-1)*17
  label(key..'Label',255,y,68,15,8,cream);text(key..'Label',key:upper())
  label(key..'Value',380,y,85,15,8,cream,2)
  box(323,y+5,48,4,dim);local o,s=box(323,y+5,0,4,cream)
  D.bars[key]={image=o,slot=s,width=48,height=4,target=0,display=0}
 end
 local batteryIcon=box(330,43,22,9,dim);D.batteryIcon={batteryIcon}
 label('leftSignal',245,54,42,25,19,dim,1);text('leftSignal','<')
 label('rightSignal',433,54,42,25,19,dim,1);text('rightSignal','>')
 box(34,197,42,26,rim,8);label('hazards',34,201,42,18,11,colors.amber,1);text('hazards','!')
 box(648,180,40,40,rim,20);box(656,188,24,24,face,12)
 local key=box(662,193,29,6,cream,2);key:SetRenderTransformPivot({X=.2,Y=.5});D.ignitionKey=key
 box(682,189,12,15,cream,3)
 label('ignition',590,219,111,14,8,cream,2);text('ignition','HOLD KEY / START')
 label('status',90,218,490,17,9,cream,1)
 D.buttons={{x=636,y=176,w=68,h=44,action='Ignition'},{x=238,y=49,w=54,h=38,action='IndicatorLeft'},
  {x=426,y=49,w=54,h=38,action='IndicatorRight'},{x=30,y=192,w=52,h=35,action='IndicatorWarnings'}}
 D.widthBase=720;D.height=238
end
