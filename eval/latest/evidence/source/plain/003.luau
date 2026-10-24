--!strict
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Run=game:GetService("RunService")
local A=RS:WaitForChild("Apex")
local D=require(A:WaitForChild("Data"))
local Request=A:WaitForChild("Request") :: RemoteEvent
local Push=A:WaitForChild("Push") :: RemoteEvent
local Drive=A:WaitForChild("Drive") :: RemoteEvent
local profiles:{[Player]:any}={}
local races:{[Player]:any}={}
local function fresh():any
 return {coins=2400,gems=120,xp=0,level=1,races=0,income=0,kart="pulse",driver="rook",owned={},drivers={rook=true},rentals={},equipped={},favorites={},upgrades={},livery={body="Cyan",accent="Violet",shade=100,decal="Stripes"},cards={},freeCrates=1,daily=0,lastDay=0,codes={},codeRetry=0,codeAttempts=0,job="none",questClaimed=false,boostUntil=0,offerUntil=os.time()+900,offerBought=false,party={},invites={},settings={music=60,effects=80,damage=true,shake=true,quality="High",large=false,reduced=false},tutorial=0,save="Session saved",vote="zenith",queueMode="Solo",queueEnd=0,phase="Hub",chatUntil=0,results={},reward=0}
end
local function send(p:Player,msg:string?)
 local s=profiles[p];if s then Push:FireClient(p,"State",s,msg or "") end
end
local function fail(p:Player,t:string) send(p,t) end
local function pay(s:any,c:number,g:number):boolean
 if s.coins<c or s.gems<g then return false end
 s.coins-=c;s.gems-=g;return true
end
local function grant(s:any,c:number,g:number,x:number)
 s.coins+=c;s.gems+=g;s.xp+=x;s.level=1+math.floor(s.xp/250);s.income+=c
end
local function kartModel(name:string,design:any):Model
 local m=Instance.new("Model");m.Name=name
 local bodyColor=D.Colors[design.body]:Lerp(Color3.new(0,0,0),1-design.shade/100)
 local accentColor=D.Colors[design.accent]
 local function block(n:string,size:Vector3,pos:Vector3,col:Color3,mat:Enum.Material?):Part
  local p=Instance.new("Part");p.Name=n;p.Size=size;p.CFrame=CFrame.new(pos);p.Anchored=true;p.CanCollide=false;p.Material=mat or Enum.Material.SmoothPlastic;p.Color=col;p.Parent=m;return p
 end
 local base=block("Body",Vector3.new(4.6,0.8,6.5),Vector3.zero,bodyColor);m.PrimaryPart=base
 block("Nose",Vector3.new(3.7,0.5,2),Vector3.new(0,0.3,-3),bodyColor)
 block("Cockpit",Vector3.new(2.4,0.8,2.6),Vector3.new(0,0.8,0.3),Color3.fromRGB(12,18,30))
 block("Driver",Vector3.new(1.25,1.1,1.25),Vector3.new(0,1.5,0.4),accentColor)
 block("Visor",Vector3.new(1.3,0.35,0.1),Vector3.new(0,1.55,-0.25),Color3.fromRGB(205,255,255),Enum.Material.Neon)
 block("Wing",Vector3.new(6,0.3,1),Vector3.new(0,1.1,2.8),accentColor)
 for _,x in {-2.6,2.6} do
  for _,z in {-2,2} do
   block("Wheel",Vector3.new(1.1,1.5,1.7),Vector3.new(x,-0.3,z),Color3.fromRGB(10,12,20))
   block("Rim",Vector3.new(1.15,0.65,0.9),Vector3.new(x,-0.3,z),accentColor,Enum.Material.Neon)
  end
  block("Light",Vector3.new(0.6,0.2,1),Vector3.new(x*0.65,0.5,-3.6),Color3.fromRGB(180,255,255),Enum.Material.Neon)
 end
 D.decorate(m,design)
 m.Parent=workspace;return m
end
local showroom=kartModel("Showroom",{body="Cyan",accent="Violet",shade=100,decal="Stripes"})
showroom:ScaleTo(1.6);showroom:PivotTo(CFrame.new(0,4,28)*CFrame.Angles(0,math.rad(-30),0))
local function stats(s:any,id:string):any
 local k=D.find(D.Karts,id);local u=s.upgrades[id] or {speed=0,handling=0,boost=0}
 local r={speed=k.speed+u.speed*5,handling=k.handling+u.handling*6,boost=k.boost+u.boost*5}
 for _,pid in s.equipped do local part=D.find(D.Parts,pid);if part then for _,key in {"speed","handling","boost"} do r[key]+=part[key] or 0 end end end
 local driver=D.find(D.Drivers,s.driver)
 r.speed+=driver.speed;r.handling+=driver.handling
 return r
end
local function position(a:number,lane:number,track:string?):CFrame
 local pos=Vector3.new(math.cos(a)*(125+lane)+(if track=="ion" then 360 elseif track=="midnight" then -360 else 0),4.4,-220+math.sin(a)*(85+lane))
 return CFrame.lookAt(pos,pos+Vector3.new(-125*math.sin(a),0,85*math.cos(a)))
end
local function clearRace(p:Player)
 local r=races[p];if r then for _,v in r.racers do if v.model then v.model:Destroy() end end end;races[p]=nil
end
local function hub(p:Player)
 clearRace(p);local s=profiles[p];s.phase="Hub";s.queueEnd=0
 if p.Character then p.Character:PivotTo(CFrame.new(0,5,57));local h=p.Character:FindFirstChildOfClass("Humanoid");if h then h.WalkSpeed=16 end end
 send(p,"Returned to the paddock.")
end
local function startRace(p:Player,preview:string?)
 local s=profiles[p];clearRace(p)
 local chosen=preview or s.kart
 local st=stats(s,chosen)
 local track=D.find(D.Tracks,s.vote) or D.Tracks[1]
 local r:any={start=os.clock()+4,preview=preview~=nil,track=track.id,laps=if track.id=="midnight" then 3 else 2,stats=st,throttle=0,steer=0,boost=false,energy=100,racers={},finished=false}
 local me:any={name=p.DisplayName,id=p.UserId,a=0,lane=0,speed=0,finish=false,model=kartModel("Kart_"..p.UserId,s.livery)}
 me.model:ScaleTo(if chosen=="comet" then 0.85 elseif chosen=="spectre" then 1.15 else 1)
 me.model.Driver.Color=if s.driver=="nyx" then Color3.fromRGB(220,70,150) elseif s.driver=="atlas" then Color3.fromRGB(255,180,70) elseif s.driver=="echo" then Color3.fromRGB(80,240,150) else D.Colors[s.livery.accent]
 table.insert(r.racers,me);me.model:PivotTo(position(0,0,r.track))
 if not preview then
  for i,n in {"KIRA • CPU","JAX • CPU","SOL • CPU"} do
   local v:any={name=n,id=-i,a=-0.04*i,lane=(i-2)*7,speed=0,pace=64+i*6,finish=false,model=kartModel("CPU_"..p.UserId.."_"..i,{body=({"Violet","Amber","Red"})[i],accent="Cyan",shade=100,decal="Lightning"})}
   v.model:PivotTo(position(v.a,v.lane,r.track));table.insert(r.racers,v)
  end
 end
 races[p]=r;s.phase=if preview then "Preview" else "Race";s.track=track.name;s.laps=r.laps;s.results={};s.reward=0
 if p.Character then local h=p.Character:FindFirstChildOfClass("Humanoid");if h then h.WalkSpeed=0 end;p.Character:PivotTo(CFrame.new(0,-20,0)) end
 send(p,if preview then "Preview drive • your next-race selection is unchanged." else "Get ready. Race clean.")
end
local function finish(p:Player,r:any)
 if r.finished then return end;r.finished=true
 local s=profiles[p];s.races+=1
 local rank=1
 for _,v in r.racers do if v.id~=p.UserId and v.finish then rank+=1 end end
 local reward=math.floor((600+(4-rank)*150)*(if s.boostUntil>os.time() then 2 else 1))
 grant(s,reward,15,150)
 s.reward=reward;s.phase="Results"
 if s.job=="accepted" then s.job="ready" end
 send(p,"Race reward accepted • +"..reward.." credits / +15 prisms / +150 XP")
end
Players.PlayerAdded:Connect(function(p)
 profiles[p]=fresh()
 p.CharacterAdded:Connect(function() task.wait(0.5);send(p) end)
end)
Players.PlayerRemoving:Connect(function(p) clearRace(p);profiles[p]=nil end)
for _,p in Players:GetPlayers() do profiles[p]=fresh() end
Drive.OnServerEvent:Connect(function(p,t,steer,boost)
 local r=races[p];if not r or type(t)~="number" or type(steer)~="number" or t~=t or steer~=steer then return end
 r.throttle=math.clamp(t,-1,1);r.steer=math.clamp(steer,-1,1);r.boost=boost==true
end)
local last:{[Player]:number}={}
Request.OnServerEvent:Connect(function(p,action,arg)
 local s=profiles[p];if not s or type(action)~="string" then return end
 if action=="Sync" then send(p);return end
 local now=os.clock();if now-(last[p] or 0)<0.08 then send(p,"Busy. Please retry.");return end;last[p]=now
 arg=if type(arg)=="table" then arg else {}
 local msg="Saved for this session."
 if action=="Buy" then
  local item=D.find(D.Parts,arg.id);if not item then return end
  if s.owned[item.id] then fail(p,"Already owned.");return end
  if not pay(s,item.price,0) then fail(p,"Insufficient credits.");return end
  s.owned[item.id]=true;msg=item.name.." purchased."
 elseif action=="Equip" then
  local item=D.find(D.Parts,arg.id);if not item or not s.owned[item.id] then fail(p,"This part is unavailable. Buy it in the shop.");return end
  s.equipped[item.slot]=if s.equipped[item.slot]==item.id then nil else item.id
 elseif action=="Kart" then if D.find(D.Karts,arg.id) then s.kart=arg.id end
 elseif action=="Favorite" then if D.find(D.Karts,arg.id) then s.favorites[arg.id]=not s.favorites[arg.id] end
 elseif action=="Preview" then if s.phase=="Hub" and D.find(D.Karts,arg.id) then startRace(p,arg.id);return end
 elseif action=="DriverBuy" or action=="DriverRent" then
  local d=D.find(D.Drivers,arg.id);if not d then return end
  if s.drivers[d.id] then fail(p,"Permanently owned.");return end
  if action=="DriverRent" and (s.rentals[d.id] or 0)>os.time() then fail(p,"Rental already active.");return end
  if not pay(s,if action=="DriverBuy" then d.price else d.rent,0) then fail(p,"Insufficient credits.");return end
  if action=="DriverBuy" then s.drivers[d.id]=true else s.rentals[d.id]=os.time()+600 end
 elseif action=="DriverEquip" then
  if s.drivers[arg.id] or (s.rentals[arg.id] or 0)>os.time() then s.driver=arg.id else fail(p,"Driver unavailable. Own or rent first.");return end
 elseif action=="Livery" then
  if not D.Colors[arg.body] or not D.Colors[arg.accent] or not table.find({50,75,100},arg.shade) or not table.find(D.Decals,arg.decal) then return end
  s.livery={body=arg.body,accent=arg.accent,shade=arg.shade,decal=arg.decal}
  showroom:Destroy();showroom=kartModel("Showroom",s.livery);showroom:PivotTo(CFrame.new(0,4,28)*CFrame.Angles(0,math.rad(-30),0))
 elseif action=="Upgrade" then
  if not D.find(D.Karts,arg.id) or not table.find({"speed","handling","boost"},arg.stat) then return end
  s.upgrades[arg.id]=s.upgrades[arg.id] or {speed=0,handling=0,boost=0}
  local u=s.upgrades[arg.id];local level=u[arg.stat]
  if level>=3 then fail(p,"Maximum level reached.");return end
  if not pay(s,400*(level+1),10*(level+1)) then fail(p,"Insufficient funds. Needs "..400*(level+1).." credits + "..10*(level+1).." prisms.");return end
  u[arg.stat]+=1
 elseif action=="Crate" then
  if s.freeCrates>0 then s.freeCrates-=1 elseif not pay(s,350,0) then fail(p,"Insufficient credits.");return end
  local cards={}
  for _=1,3 do
   local roll=math.random(100);local idx=if roll<=60 then math.random(1,3) elseif roll<=85 then 4 elseif roll<=97 then 5 else 6
   s.cards[tostring(idx)]=(s.cards[tostring(idx)] or 0)+1;table.insert(cards,idx)
  end
  s.reveal=cards;msg="Crate accepted. Three cards added to your collection."
 elseif action=="Daily" then
  local day=math.floor(os.time()/86400)
  if s.lastDay==day then fail(p,"Already claimed. Next claim at UTC midnight.");return end
  if s.lastDay>0 and day-s.lastDay>1 then s.daily=0;msg="Missed day: track restarted. Day 1 claimed." end
  s.daily=s.daily%7+1;s.lastDay=day;grant(s,150*s.daily,if s.daily==7 then 100 else 5,50)
  if s.daily==7 then s.freeCrates+=2 end
 elseif action=="Code" then
  if os.time()<s.codeRetry then fail(p,"Rate limited. Retry in "..(s.codeRetry-os.time()).."s.");return end
  local c=if type(arg.code)=="string" then string.upper(arg.code:match("^%s*(.-)%s*$") or "") else ""
  if #c==0 then fail(p,"Empty code. Enter APEX2026.");return end
  s.codeAttempts+=1
  if s.codeAttempts>=4 then s.codeRetry=os.time()+15;s.codeAttempts=0 end
  if s.codes[c] then msg="Already used."
  elseif c=="OLDAPEX" then msg="This code has expired."
  elseif c=="APEX2026" then s.codes[c]=true;grant(s,800,30,50);msg="Code accepted! +800 credits / +30 prisms."
  else msg="Invalid code. Try APEX2026." end
 elseif action=="Boost" then
  if s.boostUntil>os.time() then fail(p,"Credit boost already active.");return end
  if not pay(s,0,30) then fail(p,"Needs 30 prisms.");return end;s.boostUntil=os.time()+600
 elseif action=="Quest" then
  if s.races<1 or s.questClaimed then fail(p,"Race once to claim, once per session.");return end
  s.questClaimed=true;grant(s,500,20,100)
 elseif action=="Offer" then
  if s.offerBought or os.time()>=s.offerUntil then fail(p,"Offer unavailable or expired.");return end
  if not pay(s,500,0) then fail(p,"Needs 500 credits.");return end
  s.offerBought=true;s.freeCrates+=3;msg="Three crate tokens added."
 elseif action=="Job" then
  if arg.choice=="accept" and s.job=="none" then s.job="accepted";msg="Job accepted: complete one race to test the telemetry."
  elseif arg.choice=="claim" and s.job=="ready" then s.job="done";grant(s,400,10,80);msg="Telemetry delivered. +400 credits / +10 prisms."
  elseif arg.choice=="decline" then msg="No problem. Come back whenever you're ready." end
 elseif action=="Settings" then
  for _,k in {"music","effects"} do if type(arg[k])=="number" and arg[k]==arg[k] then s.settings[k]=math.clamp(math.floor(arg[k]/10+0.5)*10,0,100) end end
  for _,k in {"damage","shake","large","reduced"} do if type(arg[k])=="boolean" then s.settings[k]=arg[k] end end
  if arg.quality=="Low" or arg.quality=="High" then s.settings.quality=arg.quality end
 elseif action=="ResetSettings" then s.settings={music=60,effects=80,damage=true,shake=true,quality="High",large=false,reduced=false}
 elseif action=="Tutorial" then if type(arg.step)=="number" then s.tutorial=math.clamp(math.floor(arg.step),0,4) end
 elseif action=="Queue" then
  if s.phase~="Hub" then fail(p,"Return to the hub first.");return end
  s.queueMode=if arg.mode=="Duo" then "Duo" else "Solo";s.phase="Queue";s.queueEnd=os.time()+12;s.vote="zenith";s.votes={zenith=2,ion=1,midnight=1};msg="Queue joined. CPU drivers fill open grid slots."
 elseif action=="LeaveQueue" then
  if s.phase=="Queue" then s.phase="Hub";s.queueEnd=0;msg="Queue left. Countdown cancelled." end
 elseif action=="Vote" then
  if s.phase=="Queue" and os.time()<s.queueEnd and D.find(D.Tracks,arg.id) then
   s.votes[s.vote]-=1;s.vote=arg.id;s.votes[s.vote]+=1
  else fail(p,"Voting is closed.");return end
 elseif action=="Return" then hub(p);return
 elseif action=="Recover" then
  local r=races[p];if r then r.racers[1].lane=0;r.racers[1].speed=0;msg="Recovered to the current track section." end
 elseif action=="Chat" then
  local chats={"Good luck!","Nice overtake!","Let's race!","Great driving!","On your left!","Well played!","One more race?","Thanks!"}
  if os.time()<s.chatUntil then fail(p,"Quick chat cooldown: "..s.chatUntil-os.time().."s.");return end
  if type(arg.index)~="number" or not chats[arg.index] then return end
  s.chatUntil=os.time()+5;msg=p.DisplayName..": "..chats[arg.index]
  for _,other in Players:GetPlayers() do Push:FireClient(other,"Chat",p.DisplayName..": "..chats[arg.index]) end
 elseif action=="Invite" then
  local id=arg.id
  if id~="mira" and id~="dex" and id~="sol" then return end
  if id=="sol" then fail(p,"Sol is offline.");return end
  if s.party[id] or s.invites[id] then fail(p,"Already invited.");return end
  s.invites[id]="Pending"
  task.delay(3,function()
   if profiles[p]~=s then return end
   s.invites[id]=if id=="mira" then "Accepted" else "Declined"
   if id=="mira" then s.party[id]=true end
   send(p,if id=="mira" then "Demo Mira joined your party." else "Demo Dex declined: currently racing.")
  end)
 else return end
 s.save="Session saved";send(p,msg)
end)
local elapsed=0
Run.Heartbeat:Connect(function(dt)
 dt=math.min(dt,0.1);elapsed+=dt
 for p,s in profiles do
  if s.phase=="Queue" and os.time()>=s.queueEnd then
   local winner="zenith";for _,t in D.Tracks do if s.votes[t.id]>s.votes[winner] then winner=t.id end end
   s.vote=winner;startRace(p,nil)
  end
  for id,expiry in s.rentals do
   if expiry<=os.time() then s.rentals[id]=nil;if s.driver==id and not s.drivers[id] then s.driver="rook" end;send(p,"Rental expired. Rook is available.") end
  end
  local r=races[p]
  if r then
   local me=r.racers[1]
   if os.clock()>=r.start then
    for _,v in r.racers do
     if not v.finish then
      if v.id==p.UserId then
       local boosting=r.boost and r.energy>0 and r.throttle>0
       r.energy=math.clamp(r.energy+(if boosting then -30 else 12)*dt,0,100)
       local max=r.stats.speed*D.find(D.Tracks,r.track).speed+(if boosting then r.stats.boost else 0)
       local target=if r.throttle>0 then max*r.throttle else 0
       v.speed+=(target-v.speed)*math.min(dt*(if r.throttle<0 then 6 else 1.6),1)
       v.lane=math.clamp(v.lane+r.steer*dt*(12+r.stats.handling*0.13),-14,14)
       if math.abs(v.lane)>12 then v.speed*=1-dt*1.2 end
      else v.speed=v.pace end
      local radius=math.sqrt((125*math.sin(v.a))^2+(85*math.cos(v.a))^2)+v.lane
      v.a+=v.speed*dt/radius
      v.model:PivotTo(position(v.a,v.lane,r.track)*CFrame.Angles(0,if v.id==p.UserId then -r.steer*0.15 else 0,0))
      if not r.preview and v.a>=r.laps*math.pi*2 then v.finish=true;v.time=os.clock()-r.start;if v.id==p.UserId then finish(p,r) end end
     end
    end
   end
   if elapsed>=0.2 then
    local board={}
    for _,v in r.racers do table.insert(board,{name=v.name,id=v.id,progress=v.a,lap=math.min(r.laps,math.floor(math.max(0,v.a)/(math.pi*2))+1),finish=v.finish,time=v.time or 0}) end
    table.sort(board,function(a,b) if a.finish and b.finish then return a.time<b.time end return a.progress>b.progress end)
    s.results=board
    Push:FireClient(p,"Race",{board=board,speed=math.floor(me.speed),energy=math.floor(r.energy),count=math.max(0,math.ceil(r.start-os.clock())),lap=math.min(r.laps,math.floor(me.a/(math.pi*2))+1),laps=r.laps,progress=(me.a/(math.pi*2))%1,phase=s.phase,track=s.track,reward=s.reward})
   end
  end
 end
 if elapsed>=0.2 then elapsed=0 end
end)
for _,obj in workspace.NeonWorld:GetDescendants() do
 if obj:IsA("ProximityPrompt") then obj.Triggered:Connect(function(p) Push:FireClient(p,"Open",obj.ObjectText) end) end
end
