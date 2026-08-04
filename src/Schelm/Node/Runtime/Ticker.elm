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

import Dict exposing (Dict)
import Elm.Kernel.SchelmRuntime
import Platform
import Process
import Schelm.Node.Runtime exposing (Runtime)
import Schelm.Node.Runtime.Clock as Clock exposing (Elapsed, TimerDuration)
import Schelm.Node.Runtime.InternalClock exposing (Elapsed(..), MonotonicTime(..))
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


type alias Active msg =
    { interval : Int, target : Float, previous : Float, taggers : List (Tick -> msg) }


type alias State msg =
    { next : Int, generation : Int, active : Dict Int (Active msg), timer : Maybe Process.Id }


type SelfMsg
    = Woke Int Int Float


type alias Router msg =
    Platform.Router msg SelfMsg


init =
    Task.succeed { next = 0, generation = 0, active = Dict.empty, timer = Nothing }


onEffects router commands subscriptions state =
    let
        ( starts, others ) =
            splitStarts commands
    in
    cancelTimer state
        |> Task.andThen (applyCommands router others)
        |> Task.andThen (applyStarts router starts)
        |> Task.map (withTaggers subscriptions)
        |> Task.andThen (arm router)


cancelTimer state =
    case state.timer of
        Nothing ->
            Task.succeed state

        Just pid ->
            Process.kill pid |> Task.map (\_ -> { state | timer = Nothing, generation = state.generation + 1 })


splitStarts commands =
    let
        step command_ ( starts, others ) =
            case command_ of
                Start runtime duration callback ->
                    ( ( runtime, duration, callback ) :: starts, others )

                _ ->
                    ( starts, command_ :: others )

        ( starts, others ) =
            List.foldl step ( [], [] ) commands
    in
    ( List.reverse starts, List.reverse others )


applyStarts router starts state =
    case starts of
        [] ->
            Task.succeed state

        ( runtime, duration, callback ) :: rest ->
            let
                same =
                    List.filter (\( _, candidate, _ ) -> Clock.timerMilliseconds candidate == Clock.timerMilliseconds duration) rest

                different =
                    List.filter (\( _, candidate, _ ) -> Clock.timerMilliseconds candidate /= Clock.timerMilliseconds duration) rest

                accepted =
                    List.take 63 same

                rejected =
                    List.drop 63 same
            in
            applyStart router runtime duration (callback :: List.map (\( _, _, cb ) -> cb) accepted) state
                |> Task.andThen (sendStartErrors router (List.map (\( _, _, cb ) -> cb) rejected) TooManyStartJoiners)
                |> Task.andThen (applyStarts router different)


applyStart router runtime duration callbacks state =
    if Dict.size state.active >= 64 then
        sendStartErrors router callbacks TooManyTickers state

    else
        Clock.monotonicNow runtime
            |> Task.andThen
                (\(MonotonicTime now) ->
                    let
                        id =
                            state.next

                        interval =
                            Clock.timerMilliseconds duration

                        active =
                            { interval = interval, target = now + toFloat interval, previous = now, taggers = [] }

                        next =
                            { state | next = id + 1, active = Dict.insert id active state.active }
                    in
                    sendStartSuccess router callbacks (Ticker id) next
                )


sendStartSuccess router callbacks ticker state =
    case callbacks of
        [] ->
            Task.succeed state

        callback :: rest ->
            Platform.sendToApp router (callback (Ok ticker))
                |> Task.andThen (\_ -> sendStartSuccess router rest ticker state)


sendStartErrors router callbacks problem state =
    case callbacks of
        [] ->
            Task.succeed state

        callback :: rest ->
            Platform.sendToApp router (callback (Err problem))
                |> Task.andThen (\_ -> sendStartErrors router rest problem state)


applyCommands router commands state =
    case commands of
        [] ->
            Task.succeed state

        command_ :: rest ->
            applyCommand router command_ state |> Task.andThen (applyCommands router rest)


applyCommand router command_ state =
    case command_ of
        Stop (Ticker id) ->
            Task.succeed { state | active = Dict.remove id state.active }

        Start runtime duration callback ->
            if Dict.size state.active >= 64 then
                Platform.sendToApp router (callback (Err TooManyTickers)) |> Task.map (\_ -> state)

            else
                Clock.monotonicNow runtime
                    |> Task.andThen
                        (\(MonotonicTime now) ->
                            let
                                id =
                                    state.next

                                interval =
                                    Clock.timerMilliseconds duration

                                active =
                                    { interval = interval, target = now + toFloat interval, previous = now, taggers = [] }

                                next =
                                    { state | next = id + 1, active = Dict.insert id active state.active }
                            in
                            Platform.sendToApp router (callback (Ok (Ticker id))) |> Task.map (\_ -> next)
                        )


withTaggers subscriptions state =
    let
        cleared =
            Dict.map (\_ active -> { active | taggers = [] }) state.active

        add (Listen (Ticker id) tagger) dict =
            Dict.update id (Maybe.map (\active -> { active | taggers = List.take 200 (tagger :: active.taggers) })) dict
    in
    { state | active = List.foldl add cleared subscriptions }


arm router state =
    case earliest state.active of
        Nothing ->
            Task.succeed state

        Just active ->
            let
                generation =
                    state.generation + 1
            in
            Elm.Kernel.SchelmRuntime.delayUntil active.target
                |> Task.andThen (\facts -> Platform.sendToSelf router (Woke generation facts.wall facts.mono))
                |> Process.spawn
                |> Task.map (\pid -> { state | generation = generation, timer = Just pid })


onSelfMsg router (Woke generation wall mono) state =
    if generation /= state.generation then
        Task.succeed state

    else
        let
            updateOne id active ( dict, messages ) =
                if active.target > mono then
                    ( Dict.insert id active dict, messages )

                else
                    let
                        skipped =
                            min 2147483647 (max 0 (floor ((mono - active.target) / toFloat active.interval)))

                        tick =
                            Tick wall mono (Elapsed (max 0 (mono - active.previous))) skipped

                        next =
                            { active | target = active.target + toFloat ((skipped + 1) * active.interval), previous = mono }

                        emitted =
                            List.map (\tagger -> tagger tick) active.taggers
                    in
                    ( Dict.insert id next dict, List.foldl (::) messages emitted )

            ( updated, reversedMessages ) =
                Dict.foldl updateOne ( Dict.empty, [] ) state.active

            nextState =
                { state | active = updated, timer = Nothing }
        in
        List.foldr (\message task -> Platform.sendToApp router message |> Task.andThen (\_ -> task)) (arm router nextState) (List.reverse reversedMessages)


earliest dict =
    Dict.foldl
        (\_ active best ->
            case best of
                Nothing ->
                    Just active

                Just old ->
                    if active.target < old.target then
                        Just active

                    else
                        best
        )
        Nothing
        dict
