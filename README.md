reflex-dom-lazy
===============

Because sometimes you don't want to render all your data at once.

Usage
-----

Below is an example of a table with a large number of elements. Using
`Reflex.Dom.Lazy.List` we can render only the relevant window of visible
elements instead of trying to render the entire table. The lazy list widget
manages padding elements around the visible window so that the scrollbar looks
and works as though the entire list is rendered.

```haskell

> {-# Language OverloadedStrings #-}
> {-# Language RecursiveDo #-}
> import Reflex.Dom
> import Reflex.Dom.Attrs
> import Reflex.Dom.Lazy.List
> import Reflex.Dom.Tables
> import qualified Data.Map as Map
> import qualified Data.Text as T
> main :: IO ()
> main = mainWidget $ do
>  el "style" $ text $ T.unlines
>    [ ".flex { display: flex; }"
>    , ".flex-col { flex-direction: column; }"
>    , ".h-full { height: 100%; }"
>    , ".max-h-screen { max-height: 100vh; }"
>    , "thead { background: white; }"

```

The following attributes are applied to the scrollable viewport that contains
the list. The overflow attribute is particularly important!

```haskell

>    , ".flex-1 { flex: 1 1 0%; }"
>    , ".overflow-y-auto { overflow-y: auto; }"
>    , ".overflow-x-hidden { overflow-x: hidden; }"

```

This attribute controls the row height. We expect every row to have the same
height so that we can compute the amount of space to reserve for rows that
haven't been rendered:

```haskell

>    , ".h-[54px] { height: 54px; }"

```

We want the table header to remain visible:

```haskell

>    , ".sticky { position: sticky; top: 0;}"

```

We don't want the body to display a scrollbar, since we want to use the
scrollbar on our scrollable container:

```haskell

>    , "body { overflow-y: hidden; }"

```

These miscellaneous attributes are used for table and cell rendering:

```haskell

>    , ".w-full { width: 100%; }"
>    , ".whitespace-nowrap { white-space: nowrap; }"
>    , ".inline { display: inline; }"
>    ]
>  divClass "flex flex-col h-full max-h-screen" $ do
>    rec

```

Our lazy list configuration requires knowledge of the row height and total
number of elements we plan on rendering.

```haskell

>      let cfg = LazyListConfig
>            { _lazyListConfig_identifier = "example-table"
>            , _lazyListConfig_rowHeightPx = 54
>            , _lazyListConfig_cardinality = 2000
>            , _lazyListConfig_viewportAttrs = [ "class" ~: "flex-1 overflow-y-auto overflow-x-hidden" ]
>            }
>      (LazyList scrollInfo, listOut) <- lazyList cfg $ do
>          let elems = Map.fromList <$> (take <$> _lazyListConfig_cardinality cfg <*> pure (zip [1..] [1..]))

```

Using `Reflex.Dom.Lazy.List.lazyListWindow` we can slice the input map so that
it only contains the visible elements (plus some buffer).

```haskell

>              renderElems = lazyListWindow scrollInfo elems
>

```

This example uses [`Reflex.Dom.Tables.tableDyn`](https://github.com/reflex-frp/reflex-dom-tables).

```haskell

>          tableDyn renderElems $ def
>            { tableConfig_tableAttrs = ["class" ~: "w-full"]
>            , tableConfig_tbodyAttrs = []
>            , tableConfig_trAttrs = \_ _ -> ["class" ~: "h-[54px]"]
>            , tableConfig_theadAttrs = ["class" ~: "sticky"]
>            , tableConfig_columns =
>                [ TH
>                    ( text "Row Index"
>                    , \_ x -> display x
>                    )
>                , TH
>                    ( text "Some Contents"
>                    , \i x -> elClass "div" "flex whitespace-nowrap" $ do
>                        text "Test Cell Contents"
>                        elClass "pre" "inline" $ display x
>                    )
>                ]
>            }
>    pure ()

```

Hacking
-------

To work on this library, enter the nix shell with the following command:

```bash
nix-shell -A project.haskell-nix
```

Once you're inside that shell, you can use `cabal repl` for quick feedback
while developing. To build and test your changes, run:

```bash
javascript-unknown-ghcjs-cabal build
```

You'll see some output like this:

```
dist-newstyle/build/javascript-ghcjs/ghc-9.12.2/reflex-dom-lazy-0.1.0.0/x/reflex-dom-lazy/build/reflex-dom-lazy/reflex-dom-lazy.jsexe
```

Open `index.html` at that path to run the code from `Readme.lhs` in your browser.
