port module Main exposing (main)

import Feasibility.Runtime as Runtime
import Json.Encode as Encode
import Platform
import Task

port report : Encode.Value -> Cmd msg
port control : (String -> msg) -> Sub msg

type Msg
    = SnapshotReady Runtime.Snapshot
    | Written Bool
    | Probed String
    | Control String

type alias Model =
    { subscribed : Bool }

main : Program () Model Msg
main =
    Platform.worker
        { init = \_ -> ( { subscribed = True }, Task.perform SnapshotReady Runtime.snapshot )
        , update = update
        , subscriptions = subscriptions
        }

subscriptions model =
    Sub.batch
        [ control Control
        , if model.subscribed then Runtime.onProbe Probed else Sub.none
        ]

update msg model =
    case msg of
        SnapshotReady facts ->
            ( model
            , Cmd.batch
                [ report <| Encode.object
                    [ ( "kind", Encode.string "snapshot" )
                    , ( "nowMs", Encode.float facts.nowMs )
                    , ( "randomHexLength", Encode.int (String.length facts.randomHex) )
                    , ( "envPresent", Encode.bool facts.envPresent )
                    , ( "isTty", Encode.bool facts.isTty )
                    , ( "columns", Encode.int facts.columns )
                    , ( "rows", Encode.int facts.rows )
                    ]
                , Runtime.write "WRITE_ACK\n" Written
                ]
            )

        Written ok ->
            ( model, report (event "written" ok) )

        Probed value ->
            ( model, report <| Encode.object [ ( "kind", Encode.string "probe" ), ( "value", Encode.string value ) ] )

        Control "unsubscribe" ->
            ( { model | subscribed = False }, report (event "unsubscribed" True) )

        Control "exit7" ->
            ( model, Runtime.exitStandalone 7 )

        Control _ ->
            ( model, Cmd.none )

event kind ok =
    Encode.object [ ( "kind", Encode.string kind ), ( "ok", Encode.bool ok ) ]
