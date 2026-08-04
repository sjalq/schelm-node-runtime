port module Main exposing (main)

import Platform
import Schelm.Node.Runtime as Runtime
import Schelm.Node.Runtime.Clock as Clock
import Schelm.Node.Runtime.Console as Console
import Schelm.Node.Runtime.Entropy as Entropy
import Schelm.Node.Runtime.Signal as Signal
import Schelm.Node.Runtime.Ticker as Ticker
import Schelm.Node.Terminal as Terminal
import Task


port report : String -> Cmd msg


type Msg
    = Ready (Result Runtime.InitError Runtime.Runtime)
    | Wrote (Result Console.WriteError ())
    | SuiteWrote Int (Result Console.WriteError ())
    | TerminalReady (Result Terminal.AcquireError Terminal.Terminal)
    | Controlled (Result Terminal.ControlError ())
    | Recovered (Result Terminal.ControlError ())
    | ReaderReady (Result Terminal.ReaderError Terminal.InputReader)
    | ReadDone (Result Terminal.InputError Terminal.InputPiece)
    | TickerReady (Result Ticker.StartError Ticker.Ticker)
    | SignalEvent Signal.Event
    | ResizeEvent Terminal.ResizeEvent
    | TickEvent Ticker.Tick
    | EntropyDone (Result Entropy.Error String)
    | ShareAcquired (Result Terminal.AcquireError Terminal.Terminal)
    | ShareControlled (Result Terminal.ControlError ())
    | ShareReleased (Result Terminal.ControlError ())
    | ShareRecovered (Result Terminal.ControlError ())
    | ShareTickerReady (Result Ticker.StartError Ticker.Ticker)
    | ReplayReaderReady (Result Terminal.ReaderError Terminal.InputReader)
    | ReplayReadDone Int (Result Terminal.InputError Terminal.InputPiece)


type alias Model =
    { runtime : Maybe Runtime.Runtime
    , terminal : Maybe Terminal.Terminal
    , reader : Maybe Terminal.InputReader
    , ticker : Maybe Ticker.Ticker
    , mode : String
    , shareCount : Int
    }


main : Program String Model Msg
main =
    Platform.worker
        { init = \mode -> ( { empty | mode = mode }, Task.attempt Ready (Runtime.initialize Runtime.emptySelection) )
        , update = update
        , subscriptions = subscriptions
        }


empty =
    { runtime = Nothing, terminal = Nothing, reader = Nothing, ticker = Nothing, mode = "ordinary", shareCount = 0 }


subscriptions model =
    Sub.batch
        [ case model.runtime of
            Just runtime ->
                if model.mode == "fanout-signal" then
                    Sub.batch (List.repeat 200 (Signal.onSignal runtime Signal.Interrupt SignalEvent))

                else
                    Signal.onSignal runtime Signal.Interrupt SignalEvent |> Sub.map identity

            Nothing ->
                Sub.none
        , case model.terminal of
            Just terminal ->
                if model.mode == "pty-fanout-resize" then
                    Sub.batch (List.repeat 200 (Terminal.onResize terminal ResizeEvent))

                else
                    Terminal.onResize terminal ResizeEvent |> Sub.map identity

            Nothing ->
                Sub.none
        , case model.ticker of
            Just ticker ->
                if model.mode == "fanout-ticker" then
                    Sub.batch (List.repeat 200 (Ticker.onTick ticker TickEvent))

                else
                    Ticker.onTick ticker TickEvent |> Sub.map identity

            Nothing ->
                Sub.none
        ]


crash : () -> a
crash _ =
    crash ()


update msg model =
    case msg of
        Ready (Ok runtime) ->
            let
                output =
                    case Console.text "api" of
                        Ok value ->
                            value

                        Err _ ->
                            crash ()

                count =
                    case Entropy.byteCount 8 of
                        Ok value ->
                            value

                        Err _ ->
                            crash ()

                duration =
                    case Clock.timerDuration 100 of
                        Ok value ->
                            value

                        Err _ ->
                            crash ()
            in
            ( { model | runtime = Just runtime }
            , Cmd.batch
                (if model.mode == "console-suite" then
                    List.map (\id -> Console.write (Console.stdout runtime) output (SuiteWrote id)) (List.range 0 2)

                 else if model.mode == "pty-share" then
                    List.repeat 65 (Terminal.acquire runtime ShareAcquired)

                 else if model.mode == "pty-input-replay" then
                    [ Terminal.acquire runtime TerminalReady ]

                 else if model.mode == "share-ticker" then
                    List.repeat 65 (Ticker.start runtime duration ShareTickerReady)

                 else if model.mode == "fanout-ticker" then
                    [ Ticker.start runtime duration TickerReady ]

                 else if String.startsWith "pty-" model.mode then
                    [ Terminal.acquire runtime TerminalReady ]

                 else
                    [ Console.write (Console.stdout runtime) output Wrote |> Cmd.map identity
                    , Console.write (Console.stderr runtime) output Wrote
                    , Terminal.acquire runtime TerminalReady
                    , Terminal.recover runtime Recovered
                    , Ticker.start runtime duration TickerReady
                    , Entropy.hex runtime count |> Task.attempt EntropyDone
                    ]
                )
            )

        Ready (Err _) ->
            ( model, report "init-error" )

        TerminalReady (Ok terminal) ->
            ( { model | terminal = Just terminal }
            , if model.mode == "pty-input-replay" then
                Terminal.openInput terminal ReplayReaderReady

              else
                Cmd.batch [ Terminal.setRawMode terminal Terminal.Raw Controlled, Terminal.openInput terminal ReaderReady ]
            )

        ReaderReady (Ok reader) ->
            ( { model | reader = Just reader }, Terminal.read reader ReadDone )

        ReadDone (Ok piece) ->
            ( model, report (Terminal.inputText piece ++ String.fromInt (Terminal.inputBytes piece)) )

        TickerReady (Ok ticker) ->
            ( { model | ticker = Just ticker }, Cmd.none )

        TickEvent tick ->
            ( model, report (String.fromInt (Ticker.skippedIntervals tick)) )

        SignalEvent _ ->
            ( model, report "signal" )

        ResizeEvent _ ->
            ( model, report "resize" )

        Wrote _ ->
            ( model, Cmd.none )

        SuiteWrote id result ->
            ( model, report ("console:" ++ String.fromInt id ++ ":" ++ consoleResult result) )

        Controlled (Ok _) ->
            case model.terminal of
                Just terminal ->
                    if model.mode == "pty-release" || model.mode == "pty-restore-failed" then
                        ( model, Cmd.batch [ report "RAW", Terminal.release terminal Controlled ] )

                    else
                        ( model, report "RAW" )

                Nothing ->
                    ( model, Cmd.none )

        Controlled (Err Terminal.RestoreFailedControl) ->
            ( model, Cmd.batch [ report "POISON", Maybe.withDefault Cmd.none (Maybe.map (\runtime -> Terminal.recover runtime Recovered) model.runtime) ] )

        Controlled (Err _) ->
            ( model, report "control-error" )

        Recovered (Ok _) ->
            ( model, report "RECOVERED" )

        Recovered (Err _) ->
            ( model, report "recover-error" )

        TerminalReady (Err _) ->
            ( model, Cmd.none )

        ReaderReady (Err _) ->
            ( model, Cmd.none )

        ReadDone (Err _) ->
            ( model, Cmd.none )

        TickerReady (Err _) ->
            ( model, Cmd.none )

        EntropyDone _ ->
            ( model, Cmd.none )

        ShareAcquired result ->
            let
                nextCount =
                    model.shareCount + 1

                nextTerminal =
                    case result of
                        Ok terminal ->
                            Just terminal

                        Err _ ->
                            model.terminal

                nextModel =
                    { model | shareCount = nextCount, terminal = nextTerminal }
            in
            if nextCount == 65 then
                case nextTerminal of
                    Just terminal ->
                        ( { nextModel | shareCount = 0 }, Cmd.batch [ report (shareAcquireResult result), Cmd.batch (List.repeat 65 (Terminal.setRawMode terminal Terminal.Raw ShareControlled)) ] )

                    Nothing ->
                        ( nextModel, report "share-acquire-no-terminal" )

            else
                ( nextModel, report (shareAcquireResult result) )

        ShareControlled result ->
            let
                nextCount =
                    model.shareCount + 1
            in
            if nextCount == 65 then
                case model.terminal of
                    Just terminal ->
                        ( { model | shareCount = 0 }, Cmd.batch [ report (shareControlResult "control" result), Cmd.batch (List.repeat 65 (Terminal.release terminal ShareReleased)) ] )

                    Nothing ->
                        ( model, report "share-control-no-terminal" )

            else
                ( { model | shareCount = nextCount }, report (shareControlResult "control" result) )

        ShareReleased result ->
            let
                nextCount =
                    model.shareCount + 1
            in
            if nextCount == 65 then
                case model.runtime of
                    Just runtime ->
                        ( { model | shareCount = 0 }, Cmd.batch [ report (shareControlResult "release" result), Cmd.batch (List.repeat 65 (Terminal.recover runtime ShareRecovered)) ] )

                    Nothing ->
                        ( model, report "share-release-no-runtime" )

            else
                ( { model | shareCount = nextCount }, report (shareControlResult "release" result) )

        ShareRecovered result ->
            ( model, report (shareControlResult "recover" result) )

        ReplayReaderReady (Ok reader) ->
            ( { model | reader = Just reader }, Terminal.read reader (ReplayReadDone 1) )

        ReplayReaderReady (Err _) ->
            ( model, report "input-reader-error" )

        ReplayReadDone readNumber (Ok piece) ->
            case ( readNumber, model.reader ) of
                ( 1, Just reader ) ->
                    ( model, Cmd.batch [ report ("input:" ++ Terminal.inputText piece ++ ":" ++ String.fromInt (Terminal.inputBytes piece) ++ ":" ++ malformedLabel (Terminal.inputHadMalformedUtf8 piece)), Terminal.read reader (ReplayReadDone 2) ] )

                _ ->
                    ( model, report "input-unexpected-piece" )

        ReplayReadDone _ (Err (Terminal.InputEnded malformed)) ->
            ( model, report ("input-end:" ++ malformedLabel malformed) )

        ReplayReadDone _ (Err _) ->
            ( model, report "input-read-error" )

        ShareTickerReady result ->
            ( model
            , report
                (case result of
                    Ok _ ->
                        "ticker-ok"

                    Err Ticker.TooManyStartJoiners ->
                        "ticker-join-limit"

                    Err _ ->
                        "ticker-other-error"
                )
            )


consoleResult result =
    case result of
        Ok _ ->
            "ok"

        Err Console.BrokenPipe ->
            "pipe"

        Err Console.Closed ->
            "closed"

        Err _ ->
            "other"


malformedLabel malformed =
    if malformed then
        "malformed"

    else
        "valid"


shareAcquireResult result =
    case result of
        Ok _ ->
            "acquire-ok"

        Err Terminal.TooManyAcquireJoiners ->
            "acquire-join-limit"

        Err _ ->
            "acquire-other-error"


shareControlResult prefix result =
    case result of
        Ok _ ->
            prefix ++ "-ok"

        Err Terminal.TooManyControlJoiners ->
            prefix ++ "-join-limit"

        Err Terminal.Released ->
            prefix ++ "-released"

        Err _ ->
            prefix ++ "-other-error"
