effect module Schelm.Node.Runtime.Signal where { subscription = SignalSub } exposing (Event(..), Signal(..), onSignal)

import Elm.Kernel.SchelmRuntime
import Platform
import Process
import Schelm.Node.Runtime exposing (Runtime)
import Task exposing (Task)


type Signal
    = Interrupt
    | Terminate


type Event
    = Received Signal
    | SubscriberLimit Signal


onSignal _ signal tagger =
    subscription (Listen signal tagger)


type SignalSub msg
    = Listen Signal (Event -> msg)


subMap f (Listen signal tagger) =
    Listen signal (tagger >> f)


type alias Slot msg =
    { generation : Int, taggers : List (Event -> msg), rejected : Int, listener : Maybe Process.Id }


type alias State msg =
    { interrupt : Slot msg, terminate : Slot msg }


type SelfMsg
    = Fired Signal Int


type alias Router msg =
    Platform.Router msg SelfMsg


empty =
    { generation = 0, taggers = [], rejected = 0, listener = Nothing }


init =
    Task.succeed { interrupt = empty, terminate = empty }


onEffects router subs state =
    sync router Interrupt (collect Interrupt subs) state |> Task.andThen (sync router Terminate (collect Terminate subs))


collect wanted subs =
    List.foldr
        (\(Listen signal tagger) acc ->
            if signal == wanted then
                tagger :: acc

            else
                acc
        )
        []
        subs


sync router signal taggers state =
    let
        old =
            get signal state

        accepted =
            List.take 200 taggers

        rejected =
            List.drop 200 taggers

        rejectedCount =
            List.length rejected

        newlyRejected =
            List.drop old.rejected rejected

        notifyLimit next =
            List.foldl
                (\tagger task -> task |> Task.andThen (\_ -> Platform.sendToApp router (tagger (SubscriberLimit signal))))
                (Task.succeed ())
                newlyRejected
                |> Task.map (\_ -> next)
    in
    case ( accepted, old.listener ) of
        ( [], Just pid ) ->
            Process.kill pid
                |> Task.andThen (\_ -> notifyLimit (set signal { old | generation = old.generation + 1, taggers = [], rejected = rejectedCount, listener = Nothing } state))

        ( [], Nothing ) ->
            notifyLimit (set signal { old | taggers = [], rejected = rejectedCount } state)

        ( _ :: _, Nothing ) ->
            let
                generation =
                    old.generation + 1
            in
            Elm.Kernel.SchelmRuntime.attachSignal (signalInt signal) (\_ -> Platform.sendToSelf router (Fired signal generation))
                |> Process.spawn
                |> Task.andThen (\pid -> notifyLimit (set signal { generation = generation, taggers = accepted, rejected = rejectedCount, listener = Just pid } state))

        ( _ :: _, Just _ ) ->
            notifyLimit (set signal { old | taggers = accepted, rejected = rejectedCount } state)


onSelfMsg router (Fired signal generation) state =
    let
        slot =
            get signal state
    in
    if slot.generation /= generation then
        Task.succeed state

    else
        List.foldl (\tagger task -> task |> Task.andThen (\_ -> Platform.sendToApp router (tagger (Received signal)))) (Task.succeed ()) slot.taggers |> Task.map (\_ -> state)


get signal state =
    if signal == Interrupt then
        state.interrupt

    else
        state.terminate


set signal slot state =
    if signal == Interrupt then
        { state | interrupt = slot }

    else
        { state | terminate = slot }


signalInt signal =
    if signal == Interrupt then
        0

    else
        1
