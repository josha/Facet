--!strict

export type AudioWindow = { start: number?, span: number? }

local function audioWindow(summary: any, requested: AudioWindow?): any?
	local options: AudioWindow = requested or {}
	if summary.audio == nil then
		assert(options.start == nil and options.span == nil, "recording has no audio stream to sample")
		return nil
	end
	local start = options.start or 0
	assert(start == start and start >= 0 and start < summary.duration, "audio start must be within recording duration")
	local span = options.span or math.min(30, summary.duration - start)
	assert(span == span and span > 0 and span < math.huge, "audio span must be positive and finite")
	assert(start + span <= summary.duration, "audio window exceeds recording duration")
	return { start = start, span = span }
end

local function probeSummary(probe: any): any
	local duration = tonumber((probe.format or {}).duration)
	assert(duration ~= nil and duration > 0 and duration < math.huge, "recording has no positive duration")
	local video, audio = nil, nil
	for _, stream in probe.streams or {} do
		if stream.codec_type == "video" and video == nil then
			video = stream
		elseif stream.codec_type == "audio" and audio == nil then
			audio = stream
		end
	end
	assert(video ~= nil and video.width > 0 and video.height > 0, "recording has no readable video dimensions")
	return {
		duration = duration,
		video = {
			width = video.width,
			height = video.height,
			codec = video.codec_name,
			frameRate = video.avg_frame_rate,
		},
		audio = if audio ~= nil
			then { codec = audio.codec_name, channels = audio.channels, sampleRate = audio.sample_rate }
			else nil,
		audioSignal = if audio ~= nil then "unmeasured" else "no_audio_stream",
		visualJudgment = "unproved",
		audioJudgment = "unproved",
	}
end

local function audioMeasurement(log: string): any
	return {
		maxVolumeDb = string.match(log, "max_volume: ([^ ]+) dB"),
		meanVolumeDb = string.match(log, "mean_volume: ([^ ]+) dB"),
		silenceDetected = string.find(log, "silence_start:", 1, true) ~= nil,
		thresholdDb = -50,
	}
end

local function sampleCommands(original: string, output: string, summary: any, requested: AudioWindow?): { any }
	local window = audioWindow(summary, requested)
	local samples = {}
	for index, seconds in { 0, summary.duration / 2, math.max(0, summary.duration - 0.2) } do
		table.insert(samples, {
			kind = "frame",
			seconds = seconds,
			output = output .. "/frame-" .. tostring(index) .. ".png",
			argv = {
				"ffmpeg",
				"-nostdin",
				"-hide_banner",
				"-v",
				"error",
				"-n",
				"-ss",
				tostring(seconds),
				"-i",
				original,
				"-frames:v",
				"1",
				output .. "/frame-" .. tostring(index) .. ".png",
			},
		})
	end
	if window ~= nil then
		table.insert(samples, {
			kind = "audio",
			seconds = window.start,
			duration = window.span,
			output = output .. "/audio-sample.wav",
			argv = {
				"ffmpeg",
				"-nostdin",
				"-hide_banner",
				"-nostats",
				"-n",
				"-ss",
				tostring(window.start),
				"-i",
				original,
				"-t",
				tostring(window.span),
				"-map",
				"0:a:0",
				"-vn",
				"-af",
				"silencedetect=noise=-50dB:d=0.5,volumedetect",
				"-c:a",
				"pcm_s16le",
				output .. "/audio-sample.wav",
			},
		})
	end
	return samples
end

return {
	audioWindow = audioWindow,
	probeSummary = probeSummary,
	audioMeasurement = audioMeasurement,
	sampleCommands = sampleCommands,
}
