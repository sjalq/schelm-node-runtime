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


environmentName raw =
    if String.isEmpty raw then
        Err EmptyEnvironmentName

    else if String.contains "\u{0000}" raw then
        Err EnvironmentNameContainsNul

    else if String.contains "=" raw then
        Err EnvironmentNameContainsEquals

    else if String.length raw > 256 then
        Err EnvironmentNameTooLong

    else
        Ok (EnvironmentName raw)


environmentNameString (EnvironmentName value) =
    value


selection names =
    if List.length names > 128 then
        Err TooManyEnvironmentNames

    else
        Ok (Selection names)


emptySelection =
    Selection []


oneEnvironment name =
    Selection [ name ]


initialize _ =
    Task.succeed (Runtime { operatingSystem = Linux, architecture = X64, processId = 0, arguments = Array.empty, executable = "" } Dict.empty)


processInfo (Runtime info _) =
    info


environment (Runtime _ values) name =
    Dict.get (environmentNameString name) values
