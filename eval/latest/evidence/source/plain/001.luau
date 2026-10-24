--!strict
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local CAS=game:GetService("ContextActionService")
local Run=game:GetService("RunService")
local GS=game:GetService("GuiService")
local p=Players.LocalPlayer
local A=RS:WaitForChild("Apex")
local D=require(A:WaitForChild("Data"))
local Req=A:WaitForChild("Request") :: RemoteEvent
local Push=A:WaitForChild("Push") :: RemoteEvent
local Drive=A:WaitForChild("Drive") :: RemoteEvent
local pg=p:WaitForChild("PlayerGui")
local gui=Instance.new("ScreenGui");gui.Name="NeonApex";gui.ResetOnSpawn=false;gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.Parent=pg
local screen=gui
local canvas=Instance.new("Frame");canvas.Name="Canvas";canvas.BackgroundTransparency=1;canvas.Size=UDim2.fromScale(1,1);canvas.Parent=screen
local uiScale=Instance.new("UIScale");uiScale.Parent=canvas
local soundService=game:GetService("SoundService")
local music=Instance.new("Sound");music.Name="AfterDarkRadio";music.SoundId="rbxassetid://1841647093";music.Looped=true;music.Volume=0.15;music.Parent=soundService;music:Play()
local clickSound=Instance.new("Sound");clickSound.SoundId="rbxasset://sounds/electronicpingshort.wav";clickSound.Volume=0.2;clickSound.Parent=soundService
local motorSound=Instance.new("Sound");motorSound.SoundId="rbxasset://sounds/action_swim.mp3";motorSound.Looped=true;motorSound.Volume=0;motorSound.Parent=soundService;motorSound:Play()
local C={bg=Color3.fromRGB(10,16,29),panel=Color3.fromRGB(18,27,44),tile=Color3.fromRGB(27,39,58),line=Color3.fromRGB(49,67,88),text=Color3.fromRGB(235,245,250),muted=Color3.fromRGB(150,173,195),cyan=Color3.fromRGB(71,234,227),purple=Color3.fromRGB(175,132,255),gold=Color3.fromRGB(255,199,91)}
local state:any=nil
local race:any=nil
local current=""
local shopCategory="All"
local search=""
local category="All"
local rarity="All"
local sort="Name A–Z"
local selected="pulse"
local driverGroup="All"
local partySearch=""
local draft:any=nil
local dirty=false
local roam=false
local helpStep=0
local dialogueOrigin:Vector3?=nil
local lastPageFocus:string=""
local revealCount=0
local confirmCallback:(()->())?=nil
local opener:GuiObject?=nil
local pageOpener:GuiObject?=nil
local build:(string)->()
local close:()->()
local function create(class:string,props:any,parent:Instance):any
 local o=Instance.new(class)
 for k,v in props do (o :: any)[k]=v end
 o.Parent=parent;return o
end
local function round(o:Instance,n:number?) create("UICorner",{CornerRadius=UDim.new(0,n or 12)},o) end
local function stroke(o:Instance,col:Color3?) create("UIStroke",{Color=col or C.line,Thickness=1,Transparency=0.15},o) end
local function label(parent:Instance,text:string,size:number,color:Color3?,height:number?):TextLabel
 return create("TextLabel",{BackgroundTransparency=1,Size=UDim2.new(1,0,0,height or 28),Text=text,TextSize=size,Font=Enum.Font.GothamMedium,TextColor3=color or C.text,TextXAlignment=Enum.TextXAlignment.Left,TextWrapped=true},parent)
end
local function button(parent:Instance,text:string,callback:()->(),accent:boolean?,width:number?):TextButton
 local b=create("TextButton",{Size=UDim2.new(if width then 0 else 1, width or 0,0,44),BackgroundColor3=if accent then C.cyan else C.tile,TextColor3=if accent then C.bg else C.text,Text=text,TextSize=14,Font=Enum.Font.GothamBold,AutoButtonColor=true,Selectable=true},parent)
 round(b,9);if not accent then stroke(b) end
 b.Activated:Connect(function() clickSound:Play();callback() end);return b
end
local function list(parent:Instance,gap:number?):UIListLayout
 return create("UIListLayout",{Padding=UDim.new(0,gap or 10),SortOrder=Enum.SortOrder.LayoutOrder},parent)
end
local function row(parent:Instance,height:number?):Frame
 local f=create("Frame",{Size=UDim2.new(1,0,0,height or 44),BackgroundTransparency=1},parent)
 create("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder},f);return f
end
local function card(parent:Instance,title:string,sub:string,height:number?):Frame
 local f=create("Frame",{Size=UDim2.new(1,-4,0,height or 126),BackgroundColor3=C.tile},parent);round(f);stroke(f)
 create("UIPadding",{PaddingLeft=UDim.new(0,16),PaddingRight=UDim.new(0,16),PaddingTop=UDim.new(0,12),PaddingBottom=UDim.new(0,12)},f)
 list(f,5);label(f,title,17,C.text,25);label(f,sub,13,C.muted,36);return f
end
local header=create("Frame",{Size=UDim2.new(1,-32,0,66),Position=UDim2.fromOffset(16,8),BackgroundColor3=C.bg,BackgroundTransparency=0.08},canvas);round(header);stroke(header)
local brand=label(header,"N / A   •   NEON APEX",19,C.cyan,28);brand.Position=UDim2.fromOffset(18,9);brand.Size=UDim2.new(0.38,-18,0,28)
local wallet=label(header,"CONNECTING",17,C.text,28);wallet.Position=UDim2.new(0.38,0,0,7);wallet.Size=UDim2.new(0.62,-18,0,28);wallet.TextXAlignment=Enum.TextXAlignment.Right
local meta=label(header,"SESSION PROFILE  /  no cross-session storage",11,C.muted,20);meta.Position=UDim2.fromOffset(18,38);meta.Size=UDim2.new(1,-36,0,20)
local toast=label(canvas,"",15,C.cyan,48);toast.Name="Feedback";toast.Position=UDim2.new(0.5,0,1,-126);toast.AnchorPoint=Vector2.new(0.5,0);toast.Size=UDim2.new(0.8,0,0,48);toast.BackgroundColor3=C.bg;toast.BackgroundTransparency=0.08;toast.TextXAlignment=Enum.TextXAlignment.Center;toast.Visible=false;toast.ZIndex=20;round(toast)
local toastId=0
local function notify(t:string)
 if t=="" then return end
 toastId+=1;local id=toastId;toast.Text=t;toast.Visible=true
 task.delay(5,function() if toastId==id then toast.Visible=false end end)
end
local function request(action:string,arg:any?)
 if state then state.save="Saving…" end
 Req:FireServer(action,arg or {})
 task.delay(5,function() if state and state.save=="Saving…" then state.save="No confirmation received. Try again.";notify(state.save) end end)
end
local hub=create("Frame",{BackgroundTransparency=1,Position=UDim2.fromOffset(30,104),Size=UDim2.new(1,-60,1,-210)},canvas)
local hero=label(hub,"THE CITY\nIS YOUR CIRCUIT.",38,C.text,108);hero.Font=Enum.Font.GothamBlack;hero.Size=UDim2.new(0.55,0,0,108)
local kicker=label(hub,"SEASON 01   /   AFTER DARK",12,C.cyan,25);kicker.Position=UDim2.fromOffset(0,115)
local desc=label(hub,"Build your machine. Find your line.\nChase the next podium.",16,C.muted,58);desc.Position=UDim2.fromOffset(0,148);desc.Size=UDim2.new(0.47,0,0,58)
local play=button(hub,"ENTER THE GRID   →",function() build("Race") end,true,240);play.Position=UDim2.fromOffset(0,226)
local explore=button(hub,"EXPLORE PADDOCK",function() roam=not roam end,false,240);explore.Position=UDim2.fromOffset(0,334)
local dailyButton=button(hub,"DAILY SIGNAL  •  READY",function() build("Daily") end,false,240);dailyButton.Position=UDim2.fromOffset(0,280)
local featured=label(hub,"PULSE GT\nBALANCED  /  FACTORY SERIES",17,C.cyan,60);featured.Position=UDim2.new(0.63,0,0.68,0);featured.Size=UDim2.new(0.37,0,0,60)
local nav=create("ScrollingFrame",{Size=UDim2.new(1,-32,0,65),Position=UDim2.new(0,16,1,-73),BackgroundColor3=C.bg,BackgroundTransparency=0.06,BorderSizePixel=0,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.X,ScrollingDirection=Enum.ScrollingDirection.X,ScrollBarThickness=3},canvas);round(nav)
create("UIPadding",{PaddingLeft=UDim.new(0,10),PaddingTop=UDim.new(0,9),PaddingRight=UDim.new(0,10)},nav)
create("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,8)},nav)
local navButtons:any={}
for _,name in {"Garage","Shop","Inventory","Drivers","Livery","Upgrades","Crates","Daily","Quests","Party","Mechanic","Settings","Help"} do
 navButtons[name]=button(nav,name,function() build(name) end,false,100)
end
local shade=create("Frame",{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=0.35,Visible=false,ZIndex=3},canvas)
local panel=create("Frame",{AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.new(0.5,0,0.5,12),Size=UDim2.new(0.88,0,0.76,0),BackgroundColor3=C.panel,Visible=false,ZIndex=4},canvas);round(panel,16);stroke(panel)
create("UISizeConstraint",{MaxSize=Vector2.new(1000,690),MinSize=Vector2.new(280,220)},panel)
local title=label(panel,"GARAGE",26,C.text,36);title.Position=UDim2.fromOffset(22,17);title.Size=UDim2.new(1,-100,0,36)
local subtitle=label(panel,"",12,C.muted,24);subtitle.Position=UDim2.fromOffset(22,55);subtitle.Size=UDim2.new(1,-44,0,24)
local closeButton=button(panel,"×",function() close() end,false,44);closeButton.Position=UDim2.new(1,-62,0,16)
local content=create("ScrollingFrame",{Size=UDim2.new(1,-36,1,-100),Position=UDim2.fromOffset(18,88),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,ScrollBarImageColor3=C.cyan,AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new()},panel)
create("UIPadding",{PaddingRight=UDim.new(0,8),PaddingBottom=UDim.new(0,16)},content);list(content,10)
local modalShade=create("Frame",{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=0.2,Visible=false,ZIndex=30},canvas)
local modal=create("Frame",{AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.new(0.88,0,0,260),BackgroundColor3=C.panel,ZIndex=31},modalShade);round(modal,16);stroke(modal,C.cyan);create("UISizeConstraint",{MaxSize=Vector2.new(480,300)},modal)
local modalTitle=label(modal,"CONFIRM",22,C.text,42);modalTitle.Position=UDim2.fromOffset(24,18);modalTitle.Size=UDim2.new(1,-48,0,42)
local modalText=label(modal,"",16,C.muted,100);modalText.Position=UDim2.fromOffset(24,65);modalText.Size=UDim2.new(1,-48,0,100)
local function dismissConfirm() modalShade.Visible=false;confirmCallback=nil;if opener and opener.Parent then GS.SelectedObject=opener end end
local cancel=button(modal,"Cancel",dismissConfirm,false,160);cancel.Position=UDim2.new(0,24,1,-68);cancel.Size=UDim2.new(0.45,-24,0,44)
local accept=button(modal,"Confirm",function() local f=confirmCallback;dismissConfirm();if f then f() end end,true,160);accept.Position=UDim2.new(0.5,0,1,-68);accept.Size=UDim2.new(0.5,-24,0,44)
local function confirm(t:string,body:string,f:()->(),word:string?)
 opener=GS.SelectedObject;modalTitle.Text=t;modalText.Text=body;accept.Text=word or "Confirm";confirmCallback=f;modalShade.Visible=true;GS.SelectedObject=cancel
end
local function buy(t:string,body:string,action:string,arg:any) confirm(t,body,function() request(action,arg) end) end
local function clearContent()
 for _,x in content:GetChildren() do if x:IsA("GuiObject") then x:Destroy() end end
 content.CanvasPosition=Vector2.zero
end
local function cycle(parent:Instance,caption:string,options:{string},value:string,set:(string)->(),w:number?):TextButton
 return button(parent,caption..": "..value,function()
  local i=table.find(options,value) or 1;set(options[i%#options+1])
 end,false,w)
end
local function field(parent:Instance,placeholder:string,value:string,onChange:(string)->()):TextBox
 local box=create("TextBox",{Size=UDim2.new(1,0,0,44),BackgroundColor3=C.bg,TextColor3=C.text,PlaceholderColor3=C.muted,PlaceholderText=placeholder,Text=value,ClearTextOnFocus=false,TextSize=16,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left},parent);round(box);create("UIPadding",{PaddingLeft=UDim.new(0,12)},box)
 box.FocusLost:Connect(function() onChange(box.Text) end);return box
end
local function smallButtons(parent:Instance,items:any)
 local r=row(parent)
 for _,v in items do local b=button(r,v[1],v[2],v[3]);b.Size=UDim2.new(1/#items,-8,0,44) end
end
local function liveryPreview(parent:Instance)
 local vp=create("ViewportFrame",{Size=UDim2.new(1,0,0,200),BackgroundColor3=C.bg,Ambient=Color3.fromRGB(180,180,210),LightColor=Color3.new(1,1,1)},parent);round(vp)
 local cam=Instance.new("Camera");cam.FieldOfView=28;cam.CFrame=CFrame.lookAt(Vector3.new(10,7,12),Vector3.zero);cam.Parent=vp;vp.CurrentCamera=cam
 local source=workspace:FindFirstChild("Showroom")
 if source and source:IsA("Model") then
  local m=source:Clone();m:ScaleTo(1);m:PivotTo(CFrame.new());m.Parent=vp;D.decorate(m,draft)
  for _,v in m:GetDescendants() do if v:IsA("BasePart") then
   if v.Name=="Body" or v.Name=="Nose" then v.Color=D.Colors[draft.body]:Lerp(Color3.new(0,0,0),1-draft.shade/100)
   elseif v.Name=="Wing" or v.Name=="Rim" or v.Name=="Decal" then v.Color=D.Colors[draft.accent] end
   if v.Name=="Decal" then v.Transparency=if draft.decal=="None" then 1 else 0 end
  end end
 end
end
local function go(name:string)
 current=name;build(name)
end
build=function(name:string)
 if not state then return end
 local priorFocus=GS.SelectedObject
 local priorText=if priorFocus and priorFocus:IsA("TextButton") then priorFocus.Text else ""
 if current=="Livery" and dirty and name~="Livery" then
  confirm("UNSAVED DESIGN","Discard your unsaved livery changes?",function() dirty=false;draft=table.clone(state.livery);go(name) end,"Discard");return
 end
 if name=="Help" then helpStep=1;request("Tutorial",{step=1});current="";panel.Visible=false;shade.Visible=false;return end
 if name=="Mechanic" and current~="Mechanic" then local ch=p.Character;dialogueOrigin=if ch then ch:GetPivot().Position else nil end
 if current=="" then pageOpener=GS.SelectedObject end
 current=name;panel.Visible=true;shade.Visible=true;title.Text=string.upper(name);subtitle.Text="PADDOCK / "..string.upper(name).."    •    "..state.save;clearContent()
 if name=="Race" then
  if state.phase=="Queue" then
   subtitle.Text="VOTING OPEN • 1 human + 3 CPU • "..(if state.queueMode=="Duo" then "2 required; CPU teammate ready" else "1 required")
   button(content,"Leave queue",function() request("LeaveQueue") end)
   label(content,state.queueMode.." QUEUE  •  4 / 4 racers  •  starts in "..math.max(0,state.queueEnd-os.time()).."s",20,C.cyan,52)
   for _,t in D.Tracks do
    local c=card(content,t.name..(if state.vote==t.id then "   ✓ YOUR VOTE" else ""),t.desc.."   /   "..tostring(state.votes[t.id]).." votes",128)
    button(c,"Vote for track",function() request("Vote",{id=t.id}) end,false)
   end
  else
   label(content,"FIND YOUR NEXT PODIUM",25,C.cyan,40)
   label(content,"Local CPU rivals fill your grid. Vote for the next circuit ruleset, then race for credits, prisms and XP.",16,C.muted,64)
   for _,mode in {"Solo","Duo"} do
    local c=card(content,mode.." GRID",if mode=="Solo" then "1 driver required • three local CPU opponents" else "2 drivers required • demo teammate + two CPU rivals",132)
    button(c,"Join "..mode.." queue",function() request("Queue",{mode=mode}) end,true)
   end
   label(content,"W / ↑ accelerate    S / ↓ brake    A D steer    Shift boost\nGuided circuit steering • steer to choose your racing line.",14,C.muted,58)
  end
 elseif name=="Garage" then
  subtitle.Text="ALL CHASSIS AVAILABLE • select a kart for the next grid"
  field(content,"Search karts…",search,function(v) search=v;build("Garage") end)
  smallButtons(content,{{"Clear search",function() search="";build("Garage") end},{category,function() local opts={"All","Balanced","Speed","Handling"};category=opts[(table.find(opts,category) or 1)%#opts+1];build("Garage") end},{rarity,function() local opts={"All","Common","Rare","Epic","Legendary"};rarity=opts[(table.find(opts,rarity) or 1)%#opts+1];build("Garage") end}})
  cycle(content,"Sort",{"Name A–Z","Speed ↓","Rarity ↓"},sort,function(v) sort=v;build("Garage") end)
  local found={}
  for _,k in D.Karts do if (category=="All" or category==k.category) and (rarity=="All" or rarity==k.rarity) and string.find(string.lower(k.name),string.lower(search),1,true) then table.insert(found,k) end end
  table.sort(found,function(a,b)
   if sort=="Speed ↓" and a.speed~=b.speed then return a.speed>b.speed end
   if sort=="Rarity ↓" and a.rank~=b.rank then return a.rank>b.rank end
   return a.name<b.name
  end)
  if #found==0 then label(content,"No karts match. Clear search or change filters.",18,C.gold,60) end
  for _,k in found do
   local c=card(content,(if state.favorites[k.id] then "★ " else "")..k.name..(if selected==k.id then "   • INSPECTED" else "")..(if state.kart==k.id then "   ✓ NEXT RACE" else ""),k.rarity.." / "..k.category.."    SPD "..k.speed.."   HND "..k.handling.."   BST "..k.boost,174)
   label(c,k.desc,13,C.muted,28)
   smallButtons(c,{{"Inspect",function() selected=k.id;build("Garage") end},{"Choose",function() selected=k.id;request("Kart",{id=k.id}) end,true},{"Try",function() request("Preview",{id=k.id});close() end},{"★",function() request("Favorite",{id=k.id}) end}})
  end
 elseif name=="Shop" then
  smallButtons(content,{{"Codes",function() go("Codes") end},{"Crates",function() go("Crates") end},{"Boosts & offers",function() go("Quests") end}})
  cycle(content,"Category",{"All","Motors","Boosts","Wheels","Cosmetics"},shopCategory,function(v) shopCategory=v;build("Shop") end)
  for _,item in D.Parts do if shopCategory=="All" or shopCategory==item.slot then
   local own=state.owned[item.id]
   local c=card(content,item.name.."   /   "..item.slot,item.effect.."  •  "..item.price.." credits  •  "..(if own then "OWNED" elseif state.coins>=item.price then "AFFORDABLE" else "NEEDS MORE CREDITS"),132)
   button(c,if own then "Owned • manage in Inventory" else "Purchase • "..item.price.." credits",function()
    if own then go("Inventory") else buy("PURCHASE PART",item.name.."\nFull price: "..item.price.." credits","Buy",{id=item.id}) end
   end,not own)
  end end
 elseif name=="Inventory" then
  for _,slot in {"Motors","Boosts","Wheels","Cosmetics"} do
   local id=state.equipped[slot];local item=if id then D.find(D.Parts,id) else nil
   label(content,string.upper(slot).." SLOT  /  "..(if item then item.name else "EMPTY"),15,C.cyan,30)
  end
  for _,item in D.Parts do
   local owned=state.owned[item.id];local equipped=state.equipped[item.slot]==item.id
   local c=card(content,item.name.."  •  "..(if equipped then "EQUIPPED" elseif owned then "OWNED" else "UNAVAILABLE"),item.effect.." / replaces the current "..item.slot.." slot",130)
   button(c,if equipped then "Unequip" elseif owned then "Equip" else "View in shop",function() if owned then request("Equip",{id=item.id}) else go("Shop") end end,owned)
  end
  button(content,"Choose a driver →",function() go("Drivers") end)
 elseif name=="Drivers" then
  cycle(content,"Group",{"All","Pioneers","Elites"},driverGroup,function(v) driverGroup=v;build("Drivers") end)
  for _,d in D.Drivers do if driverGroup=="All" or driverGroup==d.group then
   local rented=(state.rentals[d.id] or 0)>os.time();local owned=state.drivers[d.id]
   local status=if state.driver==d.id then "EQUIPPED" elseif owned then "OWNED" elseif rented then "RENTED" else "UNAVAILABLE"
   local c=card(content,d.name.."  /  "..status,d.group.." • "..d.desc..(if rented then " / "..math.ceil((state.rentals[d.id]-os.time())/60).." min rental left" else ""),174)
   if owned or rented then button(c,"Equip "..d.name,function() request("DriverEquip",{id=d.id}) end,true)
   else smallButtons(c,{{"Buy • "..d.price,function() buy("BUY DRIVER",d.name.." • permanent ownership\n"..d.price.." credits","DriverBuy",{id=d.id}) end},{"Rent • "..d.rent,function() buy("RENT DRIVER",d.name.." • ten minutes\nFull price: "..d.rent.." credits","DriverRent",{id=d.id}) end}}) end
   label(c,"Speed +"..d.speed.."   /   Handling +"..d.handling,13,C.cyan,24)
  end end
 elseif name=="Livery" then
  if not draft then draft=table.clone(state.livery) end
  subtitle.Text=if dirty then "UNSAVED EDITS • save to use this design next race" else "SAVED DESIGN • body, accent, shade and decal"
  liveryPreview(content)
  for _,slot in {"body","accent"} do
   label(content,string.upper(slot).." COLOR",14,C.muted,24)
   local r=row(content,96)
   local layout=r:FindFirstChildOfClass("UIListLayout");if layout then layout:Destroy() end
   create("UIGridLayout",{CellSize=UDim2.new(1/3,-6,0,44),CellPadding=UDim2.fromOffset(6,6)},r)
   for _,col in {"Red","Amber","Green","Cyan","Blue","Violet"} do
    local b=button(r,(if draft[slot]==col then "✓ " else "")..col,function() draft[slot]=col;dirty=true;build("Livery") end,false)
    b.Size=UDim2.new(1/6,-7,0,44);b.BackgroundColor3=D.Colors[col];b.TextColor3=C.bg;b.TextSize=12
   end
  end
  cycle(content,"Shade",{"50%","75%","100%"},tostring(draft.shade).."%",function(v) draft.shade=tonumber(v:sub(1,-2));dirty=true;build("Livery") end)
  cycle(content,"Decal",D.Decals,draft.decal,function(v) draft.decal=v;dirty=true;build("Livery") end)
  smallButtons(content,{{"Save design",function() request("Livery",draft);dirty=false end,true},{"Revert",function() if dirty then confirm("REVERT DESIGN","Discard unsaved changes and restore the saved design?",function() draft=table.clone(state.livery);dirty=false;build("Livery") end,"Discard") end end}})
 elseif name=="Upgrades" then
  local k=D.find(D.Karts,selected)
  cycle(content,"Kart",(function() local t={};for _,v in D.Karts do table.insert(t,v.name) end;return t end)(),k.name,function(v) for _,x in D.Karts do if x.name==v then selected=x.id end end;build("Upgrades") end)
  local u=state.upgrades[selected] or {speed=0,handling=0,boost=0}
  for _,stat in {"speed","handling","boost"} do
   local level=u[stat];local cost=400*(level+1);local gems=10*(level+1)
   local c=card(content,string.upper(stat).."  /  LEVEL "..level.." OF 3",if level>=3 then "MAXIMUM • fully tuned" else "Next: +"..(if stat=="handling" then 6 else 5).." "..stat.." • "..cost.." credits + "..gems.." prisms",130)
   button(c,if level>=3 then "Maximum level" else "Upgrade "..k.name,function() if level<3 then buy("CONFIRM UPGRADE",k.name.." / "..stat.." level "..(level+1).."\n"..cost.." credits + "..gems.." prisms","Upgrade",{id=selected,stat=stat}) end end,level<3)
  end
 elseif name=="Crates" then
  local c=card(content,"AFTER DARK CACHE","3 cards • 350 credits • free tokens: "..state.freeCrates,146)
  label(c,"Common 60%  /  Rare 25%  /  Epic 12%  /  Legendary 3%",12,C.cyan,30)
  button(c,if state.freeCrates>0 then "Open • free token first" else "Open • 350 credits",function() revealCount=0;buy("OPEN CACHE","Receive three cards.\n"..(if state.freeCrates>0 then "1 free token will be consumed. No credits charged." else "Full price: 350 credits"),"Crate",{}) end,true)
  if state.reveal then
   smallButtons(content,{{"Reveal next",function() revealCount=math.min(3,revealCount+1);build("Crates") end,true},{"Reveal all",function() revealCount=3;build("Crates") end}})
   for i,idx in state.reveal do label(content,if i<=revealCount then i.."  /  "..D.Cards[idx].name.." • "..D.Cards[idx].rarity else i.."  /  UNKNOWN CARD",18,if i<=revealCount then C.purple else C.muted,44) end
  end
  local count=0;for _,n in state.cards do if n>0 then count+=1 end end
  label(content,"COLLECTION  /  "..count.." OF 6",18,C.cyan,36)
  for i,c2 in D.Cards do local n=state.cards[tostring(i)] or 0;label(content,if n>0 then c2.name.."  •  "..c2.rarity.."  ×"..n else "???  •  undiscovered",15,C.muted,32) end
 elseif name=="Daily" then
  local today=math.floor(os.time()/86400);local ready=state.lastDay~=today
  local dailyProgress=if ready and (state.daily==7 or (state.lastDay>0 and today-state.lastDay>1)) then 0 else state.daily
  label(content,if ready then "YOUR DAILY SIGNAL IS READY" else "NEXT SIGNAL IN "..(86400-os.time()%86400).."s",18,C.cyan,46)
  label(content,"Claim on consecutive UTC days. A missed day restarts the track. Session only.",14,C.muted,44)
  for i=1,7 do
   local status=if i<=dailyProgress then "CLAIMED" elseif i==dailyProgress+1 and ready then "READY" else "LOCKED"
   local c=card(content,"DAY "..i.."   /   "..status,(150*i).." credits + "..(if i==7 then "100 prisms + 2 free caches" else "5 prisms").." + 50 XP",90)
  end
  button(content,if ready then "Claim daily reward" else "Already claimed today",function() request("Daily") end,ready)
 elseif name=="Codes" then
  subtitle.Text="SHOP / SIGNAL CODES • sample: APEX2026"
  local code=""
  field(content,"Enter code",code,function(v) code=v end)
  label(content,"Try APEX2026 for 800 credits + 30 prisms. Codes ignore spaces at the ends and letter case. OLDAPEX is expired.",15,C.muted,64)
  button(content,"Redeem code",function() if state.codeRetry>os.time() then notify("Rate limited • retry in "..state.codeRetry-os.time().."s") else notify("Redeeming…");request("Code",{code=code}) end end,true)
  button(content,"← Back to shop",function() go("Shop") end)
 elseif name=="Quests" then
  local q=card(content,"FIRST FINISH",math.min(state.races,1).."/1 races completed • 500 credits + 20 prisms + 100 XP",132)
  button(q,if state.questClaimed then "CLAIMED" elseif state.races>=1 then "Claim reward" else "Race to complete",function() request("Quest") end,state.races>=1 and not state.questClaimed)
  local boost=card(content,"DOUBLE CREDIT BOOST",if state.boostUntil>os.time() then "ACTIVE • "..state.boostUntil-os.time().."s remaining" else "Double race credits for ten minutes • 30 prisms",130)
  button(boost,"Activate boost",function() buy("ACTIVATE BOOST","10 minutes of double race credits.\nFull price: 30 prisms","Boost",{}) end)
  local offer=card(content,"PADDOCK WELCOME OFFER",if state.offerBought then "PURCHASED" else "3 free cache tokens • 500 credits • expires in "..math.max(0,state.offerUntil-os.time()).."s",130)
  button(offer,"Get offer • 500 credits",function() buy("WELCOME OFFER","Three cache tokens. Once per session.\n500 credits","Offer",{}) end)
 elseif name=="Party" then
  field(content,"Search demo participants",partySearch,function(v) partySearch=v;build("Party") end)
  button(content,"Clear search",function() partySearch="";build("Party") end)
  local members={};for id in state.party do table.insert(members,id) end
  label(content,"PARTY  /  YOU"..(if #members>0 then " + "..table.concat(members,", ") else " • no guests yet"),16,C.cyan,40)
  for _,f in {{id="mira",name="Mira",status="Online"},{id="dex",name="Dex",status="Racing"},{id="sol",name="Sol",status="Offline"}} do
   if string.find(string.lower(f.name),string.lower(partySearch),1,true) then
    local c=card(content,f.name.."  •  DEMO PARTICIPANT",f.status.." • "..(state.invites[f.id] or "Not invited"),130)
    button(c,if state.party[f.id] then "In your party" elseif state.invites[f.id] then state.invites[f.id] else "Invite",function() request("Invite",{id=f.id}) end,f.status=="Online")
   end
  end
 elseif name=="Mechanic" then
  subtitle.Text="VESPER / PIT ENGINEER"
  label(content,"“Fast is a feeling. Reliable is a craft.”",25,C.cyan,70)
  local message=if state.job=="none" then "I need real track telemetry. Finish one race in any kart and bring the data back. I'll pay 400 credits, 10 prisms and 80 XP." elseif state.job=="accepted" then "Your logger is running. Finish one race, then come back to claim your reward." elseif state.job=="ready" then "Clean data. Nice work out there. Your reward is ready." else "The telemetry is perfect. Your one-time job is complete. See you on the grid."
  label(content,message,17,C.muted,100)
  if state.job=="none" then
   smallButtons(content,{{"Accept job",function() request("Job",{choice="accept"}) end,true},{"Decline",function() request("Job",{choice="decline"});close() end}})
  elseif state.job=="ready" then button(content,"Deliver telemetry • claim reward",function() request("Job",{choice="claim"}) end,true) end
  button(content,"Ask about racing",function() notify("Vesper: Hold accelerate, choose an inside line, and save boost for the straights.") end)
  button(content,"Leave conversation",function() close() end)
 elseif name=="Settings" then
  local settings=state.settings
  for _,key in {"music","effects"} do
   local c=card(content,string.upper(key).." VOLUME",settings[key].."% • use − / + with touch or controller",134)
   smallButtons(c,{{"− 10",function() request("Settings",{[key]=settings[key]-10}) end},{string.rep("━",math.floor(settings[key]/10)).." "..settings[key].."%",function() request("Settings",{[key]=(settings[key]+10)%110}) end},{"+ 10",function() request("Settings",{[key]=settings[key]+10}) end}})
  end
  for _,item in {{key="damage",name="Damage numbers"},{key="shake",name="Camera shake"},{key="large",name="Larger text"},{key="reduced",name="Reduced motion"}} do
   button(content,item.name.."  /  "..(if settings[item.key] then "ON" else "OFF"),function() request("Settings",{[item.key]=not settings[item.key]}) end)
  end
  cycle(content,"Graphics",{"High","Low"},settings.quality,function(v) request("Settings",{quality=v}) end)
  label(content,"CONTROLS\nDrive: W/S or ↑/↓ • steer A/D or ←/→ • Shift boost • R recover\nController: RT accelerate / LT brake / left stick steer / X boost\nV / L1 scoreboard • Q / Y quick chat • B close\nTouch: use the road controls. No damage or knockout mode.",14,C.muted,120)
  button(content,"Reset defaults",function() buy("RESET SETTINGS","Restore all audio, display and accessibility defaults?","ResetSettings",{}) end)
 elseif name=="Results" then
  subtitle.Text="RACE COMPLETE • rewards accepted once"
  label(content,"+"..state.reward.." CREDITS   /   +15 PRISMS   /   +150 XP",22,C.cyan,60)
  for i,v in state.results do label(content,i.."  "..v.name.."  •  "..(if v.finish then string.format("%.1fs",v.time) else "RACING • LAP "..v.lap),18,if v.id==p.UserId then C.cyan else C.text,42) end
  button(content,"Return to paddock",function() close() end,true)
 elseif name=="Scoreboard" then
  subtitle.Text="LIVE CLASSIFICATION • leaders first • circuit mode"
  for i,v in (if race then race.board else state.results) do label(content,i.."  "..v.name.."  /  LAP "..v.lap.."  /  "..(if v.finish then "FINISHED" else "RACING"),18,if v.id==p.UserId then C.cyan else C.text,54) end
 elseif name=="Chat" then
  subtitle.Text="QUICK CHAT • "..(if state.chatUntil>os.time() then "COOLDOWN "..state.chatUntil-os.time().."s" else "READY")
  local chats={"Good luck!","Nice overtake!","Let's race!","Great driving!","On your left!","Well played!","One more race?","Thanks!"}
  local wheel=create("Frame",{Size=UDim2.new(1,0,0,340),BackgroundTransparency=1},content)
  local center=label(wheel,"QUICK\nCHAT",20,C.cyan,70);center.AnchorPoint=Vector2.new(0.5,0.5);center.Position=UDim2.fromScale(0.5,0.5);center.Size=UDim2.fromOffset(100,70);center.TextXAlignment=Enum.TextXAlignment.Center
  for i,t in chats do
   local a=(i-1)*math.pi/4-math.pi/2
   local b=button(wheel,t,function() request("Chat",{index=i});close() end,false,88)
   b.TextWrapped=true;b.TextSize=12;b.Size=UDim2.fromOffset(88,48);b.AnchorPoint=Vector2.new(0.5,0.5);b.Position=UDim2.new(0.5,math.cos(a)*116,0.5,math.sin(a)*128)
  end
 end
 if UIS.GamepadEnabled then
  local focus:GuiObject=closeButton
  if lastPageFocus==name then for _,v in content:GetDescendants() do if v:IsA("TextButton") and v.Text==priorText then focus=v;break end end end
  GS.SelectedObject=focus
 end
 lastPageFocus=name
end
close=function()
 if modalShade.Visible then dismissConfirm();return end
 if current=="Livery" and dirty then confirm("LEAVE DESIGN?","Discard your unsaved changes?",function() dirty=false;draft=table.clone(state.livery);current="";panel.Visible=false;shade.Visible=false;GS.SelectedObject=navButtons.Livery end,"Discard");return end
 if current=="Results" then request("Return") end
 local old=current;current="";lastPageFocus="";panel.Visible=false;shade.Visible=false
 GS.SelectedObject=nil
 if navButtons[old] then GS.SelectedObject=navButtons[old] elseif state and state.phase=="Hub" then GS.SelectedObject=play end
end
local raceHUD=create("Frame",{BackgroundTransparency=1,Position=UDim2.fromOffset(20,88),Size=UDim2.new(1,-40,0,90),Visible=false},canvas)
local raceInfo=label(raceHUD,"",22,C.text,44);raceInfo.Size=UDim2.new(0.65,0,0,44)
local speedInfo=label(raceHUD,"",15,C.cyan,32);speedInfo.Position=UDim2.fromOffset(0,44)
local countdown=label(canvas,"",64,C.cyan,90);countdown.AnchorPoint=Vector2.new(0.5,0.5);countdown.Position=UDim2.fromScale(0.5,0.37);countdown.Size=UDim2.fromOffset(260,90);countdown.TextXAlignment=Enum.TextXAlignment.Center;countdown.Font=Enum.Font.GothamBlack;countdown.Visible=false
local controls=create("Frame",{BackgroundTransparency=1,Size=UDim2.new(1,-32,0,160),Position=UDim2.new(0,16,1,-170),Visible=false},canvas)
local held={throttle=0,steer=0,boost=false}
local function hold(text:string,x:number,y:number,w:number,key:string,val:any)
 local b=button(controls,text,function() end,false,w);b.Position=UDim2.new(x,0,0,y)
 b.InputBegan:Connect(function(input) if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then held[key]=val end end)
 b.InputEnded:Connect(function(input) if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then held[key]=if key=="boost" then false else 0 end end)
 return b
end
hold("◀",0,95,62,"steer",-1);local right=hold("▶",0,95,62,"steer",1);right.Position=UDim2.fromOffset(72,95)
local gas=hold("ACCEL",1,95,84,"throttle",1);gas.AnchorPoint=Vector2.new(1,0)
local brake=hold("BRAKE",1,95,76,"throttle",-1);brake.Position=UDim2.new(1,-94,0,95);brake.AnchorPoint=Vector2.new(1,0)
local boost=hold("BOOST",1,39,84,"boost",true);boost.AnchorPoint=Vector2.new(1,0);boost.BackgroundColor3=C.cyan;boost.TextColor3=C.bg
local board=button(controls,"BOARD",function() if current=="Scoreboard" then close() else build("Scoreboard") end end,false,84);board.Position=UDim2.new(0.5,-90,0,95)
local chat=button(controls,"CHAT",function() if current=="Chat" then close() else build("Chat") end end,false,84);chat.Position=UDim2.new(0.5,6,0,95)
local recover=button(controls,"RECOVER",function() request("Recover") end,false,100);recover.Position=UDim2.fromOffset(0,39)
local leave=button(raceHUD,"EXIT",function() confirm("LEAVE DRIVE","Return to the hub? Unfinished races earn no reward.",function() request("Return");close() end) end,false,80);leave.Position=UDim2.new(1,-80,0,0)
local help=create("Frame",{Size=UDim2.new(0.9,0,0,140),AnchorPoint=Vector2.new(0.5,1),Position=UDim2.new(0.5,0,1,-86),BackgroundColor3=C.panel,Visible=false,ZIndex=22},canvas);round(help);stroke(help,C.cyan);create("UISizeConstraint",{MaxSize=Vector2.new(650,160)},help)
local helpText=label(help,"",15,C.text,65);helpText.Position=UDim2.fromOffset(14,8);helpText.Size=UDim2.new(1,-28,0,65)
local helpRow=row(help);helpRow.Position=UDim2.fromOffset(14,82);helpRow.Size=UDim2.new(1,-28,0,44)
local backHelp=button(helpRow,"Back",function() if helpStep>1 then helpStep-=1 end end,false,88)
button(helpRow,"Next",function() if helpStep>=3 then helpStep=0;request("Tutorial",{step=4});GS.SelectedObject=navButtons.Help else helpStep+=1 end end,true,88)
button(helpRow,"Skip",function() helpStep=0;request("Tutorial",{step=4});GS.SelectedObject=navButtons.Help end,false,88)
local useHelp=button(helpRow,"Use action",function() build(({"Garage","Shop","Race"})[helpStep]) end,false,115)
local helpHighlight=create("UIStroke",{Color=C.cyan,Thickness=3,Enabled=false},navButtons.Garage)
local function back()
 if modalShade.Visible then dismissConfirm()
 elseif current~="" then close()
 elseif helpStep>0 then if helpStep>1 then helpStep-=1 else helpStep=0;request("Tutorial",{step=4});GS.SelectedObject=navButtons.Help end end
end
CAS:BindAction("ApexBack",function(_,st) if st==Enum.UserInputState.Begin then back() end return Enum.ContextActionResult.Sink end,false,Enum.KeyCode.ButtonB)
CAS:BindAction("ApexBoard",function(_,st) if st==Enum.UserInputState.Begin then if current=="Scoreboard" then close() else build("Scoreboard") end end return Enum.ContextActionResult.Sink end,false,Enum.KeyCode.V,Enum.KeyCode.ButtonL1)
CAS:BindAction("ApexChat",function(_,st) if st==Enum.UserInputState.Begin and not UIS:GetFocusedTextBox() then if current=="Chat" then close() else build("Chat") end end return Enum.ContextActionResult.Sink end,false,Enum.KeyCode.Q,Enum.KeyCode.ButtonY)
CAS:BindAction("ApexRecover",function(_,st) if st==Enum.UserInputState.Begin then request("Recover") end end,false,Enum.KeyCode.R)
local gpSteer=0
local gpThrottle=0
local gpBrake=0
local gpBoost=false
UIS.InputChanged:Connect(function(i)
 if i.KeyCode==Enum.KeyCode.Thumbstick1 then gpSteer=i.Position.X end
 if i.KeyCode==Enum.KeyCode.ButtonR2 then gpThrottle=i.Position.Z end
 if i.KeyCode==Enum.KeyCode.ButtonL2 then gpBrake=i.Position.Z end
end)
UIS.InputBegan:Connect(function(i) if i.KeyCode==Enum.KeyCode.ButtonX then gpBoost=true end end)
UIS.InputEnded:Connect(function(i) if i.KeyCode==Enum.KeyCode.ButtonX then gpBoost=false end end)
local function applySettings()
 local ss=game:GetService("SoundService")
 music.Volume=state.settings.music/100*0.35;clickSound.Volume=state.settings.effects/100*0.35
 local bloom=game:GetService("Lighting"):FindFirstChildOfClass("BloomEffect");if bloom then bloom.Enabled=state.settings.quality=="High" end
 for _,x in screen:GetDescendants() do if x:IsA("TextLabel") or x:IsA("TextButton") or x:IsA("TextBox") then
  local original=x:GetAttribute("BaseText") or x.TextSize;x:SetAttribute("BaseText",original);x.TextSize=original*(if state.settings.large then 1.12 else 1)
 end end
end
Push.OnClientEvent:Connect(function(kind,data,msg)
 if kind=="State" then
  local oldPhase=if state then state.phase else ""
  state=data
  if current=="Livery" and not dirty then draft=table.clone(state.livery) end
  if state.phase=="Race" or state.phase=="Preview" then current="";panel.Visible=false;shade.Visible=false;helpStep=0
  elseif state.phase=="Results" and oldPhase~="Results" then build("Results")
  elseif current~="" and not modalShade.Visible then build(current) end
  if state.tutorial==0 and oldPhase=="" then helpStep=1 end
  applySettings();notify(msg or "")
 elseif kind=="Race" then
  race=data
  if current=="Scoreboard" then
   local i=0;for _,v in content:GetChildren() do if v:IsA("TextLabel") then i+=1;local racer=data.board[i];if racer then v.Text=i.."  "..racer.name.."  /  LAP "..racer.lap.."  /  "..(if racer.finish then "FINISHED" else "RACING") end end end
  end
  if state and data.phase=="Results" then state.results=data.board;if current=="Results" then
   local i=0;for _,v in content:GetChildren() do if v:IsA("TextLabel") and not v.Text:find("CREDITS") then i+=1;local racer=data.board[i];if racer then v.Text=i.."  "..racer.name.."  •  "..(if racer.finish then string.format("%.1fs",racer.time) else "RACING • LAP "..racer.lap) end end end
  end end
 elseif kind=="Chat" then notify(data)
 elseif kind=="Open" then
  local map={GARAGE="Garage",SHOP="Shop",MECHANIC="Mechanic",RACE="Race"};build(map[data] or data)
 end
end)
local tickSend=0
local tickUI=0
local lastViewport=Vector2.zero
Run.RenderStepped:Connect(function(dt)
 if not state then return end
 local driving=state.phase=="Race" or state.phase=="Preview"
 motorSound.Volume=if driving and race then state.settings.effects/100*math.min(race.speed/100,1)*0.14 else 0
 motorSound.PlaybackSpeed=if race then 0.7+race.speed/100 else 1
 hub.Visible=not driving and state.phase~="Results" and not panel.Visible
 nav.Visible=not driving
 raceHUD.Visible=driving;controls.Visible=driving;countdown.Visible=driving and race~=nil and race.count>0
 if countdown.Visible then countdown.Text=tostring(race.count) end
 local camera=workspace.CurrentCamera
 if camera then
  camera.CameraType=Enum.CameraType.Scriptable
  local model=workspace:FindFirstChild("Kart_"..p.UserId)
  if (driving or state.phase=="Results") and model and model:IsA("Model") then
   local cf=model:GetPivot();local target=CFrame.lookAt((cf*CFrame.new(0,9,17)).Position,cf.Position+cf.LookVector*10)
   if state.settings.shake and not state.settings.reduced and held.boost then target*=CFrame.new(math.sin(os.clock()*32)*0.045,math.cos(os.clock()*39)*0.035,0) end
   camera.CFrame=camera.CFrame:Lerp(target,if state.settings.reduced then 1 else math.min(1,dt*7));camera.FieldOfView=76
  elseif roam and not panel.Visible then
   camera.CameraType=Enum.CameraType.Custom;local ch=p.Character;if ch then camera.CameraSubject=ch:FindFirstChildOfClass("Humanoid") end
  else
   camera.CFrame=CFrame.lookAt(Vector3.new(17,13,48),Vector3.new(-3,3,27));camera.FieldOfView=65
  end
  local vp=camera.ViewportSize
  if vp~=lastViewport then
   lastViewport=vp
   local scale=if vp.X>1000 then math.clamp(vp.Y/820,1,1.5) else 1
   uiScale.Scale=scale;canvas.Size=UDim2.fromScale(1/scale,1/scale)
   local narrow=vp.X<650
   panel.Size=if narrow then UDim2.new(0.96,0,0.76,0) else UDim2.new(0.88,0,0.76,0)
   hero.TextSize=if narrow then 26 else 38;hero.Size=UDim2.new(if narrow then 0.95 else 0.55,0,0,108)
   featured.Visible=not narrow;desc.Visible=not narrow
   explore.Position=UDim2.fromOffset(0,if narrow then 264 else 334)
   board.Position=UDim2.new(0.5,-90,0,if narrow then 0 else 95);chat.Position=UDim2.new(0.5,6,0,if narrow then 0 else 95)
   if narrow then brake.Position=UDim2.new(1,-94,0,39) else brake.Position=UDim2.new(1,-94,0,95) end
   play.Position=UDim2.fromOffset(0,if narrow then 160 else 226);dailyButton.Position=UDim2.fromOffset(0,if narrow then 212 else 280)
   brand.Text=if narrow then "N / A" else "N / A   •   NEON APEX"
   wallet.TextSize=if narrow then 13 else 17;meta.TextSize=if narrow then 9 else 11
   header.Position=UDim2.fromOffset(8,4);header.Size=UDim2.new(1,-16,0,66)
  end
 end
 tickSend+=dt;tickUI+=dt
 if driving and tickSend>=0.06 then
  tickSend=0
  local t=held.throttle;local st=held.steer;local boostHeld=held.boost or gpBoost
  if not UIS:GetFocusedTextBox() then
   if UIS:IsKeyDown(Enum.KeyCode.W) or UIS:IsKeyDown(Enum.KeyCode.Up) then t=1 end
   if UIS:IsKeyDown(Enum.KeyCode.S) or UIS:IsKeyDown(Enum.KeyCode.Down) then t=-1 end
   if UIS:IsKeyDown(Enum.KeyCode.A) or UIS:IsKeyDown(Enum.KeyCode.Left) then st=-1 end
   if UIS:IsKeyDown(Enum.KeyCode.D) or UIS:IsKeyDown(Enum.KeyCode.Right) then st=1 end
   if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then boostHeld=true end
  end
  if math.abs(gpSteer)>0.1 then st=gpSteer end
  if gpThrottle>0.1 then t=gpThrottle end;if gpBrake>0.1 then t=-gpBrake end
  Drive:FireServer(t,st,boostHeld)
 end
 if current=="Mechanic" and dialogueOrigin and p.Character and (p.Character:GetPivot().Position-dialogueOrigin).Magnitude>18 then close();notify("You walked away from Vesper.") end
 if tickUI>=0.3 then
  tickUI=0
  if current=="Chat" then subtitle.Text="QUICK CHAT • "..(if state.chatUntil>os.time() then "COOLDOWN "..(state.chatUntil-os.time()).."s" else "READY") end
  if current=="Daily" then for _,v in content:GetChildren() do if v:IsA("TextLabel") and v.Text:find("NEXT SIGNAL") then v.Text="NEXT SIGNAL IN "..(86400-os.time()%86400).."s" end end end
  wallet.Text=string.format("%s  ◈     %s  ◆",tostring(state.coins),tostring(state.gems))
  meta.Text=string.format("LV %d • XP %d/250   /   RACES %d   /   INCOME %d   /   %s",state.level,state.xp%250,state.races,state.income,state.save)
  explore.Text=if roam then "SHOWROOM VIEW" else "EXPLORE PADDOCK"
  featured.Text=string.upper(D.find(D.Karts,state.kart).name).."\n"..string.upper(D.find(D.Karts,state.kart).category).." / NEXT RACE"
  dailyButton.Text=if state.lastDay~=math.floor(os.time()/86400) then "DAILY SIGNAL  •  READY" else "DAILY SIGNAL  •  CLAIMED"
  if state.phase=="Queue" and current=="Race" then
   for _,v in content:GetChildren() do if v:IsA("TextLabel") and v.Text:find("QUEUE") then v.Text=state.queueMode.." QUEUE  •  4 / 4 racers  •  starts in "..math.max(0,state.queueEnd-os.time()).."s" end end
  end
  if driving and race then
   local pos=1;for i,v in race.board do if v.id==p.UserId then pos=i end end
   raceInfo.Text=(if state.phase=="Preview" then "PREVIEW DRIVE" else "P"..pos.." / "..#race.board.."    LAP "..race.lap.." / "..race.laps)
   speedInfo.Text=race.speed.." KM/H   •   BOOST "..race.energy.."%   •   "..race.track.." • "..math.floor(race.progress*100).."% SECTOR"
  end
  help.Visible=helpStep>0
  if helpStep>0 then
   for _,b in helpRow:GetChildren() do if b:IsA("TextButton") then b.Size=UDim2.new(0.25,-6,0,44);b.TextSize=12 end end
   helpText.Text="PILOT ORIENTATION  "..helpStep.." / 3\n"..({"↓ Garage: inspect and choose your next kart.","↓ Shop: upgrade your loadout with earned credits.","↓ Race: join a queue, vote, then chase a podium."})[helpStep]
   backHelp.Active=helpStep>1;backHelp.TextTransparency=if helpStep==1 then 0.6 else 0
   helpHighlight.Parent=if helpStep==3 then play else navButtons[if helpStep==1 then "Garage" else "Shop"];helpHighlight.Enabled=true
  else helpHighlight.Enabled=false end
 end
end)
request("Sync")
