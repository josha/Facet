--!strict

local Canvas = require("@self/canvas")
local Draw = require("@self/draw")
local Field = require("@self/field")
local Image = require("@self/image")
local Random = require("@self/random")
local Resample = require("@self/resample")

export type Image = Image.Image
export type Field = Field.Field
export type Color = Field.Color
export type Stop = Field.Stop
export type Canvas = Canvas.Canvas
export type Ink = Draw.Ink
export type Generator = Random.Generator
export type Filter = Resample.Filter

return table.freeze({
	Blur = require("@self/blur"),
	Canvas = Canvas,
	Checksum = require("@self/checksum"),
	Deflate = require("@self/deflate"),
	Draw = Draw,
	Field = Field,
	Font = require("@self/font"),
	Image = Image,
	Numeric = require("@self/numeric"),
	Png = require("@self/png"),
	Random = Random,
	Resample = Resample,
})
