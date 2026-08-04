effect module Schelm.Node.Runtime.Console where { command = ConsoleCmd } exposing (Console, Text, TextError(..), WriteError(..), line, stderr, stdout, text, textBytes, textString, write)

import Platform
import Schelm.Node.Runtime exposing (Runtime)
import Task exposing (Task)


type Console
    = Stdout
    | Stderr


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
    if String.length value > 65536 then
        Err WriteTooLarge

    else
        Ok (Text value (String.length value))


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
    Stdout


stderr _ =
    Stderr


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


init =
    Task.succeed (State Nothing)


onEffects _ _ state =
    Task.succeed state


onSelfMsg _ _ state =
    Task.succeed state
