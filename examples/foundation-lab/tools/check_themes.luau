local serde = require("@lune/serde")
local Facet = require("../../../src")
local foundation = require("../themes/foundation")
for _, name in foundation.themeNames do
	local pkg, report = foundation.build(Facet.themes, name)
	if pkg == nil then
		print(serde.encode("json", report, true))
		error(`foundation ({name}) failed to compile`, 0)
	end
	assert(pkg.style.defaultTheme == name, "default theme")
	print(`ok {pkg.identity.id} default={name} themes={#pkg.style.themes}`)
end
