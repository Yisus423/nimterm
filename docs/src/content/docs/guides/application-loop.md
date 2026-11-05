---
title: Application loop
description: Run a nimterm application, add timers, and connect event sources.
---

`App` owns the work that repeats while your interface is active: collecting
events, dispatching them to the application and widget tree, rendering when the
UI is dirty, and presenting the resulting canvas through the backend.

## Let `App` own the loop

For a standalone terminal program, `run` is the normal entry point:

```nim
import nimterm

var app = newApp(newPlatformBackend(), newText("Ready"))
app.run()
```

`run` requires a backend. It initializes the backend before the first frame and
shuts it down, along with registered event sources, when the loop ends.

## Add timers

Use `schedule` for one-shot or repeating `uiTimer` events. Timer identifiers are
application-defined strings:

```nim
var app = newApp(newPlatformBackend(), newText("Waiting..."))
app.schedule("refresh", delayMs = 1000, intervalMs = 1000)
app.onEvent = proc (app: var App, event: UiEvent): EventResponse =
  if event.kind == uiTimer and event.timerId == "refresh":
    app.invalidate()
  eventIgnored
app.run()
```

Call `cancelTimer("refresh")` to remove every timer with that identifier.
Timers are placed in the same queue as terminal and source events, so your
application sees them through one dispatch path.

## Post an event

Application code can enqueue an event and wake a blocked backend with `post`:

```nim
app.post agentEvent(AgentUiEvent(
  kind: ueTextDelta,
  runId: "run-1",
  step: 0,
  text: "Hello"))
```

`agentEvent` wraps an `AgentUiEvent` as a `uiAgent` event. Use other supported
`UiEventKind` values such as `uiTimer`, `uiError`, or `uiQuit` for application
events that fit those shapes.

## Integrate a host-owned loop

Use `init`, `step`, `flush`, and `shutdown` when another event loop owns the
process:

```nim
var app = newApp(newPlatformBackend(), newText("Ready"))
app.backend.init()
defer: app.backend.shutdown()

app.running = true
app.render()
while app.running:
  discard app.step(timeoutMs = 100)
  app.flush()
```

`step` processes at most one queued, source, or backend event. It returns
`false` when no event was available. `flush` presents only when the app is
dirty, unless you pass `force = true`.

Keyboard events flush immediately. For streamed or background updates, set
`minFrameIntervalMs` to limit presentation frequency, then call `flush` from
your host loop when the app has no event:

```nim
app.minFrameIntervalMs = 33  # about 30 fps
```

`pollIntervalMs` controls how often idle apps poll event sources that return
`needsPolling = true`. The default is 16 milliseconds.

## Add an event source

Subclass `EventSource` when your application already has a pollable producer:

```nim
type MessageSource = ref object of EventSource
  messages: seq[string]

method poll(source: MessageSource): seq[UiEvent] =
  for message in source.messages:
    result.add agentEvent(AgentUiEvent(kind: ueTextDelta, text: message))
  source.messages.setLen(0)

let source = MessageSource(id: "messages", messages: @["one", "two"])
app.addSource(source)
```

`poll` can return zero or more events. `needsPolling` defaults to `true`, which
makes an idle app poll at `pollIntervalMs`, defaulting to 16 milliseconds. A
source can override it to return `false` while idle. If `poll` raises a
`CatchableError`, the app posts a `uiError`, closes the source, and removes it.

## Limits an embedder must design around

`App` is deliberately small: one thread, one dispatch path, and no promises
about anything else. These are the behaviours an embedder meets first, each one
read off the source rather than inferred.

**A nested `step` is not guarded.** `App` carries no in-step flag
(`src/nimterm/app.nim:25-41`) and `dispatch` calls your callback directly
(`src/nimterm/app.nim:163-168`), so a `step` called from inside a handler
recursively dispatches another event while the outer one is still running.
Nothing in the library documents or tests that as safe. If you have to keep the
interface alive during a long call, make it one non-reentrant pump with a guard
of your own.

**One event per `step`.** `step` pops the queue, polls the sources, blocks in
`backend.readEvent` for the timeout it was given, polls the sources again,
dispatches, and flushes (`src/nimterm/app.nim:213-237`). `run` passes
`idleTimeout`: `pollIntervalMs` (16 ms by default, `src/nimterm/app.nim:50`)
when some source returns `needsPolling = true`, and otherwise `-1`, an
indefinite block until input, a `post`, or the earliest due timer
(`src/nimterm/app.nim:86-105,239-252`).

**`EventSource.poll` runs synchronously.** `collectEvents` calls it on the same
thread that is about to dispatch and render
(`src/nimterm/app.nim:63-75`), so a `poll` that blocks on a pipe freezes the
interface exactly as long as it blocks — and a `poll` that raises
`CatchableError` costs you the source: the app posts `uiError`, closes the
source, and removes it. Spawn the producer asynchronously and keep `poll` to
non-blocking reads.

**The POSIX backend watches two descriptors.** The `select` in `inputReady`
sets `STDIN_FILENO` and `backend.wakeRead`, and nothing else
(`src/nimterm/platform_posix.nim:128-140`). To bring a child process's output
into the loop, read it from your own `EventSource`; the backend will not poll
its descriptor for you.

**A repaint request is not thread-safe.** The event queue is the only
synchronized piece of the library (`src/nimterm/queue.nim:1-22`); `invalidate`,
`flush`, and `render` are not. `post` enqueues under the queue's lock and wakes
a blocked `readEvent`, and that is the whole cross-thread story: keep another
thread away from `App` unless you bring your own synchronization.

**A copied `App` shares more than it owns.** Assignment copies the value fields
— `running`, `dirty`, `frame`, `timers`, `sources`, `lastPresent` — while
`backend`, `queue`, the widget tree, and the source objects stay shared
(`src/nimterm/app.nim:25-41`). The copy dispatches through the same queue and
draws on the same canvas, but a source or timer added to the original after the
copy never reaches the copy you pump, and `running` belongs to whichever copy
you set it on. Keep one canonical `App` and drive that one.

### What a change in the library could add

These limits are all workable from the embedding side, which is why they are
documented rather than enforced. A library-side fix would pick them off in this
order:

- a reentrancy guard on `step`, so pumping from a handler is either safe or
  refused loudly instead of silently nesting;
- a thread-safe repaint request, so a producer on its own thread needs no
  hand-rolled synchronization;
- a backend or source that can wait on arbitrary descriptors, so a child's pipe
  is a first-class event source;
- an `EventSource` for a spawned child out of the box, the way agent frontends
  always need one.

## Handle failures

An exception from `onEvent` or a widget handler becomes a `uiError` event on a
later step. Handle it in `onEvent` if you want to show a message or stop the
application:

```nim
app.onEvent = proc (app: var App, event: UiEvent): EventResponse =
  if event.kind == uiError:
    stderr.writeLine event.sourceId & ": " & event.error
    app.running = false
    return eventHandled
  eventIgnored
```

## Next steps

- [Input and events](/guides/input-and-events/) for dispatch and focus rules.
- [Terminal backends](/guides/terminal-backends/) for capabilities and screen modes.
- [Agent frontends](/guides/agent-frontends/) for feeding streamed events into a widget.
