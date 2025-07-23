
/*
[load].
[load_tests].
[utils(logger)].
set_log_level(debug).
run_tests(actors).
*/

:- begin_tests(actors).

:- use_module(utils(logger)).
:- use_module(actors(worker)).
:- use_module(actors(supervisor)).
:- use_module(actors(pubsub)).
:- use_module(actors(actor_utils)).

:- use_module(bob).
:- use_module(alice).

test(supervisor) :-
	supervisor : started(top), 
	assertion(
		is_thread(top)), 
	supervisor : stopped(top), 
	assertion(
		 \+ is_thread(top)).

test(supervised_static_pubsub) :-
	Children = [pubsub], 
	supervisor : started(top, 
		[children(Children)]), 
	assertion(
		is_thread(top)), 
	assertion(
		is_thread(pubsub)), 
	supervisor : stopped(top), 
	assertion(
		 \+ is_thread(top)), 
	assertion(
		 \+ is_thread(pubsub)).

test(supervised_dynamic_pubsub) :-
	supervisor : started(top), 
	assertion(
		is_thread(top)), 
	supervisor : pubsub_started(top), 
	assertion(
		is_thread(pubsub)), 
	supervisor : stopped(top), 
	assertion(
		 \+ is_thread(top)), 
	assertion(
		 \+ is_thread(pubsub)).

test(stop_supervisor_with_static_children) :-
	Children = [worker(bob, 
		[topics([party])]), pubsub], 
	supervisor : started(top, 
		[children(Children)]), 
	assertion(
		is_thread(top)), 
	assertion(
		is_thread(pubsub)), 
	assertion(
		is_thread(bob)), 
	assertion(
		is_thread(bob_clock)), 
	supervisor : children(top, Answer), 
	assertion(
		member(
			child(worker, bob), Answer)), 
	assertion(
		member(
			child(worker, pubsub), Answer)), 
	supervisor : stopped(top), % No need to wait since it mas signalled
	
	assertion(
		 \+ is_thread(bob)), 
	assertion(
		 \+ is_thread(bob_clock)), 
	assertion(
		 \+ is_thread(pubsub)), 
	assertion(
		 \+ is_thread(top)).

test(exit_supervisor_with_static_children) :-
	Children = [worker(bob, 
		[topics([party])]), pubsub], 
	supervisor : started(top, 
		[children(Children)]), 
	assertion(
		is_thread(top)), 
	assertion(
		is_thread(pubsub)), 
	assertion(
		is_thread(bob)), 
	assertion(
		is_thread(bob_clock)), 
	supervisor : children(top, Answer), 
	assertion(
		member(
			child(worker, bob), Answer)), 
	assertion(
		member(
			child(worker, pubsub), Answer)), 
	supervisor : exit(top), % Must wait since this is messaged
	
	sleep(2), 
	assertion(
		 \+ is_thread(bob)), 
	assertion(
		 \+ is_thread(bob_clock)), 
	assertion(
		 \+ is_thread(pubsub)), 
	assertion(
		 \+ is_thread(top)).

test(supervised_dynamic_worker) :-
	supervisor : started(top), 
	assertion(
		is_thread(top)), 
	supervisor : worker_child_started(top, alice, alice, []), 
	assertion(
		is_thread(alice)), 
	supervisor : stopped(top), 
	assertion(
		 \+ is_thread(top)), 
	assertion(
		 \+ is_thread(alice)).

test(supervised_static_supervisor) :-
	Children = [supervisor(bottom, [])], 
	supervisor : started(top, 
		[children(Children)]), 
	assertion(
		is_thread(top)), 
	assertion(
		is_thread(bottom)), 
	supervisor : stopped(top), 
	assertion(
		 \+ is_thread(top)), 
	assertion(
		 \+ is_thread(bottom)).

test(supervised_dynamic_supervisor) :-
	supervisor : started(top), 
	assertion(
		is_thread(top)), 
	supervisor : supervisor_child_started(top, bottom, []), 
	assertion(
		is_thread(bottom)), 
	supervisor : stopped(top), 
	assertion(
		 \+ is_thread(top)), 
	assertion(
		 \+ is_thread(bottom)).

test(supervised_actor_restart) :-
	Children = [pubsub, 
	worker(bob, 
		[topics([]), 
		init(
			[mood(bored)]), 
		restarted(permanent)]), 
	worker(alice, 
		[topics([]), 
		init(
			[mood(peaceful)]), 
		restarted(transient)])], 
	supervisor : started(top, 
		[children(Children)]), 
	assertion(
		is_thread(top)), 
	assertion(
		is_thread(pubsub)), 
	assertion(
		is_thread(bob)), 
	assertion(
		is_thread(alice)), % Checking restart
		
	actor_exited(bob), % Wait for restart of permanent bob
	
	actor_ready(bob), 
	assertion(
		is_thread(bob)), % Stopping
		
	actor_exited(alice), % alice is transient
	
	actor_stopped(alice), 
	assertion(
		 \+ is_thread(alice)), 
	supervisor : child_stopped(bottom, worker, bob), 
	assertion(
		 \+ is_thread(bob)), 
	supervisor : stopped(top), 
	sleep(1), 
	assertion(
		 \+ is_thread(alice)), 
	assertion(
		 \+ is_thread(bob)), 
	assertion(
		 \+ is_thread(pubsub)), 
	assertion(
		 \+ is_thread(top)).

test(restarting_supervised_supervisors) :-
	% Starting supervisor (top) with a static child supervisor (middle)

	Children = [supervisor(middle, 
		[restarted(permanent)])], 
	supervisor : started(top, 
		[children(Children)]), 
	assertion(
		is_thread(top)), 
	assertion(
		is_thread(middle)), % Start dynamic supervisor (bottom) as child of supervisor middle
		
	supervisor : supervisor_child_started(middle, bottom, 
		[restarted(permanent)]), 
	assertion(
		is_thread(bottom)), % Exiting permanent supervisor bottom -a dynamic child of middle- restarts bottom
		
	supervisor : exit(bottom), 
	sleep(1), 
	assertion(
		is_thread(bottom)), % Stop the middle supervisor does not restart its dynamic children: bottom are not restarted (even though it is permanent)
		
	supervisor : stopped(middle), 
	sleep(1), 
	assertion(
		 \+ is_thread(middle)), 
	assertion(
		 \+ is_thread(bottom)), % Stop the top supervisor and thus every descendant.
			
	supervisor : stopped(top), 
	sleep(1), 
	assertion(
		 \+ is_thread(top)), 
	assertion(
		 \+ is_thread(middle)).

test(subscribing_unsubscribing) :-
	supervisor : started(top, 
		[children([pubsub, 
			worker(bob, 
				[topics([party, police]), 
				init(
					[mood(bored)]), 
				restarted(transient)]), 
			worker(alice, alice, 
				[topics([]), 
				init(
					[mood(peaceful)]), 
				restarted(transient)])])]), 
	assertion(
		is_thread(top)), 
	assertion(
		is_thread(pubsub)), 
	assertion(
		is_thread(bob)), 
	assertion(
		is_thread(alice)), 
    assertion(subscription(bob, party-any)),
	assertion(subscription(bob, party-alice)),
	assertion(subscription(bob, police-any)),
	assertion(subscription(bob, police-alice)),
	unsubscribed(bob, party),
	assertion(\+ subscription(bob, party-any)),
	assertion(\+ subscription(bob, party-alice)),
	all_subscribed(alice, [party, police]), 
	assertion(subscription(alice, party-any)),
	assertion(subscription(alice, party-bob)),
	assertion(subscription(alice, police-any)),
	assertion(subscription(alice, police-bob)),
	all_unsubscribed(alice),
	assertion(\+ subscription(alice, party-any)),
	assertion(\+ subscription(alice, police-any)),
	sleep(1), 
	supervisor : stopped(top), 
	assertion(
		 \+ is_thread(pubsub)), 
	assertion(
		 \+ is_thread(alice)), 
	assertion(
		 \+ is_thread(bob)), 
	assertion(
		 \+ is_thread(top)).

test(subscribing_unsubscribing_any_from) :-
	supervisor : started(top, 
		[children([pubsub, 
			worker(bob, 
				[topics([party, police]), 
				init([]),
				restarted(transient)]), 
			worker(alice, alice, 
				[topics([]), 
				init([]),
				restarted(transient)])])]), 
	assertion(
		is_thread(top)), 
	assertion(
		is_thread(pubsub)), 
	assertion(
		is_thread(bob)), 
	assertion(
		is_thread(alice)), 
	subscribed(bob, party-alice), 
	subscribed(bob, police-alice),
	assertion(subscription(bob, party-any)),
	assertion(subscription(bob, police-any)),
	unsubscribed_from(bob, alice),
	assertion(subscription(bob, party-any)),
	assertion(subscription(bob, party-alice)), 	% implicitly
	assertion(subscription(bob, police-any)),
	assertion(subscription(bob, police-alice)), % implicitly
	sleep(1), 
	supervisor : stopped(top), 
	assertion(
		 \+ is_thread(pubsub)), 
	assertion(
		 \+ is_thread(alice)), 
	assertion(
		 \+ is_thread(bob)), 
	assertion(
		 \+ is_thread(top)).

test(communicating_with_supervised_static_children) :-
	supervisor : started(top, 
		[children([pubsub])]), 
	assertion(
		is_thread(top)), 
	assertion(
		is_thread(pubsub)), 
	Children = [worker(bob, 
		[topics([party, police]), 
		init(
			[mood(bored)]), 
		restarted(permanent)]), 
	worker(alice, alice, 
		[topics([party, police]), 
		init(
			[mood(peaceful)]), 
		restarted(transient)])], 
	supervisor : supervisor_child_started(top, bottom, 
		[children(Children)]), 
	assertion(
		is_thread(bob)), 
	assertion(
		is_thread(alice)), % Querying
		
	assertion(
		query_answered(bob, mood, bored)), 
	assertion(
		query_answered(alice, mood, peaceful)), % Eventing
		
	published(party, [alice, bob]), % Give time for workers to respond to published messages
	
	sleep(1), % Checking state changes from event
	
	assertion(
		 \+ query_answered(bob, mood, bored)), 
	assertion(
		 \+ query_answered(peter, mood, bored)), 
	assertion(
		query_answered(bob, mood, panicking)), % Unsubscribing
		
	unsubscribed(bob, party), 
	supervisor : stopped(top), 
	sleep(1), 
	assertion(
		 \+ is_thread(pubsub)), 
	assertion(
		 \+ is_thread(alice)), 
	assertion(
		 \+ is_thread(bob)), 
	assertion(
		 \+ is_thread(bottom)), 
	assertion(
		 \+ is_thread(top)).

%%% TODO - add test for duplicate and subsumed subscriptions, then broadcasts

:- end_tests(actors).