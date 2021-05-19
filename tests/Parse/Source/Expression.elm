module Parse.Source.Expression exposing (suite)

-- IMPORTS ---------------------------------------------------------------------

import Expect
import Fuzz exposing (..)
import Parser
import Ren.Data.Expression as Expression exposing (..)
import Ren.Data.Expression.Accessor exposing (..)
import Ren.Data.Expression.Identifier exposing (..)
import Ren.Data.Expression.Literal exposing (..)
import Ren.Data.Expression.Operator exposing (..)
import Ren.Data.Expression.Pattern exposing (..)
import Test exposing (..)



-- SUITES ----------------------------------------------------------------------


suite : Test
suite =
    describe "Expression parsing."
        [ shouldSucceed "f a b"
            (Application
                (local "f")
                [ local "a"
                , local "b"
                ]
            )
        , shouldSucceed "(f a) b"
            (Application
                (Application (local "f")
                    [ local "a" ]
                )
                [ local "b" ]
            )
        , shouldSucceed "a |> f"
            (Infix Pipe
                (local "a")
                (local "f")
            )
        , shouldSucceed "b |> f a"
            (Infix Pipe
                (local "b")
                (Application (local "f")
                    [ local "a" ]
                )
            )
        , shouldSucceed "if a then b else c"
            (Conditional
                (local "a")
                (local "b")
                (local "c")
            )
        , shouldSucceed "if f a then b else c"
            (Conditional
                (Application (local "f") [ local "a" ])
                (local "b")
                (local "c")
            )
        , shouldSucceed "if a then f b else c"
            (Conditional
                (local "a")
                (Application (local "f") [ local "b" ])
                (local "c")
            )
        ]



-- UTILS -----------------------------------------------------------------------


shouldSucceed : String -> Expression -> Test
shouldSucceed input expected =
    test input
        (\_ ->
            Parser.run Expression.parser input
                |> Expect.equal (Ok expected)
        )


shouldFail : String -> Test
shouldFail input =
    test input
        (\_ ->
            Parser.run Expression.parser input
                |> Expect.err
        )
