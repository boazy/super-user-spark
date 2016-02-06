module Parser (
      parseFile
    ) where

import           Control.Exception (try)
import           Parser.Internal
import           Parser.Types
import           Types


parseFile :: FilePath -> Sparker SparkFile
parseFile file = do
    esf <- liftIO $ try $ parseFileIO file
    case esf of
        Left ioe -> throwError $ UnpredictedError $ show (ioe :: IOError)
        Right sf -> do
            case sf of
                Left pe -> throwError $ ParseError pe
                Right cs -> return cs

parseFileIO :: FilePath -> IO (Either ParseError SparkFile)
parseFileIO file = (liftIO $ readFile file) >>= return . parseCardFile file
