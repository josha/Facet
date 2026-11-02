--!strict

export type Values = {
	vector2: (x: number, y: number) -> unknown,
	vector3: (x: number, y: number, z: number) -> unknown,
	udim: (scale: number, offset: number) -> unknown,
	udim2: (xs: number, xo: number, ys: number, yo: number) -> unknown,
	color: (r: number, g: number, b: number) -> unknown,
	font: (family: string, weight: string) -> unknown,
	enum: (name: string, item: string) -> unknown,
	cframe: (components: { number }) -> unknown,
	raycastParams: (include: boolean, instances: { unknown }) -> unknown,
}

export type Environment = {
	values: Values,
	read: (subject: unknown, property: string) -> unknown,
	service: (name: string) -> unknown,
	invoke: (node: unknown, method: string, ...unknown) -> ...unknown,
	descendants: (node: unknown) -> { unknown },
}

return {}
