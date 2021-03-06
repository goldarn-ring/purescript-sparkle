-- | Sparkle is a library that automatically creates interactive user interfaces from type
-- | signatures.
module Sparkle
  ( class Flammable
  , examples
  , spark
  , class FlammableRowList
  , examplesRecord
  , sparkRecord
  , NonNegativeInt(..)
  , SmallInt(..)
  , SmallNumber(..)
  , Multiline(..)
  , WrapEnum(..)
  , class Interactive
  , interactive
  , interactiveGeneric
  , interactiveShow
  , interactiveFoldable
  , class PrettyPrintRowList
  , prettyPrintRowList
  , Renderable(..)
  , sparkleDoc'
  , sparkleDoc
  , sparkle'
  , sparkle
  ) where

import Prelude

import Color (Color, hsl, cssStringHSLA, toHSLA, black)
import Control.Monad.Eff (Eff)
import DOM (DOM)
import DOM.Node.Types (Element)
import Data.Array as A
import Data.Array.Partial as AP
import Data.Char (toCharCode)
import Data.Either (Either(..))
import Data.Enum (class BoundedEnum, succ, enumFromTo)
import Data.Foldable (class Foldable, for_)
import Data.Generic (class Generic, GenericSpine(..), toSpine)
import Data.List (List(..), fromFoldable, singleton, (:))
import Data.List.NonEmpty (NonEmptyList(..), toList)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.NonEmpty (NonEmpty, (:|))
import Data.Number.Format (toStringWith, precision)
import Data.Record (insert, get, delete)
import Data.String (Pattern(..), split, length, charAt)
import Data.String as S
import Data.Symbol (class IsSymbol, SProxy(..), reflectSymbol)
import Data.Tuple (Tuple(..))
import Flare (Label, ElementId, UI, setupFlare, fieldset, string, radioGroup, boolean, stringPattern, int, intRange, intSlider, number, numberSlider, select, color, resizableList_, textarea)
import Partial.Unsafe (unsafePartial)
import Signal (runSignal)
import Signal.Channel (CHANNEL)
import Text.Smolder.HTML (pre, span, div) as H
import Text.Smolder.HTML.Attributes as HA
import Text.Smolder.Markup (Markup, text) as H
import Text.Smolder.Markup ((!))
import Text.Smolder.Renderer.String (render) as H
import Type.Prelude (class RowToList)
import Type.Row (kind RowList, class RowLacks, Nil, Cons, RLProxy(..))

-- | A type class for data types that can be used for interactive Sparkle UIs. Instances for type
-- | `a` must provide a way to create a Flare UI which holds a value of type `a`.
class Flammable a where
  examples ∷ NonEmpty List a
  spark ∷ ∀ e. a → UI e a

instance flammableNumber ∷ Flammable Number where
  examples = 0.618034 :| 3.14 : 42.0 : -1.0 : 1.0e5 : Nil
  spark = number "Number"

instance flammableInt ∷ Flammable Int where
  examples = 1 :| 42 : -200 : 1337 : 0 : Nil
  spark = int "Int"

instance flammableString ∷ Flammable String where
  examples = "foo" :| "bar" : "I ❤ unicode" : Nil
  spark = string "String"

instance flammableChar ∷ Flammable Char where
  examples = 'f' :| '#' : 'K' : Nil
  spark default = fromMaybe ' ' <$> charAt 0 <$> stringPattern "Char" "^.$" (S.singleton default)

instance flammableBoolean ∷ Flammable Boolean where
  examples = false :| true : Nil
  spark = boolean "Boolean"

head ∷ ∀ a. NonEmpty List a → a
head (x :| _) = x

intercalate_ :: forall m a b. Apply m => Applicative m => m b -> List (m a) -> m Unit
intercalate_ sep (x : xs) = x *> for_ xs ((*>) sep)
intercalate_ sep Nil = pure unit

instance flammableTuple ∷ (Flammable a, Flammable b) ⇒ Flammable (Tuple a b) where
  examples =
    case examples of
      l1 :| l2 : _ →
        case examples of
          r1 :| r2 : _ → Tuple l1 r1 :| Tuple l1 r2 : Tuple l2 r1 : Tuple l2 r2 : Nil
          r1 :| _      → Tuple l1 r1 :| Tuple l2 r1 : Nil
      l1 :| _ →
        case examples of
          r1 :| r2 : _ → Tuple l1 r1 :| Tuple l1 r2 : Nil
          r1 :| _      → Tuple l1 r1 :| Nil

  spark (Tuple a b) = fieldset "Tuple" $ Tuple <$> spark a <*> spark b

instance flammableMaybe ∷ (Flammable a) ⇒ Flammable (Maybe a) where
  examples = case examples of
               x :| xs → Just x :| Nothing : (Just <$> xs)

  spark init = fieldset "Maybe" $ toMaybe <$> boolean "Just/Nothing" (isJust init) <*> spark (default init)
    where toMaybe true x  = Just x
          toMaybe false _ = Nothing
          isJust (Just _) = true
          isJust Nothing = false
          default (Just a) = a
          default Nothing = head examples

instance flammableEither ∷ (Flammable a, Flammable b) ⇒ Flammable (Either a b) where
  examples =
    case examples of
      l1 :| l2 : _ →
        case examples of
          r1 :| r2 : _ → Right r1 :| Left l1 : Right r2 : Left l2 : Nil
          r1 :| _      → Left l1 :| Right r1 : Left l2 : Nil
      l1 :| _ →
        case examples of
          r1 :| r2 : _ → Right r1 :| Left l1 : Right r2 : Nil
          r1 :| _      → Right r1 :| Left l1 : Nil

  spark default = fieldset "Either" $
                    toEither <$> radioGroup "Select:" ("Left" :| ["Right"]) id
                             <*> spark exl
                             <*> spark exr
    where toEither "Left" x _ = Left x
          toEither _      _ y = Right y
          exl = case default of
                  Left l → l
                  Right _ → head examples
          exr = case default of
                  Right r → r
                  Left _ → head examples

instance flammableColor ∷ Flammable Color where
  examples = hsl 216.0 1.0 0.42 :| hsl 120.0 0.7 0.8 : black : Nil
  spark = color "Color"

-- | A helper type class to implement a `Flammable` instance for records.
class FlammableRowList
        (list ∷ RowList)
        (row ∷ # Type)
        | list → row where
  examplesRecord ∷ RLProxy list → NonEmpty List (Record row)
  sparkRecord ∷ ∀ e. RLProxy list → UI e (Record row)

instance flammableListNil ∷ FlammableRowList Nil () where
  examplesRecord _ = {} :| Nil
  sparkRecord _ = pure {}

instance flammableListCons ∷
  ( Flammable a
  , FlammableRowList listRest rowRest
  , RowLacks s rowRest
  , RowCons s a rowRest rowFull
  , RowToList rowFull (Cons s a listRest)
  , IsSymbol s
  ) ⇒ FlammableRowList (Cons s a listRest) rowFull where
  examplesRecord _ = insert (SProxy ∷ SProxy s)
                           (head examples ∷ a)
                           (head (examplesRecord (RLProxy ∷ RLProxy listRest)) ∷ Record rowRest) :| Nil
  sparkRecord _ = insert (SProxy ∷ SProxy s)
                    <$> fieldset (reflectSymbol (SProxy ∷ SProxy s)) (spark (head examples))
                    <*> (sparkRecord (RLProxy ∷ RLProxy listRest) ∷ ∀ e. UI e (Record rowRest))

instance flammableRecord ∷
  ( RowToList row list
  , FlammableRowList list row
  ) ⇒ Flammable (Record row) where
  examples = examplesRecord (RLProxy ∷ RLProxy list)
  spark _ = fieldset "Record" (sparkRecord (RLProxy ∷ RLProxy list))

-- | A newtype for non-negative integer values.
newtype NonNegativeInt = NonNegativeInt Int

derive instance genericNonNegativeInt ∷ Generic NonNegativeInt

instance flammableNonNegativeInt ∷ Flammable NonNegativeInt where
  examples = NonNegativeInt 1 :| NonNegativeInt 500 : Nil
  spark (NonNegativeInt d) = NonNegativeInt <$> intRange "Int" 0 top d

-- | A newtype for small integer values in the range from 0 to 100.
newtype SmallInt = SmallInt Int

derive instance genericSmallInt ∷ Generic SmallInt

instance flammableSmallInt ∷ Flammable SmallInt where
  examples = SmallInt 1 :| SmallInt 50 : Nil
  spark (SmallInt d) = SmallInt <$> intSlider "Int" 0 100 d

-- | A newtype for numbers in the closed interval from 0.0 and 1.0.
newtype SmallNumber = SmallNumber Number

derive instance genericSmallNumber ∷ Generic SmallNumber

instance flammableSmallNumber ∷ Flammable SmallNumber where
  examples = SmallNumber 0.5 :| SmallNumber 0.0 : SmallNumber 0.9 : Nil
  spark (SmallNumber d) = SmallNumber <$> numberSlider "Number" 0.0 1.0 0.00001 d

-- | A newtype for strings where "\n" is parsed as a newline
-- | (instead of "\\n").
newtype Multiline = Multiline String

derive instance genericMultiline ∷ Generic Multiline

instance flammableMultiline ∷ Flammable Multiline where
  examples = Multiline "foo\nbar" :| Nil
  spark (Multiline d) = Multiline <$> textarea "Multiline" d

newtype WrapEnum a = WrapEnum a

instance flammableWrapEnum ∷ (BoundedEnum a, Show a) ⇒ Flammable (WrapEnum a) where
  examples = WrapEnum bottom :| WrapEnum top : Nil
  spark _ = WrapEnum <$> select "Enum" (bottom :| rest) show
    where
      rest ∷ Array a
      rest = fromMaybe [] do
        mSucc ← succ bottom
        pure (enumFromTo mSucc top)

instance flammableList ∷ Flammable a ⇒ Flammable (List a) where
  examples = singleton (head examples) :| Nil
  spark _ = fieldset "List" (resizableList_ spark
                                            (head examples)
                                            (toList (NonEmptyList examples)))

instance flammableArray ∷ Flammable a ⇒ Flammable (Array a) where
  examples = [head examples] :| Nil
  spark _ = A.fromFoldable <$> fieldset "Array" (resizableList_ spark
                                                                (head examples)
                                                                (toList (NonEmptyList (examples :: NonEmpty List a))))

-- | A data type that describes possible output actions and values for an interactive test.
data Renderable
  = SetText String
  | SetHTML (H.Markup Unit)

-- | A type class for interactive UIs. Instances must provide a way to create a Flare UI which
-- | returns a `Renderable` output.
class Interactive t where
  interactive ∷ ∀ e. UI e t → UI e Renderable

-- | A default `interactive` implementation for any `Show`able type.
interactiveShow ∷ ∀ t e. (Show t) ⇒ UI e t → UI e Renderable
interactiveShow = map (SetText <<< show)

-- | A default `interactive` implementation for `Foldable` types.
interactiveFoldable ∷ ∀ f a e
                     . Foldable f
                    ⇒ Generic a
                    ⇒ UI e (f a)
                    → UI e Renderable
interactiveFoldable = map (SetHTML <<< H.pre <<< markup)
  where
    markup val = do
      H.text "fromFoldable "
      prettyPrint (A.fromFoldable val)

-- | Takes a CSS classname and a `String` and returns a 'syntax highlighted'
-- | version of the `String`.
highlight ∷ ∀ e. String → String → H.Markup e
highlight syntaxClass value =
  H.span ! HA.className ("sparkle-" <> syntaxClass) $ H.text value

-- | Add a tooltip to an element.
tooltip ∷ ∀ e. String → H.Markup e → H.Markup e
tooltip tip = H.span ! HA.className "sparkle-tooltip" ! HA.title tip

-- | Extract the constructor name from a string like `Data.Tuple.Tuple`.
constructor ∷ ∀ e. String → H.Markup e
constructor long = tooltip modString $ highlight "constructor" name
  where
    parts = split (Pattern ".") long
    name = unsafePartial (AP.last parts)
    modString =
      if A.length parts == 1
        then "Data constructor form unknown module"
        else long

-- | Pretty print a `GenericSpine`. This is an adapted version of `Data.Generic.genericShowPrec`.
prettyPrec ∷ ∀ e. Int → GenericSpine → H.Markup e
prettyPrec d (SProd s arr) = do
  if (A.null arr)
    then constructor s
    else do
      showParen (d > 10) $ do
        constructor s
        for_ arr \f → do
          H.text " "
          prettyPrec 11 (f unit)
  where showParen false x = x
        showParen true  x = do
          H.text "("
          x
          H.text ")"

prettyPrec d (SRecord arr) = do
  H.text "{\n  "
  intercalate_ (H.text ",\n  ") (fromFoldable $ map recEntry arr)
  H.text "\n}"
    where
      recEntry x = do
        highlight "record-field" x.recLabel
        H.text ": "
        prettyPrec 0 (x.recValue unit)

prettyPrec d (SBoolean x)  = tooltip "Boolean" $ highlight "boolean" (show x)
prettyPrec d (SNumber x)   = tooltip "Number"  $ highlight "number" (show x)
prettyPrec d (SInt x)      = tooltip "Int"     $ highlight "number" (show x)
prettyPrec d SUnit         = tooltip "Unit"    $ H.text (show unit)
prettyPrec d (SString x)   = tooltip tip       $ highlight "string" (show x)
  where tip = "String of length " <> show (length x)
prettyPrec d (SChar x)     = tooltip tip       $ highlight "string" (show x)
  where tip = "Char (with char code " <> show (toCharCode x) <> ")"
prettyPrec d (SArray arr)  = tooltip tip $ do
  H.text "["
  intercalate_ (H.text ", ") (fromFoldable $ map (\x → prettyPrec 0 (x unit)) arr)
  H.text "]"
    where tip = "Array of length " <> show (A.length arr)

-- | Pretty print a `GenericSpine`.
pretty ∷ ∀ e. GenericSpine → H.Markup e
pretty = prettyPrec 0

-- | Pretty print a value which has a `Generic` type.
prettyPrint ∷ ∀ a e. Generic a ⇒ a → H.Markup e
prettyPrint = toSpine >>> pretty

-- | A default `interactive` implementation for types with a `Generic` instance.
interactiveGeneric ∷ ∀ a e. (Generic a) ⇒ UI e a → UI e Renderable
interactiveGeneric ui = ((SetHTML <<< H.pre <<< prettyPrint) <$> ui)

instance interactiveNumber ∷ Interactive Number where
  interactive = interactiveGeneric

instance interactiveInt ∷ Interactive Int where
  interactive = interactiveGeneric

instance interactiveString ∷ Interactive String where
  interactive = interactiveGeneric

instance interactiveChar ∷ Interactive Char where
  interactive = interactiveGeneric

instance interactiveBoolean ∷ Interactive Boolean where
  interactive = map (SetHTML <<< markup)
    where
      classN true  = "sparkle-okay"
      classN false = "sparkle-warn"
      markup v = H.pre ! HA.className (classN v) $ prettyPrint v

instance interactiveOrdering ∷ Interactive Ordering where
  interactive = interactiveShow

instance interactiveGenericSpine ∷ Interactive GenericSpine where
  interactive = map (SetHTML <<< H.pre <<< pretty)

instance interactiveMaybe ∷ Generic a ⇒ Interactive (Maybe a) where
  interactive = map (SetHTML <<< markup)
    where
      classN Nothing  = "sparkle-warn"
      classN _        = ""
      markup v = H.pre ! HA.className (classN v) $ prettyPrint v

instance interactiveEither ∷ (Generic a, Generic b) ⇒ Interactive (Either a b) where
  interactive = map (SetHTML <<< markup)
    where
      classN (Left _) = "sparkle-warn"
      classN _        = ""
      markup v = H.pre ! HA.className (classN v) $ prettyPrint v

instance interactiveTuple ∷ (Generic a, Generic b) ⇒ Interactive (Tuple a b) where
  interactive = interactiveGeneric

instance interactiveArray ∷ Generic a ⇒ Interactive (Array a) where
  interactive = map (SetHTML <<< markup)
    where
      classN [] = "sparkle-warn"
      classN _  = ""
      markup v = H.pre ! HA.className (classN v) $ prettyPrint v

instance interactiveList ∷ Generic a ⇒ Interactive (List a) where
  interactive = interactiveFoldable

instance interactiveColor ∷ Interactive Color where
  interactive = map (SetHTML <<< markup)
    where
      markup c =
        let cssHSLA = cssStringHSLA c
            style = "background-color: " <> cssHSLA
            col = toHSLA c
            showN = toStringWith (precision 4)
        in H.pre $ do
          H.div ! HA.style style ! HA.className "sparkle-color" $ H.text ""
          H.text $ "(Color.hsl " <> showN col.h <> " " <> showN col.s <> " " <> showN col.l <> ")"

-- | A helper type class to implement an `Interactive` instance for records.
class PrettyPrintRowList
        (list ∷ RowList)
        (row ∷ # Type)
        | list → row where
  prettyPrintRowList ∷ RLProxy list → Record row → List (Tuple String (H.Markup Unit))

instance prettyPrintRowListNil ∷ PrettyPrintRowList Nil () where
  prettyPrintRowList _ _ = Nil

instance prettyPrintRowListCons ∷
  ( Generic a
  , PrettyPrintRowList listRest rowRest
  , RowLacks s rowRest
  , RowCons s a rowRest rowFull
  , RowToList rowFull (Cons s a listRest)
  , IsSymbol s
  ) ⇒ PrettyPrintRowList (Cons s a listRest) rowFull where
  prettyPrintRowList _ record =
    Tuple key value : rest
    where
      keySymbol = SProxy ∷ SProxy s
      key = reflectSymbol keySymbol
      value = prettyPrint (get keySymbol record)
      rest = prettyPrintRowList (RLProxy ∷ RLProxy listRest) (delete keySymbol record)

instance interactiveRecordInstance ∷
  ( RowToList row list
  , PrettyPrintRowList list row
  ) ⇒ Interactive (Record row) where
  interactive = map (SetHTML <<< prettyPrintRecord)
    where
      prettyPrintRecord ∷ Record row → H.Markup Unit
      prettyPrintRecord record = H.pre do
        H.text "{\n  "
        intercalate_ (H.text ",\n  ") (map recEntry entries)
        H.text "\n}"

        where
          entries = prettyPrintRowList (RLProxy ∷ RLProxy list) record

      recEntry (Tuple label value) = do
        highlight "record-field" label
        H.text ": "
        value

instance interactiveWrapEnum ∷ Generic a ⇒ Interactive (WrapEnum a) where
  interactive = interactiveGeneric <<< map unwrap
    where unwrap (WrapEnum e) = e

instance interactiveFunction ∷ (Flammable a, Interactive b) ⇒ Interactive (a → b) where
  interactive f = interactive (f <*> spark (head examples))

-- | Append a new interactive test. The arguments are the ID of the parent element, the title for
-- | the test, a documentation string and the list of Flare components. Returns the element for the
-- | output of the test.
foreign import appendTest ∷ ∀ e
                          . ElementId
                          → String
                          → String
                          → Array Element
                          → Eff (dom ∷ DOM | e) Element

-- | Write the string to the specified output element.
foreign import setText ∷ ∀ e
                       . Element
                       → String
                       → Eff (dom ∷ DOM | e) Unit

-- | Set innerHTML of the specified output element.
foreign import setHTML ∷ ∀ e
                       . Element
                       → String
                       → Eff (dom ∷ DOM | e) Unit

render ∷ ∀ e. Element
       → Renderable
       → Eff (dom ∷ DOM | e) Unit
render output (SetText str) = setText output str
render output (SetHTML markup) = setHTML output (H.render markup)

-- | Run an interactive test. The ID specifies the parent element to which the test will be
-- | appended and the label provides a title for the test. The String argument is an optional
-- | documentation string.
sparkleDoc' ∷ ∀ t e
            . Interactive t
            ⇒ ElementId
            → Label
            → Maybe String
            → t
            → Eff (channel ∷ CHANNEL, dom ∷ DOM | e) Unit
sparkleDoc' parentId title doc x = do
  let flare = interactive (pure x)
  { components, signal } ← setupFlare flare
  let docString = fromMaybe "" doc
  output ← appendTest parentId title docString components
  runSignal (render output <$> signal)

-- | Run an interactive test. The label provides a title for the test. The `String` argument is an
-- | optional documentation string.
sparkleDoc ∷ ∀ t e
           . Interactive t
           ⇒ Label
           → Maybe String
           → t
           → Eff (channel ∷ CHANNEL, dom ∷ DOM | e) Unit
sparkleDoc = sparkleDoc' "tests"

-- | Run an interactive test. The ID specifies the parent element to which the test will be
-- | appended and the label provides a title for the test.
sparkle' ∷ ∀ t e
         . Interactive t
         ⇒ ElementId
         → Label
         → t
         → Eff (channel ∷ CHANNEL, dom ∷ DOM | e) Unit
sparkle' id label = sparkleDoc' id label Nothing

-- | Run an interactive test. The label provides a title for the test.
sparkle ∷ ∀ t e
        . Interactive t
        ⇒ Label
        → t
        → Eff (channel ∷ CHANNEL, dom ∷ DOM | e) Unit
sparkle = sparkle' "tests"
