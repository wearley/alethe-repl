module Language where

import Data.Set (Set)
import qualified Data.Set as S
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Control.Monad (liftM2)
import qualified Text.Parsec.Error as PE

data Term = Atom     Integer String
          | Var      String
          | Asymm    Term Term
          | Compound [Term]
          deriving (Eq,Show)

data Definition = Terminus [Term]
                | Rule { lhs   :: [Context]
                       , rhs   :: [Context]
                       , decls :: [Declaration] }
                deriving (Show)

data Declaration = Declaration { weight :: Int , rule :: Context}
                deriving (Show)

data Context = Context Term [Term]
             deriving (Show)

data KappaError = ParseError PE.ParseError
                | AmbiguityError [Definition]
                | CompilationError [Definition]
                -- | IrreversibilityError [Definition]
                -- ...
                deriving (Show)

term0 = Compound []
termTerm = Compound []
atom = Atom 0
phony = Atom (-1) ""
atomZero = atom "Z"
atomSucc = atom "S"
atomNil = atom "Nil"
atomCons = atom "Cons"
atomPlus = atom "Plus"
atomMinus = atom "Minus"
atomChar c = atom [c]

nats = iterate (\n -> Compound [atomSucc, n]) atomZero
nat = (nats!!) . fromIntegral
cons car cdr = Compound [atomCons, car, cdr]
sexpr = flip $ foldr cons
slist = foldr cons atomNil
str = slist . map atomChar

--

termLeft :: Term -> Term
termLeft (Asymm l _) = l
termLeft (Compound t) = Compound $ map termLeft t
termLeft x = x

termRight :: Term -> Term
termRight (Asymm l _) = l
termRight (Compound t) = Compound $ map termRight t
termRight x = x

class Kappa a where
    asplit :: a -> (a,a)
    vars :: a -> Set String
    unify :: a -> a -> Maybe (Map String [Term])
    compatible :: a -> a -> Bool

    varsplit :: a -> (Set String, a, a)
    varsplit t = let (l,r) = asplit t in (vars t, l, r)

zipStrict :: [a] -> [b] -> Maybe [(a,b)]
zipStrict []     []     = Just []
zipStrict (x:xs) (y:ys) = (:) (x,y) <$> zipStrict xs ys
zipStrict _      _      = Nothing

zipWithStrict :: (a -> b -> c) -> [a] -> [b] -> Maybe [c]
zipWithStrict f xs ys = map (uncurry f) <$> zipStrict xs ys

instance Kappa a => Kappa [a] where
    asplit = unzip . map asplit
    vars = S.unions . map vars
    unify xs ys = M.unionsWith (++) <$> (zipWithStrict unify xs ys >>= sequence)
    compatible xs ys = maybe False (all $ uncurry compatible) $ zipStrict xs ys

instance Kappa Term where
    asplit = liftM2 (,) termLeft termRight

    vars (Atom _ _)  = S.empty
    vars (Var v)     = S.singleton v
    vars (Asymm l r) = S.union (vars l) (vars r)
    vars (Compound t)= vars t

    unify a@(Atom _ _) b@(Atom _ _) = if a == b then Just M.empty else Nothing
    unify (Var v)      t            = Just (M.singleton v [t])
    unify (Compound s) (Compound t) = unify s t
    unify _            _            = Nothing

    compatible (Var _)      _             = True
    compatible _            (Var _)       = True
    compatible a@(Atom _ _) b@(Atom _ _)  = a == b
    compatible (Asymm l r)  t             = compatible l t || compatible r t
    compatible t            a@(Asymm _ _) = compatible a t
    compatible (Compound s) (Compound t)  = compatible s t
    compatible _            _             = False

instance Kappa Context where
    asplit (Context c p) = let (c1,c2) = asplit c
                               (p1,p2) = asplit p
                           in (Context c1 p1, Context c2 p2)

    vars (Context c p) = S.union (vars c) (vars p)
    unify (Context c1 p1) (Context c2 p2) = liftM2 (M.union) (unify p1 p2) (unify c1 c2)
    compatible (Context c1 p1) (Context c2 p2) = compatible c1 c2 && compatible p1 p2