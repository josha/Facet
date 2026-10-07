--!strict
local fs = require("@std/fs")
local process = require("@std/process")
local task = require("@std/task")

local progress = process.args[2]
local pid = process.args[3]
if progress == nil or pid == nil or tonumber(pid) == nil then
	print("usage: lute run tools/lute/focus_up.luau PROGRESS_FILE STUDIO_PID")
	print("Posts D-pad Up to that Studio process while the focus-upstream step of the progress file is in progress.")
	print("Stops when the file PROGRESS_FILE.stop exists.")
	process.exit(2)
end

local PAD = "build/pad_key"
if not fs.exists(PAD) then
	local built = process.run({ "swiftc", "-O", "-o", PAD, "tools/studio/capture/pad_key.swift" })
	assert(built.ok, built.stderr)
end

local function waiting(): boolean
	if not fs.exists(progress) then
		return false
	end
	local last: string? = nil
	for line in string.gmatch(fs.readFileToString(progress), "[^\n]+") do
		if string.find(line, '"step":"focus-upstream"', 1, true) then
			last = line
		end
	end
	return last ~= nil and string.find(last, '"phase":"started"', 1, true) ~= nil
end

while not fs.exists(progress .. ".stop") do
	if waiting() then
		process.run({ PAD, pid, "18", "0.06" })
	end
	task.wait(0.35)
end
