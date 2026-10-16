# Types.nil

Native Instance properties accept reactive `nil` values to clear the property.
They also accept `Compose.static(instance)`. The pinned
Compose release types the payload of this marker as `unknown`. Thus Luau cannot
check the class of the wrapped Instance. Ordinary property values and reactive
sources keep their native types.

Run `lute run tools/facet types` to check every Luau file in the repository and
the public API witnesses. The checker compiles each file with the pinned runtime,
then checks strict types with pinned Roblox and Lute declarations. It uses the old
Luau solver by default. `--solver new` and `--solver both` select other solver runs.
Every selected solver must report zero type errors. Each invalid public probe must
be rejected. The checker increases the analyzer graph limit to check the complete
control types. A `--!strict` directive alone does not prove that a file is typed.
