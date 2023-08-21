#import "Basic";
#import "Random";
#import "Math";
#import "Atomics";
#import "Hash";
#import,dir "../osor_cpu_dispatch";



main :: ()
{
	cpu_dispatch_init();
	defer cpu_dispatch_deinit();

	simple_dispatch();
	dispatch_once_per_thread();
	continuous_items_mode();
	load_balancing_mode();
}



simple_dispatch :: ()
{
	print_example_name("Simple Dispatch");

	//
	// This will execute this piece of code 20 times distributed amongs the
	// threads available. Note how you can refer to the specific item index
	// to process via context.dispatch_index.
	//
	work :: ()
	{
		print("Processing work item number % from thread %\n", context.dispatch_index, context.thread_index);
	}
	cpu_dispatch(20, work);
}



dispatch_once_per_thread :: ()
{
	print_example_name("Executing once per-thread");

	//
	// Sometimes you want all the threads to execute your procedure
	// just once (or all N times). This comes in handy when you need to
	// check the work that all threads have done, or when you want to
	// do some per-thread cleanup.
	//
	// In this file we actually use it in print_durations_per_thread()
	//
	// You can see more info about the dispatch modes in their description
	// on the main module file, in the CPU_Dispatch_Mode enum 
	//
	work :: ()
	{
		print("Hello from thread %\n", context.thread_index);
	}
	cpu_dispatch(1, work, mode = .PER_THREAD);
}



continuous_items_mode :: ()
{
	print_example_name("Continuous Items Mode");

	data : [200]u64; 
	for * data it.* = random_get();

	//
	// Here we have a procedure that's going to be reading and writing an element
	// in an array. If we process items that are close together it's likely that we
	// keep hitting the fastest caches of our CPU both when reading and writing.
	//
	// Alternatively, if we process items far away from each other on the same thread
	// it's likely that we're going to end up touching memory that's been also touched
	// by other threads. Which in this cause would create a phenomenon called
	// false sharing.
	//
	cache_friendly_load :: (data : []u64)
	{
		store_work_item_duration();
		for 0..100 data[context.dispatch_index] = fnv1a_hash(xx data[context.dispatch_index]);
	}

	//
	// You'll see how in this case, when we process contiguous items we're going to finish
	// up the dispatch faster, because we're much more cache-access friendly
	// 
    before := current_time_monotonic();
	cpu_dispatch(200, cache_friendly_load, cast([]u64)data, mode = .CONTIGUOUS_ITEMS);
	contiguous_items_time := to_float64_seconds(current_time_monotonic() - before) * 1000.0;
    print("With CONTIGUOUS_ITEMS it took %ms\n", contiguous_items_time);
	print_durations_per_thread();

	//
	// The load balancing mode in this case doesn't really benefit us, because the work
	// done in each work item is expected to be essentially the same. And we end up being
	// slower due to all the random cache access and false sharing issues we hit.
	//
    before = current_time_monotonic();
	cpu_dispatch(200, cache_friendly_load, cast([]u64)data, mode = .LOAD_BALANCING);
	load_balancing_time := to_float64_seconds(current_time_monotonic() - before) * 1000.0;
    print("With LOAD_BALANCING it took %ms\n", to_float64_seconds(current_time_monotonic() - before) * 1000.0);
	print_durations_per_thread();

	print("The contiguous items mode was % times faster\n", load_balancing_time / contiguous_items_time);
}



load_balancing_mode :: ()
{
	print_example_name("Load Balancing Mode");

	//
	// Here we're going to dispatch 100 items of work, and
	// we're going to make some of them take a long time.
	//
	// This can mimic tasks that are not expected to have a uniform
	// duration. For example, if you're going to parse 100 files, the time
	// the parse takes might depend on how big the file is.
	//
	// If we dispatched with the CONTIGUOUS_ITEMS mode, then each thread
	// is assigned the same number of elements. But if some of those are
	// really long and some other really short, what might happen is that
	// some of the threads that get a series of quick items are done fast,
	// while the threads that got multiple slow items are stuck working in
	// all of those.
	//
	// This defeats the purpose of multithreading them in the first place,
	// because most of the work will end up being done in a couple of threads.
	//
	// What we can do here is to select the LOAD_BALANCING mode. In this mode
	// the threads don't each get a group of items. What they do instead is to
	// grab an item to process, and when they are done, they just grab another one.
	// This makes them go possibly out of order, since the first item ready for one
	// thread might be index 3, and by the time they are done, the next item to process
	// might be index 7. The advantage is that since the threads always do work if
	// there's some left, they balance the load, smoothing out the cost of large items. 
	//
	// It can often be the case that one thread does one or two really long elements while
	// another one does 30 really fast ones. Effectively reducing the total processing time.
	//
	unbalanced_load :: ()
	{
		store_work_item_duration();
		if context.dispatch_index < 10 
		{
			iterations := 10000;
			result : u64 = 0x1234;
			random_state := Random_State.{context.thread_index, 0};
	        for 0..iterations-1
	        {
	        	result = result ^ random_get(*random_state);
		    }
		}
	}

	//
	// With continuous items, every thread picks up the same number of work items
	//
	// In the output you'll be able to see how some threads get allocated a lot of the
	// really slow threads, essentially becoming the bottleneck. While other threads just
	// get a batch of really quick items and are done immediately. This leads to poor 
	// utilization of our threads when the items have very different processing times each.
	//
	before := current_time_monotonic();
	cpu_dispatch(100, unbalanced_load, mode = .CONTIGUOUS_ITEMS);
	contiguous_items_time := to_float64_seconds(current_time_monotonic() - before) * 1000.0;
    print("With CONTIGUOUS_ITEMS it took %ms\n", contiguous_items_time);
	print_durations_per_thread();

	//
	// With load balancing threads pick up a new item when they've finished their current one (but out of order)
	//
	// You'll be able to see on the output how some threads only do one or two really expensive items, while
	// other threads can dedicate themselves to finish up a lot of the really quick ones. Balancing out the
	// work and taking less time to finish overall.
	//
	before = current_time_monotonic();
	cpu_dispatch(100, unbalanced_load, mode = .LOAD_BALANCING);
	load_balancing_time := to_float64_seconds(current_time_monotonic() - before) * 1000.0;
    print("With LOAD_BALANCING it took %ms\n", to_float64_seconds(current_time_monotonic() - before) * 1000.0);
	print_durations_per_thread();

	print("The load balancing mode was % times faster\n", contiguous_items_time / load_balancing_time);
}



#scope_file



print_example_name :: (name : string) #expand
{
    for 0..(8 + name.count)-1 print("#");
    print("\n### % ###\n", name);
    for 0..(8 + name.count)-1 print("#");
    print("\n");
    `defer print("\n\n\n");
}



#add_context completed_work_items : [..] struct { item_index : int; duration : float; };
store_work_item_duration :: () #expand
{
    before := current_time_monotonic();
    `defer
    {
        duration := cast(float32)(to_float64_seconds(current_time_monotonic() - before) * 1000.0);
        array_add(*context.completed_work_items, .{context.dispatch_index, duration});
    }
}
print_durations_per_thread :: (seconds_per_character := 0.01) #expand
{
	print("These are the items that were processed by each thread:\n");
	print_durations_for_this_thread :: (seconds_per_character : float)
	{
		builder : String_Builder;
		defer reset(*builder);
		print_to_builder(*builder, "Thread % (% items): ", formatInt(context.thread_index, minimum_digits = 3), formatInt(context.completed_work_items.count, minimum_digits = 2));
		for context.completed_work_items
		{
			character_count := (cast(int)ceil(it.duration / seconds_per_character)) / 2;
			append(*builder, "[");
			for 0..character_count-1 append(*builder, ".");
			print_to_builder(*builder, "%", formatInt(it.item_index, minimum_digits = 2));
			for 0..character_count-1 append(*builder, ".");
			append(*builder, "]");
		}
		append(*builder, "\n");
		print(builder_to_string(*builder));
		array_reset(*context.completed_work_items);
	}
	cpu_dispatch(1, print_durations_for_this_thread, seconds_per_character, mode = .PER_THREAD);
	print("\n");
}


