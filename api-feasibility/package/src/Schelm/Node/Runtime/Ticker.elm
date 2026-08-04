effect module Schelm.Node.Runtime.Ticker where { command = TickerCmd, subscription = TickerSub } exposing
    ( StartError(..)
    , Tick
    , Ticker
    , onTick
    , skippedIntervals
    , start
    , stop
    , tickElapsed
    , tickMonotonicMilliseconds
    , tickWallMilliseconds
    )

import Platform
import Schelm.Node.Runtime exposing (Runtime)
import Schelm.Node.Runtime.Clock as Clock exposing (Elapsed, TimerDuration)
import Task exposing (Task)


type Ticker
    = Ticker Int


type StartError
    = TooManyTickers
    | TooManyStartJoiners
    | TickerStartFailed


type Tick
    = Tick Int Float Elapsed Int


start runtime duration callback =
    command (Start runtime duration callback)


stop ticker =
    command (Stop ticker)


onTick ticker tagger =
    subscription (Listen ticker tagger)


tickWallMilliseconds (Tick wall _ _ _) =
    wall


tickMonotonicMilliseconds (Tick _ mono _ _) =
    mono


tickElapsed (Tick _ _ value _) =
    value


skippedIntervals (Tick _ _ _ value) =
    value


type TickerCmd msg
    = Start Runtime TimerDuration (Result StartError Ticker -> msg)
    | Stop Ticker


cmdMap f cmd =
    case cmd of
        Start runtime duration callback ->
            Start runtime duration (callback >> f)

        Stop ticker ->
            Stop ticker


type TickerSub msg
    = Listen Ticker (Tick -> msg)


subMap f (Listen ticker tagger) =
    Listen ticker (tagger >> f)


type State msg
    = State (Maybe msg)


type SelfMsg
    = None


init =
    Task.succeed (State Nothing)


onEffects _ _ _ state =
    Task.succeed state


onSelfMsg _ _ state =
    Task.succeed state
