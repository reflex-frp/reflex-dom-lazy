{-# Language DerivingStrategies #-}
{-# Language FlexibleContexts #-}
{-# Language OverloadedStrings #-}
{-# Language RecursiveDo #-}
{-# Language ScopedTypeVariables #-}
module Reflex.Dom.Lazy.List where

import Control.Monad.Fix
import Control.Monad.IO.Class
import qualified Data.Map as Map
import Data.Map (Map)
import qualified Data.Text as T
import Data.Text (Text)
import qualified GHCJS.DOM.Element as JS
import Language.Javascript.JSaddle
import Reflex.Dom.Attrs
import Reflex.Dom.Core hiding (Attrs)

-- | Information about the current scroll state of a lazy list
data ScrollInfo = ScrollInfo
  { _scrollInfo_topIndex :: Int
  -- ^ The index of the first visible row
  , _scrollInfo_numberOfElements :: Int
  -- ^ The number of rows needed to fill the viewport (with some buffer)
  , _scrollInfo_paddingTop :: Double
  -- ^ The pixel size of the padding needed above the first visible row to
  -- maintain the correct scrollbar size and scroll positioning.
  , _scrollInfo_paddingBottom :: Double
  -- ^ The pixel size of the padding needed above the first visible row to
  -- maintain the correct scrollbar size and scroll positioning.
  }
  deriving stock (Show)

-- | Configuration for a lazy list
data LazyListConfig t m = LazyListConfig
  { _lazyListConfig_identifier :: Text
  -- ^ Unique element ID of the list content container. If it is not unique,
  -- different lazy lists on the same page may interfere with each other.
  , _lazyListConfig_rowHeightPx :: Dynamic t Double
  -- ^ A fixed height for each row, which must be separately enforced by the
  -- row rendering function.
  , _lazyListConfig_cardinality :: Dynamic t Int
  -- ^ The total number of elements in the list. This is used to determine the
  -- size of the scroll bar and padding before and after the render window.
  , _lazyListConfig_viewportAttrs :: [Attrs t m]
  -- ^ These attrs should include overflow-y: auto to enable scrolling. You may
  -- need to ensure that parent elements are not providing their own scroll bar
  -- (including the <body> element). The size of this element will be
  -- considered the viewport size for rendering purposes.
  }

data LazyList t = LazyList
  { _lazyList_scrollInfo :: Dynamic t ScrollInfo
  }

-- | Render a long list of elements efficiently by only displaying those that
-- are within the visible viewport. Visible rows are sandwiched between padding
-- elements so that the scroll bar and scroll position work behave as though
-- all rows have been rendered.
lazyList
  :: ( DomBuilder t m
     , MonadFix m
     , MonadHold t m
     , PostBuild t m
     , PerformEvent t m
     , TriggerEvent t m
     , MonadIO (Performable m)
     , MonadJSM (Performable m)
     , JS.IsElement (RawElement (DomBuilderSpace m))
     )
  => LazyListConfig t m
  -> m list
  -> m (LazyList t, list)
lazyList cfg elems = mdo
  -- CSS variables used to control the height of the padding elements
  let
    topVar = "--top-pad-" <> _lazyListConfig_identifier cfg
    bottomVar = "--bottom-pad-" <> _lazyListConfig_identifier cfg
  -- <style> tags are used to create pseudo-elements before and after the lazy list container
  el "style" $ text $ mconcat
    [ "#", _lazyListConfig_identifier cfg
    , "::before { content: \"\"; display: block; height: var(", topVar, "); }"
    ]
  el "style" $ text $ mconcat
    [ "#", _lazyListConfig_identifier cfg
    , "::after { content: \"\"; display: block; height: var(", bottomVar, "); }"
    ]
  -- Create the scrollable viewport container. Don't forget to set overflow-y: auto.
  (viewport, (scrollInfo, out)) <- elDiv' (_lazyListConfig_viewportAttrs cfg) $ do
    let
      padding = fmap (\x -> (_scrollInfo_paddingTop x, _scrollInfo_paddingBottom x)) scrollInfo
      attrs = ffor padding $ \(top, bottom) -> mconcat
        [ "id" =: _lazyListConfig_identifier cfg
        , ("style" =:) $ T.intercalate ";"
            [ "overflow-anchor: none"
            , topVar <> ": " <> T.pack (show top) <> "px"
            , bottomVar <> ": " <> T.pack (show bottom) <> "px"
            ]
        ]
    -- This is the content container for the lazy list, inside the scrollable
    -- container. The padding pseudo-elements surround this element.
    out' <- elDynAttr "div" attrs $ elems
    pb <- getPostBuild
    -- Get the scroll event or the initialization event. At init, we still want
    -- to compute the height and scroll information.
    scrollish <- debounce 0 $ leftmost
      [ Right <$> domEvent Scroll viewport
      , Left <$> pb
      ]
    let scrollWithConfig = attach (current $ (,) <$> _lazyListConfig_cardinality cfg <*> _lazyListConfig_rowHeightPx cfg) scrollish
    -- Compute the current scroll window information
    scrollInfoE <- performEvent $ ffor scrollWithConfig $ \((cardinality, rowHeight), x) -> do
      let scroll = case x of
            Left _ -> 0
            Right s -> s
          numExtraElems = 50
      h <- JS.getClientHeight $ _element_raw viewport
      let
        -- How many elements to render
        numElems :: Int = (ceiling $ h / rowHeight) + numExtraElems
        -- the last rendered element index
        bottomIx :: Int = (ceiling $ (scroll + h) / rowHeight) + numExtraElems
        -- the first rendered element index
        topIx :: Int = floor $ scroll / rowHeight
      return $ ScrollInfo
        { _scrollInfo_topIndex = topIx
        , _scrollInfo_numberOfElements = numElems
        , _scrollInfo_paddingTop = fromIntegral topIx * rowHeight
        , _scrollInfo_paddingBottom = fromIntegral (cardinality - bottomIx) * rowHeight
        }
    scrollInfoD <- holdDyn (ScrollInfo 0 0 0 0) scrollInfoE
    return (scrollInfoD, out')
  return (LazyList scrollInfo, out)

-- | Takes the slice of the map that should be rendered, based on the ScrollInfo
lazyListWindow :: Reflex t => Dynamic t ScrollInfo -> Dynamic t (Map k v) -> Dynamic t (Map k v)
lazyListWindow scrollInfo listElems =
  let
    numberElems = fmap _scrollInfo_numberOfElements scrollInfo
    first = fmap _scrollInfo_topIndex scrollInfo
    renderElems = Map.take <$> numberElems <*> (Map.drop <$> ((subtract 1) <$> first) <*> listElems)
  in renderElems
