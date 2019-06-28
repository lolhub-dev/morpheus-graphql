module Data.Morpheus.Types.Types
  ( GQLQueryRoot(..)
  , Variables
  , GQLRootResolver(..)
  ) where

import           Data.Map                                      (Map)
import           Data.Morpheus.Types.Internal.AST.Operator     (RawOperator)
import           Data.Morpheus.Types.Internal.AST.RawSelection (FragmentLib)
import           Data.Morpheus.Types.Internal.Base             (Key)
import           Data.Morpheus.Types.Internal.Value            (Value)

type Variables = Map Key Value

data GQLQueryRoot = GQLQueryRoot
  { fragments      :: FragmentLib
  , queryBody      :: RawOperator
  , inputVariables :: [(Key, Value)]
  }

-- | GraphQL Root resolver, also the interpreter generates a GQL schema from it.
--
--  'queryResolver' is required, 'mutationResolver' and 'subscriptionResolver' are optional,
--  if your schema does not supports __mutation__ or __subscription__ , you acn use __()__ for it.
data GQLRootResolver a b c = GQLRootResolver
  { queryResolver        :: a
  , mutationResolver     :: b
  , subscriptionResolver :: c
  }
