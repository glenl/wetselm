port module Main exposing (main)

import Animator
import Browser
import Color
import Delay
import Dict exposing (Dict)
import Element as E
import Element.Background as Background
import Element.Border as Border
import Json.Decode as Decode
import Nats
import Nats.Config
import Nats.Effect
import Nats.Events
import Nats.PortsAPI
import Nats.Protocol
import Nats.Socket
import Nats.Sub
import OUI.Button as Button
import OUI.Material as Material
import OUI.Material.Color
import OUI.Material.Theme
import OUI.Text as Text
import Random
import Svg exposing (Svg)
import Svg.Attributes as SvgA
import Time
import UI
import Util
import Wets


type alias Model =
    { nats : Nats.State String Msg
    , socket : Nats.Socket.Socket
    , serverInfo : Maybe Nats.Protocol.ServerInfo
    , actuatorStates : Animator.Timeline (Dict Id ActuatorState)
    , chamberStates : Animator.Timeline (Dict Id ChamberState)
    , vesselStates : Animator.Timeline (Dict Id TransitState)
    , activeVessels : VesselDict
    , vesselCount : Int
    , message : String
    }


type ChamberState
    = High
    | Low


type alias ChamberFlow =
    { chamberName : String
    , state : ChamberState
    }


type ActuatorState
    = Opened
    | Closed


type alias Id =
    String


type TransitState
    = UpperEntry
    | UpperGate
    | ChamberHigh
    | ChamberLow
    | LowerGate
    | LowerEntry
    | AtSea


type alias TransitSequence =
    List TransitState


type alias Vessel =
    { direction : Util.Direction
    , sequence : TransitSequence
    }


type alias VesselDict =
    Dict Id Vessel


type Msg
    = AnimationRuntimeStep Time.Posix
    | MoveVessel Id Int
    | VesselFinished Id
    | VesselPassedGate Id
    | FlowComplete Id
    | ActuatorMoveDone Id
    | StartVessel Util.Direction
    | NatsMsg (Nats.Msg String Msg)
    | OnSocketEvent Nats.Events.SocketEvent
    | ReceiveProg String


downStreamSequence : TransitSequence
downStreamSequence =
    [ UpperEntry
    , UpperGate
    , ChamberHigh
    , ChamberLow
    , LowerEntry
    ]


upStreamSequence : TransitSequence
upStreamSequence =
    [ LowerEntry
    , LowerGate
    , ChamberLow
    , ChamberHigh
    , UpperEntry
    ]


animator : Animator.Animator Model
animator =
    Animator.animator
        |> Animator.watching
            .actuatorStates
            (\newActuatorStates model ->
                { model | actuatorStates = newActuatorStates }
            )
        |> Animator.watching
            .chamberStates
            (\newChamberStates model ->
                { model | chamberStates = newChamberStates }
            )
        |> Animator.watching
            .vesselStates
            (\newVesselStates model ->
                { model | vesselStates = newVesselStates }
            )


main : Program { now : Int } Model Msg
main =
    Browser.document
        { view = view
        , init = init
        , update = wrappedUpdate
        , subscriptions = subscriptions
        }


init : { now : Int } -> ( Model, Cmd Msg )
init flags =
    let
        nats : Nats.State String Msg
        nats =
            Nats.init (Random.initialSeed flags.now)
                (Time.millisToPosix flags.now)
    in
    ( { actuatorStates =
            Animator.init <|
                Dict.fromList
                    [ ( "Valve-M01", Closed )
                    , ( "Valve-M02", Closed )
                    , ( "Gate-M01", Closed )
                    , ( "Gate-M02", Closed )
                    ]
      , chamberStates =
            Animator.init <|
                Dict.fromList [ ( "Chamber-01", High ) ]
      , vesselStates = Animator.init Dict.empty
      , nats = nats
      , socket = Nats.Socket.new "0" "ws://localhost:8087"
      , serverInfo = Nothing
      , vesselCount = 0
      , activeVessels = Dict.empty
      , message = ""
      }
    , Cmd.none
    )


chamberDepth : ChamberState -> Float
chamberDepth cstate =
    case cstate of
        High ->
            40.0

        Low ->
            80.0


toPosition : TransitState -> Util.Position
toPosition state =
    case state of
        UpperEntry ->
            { x = -70.0, y = chamberDepth High }

        UpperGate ->
            { x = 100.0, y = chamberDepth High }

        ChamberHigh ->
            { x = 300.0, y = chamberDepth High }

        ChamberLow ->
            { x = 300.0, y = chamberDepth Low }

        LowerGate ->
            { x = 500.0, y = chamberDepth Low }

        LowerEntry ->
            { x = 650.0, y = chamberDepth Low }

        AtSea ->
            { x = 0.0, y = 0.0 }


nextTransition : Id -> VesselDict -> Maybe TransitState
nextTransition license vdict =
    Dict.get license vdict
        |> Maybe.andThen (\v -> List.head v.sequence)


adjustSequence : Id -> VesselDict -> VesselDict
adjustSequence license vdict =
    let
        pophead : Vessel -> Vessel
        pophead v =
            { v | sequence = List.drop 1 v.sequence }
    in
    Dict.update license (Maybe.map pophead) vdict


newVessel : Util.Direction -> Vessel
newVessel dir =
    { direction = dir
    , sequence =
        case dir of
            Util.Upstream ->
                upStreamSequence

            Util.Downstream ->
                downStreamSequence
    }


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Nats.subscriptions natsConfig model.nats
        , Animator.toSubscription AnimationRuntimeStep model animator
        ]


port natsSend : Nats.PortsAPI.Send String msg


port natsReceive : Nats.PortsAPI.Receive String msg


natsConfig : Nats.Config String String Msg
natsConfig =
    Nats.Config.string NatsMsg
        { send = natsSend
        , receive = natsReceive
        }
        |> Nats.Config.withDebug False


receiveProg : Nats.Protocol.Message String -> Msg
receiveProg natsMessage =
    ReceiveProg natsMessage.data


natsSubscriptions : Model -> Nats.Sub String Msg
natsSubscriptions model =
    Nats.Sub.batch
        [ Nats.connect
            (Nats.Socket.connectOptions "Wets UI" "0.1"
                |> Nats.Socket.withUserPass "test" "test"
            )
            model.socket
            OnSocketEvent
        , Nats.subscribe "Wets.client" receiveProg
        ]


wrappedUpdate : Msg -> Model -> ( Model, Cmd Msg )
wrappedUpdate msg model =
    let
        ( newModel, natsEffect, cmd ) =
            update msg model

        ( nats, natsCmd ) =
            Nats.applyEffectAndSub
                natsConfig
                natsEffect
                (natsSubscriptions model)
                newModel.nats
    in
    ( { newModel | nats = nats }
    , Cmd.batch [ cmd, natsCmd ]
    )


update : Msg -> Model -> ( Model, Nats.Effect String Msg, Cmd Msg )
update msg model =
    case msg of
        AnimationRuntimeStep tick ->
            ( Animator.update tick animator model
            , Nats.Effect.none
            , Cmd.none
            )

        MoveVessel license millis ->
            case nextTransition license model.activeVessels of
                Nothing ->
                    ( { model
                        | message =
                            "handleVessel: No next transit state for " ++ license
                      }
                    , Nats.Effect.none
                    , Cmd.none
                    )

                Just nextState ->
                    let
                        setVesselState : TransitState -> Dict Id TransitState
                        setVesselState newState =
                            Dict.insert license newState <|
                                Animator.current model.vesselStates
                    in
                    ( { model
                        | vesselStates =
                            model.vesselStates
                                |> Animator.go (Animator.millis <| toFloat millis)
                                    (setVesselState nextState)
                        , activeVessels =
                            adjustSequence license model.activeVessels
                      }
                    , Nats.Effect.none
                    , if nextState == LowerEntry || nextState == UpperEntry then
                        Delay.after millis <| VesselFinished license

                      else
                        Cmd.none
                    )

        VesselFinished id ->
            ( { model
                | activeVessels = Dict.remove id model.activeVessels
                , vesselStates =
                    model.vesselStates
                        |> Animator.go Animator.immediately
                            (Dict.remove id <| Animator.current model.vesselStates)
                , message = "Finished \"" ++ id ++ "\""
              }
            , Nats.Effect.none
            , Cmd.none
            )

        VesselPassedGate id ->
            ( model
            , Nats.publish "Wets.1" <| Wets.vesselPassedGate id
            , Cmd.none
            )

        FlowComplete id ->
            ( model
            , Nats.publish "Wets.1" <| Wets.flowEqualized id
            , Cmd.none
            )

        ActuatorMoveDone id ->
            ( model
            , Nats.publish "Wets.1" <| Wets.actuatorMoveDone id
            , Cmd.none
            )

        StartVessel direction ->
            let
                vessel : Vessel
                vessel =
                    newVessel direction

                license : String
                license =
                    Util.newVesselName model.vesselCount

                startState : TransitState
                startState =
                    vessel.sequence |> List.head |> Maybe.withDefault AtSea

                startVessel : Dict Id TransitState
                startVessel =
                    Animator.current model.vesselStates
                        |> Dict.insert license startState
            in
            ( { model
                | vesselCount = model.vesselCount + 1
                , vesselStates =
                    model.vesselStates
                        |> Animator.go Animator.immediately startVessel
                , activeVessels =
                    model.activeVessels
                        |> Dict.insert license
                            { vessel | sequence = List.drop 1 vessel.sequence }
                , message =
                    "Starting vessel \"" ++ license ++ "\""
              }
            , Nats.publish "Wets.1" <|
                Wets.newVessel license <|
                    Util.toString direction
            , Delay.after 100 <| MoveVessel license 1000
            )

        NatsMsg natsMsg ->
            let
                ( nats, natsCmd ) =
                    Nats.update natsConfig natsMsg model.nats
            in
            ( { model | nats = nats }
            , Nats.Effect.none
            , natsCmd
            )

        OnSocketEvent event ->
            ( { model
                | serverInfo =
                    case event of
                        Nats.Events.SocketOpen info ->
                            Just info

                        _ ->
                            Nothing
              }
            , Nats.Effect.none
            , Cmd.none
            )

        ReceiveProg data ->
            let
                ( new_model, cmd ) =
                    wetsHandler data model
            in
            ( new_model
            , Nats.Effect.none
            , cmd
            )


wetsHandler : String -> Model -> ( Model, Cmd Msg )
wetsHandler data model =
    case Wets.messageType data of
        Just Wets.MotorMsg ->
            case Decode.decodeString Wets.motorDecoder data of
                Ok cmd ->
                    handleMotor model cmd

                Err e ->
                    ( { model | message = Decode.errorToString e }
                    , Cmd.none
                    )

        Just Wets.FlowMsg ->
            case Decode.decodeString Wets.flowDecoder data of
                Ok cmd ->
                    handleFlow model cmd

                Err e ->
                    ( { model | message = Decode.errorToString e }
                    , Cmd.none
                    )

        Just Wets.VesselMsg ->
            case Decode.decodeString Wets.vesselDecoder data of
                Ok cmd ->
                    handleVessel model cmd

                Err e ->
                    ( { model | message = Decode.errorToString e }
                    , Cmd.none
                    )

        Nothing ->
            ( model, Cmd.none )


handleVessel : Model -> Wets.VesselCommand -> ( Model, Cmd Msg )
handleVessel model cmd =
    ( model
    , Delay.sequence
        [ ( 0, MoveVessel cmd.license 1000 )
        , ( 1000, VesselPassedGate cmd.license )
        ]
    )


flowTarget : TransitState -> Maybe ChamberFlow
flowTarget tstate =
    case tstate of
        ChamberHigh ->
            Just (ChamberFlow "Chamber-01" Low)

        ChamberLow ->
            Just (ChamberFlow "Chamber-01" High)

        _ ->
            Nothing


handleFlow : Model -> Wets.FlowCommand -> ( Model, Cmd Msg )
handleFlow model cmd =
    let
        setChamber : Id -> String -> Dict Id ChamberState
        setChamber id sensor =
            Dict.insert id
                (if sensor == "Sensor-F01" then
                    Low

                 else
                    High
                )
                (Animator.current model.chamberStates)

        vmoves :
            Id
            -> Maybe ChamberFlow
            -> List ( Int, Msg )
            -> List ( Int, Msg )
        vmoves vid cflow vlist =
            case cflow of
                Nothing ->
                    vlist

                Just _ ->
                    ( 0, MoveVessel vid 2000 ) :: vlist

        chamberMoves : List ( Int, Msg )
        chamberMoves =
            Animator.current model.vesselStates
                |> Dict.map (\_ v -> flowTarget v)
                |> Dict.foldl vmoves []
    in
    ( { model
        | chamberStates =
            model.chamberStates
                |> Animator.go (Animator.millis 2000)
                    (setChamber "Chamber-01" cmd.name)
      }
    , Delay.sequence <|
        List.append chamberMoves <|
            List.singleton ( 2000, FlowComplete cmd.name )
    )


handleMotor : Model -> Wets.MotorCommand -> ( Model, Cmd Msg )
handleMotor model cmd =
    let
        opAsState : String -> ActuatorState
        opAsState op =
            if op == "RUN_IN" then
                Closed

            else
                Opened

        setActuator : Id -> ActuatorState -> Dict Id ActuatorState
        setActuator id newState =
            Dict.insert id newState <|
                Animator.current model.actuatorStates

        actState : ActuatorState
        actState =
            opAsState cmd.operation
    in
    ( { model
        | actuatorStates =
            model.actuatorStates
                |> Animator.go (Animator.millis 1000)
                    (setActuator cmd.name actState)
      }
    , Delay.after 1000 <| ActuatorMoveDone cmd.name
    )


view : Model -> Browser.Document Msg
view model =
    { title = "Sim Proto"
    , body =
        [ UI.layout <|
            E.column
                [ E.paddingEach
                    { top = 40, right = 0, bottom = 0, left = 80 }
                ]
                [ E.row
                    [ E.spacing 20
                    , E.paddingEach { top = 0, right = 0, bottom = 0, left = 30 }
                    ]
                    [ Text.displayMedium "WETS"
                        |> Material.text UI.theme
                    ]
                , E.row
                    [ E.paddingEach
                        { top = 20, right = 0, bottom = 60, left = 20 }
                    , E.spacing 20
                    ]
                    [ startPanel
                    , E.el
                        [ E.width <| E.px 600
                        , E.height <| E.px 200
                        ]
                      <|
                        locks model
                    ]
                , E.row
                    [ E.paddingEach
                        { top = 0, right = 0, bottom = 0, left = 20 }
                    , E.spacing 20
                    ]
                    [ infoPanel model
                    , Text.bodyMedium model.message
                        |> Material.text UI.theme
                    ]
                ]
        ]
    }


locks : Model -> E.Element msg
locks model =
    Svg.svg
        [ SvgA.viewBox "0 0 600 200"
        , SvgA.width "600"
        , SvgA.height "200"
        ]
        (List.append
            [ Svg.rect
                [ SvgA.width "600"
                , SvgA.height "200"
                , SvgA.x "0"
                , SvgA.y "0"
                , SvgA.fill <| Color.toCssString Color.lightGray
                ]
                []
            , UI.chamber 0 40
            , animChamber "Chamber-01" model 200
            , UI.chamber 400 80
            , animGate "Gate-M02" model 194 34
            , UI.hub 200 170
            , animVane "Valve-M02" model 200 170
            , animGate "Gate-M01" model 394 34
            , UI.hub 400 170
            , animVane "Valve-M01" model 400 170
            ]
         <|
            allVessels model
        )
        |> E.html


startPanel : E.Element Msg
startPanel =
    let
        scheme : OUI.Material.Color.Scheme
        scheme =
            OUI.Material.Theme.colorscheme UI.theme
    in
    E.column
        [ Border.rounded 12
        , Border.color <|
            OUI.Material.Color.toElementColor scheme.outlineVariant
        , Border.width 1
        , Background.color <|
            OUI.Material.Color.toElementColor scheme.primaryContainer
        , E.padding 20
        , E.spacing 20
        , E.height E.fill
        ]
        [ "Start Vessel"
            |> Text.bodyMedium
            |> Material.text UI.theme
        , Button.new "Downstream"
            |> Button.onClick (StartVessel Util.Downstream)
            |> Material.button UI.theme []
        , Button.new "Upstream"
            |> Button.onClick (StartVessel Util.Upstream)
            |> Material.button UI.theme [ E.width E.fill ]
        ]


infoPanel : Model -> E.Element msg
infoPanel model =
    let
        isOnline : Bool
        isOnline =
            case model.serverInfo of
                Nothing ->
                    False

                Just _ ->
                    True

        panelAttr : List (E.Attribute msg)
        panelAttr =
            if isOnline then
                [ Background.color <| E.rgb255 0x1B 0x82 0x2F
                ]

            else
                [ Background.color <|
                    OUI.Material.Color.toElementColor scheme.errorContainer
                ]

        scheme : OUI.Material.Color.Scheme
        scheme =
            OUI.Material.Theme.colorscheme UI.theme
    in
    E.el
        ([ Border.rounded 10
         , Border.color <|
            OUI.Material.Color.toElementColor scheme.outlineVariant
         , Border.width 1
         , E.paddingEach { left = 18, top = 6, right = 10, bottom = 6 }
         , E.width <| E.px 100
         ]
            ++ panelAttr
        )
    <|
        Material.text UI.theme <|
            Text.bodyMedium <|
                if isOnline then
                    "Online"

                else
                    "Offline"


valveValue : ActuatorState -> Float
valveValue astate =
    case astate of
        Opened ->
            pi / 2.0

        Closed ->
            0.0


animVane : Id -> Model -> Int -> Int -> Svg msg
animVane id model x y =
    UI.vane x y <|
        Animator.linear model.actuatorStates <|
            \actuatorStates ->
                Animator.at <|
                    case Dict.get id actuatorStates of
                        Just astate ->
                            valveValue astate

                        Nothing ->
                            0.0


animChamber : Id -> Model -> Int -> Svg msg
animChamber id model xoffset =
    UI.chamber xoffset <|
        round <|
            Animator.linear model.chamberStates <|
                \chamberStates ->
                    Animator.at <|
                        case Dict.get id chamberStates of
                            Just cs ->
                                chamberDepth cs

                            Nothing ->
                                0.0


gateOpacity : ActuatorState -> Float
gateOpacity astate =
    case astate of
        Opened ->
            0.25

        Closed ->
            1.0


animGate : Id -> Model -> Int -> Int -> Svg msg
animGate id model x y =
    UI.gate x y <|
        Animator.linear model.actuatorStates <|
            \actuatorStates ->
                Animator.at <|
                    case Dict.get id actuatorStates of
                        Just gstate ->
                            gateOpacity gstate

                        Nothing ->
                            0.0


animVessel : Id -> Model -> Util.Direction -> Svg msg
animVessel id model direction =
    UI.vessel id direction <|
        Animator.xy model.vesselStates <|
            \vStates ->
                let
                    xypos : Util.Position
                    xypos =
                        Dict.get id vStates
                            |> Maybe.withDefault AtSea
                            |> toPosition
                in
                { x = Animator.at xypos.x
                , y =
                    Animator.at xypos.y
                        |> Animator.leaveSmoothly 0
                        |> Animator.arriveSmoothly 0
                }


allVessels : Model -> List (Svg msg)
allVessels model =
    model.activeVessels
        |> Dict.toList
        |> List.map
            (\t ->
                animVessel (Tuple.first t)
                    model
                    (Tuple.second t).direction
            )
