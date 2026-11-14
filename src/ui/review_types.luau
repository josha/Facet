--!strict
export type ReviewRect = { x: number, y: number, width: number, height: number }
export type ReviewColor = { r: number, g: number, b: number }
export type ReviewText = {
	content: string,
	size: number,
	bold: boolean,
	font: string?,
	role: string?,
	color: ReviewColor,
	transparency: number,
	ink: ReviewRect?,
	native: boolean?,
}
export type ReviewOutset = { left: number, top: number, right: number, bottom: number }
export type ReviewElement = {
	index: number,
	parent: number?,
	class: string,
	path: string,
	rect: ReviewRect,
	visible: boolean,
	interactive: boolean,
	clips: boolean?,
	fan: boolean?,
	z: number?,
	turn: number?,
	fill: ReviewColor,
	fillTransparency: number,
	image: boolean,
	paint: ReviewRect?,
	ground: boolean?,
	text: ReviewText?,
	unfit: string?,
	reveal: string?,
	region: boolean?,
	outset: ReviewOutset?,
	sink: boolean?,
	layer: string?,
}
export type ReviewSnapshot = { width: number, height: number, elements: { ReviewElement }, touch: boolean? }
export type ReviewSeverity = "high" | "medium" | "low"
export type ReviewFinding = {
	rule: string,
	severity: ReviewSeverity,
	path: string,
	detail: string,
	rect: ReviewRect,
}
export type ReviewProminence = {
	path: string,
	content: string,
	size: number,
	role: string?,
	bold: boolean,
	score: number,
}
export type ReviewMeasures = {
	width: number,
	height: number,
	numeral: { content: string, size: number, share: number }?,
	body: number?,
	plates: number,
	control: { height: number, aspect: number }?,
	action: {
		label: string,
		x: number,
		y: number,
		width: number,
		height: number,
		scale: number,
		contrast: number,
	}?,
}
export type ReviewReport = {
	findings: { ReviewFinding },
	prominence: { ReviewProminence },
	measures: ReviewMeasures,
	sizes: { number },
	fixes: { [string]: string },
	text: string,
}

return {}
