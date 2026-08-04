effect module Feasibility.Runtime where { command = MyCmd, subscription = MySub } exposing
    ( Snapshot, snapshot, write, exitStandalone, onProbe )

{-| Disposable runtime/compiler feasibility surface. Not production API. -}

import Elm.Kernel.RuntimeFeasibility
import Platform
import Process
import Task exposing (Task)


type alias Snapshot =
    { nowMs : Float
    , randomHex : String
    , envPresent : Bool
    , isTty : Bool
    , columns : Int
    , rows : Int
    }


snapshot : Task Never Snapshot
snapshot =
    Elm.Kernel.RuntimeFeasibility.snapshot


write : String -> (Bool -> msg) -> Cmd msg
write text toMsg =
    command (Write text toMsg)


exitStandalone : Int -> Cmd msg
exitStandalone code =
    command (ExitStandalone code)


onProbe : (String -> msg) -> Sub msg
onProbe toMsg =
    subscription (OnProbe toMsg)


type MyCmd msg
    = Write String (Bool -> msg)
    | ExitStandalone Int


cmdMap : (a -> b) -> MyCmd a -> MyCmd b
cmdMap map cmd =
    case cmd of
        Write text toMsg ->
            Write text (toMsg >> map)

        ExitStandalone code ->
            ExitStandalone code


type MySub msg
    = OnProbe (String -> msg)


subMap : (a -> b) -> MySub a -> MySub b
subMap map (OnProbe toMsg) =
    OnProbe (toMsg >> map)


type alias State msg =
    { probeTaggers : List (String -> msg)
    , probeListener : Maybe Process.Id
    }


type SelfMsg
    = Probed String


type alias Router msg =
    Platform.Router msg SelfMsg


init : Task Never (State msg)
init =
    Task.succeed { probeTaggers = [], probeListener = Nothing }


onEffects : Router msg -> List (MyCmd msg) -> List (MySub msg) -> State msg -> Task Never (State msg)
onEffects router commands subscriptions state =
    syncSubscriptions router subscriptions state
        |> Task.andThen (runCommands router commands)


runCommands : Router msg -> List (MyCmd msg) -> State msg -> Task Never (State msg)
runCommands router commands state =
    case commands of
        [] ->
            Task.succeed state

        cmd :: rest ->
            runCommand router cmd
                |> Task.andThen (\_ -> runCommands router rest state)


runCommand : Router msg -> MyCmd msg -> Task Never ()
runCommand router cmd =
    case cmd of
        Write text toMsg ->
            Elm.Kernel.RuntimeFeasibility.write text
                |> Task.andThen (toMsg >> Platform.sendToApp router)

        ExitStandalone code ->
            Elm.Kernel.RuntimeFeasibility.exit code


syncSubscriptions : Router msg -> List (MySub msg) -> State msg -> Task Never (State msg)
syncSubscriptions router subscriptions state =
    let
        taggers =
            List.map (\(OnProbe tagger) -> tagger) subscriptions
    in
    case ( taggers, state.probeListener ) of
        ( [], Just pid ) ->
            Process.kill pid
                |> Task.map (\_ -> { probeTaggers = [], probeListener = Nothing })

        ( [], Nothing ) ->
            Task.succeed { probeTaggers = [], probeListener = Nothing }

        ( _ :: _, Nothing ) ->
            Elm.Kernel.RuntimeFeasibility.listen (Probed >> Platform.sendToSelf router)
                |> Process.spawn
                |> Task.map (\pid -> { probeTaggers = taggers, probeListener = Just pid })

        ( _ :: _, Just pid ) ->
            Task.succeed { probeTaggers = taggers, probeListener = Just pid }


onSelfMsg : Router msg -> SelfMsg -> State msg -> Task Never (State msg)
onSelfMsg router selfMsg state =
    case selfMsg of
        Probed value ->
            state.probeTaggers
                |> List.foldl
                    (\tagger task -> task |> Task.andThen (\_ -> Platform.sendToApp router (tagger value)))
                    (Task.succeed ())
                |> Task.map (\_ -> state)
