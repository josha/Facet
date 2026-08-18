--!strict
--[[ NODE-PATH STRING WORK, ONCE (reuse audit REUSE-3, REUSE-6).

	A Facet node's identity is a `/`-joined path, and two questions get asked
	about one constantly: "is this path inside that subtree?" and "how do I put
	this id into a Lua pattern without it exploding?". Both had many answers.

	THE PREFIX TEST HAD SEVEN CORRECT COPIES AND TWO WRONG ONES, AND THE WRONG
	ONES WERE THE LIVE ROUTING. `src/present/focus_map.luau` exported the correct
	form and `src/present/presenter.luau` imported it at line 270 — then wrote
	`string.sub(path, 1, #rootPath) == rootPath` at 640 (which surface draws the
	focus ring) and again at 3326 (which surface a tap routes to). Two presented
	screens named `Menu` and `MenuBar` therefore routed each other's taps: a tap
	on `/MenuBar/Save` matched `/Menu`, was dispatched against the Menu handle,
	resolved to no node there, and did nothing at all.

	That failure mode is named in this repository TWICE already —
	`src/layout/text_audit.luau:99` calls it "the false-positive every prefix test
	in this repository has had to be fixed for at least once", and
	`src/render/renderer.luau:592` says it again — which is the argument for one
	owner rather than for a more careful copy.

	WHY A ROOT LEAF AND NOT `focus_map`. The correct copy lived under `present/`,
	so `layout/text_audit`, `render/renderer` and `controls/row_actions_spec` each
	grew their own rather than take a dependency on the presentation layer. The
	dependency direction is the whole cause; a module with no requires has no
	direction to get wrong. `src/spec_guard.luau` is the precedent.
]]

local paths = {}

--[[ Is `prefix` a PATH prefix of `path`? Segment-aligned, so `/S/Name` prefixes
	`/S/Name/Field` and does NOT prefix `/S/NameX/Field`. The equality case is
	first because a node is inside its own subtree — every caller here means
	"at or under". ]]
function paths.isPrefix(prefix: string, path: string): boolean
	return path == prefix or string.sub(path, 1, #prefix + 1) == prefix .. "/"
end

--[[ Escape every non-word byte so an author-supplied id can be interpolated
	into a Lua pattern. Ids reach patterns whenever a module asks "which nodes are
	under this one" with `string.match`, and an id containing `-` or `(` is legal
	Facet and illegal Lua-pattern syntax. The outer parentheses drop `gsub`'s
	second return value, which is a count nobody wants at a call site. ]]
function paths.escape(s: string): string
	return (string.gsub(s, "%W", "%%%0"))
end

return paths
