import UnitParty.Types
import UnitParty.Parser
import UnitParty.Convert
import UnitParty.Units
import System.Environment
import System.Exit
import System.IO
import System.Console.GetOpt
import Control.Monad
import Data.Maybe (fromJust)
import System.Random
import qualified Data.Map as M

data Opts = Opts { from    :: Maybe NamedUnit
                 , to      :: Maybe NamedUnit
                 , amount  :: Double
                 , analyze :: Maybe NamedUnit
                 , list    :: Bool
                 , dyk     :: Bool
                 , help    :: Bool
                 , conversion :: Bool
                 }
data Action = Convert NamedUnit NamedUnit Double
            | Analyze NamedUnit | List | DYK | Help

data NamedUnit = NU { unit :: Unit, name :: String }

main :: IO ()
main = getArgs >>= \args -> case parseArgs args of
  Left err -> doError err
  Right [] -> usage >>= putStr
  Right as -> mapM_ doAction as

doError :: String -> IO ()
doError s = hPutStrLn stderr s >> exitFailure

usage :: IO String
usage = getProgName >>= return . ("Usage: "++) . (++ usageInfo header options)
  where header = " [OPTIONS]"

parseArgs :: [String] -> Either String [Action]
parseArgs args = case getOpt Permute options args of
  (o,_,[]) -> do
    opts <- foldM (flip ($)) defaults o
    foldM (flip ($)) [] [ checkList opts
                        , checkDyk opts
                        , checkAna opts
                        , checkConv opts
                        ]
  (_,_,es) -> Left . init $ concat es

  where
    checkPresent :: Maybe a -> String -> Either String a
    checkPresent Nothing  = Left . ("Missing required parameter: "++)
    checkPresent (Just a) = const $ return a

    checkList o l = if list o then return (List:l) else return l
    checkDyk  o l = if dyk  o then return (DYK:l)  else return l
    checkAna  o l = case analyze o of
      Nothing -> return l
      Just u -> return (Analyze u:l)
    checkConv o l = if conversion o then do f <- checkPresent (from o)   "from"
                                            t <- checkPresent (to o)     "to"
                                            return $ Convert f t (amount o) : l
                    else return l

doAction :: Action -> IO ()

doAction Help = usage >>= putStr
doAction (Convert f t a) = case convert (unit f) (unit t) of
  Left err -> doError $ show err
  Right c ->  putStrLn $ unwords [show a, name f, "=", show $ c a, name t]

doAction List = mapM_ putStrLn $ M.keys baseUnits

doAction (Analyze u) = putStrLn $
  name u ++ ": " ++ show (fst . (\(U u) -> M.findMax u) $ unit u)

doAction DYK = do
  (u1,u2) <- randomUnits
  putStrLn "Did you know ..."
  putStr "  "
  doAction $ Convert u1 u2 1
  where
    pluralList = M.toList pluralUnits
    baseList   = M.toList baseUnits
    randomUnit l = randomRIO (0, length l - 1) >>= \i ->
      let (n, u) = l !! i in return $ NU u n
    randomUnits = do
      u  <- randomUnit baseList
      u' <- randomUnit pluralList

      if equidimensional (unit u) (unit u')
        then return (u,u')
        else randomUnits

defaults :: Opts
defaults = Opts Nothing Nothing 1 Nothing False False False False

options :: [OptDescr (Opts -> Either String Opts)]
options =
  [ Option "f" ["from"]    (ReqArg setFrom "FROM")    "unit to convert from"
  , Option "t" ["to"]      (ReqArg setTo   "TO")      "unit to convert to"
  , Option "a" ["amount"]  (ReqArg setAmt  "AMOUNT")  "amount to convert"
  , Option []  ["analyze"] (ReqArg setAna  "ANALYZE")  "print dimensions"
  , Option []  ["dyk"]     (NoArg setDyk)             "print a random did-you-know"
  , Option []  ["list"]    (NoArg setList)            "list known units"
  , Option "h" ["help"]    (NoArg setHelp)            "show this message"
  ]
  where
    setFrom f o = getParsed parseUnit f >>= \u ->
                    return o{from = Just $ NU u f} >>= setConv
    setTo t o   = getParsed parseUnit t >>= \u ->
                    return o{to = Just $ NU u t} >>= setConv
    setAmt a o  = getParsed parseAmount a >>= \a ->
                    return o{amount = a} >>= setConv
    setAna a o  = getParsed parseUnit a >>= \u ->
                    return o{analyze = Just $ NU u a}
    setDyk  o = return o{dyk=True}
    setList o = return o{list=True}
    setHelp o = return o{help=True}
    setConv o = return o{conversion=True}

    getParsed p u = case p u of
      Left err -> Left $ show err
      Right u' -> return u'
