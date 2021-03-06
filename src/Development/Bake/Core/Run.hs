{-# LANGUAGE RecordWildCards, DeriveDataTypeable #-}

module Development.Bake.Core.Run(
    runInit, runUpdate, runTest, runExtra
    ) where

import Development.Bake.Core.Type hiding (Client)
import Development.Bake.Core.Message
import Development.Shake.Command
import Control.Exception.Extra
import General.Str
import General.Extra
import System.Time.Extra
import Control.DeepSeq
import Data.Tuple.Extra
import System.IO.Extra
import System.Environment.Extra
import System.FilePath
import Data.Maybe
import System.Exit


state x = "--state=" ++ fromState x
patch x = "--patch=" ++ fromPatch x
test  x = "--test="  ++ fromTest  x

runInit :: IO (Maybe State, Answer)
runInit = runAll "init" [] [] State

runUpdate :: State -> [Patch] -> IO (Maybe State, Answer)
runUpdate s ps = runAll "update" (state s : map patch ps) [] State

runTest :: State -> [Patch] -> Maybe Test -> IO Answer
runTest s ps t = do
    (ex, ans) <- runAll "test" (state s : map patch ps) (map test $ maybeToList t) (both (map Test) . read)
    return $ maybe ans (\ex -> ans{aTestsSuitable=ex}) ex

runExtra :: State -> Maybe Patch -> IO (Maybe (Str, Str), Answer)
runExtra s ps = runAll "extra" (state s : map patch (maybeToList ps)) [] (both strPack . read)


runAll :: NFData a => String -> [String] -> [String] -> (String -> a) -> IO (Maybe a, Answer)
runAll name args1 args2 parse = do
    exe <- getExecutablePath
    dir <- createDir ("bake-" ++ name) args1

    (time, res) <- duration $ try_ $ do
        exe <- getExecutablePath
        (exit, Stdout sout, Stderr serr) <- cmd (Cwd dir) exe ("run" ++ name) args1 args2
        ex <- if exit /= ExitSuccess then return Nothing else do
            ans <- fmap parse $ readFile' $ dir </> ".bake.result"
            evaluate $ rnf ans
            return $ Just ans
        return (ex, Answer (strPack $ sout++serr) 0 ([],[]) (exit == ExitSuccess))
    case res of
        Left e -> do
            e <- showException e
            return (Nothing, Answer (strPack e) time ([],[]) False)
        Right (ex,ans) -> return (ex, ans{aDuration=time})
