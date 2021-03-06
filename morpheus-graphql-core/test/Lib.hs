{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE NoImplicitPrelude #-}

module Lib
  ( getGQLBody,
    expectedResponse,
    getCases,
    maybeVariables,
    readSource,
    scanSchemaTests,
    FileUrl (..),
    CaseTree (..),
    toString,
    getRequest,
    assertValidSchema,
    getSchema,
    getResolvers,
  )
where

import Control.Applicative ((<|>), pure)
import Control.Monad ((>=>), Monad)
import Data.Aeson (FromJSON, Value (..), decode)
import qualified Data.ByteString.Lazy as L (readFile)
import Data.ByteString.Lazy.Char8 (ByteString)
import Data.Either (Either (..))
import Data.Foldable (foldl)
import Data.Functor ((<$>))
import Data.HashMap.Lazy (lookup)
import Data.Maybe (Maybe (..), fromMaybe, maybe)
import Data.Morpheus.Core (parseGQLDocument)
import Data.Morpheus.Types.IO
  ( GQLRequest (..),
  )
import Data.Morpheus.Types.Internal.AST (FieldName (..), Schema (..), VALID)
import Data.Morpheus.Types.Internal.Resolving
  ( Eventless,
    ResModel,
    RootResModel (..),
    WithOperation,
    mkNull,
    mkValue,
    resultOr,
  )
import Data.Semigroup ((<>))
import Data.Text (Text, unpack)
import qualified Data.Text.Lazy as LT (toStrict)
import Data.Text.Lazy.Encoding (decodeUtf8)
import Data.Traversable (traverse)
import System.Directory (doesDirectoryExist, listDirectory)
import Test.Tasty.HUnit
  ( assertFailure,
  )
import Prelude
  ( ($),
    (.),
    Bool,
    FilePath,
    IO,
    Show,
    and,
    map,
    show,
  )

readSource :: FieldName -> IO ByteString
readSource = L.readFile . path . readName

path :: Text -> FilePath
path name = "test/" <> unpack name

gqlLib :: Text -> FilePath
gqlLib x = path x <> "/query.gql"

resLib :: Text -> FilePath
resLib x = path x <> "/response.json"

data FileUrl = FileUrl
  { filePath :: [FilePath],
    fileName :: FilePath
  }
  deriving (Show)

data CaseTree = CaseTree
  { caseUrl :: FileUrl,
    children :: Either [FilePath] [CaseTree]
  }
  deriving (Show)

prefix :: FileUrl -> FilePath -> FileUrl
prefix FileUrl {..} x =
  FileUrl
    { filePath = fileName : filePath,
      fileName = x
    }

toString :: FileUrl -> FilePath
toString FileUrl {..} = foldl (\y x -> x <> "/" <> y) fileName filePath

scanSchemaTests :: FilePath -> IO CaseTree
scanSchemaTests = deepScan

deepScan :: FilePath -> IO CaseTree
deepScan = shouldScan . FileUrl []
  where
    shouldScan :: FileUrl -> IO CaseTree
    shouldScan caseUrl = do
      children <- prefixed caseUrl
      pure CaseTree {..}
    isDirectory :: FileUrl -> IO Bool
    isDirectory = doesDirectoryExist . toString
    prefixed :: FileUrl -> IO (Either [FilePath] [CaseTree])
    prefixed p = do
      dir <- isDirectory p
      if dir
        then do
          list <- map (prefix p) <$> listDirectory (toString p)
          areDirectories <- traverse isDirectory list
          if and areDirectories
            then Right <$> traverse shouldScan list
            else pure $ Left []
        else pure $ Left []

maybeVariables :: FieldName -> IO (Maybe Value)
maybeVariables (FieldName x) = decode <$> (L.readFile (path x <> "/variables.json") <|> pure "{}")

getGQLBody :: FieldName -> IO ByteString
getGQLBody (FieldName p) = L.readFile (gqlLib p)

getCases :: FromJSON a => FilePath -> IO [a]
getCases dir = fromMaybe [] . decode <$> L.readFile ("test/" <> dir <> "/cases.json")

getSchema :: FieldName -> IO (Eventless (Schema VALID))
getSchema (FieldName x) = parseGQLDocument <$> L.readFile (path x <> "/schema.gql")

assertValidSchema :: FieldName -> IO (Schema VALID)
assertValidSchema = getSchema >=> resultOr failedSchema pure
  where
    failedSchema err = assertFailure ("unexpected schema validation error: \n " <> show err)

expectedResponse :: FieldName -> IO Value
expectedResponse (FieldName p) = fromMaybe Null . decode <$> L.readFile (resLib p)

getRequest :: FieldName -> IO GQLRequest
getRequest p = do
  queryBS <- LT.toStrict . decodeUtf8 <$> getGQLBody p
  variables <- maybeVariables p
  pure $
    GQLRequest
      { operationName = Nothing,
        query = queryBS,
        variables
      }

getResolvers :: Monad m => FieldName -> IO (RootResModel e m)
getResolvers (FieldName p) = do
  res <- fromMaybe Null . decode <$> L.readFile (path p <> "/resolvers.json")
  pure
    RootResModel
      { query = pure (lookupRes "query" res),
        mutation = pure (lookupRes "mutation" res),
        subscription = pure (lookupRes "subscription" res),
        channelMap = Nothing
      }

lookupRes ::
  ( WithOperation o,
    Monad m
  ) =>
  Text ->
  Value ->
  ResModel o e m
lookupRes name (Object fields) = maybe mkNull mkValue (lookup name fields)
lookupRes _ _ = mkNull
