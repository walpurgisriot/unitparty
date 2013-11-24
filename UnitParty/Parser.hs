module UnitParty.Parser (parseUnit, parseAmount) where

import UnitParty.Types
import UnitParty.Units

import Text.ParserCombinators.Parsec hiding ((<|>))
import Control.Applicative hiding (many, optional)
import Control.Monad ((>=>))
import Data.List (stripPrefix)
import Data.Char (toLower)

import qualified Data.Map as M

data Token = TUnit String Int | TUnit' Unit | TOp Op | TPOpen | TPClose | TGrp [Token]
data Op = Mul | Div

instance Show Token where
  show (TUnit s i) = s ++ "^" ++ show i
  show (TUnit' u)  = "unit"
  show (TOp Mul) = "*"
  show (TOp Div) = "*"
  show TPOpen = "("
  show TPClose = ")"

-- parser for units that handles:
-- 1. names in the `units' map exported by Units
-- 2. names with metric prefixes like "giga" and "femto"
-- 3. algebraic units like furlongs / hour^3
-- 4. grouping with parentheses.
parseUnit :: String -> Either UParseError Unit
parseUnit s = case lexUnit $ map toLower s of
  Left _ -> Left $ SyntaxError s
  Right toks -> mapM getUnit toks
            >>= group [TGrp []]
            >>= unify
            >>= \(TUnit' u) -> return u
  where

    group gs (TPOpen:ts) = group (TGrp []:gs) ts
    group ((TGrp g1):TGrp g2:gs) (TPClose:ts) = 
      group (TGrp (TGrp (reverse g1):g2):gs) ts
    group (TGrp g:gs) (t:ts) = group (TGrp (t:g):gs) ts
    group [(TGrp t)] [] = return $ reverse t
    group _ _ = Left $ MismatchedParens s

    unify ((TGrp g):ts) = unify g >>= unify . (:ts)
    unify (TUnit' u : TOp o : t : ts) = case t of
      TGrp g -> unify g >>= \g' -> unify $ TUnit' u : TOp o : g' : ts
      TUnit' u' -> let op = case o of { Mul -> (*~); Div -> (/~) } in
                   unify $ TUnit' (op u u'):ts
      _ -> Left $ SyntaxError s

    unify [u@(TUnit' _)] = return u
    unify _ = Left $ SyntaxError s

    getUnit (TUnit u i) =  fmap (TUnit' . (**~i)) (getUnit' u)
                       <?> (getPrefix u >>= \(p,u') ->
                            fmap (TUnit' . (**~i) . p) (getUnit' u'))
      where
        getUnit' s = case M.lookup s units of
          Nothing -> Left $ UnknownUnit s
          Just s' -> Right s'
        getPrefix = gp $ M.toList metricPrefixes
          where gp ((p,pf):ps) s = case stripPrefix p s of
                  Nothing -> gp ps s
                  Just s' -> return (pf, s')
                gp [] s = Left $ UnknownUnit s
    getUnit t = return t

    Left _ <?> a = a
    a@(Right _) <?> _ = a

-- parser for quantities
parseAmount :: String -> Either UParseError Double
parseAmount a = case parse amount "" a of
  Left err -> Left $ QuantityError a
  Right d -> return d
  where
    amount = signed <|> unsigned
    signed = char '-' >> fmap negate unsigned
    unsigned = try dec <|> (int >>= return . read)
    int = many1 digit
    dec = int >>= \i1 -> char '.' >> int >>= \i2 ->
      return $ read i1 + read i2 * (10 ** fromIntegral (negate $ length i2))

-- lexer used by parseUnit
lexUnit :: String -> Either ParseError [Token]
lexUnit = flip parse "" $
  spaces >> (unit <|> op <|> paren) `sepEndBy` spaces
  where
    unit = try expUnit <|> simpleUnit
    simpleUnit = many1 letter >>= \n -> return $ TUnit n 1
    expUnit = do
      TUnit n x <- simpleUnit
      char '^'
      i <- int
      return $ TUnit n (i*x)

    op =  (char '*' >> return (TOp Mul))
      <|> (char '/' >> return (TOp Div))

    int =  (char '-' >> many1 digit >>= return . negate . read)
       <|> (many1 digit >>= return . read)
    
    paren = (char '(' >> return TPOpen) <|> (char ')' >> return TPClose)
