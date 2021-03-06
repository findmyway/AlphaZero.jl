"""
Analytical reports generated during training, for debugging and
hyperparameters tuning.
"""
module Report

# Some imports for docstrings cross-references
import ..MCTS, ..Network, ..MemAnalysisParams

"""
    Report.Loss

Decomposition of the loss in a sum of terms (all have type `Float32`).

- `L` is the total loss: `L == Lp + Lv + Lreg + Linv`
- `Lp` is the policy cross-entropy loss term
- `Lv` is the average value mean square error
- `Lreg` is the L2 regularization loss term
- `Linv` is the loss term penalizing the average weight put by the
  network on invalid actions
"""
struct Loss
  L :: Float32
  Lp :: Float32
  Lv :: Float32
  Lreg :: Float32
  Linv :: Float32
end

"""
    Report.LearningStatus

Statistics about the performance of the neural network on a subset of the
memory buffer.

- `loss`: detailed loss on the samples, as an object of type
    [`Report.Loss`](@ref)
- `Hp`: average entropy of the ``π`` component of samples (MCTS policy);
    this quantity is independent of the network and therefore constant
    during a learning iteration
- `Hpnet`: average entropy of the network's prescribed policy on the samples
"""
struct LearningStatus
  loss :: Loss
  Hp :: Float32 # property of the memory, constant during a learning iteration
  Hpnet :: Float32
end

"""
    Report.Checkpoint

Report generated after a checkpoint evaluation.

- `batch_id`: number of batches after which the checkpoint was computed
- `status_after`: learning status at the checkpoint, as an object of type
   [`Report.LearningStatus`](@ref)
- `reward`: average reward collected by the contender network
- `redundancy`: ratio of duplicate positions encountered during the evaluation,
   not counting the initial position. If this number is too high, you may
   want to increase the move selection temperature.
- `nn_replaced`: true if the current best neural network was updated after
   the checkpoint
"""
struct Checkpoint
  batch_id :: Int
  status_after :: LearningStatus
  reward :: Float64
  redundancy :: Float64
  nn_replaced :: Bool
end

"""
    Report.Learning

Report generated at the end of the learning phase of an iteration.

- `time_convert`, `time_loss`, `time_train` and `time_eval` are the
    amounts of time (in seconds) spent at converting the samples,
    computing losses, performing gradient updates and evaluating checkpoints
    respectively
- `initial_status`: status before the learning phase, as an object of type
    [`Report.LearningStatus`](@ref)
- `losses`: loss value on each minibatch
- `checkpoints`: vector of [`Report.Checkpoint`](@ref) reports
- `nn_replaced`: true if the best neural network was replaced
"""
struct Learning
  time_convert :: Float64
  time_loss :: Float64
  time_train :: Float64
  time_eval :: Float64
  initial_status :: LearningStatus
  losses :: Vector{Float32}
  checkpoints :: Vector{Checkpoint}
  nn_replaced :: Bool
end

"""
    Report.Samples

Statistics about a set of samples, as collected during memory analysis.

- `num_samples`: total number of samples
- `num_boards`: number of distinct board positions
- `Wtot`: total weight of the samples
- `status`: [`Report.LearningStatus`](@ref) statistics of the current network
    on the samples
"""
struct Samples
  num_samples :: Int
  num_boards :: Int
  Wtot :: Float32
  status :: LearningStatus
end

"""
    Report.StageSamples

Statistics for the samples corresponding to a particular game stage,
as collected during memory analysis.

The samples whose statistics are collected in the
[`samples_stats`](@ref Report.Samples) field correspond to historical positions
where the number of remaining moves until the end of the game was in the range
defined by the `min_remaining_length` and `max_remaining_length` fields.
"""
struct StageSamples
  min_remaining_length :: Int
  max_remaining_length :: Int
  samples_stats :: Samples
end

"""
    Report.Memory

Report generated by the memory analysis phase of an iteration. It features
samples statistics for
  - the whole memory buffer (`all_samples :: Report.Samples`)
  - the samples collected during the last self-play iteration
     (`latest_batch :: Report.Samples`)
  - the subsets of the memory buffer corresponding to different game stages:
     (`per_game_stage :: Vector{Report.StageSamples}`)

See [`MemAnalysisParams`](@ref).
"""
struct Memory
  latest_batch :: Samples
  all_samples :: Samples
  per_game_stage :: Vector{StageSamples}
end

"""
    Report.SelfPlay

Report generated after the self-play phase of an iteration.

- `inference_time_ratio`: see [`MCTS.inference_time_ratio`](@ref)
- `samples_gen_speed`: average number of samples generated per second
- `average_exploration_depth`: see [`MCTS.average_exploration_depth`](@ref)
- `mcts_memory_footprint`: estimation of the maximal memory footprint of the
    MCTS tree during self-play, as computed by
    [`MCTS.approximate_memory_footprint`](@ref)
- `memory_size`: number of samples in the memory buffer at the end of the
    self-play phase
- `memory_num_distinct_boards`: number of distinct board positions in the
    memory buffer at the end of the self-play phase
"""
struct SelfPlay
  inference_time_ratio :: Float64
  samples_gen_speed :: Float64
  average_exploration_depth :: Float64
  mcts_memory_footprint :: Int
  memory_size :: Int
  memory_num_distinct_boards :: Int
end

"""
    Report.Perfs

Performances report for a subroutine.
- `time`: total time spent, in seconds
- `allocated`: amount of memory allocated, in bytes
- `gc_time`: total amount of time spent in the garbage collector
"""
struct Perfs
  time :: Float64
  allocated :: Int64
  gc_time :: Float64
end

"""
    Report.Iteration

Report generated after each training iteration.
- `perfs_self_play`, `perfs_memory_analysis` and `perfs_learning` are
    performance reports for the different phases of the iteration, as
    objects of type [`Report.Perfs`](@ref)
- `self_play`, `memory`, `learning` have types [`Report.SelfPlay`](@ref),
    [`Report.SelfPlay`](@ref) and [`Report.Learning`](@ref) respectively
"""
struct Iteration
  perfs_self_play :: Perfs
  perfs_memory_analysis :: Perfs
  perfs_learning :: Perfs
  self_play :: SelfPlay
  memory :: Union{Memory, Nothing}
  learning :: Learning
end

"""
    Report.Initial

Report summarizing the configuration of an agent before training starts.
- `num_network_parameters`: see [`Network.num_parameters`](@ref)
- `num_network_regularized_parameters`:
    see [`Network.num_regularized_parameters`](@ref)
- `mcts_footprint_per_node`: see [`MCTS.memory_footprint_per_node`](@ref)
"""
struct Initial
  num_network_parameters :: Int
  num_network_regularized_parameters :: Int
  mcts_footprint_per_node :: Int
end

#####
##### Profiling utilities
#####

macro timed(e)
  quote
    local v, t, mem, gct = Base.@timed $(esc(e))
    v, Perfs(t, mem, gct)
  end
end

#####
##### Printing and plotting
#####

using Formatting
using ..Log

const NUM_COL = Log.ColType(7, x -> fmt(".4f", x))
const BIGINT_COL = Log.ColType(10, n -> format(ceil(Int, n), commas=true))

const LEARNING_STATUS_TABLE = Log.Table([
  ("Loss",   NUM_COL,     s -> s.loss.L),
  ("Lv",     NUM_COL,     s -> s.loss.Lv),
  ("Lp",     NUM_COL,     s -> s.loss.Lp),
  ("Lreg",   NUM_COL,     s -> s.loss.Lreg),
  ("Linv",   NUM_COL,     s -> s.loss.Linv),
  ("Hp",     NUM_COL,     s -> s.Hp),
  ("Hpnet",  NUM_COL,     s -> s.Hpnet)])

const SAMPLES_STATS_TABLE = Log.Table([
  ("Loss",   NUM_COL,     s -> s.status.loss.L),
  ("Lv",     NUM_COL,     s -> s.status.loss.Lv),
  ("Lp",     NUM_COL,     s -> s.status.loss.Lp),
  ("Lreg",   NUM_COL,     s -> s.status.loss.Lreg),
  ("Linv",   NUM_COL,     s -> s.status.loss.Linv),
  ("Hpnet",  NUM_COL,     s -> s.status.Hpnet),
  ("Hp",     NUM_COL,     s -> s.status.Hp),
  ("Wtot",   BIGINT_COL,  s -> s.Wtot),
  ("Nb",     BIGINT_COL,  s -> s.num_boards),
  ("Ns",     BIGINT_COL,  s -> s.num_samples)])

function print(logger::Logger, status::Report.LearningStatus; kw...)
  Log.table_row(logger, LEARNING_STATUS_TABLE, status; kw...)
end

function print(logger::Logger, stats::Report.Memory)
  content, styles, comments = [], [], []
  # All samples
  push!(content, stats.all_samples)
  push!(styles, Log.BOLD)
  push!(comments, ["all samples"])
  # Latest batch
  push!(content, stats.latest_batch)
  push!(styles, Log.BOLD)
  push!(comments, ["latest batch"])
  # Per game stage
  for stage in stats.per_game_stage
    minrem = stage.min_remaining_length
    maxrem = stage.max_remaining_length
    push!(content, stage.samples_stats)
    push!(styles, Log.NO_STYLE)
    push!(comments, ["$minrem to $maxrem turns left"])
  end
  Log.table(
    logger, SAMPLES_STATS_TABLE, content, styles=styles, comments=comments)
end

function print(logger::Logger, report::SelfPlay)
  t = round(Int, 100 * report.inference_time_ratio)
  Log.print(logger, "Time spent on inference: $(t)%")
  sspeed = format(round(Int, report.samples_gen_speed), commas=true)
  Log.print(logger, "Generating $(sspeed) samples per second on average")
  avgdepth = fmt(".1f", report.average_exploration_depth)
  Log.print(logger, "Average exploration depth: $avgdepth")
  memf = format(report.mcts_memory_footprint, autoscale=:metric, precision=2)
  Log.print(logger, "MCTS memory footprint: $(memf)B")
  mems = format(report.memory_size, commas=true)
  memd = format(report.memory_num_distinct_boards, commas=true)
  Log.print(logger, "Experience buffer size: $(mems) ($(memd) distinct boards)")
end

function print(logger::Logger, report::Initial)
  nnparams = format(report.num_network_parameters, commas=true)
  Log.print(logger, "Number of network parameters: $nnparams")
  nnregparams = format(report.num_network_regularized_parameters, commas=true)
  Log.print(logger, "Number of regularized network parameters: $nnregparams")
  mfpn = report.mcts_footprint_per_node
  Log.print(logger, "Memory footprint per MCTS node: $(mfpn) bytes")
end

end
