--!strict
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Run=game:GetService("RunService")
local A=RS:WaitForChild("Astra")
local D=require(A.Data)
local request=A.Request
local update=A.Update
local drive=A.Drive
local profiles={}
local races={}
local inputs={}
local center=Vector3.new(0,0,-340)
local function fresh()
 return {coins=1800,gems=30,xp=0,races=0,income=0,kart="vector",driver="rook",owned={},drivers={rook=true},rentals={},equipped={},favorites={},upgrades={},livery={body="Cyan",accent="Violet",shade=100,decal="Stripes"},freeCrates=1,cards={},reveals={},daily=0,lastDaily=0,codes={},settings={music=50,effects=70,shake=true,damage=true,quality=3,reduced=false},help=false,job="new",jobProgress=0,quest=false,party={},invites={},offerEnd=os.time()+900,offer=false,boosts=0,chatAt=0,codeAt=0,codeTries=0,phase="Hub",queueEnd=0,mode="Solo",vote="Orbit",track="Orbit",message="Welcome to ASTRA. Your progress is kept for this server session."}
end
local function push(p,msg)
 local st=profiles[p];if not st then return end
 if msg then st.message=msg end
 update:FireClient(p,"state",st)
end
local function award(st,c,g,x)
 st.coins+=c;st.gems+=g;st.xp+=x;st.income+=c
end
local function buildKart(p,kid)
 local st=profiles[p];local k=D.find(D.karts,kid) or D.karts[1]
 local m=Instance.new("Model");m.Name="Kart_"..p.UserId
 local bodyColor=Color3.new(0,0,0):Lerp(D.colors[st.livery.body],st.livery.shade/100)
 local accent=D.colors[st.livery.accent]
 local function part(n,size,cf,c,mat)
  local v=Instance.new("Part");v.Name=n;v.Size=size;v.CFrame=cf;v.Color=c;v.Material=mat or Enum.Material.Metal;v.Anchored=true;v.CanCollide=false;v.Parent=m;return v
 end
 local root=part("Chassis",Vector3.new(if k.category=="Agile" then 5.8 elseif k.category=="Speed" then 4.4 else 5,.9,if k.category=="Speed" then 8 else 7),CFrame.new(),bodyColor)
 m.PrimaryPart=root
 part("Nose",Vector3.new(3,.6,2.8),CFrame.new(0,.1,-4),bodyColor)
 part("Cockpit",Vector3.new(2.4,1.4,2.6),CFrame.new(0,.9,.4),Color3.fromRGB(13,20,35))
 part("Driver",Vector3.new(1.3,1.3,1.3),CFrame.new(0,2,.6),if st.driver=="rook" then Color3.fromRGB(230,240,255) else Color3.fromRGB(255,180,60),Enum.Material.Neon)
 for _,x in {-2.8,2.8} do for _,z in {-2.2,2.2} do
  part("Hover wheel",Vector3.new(1.2,1.4,2),CFrame.new(x,-.3,z),Color3.fromRGB(7,11,20))
  part("Wheel light",Vector3.new(1.3,.18,2.1),CFrame.new(x,-.3,z),accent,Enum.Material.Neon)
 end end
 for j,mark in D.markings(st.livery.decal) do part("Livery"..j,mark.size,mark.cf,accent,Enum.Material.Neon) end
 part("Wing",Vector3.new(5+k.rarity,.3,if k.category=="Speed" then 1.5 else 1),CFrame.new(0,1.4,3.4),accent)
 part("Exhaust",Vector3.new(2,.3,1),CFrame.new(0,0,4),Color3.fromRGB(45,220,255),Enum.Material.Neon)
 local lamp=Instance.new("PointLight");lamp.Color=Color3.fromRGB(155,220,255);lamp.Brightness=2;lamp.Range=24;lamp.Parent=root
 m:SetAttribute("Kart",kid);m:SetAttribute("Driver",st.driver);m:SetAttribute("Decal",st.livery.decal)
 m.Parent=workspace;return m
end
local function placeKart(r)
 local a=r.dist/r.radius
 local pos=center+Vector3.new(math.sin(a)*(r.radius+r.lane),3,math.cos(a)*(r.radius+r.lane))
 local tangent=Vector3.new(math.cos(a),0,-math.sin(a))
 r.model:PivotTo(CFrame.lookAt(pos,pos+tangent))
 if r.player and r.player.Character then
  local root=r.player.Character:FindFirstChild("HumanoidRootPart")
  if root then root.CFrame=CFrame.new(pos+Vector3.new(0,3,0));root.Anchored=true end
 end
end
local function restore(p)
 local st=profiles[p]
 local r=races[p];if r then if r.model then r.model:Destroy() end for _,b in r.bots do b.model:Destroy() end races[p]=nil end
 if p.Character then local root=p.Character:FindFirstChild("HumanoidRootPart");if root then root.Anchored=false;root.CFrame=CFrame.new(0,7,24) end
 for _,v in p.Character:GetDescendants() do if v:IsA("BasePart") then v.Transparency=if v.Name=="HumanoidRootPart" then 1 else 0 end end end
 st.phase="Hub";inputs[p]=nil;push(p,"Back in the hub. Loadout and rewards retained.")
end
local function startRace(p,preview,kid)
 local st=profiles[p]
 if races[p] then return end
 local votes={Orbit=1,Eclipse=1,Solar=1};votes[st.vote]+=1
 st.track=st.vote
 local track=D.find(D.tracks,st.track) or D.tracks[1]
 local radius=track.radius
 -- Every circuit shares the same authored arc; scale its radius for the selected layout.
 for _,part in workspace.AstraWorld:GetChildren() do
  if part:IsA("BasePart") and (part.Name=="Road" or part.Name=="Rail" or part.Name=="Lane" or part.Name=="Pylon" or part.Name=="Pylon light") then
   local old=part:GetAttribute("Original");if not old then part:SetAttribute("Original",part.CFrame);old=part.CFrame end
   local offset=old.Position-center
   part.CFrame=CFrame.new(center+Vector3.new(offset.X*radius/180,offset.Y,offset.Z*radius/180))*old.Rotation
   if part.Name=="Road" or part.Name=="Rail" then part.Size=Vector3.new(part.Size.X,part.Size.Y,10.4*radius/180+.3) end
  end
 end
 local k=D.find(D.karts,kid or st.kart)
 local u=st.upgrades[k.id] or {speed=0,handling=0,boost=0}
 local motor=D.find(D.parts,st.equipped.Motor)
 local booster=D.find(D.parts,st.equipped.Boost)
 local driver=D.find(D.drivers,st.driver)
 local r={player=p,model=buildKart(p,k.id),radius=radius,dist=0,lane=0,speed=0,energy=100,start=os.clock()+3,elapsed=0,finished=false,preview=preview,bots={},max=k.speed+u.speed*5+(motor and motor.power or 0)+driver.speed,handling=k.handling+u.handling+driver.handling+(st.equipped.Wheels and 3 or 0),boost=k.boost+u.boost*4+(booster and booster.power or 0),order={}}
 for j,name in {"KIRA / AI","JAX / AI","ONYX / AI"} do
  local m=buildKart(p,D.karts[j+1].id);m.Name=name
  for _,v in m:GetChildren() do if v:IsA("BasePart") and v.Name=="Chassis" then v.Color=D.karts[j+1].color end end
  table.insert(r.bots,{name=name,model=m,dist=-j*8,lane=(j-2)*7,radius=radius,speed=69+j*4,finished=false})
 end
 races[p]=r;st.phase=if preview then "Preview" else "Racing"
 st.queueEnd=0;st.lastReward=0
 if p.Character then for _,v in p.Character:GetDescendants() do if v:IsA("BasePart") then v.Transparency=1 end end end
 placeKart(r);push(p,if preview then "Preview drive. Exit returns without changing your race kart." else "Winning track: "..st.track.." • 3 laps. Get ready!")
end
local function spend(st,c,g)
 if st.coins<c or st.gems<g then return false end
 st.coins-=c;st.gems-=g;return true
end
request.OnServerInvoke=function(p,action,arg,extra)
 local st=profiles[p];if not st then return {ok=false,message="Profile loading"} end
 local ok=true;local msg="Saved for this server session."
 if action=="get" then return {ok=true,state=st}
 elseif action=="queue" then
  if st.phase~="Hub" then ok=false;msg="Return to the hub first." else st.mode=if arg=="Duo" then "Duo" else "Solo";st.phase="Queue";st.queueEnd=os.time()+14;st.vote="Orbit";msg="Queue joined. Local rivals are ready. Vote before the countdown ends." end
 elseif action=="cancelQueue" then if st.phase=="Queue" then st.phase="Hub";st.queueEnd=0;msg="Queue canceled. No race started." else ok=false;msg="Race has already started." end
 elseif action=="vote" then if st.phase=="Queue" and os.time()<st.queueEnd and D.find(D.tracks,arg) then st.vote=arg;msg="Vote accepted: "..arg else ok=false;msg="Voting is closed." end
 elseif action=="return" then restore(p);return {ok=true,state=st}
 elseif action=="preview" then if st.phase=="Hub" and D.find(D.karts,arg) then startRace(p,true,arg) else ok=false;msg="Preview unavailable during a race." end
 elseif action=="recover" then local r=races[p];if r then r.lane=0;r.speed=0;placeKart(r);msg="Recovered to the center of your current sector." end
 elseif action=="kart" then if D.find(D.karts,arg) then st.kart=arg;msg="Next race kart selected." else ok=false end
 elseif action=="favorite" then if D.find(D.karts,arg) then st.favorites[arg]=not st.favorites[arg] end
 elseif action=="buy" then
  local item=D.find(D.parts,arg)
  if not item then ok=false;msg="Unknown part." elseif st.owned[arg] then ok=false;msg="Already owned." elseif spend(st,item.price,0) then st.owned[arg]=true;msg=item.name.." purchased." else ok=false;msg="Insufficient credits. Nothing spent." end
 elseif action=="equip" then
  local item=D.find(D.parts,arg)
  if item and st.owned[arg] then st.equipped[item.slot]=if st.equipped[item.slot]==arg then nil else arg;msg="Equipment saved." else ok=false;msg="Purchase this part first." end
 elseif action=="driverBuy" or action=="driverRent" then
  local d=D.find(D.drivers,arg)
  if not d then ok=false;msg="Unknown driver." elseif st.drivers[arg] then ok=false;msg="Permanently owned." elseif action=="driverRent" and (st.rentals[arg] or 0)>os.time() then ok=false;msg="Rental already active."
  elseif spend(st,if action=="driverBuy" then d.price else d.rent,0) then
   if action=="driverBuy" then st.drivers[arg]=true else st.rentals[arg]=os.time()+600 end
   msg=if action=="driverBuy" then "Driver purchased permanently." else "Driver rented for 10 minutes."
  else ok=false;msg="Insufficient credits. Nothing spent." end
 elseif action=="driver" then
  if st.drivers[arg] or (st.rentals[arg] or 0)>os.time() then st.driver=arg;msg="Driver equipped." else ok=false;msg="Driver unavailable. Buy or rent first." end
 elseif action=="livery" then
  if type(arg)=="table" and D.colors[arg.body] and D.colors[arg.accent] and table.find({50,75,100},arg.shade) and table.find(D.decals,arg.decal) then st.livery={body=arg.body,accent=arg.accent,shade=arg.shade,decal=arg.decal};msg="Design saved for this session." else ok=false;msg="Invalid design." end
 elseif action=="upgrade" then
  if D.find(D.karts,arg) and table.find({"speed","handling","boost"},extra) then
   local u=st.upgrades[arg] or {speed=0,handling=0,boost=0};local n=u[extra]
   if n>=3 then ok=false;msg="Maximum level reached." elseif spend(st,300*(n+1),5*(n+1)) then u[extra]+=1;st.upgrades[arg]=u;msg="Upgrade installed on "..D.find(D.karts,arg).name else ok=false;msg="Insufficient credits or crystals. Nothing spent." end
  else ok=false;msg="Invalid upgrade." end
 elseif action=="crate" then
  if st.freeCrates>0 then st.freeCrates-=1 elseif not spend(st,400,0) then ok=false;msg="Insufficient credits. Nothing spent." end
  if ok then st.reveals={} for j=1,3 do local roll=math.random(100);local idx=if roll<=60 then math.random(1,3) elseif roll<=90 then math.random(4,5) else 6;local name=D.cards[idx];table.insert(st.reveals,name);st.cards[name]=(st.cards[name] or 0)+1 end msg="Crate accepted. Three cards added to your collection." end
 elseif action=="daily" then
  local day=math.floor(os.time()/86400);local last=math.floor(st.lastDaily/86400)
  if last==day then ok=false;msg="Already claimed. Next reward at UTC midnight." else
   local missed=st.lastDaily>0 and day-last>1
   st.daily=if missed or st.daily>=7 then 1 else st.daily+1;st.lastDaily=os.time()
   award(st,150+st.daily*50,if st.daily==7 then 30 else 2,25)
   if st.daily==7 then st.freeCrates+=2 end
   msg=if missed then "Missed day: track restarted. Day 1 reward granted." else "Day "..st.daily.." reward granted."
  end
 elseif action=="code" then
  if os.time()<st.codeAt then ok=false;msg="Rate limited. Retry in "..(st.codeAt-os.time()).."s."
  else
   local code=if type(arg)=="string" then string.upper(arg:match("^%s*(.-)%s*$")) else ""
   st.codeTries+=1
   if st.codeTries>=5 then st.codeAt=os.time()+20;st.codeTries=0 end
   if code=="" then ok=false;msg="Enter a code." elseif st.codes[code] then ok=false;msg="Already used." elseif code=="OLDORBIT" then ok=false;msg="This code expired." elseif code~="NEONSTART" then ok=false;msg="Invalid code. Try NEONSTART." else st.codes[code]=true;award(st,600,10,50);msg="Code redeemed: +600 credits, +10 crystals, +50 XP." end
  end
 elseif action=="quest" then if st.races>=1 and not st.quest then st.quest=true;award(st,350,5,100);msg="First finish quest claimed." else ok=false;msg=if st.quest then "Already claimed." else "Finish one race first." end
 elseif action=="offer" then if st.offer or os.time()>=st.offerEnd then ok=false;msg="Offer unavailable or expired." elseif spend(st,500,0) then st.offer=true;st.freeCrates+=2;st.boosts+=2;msg="Starter offer claimed: 2 crates + 2 race boosters." else ok=false;msg="Insufficient credits." end
 elseif action=="boost" then if st.boosts>0 then st.boosts-=1;st.boostActive=true;msg="Next race reward boosted by 200 credits." else ok=false;msg="No boosters. Find them in the starter offer." end
 elseif action=="job" then if arg=="accept" and st.job=="new" then st.job="active";msg="Collect the three green energy cells around the hub." elseif arg=="claim" and st.jobProgress>=3 and st.job~="done" then st.job="done";award(st,300,5,75);msg="Job complete. +300 credits, +5 crystals." elseif arg=="decline" then msg="No worries. Come back anytime." else msg="Mechanic: collect three green cells, then come back." end
 elseif action=="invite" then
  if arg=="SOL / Demo" or arg=="MIRA / Demo" then
   if st.invites[arg] or st.party[arg] then ok=false;msg="Invitation already sent." else st.invites[arg]="Pending";msg="Invitation pending."
    task.delay(2,function() if not profiles[p] then return end st.invites[arg]=if arg=="SOL / Demo" then "Accepted" else "Declined";if arg=="SOL / Demo" then st.party[arg]=true end push(p,arg.." "..st.invites[arg]) end)
   end
  else ok=false;msg="Offline friends cannot be invited." end
 elseif action=="chat" then
  if not table.find(D.chat,arg) then ok=false;msg="Invalid message." elseif os.time()-st.chatAt<5 then ok=false;msg="Chat cooldown: "..(5-(os.time()-st.chatAt)).."s." else st.chatAt=os.time();msg=p.DisplayName..": "..arg;update:FireAllClients("chat",msg) end
 elseif action=="settings" then
  if type(arg)=="table" then
   for _,key in {"music","effects"} do if type(arg[key])=="number" then st.settings[key]=math.clamp(math.floor(arg[key]),0,100) end end
   for _,key in {"shake","damage","reduced"} do if type(arg[key])=="boolean" then st.settings[key]=arg[key] end end
   if type(arg.quality)=="number" then st.settings.quality=math.clamp(math.floor(arg.quality),1,3) end
   msg="Settings saved for this session."
  else ok=false;msg="Settings rejected." end
 elseif action=="help" then st.help=true;msg="Help progress saved."
 else ok=false;msg="Unknown request." end
 push(p,msg);return {ok=ok,message=msg,state=st}
end
drive.OnServerEvent:Connect(function(p,throttle,steer,boost)
 if type(throttle)=="number" and type(steer)=="number" and throttle==throttle and steer==steer then inputs[p]={throttle=math.clamp(throttle,-1,1),steer=math.clamp(steer,-1,1),boost=boost==true,at=os.clock()} end
end)
Players.PlayerAdded:Connect(function(p)
 profiles[p]=fresh()
 p.CharacterAdded:Connect(function() task.wait(.6);push(p) end)
end)
Players.PlayerRemoving:Connect(function(p) if races[p] then restore(p) end profiles[p]=nil;inputs[p]=nil end)
for _,p in Players:GetPlayers() do profiles[p]=fresh() end
local tickClock=0
Run.Heartbeat:Connect(function(dt)
 dt=math.min(dt,.1);tickClock+=dt
 for p,st in profiles do
  if st.phase=="Queue" and os.time()>=st.queueEnd then startRace(p,false) end
  if not st.drivers[st.driver] and (st.rentals[st.driver] or 0)<=os.time() then st.driver="rook";push(p,"Rental expired. Rook equipped; permanent ownership is unchanged.") end
  local r=races[p]
  if r and not r.finished then
   local inp=inputs[p] or {throttle=0,steer=0,boost=false,at=0}
   if os.clock()-inp.at>1 then inp={throttle=0,steer=0,boost=false,at=0} end
   local started=os.clock()>=r.start
   if started then
    local boosting=inp.boost and r.energy>1 and inp.throttle>0
    r.energy=math.clamp(r.energy+(if boosting then -32 else 14)*dt,0,100)
    local target=if inp.throttle>0 then (r.max+(if boosting then r.boost else 0))*inp.throttle else 0
    r.speed+=math.clamp(target-r.speed,-(if inp.throttle<0 then 100 else 45)*dt,55*dt)
    r.lane=math.clamp(r.lane+inp.steer*r.handling*3*dt,-12.8,12.8)
    if math.abs(r.lane)>12 then r.speed=math.min(r.speed,45) end
    r.dist+=r.speed*dt;r.elapsed+=dt
    for _,b in r.bots do if not b.finished then b.dist+=b.speed*dt;if b.dist>=math.pi*2*r.radius*3 then b.finished=true;table.insert(r.order,b.name) end end placeKart(b) end
    if r.dist>=math.pi*2*r.radius*3 and not r.preview then
     r.finished=true;table.insert(r.order,p.DisplayName);st.phase="Results";st.races+=1
     local place=#r.order;local coins=650+(4-place)*150+(if st.boostActive then 200 else 0);st.boostActive=false
     award(st,coins,8,120);st.lastReward=coins;st.finishPlace=place
     st.results=table.clone(r.order);for _,b in r.bots do if not b.finished then table.insert(st.results,b.name.." • still racing") end end
     push(p,"Finish accepted! +"..coins.." credits • +8 crystals • +120 XP")
    end
   end
   placeKart(r)
  end
  if r and r.finished then
   local changed=false
   for _,b in r.bots do
    if not b.finished then b.dist+=b.speed*dt;placeKart(b)
     if b.dist>=math.pi*2*r.radius*3 then b.finished=true;table.insert(r.order,b.name);changed=true end
    end
   end
   if changed then
    st.results=table.clone(r.order)
    local remaining={} for _,b in r.bots do if not b.finished then table.insert(remaining,b) end end
    table.sort(remaining,function(a,b) return a.dist>b.dist end)
    for _,b in remaining do table.insert(st.results,b.name.." • still racing") end
    push(p)
   end
  end
  if tickClock>=.15 and r then
   local rows={{name=p.DisplayName,dist=r.dist,lap=math.min(3,math.floor(r.dist/(math.pi*2*r.radius))+1),finished=r.finished,localPlayer=true}}
   for _,b in r.bots do table.insert(rows,{name=b.name,dist=b.dist,lap=math.min(3,math.floor(b.dist/(math.pi*2*r.radius))+1),finished=b.finished,localPlayer=false}) end
   table.sort(rows,function(a,b) return a.dist>b.dist end)
   local pos=1;for j,v in rows do if v.localPlayer then pos=j end end
   update:FireClient(p,"race",{rows=rows,position=pos,lap=math.min(3,math.floor(r.dist/(math.pi*2*r.radius))+1),speed=math.floor(r.speed),energy=math.floor(r.energy),countdown=math.max(0,math.ceil(r.start-os.clock())),time=math.floor(r.elapsed),progress=(r.dist%(math.pi*2*r.radius))/(math.pi*2*r.radius),track=st.track})
  end
 end
 if tickClock>=.15 then tickClock=0 end
end)
for j,pos in {Vector3.new(-24,6,6),Vector3.new(25,6,12),Vector3.new(4,6,-18)} do
 local cell=Instance.new("Part");cell.Name="Energy cell "..j;cell.Size=Vector3.new(2,3,2);cell.CFrame=CFrame.new(pos)*CFrame.Angles(0,.6,0);cell.Color=Color3.fromRGB(60,255,140);cell.Material=Enum.Material.Neon;cell.Anchored=true;cell.Parent=workspace.AstraWorld
 local pr=Instance.new("ProximityPrompt");pr.ActionText="Collect cell";pr.ObjectText="Mechanic job";pr.HoldDuration=.3;pr.Parent=cell
 pr.Triggered:Connect(function(p) local st=profiles[p];local root=p.Character and p.Character:FindFirstChild("HumanoidRootPart");if st and st.job=="active" and root and (root.Position-cell.Position).Magnitude<14 then st.cells=st.cells or {};if not st.cells[j] then st.cells[j]=true;st.jobProgress+=1;push(p,"Energy cells: "..st.jobProgress.."/3. Return to the mechanic when complete.") end end end)
end
