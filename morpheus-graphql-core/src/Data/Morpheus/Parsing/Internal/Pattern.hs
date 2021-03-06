{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Data.Morpheus.Parsing.Internal.Pattern
  ( inputValueDefinition,
    fieldsDefinition,
    typeDeclaration,
    optionalDirectives,
    enumValueDefinition,
    inputFieldsDefinition,
    parseOperationType,
    argumentsDefinition,
    parseDirectiveLocation,
  )
where

import Data.Functor (($>))
-- MORPHEUS
import Data.Morpheus.Parsing.Internal.Arguments
  ( maybeArguments,
  )
import Data.Morpheus.Parsing.Internal.Internal
  ( Parser,
    getLocation,
  )
import Data.Morpheus.Parsing.Internal.Terms
  ( ignoredTokens,
    keyword,
    optDescription,
    parseName,
    parseType,
    parseTypeName,
    setOf,
    symbol,
    uniqTuple,
  )
import Data.Morpheus.Parsing.Internal.Value
  ( Parse (..),
    parseDefaultValue,
  )
import Data.Morpheus.Types.Internal.AST
  ( ArgumentsDefinition (..),
    DataEnumValue (..),
    Directive (..),
    DirectiveLocation (..),
    FieldContent (..),
    FieldDefinition (..),
    FieldName,
    FieldsDefinition,
    IN,
    InputFieldsDefinition,
    OUT,
    OperationType (..),
    TypeName,
    Value,
  )
import Data.Text (pack)
import Text.Megaparsec
  ( (<|>),
    choice,
    label,
    many,
    optional,
  )
import Text.Megaparsec.Char (string)

--  EnumValueDefinition: https://graphql.github.io/graphql-spec/June2018/#EnumValueDefinition
--
--  EnumValueDefinition
--    Description(opt) EnumValue Directives(Const)(opt)
--
enumValueDefinition ::
  Parse (Value s) =>
  Parser (DataEnumValue s)
enumValueDefinition = label "EnumValueDefinition" $ do
  enumDescription <- optDescription
  enumName <- parseTypeName
  enumDirectives <- optionalDirectives
  return DataEnumValue {..}

-- InputValue : https://graphql.github.io/graphql-spec/June2018/#InputValueDefinition
--
-- InputValueDefinition
--   Description(opt) Name : Type DefaultValue(opt) Directives (Const)(opt)
--
inputValueDefinition ::
  Parse (Value s) =>
  Parser (FieldDefinition IN s)
inputValueDefinition = label "InputValueDefinition" $ do
  fieldDescription <- optDescription
  fieldName <- parseName
  symbol ':'
  fieldType <- parseType
  fieldContent <- optional (DefaultInputValue <$> parseDefaultValue)
  fieldDirectives <- optionalDirectives
  pure FieldDefinition {..}

-- Field Arguments: https://graphql.github.io/graphql-spec/June2018/#sec-Field-Arguments
--
-- ArgumentsDefinition:
--   ( InputValueDefinition(list) )
--
argumentsDefinition ::
  Parse (Value s) =>
  Parser (ArgumentsDefinition s)
argumentsDefinition =
  label "ArgumentsDefinition" $
    uniqTuple inputValueDefinition

--  FieldsDefinition : https://graphql.github.io/graphql-spec/June2018/#FieldsDefinition
--
--  FieldsDefinition :
--    { FieldDefinition(list) }
--
fieldsDefinition ::
  Parse (Value s) =>
  Parser (FieldsDefinition OUT s)
fieldsDefinition = label "FieldsDefinition" $ setOf fieldDefinition

--  FieldDefinition
--    Description(opt) Name ArgumentsDefinition(opt) : Type Directives(Const)(opt)
--
fieldDefinition :: Parse (Value s) => Parser (FieldDefinition OUT s)
fieldDefinition = label "FieldDefinition" $ do
  fieldDescription <- optDescription
  fieldName <- parseName
  fieldContent <- optional (FieldArgs <$> argumentsDefinition)
  symbol ':'
  fieldType <- parseType
  fieldDirectives <- optionalDirectives
  pure FieldDefinition {..}

-- InputFieldsDefinition : https://graphql.github.io/graphql-spec/June2018/#sec-Language.Directives
--   InputFieldsDefinition:
--     { InputValueDefinition(list) }
--
inputFieldsDefinition ::
  Parse (Value s) =>
  Parser (InputFieldsDefinition s)
inputFieldsDefinition = label "InputFieldsDefinition" $ setOf inputValueDefinition

-- Directives : https://graphql.github.io/graphql-spec/June2018/#sec-Language.Directives
--
-- example: @directive ( arg1: "value" , .... )
--
-- Directives[Const]
-- Directive[Const](list)
--
optionalDirectives :: Parse (Value s) => Parser [Directive s]
optionalDirectives = label "Directives" $ many directive

-- Directive[Const]
--
-- @ Name Arguments[Const](opt)
directive :: Parse (Value s) => Parser (Directive s)
directive = label "Directive" $ do
  directivePosition <- getLocation
  symbol '@'
  directiveName <- parseName
  directiveArgs <- maybeArguments
  pure Directive {..}

-- typDeclaration : Not in spec ,start part of type definitions
--
--  typDeclaration
--   Description(opt) scalar Name
--
typeDeclaration :: FieldName -> Parser TypeName
typeDeclaration kind = do
  keyword kind
  parseTypeName

parseOperationType :: Parser OperationType
parseOperationType = label "OperationType" $ do
  kind <-
    (string "query" $> Query)
      <|> (string "mutation" $> Mutation)
      <|> (string "subscription" $> Subscription)
  ignoredTokens
  return kind

parseDirectiveLocation :: Parser DirectiveLocation
parseDirectiveLocation =
  label
    "DirectiveLocation"
    ( choice $
        toKeyword
          <$> [ FIELD_DEFINITION,
                FRAGMENT_DEFINITION,
                FRAGMENT_SPREAD,
                INLINE_FRAGMENT,
                ARGUMENT_DEFINITION,
                INTERFACE,
                ENUM_VALUE,
                INPUT_OBJECT,
                INPUT_FIELD_DEFINITION,
                SCHEMA,
                SCALAR,
                OBJECT,
                QUERY,
                MUTATION,
                SUBSCRIPTION,
                UNION,
                ENUM,
                FIELD
              ]
    )
    <* ignoredTokens

toKeyword :: Show a => a -> Parser a
toKeyword x = string (pack $ show x) $> x
