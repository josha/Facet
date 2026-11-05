--!strict

export type Subject = typeof((function(value: unknown)
	if type(value) == "function" then
		error "a held subject cannot be a function"
	end
	return value
end)(nil))

export type Release = (subject: unknown) -> ()

export type Slot = Subject | Release

export type Owner<R> = {
	parent: Owner<R>?,
	nodeToken: number?,
	reactor: R?,
	boundary: { report: (unknown) -> () }?,
	head: Owner<R>?,
	disposed: boolean?,
	previous: Owner<R>?,
	following: Owner<R>?,
	release: (() -> ())?,
	after: (() -> ())?,
	batchRelease: Release?,
	[number]: Slot,
}

return {}
