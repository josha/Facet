--!strict
local Players=game:GetService("Players")
local Run=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local Gui=game:GetService("GuiService")
local RS=game:GetService("ReplicatedStorage")
local Facet=require(RS.Packages.Facet)
local C=Facet.Compose
local A=RS:WaitForChild("Astra")
local D=require(A.Data)
local player=Players.LocalPlayer
local initial=A.Request:InvokeServer("get").state
local state=C.cell(initial)
local race=C.cell({rows={},position=1,lap=1,speed=0,energy=100,countdown=3,time=0,progress=0,track="Orbit"})
local notice=C.cell(initial.message)
local pending=C.cell(false)
local path=C.cell({})
local page=C.cell("")
local clock=C.cell(os.time())
local mode=C.cell("Solo")
local chatOpen=C.cell(false)
local scoreOpen=C.cell(false)
local training=C.cell(not initial.help)
local trainingStep=C.cell(1)
local confirmOpen=C.cell(false)
local confirmTitle=C.cell("")
local confirmText=C.cell("")
local confirmLabel=C.cell("Confirm")
local confirmAction=function() end
local context=Instance.new("InputContext");context.Name="AstraDriving";context.Parent=player.PlayerGui
local held={forward=false,brake=false,left=false,right=false,boost=false}
local function bind(name,keys,pressed,released)
 local action=Instance.new("InputAction");action.Name=name;action.Type=Enum.InputActionType.Bool;action.Parent=context
 for j,key in keys do local b=Instance.new("InputBinding");b.Name="Binding"..j;b.KeyCode=key;b.Parent=action end
 action.Pressed:Connect(pressed);if released then action.Released:Connect(released) end
 return action
end
local rgb=function(r,g,b) return {r=r/255,g=g/255,b=b/255} end
local typography={}
for role,size in {caption=17,label=20,body=20,control=20,strong=20,numeral=28,heading=26,title=36} do typography[role]={size=size,font={family="rbxasset://fonts/families/BuilderSans.json"}} end
local theme,report=Facet.themes.define({base=Facet.themes.neutralPackage(),metrics={typography=typography},identity={id="astra",displayName="ASTRA"},style={defaultTheme="Astra",themes={{name="Astra",colors={surface=rgb(8,14,27),surfaceStrong=rgb(15,25,43),content=rgb(228,243,255),accent=rgb(43,226,238),onAccent=rgb(4,14,24)},extra={control=rgb(25,40,62),controlSelected=rgb(69,40,110),contentSecondary=rgb(153,183,207),hairline=rgb(44,208,230),hairlineOpacity=.25}}}}})
assert(report.ok)
local app=Facet.app({name="ASTRA",theme=theme})
local UI=app.UI
local Host=app.runtime.constructors
local function send(action,arg,extra)
 if pending:peek() then return nil end
 pending:set(true);notice:set("Sending…")
 local ok,result=pcall(function() return A.Request:InvokeServer(action,arg,extra) end)
 pending:set(false)
 if ok then state:set(result.state);notice:set(result.message or result.state.message);return result end
 notice:set("Connection failed. Your request was not confirmed.");return nil
end
local dialogueOrigin: Vector3? = nil
local function open(name)
 if name=="Mechanic" then local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart");dialogueOrigin=if root then root.Position else nil end
 if name=="Livery" then end
 page:set(name);path:set({{id=name,value=name}})
end
local function close() page:set("");path:set({}) end
local function confirm(title,terms,fn)
 confirmTitle:set(title);confirmText:set(terms);confirmLabel:set(if title:find("Discard") then "Discard" else "Confirm");confirmAction=fn;confirmOpen:set(true)
end
local function text(value,role)
 return UI.Text {text=value,textRole=role or "body",wrap=true,Size=UDim2.new(1,0,0,0),AutoLocalize=false}
end
local function button(label,fn,emphasis)
 return UI.Button {label=label,onActivate=fn,appearance=if emphasis then "emphasis" else "standard",enabled=function(use) return not use(pending) end}
end
local function row(children) children.gap="s";children.wrap=true;children.width="fill";return UI.HStack(children) end
local function section(children) children.gap="m";children.width="fill";children.padding="m";children.surface="panel";return UI.VStack(children) end
local function pageShell(title,body)
 local oldTouch=Gui.TouchControlsEnabled
 Gui.TouchControlsEnabled=false;context.Enabled=false
 if title=="MECHANIC / REN" then Gui.TouchControlsEnabled=oldTouch;context.Enabled=true end
 C.cleanup(function() Gui.TouchControlsEnabled=oldTouch;context.Enabled=true;for k in held do held[k]=false end end)
 return UI.VStack {surface="surface",width="fill",height="fill",
  UI.Screen {
   UI.NavBar {title=title,trailing=button("Close / B",close)},
   text(function(use) local st=use(state);return string.format("%s CR   •   %s ◈   •   LV %d",st.coins,st.gems,1+math.floor(st.xp/300)) end,"caption"),
   UI.ScrollView {width="fill",height="fill",UI.fill(),UI.VStack {width="fill",maxWidth=1100,gap="m",padding="s",body()}},
   text(notice,"caption"),
  }
 }
end
local destinations={}
destinations.Queue={content=function() return pageShell("RACE TERMINAL",function()
 return UI.VStack {width="fill",gap="m",
  text("Choose your grid.","title"),text("Three laps. Three rivals. Earn credits, crystals and XP. Hold W / RT to accelerate; A/D to change line. Space boosts."),
  UI.Picker {selected=mode,options={{value="Solo",label="Solo"},{value="Duo",label="Duo"}},style="segmented"},
  button("Join queue",function() send("queue",mode:peek()) end,true),
  text(function(use) local st=use(state);return if st.phase=="Queue" then string.format("%s • %d / %d ready • starts in %ds",st.mode,if st.mode=="Duo" then 2 else 1,if st.mode=="Duo" then 2 else 1,math.max(0,st.queueEnd-use(clock))) else "Queue open • local AI rivals included" end,"heading"),
  text("TRACK VOTE","caption"),
  button(function(use) return (if use(state).vote=="Orbit" then "✓ " else "").."ORBIT • Fast cyan sweepers • "..(if use(state).vote=="Orbit" then 2 else 1).." votes" end,function() send("vote","Orbit") end),
  button(function(use) return (if use(state).vote=="Eclipse" then "✓ " else "").."ECLIPSE • Tight violet turns • "..(if use(state).vote=="Eclipse" then 2 else 1).." votes" end,function() send("vote","Eclipse") end),
  button(function(use) return (if use(state).vote=="Solar" then "✓ " else "").."SOLAR • Wide amber arcs • "..(if use(state).vote=="Solar" then 2 else 1).." votes" end,function() send("vote","Solar") end),
  text("Kira votes Orbit • Jax votes Eclipse • Onyx votes Solar. Your vote breaks the tie. Duo includes Kira as your local demo teammate."),
  button("Leave queue",function() send("cancelQueue") end),
 }
end) end}
destinations.Scoreboard={content=function() return pageShell("LIVE GRID",function()
 return UI.VStack {width="fill",gap="m",text("Leaders first • circuit racing • no knockout rules","caption"),text(function(use)
  local lines={} for j,r in use(race).rows do table.insert(lines,string.format("%02d   %s%s   |   LAP %d/3   |   %s",j,if r.localPlayer then "YOU • " else "",r.name,r.lap,if r.finished then "FINISHED" else "RACING")) end return table.concat(lines,"\n\n")
 end,"heading")}
end) end}
destinations.Results={content=function() return pageShell("RACE COMPLETE",function()
 return UI.VStack {width="fill",gap="m",text(function(use) return "P"..(use(state).finishPlace or 1).." / FINISH ACCEPTED" end,"title"),text(function(use) return "+"..(use(state).lastReward or 0).." credits  •  +8 crystals  •  +120 XP" end,"heading"),text(function(use) return table.concat(use(state).results or {},"\n\n") end),button("Return to the hub",function() send("return");close() end,true)}
end) end}
-- More task destinations are registered below.
local function hud()
 return UI.Composition "FlightDeck" {
  UI.Region "Identity" {zone="topLeft",rank=1,
   UI.VStack {gap="xs",surface="panel",padding="m",Size=UDim2.fromOffset(280,0),
    text("A S T R A","title"),text("NEON CIRCUIT  /  SEASON 01","caption"),
    text(function(use) local st=use(state);return string.format("%d CR   /   %d ◈",st.coins,st.gems) end,"numeral"),
    text(function(use) local st=use(state);return string.format("LV %d  •  XP %d/300  •  %d races",1+math.floor(st.xp/300),st.xp%300,st.races) end,"caption"),
   },
   UI.VStack {surface="panel",padding="s",Size=UDim2.fromOffset(118,0),
    text(function(use) local s=use(state);return s.coins.." CR\n"..s.gems.." ◈  /  L"..(1+math.floor(s.xp/300)) end,"caption")},
  },
  UI.Region "Commands" {zone="topRight",rank=2,
   UI.VStack {gap="s",surface="panel",padding="s",Size=UDim2.fromOffset(220,0),
    button("RACE  /  X",function() open("Queue") end,true),
    button("Garage",function() open("Garage") end),
    button("Market",function() open("Shop") end),
    button(function(use) return if math.floor(use(state).lastDaily/86400)<math.floor(use(clock)/86400) then "Rewards • READY" else "Mission control" end,function() open("Rewards") end),
    button("More / Settings",function() open("More") end),
   },button("Menu / X",function() open("More") end)},
  UI.Region "Telemetry" {zone="top",rank=1,
   UI.VStack {gap="xs",surface="panel",padding="s",Size=UDim2.fromOffset(260,0),
    text(function(use) local st=use(state);local r=use(race);return if st.phase=="Racing" or st.phase=="Preview" then (if r.countdown>0 then "START IN "..r.countdown else string.format("P%d   •   LAP %d / 3",r.position,r.lap)) elseif st.phase=="Queue" then "GRID OPENS IN "..math.max(0,st.queueEnd-use(clock)) else "WELCOME TO THE PADDOCK" end,"heading"),
    text(function(use) local r=use(race);return if use(state).phase=="Racing" or use(state).phase=="Preview" then string.format("%03d km/h   •   BOOST %d%%",r.speed,r.energy) else "Prepare. Race. Evolve." end,"caption"),
   },UI.VStack {surface="panel",padding="s",Size=UDim2.fromOffset(112,0),
    text(function(use) local r=use(race);return if use(state).phase=="Racing" or use(state).phase=="Preview" then "P"..r.position.."  L"..r.lap.."/3\n"..r.speed.." km/h" else "ASTRA\nNEON CIRCUIT" end,"caption")}},
  UI.Region "LiveGrid" {zone="left",rank=3,mayDrop=true,
 UI.VStack {gap="s",surface="panel",padding="m",Size=UDim2.fromOffset(290,0),Visible=scoreOpen,
  text("LIVE GRID / 3 LAPS","heading"),
  text(function(use) local lines={} for j,r in use(race).rows do table.insert(lines,j..". "..(if r.localPlayer then "YOU" else r.name).."  /  L"..r.lap.."  /  "..(if r.finished then "FIN" else "RACING")) end return table.concat(lines,"\n\n") end,"caption"),
  button("Close grid / Tab",function() scoreOpen:set(false) end),
 }},
UI.Region "RaceActions" {zone="right",rank=3,

   UI.VStack {gap="s",Size=UDim2.fromOffset(165,0),
    button("Grid / Tab",function() scoreOpen:set(not scoreOpen:peek()) end),
    button("Chat / Q / Y",function() chatOpen:set(true) end),
    button("Recover / R",function() send("recover") end),
    button("Exit drive",function() send("return");close() end),
   },button("Race tools",function() open("RaceTools") end)},
  UI.Region "TouchDrive" {zone="right",rank=4,
   UI.VStack {gap="s",Size=UDim2.fromOffset(190,0),Visible=function(use) return use(state).phase=="Racing" or use(state).phase=="Preview" end,
    button("Throttle • toggle",function() held.forward=not held.forward;held.brake=false end,true),
    button("Brake",function() held.forward=false;held.brake=true;task.delay(.6,function() held.brake=false end) end),
    row({button("◀",function() held.left=true;task.delay(.35,function() held.left=false end) end),button("▶",function() held.right=true;task.delay(.35,function() held.right=false end) end)}),
    button("Boost • toggle",function() held.boost=not held.boost end),
   },UI.VStack {gap="xs",Size=UDim2.fromOffset(100,0),Visible=function(use) return use(state).phase=="Racing" or use(state).phase=="Preview" end,
    button("Go / Stop",function() held.forward=not held.forward;held.brake=false end,true),
    button("◀",function() held.left=true;task.delay(.3,function() held.left=false end) end),
    button("▶",function() held.right=true;task.delay(.3,function() held.right=false end) end),
    button("Boost",function() held.boost=not held.boost end),
   }},
  UI.Region "Training" {zone="left",rank=5,mayDrop=true,
   UI.VStack {gap="s",padding="s",surface="panel",Size=UDim2.fromOffset(265,0),Visible=function(use) return use(training) and use(state).phase=="Hub" end,
    text(function(use) return "FLIGHT SCHOOL  "..use(trainingStep).."/3" end,"heading"),
    text(function(use) return ({"↓ Inspect and choose a kart.","↓ Buy a part, then equip it.","↓ Queue, vote, then race."})[use(trainingStep)] end,"caption"),
    button(function(use) return ({"OPEN GARAGE","OPEN MARKET","OPEN QUEUE"})[use(trainingStep)] end,function() open(({"Garage","Shop","Queue"})[trainingStep:peek()]) end,true),
    row({UI.Button {label="Back",enabled=function(use) return use(trainingStep)>1 end,onActivate=function() trainingStep:set(math.max(1,trainingStep:peek()-1)) end},
      button("Next",function() if trainingStep:peek()==3 then training:set(false);send("help") else trainingStep:set(trainingStep:peek()+1) end end),
      button("Skip",function() training:set(false);send("help") end)}),
   }},
  UI.Region "Status" {zone="bottom",rank=2,
   UI.VStack {surface="panel",padding="s",gap="xs",Size=UDim2.fromOffset(330,0),
    text(notice,"caption"),
    text("W / RT accelerate  •  S / LT brake  •  A D steer  •  Space / RB boost","caption"),
   }},
 }
end

local selected=C.cell("vector")
local search=C.cell("")
local category=C.cell("All")
local rarity=C.cell("All")
local sort=C.cell("Name")
local shopFilter=C.cell("All")
local code=C.cell("")
local driverGroup=C.cell("All")
local partySearch=C.cell("")
local reveal=C.cell(0)
local draftBody=C.cell(initial.livery.body)
local draftAccent=C.cell(initial.livery.accent)
local draftShade=C.cell(initial.livery.shade)
local draftDecal=C.cell(initial.livery.decal)
local dirty=C.cell(false)
local helpStep=C.cell(1)
local function options(list)
 local t={} for _,v in list do table.insert(t,{value=v,label=tostring(v)}) end return t
end
local function choice(label,cell,list)
 return UI.VStack {width="fill",gap="xs",text(label,"caption"),UI.Picker {selected=cell,options=options(list),style="menu"}}
end
local function preview(kartCell,livery)
 return UI.Stage {Size=UDim2.new(1,0,0,230),camera=CFrame.lookAt(Vector3.new(10,7,-13),Vector3.zero),fieldOfView=38,
 content=function(runtime,world)
  local Host=runtime.constructors
  local function piece(name,size,cf,color,mat)
   Host.Part(name){Parent=C.static(world),Anchored=true,CanCollide=false,Size=size,CFrame=cf,Color=color,Material=mat or Enum.Material.Metal}
  end
  piece("Body",function(use) local k=D.find(D.karts,use(kartCell));return Vector3.new(if k.category=="Agile" then 5.8 elseif k.category=="Speed" then 4.4 else 5,.9,if k.category=="Speed" then 8 else 7) end,CFrame.new(),function(use)
   if livery then return Color3.new(0,0,0):Lerp(D.colors[use(draftBody)],use(draftShade)/100) end
   return D.find(D.karts,use(kartCell)).color
  end)
  piece("Nose",Vector3.new(3,.6,2),CFrame.new(0,0,-4),function(use) return if livery then Color3.new(0,0,0):Lerp(D.colors[use(draftBody)],use(draftShade)/100) else D.find(D.karts,use(kartCell)).color end)
  piece("Canopy",Vector3.new(2.5,1.6,2.8),CFrame.new(0,1,.5),Color3.fromRGB(15,23,42))
  for _,x in {-2.8,2.8} do for _,z in {-2.2,2.2} do
   piece("Wheel",Vector3.new(1.1,1.5,2.1),CFrame.new(x,-.3,z),Color3.fromRGB(12,18,28))
   piece("Rim",Vector3.new(1.2,.2,2.2),CFrame.new(x,-.3,z),function(use) return if livery then D.colors[use(draftAccent)] else Color3.fromRGB(40,235,245) end,Enum.Material.Neon)
  end end
  piece("Wing",function(use) local k=D.find(D.karts,use(kartCell));return Vector3.new(5+k.rarity,.3,if k.category=="Speed" then 1.5 else 1) end,CFrame.new(0,1.4,3.5),function(use) return if livery then D.colors[use(draftAccent)] else D.find(D.karts,use(kartCell)).color end)
  for j=1,12 do
   piece("Mark"..j,function(use) return D.markings(if livery then use(draftDecal) else "Stripes")[j].size end,
   function(use) return D.markings(if livery then use(draftDecal) else "Stripes")[j].cf end,
   function(use) return if livery then D.colors[use(draftAccent)] else Color3.fromRGB(225,245,255) end,Enum.Material.Neon)
  end
  return nil
 end}
end
local function garage()
 local list={}
 for _,k in D.karts do
  table.insert(list,button(function(use) return (if use(selected)==k.id then "▶ " else "")..k.name.."  •  "..k.category.."  •  R"..k.rarity.."  •  "..k.speed.." km/h"..(if use(state).favorites[k.id] then "  ★" else "") end,function() selected:set(k.id) end))
  list[#list].Visible=true
 end
 -- Filtering and sorting updates retained native row order; selection lives in the model.
 for j,k in D.karts do
  local item=list[j]
  item.Visible=true
  C.watch(function(use)
   local q=string.lower(use(search));local cat=use(category);local r=use(rarity)
   item.Visible=(q=="" or string.find(string.lower(k.name),q,1,true)~=nil) and (cat=="All" or cat==k.category) and (r=="All" or tonumber(r)==k.rarity)
   local ranked=table.clone(D.karts)
   table.sort(ranked,function(a,b)
    if use(sort)=="Speed" and a.speed~=b.speed then return a.speed>b.speed elseif use(sort)=="Rarity" and a.rarity~=b.rarity then return a.rarity>b.rarity end return a.name<b.name
   end)
   for idx,v in ranked do if v.id==k.id then item.LayoutOrder=idx end end
  end)
 end
 return UI.VStack {width="fill",gap="m",
  text("ENGINEER YOUR EDGE","title"),
  row({button("Inventory",function() open("Inventory") end),button("Drivers",function() open("Drivers") end),button("Livery studio",function() open("Livery") end),button("Upgrades",function() open("Upgrades") end)}),
  UI.TextInput {value=search,placeholder="Search kart names",label="Search",clearButton=true},
  button("Clear search",function() search:set("") end),
  choice("Category",category,{"All","Balanced","Speed","Agile"}),
  choice("Rarity",rarity,{"All","1","2","3","4"}),
  choice("Sort",sort,{"Name","Speed","Rarity"}),
  UI.VStack(list),
  text(function(use)
   local count=0 for _,k in D.karts do if (use(search)=="" or string.find(string.lower(k.name),string.lower(use(search)),1,true)) and (use(category)=="All" or use(category)==k.category) and (use(rarity)=="All" or tonumber(use(rarity))==k.rarity) then count+=1 end end
   return if count==0 then "No matching karts. Clear search or adjust filters. Your selection is retained." else count.." karts • selection stays when filtering"
  end,"caption"),
  section({text(function(use) return D.find(D.karts,use(selected)).name end,"title"),preview(selected,false),
   text(function(use) local k=D.find(D.karts,use(selected));return string.format("SPEED %d   /   HANDLING %d   /   BOOST +%d\n%s • Rarity %d • Available",k.speed,k.handling,k.boost,k.category,k.rarity) end,"heading"),
   text(function(use) return if use(state).kart==use(selected) then "EQUIPPED FOR NEXT RACE" else "SELECTED FOR INSPECTION" end,"caption"),
   row({button("Choose for next race",function() send("kart",selected:peek()) end,true),button("Try kart",function() local r=send("preview",selected:peek());if r and r.ok then close() end end),button("Favorite ★",function() send("favorite",selected:peek()) end)}),
  }),
 }
end
destinations.Garage={content=function() return pageShell("GARAGE / FLEET",garage) end}
destinations.Shop={content=function() return pageShell("MARKET / PERFORMANCE",function()
 local children={text("BUILD A FASTER TOMORROW","title"),text("Parts are owned once and equipped in the garage. Full prices in credits."),choice("Browse",shopFilter,{"All","Motor","Boost","Wheels","Cosmetics"}),row({button("Redeem code",function() open("Codes") end),button("Inventory",function() open("Inventory") end)})}
 for _,item in D.parts do
  local card=section({text(item.name,"heading"),text(item.slot.."  •  "..item.effect),text(function(use) return if use(state).owned[item.id] then "OWNED" else item.price.." credits • "..(if use(state).coins>=item.price then "Affordable" else "Insufficient credits") end,"caption"),
   button("Buy • "..item.price.." credits",function() confirm("Purchase "..item.name.."?",item.effect.."\nFull price: "..item.price.." credits. Ownership is permanent for this server session.",function() send("buy",item.id) end) end,true)})
  C.watch(function(use) card.Visible=use(shopFilter)=="All" or use(shopFilter)==item.slot end)
  table.insert(children,card)
 end
 return UI.VStack(children)
end) end}
destinations.Codes={content=function() return pageShell("REDEEM A SIGNAL",function()
 return UI.VStack {width="fill",gap="m",text("WELCOME SIGNAL: NEONSTART","title"),text("Redeem NEONSTART for 600 credits, 10 crystals and 50 XP. Codes ignore case and surrounding spaces."),
 UI.TextInput {value=code,label="Code",placeholder="NEONSTART",clearButton=true},
 button("Redeem",function() send("code",code:peek()) end,true),
 text(function(use) local t=math.max(0,use(state).codeAt-use(clock));return if t>0 then "Rate limited • retry in "..t.."s" else "Ready to redeem • OLDORBIT is an expired signal" end),
 button("Back to market",function() open("Shop") end)}
end) end}
destinations.Inventory={content=function() return pageShell("INVENTORY / LOADOUT",function()
 local children={text("ONE PART PER SLOT","title"),text("Equipping replaces the previous part in that slot. Tap an equipped part to remove it.")}
 for _,slot in {"Motor","Boost","Wheels","Cosmetics"} do table.insert(children,text(function(use) local id=use(state).equipped[slot];return slot..": "..(if id then D.find(D.parts,id).name else "EMPTY SLOT") end,"heading")) end
 for _,item in D.parts do table.insert(children,section({text(item.name.." • "..item.effect,"heading"),
  text(function(use) return if use(state).equipped[item.slot]==item.id then "EQUIPPED" elseif use(state).owned[item.id] then "OWNED • available" else "UNAVAILABLE • purchase in market" end),
  button("Equip / Unequip",function() send("equip",item.id) end)})) end
 table.insert(children,button("Choose driver",function() open("Drivers") end))
 return UI.VStack(children)
end) end}
destinations.Drivers={content=function() return pageShell("DRIVERS / CREW",function()
 local children={text("FIND YOUR CO-PILOT","title"),choice("Group",driverGroup,{"All","Pilots","Synthetics"})}
 for _,driver in D.drivers do
  local card=section({text(driver.name.." / "..driver.group,"heading"),text("Speed +"..driver.speed.."   •   Handling +"..driver.handling),
   text(function(use) local st=use(state);return (if st.driver==driver.id then "EQUIPPED • " else "")..(if st.drivers[driver.id] then "PERMANENTLY OWNED" elseif (st.rentals[driver.id] or 0)>use(clock) then "RENTED • "..(st.rentals[driver.id]-use(clock)).."s remaining" else "UNAVAILABLE") end),
   row({button("Equip",function() send("driver",driver.id) end,true),
   button("Buy • "..driver.price.." CR",function() confirm("Buy "..driver.name.."?",driver.price.." credits • permanent driver ownership for this session.",function() send("driverBuy",driver.id) end) end),
   button("Rent • "..driver.rent.." CR",function() confirm("Rent "..driver.name.."?",driver.rent.." credits • 10 minutes from acceptance. Rental expiry returns you to Rook unless permanently owned.",function() send("driverRent",driver.id) end) end)}),
  })
  C.watch(function(use) card.Visible=use(driverGroup)=="All" or use(driverGroup)==driver.group end)
  table.insert(children,card)
 end
 return UI.VStack(children)
end) end}
local function restoreDraft()
 local l=state:peek().livery;draftBody:set(l.body);draftAccent:set(l.accent);draftShade:set(l.shade);draftDecal:set(l.decal);dirty:set(false)
end
local function liveryDirty()
 local l=state:peek().livery
 return draftBody:peek()~=l.body or draftAccent:peek()~=l.accent or draftShade:peek()~=l.shade or draftDecal:peek()~=l.decal
end
local cleanClose=close
close=function()
 if page:peek()=="Help" and helpStep:peek()>1 then helpStep:set(helpStep:peek()-1);return end
 if page:peek()=="Livery" and liveryDirty() then confirm("Discard unsaved design?","Cancel keeps your draft. Discard restores the saved body, accent, shade and decal.",function() restoreDraft();cleanClose() end)
 else cleanClose() end
end
destinations.Livery={content=function() return pageShell("LIVERY / COLOR LAB",function()
 return UI.VStack {width="fill",gap="m",text("MAKE YOUR SIGNATURE","title"),preview(selected,true),
 text(function(use) local l=use(state).livery;return if use(draftBody)~=l.body or use(draftAccent)~=l.accent or use(draftShade)~=l.shade or use(draftDecal)~=l.decal then "● UNSAVED EDITS" else "✓ SAVED DESIGN" end,"heading"),
 choice("Body color",draftBody,D.colorNames),
(function() local swatches={} for _,name in D.colorNames do table.insert(swatches,UI.Button {label=name,BackgroundColor3=D.colors[name],onActivate=function() draftBody:set(name) end}) end return row(swatches) end)(),
choice("Accent color",draftAccent,D.colorNames),
(function() local swatches={} for _,name in D.colorNames do table.insert(swatches,UI.Button {label=name,BackgroundColor3=D.colors[name],onActivate=function() draftAccent:set(name) end}) end return row(swatches) end)(),
choice("Shade",draftShade,{50,75,100}),choice("Decal",draftDecal,D.decals),
 row({button("Save design",function() send("livery",{body=draftBody:peek(),accent=draftAccent:peek(),shade=draftShade:peek(),decal=draftDecal:peek()}) end,true),
 button("Revert",function() if liveryDirty() then confirm("Discard unsaved design?","Restore the last saved design? Cancel keeps your draft.",restoreDraft) else restoreDraft() end end)})}
end) end}
destinations.Upgrades={content=function() return pageShell("TUNING / UPGRADE BAY",function()
 local children={text(function(use) return "TUNING "..D.find(D.karts,use(selected)).name end,"title"),text("Upgrades are separate for each kart. Select a kart in the garage. Maximum level: 3."),preview(selected,false)}
 for _,stat in {"speed","handling","boost"} do
  table.insert(children,section({text(string.upper(stat),"heading"),
  text(function(use) local u=use(state).upgrades[use(selected)] or {};local n=u[stat] or 0;return "Level "..n.."/3 • "..(if n>=3 then "MAXIMUM" else "Next: +"..(if stat=="speed" then 5 elseif stat=="handling" then 1 else 4).." • "..300*(n+1).." credits + "..5*(n+1).." crystals") end),
  button("Upgrade "..stat,function()
   local id=selected:peek();local u=state:peek().upgrades[id] or {};local n=u[stat] or 0
   confirm("Upgrade "..D.find(D.karts,id).name.." "..stat.."?",if n>=3 then "Maximum level reached. No further upgrade available." else "Spend "..300*(n+1).." credits AND "..5*(n+1).." crystals for level "..(n+1)..".",function() send("upgrade",id,stat) end)
  end,true)}))
 end
 return UI.VStack(children)
end) end}
destinations.Rewards={content=function() return pageShell("MISSION CONTROL",function()
 local children={text("YOUR NEXT BREAKTHROUGH","title"),row({button("Daily track",function() open("Daily") end),button("Crates & collection",function() open("Crates") end),button("Mechanic job",function() open("Mechanic") end)}),
 section({text("FIRST FINISH","heading"),text(function(use) return "Finish a race: "..math.min(1,use(state).races).."/1 • Reward: 350 CR + 5 crystals + 100 XP"..(if use(state).quest then " • CLAIMED" else "") end),button("Claim quest",function() send("quest") end,true)}),
 section({text("STARTER TRANSMISSION","heading"),text(function(use) local st=use(state);return "500 credits • 2 crates + 2 reward boosters\n"..(if st.offer then "CLAIMED" elseif use(clock)>=st.offerEnd then "EXPIRED" else "Eligible • expires in "..(st.offerEnd-use(clock)).."s") end),button("Review offer",function() confirm("Starter transmission","500 credits for 2 crates and 2 one-race reward boosters.",function() send("offer") end) end)}),
 section({text("RACE BOOSTERS","heading"),text(function(use) return use(state).boosts.." owned • "..(if use(state).boostActive then "ACTIVE for next finish" else "+200 credits on your next completed race") end),button("Activate one booster",function() send("boost") end)}),
 text(function(use) local st=use(state);return "Session income: "..st.income.." CR • Hub energy: "..st.jobProgress.."/3" end),
 }
 return UI.VStack(children)
end) end}
destinations.Daily={content=function() return pageShell("DAILY / SEVEN SIGNALS",function()
 local children={text("COME BACK TO THE GRID","title"),text("One claim per UTC day. A missed day restarts the track. Final day: 30 crystals and 2 free crates.")}
 for day=1,7 do table.insert(children,text(function(use)
  local st=use(state);local ready=math.floor(st.lastDaily/86400)<math.floor(use(clock)/86400)
  return "DAY "..day.."  /  "..(150+day*50).." CR + "..(if day==7 then "30 ◈ + 2 crates" else "2 ◈").."  /  "..(if day<=st.daily then "CLAIMED" elseif day==st.daily+1 and ready then "READY" else "LOCKED")
 end,"heading")) end
 table.insert(children,text(function(use) return "Next UTC reset in "..(86400-use(clock)%86400).."s" end))
 table.insert(children,button("Claim ready day",function() send("daily") end,true))
 return UI.VStack(children)
end) end}
destinations.Crates={content=function() return pageShell("CRATES / ARCHIVE",function()
 local children={text("ORBITAL CACHE","title"),text("3 cards per crate • 400 credits\nOdds per card: Common 60% • Rare 30% • Legendary 10%"),
 text(function(use) return "Free crates: "..use(state).freeCrates.." • A free crate is always consumed first." end),
 button("Open crate",function() confirm("Open orbital cache?",if state:peek().freeCrates>0 then "Consume 1 free crate. No credits charged. Receive 3 cards." else "Spend 400 credits. Receive 3 cards.",function() local r=send("crate");if r and r.ok then reveal:set(1) end end) end,true),
 text(function(use) local cards=use(state).reveals;local shown={} for j=1,math.min(use(reveal),#cards) do table.insert(shown,"CARD "..j.." / "..cards[j]) end return if #shown==0 then "Your next discovery awaits." else table.concat(shown,"\n") end,"heading"),
 row({button("Reveal next",function() reveal:set(math.min(3,reveal:peek()+1)) end),button("Reveal all",function() reveal:set(3) end)}),
 text(function(use) local total=0 for _,n in D.cards do if use(state).cards[n] then total+=1 end end return "COLLECTION  /  "..total.." of 6 discovered" end,"heading")}
 for _,name in D.cards do table.insert(children,text(function(use) local count=use(state).cards[name] or 0;return if count>0 then name.."  ×"..count else "??? / Undiscovered" end)) end
 return UI.VStack(children)
end) end}
destinations.Mechanic={content=function() return pageShell("MECHANIC / REN",function()
 return UI.VStack {width="fill",gap="m",text("REN  /  PIT ENGINEER","title"),text("“The reactor's hungry. Bring me the three green energy cells scattered around the paddock and I'll pay you 300 credits and 5 crystals.”"),
 text(function(use) local st=use(state);return "Job: "..st.job.." • Energy cells "..st.jobProgress.."/3" end,"heading"),
 row({button("Ask about the job",function() send("job","ask") end),button("Accept job",function() send("job","accept");close() end,true),button("Decline",function() send("job","decline");close() end),button("Claim reward",function() send("job","claim") end),button("Leave conversation",close)})}
end) end}
destinations.Party={content=function() return pageShell("PARTY / SIGNALS",function()
 local children={text("YOUR RACING CREW","title"),text("These are clearly labeled demo participants for solo play. Sol accepts; Mira declines; Vex is offline."),
 UI.TextInput {value=partySearch,label="Search friends",placeholder="Find a participant",clearButton=true},button("Clear search",function() partySearch:set("") end),
 text(function(use) local names={} for name in use(state).party do table.insert(names,name) end return "PARTY: "..(if #names>0 then table.concat(names,", ") else "Just you") end,"heading")}
 for _,friend in {{"SOL / Demo","Online"},{"MIRA / Demo","Racing"},{"VEX / Demo","Offline"}} do
  local card=section({text(friend[1].." • "..friend[2],"heading"),text(function(use) return use(state).invites[friend[1]] or "Not invited" end),button("Invite",function() send("invite",friend[1]) end)})
  C.watch(function(use) card.Visible=string.find(string.lower(friend[1]),string.lower(use(partySearch)),1,true)~=nil end)
  table.insert(children,card)
 end
 return UI.VStack(children)
end) end}
destinations.Chat={content=function() return pageShell("QUICK CHAT",function()
 local items={} for _,message in D.chat do table.insert(items,{id=message,label=message,onSelect=function() send("chat",message);close() end}) end
 local children={text("ONE SIGNAL. FIVE SECOND COOLDOWN.","title"),text(function(use) return "Ready in "..math.max(0,5-(use(clock)-use(state).chatAt)).."s. Opening or canceling sends nothing." end),
 UI.RadialMenu {label="Open message wheel",items=items}}
 for _,message in D.chat do table.insert(children,button(message,function() send("chat",message);close() end)) end
 return UI.VStack(children)
end) end}
destinations.Settings={content=function() return pageShell("SETTINGS / FLIGHT SYSTEMS",function()
 local music=C.cell(state:peek().settings.music);local effects=C.cell(state:peek().settings.effects)
 local shake=C.cell(state:peek().settings.shake);local damage=C.cell(state:peek().settings.damage)
 local quality=C.cell(state:peek().settings.quality);local reduced=C.cell(state:peek().settings.reduced)
 local function save() send("settings",{music=music:peek(),effects=effects:peek(),shake=shake:peek(),damage=damage:peek(),quality=quality:peek(),reduced=reduced:peek()}) end
 return UI.VStack {width="fill",gap="m",text("TUNE YOUR EXPERIENCE","title"),
 UI.Slider {label="Music volume",value=music,min=0,max=100,step=5,onCommit=save},
 UI.Slider {label="Effects volume",value=effects,min=0,max=100,step=5,onCommit=save},
 UI.Toggle {label="Camera shake",value=shake},UI.Toggle {label="Damage numbers",value=damage},
 UI.Toggle {label="Reduced motion",value=reduced},
 UI.Slider {label="Graphics quality",value=quality,min=1,max=3,step=1},
 button("Save settings",save,true),
 button("Reset to defaults",function() confirm("Reset all settings?","Music 50%, effects 70%, camera shake and damage numbers on, quality 3, reduced motion off. Cancel changes nothing.",function() local r=send("settings",{music=50,effects=70,shake=true,damage=true,quality=3,reduced=false});if r and r.ok then music:set(50);effects:set(70);shake:set(true);damage:set(true);quality:set(3);reduced:set(false) end end) end),
 text("CONTROLS","heading"),text("Keyboard: W accelerate • S brake • A/D steer • Space boost • R recover • Tab grid • Q quick chat.\nController: RT accelerate • LT brake • D-pad steer • RB boost • LB grid • Y chat • X queue • B Back.\nTouch: use the driving controls at the right edge. Menus support touch and controller selection.\nProgress is saved in this server session only.")}
end) end}
destinations.Help={content=function() return pageShell("FLIGHT SCHOOL",function()
 return UI.VStack {width="fill",gap="m",text(function(use) return "STEP "..use(helpStep).." / 3" end,"title"),
 text(function(use) return ({"1 / GARAGE: inspect a kart, favorite it, and choose your next race vehicle.","2 / MARKET: buy a part, then equip it in Inventory. Cancellation never spends credits.","3 / QUEUE: choose Solo or Duo, vote for a track, and complete three laps. W / RT accelerates; Space / RB boosts."})[use(helpStep)] end,"heading"),
 button("Use this action",function() open(({"Garage","Shop","Queue"})[helpStep:peek()]) end,true),
 row({UI.Button {label="Back",enabled=function(use) return use(helpStep)>1 end,onActivate=function() helpStep:set(math.max(1,helpStep:peek()-1)) end},
 button("Next",function() if helpStep:peek()<3 then helpStep:set(helpStep:peek()+1) else send("help");close() end end),
 button("Skip",function() send("help");close() end)})}
end) end}
destinations.More={content=function() return pageShell("PADDOCK / SERVICES",function()
 return UI.VStack {width="fill",gap="m",text("ALL SYSTEMS ONLINE","title"),button("Race queue",function() open("Queue") end,true),button("Garage",function() open("Garage") end),button("Market",function() open("Shop") end),button("Mission control",function() open("Rewards") end),button("Party",function() open("Party") end),button("Settings",function() open("Settings") end),button("Replay help / current step",function() open("Help") end),button("Drivers",function() open("Drivers") end),button("Inventory",function() open("Inventory") end),button("Livery",function() open("Livery") end),button("Upgrades",function() open("Upgrades") end),button("Daily rewards",function() open("Daily") end),button("Crates",function() open("Crates") end)}
end) end}


destinations.Garage={content=function()
 local oldTouch=Gui.TouchControlsEnabled;Gui.TouchControlsEnabled=false;context.Enabled=false
 C.cleanup(function() Gui.TouchControlsEnabled=oldTouch;context.Enabled=true end)
 local column=C.cell("sidebar")
 local selection=C.cell({[selected:peek()]=true})
 local filtered=C.formula(function(use)
  local result={}
  for _,k in D.karts do
   if (use(search)=="" or string.find(string.lower(k.name),string.lower(use(search)),1,true)) and (use(category)=="All" or use(category)==k.category) and (use(rarity)=="All" or tonumber(use(rarity))==k.rarity) then table.insert(result,k) end
  end
  table.sort(result,function(a,b)
   if use(sort)=="Speed" and a.speed~=b.speed then return a.speed>b.speed elseif use(sort)=="Rarity" and a.rarity~=b.rarity then return a.rarity>b.rarity end return a.name<b.name
  end)
  return result
 end)
 return UI.VStack {surface="surface",width="fill",height="fill",
  UI.Screen {
   UI.NavBar {title="GARAGE / FLEET",trailing=button("Close / B",close)},
   row({button("Inventory",function() open("Inventory") end),button("Drivers",function() open("Drivers") end),button("Livery",function() open("Livery") end),button("Upgrades",function() open("Upgrades") end)}),
   UI.VStack {width="fill",height="fill",UI.fill(),
    UI.NavigationSplitView {preferredCompactColumn=column,minSidebarWidth=300,minDetailWidth=420,compactWidth=780,resizable=false,backLabel="Fleet",detailLabel="Inspect",
     sidebar=function()
      return UI.ScrollView {width="fill",height="fill",padding="m",gap="s",
       UI.TextInput {value=search,label="Search fleet",placeholder="Kart name",clearButton=true},
       button("Clear search",function() search:set("") end),
       row({
(function() local v=choice("Category",category,{"All","Balanced","Speed","Agile"});v.Size=UDim2.new(.34,-6,0,0);return v end)(),
(function() local v=choice("Rarity",rarity,{"All","1","2","3","4"});v.Size=UDim2.new(.30,-6,0,0);return v end)(),
(function() local v=choice("Sort",sort,{"Name","Speed","Rarity"});v.Size=UDim2.new(.34,-6,0,0);return v end)(),
})
,
       text(function(use) return if #use(filtered)==0 then "No matching karts. Clear search or adjust filters." else #use(filtered).." karts • choose a chassis" end,"caption"),
       UI.VirtualList {from=filtered,key="id",selection=selection,selectionFrom=D.karts,itemSize=92,measure=true,Size=UDim2.new(1,0,0,300),
        onSelectionChange=function(map) selection:set(map);for id in map do selected:set(id) end end,
        onActivate=function(item) selected:set(item.id);column:set("detail") end,
        render=function(current)
         return UI.VStack {width="fill",padding="m",gap="xs",
          text(function(use) local k=use(current);return k.name..(if use(state).favorites[k.id] then " ★" else "") end,"heading"),
          text(function(use) local k=use(current);return k.category.." • R"..k.rarity.." • "..k.speed.." km/h" end,"caption")}
        end},
       button("Inspect selection",function() column:set("detail") end,true),
      }
     end,
     detail=function()
      local art=preview(selected,false);art.Size=UDim2.fromScale(1,1)
      return UI.ScrollView {width="fill",height="fill",padding="m",gap="m",
       text(function(use) return D.find(D.karts,use(selected)).name end,"title"),
       text(function(use) return if use(state).kart==use(selected) then "EQUIPPED FOR NEXT RACE" else "SELECTED • AVAILABLE TO DRIVE" end,"caption"),
       UI.ZStack {Size=UDim2.new(1,0,0,320),art},
       text(function(use) local k=D.find(D.karts,use(selected));local u=use(state).upgrades[k.id] or {speed=0,handling=0,boost=0};return string.format("SPEED %d  /  HANDLING %d  /  BOOST +%d",k.speed+u.speed*5,k.handling+u.handling,k.boost+u.boost*4) end,"heading"),
       row({button("Choose for next race",function() send("kart",selected:peek()) end,true),button("Try kart",function() local r=send("preview",selected:peek());if r and r.ok then close() end end),button("Favorite ★",function() send("favorite",selected:peek()) end)}),
      }
     end,
    }},
   text(notice,"caption"),
  }}
end}

destinations.RaceTools={content=function() return pageShell("RACE TOOLS",function()
 return UI.VStack {width="fill",gap="m",button("Live grid",function() close();scoreOpen:set(true) end),button("Quick chat",function() close();chatOpen:set(true) end),button("Recover kart",function() send("recover");close() end),button("Exit drive to hub",function() send("return");close() end)}
end) end}
app.mount(function()
 return UI.ZStack {width="fill",height="fill",
  UI.NavigationStack {path=path,chrome="hidden",root={content=hud},destinations=destinations},
  UI.RadialMenu {launcher=false,isPresented=chatOpen,preset="donut",ringWidth=180,contentFit="none",label="Quick chat",items=(function()
   local items={} for _,message in D.chat do table.insert(items,{id=message,label=message,onSelect=function() send("chat",message);chatOpen:set(false) end}) end return items
  end)()},
  UI.Dialog {isPresented=confirmOpen,onPresentedChange=function(v) confirmOpen:set(v) end,title=confirmTitle,
   content=function() return text(confirmText) end,
   actions={{id="cancel",label="Cancel",role="cancel",onActivate=function() end},{id="confirm",label=confirmLabel,onActivate=function() confirmAction() end}}},
 }
end)
A.Update.OnClientEvent:Connect(function(kind,value)
 if kind=="state" then
  local old=state:peek();state:set(value);notice:set(value.message)
  if value.phase=="Racing" and old.phase~="Racing" then close() end
  if value.phase=="Results" and old.phase~="Results" then open("Results") end
 elseif kind=="race" then race:set(value)
 elseif kind=="chat" then notice:set(value) end
end)
bind("Accelerate",{Enum.KeyCode.W,Enum.KeyCode.Up,Enum.KeyCode.ButtonR2},function() held.forward=true end,function() held.forward=false end)
bind("Brake",{Enum.KeyCode.S,Enum.KeyCode.Down,Enum.KeyCode.ButtonL2},function() held.brake=true end,function() held.brake=false end)
bind("Left",{Enum.KeyCode.A,Enum.KeyCode.Left,Enum.KeyCode.DPadLeft},function() held.left=true end,function() held.left=false end)
bind("Right",{Enum.KeyCode.D,Enum.KeyCode.Right,Enum.KeyCode.DPadRight},function() held.right=true end,function() held.right=false end)
bind("Boost",{Enum.KeyCode.Space,Enum.KeyCode.ButtonR1},function() held.boost=true end,function() held.boost=false end)
bind("Queue",{Enum.KeyCode.ButtonX},function() open("Queue") end)
bind("Chat",{Enum.KeyCode.Q,Enum.KeyCode.ButtonY},function() chatOpen:set(true) end)
bind("Grid",{Enum.KeyCode.Tab,Enum.KeyCode.ButtonL1},function() scoreOpen:set(not scoreOpen:peek()) end)
bind("Recover",{Enum.KeyCode.R},function() send("recover") end)
local menuContext=Instance.new("InputContext");menuContext.Name="AstraMenus";menuContext.Priority=1000000;menuContext.Sink=true;menuContext.Parent=player.PlayerGui
local back=Instance.new("InputAction");back.Name="Back";back.Type=Enum.InputActionType.Bool;back.Parent=menuContext
local backBinding=Instance.new("InputBinding");backBinding.KeyCode=Enum.KeyCode.ButtonB;backBinding.Parent=back
back.Pressed:Connect(function()
 if confirmOpen:peek() then confirmOpen:set(false)
 elseif chatOpen:peek() then chatOpen:set(false)
 elseif scoreOpen:peek() then scoreOpen:set(false)
 elseif page:peek()=="Help" and helpStep:peek()>1 then helpStep:set(helpStep:peek()-1)
 elseif #path:peek()>0 then close()
 elseif training:peek() then if trainingStep:peek()>1 then trainingStep:set(trainingStep:peek()-1) else training:set(false);send("help") end end
end)
local analog=Instance.new("InputAction");analog.Name="AnalogSteering";analog.Type=Enum.InputActionType.Direction2D;analog.Parent=context
local analogBinding=Instance.new("InputBinding");analogBinding.KeyCode=Enum.KeyCode.Thumbstick1;analogBinding.Parent=analog
local effects=Instance.new("SoundGroup");effects.Name="AstraEffects";effects.Volume=initial.settings.effects/100;effects.Parent=game:GetService("SoundService")
local music=Instance.new("SoundGroup");music.Name="AstraMusic";music.Volume=initial.settings.music/100;music.Parent=game:GetService("SoundService")
local engine=Instance.new("Sound");engine.Name="Engine";engine.SoundId="rbxasset://sounds/rocket whoosh 01.wav";engine.Looped=true;engine.Volume=.12;engine.SoundGroup=effects;engine.Parent=game:GetService("SoundService")
local melody=Instance.new("Sound");melody.Name="Paddock melody";melody.SoundId="rbxasset://sounds/electronicpingshort.wav";melody.Volume=.12;melody.SoundGroup=music;melody.Parent=game:GetService("SoundService")
local notes={.75,1,1.125,1.5,1.125,1,.84,1}
local musicClock=0;local note=1
local lastSettings=initial.settings

local accumulator=0
Run.RenderStepped:Connect(function(dt)
 accumulator+=dt
 musicClock+=dt
 if musicClock>.65 then musicClock=0;melody.PlaybackSpeed=notes[note];note=note%#notes+1;if state:peek().settings.music>0 then melody:Play() end end

 if accumulator>.08 then
  accumulator=0;clock:set(os.time())
  if state:peek().phase=="Racing" or state:peek().phase=="Preview" then
   A.Drive:FireServer(if held.forward then 1 elseif held.brake then -1 else 0,math.clamp((if held.right then 1 else 0)-(if held.left then 1 else 0)+analog:GetState().X,-1,1),held.boost)
  end
 end
 if page:peek()=="Mechanic" and dialogueOrigin then local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart");if root and (root.Position-dialogueOrigin).Magnitude>28 then close();notice:set("Conversation ended: you walked away.") end end
 local settings=state:peek().settings
 effects.Volume=settings.effects/100;music.Volume=settings.music/100
 local bloom=game.Lighting:FindFirstChildOfClass("BloomEffect");if bloom then bloom.Enabled=settings.quality>1 end
 local camera=workspace.CurrentCamera
 local kart=workspace:FindFirstChild("Kart_"..player.UserId)
 if kart and kart:IsA("Model") and kart.PrimaryPart then
  camera.CameraType=Enum.CameraType.Scriptable
  local cf=kart:GetPivot()
  local target=CFrame.lookAt(cf.Position-cf.LookVector*22+Vector3.new(0,12,0),cf.Position+cf.LookVector*18)
  camera.CFrame=camera.CFrame:Lerp(target,1-math.exp(-dt*8))
  camera.FieldOfView=74+(if settings.reduced then 0 else race:peek().speed/30)
  if settings.shake and not settings.reduced and held.boost and race:peek().energy>0 then camera.CFrame*=CFrame.Angles(math.sin(os.clock()*31)*.0015,0,0) end
  if not engine.IsPlaying then engine:Play() end;engine.PlaybackSpeed=.7+race:peek().speed/120
 else
  engine:Stop()
  camera.CameraType=Enum.CameraType.Custom
  local hum=player.Character and player.Character:FindFirstChildOfClass("Humanoid");if hum then camera.CameraSubject=hum end
 end
end)
for _,obj in workspace.AstraWorld:GetDescendants() do if obj:IsA("ProximityPrompt") then
 obj.Triggered:Connect(function(p)
  if p~=player then return end
  local name=obj.Parent.Name
  if name=="GARAGE" then open("Garage") elseif name=="MARKET" then open("Shop") elseif name=="RACE" then open("Queue") elseif name=="MECHANIC" then open("Mechanic") end
 end)
end end
script.Destroying:Connect(app.dispose)
