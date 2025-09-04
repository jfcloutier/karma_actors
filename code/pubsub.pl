/*
The PubSub singleton worker actor. 

It receives subscriptions from actors to listen to Subs from sources, and dispatches events received
to topic listeners.

A subscription is a topic - source  pair. The topic is an atom and Source is the name of a matching source (`any`, the default, for all sources to match)

Actors publish an atom (the topic), a payload and the source (an actor's nanme)
Actors receive events `event(Topic, Payload, Source).

TODO: Set an exclusive affinity to the PubSub thread to maxinimize its time being scheduled to a core
*/

:- module(pubsub, [subscribed/1, subscribed/2, all_subscribed/1, all_subscribed/2, all_unsubscribed/0, all_unsubscribed/1, unsubscribed/1, unsubscribed/2, unsubscribed_from/1, unsubscribed_from/2, subscription/1, subscription/2, published/1, published/2]).

:- use_module(library(aggregate)).
:- use_module(utils(logger)).
:- use_module(actors(actor_utils)).
:- use_module(actors(worker)).

% Singleton thread's name
name(pubsub).

%% Public

all_subscribed(Subs) :-
	self(Subscriber),
	all_subscribed(Subscriber, Subs).

all_subscribed(_, []).
all_subscribed(Subscriber, [Sub|Others]) :-
	subscribed(Subscriber, Sub),
	all_subscribed(Subscriber, Others).

subscribed(Sub) :-
	self(Subscriber),
	subscribed(Subscriber, Sub).

subscribed(Subscriber, Sub) :-
	name(Pubsub),
	message_sent(Pubsub,
		subscribed(Subscriber, Sub)).

unsubscribed(Sub) :-
	self(Subscriber),
	unsubscribed(Subscriber, Sub).

unsubscribed(Subscriber, Sub) :-
	name(Pubsub),
	message_sent(Pubsub,
		unsubscribed(Subscriber, Sub)).

unsubscribed_from(Source) :-
	self(Subscriber),
	unsubscribed_from(Subscriber, Source).

unsubscribed_from(Subscriber, Source) :-
	name(Pubsub),
	message_sent(Pubsub,
		unsubscribed_from(Subscriber, Source)).

all_unsubscribed :-
	self(Subscriber),
	all_unsubscribed(Subscriber).

all_unsubscribed(Subscriber) :-
	name(Pubsub),
	message_sent(Pubsub,
		all_unsubscribed(Subscriber)).

published(Topic) :-
	published(Topic, []).

published(Topic, Payload) :-
	self(Source),
	name(Pubsub),
	message_sent(Pubsub,
		pub(Topic, Payload, Source)).

subscription(Topic) :-
	self(Subscriber),
	subscription(Subscriber, Topic).

subscription(Subscriber, Topic) :-
	name(PubSub),
	query_answered(PubSub,
		subscription(Subscriber, Topic),
		true).

%% Private

init(_, State) :-
	log(info, pubsub, "Initializing pubsub"),
	empty_state(EmptyState),
	put_state(EmptyState, [subscriptions - []], State).

% Called when worker exits
terminated :-
	log(info, pubsub, "Pubsub ~@ terminated", [self]).

signal_processed(control(stopped)) :-
	log(debug, pubsub, "Stopping pubsub"),
	worker : stopped.

handled(message(subscribed(Subscriber, Sub), _), State, NewState) :-
	log(debug, pubsub, "Subscribing ~w to ~p", [Subscriber, Sub]),
	add_subscription(Subscriber, Sub, State, NewState).

handled(message(unsubscribed(Subscriber, Sub), _), State, NewState) :-
	log(debug, pubsub, "Unsubscribing ~w from ~p", [Subscriber, Sub]),
		remove_subscription(Subscriber, Sub, State, NewState).

handled(message(unsubscribed_from(Subscriber, Source), _), State, NewState) :-
	log(debug, pubsub, "Unsubscribing ~w from source ~p", [Subscriber, Source]),
	 remove_subscriptions_from(Subscriber, Source, State, NewState).

handled(message(all_unsubscribed(Subscriber), _), State, NewState) :-
	 remove_all_subscriptions(Subscriber, State, NewState).

handled(message(pub(Topic, Payload, Source), _), State, State) :-
	broadcast(event(Topic, Payload, Source),
		State).

handled(query(subscription(Subscriber, Topic)), State, true) :-
	get_state(State, subscriptions, Subscriptions),
	member(subscription(Subscriber, T),
		Subscriptions),
	sub_match(Topic, T),
	!.
handled(query(subscription(_, _)), _, false).

broadcast(event(Topic, Payload, Source), State) :-
	Sub = Topic - Source,
	get_state(State, subscriptions, Subscriptions),
	log(debug, pubsub, "Broadcasting ~p to subscriptions ~p", [event(Topic, Payload, Source), Subscriptions]),
	concurrent_forall(
		   (member(subscription(Name, Subscription), Subscriptions),
			sub_match(Sub, Subscription)),
		   event_sent_to(event(Topic, Payload, Source), Name),
		   [threads(10)]).

sub_match(Topic-_, Topic-any).
sub_match(Topic-any, Topic-_).
sub_match(Topic-Source, Topic-Source).

event_sent_to(Event, Name) :-
	log(debug, pubsub, "Sending event ~p to ~w", [Event, Name]),
	sent(Name, Event).

% Adding a subscription removes a subscription subsumed by it, if any,
% or it is a noop if it is subsumed by an existing subscription.
add_subscription(Subscriber, Topic-any, State, NewState) :-
	get_state(State, subscriptions, Subscriptions),
	((member(subscription(Subscriber, Sub),
				Subscriptions),
			sub_match(Sub, Topic - any)) ->
	(delete(Subscriptions, Sub, Subscriptions1),
			put_state(State,
				subscriptions,
				[subscription(Subscriber, Topic - any)|Subscriptions1],
				NewState));
	put_state(State,
			subscriptions,
			[subscription(Subscriber, Topic - any)|Subscriptions],
			NewState)).

add_subscription(Subscriber, Topic-Source, State, NewState) :-
	Source \== any,
	get_state(State, subscriptions, Subscriptions),
	((member(subscription(Subscriber, Sub),
				Subscriptions),
			sub_match(Sub, Topic - Source)) ->
	NewState = State;
	put_state(State,
			subscriptions,
			[subscription(Subscriber, Topic - Source)|Subscriptions],
			NewState)).
		
add_subscription(Subscriber, Topic, State, NewState) :-
	 \+ unifiable(_ - _, Topic, _),
	add_subscription(Subscriber, Topic - any, State, NewState).

remove_subscription(Subscriber, Topic-Source, State, NewState) :-
	Sub = Topic - Source,
	!,
	get_state(State, subscriptions, Subscriptions),
	delete_matching_subs(Subscriptions,
		subscription(Subscriber, Sub),
		Subscriptions1),
	put_state(State, subscriptions, Subscriptions1, NewState).

remove_subscription(Subscriber, Topic, State, NewState) :-
		remove_subscription(Subscriber, Topic - any, State, NewState).

remove_subscriptions_from(Subscriber, Source, State, NewState) :-
	get_state(State, subscriptions, Subscriptions),
	delete_subs_from(Subscriptions, Subscriber, Source, Subscriptions1),
	put_state(State, subscriptions, Subscriptions1, NewState).

delete_matching_subs([], _, []).

delete_matching_subs([subscription(Subscriber, Sub)|Rest], subscription(Subscriber, DeleteSub), RemainingSubscriptions) :-
	sub_match(Sub, DeleteSub),
	!,
	delete_matching_subs(Rest,
		subscription(Subscriber, DeleteSub),
		RemainingSubscriptions).
	
delete_matching_subs([Subscription|Rest], subscription(Subscriber, DeleteSub), [Subscription|RemainingSubscriptions]) :-
	delete_matching_subs(Rest,
		subscription(Subscriber, DeleteSub),
		RemainingSubscriptions).

delete_subs_from([], _, _, []).
delete_subs_from([subscription(Subscriber, _-Source)|Rest], Subscriber, Source, RemainingSubscriptions) :-
	!,
	delete_subs_from(Rest, Subscriber, Source, RemainingSubscriptions).
delete_subs_from([Subscription|Rest], Subscriber, Source, [Subscription|RemainingSubscriptions]) :-
	delete_subs_from(Rest, Subscriber, Source, RemainingSubscriptions).

remove_all_subscriptions(Subscriber, State, NewState) :-
	get_state(State, subscriptions, Subscriptions),
	delete(Subscriptions,
		subscription(Subscriber, _),
		Subscriptions1),
	put_state(State, subscriptions, Subscriptions1, NewState).    
