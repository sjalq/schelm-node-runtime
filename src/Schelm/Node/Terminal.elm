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
    = InputReader Int Int


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
    , reading : Maybe ( InputReader, Int, Process.Id )
    , nextReader : Int
    , nextRead : Int
    , resizeTaggers : List (ResizeEvent -> msg)
    , resizeRejected : Int
    , resizeListener : Maybe ( Int, Process.Id )
    , nextResize : Int
    }


type SelfMsg msg
    = ReadDone InputReader Int (Result InputError InputPiece -> msg) (Result InputError InputPiece)
    | ResizeDone Int Size


type alias Router msg =
    Platform.Router msg (SelfMsg msg)


init =
    Task.succeed { terminal = Nothing, reader = Nothing, reading = Nothing, nextReader = 0, nextRead = 0, resizeTaggers = [], resizeRejected = 0, resizeListener = Nothing, nextResize = 0 }


onEffects router commands subscriptions state =
    applyCommands router commands state |> Task.andThen (syncResize router subscriptions)


applyCommands router commands state =
    case commands of
        [] ->
            Task.succeed state

        command_ :: rest ->
            case command_ of
                Acquire _ callback ->
                    let
                        ( matching, remaining ) =
                            takeAcquire rest
                    in
                    applyAcquire router (callback :: matching) state
                        |> Task.andThen (applyCommands router remaining)

                SetRaw terminal mode callback ->
                    let
                        ( matching, remaining ) =
                            takeSetRaw terminal mode rest

                        callbacks =
                            callback :: matching
                    in
                    if state.terminal /= Just terminal then
                        sendControlCallbacks router callbacks (Err Released) state
                            |> Task.andThen (applyCommands router remaining)

                    else
                        applyControl router callbacks (Elm.Kernel.SchelmRuntime.setRaw (terminalId terminal) (mode == Raw)) state
                            |> Task.andThen (applyCommands router remaining)

                Release terminal callback ->
                    let
                        ( matching, remaining ) =
                            takeRelease terminal rest

                        callbacks =
                            callback :: matching
                    in
                    if state.terminal /= Just terminal then
                        sendControlCallbacks router callbacks (Err Released) state
                            |> Task.andThen (applyCommands router remaining)

                    else
                        applyRelease router terminal callbacks state
                            |> Task.andThen (applyCommands router remaining)

                Recover _ callback ->
                    let
                        ( matching, remaining ) =
                            takeRecover rest
                    in
                    applyControl router (callback :: matching) Elm.Kernel.SchelmRuntime.recover state
                        |> Task.andThen (applyCommands router remaining)

                _ ->
                    applyCommand router command_ state |> Task.andThen (applyCommands router rest)


takeAcquire commands =
    case commands of
        (Acquire _ callback) :: rest ->
            let
                ( matching, remaining ) =
                    takeAcquire rest
            in
            ( callback :: matching, remaining )

        _ ->
            ( [], commands )


takeSetRaw terminal mode commands =
    case commands of
        (SetRaw candidate candidateMode callback) :: rest ->
            if candidate == terminal && candidateMode == mode then
                let
                    ( matching, remaining ) =
                        takeSetRaw terminal mode rest
                in
                ( callback :: matching, remaining )

            else
                ( [], commands )

        _ ->
            ( [], commands )


takeRelease terminal commands =
    case commands of
        (Release candidate callback) :: rest ->
            if candidate == terminal then
                let
                    ( matching, remaining ) =
                        takeRelease terminal rest
                in
                ( callback :: matching, remaining )

            else
                ( [], commands )

        _ ->
            ( [], commands )


takeRecover commands =
    case commands of
        (Recover _ callback) :: rest ->
            let
                ( matching, remaining ) =
                    takeRecover rest
            in
            ( callback :: matching, remaining )

        _ ->
            ( [], commands )


applyAcquire router callbacks state =
    let
        accepted =
            List.take 64 callbacks

        rejected =
            List.drop 64 callbacks

        finish result next =
            sendAcquireCallbacks router accepted result next
                |> Task.andThen (sendAcquireCallbacks router rejected (Err TooManyAcquireJoiners))
    in
    case state.terminal of
        Just _ ->
            finish (Err Busy) state

        Nothing ->
            Elm.Kernel.SchelmRuntime.acquireTerminal
                |> Task.andThen
                    (\raw ->
                        case raw.kind of
                            "ok" ->
                                let
                                    terminal =
                                        Terminal raw.id { size = { columns = raw.columns, rows = raw.rows }, colorSupport = color raw.depth }
                                in
                                finish (Ok terminal) { state | terminal = Just terminal }

                            "not" ->
                                finish (Err NotInteractive) state

                            "busy" ->
                                finish (Err Busy) state

                            "restore" ->
                                finish (Err RestoreFailed) state

                            _ ->
                                finish (Err AcquireFailed) state
                    )


applyControl router callbacks operation state =
    let
        accepted =
            List.take 64 callbacks

        rejected =
            List.drop 64 callbacks
    in
    operation
        |> Task.andThen
            (\outcome ->
                sendControlCallbacks router accepted (control outcome) state
                    |> Task.andThen (sendControlCallbacks router rejected (Err TooManyControlJoiners))
            )


applyRelease router terminal callbacks state =
    cancelRead state
        |> Task.andThen
            (\cancelled ->
                Elm.Kernel.SchelmRuntime.release (terminalId terminal)
                    |> Task.andThen
                        (\outcome ->
                            let
                                next =
                                    if outcome == "ok" then
                                        { cancelled | terminal = Nothing, reader = Nothing }

                                    else
                                        cancelled
                            in
                            sendControlCallbacks router (List.take 64 callbacks) (control outcome) next
                                |> Task.andThen (sendControlCallbacks router (List.drop 64 callbacks) (Err TooManyControlJoiners))
                        )
            )


sendAcquireCallbacks router callbacks result state =
    case callbacks of
        [] ->
            Task.succeed state

        callback :: rest ->
            send router callback result state |> Task.andThen (sendAcquireCallbacks router rest result)


sendControlCallbacks router callbacks result state =
    case callbacks of
        [] ->
            Task.succeed state

        callback :: rest ->
            send router callback result state |> Task.andThen (sendControlCallbacks router rest result)


terminalId (Terminal id _) =
    id


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

        SetRaw ((Terminal id _) as terminal) mode callback ->
            if state.terminal /= Just terminal then
                send router callback (Err Released) state

            else
                Elm.Kernel.SchelmRuntime.setRaw id (mode == Raw) |> Task.andThen (\outcome -> send router callback (control outcome) state)

        Release ((Terminal id _) as terminal) callback ->
            if state.terminal /= Just terminal then
                send router callback (Err Released) state

            else
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
                                InputReader id state.nextReader
                        in
                        send router callback (Ok reader) { state | reader = Just reader, nextReader = state.nextReader + 1 }

        CloseInput reader ->
            if state.reader /= Just reader then
                Task.succeed state

            else
                case state.reading of
                    Nothing ->
                        Task.succeed { state | reader = Nothing }

                    Just ( activeReader, _, pid ) ->
                        if activeReader /= reader then
                            Task.succeed { state | reader = Nothing }

                        else
                            Process.kill pid |> Task.map (\_ -> { state | reader = Nothing, reading = Nothing, nextRead = state.nextRead + 1 })

        Read ((InputReader id _) as reader) callback ->
            if state.reader /= Just reader then
                Task.succeed state

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
                                    Platform.sendToSelf router (ReadDone reader readId callback result)
                                )
                            |> Process.spawn
                            |> Task.map (\pid -> { state | reading = Just ( reader, readId, pid ) })


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
        currentTaggers =
            case state.terminal of
                Just current ->
                    List.foldr
                        (\(Resize terminal tagger) acc ->
                            if terminal == current then
                                tagger :: acc

                            else
                                acc
                        )
                        []
                        subscriptions

                Nothing ->
                    []

        accepted =
            List.take 200 currentTaggers

        rejected =
            List.drop 200 currentTaggers

        rejectedCount =
            List.length rejected

        newlyRejected =
            List.drop state.resizeRejected rejected

        notifyLimit next =
            List.foldl
                (\tagger task -> task |> Task.andThen (\_ -> Platform.sendToApp router (tagger ResizeSubscriberLimit)))
                (Task.succeed ())
                newlyRejected
                |> Task.map (\_ -> { next | resizeRejected = rejectedCount })
    in
    case ( accepted, state.resizeListener, state.terminal ) of
        ( [], Just ( _, pid ), _ ) ->
            Process.kill pid
                |> Task.andThen (\_ -> notifyLimit { state | resizeTaggers = [], resizeListener = Nothing, nextResize = state.nextResize + 1 })

        ( [], Nothing, _ ) ->
            notifyLimit { state | resizeTaggers = [] }

        ( _ :: _, Just _, Just _ ) ->
            notifyLimit { state | resizeTaggers = accepted }

        ( _ :: _, Nothing, Just terminal ) ->
            let
                generation =
                    state.nextResize
            in
            Elm.Kernel.SchelmRuntime.attachResize (terminalId terminal) (\size -> Platform.sendToSelf router (ResizeDone generation size))
                |> Process.spawn
                |> Task.andThen (\pid -> notifyLimit { state | resizeTaggers = accepted, resizeListener = Just ( generation, pid ) })

        ( _ :: _, _, Nothing ) ->
            Task.succeed state


onSelfMsg router selfMsg state =
    case selfMsg of
        ReadDone reader readId callback result ->
            case state.reading of
                Just ( currentReader, currentRead, _ ) ->
                    if currentReader == reader && currentRead == readId && state.reader == Just reader then
                        Platform.sendToApp router (callback result)
                            |> Task.map (\_ -> { state | reading = Nothing, nextRead = state.nextRead + 1 })

                    else
                        Task.succeed state

                Nothing ->
                    Task.succeed state

        ResizeDone generation size ->
            case state.resizeListener of
                Just ( current, _ ) ->
                    if current == generation then
                        List.foldl
                            (\tagger task -> task |> Task.andThen (\_ -> Platform.sendToApp router (tagger (Resized size))))
                            (Task.succeed ())
                            state.resizeTaggers
                            |> Task.map (\_ -> state)

                    else
                        Task.succeed state

                Nothing ->
                    Task.succeed state


cancelRead state =
    case state.reading of
        Nothing ->
            Task.succeed state

        Just ( _, _, pid ) ->
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
