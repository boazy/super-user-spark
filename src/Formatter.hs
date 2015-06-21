module Formatter where

import           Data.List (intersperse)

import           Constants
import           Types

formatCards :: [Card] -> Sparker String
formatCards cs = do
    initial <- initialState
    (_, res) <- runSparkFormatter initial (cards cs)
    return res

initialState :: Sparker FormatterState
initialState = return $ FormatterState {
        state_current_indent = 0
    ,   state_longest_src = 0
    ,   state_newline_before_deploy = True
    }

indentation :: Int
indentation = 4

cards :: [Card] -> SparkFormatter ()
cards cs = do
    onLines card cs

onLines :: (a -> SparkFormatter ()) -> [a] -> SparkFormatter ()
onLines thingFormatter things = do
    let allThings = map thingFormatter things
    sequence_ $ intersperse newline allThings


card :: Card -> SparkFormatter ()
card (Card name _ ds) = do
    string keywordCard
    string " "
    string name
    string " "
    declaration $ Block ds

braces :: SparkFormatter () -> SparkFormatter ()
braces f = do
    modify (\s -> s {state_newline_before_deploy = True})
    string "{"
    newline
    indent 4
    newline
    f
    newline
    indent (-4)
    newline
    string "}"

string :: String -> SparkFormatter ()
string s = tell s

interspersed :: [String] -> String -> SparkFormatter ()
interspersed [] _ = return ()
interspersed [s] _ = string s
interspersed (s:ss) i = do
    string s
    string i
    spaced ss

spaced :: [String] -> SparkFormatter ()
spaced strs = interspersed strs " "

newline :: SparkFormatter ()
newline = do
    string "\n"
    ci <- gets state_current_indent
    string $ replicate ci ' '

indent :: Int -> SparkFormatter ()
indent c = do
    ci <- gets state_current_indent
    modify (\s -> s {state_current_indent = ci + c})

declarations :: [Declaration] -> SparkFormatter ()
declarations = onLines declaration

declaration :: Declaration -> SparkFormatter ()
declaration (SparkOff cr) = do
    string keywordSpark
    string " "
    cardReference cr
declaration (Deploy src dst k) = do
    nbf <- gets state_newline_before_deploy
    if nbf
    then newline
    else return ()
    string src
    ls <- gets state_longest_src
    string $ replicate (ls - length src) ' '
    string " "
    mkind k
    string " "
    string dst
    modify (\s -> s {state_newline_before_deploy = False})
declaration (IntoDir dir) = do
    string keywordInto
    string " "
    string dir
declaration (OutofDir dir) = do
    string keywordOutof
    string " "
    string dir
declaration (DeployKindOverride k) = do
    string keywordKindOverride
    string " "
    kind k
declaration (Block ds) = do
    ls <- gets state_longest_src
    let m = maximum $ map srcLen ds
    modify (\s -> s {state_longest_src = m} )
    braces $ declarations ds
    modify (\s -> s {state_longest_src = ls} )
    newline
  where
    srcLen (Deploy src _ _) = length src
    srcLen _ = 0
declaration (Alternatives ds) = do
    string keywordAlternatives
    string " "
    spaced ds


kind :: DeploymentKind -> SparkFormatter ()
kind LinkDeployment = string keywordCopy
kind CopyDeployment = string keywordLink

mkind :: Maybe DeploymentKind -> SparkFormatter ()
mkind (Just k) = kind k
mkind Nothing = string $ ' ':unspecifiedKindSymbol

cardReference :: CardReference -> SparkFormatter ()
cardReference (CardRepo repo mb mfpmcn) = do
    string keywordGit
    string " "
    string $ show repo
    case mb of
        Nothing -> return ()
        Just b -> do
            string branchDelimiter
            string b
    case mfpmcn of
        Nothing -> return ()
        Just (fp, mcn) -> do
            string " "
            string fp
            case mcn of
                Nothing -> return ()
                Just cn -> do
                    string " "
                    string cn

cardReference (CardFile fp mcn) = do
    string keywordFile
    string " "
    string fp
    case mcn of
        Nothing -> return ()
        Just cn -> do
            string " "
            string cn

cardReference (CardName name) = do
    string keywordCard
    string " "
    string name



srcLen :: Deployment -> [Int]
srcLen (Put srcs _ _) = map length srcs

maximums :: [[Int]] -> [Int]
maximums [[]] = []
maximums lss = if all null lss
    then []
    else (maximum $ map ahead lss):(maximums $ map atail lss)
  where
    ahead [] = 0
    ahead (l:_) = l

    atail [] = []
    atail (_:ls) = ls

formatDeployments :: [Deployment] -> String
formatDeployments ds = unlines $ map (formatDeployment lens) ds
  where lens = maximums $ map srcLen ds

formatDeployment :: [Int] -> Deployment -> String
formatDeployment ms d@(Put srcs dst k) = unwords $
    [
        padded ms srcs
    ,   kindSymbol k
    ,   dst
    ]
  where
    kindSymbol LinkDeployment = linkKindSymbol
    kindSymbol CopyDeployment = copyKindSymbol

    padded :: [Int] -> [FilePath] -> String
    padded [] [] = []
    padded (m:r) [] = replicate m ' ' ++ padded r []
    padded [] _ = []
    padded (m:r) (s:ss) = s ++ replicate (m - length s) ' ' ++ " " ++ padded r ss


formatPreDeployments :: [(Deployment, PreDeployment)] -> String
formatPreDeployments ds = unlines $ zipStrs dests $ map (": " ++) ms
  where
    ms = map formatPreDeployment predeps

    dests = map (dst.fst) ds
    predeps = map snd ds

formatPostDeployments :: [(Deployment, Maybe String)] -> String
formatPostDeployments ds = unlines $ zipStrs dests $ map (": " ++) ms
  where
    ms = map mstr predeps

    mstr Nothing = "done"
    mstr (Just err) = err

    dests = map (dst.fst) ds
    predeps = map snd ds

formatPreDeployment :: PreDeployment -> String
formatPreDeployment (Ready _ _ _) = "ready to deploy"
formatPreDeployment AlreadyDone = "done already"
formatPreDeployment (Error str) = unwords ["Error:", str]



zipStrs :: [String] -> [String] -> [String]
zipStrs [] [] = []
zipStrs [] ss = ss
zipStrs ss [] = ss
zipStrs (s:ss) (t:ts) = (s++t):(zipStrs ss ts)





