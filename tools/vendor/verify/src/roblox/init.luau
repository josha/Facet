--!strict

local Performance = require "@self/performance"
local Network = require "@self/network"
local ExperienceHost = require "@self/experience-host"

local Datatypes = require "@self/datatypes"
local Environment = require "@self/environment"
local CheckpointPlan = require "@self/checkpoint-plan"
local ObservationSink = require "@self/observation-sink"
local PlaceBoot = require "@self/place-boot"
local ScenarioRunner = require "@self/scenario-runner"
local Scheduler = require "@self/scheduler"
local ScenarioStepJournal = require "@self/scenario-step-journal"
local TierLadder = require "@self/tier-ladder"
local WitnessHost = require "@self/witness-host"

export type Network = Network.Network
export type NetworkOptions = Network.Options
export type NetworkPayload = Network.Payload
export type ExperienceHostOptions = ExperienceHost.Options
export type ExperienceEndpoint = ExperienceHost.Endpoint

export type EnvironmentOptions<P = { [string]: unknown }, M = { [string]: unknown }, F = { [string]: unknown }> =
	Environment.Options<P, M, F>
export type EnvironmentDefineOptions = Environment.DefineOptions
export type EnvironmentClass<P = { [string]: unknown }, M = { [string]: unknown }> = Environment.ClassSpec<P, M>
export type EnvironmentLimits = Environment.Limits
export type EnvironmentOperation = Environment.Operation
export type Environment = Environment.Environment
export type Instance = Environment.Instance
export type EnvironmentSnapshot = Environment.Snapshot
export type EnvironmentMethod = Environment.Method
export type Signal<A... = ...unknown> = Environment.Signal<A...>
export type Connection = Environment.Connection
export type DatatypeVector2 = Datatypes.Vector2Value
export type DatatypeVector3 = Datatypes.Vector3Value
export type DatatypeCFrame = Datatypes.CFrameValue
export type DatatypeColor3 = Datatypes.Color3Value
export type DatatypeUDim = Datatypes.UDimValue
export type DatatypeUDim2 = Datatypes.UDim2Value
export type DatatypeEnum = Datatypes.EnumValue
export type VirtualScheduler = Scheduler.Scheduler
export type VirtualTask<A... = ...unknown, R... = ...unknown> = Scheduler.Task<A..., R...>
export type VirtualCallback<A... = ...unknown, R... = ...unknown> = Scheduler.Callback<A..., R...>
export type Window = WitnessHost.Window
export type WindowList = WitnessHost.WindowList
export type WindowSelection = WitnessHost.Selection
export type ViewportTarget = WitnessHost.ViewportTarget
export type ViewportRect = WitnessHost.ViewportRect
export type CropOutcome = WitnessHost.CropOutcome
export type CaptureFrame = WitnessHost.Frame
export type CaptureDeps = WitnessHost.CaptureDeps
export type CaptureReasons = WitnessHost.CaptureReasons
export type CaptureLimits = WitnessHost.CaptureLimits
export type CaptureOptions = WitnessHost.CaptureOptions
export type ChangeDeps = WitnessHost.ChangeDeps
export type ChangeReasons = WitnessHost.ChangeReasons
export type CheckpointRow = CheckpointPlan.Row
export type CheckpointOrdered<R = CheckpointRow> = CheckpointPlan.Ordered<R>
export type CheckpointFrame = WitnessHost.CheckpointFrame
export type CheckpointFramesOptions = WitnessHost.CheckpointFramesOptions
export type WitnessReceipt = WitnessHost.Receipt
export type WitnessOutcome = WitnessHost.Outcome
export type RecordReceiptOptions = WitnessHost.RecordOptions
export type PlaceBootStage = PlaceBoot.Stage
export type PlaceBootView = PlaceBoot.View
export type PlaceBootObserver = PlaceBoot.Observer
export type PlaceBootConfig = PlaceBoot.Config
export type PlaceBootDeps<B = unknown> = PlaceBoot.Deps<B>
export type PlaceBootReport = PlaceBoot.Report
export type PlaceBootHost<B = unknown, C = () -> unknown> = PlaceBoot.Host<B, C>
export type PlaceBootFiles = PlaceBoot.Files
export type PlaceBootCache<B = unknown, C = () -> unknown> = PlaceBoot.Cache<B, C>
export type PlaceBootMounted = PlaceBoot.Mounted
export type PlaceBootOpaque = PlaceBoot.Opaque
export type PlaceBootTreeDeps<B = unknown> = PlaceBoot.TreeDeps<B>
export type ScenarioDeps = ScenarioRunner.Deps
export type ScenarioPredicates = ScenarioRunner.Predicates
export type ScenarioReasons = ScenarioRunner.Reasons
export type ScenarioOptions = ScenarioRunner.Options
export type ScenarioSelection = ScenarioRunner.Selection
export type CheckReceiptOptions = WitnessHost.CheckReceiptOptions
export type TierLadderSpec = TierLadder.Spec
export type TierLadderSeal = TierLadder.Seal
export type TierLadderVerdict = TierLadder.Verdict
export type TierLadderReceiptOptions = TierLadder.ReceiptOptions
export type TierLadderUnsupportedRule = TierLadder.UnsupportedRule
export type TierLadderDecoder = TierLadder.Decoder
export type TierLadderVerbs = TierLadder.Verbs
export type SessionObservationOptions = TierLadder.SessionObservationOptions
export type ChunkedProbe = TierLadder.ChunkedProbe
export type ChunkedCallPlanOptions = TierLadder.CallPlanOptions
export type ClientObservationOptions = TierLadder.ClientObservationOptions
export type ClientObservationMarker = TierLadder.Marker
export type JourneyNames = TierLadder.JourneyNames
export type JourneyOptions = TierLadder.JourneyOptions
export type JourneyBinding = TierLadder.JourneyBinding
export type JourneyAcceptance = TierLadder.JourneyAcceptance
export type PredicateRow = TierLadder.PredicateRow
export type ObservationNode = ObservationSink.Node
type ObservationOwner = ObservationSink.Owner
export type ObservationTransport = ObservationSink.Transport
export type ObservationWire = ObservationSink.Wire
export type ObservationRecord = ObservationSink.Record
export type ObservationReportLimits = ObservationSink.ReportLimits
export type ObservationMarker = ObservationSink.Marker
export type ObservationMarkerLimits = ObservationSink.MarkerLimits
export type ObservationMarkerOptions = ObservationSink.MarkerOptions
export type ObservationValueNames = ObservationSink.ValueNames
export type ObservationSeam<N = ObservationNode> = ObservationSink.Seam<N>
export type ObservationSeamDeps<N = ObservationNode, O = ObservationOwner> = ObservationSink.SeamDeps<N, O>
export type ObservationSeamState<N = ObservationNode> = ObservationSink.SeamState<N>
export type ObservationAcquire<N = ObservationNode> = ObservationSink.Acquire<N>

return {
	performance = Performance,
	network = Network,
	experienceHost = ExperienceHost,
	testEnvironment = Environment.create,
	BASIC_ENVIRONMENT_CLASSES = Environment.BASIC_CLASSES,
	virtualScheduler = Scheduler.create,
	datatypes = Datatypes,
	isInstance = Environment.isInstance,
	typeName = Environment.typeName,
	witnessHost = WitnessHost,
	DEFAULT_CAPTURE_LIMITS = WitnessHost.DEFAULT_CAPTURE_LIMITS,
	DEFAULT_CAPTURE_REASONS = WitnessHost.DEFAULT_CAPTURE_REASONS,
	DEFAULT_CHANGE_REASONS = WitnessHost.DEFAULT_CHANGE_REASONS,
	DEFAULT_WHOLE_WINDOW_TOLERANCE = WitnessHost.DEFAULT_WHOLE_WINDOW_TOLERANCE,
	parseWindowRows = WitnessHost.parseWindowRows,
	selectWindow = WitnessHost.selectWindow,
	pngSize = WitnessHost.pngSize,
	parsePid = WitnessHost.parsePid,
	documentWindowSize = WitnessHost.documentWindowSize,
	captureFrame = WitnessHost.captureFrame,
	changedPathArgs = WitnessHost.changedPathArgs,
	acceptsChange = WitnessHost.acceptsChange,
	looksLikeWholeWindow = WitnessHost.looksLikeWholeWindow,
	checkpointFrames = WitnessHost.checkpointFrames,
	recordReceipt = WitnessHost.recordReceipt,
	decodeReceipt = WitnessHost.decodeReceipt,
	checkReceipt = WitnessHost.checkReceipt,
	placeBoot = PlaceBoot,
	bootPlace = PlaceBoot.run,
	buildPlaceTree = PlaceBoot.buildTree,
	createPlaceCache = PlaceBoot.createCache,
	createPlaceRuntime = PlaceBoot.createRuntime,
	resolvePlaceAlias = PlaceBoot.resolveAlias,
	stabilizeCommit = PlaceBoot.stabilizeCommit,
	PLACE_COMMIT_TOKEN = PlaceBoot.COMMIT_TOKEN,
	PLACE_FRAME_SECONDS = PlaceBoot.FRAME_SECONDS,
	PLACE_BOOT_STAGES = PlaceBoot.STAGES,
	scenarioRunner = ScenarioRunner,
	checkpointPlan = CheckpointPlan,
	scenarioStepJournal = ScenarioStepJournal,
	DEFAULT_SCENARIO_REASONS = ScenarioRunner.DEFAULT_REASONS,
	observeScenario = ScenarioRunner.observe,
	tierLadder = TierLadder,
	DEFAULT_REFUSAL_PATTERNS = TierLadder.DEFAULT_REFUSAL_PATTERNS,
	classifyLadderVerdict = TierLadder.classify,
	judgeLadder = TierLadder.judge,
	ladderReceipt = TierLadder.receipt,
	sessionObservations = TierLadder.sessionObservations,
	chunkedCallPlan = TierLadder.chunkedCallPlan,
	clientObservations = TierLadder.clientObservations,
	journeySpec = TierLadder.journeySpec,
	observationSink = ObservationSink,
	OBSERVATION_ENCODED_TAG_SUFFIX = ObservationSink.ENCODED_TAG_SUFFIX,
	DEFAULT_OBSERVATION_REPORT_LIMITS = ObservationSink.DEFAULT_REPORT_LIMITS,
	DEFAULT_OBSERVATION_MARKER_LIMITS = ObservationSink.DEFAULT_MARKER_LIMITS,
	OBSERVATION_SINK_REASONS = ObservationSink.REASONS,
	observationWire = ObservationSink.createWire,
	boundedObservationValue = ObservationSink.boundedValue,
	observationMarkers = ObservationSink.markers,
	tallyObservations = ObservationSink.tally,
	observationReferencePool = ObservationSink.referencePool,
	createObservationSeamState = ObservationSink.createSeamState,
	pooledObservationSeam = ObservationSink.pooledSeam,
	armObservationSink = ObservationSink.arm,
	publishObservations = ObservationSink.publish,
}
