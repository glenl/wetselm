module Wets exposing
    ( FlowCommand
    , MotorCommand
    , VesselCommand
    , WetsMessage(..)
    , actuatorMoveDone
    , flowDecoder
    , flowEqualized
    , messageType
    , motorDecoder
    , newVessel
    , vesselDecoder
    , vesselPassedGate
    )

import Json.Decode as Decode
import Json.Encode as Encode


type WetsMessage
    = MotorMsg
    | FlowMsg
    | VesselMsg


type alias MotorCommand =
    { object : String
    , operation : String
    , name : String
    }


type alias VesselCommand =
    { object : String
    , operation : String
    , license : String
    , gate : String
    }


messageType : String -> Maybe WetsMessage
messageType s =
    case Decode.decodeString (Decode.field "object" Decode.string) s of
        Ok cmd ->
            case cmd of
                "Motor" ->
                    Just MotorMsg

                "FlowSensor" ->
                    Just FlowMsg

                "Vessel" ->
                    Just VesselMsg

                _ ->
                    Nothing

        Err _ ->
            Nothing


motorDecoder : Decode.Decoder MotorCommand
motorDecoder =
    Decode.map3 MotorCommand
        (Decode.field "object" Decode.string)
        (Decode.field "operation" Decode.string)
        (Decode.field "name" Decode.string)


type alias FlowCommand =
    { object : String
    , operation : String
    , name : String
    }


flowDecoder : Decode.Decoder FlowCommand
flowDecoder =
    Decode.map3 FlowCommand
        (Decode.field "object" Decode.string)
        (Decode.field "operation" Decode.string)
        (Decode.field "name" Decode.string)


vesselDecoder : Decode.Decoder VesselCommand
vesselDecoder =
    Decode.map4 VesselCommand
        (Decode.field "object" Decode.string)
        (Decode.field "operation" Decode.string)
        (Decode.field "license" Decode.string)
        (Decode.field "gate" Decode.string)


newVessel : String -> String -> String
newVessel license direction =
    Encode.object
        [ ( "object", Encode.string "VesselArrived" )
        , ( "license", Encode.string license )
        , ( "direction", Encode.string direction )
        , ( "wets_name", Encode.string "Wets_1" )
        ]
        |> Encode.encode 0


actuatorMoveDone : String -> String
actuatorMoveDone name =
    Encode.object
        [ ( "object", Encode.string "MotorCompleted" )
        , ( "name", Encode.string name )
        ]
        |> Encode.encode 0


vesselPassedGate : String -> String
vesselPassedGate license =
    Encode.object
        [ ( "object", Encode.string "VesselPassedGate" )
        , ( "license", Encode.string license )
        ]
        |> Encode.encode 0


flowEqualized : String -> String
flowEqualized name =
    Encode.object
        [ ( "object", Encode.string "FlowEqualized" )
        , ( "name", Encode.string name )
        ]
        |> Encode.encode 0
