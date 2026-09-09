# Panels

Six bots share one interface. A person who learns a screen in one of them should
recognise it in the next, and the language they pick in any of them is the same
row in `core`. This is the contract that makes that true.

It lives in `core` because it belongs to no single bot. When it changes, it
changes here first.

Every rule is written as **"is exactly"**, not "must contain". That distinction
is the whole reason this file exists: the earlier About-card rule said what a
card must include and said nothing about what it must not, so every bot kept
whatever it already had underneath — one printed a commit hash, another a build
timestamp, and both were following the rule as written.

## The nine rules

**R1 — A panel is title, hint, quote.** Bold title, italic one-line hint, then
the substance in `<blockquote>`. Built by ONE named helper per bot and used by
every screen, including Home, Help and About. Never assembled inline.

A screen whose substance is entirely in its keyboard has no quote — the language
picker, an option grid — because R7 forbids restating the buttons in the body.
The helper emits no blockquote rather than an empty one.

**R2 — One word for going up, and it is "Back".** However deep the screen. The
callback target differs per screen; the word does not. "Menu" and "Home" as
navigation labels are retired.

**R3 — Close exists only in a group, and it is Danger.** In a direct chat the
conversation is the panel: closing it deletes the thing the person is reading.
In a group the panel is one person's menu in everyone else's feed, so dismissing
it is not optional.

This governs *menu panels*. A result surface — a media grid, a generated
collage — is content rather than navigation, and may offer dismissal in either
scope, because there the thing being closed is not the conversation.

**R4 — At most one Primary per screen.** It marks the single thing a person most
likely came to do, and the choice must be defensible in one sentence. A screen
where nothing leads takes no colour. Two Primaries single out neither.

**R5 — Success means "this is the state you are in", and never sits on a button
that acts.** The current language, the open tab: tapping either again does
nothing, which is what earns them the colour.

The near miss is a toggle. A switch does report its state — and the same tap
turns it off, so Success there would be the colour for "this is how things are"
sitting on the control that undoes it. Toggles keep the glyph and take no
colour. The practical half agrees: a mark is a signal when it is on one option
out of a set, and wallpaper when it can be on all of them at once.

**R6 — Danger destroys or dismisses.** Close, Delete, Disconnect. Nothing else.

**R7 — Selection shows in both states.** `◉ ` chosen, `◎ ` not chosen, on every
option of the set, so the column has one left edge. Multi-select sets use
`■ `/`□ ` — the pick-one and pick-any distinction is worth keeping visible.
State lives on the buttons, never as a list in the body repeating them.

**R8 — The language set is one list in one order.**

```
en 🇬🇧 English      ru 🇷🇺 Русский       uk 🇺🇦 Українська   es 🇪🇸 Español
fr 🇫🇷 Français     de 🇩🇪 Deutsch       it 🇮🇹 Italiano     pl 🇵🇱 Polski
cs 🇨🇿 Čeština      tr 🇹🇷 Türkçe        sv 🇸🇪 Svenska      be 🇧🇾 Беларуская
ca 🇦🇩 Català       zh 🇨🇳 中文           ja 🇯🇵 日本語        ar 🇦🇪 العربية
```

Two buttons per row, flag plus native name. A bot with fewer locales shows fewer
buttons in that same order and format — never a different format. Three
hand-maintained copies of this list drifted into three different orders once;
if a fourth copy appears, generate it.

**R9 — A panel carries no emoji.** Not in titles, section headers, button labels
or the rows inside a quote. There is no exception for statistics markers: "no
emoji except as row markers in a statistics block" is not a rule anyone can
check, and one bot already rendered that panel with none and read fine.

Notifications are not panels. A status line delivered outside a panel may carry
a glyph where it is the only thing separating a warning from a wait at a glance.
Flags in the language picker are content. `◉`/`◎`/`■`/`□` are the marks of R7,
not decoration, and pagination arrows are direction.

## The About card

Exactly this, and nothing else:

```
<b>Name</b> · <i>vX.Y.Z</i>
One line of what the bot is.

<blockquote>One bot-specific fact · its value
Source · <a href="…">Org/repo</a> · LICENCE
Admin · <a href="https://t.me/amtiyo">@amtiyo</a></blockquote>
```

No commit hash, no build timestamp, no extra rows. The repository is a link
inside the text and never also a button — two controls for one action is one too
many. Vido is the one exception: its repository is private, so it states no
Source row rather than pointing at something the reader cannot open.

## The language screen

```
Language
Applies to this bot's replies, and is shared with the other bots.

[◉ 🇬🇧 English]    [◎ 🇷🇺 Русский]     ← the current one is Success
[◎ 🇺🇦 Українська] [◎ 🇪🇸 Español]
…
[Follow Telegram]                     ← withdraws the manual choice
[Back]  [Close]                       ← Close only in a group, Danger
```

Picking a language writes a `manual` observation, and manual outranks every
automatic source for ever — so without a way back, one wrong tap is permanent.
That is what **Follow Telegram** is for. It calls `core.clear_language`, which
deletes *this bot's* observation and re-resolves; a sibling's manual claim
survives and then wins. It is not a seventeenth language, so it carries no
selection mark, and it performs an action, so under R5 it carries no colour.

Three things worth knowing before relying on it:

- It clears one bot's claim, not the person's language. This is "stop asserting
  a language", not "reset the user".
- It also deletes the weakest `client` row — the Telegram `language_code` hint
  `core.touch` records. That row returns on the person's next interaction, so
  strictly the hint wins again from the next touch, not from the instant of the
  tap.
- The panel should redraw the picker, in whatever the language resolved to. Not
  the screen named after the code that was tapped.

```sql
core.set_language(<bot>, 'user', <user_id>, <lang>, 'manual')  -- pick
core.clear_language(<bot>, 'user', <user_id>)                  -- follow Telegram
core.effective_language(<user_id>, NULL, 'user')               -- read; NULL = none
```

All three are `EXECUTE`-granted per bot role and revoked from `PUBLIC` — see
migration 012, and revoke `PUBLIC` in the same migration that creates any new
one.

## Where the buttons come from

Button styles are Bot API 9.4+, and the three client stacks in the family spell
them differently. The wire values are identical: `primary`, `success`, `danger`.

| Bot | Client | Style constant |
|:--|:--|:--|
| voicy, searchy, branchy, makeitMD | `FreshLabDev/tg` | `tg.StylePrimary` / `StyleSuccess` / `StyleDanger` |
| vido | python-telegram-bot 22.8 | `telegram.constants.KeyboardButtonStyle` |
| quoto | aiogram 3.25 | `aiogram.enums.ButtonStyle` |

Vido runs aiogram too, but only for its media sender; its panels are
python-telegram-bot. Check which one a file imports before reaching for a
constant.

## Reference

**voicy** is the reference implementation. When a rule is ambiguous, read
`voicy/internal/bot/menu.go`, `internal/i18n/i18n.go`, `internal/transcript/format.go`
and `internal/db/store.go`, and do what they do — with the caveat that being the
reference is a claim to re-check rather than trust: an audit against this
contract found four of its screens assembling their own HTML and one option set
missing half its marks.
