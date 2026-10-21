--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Hub = require(ReplicatedStorage.Shared.Hub)
local Interface = require(script.Interface)
Interface.mount(Hub.context(Players.LocalPlayer))
