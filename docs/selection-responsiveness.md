# Clipboard selection responsiveness

## Problem and intended behavior

The original card attaches competing single-click and double-click handlers.
In a native event comparison, the single-click selection callback took about
359 ms to run. That delay happens before the selected card ID changes.

Selection can safely happen on the first completed click, including when that
click becomes the first half of a double-click. A subsequent double-click can
paste the selected clip. The implementation uses Apple's built-in
[simultaneous gesture composition](https://developer.apple.com/documentation/swiftui/view/simultaneousgesture(_:including:))
to allow those actions to cooperate.

macOS already supplies mouse events and their
[click counts](https://developer.apple.com/documentation/appkit/nsevent/clickcount).
The app defines what those inputs mean for a clipboard card; it does not add a
custom timer or implement double-click recognition itself.

Expected behavior:

- A completed single click selects the card promptly and never pastes.
- An unmodified double-click selects on the first click and pastes once.
- Shift-click extends the selection range; Command-click toggles a card.
- Command takes precedence when Command and Shift are held together.
- Modified double-clicks change selection without pasting.
- Clicking leaves the card under the pointer so a second click reaches it.
- Keyboard and programmatic selection retain the configured center/right-edge
  scroll position. This includes navigation after a mouse selection.

Keeping clicked cards stationary is an intentional behavior change. It also
applies to partially visible cards; clicking does not automatically align them.

## Implementation

`ClipCardInteractions` classifies gestures and invokes four callbacks. The
card supplies its existing selection and paste actions, so the modifier does
not own clipboard data or write to the pasteboard.

`ClipboardStore` records whether the selection came from a pointer operation.
Assigning `selectedID` resets this flag; the pointer selection methods set it
after updating the selected ID. `BarView` skips its automatic scroll for those
pointer selections. Arrow navigation and other direct assignments continue
through the existing scroll behavior.

The store also accepts an optional base directory so unit tests can exercise
selection against temporary fixture history instead of the user's history.
Production's shared store keeps its existing default directory selection.

## Reproducing the automated checks

Run the store regression tests:

```sh
swift test
```

The three selection regressions cover mouse-to-keyboard navigation,
Shift/Command multi-selection followed by navigation, and programmatic
selection after clicking. They assert selected IDs and the scrolling flag;
they do not inspect rendered scroll offsets.

Run the native gesture probe from a logged-in macOS GUI session:

```sh
bash scripts/check_card_interactions.sh
```

It compiles the production gesture modifier with a fixture window, posts
events only to that window, prints callback order and latency, and exits
nonzero on failure. Its callbacks record actions rather than invoking the
clipboard store or paste service. The runner removes its temporary build.

The 13 scenarios compare the original and updated handlers, check all the
click combinations above, and check immediate Shift/Command release after
clicking. Drag and context-menu modifiers are attached to the fixture to match
the card's gesture environment; this probe does not exercise dragging or
context-menu actions.

The updated handlers must deliver the first expected callback within 150 ms.
That limit leaves room for a loaded development machine while catching a
return of the observed delay. An explicit override is available:

```sh
PESTY_PROBE_MAX_LATENCY_MS=200 bash scripts/check_card_interactions.sh
```

Synthetic events supply their click counts explicitly. This verifies how the
handlers respond to recognized clicks, rather than the OS's classification of
physical mouse input. Callback latency is not a frame-rendering or total
end-to-end latency measurement. The GUI probe is separate from headless CI.

Run the actual-strip integration probe from the same GUI session:

```sh
bash scripts/check_bar_navigation.sh
```

It compiles the real `BarView`, `ClipCardView`, and `ClipboardStore` with a
fixture entry point in place of the normal app entry point. It creates 40 text
clips in a disposable home directory. A safety check verifies the redirected
home, application-support path, and fixture marker before creating the store.
The runner removes that directory after the probe exits. Clipboard polling,
the production app delegate, and the global hotkey are never started.

This probe posts clicks to its own window and inspects the actual scroll
view's visible rectangle. It checks mouse selection, offscreen navigation,
right-edge alignment, context-menu opening, and Escape dismissal. Navigation
calls the store method used by the key handler, so it exercises rendering and
scrolling without testing physical arrow-key routing. It does not invoke paste
or context-menu actions. Both GUI probes have timeouts to avoid stuck test
windows.

## Recorded validation

Environment: Apple Silicon, macOS 15.7.5 (24G624), Swift 6.2.4.

- All 10 unit tests passed, including the three selection regressions.
- The checked-in native probe passed all 13 scenarios. Its original single
  click took 360.7 ms; the updated selection callbacks took 2.4–4.8 ms in that
  run. Earlier isolated runs measured about 359 ms versus 2–18 ms.
- The universal release app built for arm64 and x86_64.
- The updated app was installed and the user confirmed improved selection
  responsiveness.
- The actual-strip integration probe passed all 10 checks: the fixture strip
  was found, clicking selected the second card without changing the scroll
  offset, navigation selected and revealed an offscreen card, the right-edge
  setting aligned it, the context menu opened without changing selection, and
  Escape dismissed it.

## Full-app review checklist and coverage boundaries

Use ordinary fixture text in the running app and enough history to scroll:

- Click a card near either visible edge, then double-click it. Confirm the
  first click leaves it under the pointer and the double-click pastes once.
- In both center and right-edge navigation modes, use arrow keys until the
  selection leaves the initial viewport. Confirm it remains visible. Click a
  card, then resume arrow navigation to verify scrolling resumes.
- Drag a text, image, and file card to an accepting destination. Confirm the
  expected content arrives and dragging does not accidentally paste.
- Open a card's context menu, dismiss it, reopen it, and exercise an action
  using fixture data. Confirm subsequent ordinary clicks still select.

The automated checks do not establish all of these behaviors. Physical
drag/drop, context-menu actions, external-app paste, physical key routing,
macOS 14/26 runtime behavior, and Intel runtime behavior require their own
checks. Building the Intel slice verifies compilation, not Intel interaction
behavior. The native integration probe covers the strip, not the full
production window/hotkey/paste pipeline.

The change does not alter visual styling, so there is no styling screenshot
delta. Selection timing and mouse scrolling behavior change as described above.
