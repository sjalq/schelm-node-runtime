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
    { count : Int }


main : Program Int Model Msg
main =
    Platform.worker
        { init = \count -> ( { count = count }, Task.attempt Ready (Runtime.initialize Runtime.emptySelection) )
        , update = update
        , subscriptions = always Sub.none
        }


update msg model =
    case msg of
        Ready (Ok runtime) ->
            let
                make id =
                    case Console.text "" of
                        Ok value ->
                            Console.write (Console.stdout runtime) value (Wrote id)

                        Err _ ->
                            Cmd.none
            in
            ( model, Cmd.batch (List.map make (List.range 0 (model.count - 1))) )

        Ready (Err _) ->
            ( model, report (event "init-error" -1) )

        Wrote id result ->
            ( model
            , report
                (event
                    (case result of
                        Ok _ ->
                            "ok"

                        Err Console.TooManyWrites ->
                            "count"

                        Err Console.BackpressureLimit ->
                            "bytes"

                        Err _ ->
                            "error"
                    )
                    id
                )
            )


event outcome id =
    E.object
        [ ( "kind", E.string "settle" )
        , ( "id", E.int id )
        , ( "outcome", E.string outcome )
        ]
