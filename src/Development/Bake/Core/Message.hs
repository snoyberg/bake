{-# LANGUAGE RecordWildCards, OverloadedStrings #-}

module Development.Bake.Core.Message(
    Message(..), Ping(..), Question(..), Answer(..), aTests,
    sendMessage, messageToInput, messageFromInput, questionToOutput
    ) where

import Development.Bake.Core.Type
import General.Web
import Control.Applicative
import Control.Monad
import Control.DeepSeq
import Data.Aeson hiding (Success)
import General.Str
import qualified Data.ByteString.Lazy.Char8 as LBS


data Message
    -- Send by the user
    = AddPatch Author Patch
    | DelPatch Author Patch
    | DelAllPatches Author
    | Pause Author
    | Unpause Author
    -- Sent by the client
    | Pinged Ping
    | Finished {question :: Question, answer :: Answer}
    deriving (Show,Eq)

instance NFData Message where
    rnf (AddPatch x y) = rnf x `seq` rnf y
    rnf (DelPatch x y) = rnf x `seq` rnf y
    rnf (DelAllPatches x) = rnf x
    rnf (Pause x) = rnf x
    rnf (Unpause x) = rnf x
    rnf (Pinged x) = rnf x
    rnf (Finished x y) = rnf x `seq` rnf y

data Question = Question
    {qCandidate :: (State, [Patch])
    ,qTest :: Maybe Test
    ,qThreads :: Int
    ,qClient :: Client
    }
    deriving (Show,Eq,Ord)

instance NFData Question where
    rnf (Question a b c d) = rnf (a,b,c,d)

data Answer = Answer
    {aStdout :: Str
    ,aDuration :: Double
    ,aTestsSuitable :: ([Test],[Test])
        -- only filled in if qTest is Nothing
        -- (those tests which are suitable, those which are unsuitable)
    ,aSuccess :: Bool
    }
    deriving (Show,Eq)

instance NFData Answer where
    rnf (Answer a b c d) = rnf a `seq` rnf b `seq` rnf c `seq` rnf d

aTests :: Answer -> [Test]
aTests = uncurry (++) . aTestsSuitable

data Ping = Ping
    {pClient :: Client
    ,pAuthor :: Author
    ,pMaxThreads :: Int
    ,pNowThreads :: Int
    }
    deriving (Show,Eq)

instance NFData Ping where
    rnf (Ping a b c d) = rnf a `seq` rnf b `seq` rnf c `seq` rnf d

-- JSON instance is only true for Finished
instance ToJSON Message where
    toJSON (Finished q a) = object ["question" .= q, "answer" .= a]

instance FromJSON Message where
    parseJSON (Object v) = Finished <$>
        (v .: "question") <*> (v .: "answer")
    parseJSON _ = mzero

instance ToJSON Question where
    toJSON Question{..} = object
        ["candidate" .= toJSONCandidate qCandidate
        ,"test" .= qTest
        ,"threads" .= qThreads
        ,"client" .= qClient]

instance FromJSON Question where
    parseJSON (Object v) = Question <$>
        (fromJSONCandidate =<< (v .: "candidate")) <*> (v .: "test") <*> (v .: "threads") <*> (v .: "client")
    parseJSON _ = mzero

toJSONCandidate (s, ps) = object ["state" .= s, "patches" .= ps]

fromJSONCandidate (Object v) = (,) <$> (v .: "state") <*> (v .: "patches")
fromJSONCandidate _ = mzero

instance ToJSON Answer where
    toJSON Answer{..} = object
        ["stdout" .= aStdout
        ,"duration" .= aDuration
        ,"tests" .= aTestsSuitable
        ,"success" .= aSuccess]

instance FromJSON Answer where
    parseJSON (Object v) = Answer <$>
        (v .: "stdout") <*> (v .: "duration") <*> (v .: "tests") <*> (v .: "success")
    parseJSON _ = mzero


messageToInput :: Message -> Input
messageToInput (AddPatch author (Patch patch)) = Input ["api","add"] [("author",author),("patch",patch)] ""
messageToInput (DelPatch author (Patch patch)) = Input ["api","del"] [("author",author),("patch",patch)] ""
messageToInput (DelAllPatches author) = Input ["api","delall"] [("author",author)] ""
messageToInput (Pause author) = Input ["api","pause"] [("author",author)] ""
messageToInput (Unpause author) = Input ["api","unpause"] [("author",author)] ""
messageToInput (Pinged Ping{..}) = Input ["api","ping"]
    [("client",fromClient pClient),("author",pAuthor)
    ,("maxthreads",show pMaxThreads),("nowthreads",show pNowThreads)] ""
messageToInput x@Finished{} = Input ["api","finish"] [] $ LBS.unpack $ encode x


-- return either an error message (not a valid message), or a message
messageFromInput :: Input -> Either String Message
messageFromInput (Input [msg] args body)
    | msg == "add" = AddPatch <$> str "author" <*> (Patch <$> str "patch")
    | msg == "del" = DelPatch <$> str "author" <*> (Patch <$> str "patch")
    | msg == "delall" = DelAllPatches <$> str "author"
    | msg == "pause" = Pause <$> str "author"
    | msg == "unpause" = Unpause <$> str "author"
    | msg == "ping" = Pinged <$> (Ping <$> (Client <$> str "client") <*>
        str "author" <*> int "maxthreads" <*> int "nowthreads")
    | msg == "finish" = eitherDecode $ LBS.pack body
    where str x | Just v <- lookup x args = Right v
                | otherwise = Left $ "Missing field " ++ show x ++ " from " ++ show msg
          int x = read <$> str x
messageFromInput (Input msg args body) = Left $ "Invalid API call, got " ++ show msg


questionToOutput :: Maybe Question -> Output
questionToOutput = OutputString . LBS.unpack . encode


sendMessage :: (Host,Port) -> Message -> IO (Maybe Question)
sendMessage hp msg = do
    res <- send hp $ messageToInput msg
    return $ decode $ LBS.pack res
