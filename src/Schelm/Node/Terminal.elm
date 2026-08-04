effect module Schelm.Node.Terminal where { command = TerminalCmd, subscription = TerminalSub } exposing
    ( AcquireError(..)
    , ColorSupport(..)
    , Configuration
    , ControlError(..)
    , InputError(..)
    , InputPiece
    , InputReader
    , RawMode(..)
    , ReaderError(..)
    , ResizeEvent(..)
    , Size
    , Terminal
    , acquire
    , closeInput
    , configuration
    , inputBytes
    , inputHadMalformedUtf8
    , inputText
    , onResize
    , openInput
    , read
    , recover
    , release
    , setRawMode
    )

import Elm.Kernel.SchelmRuntime
import Platform
import Process
import Schelm.Node.Runtime exposing (Runtime)
import Task exposing (Task)


type Terminal
    = Terminal Int Configuration


type alias Configuration =
    { size : Size, colorSupport : ColorSupport }


type alias Size =
    { columns : Int, rows : Int }


type ColorSupport
    = NoColor
    | BasicColor
    | Color256
    | TrueColor


type AcquireError
    = NotInteractive
    | Busy
    | RestoreFailed
    | TooManyAcquireJoiners
    | AcquireFailed


type RawMode
    = Cooked
    | Raw


type ControlError
    = Released
    | RestoreFailedControl
    | TooManyControlJoiners
    | RawModeUnsupported
    | ControlFailed


type InputReader
    = InputReader Int


type ReaderError
    = ReaderBusy
    | ReaderReleased
    | RestoreFailedReader
    | ReaderOpenFailed


type InputPiece
    = InputPiece String Int Bool


type InputError
    = InputEnded Bool
    | InputReadInProgress
    | ReaderClosed
    | InputFailed


type ResizeEvent
    = Resized Size
    | ResizeSubscriberLimit


acquire runtime callback =
    command (Acquire runtime callback)


configuration (Terminal _ config) =
    config


setRawMode terminal mode callback =
    command (SetRaw terminal mode callback)


release terminal callback =
    command (Release terminal callback)


recover runtime callback =
    command (Recover runtime callback)


openInput terminal callback =
    command (OpenInput terminal callback)


closeInput reader =
    command (CloseInput reader)


read reader callback =
    command (Read reader callback)


inputText (InputPiece value _ _) =
    value


inputBytes (InputPiece _ width _) =
    width


inputHadMalformedUtf8 (InputPiece _ _ malformed) =
    malformed


onResize terminal tagger =
    subscription (Resize terminal tagger)


type TerminalCmd msg
    = Acquire Runtime (Result AcquireError Terminal -> msg)
    | SetRaw Terminal RawMode (Result ControlError () -> msg)
    | Release Terminal (Result ControlError () -> msg)
    | Recover Runtime (Result ControlError () -> msg)
    | OpenInput Terminal (Result ReaderError InputReader -> msg)
    | CloseInput InputReader
    | Read InputReader (Result InputError InputPiece -> msg)


cmdMap f cmd =
    case cmd of
        Acquire runtime cb ->
            Acquire runtime (cb >> f)

        SetRaw terminal mode cb ->
            SetRaw terminal mode (cb >> f)

        Release terminal cb ->
            Release terminal (cb >> f)

        Recover runtime cb ->
            Recover runtime (cb >> f)

        OpenInput terminal cb ->
            OpenInput terminal (cb >> f)

        CloseInput reader ->
            CloseInput reader

        Read reader cb ->
            Read reader (cb >> f)


type TerminalSub msg
    = Resize Terminal (ResizeEvent -> msg)


subMap f (Resize terminal tagger) =
    Resize terminal (tagger >> f)


type alias State msg =
    { terminal : Maybe Terminal
    , reader : Maybe InputReader
    , reading : Maybe ( Int, Process.Id )
    , nextRead : Int
    , resizeTaggers : List (ResizeEvent -> msg)
    , resizeListener : Maybe Process.Id
    }


type SelfMsg msg
    = ReadDone Int (Result InputError InputPiece -> msg) (Result InputError InputPiece)


type alias Router msg =
    Platform.Router msg (SelfMsg msg)


init =
    Task.succeed { terminal = Nothing, reader = Nothing, reading = Nothing, nextRead = 0, resizeTaggers = [], resizeListener = Nothing }


onEffects router commands subscriptions state =
    applyCommands router commands state |> Task.andThen (syncResize router subscriptions)


applyCommands router commands state =
    case commands of
        [] ->
            Task.succeed state

        command_ :: rest ->
            applyCommand router command_ state |> Task.andThen (applyCommands router rest)


applyCommand router command_ state =
    case command_ of
        Acquire _ callback ->
            Elm.Kernel.SchelmRuntime.acquireTerminal
                |> Task.andThen
                    (\raw ->
                        case raw.kind of
                            "ok" ->
                                let
                                    terminal =
                                        Terminal raw.id { size = { columns = raw.columns, rows = raw.rows }, colorSupport = color raw.depth }
                                in
                                send router callback (Ok terminal) { state | terminal = Just terminal }

                            "not" ->
                                send router callback (Err NotInteractive) state

                            "busy" ->
                                send router callback (Err Busy) state

                            "restore" ->
                                send router callback (Err RestoreFailed) state

                            _ ->
                                send router callback (Err AcquireFailed) state
                    )

        SetRaw (Terminal id _) mode callback ->
            Elm.Kernel.SchelmRuntime.setRaw id (mode == Raw) |> Task.andThen (\outcome -> send router callback (control outcome) state)

        Release (Terminal id _) callback ->
            cancelRead state
                |> Task.andThen
                    (\cancelled ->
                        Elm.Kernel.SchelmRuntime.release id
                            |> Task.andThen
                                (\outcome ->
                                    let
                                        next =
                                            if outcome == "ok" then
                                                { cancelled | terminal = Nothing, reader = Nothing }

                                            else
                                                cancelled
                                    in
                                    send router callback (control outcome) next
                                )
                    )

        Recover _ callback ->
            Elm.Kernel.SchelmRuntime.recover |> Task.andThen (\outcome -> send router callback (control outcome) state)

        OpenInput ((Terminal id _) as terminal) callback ->
            if state.terminal /= Just terminal then
                send router callback (Err ReaderReleased) state

            else
                case state.reader of
                    Just _ ->
                        send router callback (Err ReaderBusy) state

                    Nothing ->
                        let
                            reader =
                                InputReader id
                        in
                        send router callback (Ok reader) { state | reader = Just reader }

        CloseInput reader ->
            if state.reader /= Just reader then
                Task.succeed state

            else
                case state.reading of
                    Nothing ->
                        Task.succeed { state | reader = Nothing }

                    Just ( _, pid ) ->
                        Process.kill pid |> Task.map (\_ -> { state | reader = Nothing, reading = Nothing, nextRead = state.nextRead + 1 })

        Read ((InputReader id) as reader) callback ->
            if state.reader /= Just reader then
                send router callback (Err ReaderClosed) state

            else
                case state.reading of
                    Just _ ->
                        send router callback (Err InputReadInProgress) state

                    Nothing ->
                        let
                            readId =
                                state.nextRead
                        in
                        Elm.Kernel.SchelmRuntime.read id
                            |> Task.andThen
                                (\raw ->
                                    let
                                        result =
                                            case raw.kind of
                                                "piece" ->
                                                    Ok (InputPiece raw.text raw.bytes raw.malformed)

                                                "end" ->
                                                    Err (InputEnded raw.malformed)

                                                "closed" ->
                                                    Err ReaderClosed

                                                _ ->
                                                    Err InputFailed
                                    in
                                    Platform.sendToSelf router (ReadDone readId callback result)
                                )
                            |> Process.spawn
                            |> Task.map (\pid -> { state | reading = Just ( readId, pid ) })


send router callback result state =
    Platform.sendToApp router (callback result) |> Task.map (\_ -> state)


control outcome =
    case outcome of
        "ok" ->
            Ok ()

        "released" ->
            Err Released

        "restore" ->
            Err RestoreFailedControl

        _ ->
            Err ControlFailed


syncResize router subscriptions state =
    let
        taggers =
            List.take 200 (List.map (\(Resize _ tagger) -> tagger) subscriptions)
    in
    case ( taggers, state.resizeListener ) of
        ( [], Just pid ) ->
            Process.kill pid |> Task.map (\_ -> { state | resizeTaggers = [], resizeListener = Nothing })

        ( [], Nothing ) ->
            Task.succeed { state | resizeTaggers = [] }

        ( _ :: _, Just _ ) ->
            Task.succeed { state | resizeTaggers = taggers }

        ( _ :: _, Nothing ) ->
            Elm.Kernel.SchelmRuntime.attachResize
                (\size -> List.foldr (\tagger task -> Platform.sendToApp router (tagger (Resized size)) |> Task.andThen (\_ -> task)) (Task.succeed ()) taggers)
                |> Process.spawn
                |> Task.map (\pid -> { state | resizeTaggers = taggers, resizeListener = Just pid })


onSelfMsg router (ReadDone readId callback result) state =
    case state.reading of
        Just ( current, _ ) ->
            if current == readId then
                Platform.sendToApp router (callback result)
                    |> Task.map (\_ -> { state | reading = Nothing, nextRead = state.nextRead + 1 })

            else
                Task.succeed state

        Nothing ->
            Task.succeed state


cancelRead state =
    case state.reading of
        Nothing ->
            Task.succeed state

        Just ( _, pid ) ->
            Process.kill pid
                |> Task.map (\_ -> { state | reading = Nothing, nextRead = state.nextRead + 1 })


color depth =
    if depth >= 24 then
        TrueColor

    else if depth >= 8 then
        Color256

    else if depth > 0 then
        BasicColor

    else
        NoColor
