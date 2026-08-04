module Schelm.Node.Runtime exposing
    ( Architecture(..)
    , EnvironmentName
    , InitError(..)
    , NameError(..)
    , OperatingSystem(..)
    , ProcessInfo
    , Runtime
    , RuntimeField(..)
    , Selection
    , SelectionError(..)
    , emptySelection
    , environment
    , environmentName
    , environmentNameString
    , initialize
    , oneEnvironment
    , processInfo
    , selection
    )

import Array exposing (Array)
import Dict exposing (Dict)
import Elm.Kernel.SchelmRuntime
import Set
import Task exposing (Task)


type Runtime
    = Runtime ProcessInfo (Dict String String)


type EnvironmentName
    = EnvironmentName String


type Selection
    = Selection (List EnvironmentName)


type NameError
    = EmptyEnvironmentName
    | EnvironmentNameContainsNul
    | EnvironmentNameContainsEquals
    | EnvironmentNameTooLong


type SelectionError
    = TooManyEnvironmentNames
    | EnvironmentSelectionTooLarge


type InitError
    = UnsupportedRuntime
    | TooManyArguments
    | ArgumentTooLarge
    | ArgumentsTooLarge
    | ExecutablePathTooLarge
    | EnvironmentValueTooLarge EnvironmentName
    | SelectedEnvironmentTooLarge
    | InvalidHostText RuntimeField


type RuntimeField
    = HostArgument
    | HostExecutable
    | HostEnvironmentValue EnvironmentName


type OperatingSystem
    = Linux
    | Darwin
    | Windows
    | FreeBsd
    | OpenBsd
    | SunOs
    | Aix
    | OtherOperatingSystem String


type Architecture
    = X64
    | Arm64
    | Arm
    | Ia32
    | Mips
    | MipsEl
    | Ppc
    | Ppc64
    | S390
    | S390x
    | OtherArchitecture String


type alias ProcessInfo =
    { operatingSystem : OperatingSystem, architecture : Architecture, processId : Int, arguments : Array String, executable : String }


type alias Raw =
    { platform : String, arch : String, pid : Int, args : List String, exec : String, env : List { a : String, b : String } }


environmentName raw =
    case utf8Width raw of
        Nothing ->
            Err EnvironmentNameTooLong

        Just width ->
            if width == 0 then
                Err EmptyEnvironmentName

            else if String.contains "\u{0000}" raw then
                Err EnvironmentNameContainsNul

            else if String.contains "=" raw then
                Err EnvironmentNameContainsEquals

            else if width > 256 then
                Err EnvironmentNameTooLong

            else
                Ok (EnvironmentName raw)


environmentNameString (EnvironmentName value) =
    value


selection names =
    let
        step name ( seen, byteTotal, kept ) =
            let
                value =
                    environmentNameString name
            in
            if Set.member value seen then
                ( seen, byteTotal, kept )

            else
                ( Set.insert value seen, byteTotal + Maybe.withDefault 0 (utf8Width value), name :: kept )

        ( _, selectedBytes, reversed ) =
            List.foldl step ( Set.empty, 0, [] ) names
    in
    if List.length reversed > 128 then
        Err TooManyEnvironmentNames

    else if selectedBytes > 16384 then
        Err EnvironmentSelectionTooLarge

    else
        Ok (Selection (List.reverse reversed))


emptySelection =
    Selection []


oneEnvironment name =
    Selection [ name ]


initialize (Selection names) =
    Elm.Kernel.SchelmRuntime.snapshot (List.map environmentNameString names)
        |> Task.mapError (\_ -> UnsupportedRuntime)
        |> Task.andThen validateRaw


validateRaw raw =
    let
        args =
            raw.args

        widths =
            List.map utf8Width args

        total =
            List.sum (List.map (Maybe.withDefault 0) widths)

        envResult =
            validateEnv raw.env
    in
    if List.length args > 1024 then
        Task.fail TooManyArguments

    else if List.any ((==) Nothing) widths then
        Task.fail (InvalidHostText HostArgument)

    else if List.any (Maybe.withDefault 0 >> (>) 65536) widths then
        Task.fail ArgumentTooLarge

    else if total > 1048576 then
        Task.fail ArgumentsTooLarge

    else
        case utf8Width raw.exec of
            Nothing ->
                Task.fail (InvalidHostText HostExecutable)

            Just n ->
                if n > 4096 then
                    Task.fail ExecutablePathTooLarge

                else
                    case envResult of
                        Err e ->
                            Task.fail e

                        Ok values ->
                            Task.succeed (Runtime { operatingSystem = os raw.platform, architecture = arch raw.arch, processId = raw.pid, arguments = Array.fromList args, executable = raw.exec } values)


validateEnv pairs =
    let
        step pair result =
            case result of
                Err e ->
                    Err e

                Ok ( total, dict ) ->
                    case ( environmentName pair.a, utf8Width pair.b ) of
                        ( Ok name, Just n ) ->
                            if n > 65536 then
                                Err (EnvironmentValueTooLarge name)

                            else if total + n > 1048576 then
                                Err SelectedEnvironmentTooLarge

                            else
                                Ok ( total + n, Dict.insert pair.a pair.b dict )

                        ( Ok name, Nothing ) ->
                            Err (InvalidHostText (HostEnvironmentValue name))

                        _ ->
                            Err UnsupportedRuntime
    in
    List.foldl step (Ok ( 0, Dict.empty )) pairs |> Result.map Tuple.second


processInfo (Runtime info _) =
    info


environment (Runtime _ values) name =
    Dict.get (environmentNameString name) values


utf8Width value =
    let
        n =
            Elm.Kernel.SchelmRuntime.utf8Width value
    in
    if n < 0 then
        Nothing

    else
        Just n


os value =
    case value of
        "linux" ->
            Linux

        "darwin" ->
            Darwin

        "win32" ->
            Windows

        "freebsd" ->
            FreeBsd

        "openbsd" ->
            OpenBsd

        "sunos" ->
            SunOs

        "aix" ->
            Aix

        _ ->
            OtherOperatingSystem (String.left 64 value)


arch value =
    case value of
        "x64" ->
            X64

        "arm64" ->
            Arm64

        "arm" ->
            Arm

        "ia32" ->
            Ia32

        "mips" ->
            Mips

        "mipsel" ->
            MipsEl

        "ppc" ->
            Ppc

        "ppc64" ->
            Ppc64

        "s390" ->
            S390

        "s390x" ->
            S390x

        _ ->
            OtherArchitecture (String.left 64 value)
