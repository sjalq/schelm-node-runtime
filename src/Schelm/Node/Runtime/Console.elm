effect module Schelm.Node.Runtime.Console where { command = ConsoleCmd } exposing (Console, Text, TextError(..), WriteError(..), line, stderr, stdout, text, textBytes, textString, write)

import Dict exposing (Dict)
import Elm.Kernel.SchelmRuntime
import Platform
import Process
import Schelm.Node.Runtime exposing (Runtime)
import Task exposing (Task)


type Console
    = Console Int


type Text
    = Text String Int


type TextError
    = InvalidText
    | WriteTooLarge


type WriteError
    = BackpressureLimit
    | TooManyWrites
    | BrokenPipe
    | Closed
    | InvalidHostState
    | WriteFailed


text value =
    let
        width =
            Elm.Kernel.SchelmRuntime.utf8Width value
    in
    if width < 0 then
        Err InvalidText

    else if width > 65536 then
        Err WriteTooLarge

    else
        Ok (Text value width)


line (Text value width) =
    if width >= 65536 then
        Err WriteTooLarge

    else
        Ok (Text (value ++ "\n") (width + 1))


textString (Text value _) =
    value


textBytes (Text _ width) =
    width


stdout _ =
    Console 0


stderr _ =
    Console 1


write endpoint value callback =
    command (Write endpoint value callback)


type ConsoleCmd msg
    = Write Console Text (Result WriteError () -> msg)


cmdMap f (Write endpoint value callback) =
    Write endpoint value (callback >> f)


type alias Pending msg =
    { id : Int, text : Text, callback : Result WriteError () -> msg }


type alias Endpoint msg =
    { front : List (Pending msg), back : List (Pending msg), count : Int, bytes : Int, inFlight : Maybe (Pending msg), terminal : Maybe WriteError, generation : Int }


type alias State msg =
    { nextId : Int, endpoints : Dict Int (Endpoint msg) }


type SelfMsg
    = WriteDone Int Int Int String


type alias Router msg =
    Platform.Router msg SelfMsg


empty =
    { front = [], back = [], count = 0, bytes = 0, inFlight = Nothing, terminal = Nothing, generation = 0 }


init =
    Task.succeed { nextId = 0, endpoints = Dict.fromList [ ( 0, empty ), ( 1, empty ) ] }


onEffects router commands state =
    applyCommands router commands state


applyCommands router commands state =
    case commands of
        [] ->
            Task.succeed state

        command_ :: rest ->
            applyCommand router command_ state |> Task.andThen (applyCommands router rest)


applyCommand router (Write (Console key) value callback) state =
    let
        endpoint =
            Dict.get key state.endpoints |> Maybe.withDefault empty

        width =
            textBytes value
    in
    case endpoint.terminal of
        Just problem ->
            send router callback (Err problem) state

        Nothing ->
            if endpoint.count >= 256 then
                send router callback (Err TooManyWrites) state

            else if endpoint.bytes + width > 1048576 then
                send router callback (Err BackpressureLimit) state

            else if width == 0 then
                send router callback (Ok ()) state

            else
                let
                    pending =
                        { id = state.nextId, text = value, callback = callback }

                    queued =
                        { endpoint | back = pending :: endpoint.back, count = endpoint.count + 1, bytes = endpoint.bytes + width }

                    next =
                        put key queued { state | nextId = state.nextId + 1 }
                in
                start router key next


start router key state =
    let
        endpoint =
            Dict.get key state.endpoints |> Maybe.withDefault empty
    in
    case endpoint.inFlight of
        Just _ ->
            Task.succeed state

        Nothing ->
            case dequeue endpoint of
                Nothing ->
                    Task.succeed state

                Just ( pending, remaining ) ->
                    let
                        generation =
                            endpoint.generation

                        running =
                            { remaining | inFlight = Just pending }
                    in
                    Elm.Kernel.SchelmRuntime.write key (textString pending.text)
                        |> Task.andThen (\outcome -> Platform.sendToSelf router (WriteDone key generation pending.id outcome))
                        |> Process.spawn
                        |> Task.map (\_ -> put key running state)


onSelfMsg router (WriteDone key generation id outcome) state =
    let
        endpoint =
            Dict.get key state.endpoints |> Maybe.withDefault empty
    in
    case endpoint.inFlight of
        Just pending ->
            if endpoint.generation /= generation || pending.id /= id then
                Task.succeed state

            else
                let
                    problem =
                        decode outcome

                    terminal =
                        case problem of
                            Err BrokenPipe ->
                                Just BrokenPipe

                            Err Closed ->
                                Just Closed

                            _ ->
                                endpoint.terminal

                    cleared =
                        { endpoint | inFlight = Nothing, count = endpoint.count - 1, bytes = endpoint.bytes - textBytes pending.text, terminal = terminal }

                    next =
                        put key cleared state
                in
                send router pending.callback problem next |> Task.andThen (start router key)

        Nothing ->
            Task.succeed state


dequeue endpoint =
    case endpoint.front of
        item :: rest ->
            Just ( item, { endpoint | front = rest } )

        [] ->
            case List.reverse endpoint.back of
                [] ->
                    Nothing

                item :: rest ->
                    Just ( item, { endpoint | front = rest, back = [] } )


put key endpoint state =
    { state | endpoints = Dict.insert key endpoint state.endpoints }


send router callback result state =
    Platform.sendToApp router (callback result) |> Task.map (\_ -> state)


decode outcome =
    case outcome of
        "ok" ->
            Ok ()

        "pipe" ->
            Err BrokenPipe

        "closed" ->
            Err Closed

        _ ->
            Err WriteFailed
