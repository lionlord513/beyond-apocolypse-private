-- Imported instrument artwork with retained, live needles and indicator lamps.
return function(D,box,label,text,colors,picture)
 local cream={R=.88,G=.84,B=.69,A=1};local dim={R=.17,G=.19,B=.15,A=1}
 picture('panel',0,0,720,320)
 D.needles={};D.images={}
 local function dial(id,cx,cy,r,max,step,caption,marks,pod)
  local function keep(o)if pod then D.nitrousWidgets[#D.nitrousWidgets+1]=o end;return o end
  local function b(...)local o=box(...);return keep(o)end
  local function l(...)return keep(label(...))end
  local function art(...)return keep(picture(...))end
  art('dial',cx-r-3,cy-r-3,2*r+6,2*r+6)
  local small=r<65;local tiny=r<35;local start=small and 180 or 135;local sweep=small and 180 or 270
  local count=max/step
  for i=0,count*4 do
   local a=math.rad(start+i/(count*4)*sweep);local major=i%4==0;local length=major and(tiny and 4 or 7)or(tiny and 2 or 3)
   local t=b(cx+math.cos(a)*(r-12)-.5,cy+math.sin(a)*(r-12)-length/2,1,length,cream)
   t:SetRenderTransformPivot({X=.5,Y=.5});t:SetRenderTransformAngle(math.deg(a)-90)
   if major then
    local index=i/4;local radius=r-(tiny and 21 or small and 24 or 29);local width=tiny and 14 or 28
    l(id..'Mark'..index,cx+math.cos(a)*radius-width/2,cy+math.sin(a)*radius-9,width,19,tiny and 5 or small and 7 or 9,cream,1)
    text(id..'Mark'..index,marks and marks[index+1]or tostring(index*step):gsub('%.0$',''))
   end
  end
  l(id..'Caption',cx-r+8,cy+(small and 9 or 22),2*r-16,18,tiny and 6 or small and 7 or 9,cream,1);text(id..'Caption',caption)
  local w=(r-(small and 17 or 21))/.934;local h=w/3
  local n=art('needle',cx-w*.066,cy-h*.5,w,h);n:SetRenderTransformPivot({X=.066,Y=.5});n:SetRenderTransformAngle(start)
  D.needles[id]={image=n,value=0,target=0,start=start,sweep=sweep,textured=true}
 end
 dial('speedDial',145,133,84,240,30,'KM/H')
 dial('rpmDial',575,133,84,8,1,'RPM x 1000')
 dial('fuelDial',360,114,49,1,.5,'FUEL',{'E','1/2','F'})
 label('fuelValue',300,135,120,18,8,cream,1)
 label('speed',110,177,70,26,15,cream,1);label('unit',180,184,20,16,7,cream);text('unit','')
 label('rpm',529,174,92,20,10,cream,1)
 label('gear',330,37,60,34,22,cream,1)
 label('temperature',529,194,92,17,7,cream,1)
 for i,key in ipairs({'oil','coolant','battery'})do
  D[key..'Value']=nil
  dial(key..'Dial',290+(i-1)*70,215,30,1,1,key:upper(),{'E','F'})
 end
 D.batteryIcon={}
 D.leftSignal=picture('arrow',247,47,42,22);D.images.leftSignal=true
 D.rightSignal=picture('arrow',431,47,42,22);D.rightSignal:SetRenderTransformAngle(180);D.images.rightSignal=true
 D.hazards=picture('hazard',82,244,42,28)
 picture('dial',533,229,42,42)
 D.ignitionKey=picture('key',530,226,48,48);D.ignitionKey:SetRenderTransformPivot({X=.5,Y=.5})
 label('engineState',584,242,78,20,8,cream,1)
 label('status',220,270,330,20,8,cream,1)
 D.buttons={{x=525,y=221,w=58,h=58,action='Ignition'},{x=240,y=41,w=56,h=34,action='IndicatorLeft'},
  {x=424,y=41,w=56,h=34,action='IndicatorRight'},{x=76,y=238,w=54,h=40,action='IndicatorWarnings'}}
 D.nitrousWidgets={}
 dial('nitrousDial',654,-43,58,1,.5,'NITROUS',{'E','1/2','F'},true)
 D.nitrousWidgets[#D.nitrousWidgets+1]=label('nitrousValue',603,-18,102,18,8,cream,1)
 for _,o in ipairs(D.nitrousWidgets)do o:SetVisibility(2)end
 D.nitrousVisible=false
 D.widthBase=720;D.height=320
end
