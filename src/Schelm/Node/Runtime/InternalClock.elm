module Schelm.Node.Runtime.InternalClock exposing (Deadline(..), Elapsed(..), MonotonicTime(..), TimerDuration(..), WallTime(..))


type WallTime
    = WallTime Int


type MonotonicTime
    = MonotonicTime Float


type Elapsed
    = Elapsed Float


type TimerDuration
    = TimerDuration Int


type Deadline
    = Deadline Float
