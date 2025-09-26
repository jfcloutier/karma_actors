:- module(actor_utils, [
    self/1, 
    actor_started/2, actor_started/3, actor_exited/1,
    actor_ready/1, actor_stopped/1, actor_stopped/2, 
    sent/2, call_at_interval/5, call_later/5, control_sent/2, control_sent/3, message_sent/1, message_sent/2, query_answered/2, query_answered/3, query_answered/4,
    empty_state/1, get_state/3, put_state/3, put_state/4, acc_state/4, dec_state/4,
    count_in/3, pick_some/2, remember_one/1]).

:- use_module(utils(logger)).
:- use_module(actors(timer)).

self(Name) :-
	thread_self(Name).

actor_started(Name, Goal) :-
	actor_started(Name, Goal, []).

actor_started(Name, Goal, Options) :-
	FullOptions = [alias(Name)|Options], 
	thread_create(Goal, _, FullOptions).

actor_exited(Name) :-
	log(debug, actors, "About to exit actor ~w", [Name]), 
	sent(Name, 
		control(exit)).

empty_state(state{}).

get_state(State, Key, Value) :-
	is_dict(State, state), 
	get_dict(Key, State, Value).

% Adding/overwriting pairs to a dictionary.

put_state(State, Pairs, NewState) :-
	dict_pairs(State, Tag, StatePairs), 
	merge_pairs(StatePairs, Pairs, MergedPairs), 
	dict_pairs(NewState, Tag, MergedPairs).

put_state(State, Key, Value, NewState) :-
	is_dict(State, state), 
	put_dict(Key, State, Value, NewState).

acc_state(State, Key, Value, NewState) :-
	get_state(State, Key, Acc),
	% Value could be a list of values
    flatten([Value | Acc], Acc1),
	put_state(State, Key, Acc1, NewState).

dec_state(State, Key, Value, NewState) :-
	get_state(State, Key, Acc),
	select(Value, Acc, Acc1),
	put_state(State, Key, Acc1, NewState).

%! count_in(List+, +Item, -Count)
% the number of times an item is in a list
count_in([], _, 0).
count_in([Item | Rest], Item, Count) :-
	count_in(Rest, Item, C),
	Count is C + 1.
count_in([E | Rest], Item, Count) :-
	E \= Item,
	count_in(Rest, Item, Count).

% Pick a random subset of a list, at least one but no more than half. Deterministic.
pick_some([], []).
pick_some([E], [E]).

pick_some(List, SubList) :-
	sort(List, Set),
	random_permutation(Set, PermutedList), 
	length(Set, L), 
	Max is max(1, round(L / 2)),
	random_between(1, Max, N), 
	take(N, PermutedList, SubList).

take(_, [], []).
take(0, _, []).

take(N, _, []) :-
	N < 0.

take(N, [El|Rest], [El|Others]) :-
	N > 0, N1 is N - 1, 
	take(N1, Rest, Others).

merge_pairs(Pairs, InPairs, MergedPairs) :-
	append(InPairs, Pairs, AllPairs), 
	sort(1,  @>= , AllPairs, SortedAllPairs), 
	group_pairs_by_key(SortedAllPairs, Grouped), 
	pairs_from_groups(Grouped, MergedPairs).

pairs_from_groups([], []).

pairs_from_groups([Key-[Value|_]|Rest], [Key-Value|OtherPairs]) :-
	pairs_from_groups(Rest, OtherPairs).

% Tell a thread to process a message in priority by signalling it

signal(Name, Module, Signal) :-
	log(debug, actors, "Signaling ~w ~w with ~p", [Module, Name, Signal]), 
	is_thread(Name)
	 ->
			(Goal =.. [ : , Module, 
		signal_processed(Signal)], 
		thread_signal(Name, Goal));
	log(debug, actors, "Can not signal non-existent thread ~w", [Name]).

% Signal a control message

control_sent(Module, Control) :-
	Module : name(Name), 
	control_sent(Name, Module, Control).

control_sent(Name, Module, Control) :-
	catch(
		signal(Name, Module, 
			control(Control)), Exception, 
		(
			log(warn, actors, "Failed to send signal ~p to ~w (~w): ~p", [Control, Name, Module, Exception]), true)).

% Undecorated message sent with best effort.

sent(Name, Message) :-
	catch(
		(
			log(debug, actors, "~@ is sending ~p to ~w", [self, Message, Name]), 
			thread_send_message(Name, Message)), Exception, 
		(
			log(warn, actors, "Failed to send message ~p to ~w: ~p", [Message, Name, Exception]), true)).

% Send undecorated message periodically

call_at_interval(Target, Tag, Message, Delay, Timer) :-
	self(Name), 
	atomic_list_concat([Name, Tag], "_", Timer), 
	timer : repeated(Timer, 
		thread_send_message(Target, Message), Delay).

call_later(Target, Tag, Message, Delay, Timer) :-
	self(Name), 
	atomic_list_concat([Name, Tag], "_", Timer), 
	timer : once(Timer, 
		thread_send_message(Target, Message), Delay).

% Send self a message

message_sent(Message) :-
	thread_self(Name), 
	message_sent(Name, Message).

% Send a semantic message

message_sent(Name, Message) :-
	thread_self(From), 
	sent(Name, 
		message(Message, From)).

% Send self a query

query_answered(Question, Answer) :-
	thread_self(Name), 
	query_answered(Name, Question, Answer).

% Send a semantic query and wait for *the* answer

query_answered(Name, Question, Answer) :-
	query_answered(Name, Question, 5, Answer).

query_answered(Name, Question, Timeout, Answer) :-
	log(info, actors, "~@ is sending query ~p to ~w", [self, Question, Name]), 
	catch(
		(
			thread_self(From), 
			thread_send_message(Name, 
				query(Question, From)), % Fails (quietly) is a matching message is not received in time
				
			log(debug, actors, "~w is waiting for response(Answer, ~p, ~w), timeout is ~w", [From, Question, Name, Timeout]), 
			thread_get_message(From, 
				response(Response, Question, Name), 
				[timeout(Timeout)]), 
				!,
				Answer = Response,
			log(info, actors, "Got answer ~p from ~w to query ~p", [Answer, Name, Question])), Exception, 
		(
			log(warn, actors, "Failed to query ~w about ~p: ~p~n", [Name, Question, Exception]), fail)).

% Wait 20s for a actor thread to be alive

actor_ready(Name) :-
	actor_ready(Name, 20).

actor_ready(Name, 0) :-
	log(warn, actors, "Failed waiting for actor thread ~w~n", [Name]), !, fail.

actor_ready(Name, CountDown) :-
	is_thread(Name)
	 ->
			log(debug, actors, "Actor ~w is running", [Name]), true;
	(
		log(debug, actors, "Waiting for actor thread ~w (~w)", [Name, CountDown]), 
		sleep(0.25), AttemptsLeft is CountDown - 1, 
		actor_ready(Name, AttemptsLeft)).

% Wait 15s (60 * 0.25s) for an actor thread to be stopped

actor_stopped(Name) :-
	actor_stopped(Name, 60).

actor_stopped(Name, 0) :-
	log(warn, actors, "Failed waiting for actor thread ~w to be stopped", [Name]), !, fail.

actor_stopped(Name, CountDown) :-
	 \+ is_thread(Name) ->
		true;
	(
		log(debug, actors, "Waiting for actor thread stopped ~w (~w)~n", [Name, CountDown]), 
		sleep(0.25), AttemptsLeft is CountDown - 1, 
		actor_stopped(Name, AttemptsLeft)).

remember_one(Term) :-
    Term =.. [Head | Args],
    length(Args, Arity),
    abolish(Head, Arity),
    assert(Term).
