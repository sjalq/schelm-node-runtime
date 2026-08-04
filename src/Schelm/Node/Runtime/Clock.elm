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

import Elm.Kernel.SchelmRuntime
import Schelm.Node.Runtime exposing (Runtime)
import Schelm.Node.Runtime.InternalClock as Internal exposing (Deadline(..), Elapsed(..), MonotonicTime(..), TimerDuration(..), WallTime(..))
import Task exposing (Task)


type alias WallTime =
    Internal.WallTime


type alias MonotonicTime =
    Internal.MonotonicTime


type alias Elapsed =
    Internal.Elapsed


type alias TimerDuration =
    Internal.TimerDuration


type alias Deadline =
    Internal.Deadline


type TimerDurationError
    = TimerDurationTooShort
    | TimerDurationTooLong


wallNow _ =
    Elm.Kernel.SchelmRuntime.wallNow |> Task.map WallTime


monotonicNow _ =
    Elm.Kernel.SchelmRuntime.monotonicNow |> Task.map MonotonicTime


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
    Deadline (min 9007199254740991 (n + toFloat d))


deadlineReached (MonotonicTime n) (Deadline d) =
    n >= d


remaining (MonotonicTime n) (Deadline d) =
    Elapsed (max 0 (d - n))
