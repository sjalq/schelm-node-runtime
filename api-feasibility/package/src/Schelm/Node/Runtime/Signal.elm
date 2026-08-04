effect module Schelm.Node.Runtime.Signal where { subscription = SignalSub } exposing (Event(..), Signal(..), onSignal)

import Platform
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
