--!strict
local Facet = require("../../../src")
local foundation = require("../themes/foundation")
for _, name in foundation.themeNames do
	local pkg, report = foundation.build(Facet.themes, name)
	if pkg == nil then
		for _, issue in report.errors do
			print(`{issue.field}: {issue.message}`)
		end
		error(`foundation ({name}) failed to compile`, 0)
	end
	assert(pkg.style.defaultTheme == name, "default theme")
	print(`ok {pkg.identity.id} default={name} themes={#pkg.style.themes}`)
end
