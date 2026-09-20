--!strict
-- GUILD CARD — the sign-up form (spec §14).
--
-- VARIANT B SHIPS, AND SAYS SO. The spec declares two variants: a masked field
-- with a "Show" toggle IF the bounded framework fix for secure text entry landed
-- in this stage, and otherwise a plain visible field with a permanent
-- disclosure caption. No masking landed (there is no secure/masked mode on
-- `UI.TextField` or `newTextInput` at v0.9.x), so this is Variant B, the caption
-- is not decoration, and the gap ships in framework-fixes.md rather than being
-- hidden behind a field that only looks secure.
--
-- The screen is otherwise a UI-capability exercise and states that on itself:
-- Roblox identity is ambient, so nothing here has a production job.
local signup = {}

function signup.new(app: any): any
	local UI = app.UI
	local Compose = app.Compose
	local S = app.S
	local Facet = app.Facet
	local identity = app.services.identity

	local self: any = {}
	local guildName = Compose.cell("")
	local watchword = Compose.cell("")
	local fieldError = Compose.cell("")
	local handle: any = nil
	local confirmHandle: any = nil
	self.guildName = guildName
	self.watchword = watchword
	self.fieldError = fieldError

	local nameField = UI.TextInput("GuildName")({
		value = guildName,
		placeholder = S.t("guild.name"),
		-- lowercase-trim, and idempotent by construction: running it twice
		-- answers what running it once did
		validate = function(proposed: string): string?
			return string.lower((string.gsub(proposed, "^%s*(.-)%s*$", "%1")))
		end,
		keyboardType = "email",
		clearButtonMode = "whileEditing",
		maxLength = 24,
		env = app.env,
		actionSystem = app.actionSystem,
	})

	local watchwordField = UI.TextInput("Watchword")({
		value = watchword,
		placeholder = S.t("guild.watchword"),
		maxLength = 32,
		env = app.env,
		actionSystem = app.actionSystem,
	})

	local canSubmit = Compose.formula(function(use)
		return use(guildName) ~= "" and use(watchword) ~= "" and use(app.commands.status("signup")) ~= "pending"
	end)
	local hasError = Compose.formula(function(use)
		return use(fieldError) ~= ""
	end)
	local pending = Compose.formula(function(use)
		return use(app.commands.status("signup")) == "pending"
	end)
	local cannotSubmit = Compose.formula(function(use)
		return not use(canSubmit)
	end)

	local function close()
		if handle ~= nil then
			app.presenter.dismiss(handle)
			handle = nil
		end
	end
	self.close = close

	local function submit()
		if not canSubmit:peek() then
			return
		end
		fieldError:set("")
		local name = guildName:peek()
		app.commands.submit({
			id = "signup",
			decide = function()
				return identity.decide(name)
			end,
			confirm = function()
				identity.signIn(name)
				app.toast(S.t("guild.welcome", { name = identity.normalize(name) }))
				close()
			end,
			revert = function()
				-- a field-level error, right under the row that caused it
				fieldError:set(S.t("reject.guildTaken"))
			end,
		})
	end
	self.submit = submit

	local function view(): any
		return UI.Screen("CartwheelGuildCard")({
			padding = "l",

			UI.VStack("Card")({
				gap = "m",
				padding = "l",
				surface = "raised",
				width = UI.fill(),

				UI.Text("Title")({ text = S.t("guild.title"), textSize = "title" }),
				UI.Text("Note")({
					text = S.t("guild.note"),
					textSize = "caption",
					role = "secondary",
					lineLimit = 3,
				}),
				nameField,
				app.when("ErrorWhen")({
					condition = hasError,
					thenView = function()
						return UI.Text("Error")({
							text = fieldError,
							textSize = "strong",
							lineLimit = 2,
						})
					end,
				}),
				watchwordField,
				-- VARIANT B's permanent caption: two lines are reserved for
				-- it, because the pseudo-locale wraps it
				UI.Text("Visible")({
					text = S.t("guild.watchwordVisible"),
					textSize = "caption",
					role = "secondary",
					lineLimit = 2,
				}),
				app.when("WorkingWhen")({
					condition = pending,
					thenView = function()
						return UI.Text("Working")({
							text = S.t("command.working"),
							textSize = "caption",
							surface = "chip",
						})
					end,
				}),
				UI.HStack("Toolbar")({
					gap = "s",
					align = "center",

					UI.Button("Cancel")({
						label = S.t("guild.cancel"),
						role = "cancel",
						onActivate = close,
					}),
					UI.Button("Submit")({
						label = S.t("guild.submit"),
						surface = "accent",
						enabled = canSubmit,
						onActivate = submit,
					}),
					app.when("HintWhen")({
						condition = cannotSubmit,
						thenView = function()
							return UI.Text("Hint")({
								text = S.t("guild.submitHint"),
								textSize = "caption",
								role = "secondary",
								lineLimit = 2,
								disclose = true,
							})
						end,
					}),
				}),
			}),
		})
	end

	function self.open()
		if handle ~= nil then
			return
		end
		fieldError:set("")
		handle = app.presentModal(function()
			return view()
		end, {
			outsideTapCancel = true,
			-- FOCUS AUTOSET, by PATH. A `newTextInput`'s focusable is its inner
			-- `Field` node, and this form has two of them, so the unambiguous
			-- spelling is the full path rather than the id.
			initialFocus = "/CartwheelGuildCard/Card/GuildName/Field",
		})
	end

	function self.isOpen(): boolean
		return handle ~= nil
	end

	-- signing out is destructive-shaped, so it asks first
	function self.openSignOut()
		if confirmHandle ~= nil then
			return
		end
		confirmHandle = app.presentModal(function()
			return UI.Screen("CartwheelSignOut")({
				padding = "l",

				UI.VStack("Card")({
					gap = "m",
					padding = "l",
					surface = "raised",

					UI.Text("Title")({ text = S.t("guild.signOutConfirm"), textSize = "heading" }),
					UI.Text("Body")({
						text = S.t("guild.signOutBody"),
						textSize = "caption",
						role = "secondary",
					}),
					UI.HStack("Toolbar")({
						gap = "s",

						UI.Button("Keep")({
							label = S.t("guild.cancel"),
							role = "cancel",
							onActivate = function()
								self.closeSignOut()
							end,
						}),
						UI.Button("SignOut")({
							label = S.t("guild.signOut"),
							role = "destructive",
							onActivate = function()
								identity.signOut()
								guildName:set("")
								watchword:set("")
								self.closeSignOut()
							end,
						}),
					}),
				}),
			})
		end, { outsideTapCancel = true, initialFocus = "Keep" })
	end

	function self.closeSignOut()
		if confirmHandle ~= nil then
			app.presenter.dismiss(confirmHandle)
			confirmHandle = nil
		end
	end

	function self.dump(): any
		return {
			open = handle ~= nil,
			signedIn = identity.signedIn:peek(),
			guild = identity.guildName:peek(),
			name = guildName:peek(),
			watchword = watchword:peek(),
			watchwordMasked = false,
			error = fieldError:peek(),
			canSubmit = canSubmit:peek(),
		}
	end

	return self
end

return signup
