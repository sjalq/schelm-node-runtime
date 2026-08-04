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


type alias Model =
    { runtime : Maybe Runtime.Runtime
    , terminal : Maybe Terminal.Terminal
    , reader : Maybe Terminal.InputReader
    , ticker : Maybe Ticker.Ticker
    , mode : String
    }


main : Program String Model Msg
main =
    Platform.worker
        { init = \mode -> ( { empty | mode = mode }, Task.attempt Ready (Runtime.initialize Runtime.emptySelection) )
        , update = update
        , subscriptions = subscriptions
        }


empty =
    { runtime = Nothing, terminal = Nothing, reader = Nothing, ticker = Nothing, mode = "ordinary" }


subscriptions model =
    Sub.batch
        [ case model.runtime of
            Just runtime ->
                Signal.onSignal runtime Signal.Interrupt SignalEvent |> Sub.map identity

            Nothing ->
                Sub.none
        , case model.terminal of
            Just terminal ->
                Terminal.onResize terminal ResizeEvent |> Sub.map identity

            Nothing ->
                Sub.none
        , case model.ticker of
            Just ticker ->
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
                (if String.startsWith "pty-" model.mode then
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
            , Cmd.batch [ Terminal.setRawMode terminal Terminal.Raw Controlled, Terminal.openInput terminal ReaderReady ]
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
