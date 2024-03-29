{-# LANGUAGE TypeFamilies, InstanceSigs, ScopedTypeVariables, Rank2Types #-}

module Test.Hspec.WebDriver.Toolkit (
  -- * Main hooks
  runWebDriver
  , WdOptions(..)
  , defaultWdOptions
  , RunMode(..)
  , XvfbConfig(..)
  , VideoSettings(..)
  , WhenToSave(..)

  -- * Hooks

  -- ** Default hook sets
  , defaultHooks
  , allHooks

  -- ** Screenshots
  , screenshotBeforeTest
  , screenshotAfterTest
  , screenshotBeforeAndAfterTest

  -- ** Video recording
  , recordEntireVideo
  , recordIndividualVideos
  , recordErrorVideos

  -- ** Log saving
  , saveBrowserLogs
  , failOnSevereBrowserLogs
  , failOnCertainBrowserLogs
  , saveWebDriverLogs

  -- ** Test timing
  , recordTestTiming

  -- * Test helpers
  , runWithBrowser
  , runWithBrowser'
  , runEveryBrowser
  , runEveryBrowser'
  , executeWithBrowser
  , closeAllSessionsExcept
  , closeAllSessions
  , getTestFolder
  , beforeAllWith
  , beforeWith'
  , withCustomLogFailing

  -- * Types
  , Hook
  , SpecType
  , Browser
  , ToolsRoot
  , RunRoot
  , WdSession
  , WdExample
  , getSessionMap
  , getResultsDir

  , module Test.Hspec.WebDriver.Toolkit.Capabilities
  , module Test.Hspec.WebDriver.Toolkit.Expectations
  ) where

import Control.Concurrent
import Control.Exception
import Data.Default
import Data.Time.Clock
import Data.Time.Format
import System.Directory
import System.FilePath
import Test.Hspec
import Test.Hspec.WebDriver.Internal.Hooks.Logs
import Test.Hspec.WebDriver.Internal.Hooks.Screenshots
import Test.Hspec.WebDriver.Internal.Hooks.Timing
import Test.Hspec.WebDriver.Internal.Hooks.Video
import Test.Hspec.WebDriver.Internal.Lib
import Test.Hspec.WebDriver.Internal.Misc
import Test.Hspec.WebDriver.Internal.Types
import Test.Hspec.WebDriver.Internal.Util
import Test.Hspec.WebDriver.Internal.WebDriver
import Test.Hspec.WebDriver.Internal.Wrap
import Test.Hspec.WebDriver.Toolkit.Capabilities
import Test.Hspec.WebDriver.Toolkit.Expectations
import qualified Test.WebDriver as W
import qualified Test.WebDriver.Session as W


-- | A good default set of hooks: `screenshotBeforeAndAfterTest`, `recordErrorVideos`, and `saveBrowserLogs`.
defaultHooks :: Hook
defaultHooks = screenshotBeforeAndAfterTest
  . recordErrorVideos def
  . saveBrowserLogs

-- | All possible test instrumentation.
allHooks :: Hook
allHooks = undefined

-- | Start a Selenium server and run a spec inside it.
-- Auto-detects the browser version and downloads the Selenium .jar file and driver executable if necessary.
runWebDriver :: WdOptions -> Hook -> SpecWith WdSession -> Spec
runWebDriver wdOptions hooks tests =
  beforeAll (startWebDriver wdOptions) $
  afterAll stopWebDriver $
  afterAll closeAllSessions $
  addLabelsToTree (\labels sessionWithLabels -> sessionWithLabels { wdLabels = labels }) $
  hooks $
  tests

-- | Create a timestamp-named folder to contain the results of a given test run
getTestFolder :: FilePath -> IO FilePath
getTestFolder baseDir = do
  timestamp <- formatTime defaultTimeLocale "%FT%H.%M.%S" <$> getCurrentTime
  let testRoot = baseDir </> timestamp
  createDirectoryIfMissing True testRoot
  return testRoot

getSessionMap :: WdSession -> MVar [(String, W.WDSession)]
getSessionMap (WdSession {wdSessionMap}) = wdSessionMap


-- | Change the log failing function for all functions in this test.
withCustomLogFailing :: (W.LogEntry -> Bool) -> SpecType -> SpecType
withCustomLogFailing newFailureFn = aroundWith $ \action session@(WdSession {wdLogFailureFn}) -> do
  bracket (modifyMVar wdLogFailureFn (\current -> return (newFailureFn, current)))
          (\oldFailureFn -> modifyMVar_ wdLogFailureFn $ const $ return oldFailureFn)
          (\_ -> action session)
