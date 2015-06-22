{-# LANGUAGE OverloadedStrings #-}

module Deployer where

import           Data.Maybe         (catMaybes)
import           Data.Text          (pack)
import           Prelude            hiding (error)
import           Shelly             (cp_r, fromText, shelly)
import           System.Directory   (createDirectoryIfMissing, emptyPermissions,
                                     getDirectoryContents, getPermissions,
                                     removeDirectoryRecursive, removeFile)
import           System.Exit        (ExitCode (..))
import           System.FilePath    (dropFileName)
import           System.Posix.Files (createSymbolicLink, fileExist,
                                     getSymbolicLinkStatus, isBlockDevice,
                                     isCharacterDevice, isDirectory,
                                     isNamedPipe, isRegularFile, isSocket,
                                     isSymbolicLink, readSymbolicLink)
import           System.Process     (system)

import           Formatter          (formatPostDeployments,
                                     formatPreDeployments)
import           Types
import           Utils


deploy :: [Deployment] -> Sparker ()
deploy dps = do
    state <- initialState dps
    _ <- runSparkDeployer state $ deployAll dps
    return ()

initialState :: [Deployment] -> Sparker DeployerState
initialState _ = return DeployerState

deployAll :: [Deployment] -> SparkDeployer ()
deployAll deps = do
    pdps <- predeployments deps

    case catErrors pdps of
        [] -> do
            dry <- asks conf_dry
            if dry
            then return ()
            else do
                deployments pdps
                postdeployments deps pdps

        ss -> throwError $ DeployError $ PreDeployError ss

catErrors :: [PreDeployment] -> [String]
catErrors [] = []
catErrors (s:ss) = case s of
                    Ready _ _ _ -> catErrors ss
                    AlreadyDone -> catErrors ss
                    Error str   -> str : catErrors ss


predeployments :: [Deployment] -> SparkDeployer [PreDeployment]
predeployments dps = do
    pdps <- mapM preDeployment dps
    lift $ verboseOrDry $ formatPreDeployments $ zip dps pdps
    return pdps

preDeployment :: Deployment -> SparkDeployer PreDeployment
preDeployment (Put [] dst _) = return $ Error $ unwords ["No source for deployment with destination:", dst]
preDeployment d@(Put (s:ss) dst kind) = do
    sd <- diagnose s
    dd <- diagnose dst
    case sd of
        NonExistent     -> preDeployment (Put ss dst kind)
        IsFile _        -> do
            case dd of
                NonExistent     -> ready
                IsFile      _   -> do
                    case kind of
                        LinkDeployment -> do
                            incaseElse conf_replace
                                (rmFile dst >> preDeployment d)
                                (error ["Destination", dst, "already exists and is file (for a link deployment):", s, "."])
                        CopyDeployment -> do
                            equal <- compareFiles s dst
                            if equal
                            then done
                            else do
                                incaseElse conf_replace
                                    (rmFile dst >> preDeployment d)
                                    (error ["Destination", dst, "already exists and is a file, different from the source:", s, "."])
                IsDirectory _   -> do
                    incaseElse conf_replace
                        (rmDir dst >> preDeployment d)
                        (error ["Destination", dst, "already exists and is a directory."])
                IsLink      _   -> do
                    case kind of
                        CopyDeployment -> do
                            incaseElse conf_replace
                                (unlink dst >> preDeployment d)
                                (error ["Destination", dst, "already exists and is a symbolic link (for a copy deployment):", s, "."])
                        LinkDeployment -> do
                            point <- liftIO $ readSymbolicLink dst
                            if point `filePathEqual` s
                            then done
                            else do
                                liftIO $ putStrLn $ point ++ " is not equal to " ++ dst
                                incaseElse conf_replace
                                    (unlink dst >> preDeployment d)
                                    (error ["Destination", dst, "already exists and is a symbolic link but not to the source."])
                _               -> error ["Destination", dst, "already exists and is something weird."]
        IsDirectory _   -> do
            case dd of
                NonExistent     -> ready
                IsFile      _   -> do
                    incaseElse conf_replace
                        (rmDir dst >> preDeployment d)
                        (error ["Destination", dst, "already exists and is a directory."])
                IsDirectory _   -> do
                    case kind of
                        LinkDeployment -> do
                            incaseElse conf_replace
                                (rmDir dst >> preDeployment d)
                                (error ["Destination", dst, "already exists and is directory (for a link deployment):", s, "."])
                        CopyDeployment -> do
                            equal <- compareDirectories s dst
                            if equal
                            then done
                            else do
                                incaseElse conf_replace
                                    (rmDir dst >> preDeployment d)
                                    (error ["Destination", dst, "already exists and is a directory, different from the source."])
                IsLink      _   -> do
                    case kind of
                        CopyDeployment -> do
                            incaseElse conf_replace
                                (unlink dst >> preDeployment d)
                                (error ["Destination", dst, "already exists and is a symbolic link."])
                        LinkDeployment -> do
                            point <- liftIO $ readSymbolicLink dst
                            if point `filePathEqual` s
                            then done
                            else incaseElse conf_replace
                                (unlink dst >> preDeployment d)
                                (error ["Destination", dst, "already exists and is a symbolic link but not to the source."])
                _               -> error ["Destination", dst, "already exists and is something weird."]
        IsLink _        -> error ["Source", s, "is a symbolic link."]
        _               -> error ["Source", s, "is not a valid file type."]

  where
    done :: SparkDeployer PreDeployment
    done = return $ AlreadyDone

    ready :: SparkDeployer PreDeployment
    ready = return $ Ready s dst kind

    error :: [String] -> SparkDeployer PreDeployment
    error strs = return $ Error $ unwords strs


cmpare :: FilePath -> FilePath -> SparkDeployer Bool
cmpare f1 f2 = do
    d1 <- diagnose f1
    d2 <- diagnose f2
    if d1 /= d2
    then return False
    else case d1 of
        IsFile      _   -> compareFiles f1 f2
        IsDirectory _   -> compareDirectories f1 f2
        _           -> return True

compareFiles :: FilePath -> FilePath -> SparkDeployer Bool
compareFiles f1 f2 = do
    s1 <- liftIO $ readFile f1
    s2 <- liftIO $ readFile f2
    return $ s1 == s2

compareDirectories :: FilePath -> FilePath -> SparkDeployer Bool
compareDirectories d1 d2 = do
    dc1 <- contents d1
    dc2 <- contents d2
    b <- mapM (uncurry cmpare) $ zip dc1 dc2
    return $ and b
  where
    contents d = do
        cs <- liftIO $ getDirectoryContents d
        return $ filter (\f -> not $ f == "." || f == "..") cs

diagnose :: FilePath -> SparkDeployer Diagnostics
diagnose fp = do
    e <- liftIO $ fileExist fp
    if e
    then do
        s <- liftIO $ getSymbolicLinkStatus fp
        if isBlockDevice s
        then return IsBlockDevice
        else if isCharacterDevice s
            then return IsCharDevice
            else if isSocket s
                then return IsSocket
                else if isNamedPipe s
                    then return IsPipe
                    else do
                        p <- liftIO $ getPermissions fp
                        if isSymbolicLink s
                        then return $ IsLink p
                        else if isDirectory s
                            then return $ IsDirectory p
                            else if isRegularFile s
                                then return $ IsFile p
                                else throwError $ UnpredictedError "Contact the author if you see this"
    else do
        -- Because if a link exists, but it points to something that doesn't exist, it is considered as non-existent by `fileExist`
        es <- liftIO $ system $ unwords ["test", "-L", fp]
        case es of
            ExitSuccess -> return $ IsLink emptyPermissions
            ExitFailure _ -> return NonExistent



deployments :: [PreDeployment] -> SparkDeployer [Maybe String]
deployments = mapM deployment

deployment :: PreDeployment -> SparkDeployer (Maybe String)
deployment AlreadyDone = return Nothing
deployment (Error str) = return $ Just str
deployment (Ready src dst kind) = do
    case kind of
        LinkDeployment -> link src dst
        CopyDeployment -> copy src dst
    return Nothing

copy :: FilePath -> FilePath -> SparkDeployer ()
copy src dst = do
    liftIO $ createDirectoryIfMissing True upperDir
    liftIO $ shelly $ cp_r (fromText $ pack src) (fromText $ pack dst)
  where upperDir = dropFileName dst

link :: FilePath -> FilePath -> SparkDeployer ()
link src dst = do
    liftIO $ createDirectoryIfMissing True upperDir
    liftIO $ createSymbolicLink src dst
  where upperDir = dropFileName dst


-- TODO these dont catch errors
unlink :: FilePath -> SparkDeployer ()
unlink fp = do
    es <- liftIO $ system $ unwords $ ["/usr/bin/unlink", fp]
    case es of
        ExitSuccess -> verbose $ unwords ["unlinked", fp]
        ExitFailure _ -> throwError $ DeployError $ PreDeployError ["Something went wrong while unlinking " ++ fp ++ "."]

rmFile :: FilePath -> SparkDeployer ()
rmFile fp = do
    liftIO $ removeFile fp
    verbose $ unwords ["removed", fp]

rmDir :: FilePath -> SparkDeployer ()
rmDir fp = do
    liftIO $ removeDirectoryRecursive fp
    verbose $ unwords ["removed", fp]


postdeployments :: [Deployment] -> [PreDeployment] -> SparkDeployer ()
postdeployments deps predeps = do
    pdps <- mapM postdeployment predeps
    lift $ verbose $ formatPostDeployments $ zip deps pdps
    case catMaybes pdps of
        [] -> return ()
        es -> throwError $ DeployError $ PostDeployError es

postdeployment :: PreDeployment -> SparkDeployer (Maybe String)
postdeployment AlreadyDone = return Nothing
postdeployment (Error _) = throwError $ UnpredictedError "Contact the author if you see this. (postdeployment)"
postdeployment (Ready src dst kind) = do
    sd <- diagnose src
    dd <- diagnose dst
    case sd of
        NonExistent     -> error ["The source", src, "is somehow missing after deployment."]
        IsFile      _   -> do
            case dd of
                NonExistent     -> error ["The destination", dst, "is somehow non-existent after deployment."]
                IsFile      _   -> do
                    case kind of
                        LinkDeployment -> error ["The destination", dst, "is somehow a file while it was a link deployment."]
                        CopyDeployment -> do
                            equal <- compareFiles src dst
                            if equal
                            then fine
                            else error ["The source and destination files are somehow still not equal."]
                IsDirectory _   -> error ["The destination", dst, "is somehow a directory after the deployment of the file", src, "."]
                IsLink      _   -> do
                    case kind of
                        CopyDeployment -> error ["The destination", dst, "is somehow a link while it was a copy deployment."]
                        LinkDeployment -> do
                            point <- liftIO $ readSymbolicLink dst
                            if point `filePathEqual` src
                            then fine
                            else error ["The destination", dst, "is a symbolic link, but it doesn't point to the source."]
                _               -> error ["The destination", dst, "is something weird after deployment."]
        IsDirectory _   -> do
            case dd of
                NonExistent     -> error ["The destination", dst, "is somehow non-existent after deployment."]
                IsFile      _   -> error ["The destination", dst, "is somehow a file after the deployment of the directory", src, "."]
                IsDirectory _   -> do
                    case kind of
                        LinkDeployment -> error ["The destination", dst, "is somehow a directory while it was a link deployment."]
                        CopyDeployment -> do
                            equal <- compareDirectories src dst
                            if equal
                            then fine
                            else error ["The source and destination directories are somehow still not equal."]
                IsLink      _   -> do
                    case kind of
                        CopyDeployment -> error ["The destination", dst, "is somehow a link while it was a copy deployment."]
                        LinkDeployment -> do
                            point <- liftIO $ readSymbolicLink dst
                            if point `filePathEqual` src
                            then fine
                            else error ["The destination is a symbolic link, but it doesn't point to the source."]
                _               -> error ["The destination", dst, "is something weird after deployment."]

        IsLink      _   -> error ["The source", src, "is a symbolic link."]
        _               -> error ["The source", src, "is something weird."]

  where
    fine :: SparkDeployer (Maybe String)
    fine = return Nothing
    error :: [String] -> SparkDeployer (Maybe String)
    error err = return $ Just $ unwords err

filePathEqual :: FilePath -> FilePath -> Bool -- TODO comparison could be more fuzzy
filePathEqual = (==)
