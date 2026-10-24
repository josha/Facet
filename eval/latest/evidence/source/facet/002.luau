--!strict
local D={}
D.karts={
{id="vector",name="Vector / 01",category="Balanced",rarity=1,speed=92,handling=7,boost=22,color=Color3.fromRGB(34,231,241)},
{id="wraith",name="Wraith / 02",category="Speed",rarity=3,speed=108,handling=5,boost=20,color=Color3.fromRGB(172,92,255)},
{id="comet",name="Comet / 03",category="Agile",rarity=2,speed=86,handling=10,boost=28,color=Color3.fromRGB(255,175,51)},
{id="nova",name="Nova / 04",category="Speed",rarity=4,speed=116,handling=4,boost=18,color=Color3.fromRGB(255,69,126)},
{id="pulse",name="Pulse / 05",category="Agile",rarity=2,speed=90,handling=9,boost=32,color=Color3.fromRGB(74,255,151)},
}
D.parts={
{id="ion",name="Ion motor",slot="Motor",price=450,effect="+8 top speed",power=8},
{id="fusion",name="Fusion motor",slot="Motor",price=1200,effect="+16 top speed",power=16},
{id="capacitor",name="Flux capacitor",slot="Boost",price=650,effect="+12 boost speed",power=12},
{id="grip",name="Magnetic wheels",slot="Wheels",price=350,effect="+30% steering response",power=3},
{id="halo",name="Halo trim",slot="Cosmetics",price=800,effect="Golden running lights",power=0},
}
D.drivers={
{id="rook",name="Rook",group="Pilots",speed=0,handling=1,price=0,rent=0},
{id="echo",name="Echo",group="Synthetics",speed=5,handling=1,price=1500,rent=180},
{id="astra",name="Astra",group="Pilots",speed=3,handling=3,price=2200,rent=240},
{id="nyx",name="Nyx",group="Synthetics",speed=8,handling=0,price=2800,rent=300},
}
D.colors={Red=Color3.fromRGB(255,70,90),Amber=Color3.fromRGB(255,181,54),Green=Color3.fromRGB(70,245,143),Cyan=Color3.fromRGB(31,229,247),Blue=Color3.fromRGB(69,126,255),Violet=Color3.fromRGB(178,93,255)}
D.colorNames={"Red","Amber","Green","Cyan","Blue","Violet"}
D.decals={"Stripes","Circuit","Comet","Chevron","Hex","Orbit"}
D.cards={"Ion spark","Moon runner","Flux engine","Night rider","Prism drift","Astral crown"}
D.chat={"Good luck!","Nice drift!","Follow me!","Let's race!","Great race!","Thanks!","On my way!","One more!"}
D.tracks={{id="Orbit",name="ORBIT / Azure ring",description="Fast sweepers • cyan city",radius=180},{id="Eclipse",name="ECLIPSE / Violet ring",description="Tight lines • violet night",radius=145},{id="Solar",name="SOLAR / Amber ring",description="Wide arc • amber sunrise",radius=210}}
function D.find(list,id) for _,v in list do if v.id==id then return v end end return nil end
function D.markings(name)
 local marks={}
 for i=1,12 do
  local size=Vector3.new(.2,.08,.2);local cf=CFrame.new(0,-2,0)
  if name=="Stripes" then
   if i<=2 then size=Vector3.new(.3,.08,6.5);cf=CFrame.new(if i==1 then -1.4 else 1.4,.53,0) end
  elseif name=="Circuit" then
   size=Vector3.new(if i%2==0 then 3.5 else .16,.08,if i%2==0 then .16 else 1.5)
   cf=CFrame.new(if i%2==0 then 0 else 1.5,.54,-3+(i-1)*.5)
  elseif name=="Comet" then
   size=Vector3.new(.16,.08,2.5);cf=CFrame.new(-1.8+i*.3,.54,-1.8+i*.3)*CFrame.Angles(0,-.6,0)
  elseif name=="Chevron" then
   size=Vector3.new(.18,.08,1.5);cf=CFrame.new(if i%2==0 then .55 else -.55,.54,-3+math.floor((i-1)/2)*1.05)*CFrame.Angles(0,if i%2==0 then -.7 else .7,0)
  elseif name=="Hex" then
   local a=i*math.pi/3;size=Vector3.new(.15,.08,.9);cf=CFrame.new(math.sin(a),.54,math.cos(a)+(if i>6 then 1.8 else -1.8))*CFrame.Angles(0,a+math.pi/2,0)
  elseif name=="Orbit" then
   local a=i*math.pi/6;size=Vector3.new(.16,.08,.9);cf=CFrame.new(math.sin(a)*1.7,.54,math.cos(a)*2.8)*CFrame.Angles(0,a,0)
  end
  table.insert(marks,{size=size,cf=cf})
 end
 return marks
end
return D

