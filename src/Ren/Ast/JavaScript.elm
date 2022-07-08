module Ren.Ast.JavaScript exposing (..)

{-| -}

-- IMPORTS ---------------------------------------------------------------------

import Ren.Ast.Core as Core
import Ren.Ast.Expr as Expr exposing (Expr)
import Util.List as List



-- TYPES -----------------------------------------------------------------------


type Statement
    = Block (List Statement)
    | Comment String
    | Const String Expression
    | Expr Expression
    | If Expression Statement (Maybe Statement)
    | Return Expression
    | Throw String


type Expression
    = Access Expression (List String)
    | Add Expression Expression
    | And Expression Expression
    | Array (List Expression)
    | Arrow String Statement
    | Bool Bool
    | Call Expression (List Expression)
    | Div Expression Expression
    | Eq Expression Expression
    | Gt Expression Expression
    | Gte Expression Expression
    | IIFE (Maybe ( String, Expression )) Statement
    | Index Expression Expression
    | Lt Expression Expression
    | Lte Expression Expression
    | Mod Expression Expression
    | Mul Expression Expression
    | Neq Expression Expression
    | Number Float
    | Or Expression Expression
    | Spread Expression
    | String String
    | Sub Expression Expression
    | Typeof Expression
    | Undefined
    | Var String



-- CONSTANTS -------------------------------------------------------------------
-- CONSTRUCTORS ----------------------------------------------------------------


fromExpr : Expr -> Statement
fromExpr =
    let
        go exprF =
            case exprF of
                Core.EAbs arg (Expr (IIFE (Just ( name, expr )) (Block body))) ->
                    Expr <| Arrow arg (return <| Block <| Const name expr :: body)

                Core.EAbs arg (Expr (IIFE (Just ( name, expr )) body)) ->
                    Expr <| Arrow arg (return <| Block [ Const name expr, body ])

                Core.EAbs arg (Expr (IIFE Nothing body)) ->
                    Expr <| Arrow arg (return body)

                Core.EAbs arg body ->
                    Expr <| Arrow arg (return body)

                Core.EApp (Expr (Call (Var "<access>") [ String key ])) stmt ->
                    case expression stmt of
                        Just expr ->
                            Expr <| Access expr [ key ]

                        Nothing ->
                            Throw "[I"

                Core.EApp (Expr (Call (Var "<binop>") [ String op, lhs ])) stmt ->
                    case ( Expr.operatorFromName op, expression stmt ) of
                        ( Just operator, Just rhs ) ->
                            Expr <| fromOperator operator lhs rhs

                        _ ->
                            Comment "TODO: handle binop with non-expr arg"

                Core.EApp (Expr (Call fun args)) (Expr arg) ->
                    Expr <| Call fun (args ++ [ arg ])

                Core.EApp (Expr fun) (Expr arg) ->
                    Expr <| Call fun [ arg ]

                Core.EApp fun arg ->
                    Block [ fun, arg ]

                Core.ELet "" expr (Block body) ->
                    Block <| expr :: body

                Core.ELet "" expr body ->
                    Block [ expr, body ]

                Core.ELet name stmt (Block body) ->
                    case expression stmt of
                        Just expr ->
                            Block <| Const name expr :: body

                        Nothing ->
                            Block body

                Core.ELet name stmt body ->
                    case expression stmt of
                        Just expr ->
                            Block [ Const name expr, body ]

                        Nothing ->
                            body

                Core.ELit (Core.LArr elements) ->
                    Expr <| Array <| List.filterMap expression elements

                Core.ELit (Core.LBool b) ->
                    Expr <| Bool b

                Core.ELit (Core.LCon tag args) ->
                    Expr <| Array <| String tag :: List.filterMap expression args

                Core.ELit (Core.LNum n) ->
                    Expr <| Number n

                Core.ELit (Core.LRec fields) ->
                    Debug.todo ""

                Core.ELit (Core.LStr s) ->
                    Expr <| String s

                Core.ELit Core.LUnit ->
                    Expr Undefined

                Core.EVar name ->
                    Expr <| Var name

                Core.EPat (Expr expr) cases ->
                    let
                        branchFromCase ( pattern, guard, body ) =
                            If (checksFromPattern (Var "$pat") pattern)
                                (case guard of
                                    Just (Expr g) ->
                                        Block <|
                                            List.concat
                                                [ assignmentsFromPattern (Var "$pat") pattern
                                                , [ If g (return body) Nothing ]
                                                ]

                                    _ ->
                                        return <|
                                            Block <|
                                                List.concat
                                                    [ assignmentsFromPattern (Var "$pat") pattern
                                                    , [ body ]
                                                    ]
                                )
                                Nothing
                    in
                    [ Throw "Non-exhaustive pattern match" ]
                        |> (++) (List.map (return << branchFromCase) cases)
                        |> Block
                        |> IIFE (Just ( "$pat", expr ))
                        |> Expr

                Core.EPat _ _ ->
                    Debug.todo ""
    in
    Expr.lower >> Core.fold go


fromOperator : Expr.Operator -> Expression -> Expression -> Expression
fromOperator op lhs rhs =
    case op of
        Expr.Add ->
            Add lhs rhs

        Expr.And ->
            And lhs rhs

        Expr.Concat ->
            Array [ Spread lhs, Spread rhs ]

        Expr.Cons ->
            Array [ lhs, Spread rhs ]

        Expr.Div ->
            Div lhs rhs

        Expr.Eq ->
            Eq lhs rhs

        Expr.Gte ->
            Gte lhs rhs

        Expr.Gt ->
            Gt lhs rhs

        Expr.Lte ->
            Lte lhs rhs

        Expr.Lt ->
            Lt lhs rhs

        Expr.Mod ->
            Mod lhs rhs

        Expr.Mul ->
            Mul lhs rhs

        Expr.Neq ->
            Neq lhs rhs

        Expr.Or ->
            Or lhs rhs

        Expr.Sub ->
            Sub lhs rhs


checksFromPattern : Expression -> Core.Pattern -> Expression
checksFromPattern expr pattern =
    case pattern of
        Core.PAny ->
            Bool True

        Core.PLit (Core.LArr elements) ->
            elements
                |> List.indexedMap (\i el -> checksFromPattern (Index expr <| Number <| Basics.toFloat i) el)
                -- Patterns like the wildcard `_` are always just true. This is
                -- necessary to handle top-level patterns that match on anything
                -- but once we're inside a container like an array we can just
                -- remove these checks altogether.
                |> List.filter ((/=) (Bool True))
                -- We also want to check the length of the array, if it's not long
                -- enough to satisfy all the other patterns, there's no point trying
                -- any of them!
                |> (::) (Gte (Access expr [ "length" ]) (Number <| Basics.toFloat <| List.length elements))
                -- Finally, we'll do a runtime type check to confirm the value
                -- actually *is* an array. In JavaScript doing `typeof arr` will
                -- (perhaps unintuitively) return `"object"` for arrays, so we
                -- need to call a method on the global `Array` object instead.
                |> List.foldl (\y x -> And x y) (Call (Access (Var "globalThis") [ "Array", "isArray" ]) [ expr ])

        Core.PLit (Core.LBool b) ->
            Eq expr <| Bool b

        Core.PLit (Core.LCon tag args) ->
            -- Variants are represented as arrays at runtime, where the first
            -- element is the tag and the rest are any arguments.
            checksFromPattern expr <| Core.PLit <| Core.LArr <| (Core.PLit (Core.LStr tag) :: args)

        Core.PLit (Core.LNum n) ->
            Eq expr <| Number n

        Core.PLit (Core.LRec fields) ->
            fields
                |> List.map (\( k, v ) -> checksFromPattern (Access expr [ k ]) v)
                -- As with arrays, we can safely remove checks that will always
                -- succeed.
                |> List.filter ((/=) (Bool True))
                |> List.foldl (\y x -> And x y) (Eq (Typeof expr) (String "object"))

        Core.PLit (Core.LStr s) ->
            Eq expr <| String s

        Core.PLit Core.LUnit ->
            Eq expr Undefined

        Core.PTyp "Array" pat ->
            And
                (Call (Access (Var "Array") [ "isArray" ]) [ expr ])
                (checksFromPattern expr pat)

        Core.PTyp type_ pat ->
            And
                (Or
                    (Eq (Typeof expr) (String type_))
                    (Eq (Access expr [ "constructor", "name" ]) (String type_))
                )
                (checksFromPattern expr pat)

        Core.PVar _ ->
            Bool True


assignmentsFromPattern : Expression -> Core.Pattern -> List Statement
assignmentsFromPattern expr pattern =
    case pattern of
        Core.PAny ->
            []

        Core.PLit (Core.LArr elements) ->
            elements
                |> List.indexedMap (\i el -> assignmentsFromPattern (Index expr <| Number <| Basics.toFloat i) el)
                |> List.concat

        Core.PLit (Core.LBool b) ->
            []

        Core.PLit (Core.LCon _ args) ->
            assignmentsFromPattern expr <| Core.PLit <| Core.LArr <| Core.PAny :: args

        Core.PLit (Core.LNum n) ->
            []

        Core.PLit (Core.LRec fields) ->
            fields
                |> List.concatMap (\( k, v ) -> assignmentsFromPattern (Access expr [ k ]) v)

        Core.PLit (Core.LStr s) ->
            []

        Core.PLit Core.LUnit ->
            []

        Core.PTyp tag pat ->
            Debug.todo ""

        Core.PVar name ->
            [ Const name expr ]



-- QUERIES ---------------------------------------------------------------------
-- MANIPULATIONS ---------------------------------------------------------------


return : Statement -> Statement
return stmt =
    case stmt of
        Block stmts ->
            Block <| returnLast stmts

        Comment str ->
            Comment str

        Const _ expr ->
            Return expr

        Expr expr ->
            Return expr

        If cond then_ else_ ->
            If cond (return then_) (Maybe.map return else_)

        Return expr ->
            Return expr

        Throw error ->
            Throw error


returnLast : List Statement -> List Statement
returnLast stmts =
    case List.reverse stmts of
        stmt :: rest ->
            List.reverse <| return stmt :: rest

        [] ->
            []



-- CONVERSIONS -----------------------------------------------------------------


expression : Statement -> Maybe Expression
expression stmt =
    case stmt of
        Expr expr ->
            Just expr

        _ ->
            Nothing



-- UTILS -----------------------------------------------------------------------
