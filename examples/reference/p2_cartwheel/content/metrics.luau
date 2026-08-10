--!strict
-- Cartwheel's proof-owned layout metrics (spec §2 "Proposed theme metrics").
--
-- THE SPEC ASKS FOR `metrics.cartwheel.*` IN THE TOKEN SCHEMA, AND A PROOF
-- CANNOT PUT THEM THERE. A theme metric NAME is validated against the neutral
-- ThemeSnapshot (`snapshot.isMetricPath`), so a name no shipped package declares
-- is a construction error, not a new token — and adding one is a framework/theme
-- change, which is the lead's call and outside this package's scope
-- (package-briefs.md: "token additions are a lead decision"). So the seven
-- numbers live here, in ONE place, as declared literals.
--
-- A literal number is legal everywhere the framework takes a dimension and it
-- means exactly one thing: this value is deliberately theme-independent. Every
-- OTHER number in this proof is a token — type roles, space steps, radii,
-- strokes, target sizes — so this table is the whole surface a theme cannot
-- move, and the report names it as the stage's one metric deviation.
local metrics = {}

-- shell sidebar lane `minWidth` — five control rows' worth of label
metrics.sidebarMin = 220
-- shell detail lane `minWidth` — below this a two-lane shell is illegal
metrics.detailMin = 360
-- dashboard card lane legality
metrics.cardMin = 280
-- gallery `Grid.minColumnWidth`
metrics.tileMin = 96
-- Skyglow / Ledger / Top Five plot height
metrics.chartH = 160
-- Workbench + Plaza preview boxes
metrics.previewMin = 200
-- parallax header band height
metrics.heroH = 120

return table.freeze(metrics)
