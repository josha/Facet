--!strict

export type Report = { current: string?, demo: { active: string? }? }

return function(report: Report): string
	return (report.current or "") .. "/" .. (if report.demo then report.demo.active or "" else "")
end
