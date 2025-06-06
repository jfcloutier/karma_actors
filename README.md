# The Karma actor framework

A Prolog Actor Model library for SWI-Prolog

## About

An actor module starts and runs named, supervised threads (a.k.a actors).

An actor module must implement `started(Name, Options, Supervisor)` and `signal_processed(Signal)`.

Start options:

* topics(Topics) - Topics is the list of topics for the events the worker wants to receive (defaults to [])
* handler(Handler) - Handler is the fully qualified name of the clause header handling events (required)
* init(Init) - Init is the fully qualified name of the clause called when initiating the agent (defaults to worker:noop/0)

If the module runs a singleton actor, it must also implement `name(Name)`.

An actor is started via `supervisor:child_started(Supervisor, Module, Options)` (for a singleton actor) or `child_started(Supervisor, Module, Name, Options)` (for a named actor).

A supervisor actor restarts its terminated, supervised actors according to the option `restarted(Restart)` with which they were started, where Restart is one of:

* permanent (always restart),
* temporary (never restart)
* transient (restart on abnormal exit - the default).

A supervisor can supervise another supervisor. If a supervised supervisor is restarted, only its `permanent` children are restarted.

Actors interact by sending messages to each other:

* directly via `sent(Name, Message)` (Name is the name of the target actor)
* indirectly via pubsub `published(Topic, Payload)` where the Message sent is `event(Topic, Payload, SenderName)`

Message sent by an actor via pubsub is received by all actors that have subscribed to the message topic.

An actor can subscribe to a list of topics or to an individual topic via

* `all_subscribed(Topics)` where topics is a list of topics
* `subscribed(Topic)`

An actor unsubscribes from all topics with `all_unsubscribed`.

On termination, an actor must send an `exited(Kind, Module, Name, Exit)` message to its supervisor where Exit = `exit(normal)` means normal exit.

See `./tests/actors` for simple examples of using the Karma actor model.
