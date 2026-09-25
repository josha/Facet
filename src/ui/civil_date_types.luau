--!strict
export type CivilDate = { year: number, month: number, day: number, hour: number?, minute: number? }
export type Range = { start: CivilDate?, finish: CivilDate? }
export type Order = "mdy" | "dmy" | "ymd"
export type Locale = {
	months: { string }?,
	weekdays: { string }?,
	order: Order?,
	separator: string?,
	hourCycle: number?,
}
export type Module = {
	ENGLISH: Locale,
	isLeap: (number) -> boolean,
	daysIn: (number, number) -> number,
	problem: (unknown, boolean?) -> string?,
	toDays: (CivilDate) -> number,
	fromDays: (number) -> CivilDate,
	dateOf: (CivilDate) -> CivilDate,
	addDays: (CivilDate, number) -> CivilDate,
	addMonths: (CivilDate, number) -> CivilDate,
	compare: (CivilDate, CivilDate) -> number,
	same: (CivilDate?, CivilDate?) -> boolean,
	weekday: (CivilDate) -> number,
	monthGrid: (number, number, number) -> { CivilDate },
	within: (CivilDate, CivilDate?, CivilDate?) -> boolean,
	clampRange: (Range, CivilDate?, CivilDate?) -> Range?,
	fromUnix: (number, number) -> CivilDate,
	toUnix: (CivilDate, number) -> number,
	systemClock: (number?) -> () -> CivilDate,
	formatTime: (CivilDate, number) -> string,
	format: (CivilDate, Locale?) -> string,
	parse: (string, Locale?, boolean?) -> (CivilDate?, string?),
}
return {}
