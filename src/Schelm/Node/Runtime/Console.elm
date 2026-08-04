effect module Schelm.Node.Runtime.Console where { command = ConsoleCmd } exposing (Console, Text, TextError(..), WriteError(..), line, stderr, stdout, text, textBytes, textString, write)

import Elm.Kernel.SchelmRuntime
import Platform
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
        Ok
            (Text (value ++ "\n") (width + 1))


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


type State msg
    = State (Maybe msg)


type SelfMsg
    = None


type alias Router msg =
    Platform.Router msg SelfMsg


init =
    Task.succeed (State Nothing)


onEffects router commands state =
    let
        accepted =
            List.take 256 commands

        bytes =
            List.sum (List.map (\(Write _ value _) -> textBytes value) accepted)
    in
    if List.length commands > 256 then
        run router (List.take 256 commands) state
            |> Task.andThen (\next -> reject router TooManyWrites (List.drop 256 commands) next)

    else if bytes > 1048576 then
        reject router BackpressureLimit commands state

    else
        run router accepted state


run router commands state =
    case commands of
        [] ->
            Task.succeed state

        (Write (Console endpoint) value callback) :: rest ->
            Elm.Kernel.SchelmRuntime.write endpoint (textString value)
                |> Task.andThen (\outcome -> Platform.sendToApp router (callback (decode outcome)))
                |> Task.andThen (\_ -> run router rest state)


reject router problem commands state =
    case commands of
        [] ->
            Task.succeed state

        (Write _ _ callback) :: rest ->
            Platform.sendToApp router (callback (Err problem)) |> Task.andThen (\_ -> reject router problem rest state)


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


onSelfMsg _ _ state =
    Task.succeed state
