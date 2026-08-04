module Schelm.Node.Runtime.Clock exposing
    ( Deadline
    , Elapsed
    , MonotonicTime
    , TimerDuration
    , TimerDurationError(..)
    , WallTime
    , deadlineAfter
    , deadlineReached
    , elapsed
    , elapsedMilliseconds
    , monotonicNow
    , remaining
    , timerDuration
    , timerMilliseconds
    , wallNow
    )

import Schelm.Node.Runtime exposing (Runtime)
import Task exposing (Task)


type WallTime
    = WallTime Int


type MonotonicTime
    = MonotonicTime Float


type Elapsed
    = Elapsed Float


type TimerDuration
    = TimerDuration Int


type TimerDurationError
    = TimerDurationTooShort
    | TimerDurationTooLong


type Deadline
    = Deadline Float


wallNow _ =
    Task.succeed (WallTime 0)


monotonicNow _ =
    Task.succeed (MonotonicTime 0)


elapsed (MonotonicTime a) (MonotonicTime b) =
    Elapsed (max 0 (b - a))


elapsedMilliseconds (Elapsed n) =
    n


timerDuration n =
    if n < 10 then
        Err TimerDurationTooShort

    else if n > 86400000 then
        Err TimerDurationTooLong

    else
        Ok (TimerDuration n)


timerMilliseconds (TimerDuration n) =
    n


deadlineAfter (MonotonicTime n) (TimerDuration d) =
    Deadline (n + toFloat d)


deadlineReached (MonotonicTime n) (Deadline d) =
    n >= d


remaining (MonotonicTime n) (Deadline d) =
    Elapsed (max 0 (d - n))
