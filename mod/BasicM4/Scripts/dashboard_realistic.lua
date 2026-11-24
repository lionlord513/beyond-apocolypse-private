-- Retained analog instruments; all gauges reuse their widgets between updates.
return function(D,box,label,text,colors)
 local cream={R=.80,G=.79,B=.65,A=1};local dim={R=.22,G=.24,B=.20,A=1}
 local rim={R=.18,G=.19,B=.18,A=1};local face={R=.014,G=.017,B=.014,A=1}
 box(0,0,720,260,{R=.027,G=.029,B=.025,A=.97},22)
 box(8,8,704,244,{R=.07,G=.074,B=.063,A=1},16)
 box(14,31,692,193,face,16)
 label('grip',484,10,210,20,8,colors.muted,2);text('grip','Hold Alt to drag')
 D.needles={}
 local function dial(id,cx,cy,r,max,step,caption,marks,pod)
  local function b(...)
   local o,s=box(...);if pod then D.nitrousWidgets[#D.nitrousWidgets+1]=o end;return o,s
  end
  local function l(...)
   local o=label(...);if pod then D.nitrousWidgets[#D.nitrousWidgets+1]=o end;return o
  end
  b(cx-r-3,cy-r-3,2*r+6,2*r+6,rim,r+3);b(cx-r,cy-r,2*r,2*r,face,r)
  local small=r<60
  for i=0,max/step do
   local a=math.rad(135+i/(max/step)*270)
   local t=b(cx+math.cos(a)*(r-9)-1,cy+math.sin(a)*(r-9)-4,2,8,cream)
   t:SetRenderTransformPivot({X=.5,Y=.5});t:SetRenderTransformAngle(math.deg(a)-90)
   l(id..'Mark'..i,cx+math.cos(a)*(r-(small and 21 or 28))-17,cy+math.sin(a)*(r-(small and 21 or 28))-9,34,20,small and 7 or 9,cream,1)
   text(id..'Mark'..i,marks and marks[i+1]or tostring(i*step))
  end
  l(id..'Caption',cx-r,cy+(small and 9 or 20),2*r,20,small and 7 or 9,cream,1);text(id..'Caption',caption)
  local n=b(cx,cy-1,r-(small and 12 or 17),2,colors.red);n:SetRenderTransformPivot({X=0,Y=.5});n:SetRenderTransformAngle(135)
  b(cx-5,cy-5,10,10,rim,5)
  D.needles[id]={image=n,value=0,target=0}
 end
 dial('speedDial',145,126,81,240,30,'KM/H')
 dial('rpmDial',575,126,81,8,1,'RPM x 1000')
 dial('fuelDial',360,112,44,1,.5,'FUEL',{'E','1/2','F'})
 label('fuelValue',300,158,120,20,8,cream,1)
 label('speed',110,169,70,26,15,cream,1);label('unit',180,178,20,16,7,cream);text('unit','')
 label('rpm',529,169,92,22,10,cream,1)
 label('gear',328,34,64,33,22,cream,1)
 label('temperature',529,192,92,20,8,cream,1)
 for i,key in ipairs({'oil','coolant','battery'})do
  local y=180+(i-1)*16
  label(key..'Label',250,y,72,20,8,cream);text(key..'Label',key:upper())
  label(key..'Value',380,y,90,20,8,cream,2)
  box(323,y+6,48,4,dim);local o,s=box(323,y+6,0,4,cream)
  D.bars[key]={image=o,slot=s,width=48,height=4,target=0,display=0}
 end
 local batteryIcon=box(402,44,22,9,dim);D.batteryIcon={batteryIcon}
 label('leftSignal',245,44,42,28,19,dim,1);text('leftSignal','<')
 label('rightSignal',433,44,42,28,19,dim,1);text('rightSignal','>')
 box(34,211,42,26,rim,8);label('hazards',34,214,42,20,11,colors.amber,1);text('hazards','!')
 box(648,194,40,40,rim,20);box(656,202,24,24,face,12)
 local key=box(662,207,29,6,cream,2);key:SetRenderTransformPivot({X=.2,Y=.5});D.ignitionKey=key
 box(682,203,12,15,cream,3)
 label('ignition',570,235,132,20,8,cream,2);text('ignition','HOLD KEY / START')
 label('status',90,232,470,22,9,cream,1)
 D.buttons={{x=636,y=190,w=68,h=44,action='Ignition'},{x=238,y=39,w=54,h=38,action='IndicatorLeft'},
  {x=426,y=39,w=54,h=38,action='IndicatorRight'},{x=30,y=206,w=52,h=35,action='IndicatorWarnings'}}
 D.nitrousWidgets={}
 D.nitrousWidgets[#D.nitrousWidgets+1]=box(638,-6,40,23,rim,5)
 dial('nitrousDial',658,-48,52,1,.5,'NITROUS',{'E','1/2','F'},true)
 D.nitrousWidgets[#D.nitrousWidgets+1]=label('nitrousValue',609,-23,98,20,7,cream,1)
 for _,o in ipairs(D.nitrousWidgets)do o:SetVisibility(2)end
 D.nitrousVisible=false
 D.widthBase=720;D.height=260
end
