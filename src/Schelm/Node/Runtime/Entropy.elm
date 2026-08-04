module Schelm.Node.Runtime.Entropy exposing (ByteCount, CountError(..), Error(..), byteCount, byteCountInt, bytes, hex)

import Bytes exposing (Bytes)
import Elm.Kernel.SchelmRuntime
import Schelm.Node.Runtime exposing (Runtime)
import Task exposing (Task)


type ByteCount
    = ByteCount Int


type CountError
    = NonPositiveCount
    | CountTooLarge


type Error
    = EntropyUnavailable


byteCount n =
    if n <= 0 then
        Err NonPositiveCount

    else if n > 65536 then
        Err CountTooLarge

    else
        Ok (ByteCount n)


byteCountInt (ByteCount n) =
    n


bytes _ (ByteCount n) =
    Elm.Kernel.SchelmRuntime.entropy n |> Task.mapError (\_ -> EntropyUnavailable)


hex _ (ByteCount n) =
    Elm.Kernel.SchelmRuntime.entropyHex n |> Task.mapError (\_ -> EntropyUnavailable)
