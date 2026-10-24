--!strict
local D={}
D.Karts={
{id="pulse",name="Pulse GT",category="Balanced",rarity="Common",rank=1,speed=96,handling=82,boost=32,desc="A precise all-rounder. Built for your first podium."},
{id="razor",name="Razor IX",category="Speed",rarity="Rare",rank=2,speed=112,handling=64,boost=30,desc="Straight-line power with a demanding turn-in."},
{id="nova",name="Nova Drift",category="Handling",rarity="Epic",rank=3,speed=91,handling=100,boost=38,desc="Wide arcs. Tight exits. Effortless control."},
{id="spectre",name="Spectre R",category="Speed",rarity="Legendary",rank=4,speed=121,handling=57,boost=42,desc="An experimental chassis with a fierce boost."},
{id="comet",name="Comet Mini",category="Handling",rarity="Common",rank=1,speed=88,handling=94,boost=36,desc="Lightweight, agile and eager to race."},
{id="vector",name="Vector S",category="Balanced",rarity="Rare",rank=2,speed=103,handling=78,boost=35,desc="A balanced competition chassis."}}
D.Parts={
{id="motor1",name="Ion Motor",slot="Motors",price=650,effect="Speed +8",speed=8},
{id="motor2",name="Fusion Core",slot="Motors",price=1800,effect="Speed +18",speed=18},
{id="boost1",name="Flux Cell",slot="Boosts",price=500,effect="Boost +12",boost=12},
{id="wheel1",name="Mag Grip",slot="Wheels",price=450,effect="Handling +12",handling=12},
{id="paint1",name="Holo Trail",slot="Cosmetics",price=300,effect="Violet exhaust trail"}}
D.Drivers={
{id="rook",name="Rook",group="Pioneers",price=0,rent=0,speed=0,handling=4,desc="Steady hands. Handling +4."},
{id="echo",name="Echo",group="Pioneers",price=1500,rent=180,speed=5,handling=6,desc="A balanced ace. Speed +5 / Handling +6."},
{id="nyx",name="Nyx",group="Elites",price=2500,rent=250,speed=10,handling=0,desc="A fearless sprinter. Speed +10."},
{id="atlas",name="Atlas",group="Elites",price=2200,rent=220,speed=0,handling=16,desc="Track tactician. Handling +16."}}
D.Tracks={{id="zenith",name="Zenith Ring",desc="Balanced neon circuit • 2 laps",speed=1},{id="ion",name="Ion Sprint",desc="Overcharged speed zone • 2 laps",speed=1.15},{id="midnight",name="Midnight Grip",desc="Technical grip circuit • 3 laps",speed=0.9}}
D.Colors={Red=Color3.fromRGB(255,74,100),Amber=Color3.fromRGB(255,185,65),Green=Color3.fromRGB(68,234,147),Cyan=Color3.fromRGB(58,224,240),Blue=Color3.fromRGB(65,125,255),Violet=Color3.fromRGB(172,104,255)}
D.Decals={"None","Lightning","Stripes","Circuit","Star","Arrow"}
D.Cards={{name="Ion Spark",rarity="Common"},{name="Pit Crew",rarity="Common"},{name="Night Run",rarity="Common"},{name="Flux Wave",rarity="Rare"},{name="Solar Ace",rarity="Epic"},{name="Apex Legend",rarity="Legendary"}}
function D.find(list:any,id:string):any for _,v in list do if v.id==id then return v end end return nil end
function D.decorate(m:Model,design:any)
 for _,v in m:GetChildren() do if v.Name=="Decal" then v:Destroy() end end
 local function bar(x:number,z:number,w:number,l:number,angle:number)
  local p=Instance.new("Part");p.Name="Decal";p.Size=Vector3.new(w,0.06,l);p.Anchored=true;p.CanCollide=false;p.Color=D.Colors[design.accent];p.Material=Enum.Material.Neon;p.CFrame=m:GetPivot()*CFrame.new(x,0.73,z)*CFrame.Angles(0,math.rad(angle),0);p.Parent=m
 end
 local d=design.decal
 if d=="Stripes" then bar(-0.7,-2,0.3,2.6,0);bar(0.7,-2,0.3,2.6,0)
 elseif d=="Lightning" then bar(-0.3,-2.7,0.3,1.4,35);bar(0,-1.9,0.3,1.1,-50);bar(0.3,-1.1,0.3,1.4,35)
 elseif d=="Circuit" then bar(-0.9,-2,0.25,2.4,0);bar(0.9,-2,0.25,2.4,0);bar(0,-3.1,0.25,1.8,90);bar(0,-0.9,0.25,1.8,90)
 elseif d=="Star" then for i=0,3 do bar(0,-2,0.25,2.5,i*45) end
 elseif d=="Arrow" then bar(-0.5,-2.3,0.3,1.6,-40);bar(0.5,-2.3,0.3,1.6,40);bar(0,-1.5,0.3,1.5,0) end
end

return D