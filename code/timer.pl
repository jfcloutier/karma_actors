/*
Timer creates threads to periodically call goals until stopped.
*/

:- module(timer, []).



:- use_module(utils(logger)).

repeated(Timer, Goal, Delay) :-
	log(debug, timer, "Timer ~w will be executing ~p every ~w seconds", [Timer, Goal, Delay]), 
	thread_create(
		run(Goal, Delay, repeat), _, 
		[alias(Timer), 
		detached(true)]).

once(Timer, Goal, Delay) :-
	log(debug, timer, "Timer ~w will be executing ~p in ~w seconds", [Timer, Goal, Delay]), 
	thread_create(
		run(Goal, Delay, once), _, 
		[alias(Timer), 
		detached(true)]).

stopped(Timer) :-
	log(info, timer, "Stopping timer ~w", [Timer]), 
	is_thread(Timer)
	 ->
			thread_signal(Timer, exit_timer);
			true.

% Run in thread

run(Goal, Delay, Mode) :-
	sleep(Delay), 
	catch(
		(
			log(debug, timer, "Timer ~@ is executing ~p after waiting ~w seconds", [self, Goal, Delay]), 
			call(Goal)), 
			Exception, 
		(
			log(warn, timer, "Failed to execute ~p: ~p", [Goal, Exception]), true)), 
	(Mode == repeat -> run(Goal, Delay, Mode) ; true).

exit_timer :-
	thread_self(Timer), 
	log(debug, timer, "Exiting timer ~w", [Timer]), 
	thread_exit(true).
    