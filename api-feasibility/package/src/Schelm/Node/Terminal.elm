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

import Platform
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


type State msg
    = State (Maybe msg)


type SelfMsg
    = None


init =
    Task.succeed (State Nothing)


onEffects _ _ _ state =
    Task.succeed state


onSelfMsg _ _ state =
    Task.succeed state
