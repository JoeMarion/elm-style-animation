module Html.Animation (Animation, Action, init, update, render, animate, queue, stagger, on, props, delay, duration, easing, spring, andThen, forwardTo, forwardToAll, to, add, minus, stay, noWobble, gentle, wobbly, stiff, fastAndLoose, toColor, toRGB, toRGBA, toHSL, toHSLA, fromColor, rgb, rgba, hsl, hsla) where

{-| This library is for animating css properties and is meant to work well with elm-html.

The easiest way to get started with this library is to check out the examples that are included with the [source code](https://github.com/mdgriffith/elm-html-animation).

Once you have the basic structure of how to use this library, you can refer to this documentation to fill any gaps.


# Base Definitions
@docs Animation, Action

# Creating an animation
@docs animate, queue, stagger, props, delay, spring, duration, easing, andThen, on

# Animating Properties

These functions specify the value for a StyleProperty.

After taking an argument, these functions have `Float -> Float -> Float` as their signature.
This can be understood as `ExistingStyleValue -> CurrentTime -> NewStyleValue`, where CurrentTime is between 0 and 1.

@docs to, stay, add, minus

# Spring Presets
@docs noWobble, gentle, wobbly, stiff, fastAndLoose

# Animating Colors
@docs toColor, toRGB, toRGBA, toHSL, toHSLA

# Render a Animation into CSS
@docs render

# Setting the starting style
@docs init

# Initial Color Formats
@docs fromColor, rgb, rgba, hsl, hsla

# Update a Style
@docs update

# Managing a list of styled widgets
@docs forwardTo, forwardToAll

-}

import Effects exposing (Effects)
import Time exposing (Time, second)
import String exposing (concat)
import List
import Color
import Html.Animation.Properties exposing (..)
import Html.Animation.Render as Render
import Html.Animation.Spring as Spring
import Html.Animation.Core as Core



{-| An Animation of CSS properties.
-}
type Animation
  = A Core.Model





type alias KeyframeWithOptions =
  { frame : Core.StyleKeyframe
  , duration : Maybe Time
  , easing : Maybe (Float -> Float)
  , spring : Maybe Spring.Model
  }




{-| Actions to be run on an animation.
You won't be constructing using this type directly, though it may show up in your type signatures.

To start animations you'll be using the `animate`, `queue`, and `stagger` functions
-}
type alias PreAction =
  { frames : List KeyframeWithOptions
  , action : List Core.StyleKeyframe -> Core.Action
  }

type alias Dynamic = Core.Physics Core.DynamicTarget


type Action
  = Staggered (Float -> Action)
  | Unstaggered PreAction
  | Internal Core.Action





empty : Core.Model
empty =
  { elapsed = 0.0
  , start = Nothing
  , anim = []
  , previous = []
  }


emptyKeyframe : Core.StyleKeyframe
emptyKeyframe =
  { target = []
  , delay = 0.0
  }


emptyPhysics : a -> Core.Physics a
emptyPhysics target =
  { target = target
  , physical = 
        { position = 0
        , velocity = 0
        }
  , spring =
      { stiffness = noWobble.stiffness
      , damping = noWobble.damping
      , destination = 1
      }
  , easing = Nothing
  }

emptyKeyframeWithOptions =
  { frame = emptyKeyframe
  , duration = Nothing
  , easing = Nothing
  , spring = Nothing
  }



{-| Create an initial style for your init model.

__Note__ All properties that you animate must be present in the init or else that property won't be animated.

-}
init : Core.Style -> Animation
init sty =
  let
    deduped =
      List.foldr
        (\x acc ->
          if
            List.any
              (\y ->
                Render.id x
                  == Render.id y
                  && Render.name x
                  /= "transform"
              )
              acc
          then
            acc
          else
            x :: acc
        )
        []
        sty
  in
    A { empty | previous = deduped }





{-| A spring preset.  Probably should be your initial goto for using springs.
-}
noWobble : Spring.Model
noWobble =
  { stiffness = 170
  , damping = 26
  , destination = 1
  }


{-| A spring preset.
-}
gentle : Spring.Model
gentle =
  { stiffness = 120
  , damping = 14
  , destination = 1
  }


{-| A spring preset.
-}
wobbly : Spring.Model
wobbly =
  { stiffness = 180
  , damping = 12
  , destination = 1
  }


{-| A spring preset.
-}
stiff : Spring.Model
stiff =
  { stiffness = 210
  , damping = 20
  , destination = 1
  }


{-| A spring preset.
-}
fastAndLoose : Spring.Model
fastAndLoose =
  { stiffness = 320
  , damping = 17
  , destination = 1
  }


{-| Update an animation.  This will probably only show up once in your code.
See any of the examples at [https://github.com/mdgriffith/elm-html-animation](https://github.com/mdgriffith/elm-html-animation)
-}
update : Action -> Animation -> ( Animation, Effects Action )
update action (A model) =
  let
    ( newModel, fx ) =
      Core.update (resolve action 0) model
  in
    ( A newModel, Effects.map Internal fx )




--finalStyle : Style -> List Core.StyleKeyframe -> Style
--finalStyle style keyframes =
--                List.foldl
--                      (\frame st ->
--                        bakeFinal frame st
--                      ) style keyframes
--equivalentAnim : Style -> List Core.StyleKeyframe -> List Core.StyleKeyframe -> Bool
--equivalentAnim style frame1 frame2 =
--                        if List.length frame1 == 0 then
--                          False
--                        else
--                          let
--                            final1 = finalStyle style frame1
--                            final2 = finalStyle style frame2
--                          in
--                            final1 == final2



{-| Begin describing an animation.  This animation will cleanly interrupt any animation that is currently running.

      UI.animate
         |> UI.duration (0.4*second)
         |> UI.props
             [ UI.Left UI.Px (UI.to 0)
             , UI.Opacity (UI.to 1)
             ]
         |> UI.on model.style

-}
animate : Action
animate =
  Unstaggered
    <| { frames = []
       , action = Core.Interrupt
       }


{-| The same as `animate` but instead of interrupting the current animation, this will queue up after the current animation is finished.

      UI.queue
         |> UI.duration (0.4*second)
         |> UI.props
             [ UI.Left UI.Px (UI.to 0)
             , UI.Opacity (UI.to 1)
             ]
         |> UI.on model.style

-}
queue : Action
queue =
  Unstaggered
    <| { frames = []
       , action = Core.Queue
       }


{-| Can be used to stagger animations on a list of widgets.

     UI.stagger
        (\i ->
           UI.animate
             |> UI.delay (i * 0.05 * second) -- The delay is staggered based on list index
             |> UI.duration (0.3 * second)
             |> UI.props
                 [ UI.Left (UI.to 200) UI.Px
                 ]
          |> UI.andThen
             |> UI.delay (2.0 * second)
             |> UI.duration (0.3 * second)
             |> UI.props
                 [ UI.Left (UI.to -50) UI.Px
                 ]
        )
        |> forwardToAllWidgets model.widgets

-}
stagger : (Float -> Action) -> Action
stagger =
  Staggered


{-| Apply an update to a Animation model.  This is used at the end of constructing an animation.

     UI.animate
         |> UI.duration (0.4*second)
         |> UI.props
             [ UI.Left UI.Px (UI.to 0)
             , UI.Opacity (UI.to 1)
             ]
         |> UI.on model.style

-}
on : Animation -> Action -> ( Animation, Effects Action )
on model action =
  update action model


{-| Resolve the stagger if there is one, and apply springs if present.

-}
resolve : Action -> Int -> Core.Action
resolve stag i =
  let
    f =
      toFloat i
  in
    case stag of
      Unstaggered preaction ->
        preaction.action
          <| List.map
              applyKeyframeOptions
              preaction.frames

      Staggered s ->
        resolve (s f) i

      Internal ia ->
        ia


applyKeyframeOptions : KeyframeWithOptions -> Core.StyleKeyframe
applyKeyframeOptions options =
  let
    frame =
      options.frame

    applyOpt prop =
      let
        addOptions a =
          let
            newSpring =
              case options.spring of
                Nothing ->
                  a.spring

                Just partialSpring ->
                  let
                    oldSpring =
                      a.spring
                  in
                    { oldSpring
                      | stiffness = partialSpring.stiffness
                      , damping = partialSpring.damping
                    }
            newEasing = Core.emptyEasing


            withEase =
                Maybe.map 
                    (\ease ->
                        { newEasing | ease = ease }
                           

                    ) 
                    options.easing

            withDuration = 
              case options.duration of
                Nothing ->
                    withEase
                Just dur ->
                    case withEase of
                        Nothing ->
                            Just { newEasing | duration = dur }
                        Just ease ->
                            Just { ease | duration = dur }

          in
            { a | spring = newSpring
                , easing = withDuration }
      in
        Core.mapProp addOptions prop
  in
    { frame | target = List.map applyOpt frame.target }




{-| Can be used in place of `on`.  Instead of applying an update directly to a Animation model,
you can forward the update to a specific element in a list that has a Animation model.

To use this function, you'll need to supply a getter and a setter function for getting and setting the style model.

So, for a model like the following

    type alias Model = { widgets : List Widget }

    type alias Widget =
              { style : UI.Animation
              }
You'd probably want to create a specialized version of `forwardTo`.

    forwardToWidget = UI.forwardTo
                        .style -- widget style getter
                        (\w style -> { w | style = style }) -- widget style setter

Which you can then use to apply an animation to a widget in a list.

    (widgets, fx) =
            UI.animate
                |> UI.duration (5*second)
                |> UI.props
                    [ UI.Opacity (UI.to 0)
                    ]
                |> forwardToWidget i model.widgets
                -- Where i is the index of the widget to update.

-}
forwardTo : (Int -> Action -> b) -> (a -> Animation) -> (a -> Animation -> a) -> Int -> List a -> Action -> ( List a, Effects b )
forwardTo toInternalAction styleGet styleSet i widgets action =
  let
    ( widgets, effects ) =
      List.unzip
        <| List.indexedMap
            (\j widget ->
              if j == i then
                let
                  (A anim) = styleGet widget
                  ( newStyle, fx ) =
                    Core.update
                      (resolve action i)
                      anim
                in
                  ( styleSet widget (A newStyle)
                  , Effects.map
                      (\a -> toInternalAction i (Internal a))
                      fx
                  )
              else
                ( widget, Effects.none )
            )
            widgets
  in
    ( widgets, Effects.batch effects )


{-| Same as `forwardTo`, except it applies an update to every member of the list.

-}
forwardToAll : (Int -> Action -> b) -> (a -> Animation) -> (a -> Animation -> a) -> List a -> Action -> ( List a, Effects b )
forwardToAll toInternalAction styleGet styleSet widgets action =
  let
    --largestDuration = List.map
    --                      (\i ->
    --                        case resolve action i of
    --                          Queue frames -> getFullDuration frames
    --                          Interrupt frames -> getFullDuration frames
    --                          _ -> 0.0
    --                      )
    --                      [1..List.length widgets]
    --                |> List.maximum
    --                |> Maybe.withDefault 0.0
    ( widgets, effects ) =
      List.unzip
        <| List.indexedMap
            (\i widget ->
              let
                (A anim) = styleGet widget
                ( newStyle, fx ) =
                  Core.update
                    --(normalizedDuration largestDuration (resolve action i))
                    (resolve action i)
                    anim
                    
              in
                ( styleSet widget (A newStyle)
                , Effects.map
                    (\a -> toInternalAction i (Internal a))
                    fx
                )
            )
            widgets
  in
    ( widgets, Effects.batch effects )



--normalizedDuration : Time -> InternalAction -> InternalAction
--normalizedDuration desiredDuration action =
--                            case action of
--                                Queue frames ->
--                                    Queue <| addBufferDuration frames desiredDuration
--                                Interrupt frames ->
--                                    Interrupt <| addBufferDuration frames desiredDuration
--                                _ -> action


{-| Adds a blank keyframe with a duration that makes the keyframes fill all the time until Time.

-}



--addBufferDuration : List Core.StyleKeyframe -> Time -> List Core.StyleKeyframe
--addBufferDuration frames desiredDuration =
--                let
--                  dur = getFullDuration frames
--                  delta = desiredDuration - dur
--                in
--                  if dur >= desiredDuration then
--                    frames
--                  else
--                    frames ++ [{ emptyKeyframe | duration = delta }]


{-|
-}



--getFullDuration : List Core.StyleKeyframe -> Time
--getFullDuration frames =
--                    List.foldl
--                        (\frame total ->
--                            total + frame.delay + frame.duration
--                        )
--                        0 frames


{-| Specify the properties that should be animated

     UI.animate
         |> UI.duration (0.4*second)
         |> UI.props
             [ UI.Left UI.Px (UI.to 0)
             , UI.Opacity (UI.to 1)
             ]
         |> UI.on model.style

-}
props : List (StyleProperty Dynamic) -> Action -> Action
props p action =
  updateOrCreate
    action
    (\a ->
      let
        frame =
          a.frame

        updatedFrame =
          { frame | target = p }
      in
        { a | frame = updatedFrame }
    )


{-| Specify a duration.  If not specified, the default is 350ms.

   UI.animate
         |> UI.duration (0.4*second)
         |> UI.props
             [ UI.Left UI.Px (UI.to 0)
             , UI.Opacity (UI.to 1)
             ]
         |> UI.on model.style
-}
duration : Time -> Action -> Action
duration dur action =
  updateOrCreate action (\a -> { a | duration = Just dur })


{-| Specify a delay.  If not specified, the default is 0.

   UI.animate
         |> UI.duration (0.4*second)
         |> UI.delay (0.5*second)
         |> UI.props
             [ UI.Left UI.Px (UI.to 0)
             , UI.Opacity (UI.to 1)
             ]
         |> UI.on model.style
-}
delay : Time -> Action -> Action
delay delay action =
  updateOrCreate
    action
    (\a ->
      let
        frame =
          a.frame

        updatedFrame =
          { frame | delay = delay }
      in
        { a | frame = updatedFrame }
    )


{-| Specify an easing function.  It is expected that values should match up at the beginning and end.  So, f 0 == 0 and f 1 == 1.  The default easing is sinusoidal
in-out.

-}
easing : (Float -> Float) -> Action -> Action
easing ease action =
  updateOrCreate action (\a -> { a | easing = Just ease })


{-| Animate based on spring physics.  You'll need to provide both a stiffness and a dampness to this function.


__Note:__ This will cause both `duration` and `easing` to be ignored as they are now controlled by the spring.

   UI.animate
         |> UI.spring UI.noWobble
         |> UI.props
             [ UI.Left UI.Px (UI.to 0)
             , UI.Opacity (UI.to 1)
             ]
         |> UI.on model.style
-}
spring : Spring.Model -> Action -> Action
spring spring action =
  updateOrCreate action (\a -> { a | spring = Just spring })


{-| Append another keyframe.  This is used for multistage animations.  For example, to cycle through colors, we'd use the following:

      UI.animate
              |> UI.props
                  [ UI.BackgroundColor
                        UI.toRGBA 100 100 100 1.0
                  ]
          |> UI.andThen -- create a new keyframe
              |> UI.duration (1*second)
              |> UI.props
                  [ UI.BackgroundColor
                        UI.toRGBA 178 201 14 1.0
                  ]
          |> UI.andThen
              |> UI.props
                  [ UI.BackgroundColor
                        UI.toRGBA 58 40 69 1.0
                  ]
          |> UI.on model.style
-}
andThen : Action -> Action
andThen stag =
  case stag of
    Internal ia ->
      Internal ia

    Staggered s ->
      Staggered s

    Unstaggered preaction ->
      Unstaggered
        <| { preaction | frames = preaction.frames ++ [ emptyKeyframeWithOptions ] }


{-| Update the last Core.StyleKeyframe in the queue.  If the queue is empty, create a new Core.StyleKeyframe and update that.
-}
updateOrCreate : Action -> (KeyframeWithOptions -> KeyframeWithOptions) -> Action
updateOrCreate action fn =
  case action of
    Internal ia ->
      Internal ia

    Staggered s ->
      Staggered s

    Unstaggered preaction ->
      Unstaggered
        <| { preaction
            | frames =
                case List.reverse preaction.frames of
                  [] ->
                    [ fn emptyKeyframeWithOptions ]

                  cur :: rem ->
                    List.reverse ((fn cur) :: rem)
           }


{-| Animate a StyleProperty to a value.

-}
to : Float -> Dynamic
to target =
  emptyPhysics
    <| (\from current -> ((target - from) * current) + from)


{-| Animate a StyleProperty by adding to its existing value

-}
add : Float -> Dynamic
add target =
  emptyPhysics
    <| (\from current -> ((target - from) * current) + from)


{-| Animate a StyleProperty by subtracting to its existing value

-}
minus : Float -> Dynamic
minus target =
  emptyPhysics
    <| (\from current -> ((target - from) * current) + from)


{-| Keep an animation where it is!  This is useful for stacking transforms.

-}
stay : Float -> Dynamic
stay target =
  emptyPhysics
    <| (\from current -> from)


type alias ColorProperty =
  Dynamic -> Dynamic -> Dynamic -> Dynamic -> StyleProperty Dynamic


{-| Animate a color-based property, given a color from the Color elm module.

-}
toColor : Color.Color -> ColorProperty -> StyleProperty Dynamic
toColor color almostColor =
  let
    rgba =
      Color.toRgb color
  in
    almostColor
      (to <| toFloat rgba.red)
      (to <| toFloat rgba.green)
      (to <| toFloat rgba.blue)
      (to rgba.alpha)


{-| Animate a color-based style property to an rgb color.  Note: this leaves the alpha channel where it is.

     UI.animate
            |> UI.props
                [ UI.BackgroundColor
                      UI.toRGB 100 100 100
                ]
            |> UI.on model.style

-}
toRGB : Float -> Float -> Float -> ColorProperty -> StyleProperty Dynamic
toRGB r g b prop =
  prop (to r) (to g) (to b) (to 1.0)


{-| Animate a color-based style property to an rgba color.

       UI.animate
            |> UI.props
                [ UI.BackgroundColor
                      UI.toRGBA 100 100 100 1.0
                ]
            |> UI.on model.style


-}
toRGBA : Float -> Float -> Float -> Float -> ColorProperty -> StyleProperty Dynamic
toRGBA r g b a prop =
  prop (to r) (to g) (to b) (to a)


{-| Animate a color-based style property to an hsl color. Note: this leaves the alpha channel where it is.

-}
toHSL : Float -> Float -> Float -> ColorProperty -> StyleProperty Dynamic
toHSL h s l prop =
  let
    rgba =
      Color.toRgb <| Color.hsl h s l
  in
    prop
      (to <| toFloat rgba.red)
      (to <| toFloat rgba.green)
      (to <| toFloat rgba.blue)
      (to rgba.alpha)


{-| Animate a color-based style property to an hsla color.

-}
toHSLA : Float -> Float -> Float -> Float -> ColorProperty -> StyleProperty Dynamic
toHSLA h s l a prop =
  let
    rgba =
      Color.toRgb <| Color.hsl h s l
  in
    prop
      (to <| toFloat rgba.red)
      (to <| toFloat rgba.green)
      (to <| toFloat rgba.blue)
      (to rgba.alpha)


{-| Fade a color to a specific alpha level

-}



--fade : Float -> ColorProperty -> StyleProperty (Physics DynamicTarget)
--fade alpha prop =
--    prop stay stay stay (to alpha)


{-| Specify an initial Color-based property using a Color from the elm core Color module.

-}
fromColor : Color.Color -> (Static -> Static -> Static -> Static -> StyleProperty Static) -> StyleProperty Static
fromColor color almostColor =
  let
    rgba =
      Color.toRgb color
  in
    almostColor
      (toFloat rgba.red)
      (toFloat rgba.green)
      (toFloat rgba.blue)
      (rgba.alpha)


{-| Specify an initial Color-based property using rgb

-}
rgb : Float -> Float -> Float -> (Static -> Static -> Static -> Static -> StyleProperty Static) -> StyleProperty Static
rgb r g b prop =
  prop r g b 1.0


{-| Specify an initial Color-based property using rgba

-}
rgba : Float -> Float -> Float -> Float -> (Static -> Static -> Static -> Static -> StyleProperty Static) -> StyleProperty Static
rgba r g b a prop =
  prop r g b a


{-| Specify an initial Color-based property using hsl

-}
hsl : Float -> Float -> Float -> (Static -> Static -> Static -> Static -> StyleProperty Static) -> StyleProperty Static
hsl h s l prop =
  let
    rgba =
      Color.toRgb <| Color.hsl h s l
  in
    prop
      (toFloat rgba.red)
      (toFloat rgba.blue)
      (toFloat rgba.green)
      rgba.alpha


{-| Specify an initial Color-based property using hsla

-}
hsla : Float -> Float -> Float -> Float -> (Static -> Static -> Static -> Static -> StyleProperty Static) -> StyleProperty Static
hsla h s l a prop =
  let
    rgba =
      Color.toRgb <| Color.hsla h s l a
  in
    prop
      (toFloat rgba.red)
      (toFloat rgba.blue)
      (toFloat rgba.green)
      rgba.alpha


{-| Render into concrete css that can be directly applied to 'style' in elm-html

    div [ style (UI.render widget.style) ] [ ]

-}
render : Animation -> List ( String, String )
render (A model) =
  let
    currentAnim =
      List.head model.anim
  in
    case currentAnim of
      Nothing ->
        let
          rendered =
            List.map renderProp model.previous

          transformsNprops =
            List.partition (\( name, _ ) -> name == "transform") rendered

          combinedTransforms =
            ( "transform"
            , String.concat
                (List.intersperse
                  " "
                  (List.map (snd) (fst transformsNprops))
                )
            )
        in
          snd transformsNprops ++ [ combinedTransforms ]

      Just anim ->
        -- Combine all transform properties
        let
          baked =
            Core.bake anim model.previous

          rendered =
            List.map renderProp baked

          transformsNprops =
            List.partition (\s -> fst s == "transform") rendered

          combinedTransforms =
            ( "transform"
            , String.concat
                (List.intersperse
                  " "
                  (List.map (snd) (fst transformsNprops))
                )
            )
        in
          snd transformsNprops ++ [ combinedTransforms ]


renderProp : StyleProperty Static -> ( String, String )
renderProp prop =
  ( Render.name prop
  , Render.value prop
  )


--bakeFinal : Core.StyleKeyframe -> Style -> Style
--bakeFinal frame style = style



-- Update




