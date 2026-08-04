port module Main exposing (main)

import Json.Encode as E
import Platform
import Schelm.Node.Runtime as Runtime
import Schelm.Node.Runtime.Console as Console
import Task


port report : E.Value -> Cmd msg


type Msg
    = Ready (Result Runtime.InitError Runtime.Runtime)
    | Wrote Int (Result Console.WriteError ())


type alias Model =
    { settled : Int }


main : Program () Model Msg
main =
    Platform.worker { init = \_ -> ( { settled = 0 }, Task.attempt Ready (Runtime.initialize Runtime.emptySelection) ), update = update, subscriptions = always Sub.none }


initError error =
    case error of
        Runtime.UnsupportedRuntime ->
            "unsupported"

        Runtime.TooManyArguments ->
            "args-count"

        Runtime.ArgumentTooLarge ->
            "arg-large"

        Runtime.ArgumentsTooLarge ->
            "args-large"

        Runtime.ExecutablePathTooLarge ->
            "exec-large"

        Runtime.EnvironmentValueTooLarge _ ->
            "env-large"

        Runtime.SelectedEnvironmentTooLarge ->
            "env-total"

        Runtime.InvalidHostText _ ->
            "host-text"


update msg model =
    case msg of
        Ready (Ok runtime) ->
            let
                values =
                    [ "", "a", "bb" ]

                make i raw =
                    case Console.text raw of
                        Ok value ->
                            Console.write (Console.stdout runtime) value (Wrote i)

                        Err _ ->
                            Cmd.none
            in
            ( model, Cmd.batch (List.indexedMap make values) )

        Ready (Err error) ->
            ( model, report (E.object [ ( "kind", E.string "init-error" ), ( "error", E.string (initError error) ) ]) )

        Wrote id result ->
            let
                next =
                    { model | settled = model.settled + 1 }

                outcome =
                    case result of
                        Ok _ ->
                            "ok"

                        Err _ ->
                            "error"
            in
            ( next, report (E.object [ ( "kind", E.string "settle" ), ( "id", E.int id ), ( "outcome", E.string outcome ) ]) )
