--!strict

local Experience = require "@self/experience"
local Performance = require "@self/performance"

local Actors = require "@self/actors"
local Capability = require "@self/capability"
local Execution = require "@self/execution"
local HarnessModule = require "@self/harness"
local Lifecycle = require "@self/lifecycle"
local Manifest = require "@self/manifest"
local Matchers = require "@self/matchers"
local Media = require "@self/media"
local Observation = require "@self/observation"
local Plan = require "@self/plan"
local Shape = require "@self/shape"
local ReportModel = require "@self/report"
local SessionModule = require "@self/session"
local Spy = require "@self/spy"
local Transport = require "@self/transport"
local Types = require "@self/types"
local Wait = require "@self/wait"
local Witness = require "@self/witness"

export type ExperienceHost = Experience.Host
export type ExperienceCase = Experience.Case
export type ExperienceContext = Experience.Context
export type ExperienceResult = Experience.Result
export type PerformanceInput = Performance.Input
export type PerformanceSummary = Performance.Summary
export type PerformanceLimits = Performance.Limits
export type PerformanceEvaluation = Performance.Evaluation

export type Status = Types.Status
export type Failure = Types.Failure
export type StepResult = Types.StepResult
export type Artifact = Types.Artifact
export type Origin = Types.Origin
export type CaseResult = Types.CaseResult
export type ReportSource = Types.ReportSource
export type Report = Types.Report
export type ManifestEntry = Types.ManifestEntry
export type Manifest = Types.Manifest
export type SelectionSubject = Types.SelectionSubject
export type SelectionPredicate = Types.SelectionPredicate
export type ShardPayload = Types.ShardPayload
export type Expectation = Matchers.Expectation
export type Spy<A... = ...unknown> = Spy.Spy<A...>
export type SpyCall = Spy.Call

export type InvocationResult = HarnessModule.InvocationResult
export type Invoker = HarnessModule.Invoker
export type StepOptions = HarnessModule.StepOptions
export type Disposable<T = unknown> = HarnessModule.Disposable<T>
export type Resource<T = unknown> = HarnessModule.Resource<T>
export type Context = HarnessModule.Context
export type CaseRun = HarnessModule.CaseRun
export type CaseOptions = HarnessModule.CaseOptions
export type Selection = HarnessModule.Selection
export type RunOptions = HarnessModule.RunOptions
export type Harness = HarnessModule.Harness
export type SyntheticOptions = HarnessModule.SyntheticOptions

export type PlanUnit = Types.PlanUnit
export type PlanUnitDraft = Types.PlanUnitDraft
export type PlanPolicy = Types.PlanPolicy
export type RetryPolicy = Types.RetryPolicy
export type Plan = Types.Plan
export type PlanDraft = Types.PlanDraft
export type PlanSelection = Types.PlanSelection
export type PlanBatch = Types.PlanBatch
export type BatchingMode = Types.BatchingMode

export type BatchStatus = Types.BatchStatus
export type BatchOutcome = Types.BatchOutcome
export type AttemptRecord = Types.AttemptRecord
export type BatchRecord = Types.BatchRecord
export type Fact = Types.Fact
export type ExecutionProvenance = Types.ExecutionProvenance
export type ExecutionReport = Types.ExecutionReport
export type Host = Execution.Host
export type Fixture = Execution.Fixture
export type PlanAccount = Execution.Account
export type ExecutionOptions = Execution.Options

export type ActorProbe = Actors.Probe
export type ActorOps<H = unknown> = Actors.Ops<H>
export type ActorSpec = Actors.Spec

export type MediaAudioWindow = Media.AudioWindow
export type MediaResolvedAudioWindow = Media.ResolvedAudioWindow
export type MediaRecording = Media.Recording
export type MediaProbe = Media.Probe
export type MediaProbeStream = Media.ProbeStream
export type MediaSummary = Media.Summary
export type MediaAudioMeasurement = Media.AudioMeasurement
export type MediaSampleCommand = Media.SampleCommand

export type WaitOps = Wait.Ops
export type WaitProbe = Wait.Probe
export type WaitSpec = Wait.Spec
export type WaitResult = Wait.Result

export type LifecycleReturned = Lifecycle.Returned
export type LifecycleStep = Lifecycle.Step
export type LifecycleCheckpoint = Lifecycle.Checkpoint
export type LifecycleFailure = Lifecycle.Failure
export type LifecycleOutcome = Lifecycle.Outcome
export type LifecycleRecord = Lifecycle.Record
export type LifecycleOps<H = unknown> = Lifecycle.Ops<H>
export type LifecycleHandle = Lifecycle.Handle
export type LifecycleBody = Lifecycle.Body
export type LifecycleSpec = Lifecycle.Spec
export type LifecycleResult = Lifecycle.Result
export type LifecycleRun<H = unknown> = Lifecycle.Run<H>
export type LifecycleBatch = Lifecycle.Batch

export type Negotiation = Capability.Negotiation
export type Bundle = Observation.Bundle
export type BundleDraft = Observation.Draft
export type BundleVerdict = Observation.Verdict
export type Session<S = { [string]: unknown }> = SessionModule.Session<S>
export type SessionOptions<S = { [string]: unknown }> = SessionModule.Options<S>
export type SessionProvidedOptions<S> = SessionModule.ProvidedOptions<S>
export type TransportRecord = Transport.Record
export type Segment = Transport.Segment

export type ClassifyConsoleOptions = Witness.ClassifyOptions

return {
	experience = Experience,
	performance = Performance,
	SCHEMA_VERSION = ReportModel.SCHEMA_VERSION,
	MANIFEST_SCHEMA_VERSION = Manifest.SCHEMA_VERSION,
	PLAN_SCHEMA_VERSION = Plan.SCHEMA_VERSION,
	EXECUTION_SCHEMA_VERSION = Execution.SCHEMA_VERSION,
	OBSERVATION_CONTRACT = Observation.CONTRACT,
	TIMING_FIELDS = ReportModel.TIMING_FIELDS,

	createHarness = HarnessModule.createHarness,
	syntheticReport = HarnessModule.syntheticReport,
	format = HarnessModule.format,
	expect = Matchers.expect,
	float32 = Matchers.float32,
	spy = Spy.on,

	validateManifest = Manifest.validate,

	validatePlan = Plan.validate,
	selectPlan = Plan.select,
	partitionPlan = Plan.partition,
	planDigest = Plan.digest,
	planFromManifest = Plan.fromManifest,
	caseId = Plan.caseId,

	negotiate = Capability.negotiate,
	explainCapabilities = Capability.explain,

	execute = Execution.execute,
	accountPlan = Execution.account,
	createSession = SessionModule.create,
	runLifecycle = Lifecycle.run,
	runConcurrentLifecycles = Lifecycle.runConcurrent,
	lifecycleFailures = Lifecycle.failures,
	attachLifecycle = Lifecycle.attach,
	waitUntil = Wait.waitUntil,
	mediaAudioWindow = Media.audioWindow,
	mediaProbeSummary = Media.probeSummary,
	mediaAudioMeasurement = Media.audioMeasurement,
	mediaSampleCommands = Media.sampleCommands,
	actorNames = Actors.names,
	runActors = Actors.run,

	sealObservations = Observation.seal,
	isSealedBundle = Observation.isSealed,
	evaluateObservations = Observation.evaluate,
	observationVerdict = Observation.verdict,
	observationStringMap = Observation.stringMap,

	frame = Transport.frame,
	extract = Transport.extract,
	reassemble = Transport.reassemble,
	receipt = Transport.receipt,
	segment = Transport.segment,
	reassembleSegments = Transport.reassembleSegments,

	finite = Shape.finite,
	finiteNonnegative = Shape.finiteNonnegative,
	nonnegativeInteger = Shape.nonnegativeInteger,
	denseRows = Shape.denseRows,
	deeplyFinite = Shape.deeplyFinite,
	safeId = Shape.safeId,
	nonempty = Shape.nonempty,
	exact = Shape.exact,
	exactKeys = Shape.exactKeys,
	hasOnlyFields = Shape.hasOnlyFields,
	decode = ReportModel.decode,
	merge = ReportModel.merge,
	compose = ReportModel.compose,
	canonical = ReportModel.canonical,
	verdictDigest = ReportModel.verdictDigest,
	verdictDifferences = ReportModel.verdictDifferences,

	DEFAULT_WITNESS_ERROR_PATTERNS = Witness.DEFAULT_ERROR_PATTERNS,
	DEFAULT_WITNESS_BLOCK_BEGIN_PATTERNS = Witness.DEFAULT_BLOCK_BEGIN_PATTERNS,
	DEFAULT_WITNESS_BLOCK_END_PATTERNS = Witness.DEFAULT_BLOCK_END_PATTERNS,
	classifyConsole = Witness.classifyConsole,
	classifyConsoleText = Witness.classifyConsoleText,
	splitConsoleLines = Witness.splitConsoleLines,
}
