
-----------------------------------------------------------------------------
-- |
-- Module      :  Text.BlogLiterately.Highlight
-- Copyright   :  (c) 2008-2010 Robert Greayer, 2012 Brent Yorgey
-- License     :  GPL (see LICENSE)
-- Maintainer  :  Brent Yorgey <byorgey@gmail.com>
--
-- XXX write me
--
-----------------------------------------------------------------------------

module Text.BlogLiterately.Highlight
    (

    ) where

{-

The literate Haskell that Pandoc finds in a file ends up in various
`CodeBlock` elements of the `Pandoc` document.  Other code can also
wind up in `CodeBlock` elements -- normal markdown formatted code.
The `Attr` component has metadata about what's in the code block:

    [haskell]
    type Attr = ( String,             -- code block identifier
                , [String]            -- list of code classes
                , [(String, String)]  -- name/value pairs
                )

Thanks to some feedback from the Pandoc author, John MacFarlane, I
learned that the CodeBlock *may* contain markers about the kind of
code contained within the block.  LHS (bird-style or LaTex style) will
always have an `Attr` of the form `("",["sourceCode","haskell"],[])`,
and other `CodeBlock` elements are the markdown code blocks *may* have
an identifier, classes, or key/value pairs.  Pandoc captures this info
when the file contains code blocks in the delimited (rather than
indented) format, which allows an optional meta-data specification,
e.g.

~~~~~~~~~~~
~~~~~~~ { .bash }
x=$1
echo $x
~~~~~~~
~~~~~~~~~~~

Although Pandoc supports the above format for marking code blocks (and
annotating the kind of code within the block) I'll also keep my
notation as another option for use with indented blocks, i.e. if you
write:

<pre><code>
    [haskell]
    foo :: String -> String
</code></pre>

it is a Haskell block.  You can also use other annotations, *e.g.*

<pre><code>
    [cpp]
    cout << "Hello World!";
</code></pre>

If highlighting-kate is specified for highlighting Haskell blocks, the
distinction between the literate blocks and the delimited blocks is
lost (this is simply how the Pandoc highlighting module currently
works).

I'll adopt the rule that if you specify a class or classes using
Pandoc's delimited code block syntax, I'll assume that there is no
additional tag within the block in Blog Literately syntax.  I still
need my `unTag` function to parse the code block.


To highlight the syntax using hscolour (which produces HTML), I'm
going to need to transform the `String` from a `CodeBlock` element to
a `String` suitable for the `RawHtml` element (because the hscolour
library transforms Haskell text to HTML). Pandoc strips off the
prepended &gt; characters from the literate Haskell, so I need to put
them back, and also tell hscolour whether the source it is colouring
is literate or not.  The hscolour function looks like:

    [haskell]
    hscolour :: Output      -- ^ Output format.
             -> ColourPrefs -- ^ Colour preferences...
             -> Bool        -- ^ Whether to include anchors.
             -> Bool        -- ^ Whether output document is partial or complete.
             -> String      -- ^ Title for output.
             -> Bool        -- ^ Whether input document is literate haskell
             -> String      -- ^ Haskell source code.
             -> String      -- ^ Coloured Haskell source code.

Since I still don't like the `ICSS` output from hscolour, I'm going to
provide two options for hscolouring to users: one that simply uses
hscolour's `CSS` format, so the user can provide definitions in their
blog's stylesheet to control the rendering, and a post-processing
option to transform the `CSS` class-based rendering into a inline
style based rendering (for people who can't update their stylesheet).
`colourIt` performs the initial transformation:

-}

colourIt literate srcTxt =
    hscolour CSS defaultColourPrefs False True "" literate srcTxt'
    where srcTxt' | literate = prepend srcTxt
                  | otherwise = srcTxt

-- | Prepend literate Haskell markers to some source code.
prepend :: String -> String
prepend = unlines . map ("> " ++) . lines

Hscolour uses HTML `span` elements and CSS classes like 'hs-keyword'
or `hs-keyglyph` to markup Haskell code.  What I want to do is take
each marked `span` element and replace the `class` attribute with an
inline `style` element that has the markup I want for that kind of
source.  Style preferences are specified as a list of name/value
pairs:

> type StylePrefs = [(String,String)]

Here's a default style that produces something like what the source
listings on Hackage look like:

> defaultStylePrefs = [
>     ("hs-keyword","color: blue; font-weight: bold;")
>   , ("hs-keyglyph","color: red;")
>   , ("hs-layout","color: red;")
>   , ("hs-comment","color: green;")
>   , ("hs-conid", "")
>   , ("hs-varid", "")
>   , ("hs-conop", "")
>   , ("hs-varop", "")
>   , ("hs-str", "color: teal;")
>   , ("hs-chr", "color: teal;")
>   , ("hs-number", "")
>   , ("hs-cpp", "")
>   , ("hs-selection", "")
>   , ("hs-variantselection", "")
>   , ("hs-definition", "")]

I can read these preferences in from a file using the `Read` instance
for `StylePrefs`.  I could handle errors better, but this should work:

> getStylePrefs ""    = return defaultStylePrefs
> getStylePrefs fname = liftM read (U.readFile fname)

Hscolour produces a `String` of HTML.  To 'bake' the styles into the
HTML, we need to parse it, manipulate it and then re-render it as a
`String`.  We use HaXml to do all of this:

> bakeStyles :: StylePrefs -> String -> String
> bakeStyles prefs s = verbatim $ filtDoc (xmlParse "bake-input" s)
>   where
>
>     -- filter the document (an Hscoloured fragment of Haskell source)
>     filtDoc (Document p s e m) =  c where
>         [c] = filts (CElem e noPos)
>
>     -- the filter is a fold of individual filters for each CSS class
>     filts = mkElem "pre" [(foldXml $ foldl o keep $ map filt prefs) `o` replaceTag "code"]
>
>     -- an individual filter replaces the attributes of a tag with
>     -- a style attribute when it has a specific 'class' attribute.
>     filt (cls,style) =
>         replaceAttrs [("style",style)] `when`
>             (attrval $ (N "class", AttValue [Left cls]))

Highlighting-Kate uses &lt;br/> in code blocks to indicate newlines.
WordPress (if not other software) chooses to strip them away when
found in &lt;pre> sections of uploaded HTML.  So we need to turn them
back to newlines.

> replaceBreaks :: String -> String
> replaceBreaks s = verbatim $ filtDoc (xmlParse "input" s)
>   where
>     -- filter the document (a highlighting-kate highlighted fragment of
>     -- haskell source)
>     filtDoc (Document p s e m) = c where
>         [c] = filts (CElem e noPos)
>     filts = foldXml (literal "\n" `when` tag "br")

Note to self: the above is a function that could be made better in a
few ways and then factored out into a library.  A way to handle the
above would be to allow the preferences to be specified as an actual
CSS style sheet, which then would be baked into the HTML.  Such a
function could be separately useful, and could be used to 'bake' in
the highlighting-kate styles.

To completely colourise/highlight a `CodeBlock` we now can create a
function that transforms a `CodeBlock` into a `RawHtml` block, where
the content contains marked up Haskell (possibly with literate
markers), or marked up non-Haskell, if highlighting of non-Haskell has
been selected.

> colouriseCodeBlock :: HsHighlight -> Bool -> Block -> Block
> colouriseCodeBlock hsHighlight otherHighlight b@(CodeBlock attr@(_,classes,_) s)
>
>   | tag == "haskell" || haskell
>   = case hsHighlight of
>         HsColourInline style ->
>             RawBlock "html" $ bakeStyles style $ colourIt lit src
>         HsColourCSS   -> RawBlock "html" $ colourIt lit src
>         HsNoHighlight -> RawBlock "html" $ simpleHTML hsrc
>         HsKate        -> if null tag
>             then myHighlightK attr hsrc
>             else myHighlightK ("",tag:classes,[]) hsrc
>
>   | otherHighlight
>   = case tag of
>         "" -> myHighlightK attr src
>         t  -> myHighlightK ("",[t],[]) src
>
>   | otherwise
>   = RawBlock "html" $ simpleHTML src
>
>   where
>     (tag,src)
>         | null classes = unTag s
>         | otherwise    = ("",s)
>     hsrc
>         | lit          = prepend src
>         | otherwise    = src
>     lit          = "sourceCode" `elem` classes
>     haskell      = "haskell" `elem` classes
>     simpleHTML s = "<pre><code>" ++ s ++ "</code></pre>"
>     myHighlightK attr s = case highlight formatHtmlBlock attr s of
>         Nothing   -> RawBlock "html" $ simpleHTML s
>         Just html -> RawBlock "html" $ replaceBreaks $ renderHtml html
>
> colouriseCodeBlock _ _ b = b

Colourising a `Pandoc` document is simply:

> colourisePandoc hsHighlight otherHighlight (Pandoc m blocks) =
>     Pandoc m $ map (colouriseCodeBlock hsHighlight otherHighlight) blocks
