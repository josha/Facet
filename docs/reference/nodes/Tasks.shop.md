# Tasks.shop

Open a modal shop.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local C=Facet.Compose
local app = Facet.app({})
local UI=app.UI
local open,filter,status=C.cell(false),C.cell("All"),C.cell("")
local owned=C.cell({} :: {[string]:boolean})
local buy=assert(game.ReplicatedStorage:FindFirstChild("Purchase")) :: RemoteFunction
type Item={id:string,label:string,kind:string}
local items:{Item}={{id="kart",label="Kart / 250 Coins",kind="Karts"}}
local rows=C.formula(function(use:Facet.Use):{Item}
local rows={} for _,item in items do
if use(filter)=="All" or item.kind==use(filter) then table.insert(rows,item) end
end return rows end)
local options:{Facet.PickerOption<string>}={
{value="All",label="All"},{value="Karts",label="Karts"},{value="Other",label="Other"},
}
app.mount(function()
return UI.Screen "Root" {
UI.Button {label="Shop",onActivate=function() open:set(true) end},
UI.Sheet {title="Shop",isPresented=open,closeButton="Close",
content=function() return UI.VStack "Rows" {width="fill",align="stretch",gap="s",
UI.Picker {selected=filter,options=options,style="menu"},
UI.Text {text=status,wrap=true},
UI.Text {text="No items.",Visible=function(use:Facet.Use) return #use(rows)==0 end},
C.keyed {from=rows,key=function(item:Item) return item.id end,
render=function(row:Facet.Readable<Item>) local item=row:peek()
return UI.VStack "Rows" {align="stretch",gap="xs",
UI.Text {text=item.label,wrap=true},
UI.Button {
label=function(use:Facet.Use) return if use(owned)[item.id] then "Owned" else "Buy" end,
enabled=function(use:Facet.Use) return not use(owned)[item.id] end,
onActivate=function()
local bought:boolean,text:string=buy:InvokeServer(item.id)
owned:update(function(value) value=table.clone(value) value[item.id]=bought return value end)
status:set(text)
end,
}, }
end }, } end,
}, }
end)
script.Destroying:Connect(app.dispose)
```

The server checks price, balance and ownership. Return bought and text. See [Tasks.sheet](Tasks.sheet.md).
