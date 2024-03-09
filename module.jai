


//
// The principle behind cpu_dispatch(...) is to execute the same procedure
// multiple times and use threads to your advantage to make that faster. Some
// languages also call this a parallel-for.
//
// You can access this via calling the cpu_dispatch() procedures
// in this module. Although don't forget to call cpu_dispatch_init()
// and cpu_dispatch_deinit() at the start and end of you application.
//
// The idea is that you take your N iterations of the loop you would
// have ran. And split that work between some threads so they each do
// a subset. In theory you could be getting a speed-up of times the number
// of threads used. So if you had 100 items and they took 100ms to do in one
// thread, if you dispatched amongs 10 threads you'd be 10x faster, so 10ms to
// finish your whole loop!
//
// The reality of computers is slightly different, the threads need to spin
// up and get the work assigned, their caches will need to be filled, your
// work might have contention, etc. But you often get very good speed-ups
// for little complexity. Especially compared to other threading paradigms.
//
// The catch is that the iterations of your loop can now happen
// at the same time, so they must be independent of each other. If one iteration
// needs the result of the previous one, this is harder to do. Although sometimes
// you still can, by computing partial results on each thread and combining them
// later.
//
// Another benefit of this is that with this type of multithreading, your code
// can scale to an arbitrary number of threads. Whereas with other forms of 
// multithreading where you might spin a thread to do physics, another one to
// do gameplay, etc. You're limited in the amount of threads that your code will
// ever use.
//
// Yet another thing about this paradigm is that you can mostly think of your
// application as a single-threaded application. And then you find the spots that
// need sped up and paralelize them with this. The logic ends up way cleaner
// than if you set up a whole job system with dependencies, etc. It's more 
// straightforward to read and it's clear when multithreading is at play.
//
// If you've worked with GPUs, this mimics that mental model really well, 
// especially if you've worked with compute shaders. There, you end up shaping
// your problems so they become massively parallel, with single independent
// work items to compute. The GPU then processes them all practically at
// the same time (not exactly, but that can be the mental model). One of the
// reasons GPUs have been able to scale so incredibly well even with really
// old code is that this mental model is the essence of how they work.
//
// You could take a game from years ago and run it on a GPU that has twice
// the amount of cores (the meaning of "core" being slightly hazy but we'll
// ignore that) and you'll see a very linear scaling with the amount of pixels
// (or vertices, or other things) that it process at the same time. This is
// clasically not the case with CPU code, where if you take many games and run
// them on a 4-core CPU and a 32-core CPU they might perform the same.
//
// There's going to be cases where spinning up a bespoke thread (audio, I/O, etc)
// will be the right thing to do still. But trying to think of this dispatch
// paradigm first has proven to be very useful for me personally.
// Compared to other types of heterogeneous multithreading, (bespoke long lived threads,
// job systems, etc.) this paradigm tends to keep solutions simpler and with less code.
//
// Damn, that sounds like I'm really a GPU person. I am though, Sony was right
// with the PS3, SPUs were ahead of their time and they'll come back :D
//
//                                     - Ruben Osorio, 21/08/2023
// 
//



#add_context dispatch_index : s64 = -1;
cpu_dispatch :: (dispatch_count : int, $procedure : $P, $arguments : ..Code, $mode : CPU_Dispatch_Mode = .CONTIGUOUS_ITEMS) #expand
{ 
    ARGUMENT_TYPE_COUNT :: #run type_info(P).argument_types.count;
    ARGUMENT_TYPES :: #run () -> [ARGUMENT_TYPE_COUNT]Type
    {
        types : [ARGUMENT_TYPE_COUNT]Type;
        for type_info(P).argument_types types[it_index] = get_type(it);
        return types;
    }();

    #insert -> string
    {
        builder : String_Builder;

        append(*builder, "Packed_Arguments :: struct {");
        for ARGUMENT_TYPES print(*builder, "argument_%1 : ARGUMENT_TYPES[%1];", it_index);
        append(*builder, "}\n");

        append(*builder, "packed_arguments := Packed_Arguments.{");
        for arguments print(*builder, "argument_%1 = #insert arguments[%1],", it_index);
        append(*builder, "};\n");

        append(*builder, "non_polymorph_procedure :: #procedure_of_call procedure(");
        for arguments print(*builder, "packed_arguments.argument_%,", it_index);
        append(*builder, ");\n");

        return builder_to_string(*builder);
    }

    call_procedure_with_packed_arguments :: ($procedure : $Procedure, packed_arguments : *$Packed_Arguments)
    {
        #insert -> string
        {
            builder : String_Builder;
            append(*builder, "procedure(");
            for 0..ARGUMENT_TYPE_COUNT-1 print(*builder, "packed_arguments.argument_%,", it);
            append(*builder, ");\n");
            return builder_to_string(*builder);
        }
    }

    internal_procedure :: (dispatch_index : int, pointer_to_arguments : *void) #no_abc
    {
        packed_arguments := cast(*Packed_Arguments)pointer_to_arguments;
        #if mode == .CONTIGUOUS_ITEMS || mode == .PER_THREAD
        {
            context.dispatch_index = dispatch_index;
            call_procedure_with_packed_arguments(procedure, packed_arguments);
            context.dispatch_index = -1;
        }
        else #if mode == .LOAD_BALANCING
        {
            while true
            {
                context.dispatch_index = atomic_add(*cpu_dispatch_load_balancing_counter, 1);
                defer context.dispatch_index = -1;
                if context.dispatch_index >= cpu_dispatch_load_balancing_dispatch_count then break;
                call_procedure_with_packed_arguments(procedure, packed_arguments);
            }
        }
        else #assert(false);
    }

    cpu_dispatch_wake_threads_up();
    defer cpu_dispatch_send_threads_to_sleep();
    #if mode == .CONTIGUOUS_ITEMS
    {
        cpu_dispatch_distributed_internal(dispatch_count, internal_procedure, *packed_arguments);
    }
    else #if mode == .LOAD_BALANCING
    {
        assert(cpu_dispatch_load_balancing_counter == 0);
        assert(cpu_dispatch_load_balancing_dispatch_count == 0);
        cpu_dispatch_load_balancing_counter = 0;
        cpu_dispatch_load_balancing_dispatch_count = dispatch_count;
        cpu_dispatch_per_thread_internal(1, internal_procedure, *packed_arguments);
        assert(cpu_dispatch_load_balancing_counter >= cpu_dispatch_load_balancing_dispatch_count);
        cpu_dispatch_load_balancing_counter = 0;
        cpu_dispatch_load_balancing_dispatch_count = 0;
    }
    else #if mode == .PER_THREAD
    {
        cpu_dispatch_per_thread_internal(dispatch_count, internal_procedure, *packed_arguments);
    }
    else
    {
        #assert(false);
    }
}



CPU_Dispatch_Mode :: enum
{
    CONTIGUOUS_ITEMS;
    //
    // This spreads the N amount of items into batches of roughly
    // N/threads items, and gives one batch to each thread. Every batch
    // is processed contiguously, meaning that one thread would do 0..X,
    // another would do X+1..Y, next one would do Y+1..Z, etc.
    //
    // If the threads are processing contiguous items in arrays, and/or if
    // they would have better cache access when accessing items in order
    // this is the preferred mode.
    //

    LOAD_BALANCING;
    //
    // This makes every thread retrieve items from a shared counter. It starts
    // with a counter to zero and each thread increments it atomically to grab an
    // index to process, then processes that one and atomically grabs a new one.
    //
    // This makes it so each thread would grab items out of order, for example, a 
    // thread could be getting item index 0, 2, 5, 8, while another one does 1, 3, 4,
    // 6, 7. So potential cache access is worse in certain scenarios.
    //
    // However, the advantage of this is in cases where each work item can take very 
    // different amounts of processing times. Because if one thread gets an item that takes
    // a while, it can stay working on that one while other threads get cheaper work items.
    // This is because as opposed to the mode above, one thread doesn't have a predetermined
    // set of items to process, they just query until there's nothing else to do.
    //

    PER_THREAD;
    //
    // This dispatches "dispatch_count" number of items per-thread. In case you want to 
    // do something fairly custom with it. A case that's frequently used is dispatch_count=1
    // so you can run some piece of code once per thread. For example, to reset your temporary
    // storage, or to aggregate results done in a previous cpu_dispatch.
    //
};



cpu_dispatch_init :: (percentage_of_processors_to_use := 0.8,
                      min_threads_to_create           := 4,
                      temporary_storage_for_threads   := 128 * 1024,
                      base_context_for_threads        : *Context = null,
                      $on_thread_start                : Code = #code {},
                      $on_thread_end                  : Code = #code {})
{
    should_threads_be_running = 0;
    thread_count := max(cast(int)(cast(float32)get_number_of_processors() * percentage_of_processors_to_use), min_threads_to_create);
    per_cpu_dispatch_thread, per_cpu_dispatch_thread_original_memory = NewArray(thread_count, Per_Thread_Data, alignment = CACHE_LINE_SIZE);
    if !base_context_for_threads then base_context_for_threads = *context;
    THREAD_PROCEDURE :: #bake_arguments thread_procedure(on_thread_start = on_thread_start, on_thread_end = on_thread_end);
    for * per_cpu_dispatch_thread
    {
        it.* = .{};
        it._cpu_dispatch_thread_index = xx it_index;
        it.thread.starting_context = base_context_for_threads.*;
        it.thread.data = cast(*void)it;
        success := thread_init(*it.thread, THREAD_PROCEDURE, temporary_storage_size = cast(s32)temporary_storage_for_threads); 
        assert(success);
    }
    for * per_cpu_dispatch_thread thread_start(*it.thread);
}

cpu_dispatch_deinit :: ()
{
    cpu_dispatch_wake_threads_up();
    for * per_cpu_dispatch_thread
    {
        it.should_stop = true;
        signal_work_available(it);
        while !thread_is_done(*it.thread){}
        thread_deinit(*it.thread);
    }
    per_cpu_dispatch_thread.data = null;
    per_cpu_dispatch_thread.count = 0;
    free(per_cpu_dispatch_thread_original_memory);
}



cpu_dispatch_wake_threads_up :: ()
{
    should_threads_be_running += 1;
    signal_value_changed(*should_threads_be_running);
}

cpu_dispatch_send_threads_to_sleep :: ()
{
    should_threads_be_running -= 1;
    signal_value_changed(*should_threads_be_running);
    #assert(should_threads_be_running >= 0);
}



#scope_file



#import "Basic";
#import "Compiler";
#import "Math";
#import "Thread";
#import "Atomics";
#import "System";
#import "Machine_X64";



should_threads_be_running : s32 = 0;
per_cpu_dispatch_thread : []Per_Thread_Data;
per_cpu_dispatch_thread_original_memory : *void;
CACHE_LINE_SIZE :: 64;
Per_Thread_Data :: struct
{
    Unpadded_Data :: struct
    {
        _cpu_dispatch_thread_index : s32;
        thread : Thread;
        work_flag : s32 = 0;
        should_stop := false;

        first_dispatch_index := 0;
        last_dispatch_index  := 0;
        user_procedure : Internal_Procedure;
        user_data      : *void;
    }
    PAD_TO_CACHELINE_SIZE :: #run (align_forward(size_of(Unpadded_Data), CACHE_LINE_SIZE) - size_of(Unpadded_Data));

    using unpadded_data : Unpadded_Data;
    padding : [PAD_TO_CACHELINE_SIZE]u8;
}
#assert((size_of(Per_Thread_Data) % CACHE_LINE_SIZE) == 0);

#add_context cpu_dispatch_thread_index : s64 = -1;
thread_procedure :: (_thread : *Thread, $on_thread_start : Code, $on_thread_end : Code) -> s64
{
    using per_thread_data := cast(*Per_Thread_Data)_thread.data;
    context.cpu_dispatch_thread_index = per_thread_data._cpu_dispatch_thread_index;
    #insert on_thread_start;
    while !should_stop
    {
        wait_for_work_to_do(per_thread_data);
        if should_stop then break;
        for first_dispatch_index..last_dispatch_index
            user_procedure(it, user_data);
        signal_work_done(per_thread_data);
    }
    #insert on_thread_end;
    return 0;
}

Internal_Procedure :: #type (thread_index : int, parameters : *void);
cpu_dispatch_load_balancing_counter        : s64 = 0;
cpu_dispatch_load_balancing_dispatch_count : s64 = 0;



cpu_dispatch_distributed_internal :: (dispatch_count : int, internal_procedure : Internal_Procedure, procedure_arguments : *void)
{
    if #compile_time
    {
        for 0..dispatch_count-1
        {
            internal_procedure(it, procedure_arguments);
        }
    }
    else
    {
        assert(context.thread_index == 0);
        assert(context.dispatch_index == -1);

        available_threads_to_do_work := per_cpu_dispatch_thread.count + 1;
        base_count_per_thread        := cast(int)floor(cast(float64)dispatch_count / cast(float64)available_threads_to_do_work); 
        remainder                    := dispatch_count - (base_count_per_thread * available_threads_to_do_work); 
        current_first_dispatch_index := 0;

        // First we have the main thread dispatch work to all the other threads
        for * per_cpu_dispatch_thread
        {
            count_for_this_thread := base_count_per_thread; 
            if remainder > 0 then { count_for_this_thread += 1; remainder -= 1; }
            if count_for_this_thread > 0
            {
                it.first_dispatch_index = current_first_dispatch_index;
                it.last_dispatch_index  = current_first_dispatch_index + count_for_this_thread - 1;
                it.user_procedure = internal_procedure;
                it.user_data      = procedure_arguments;
                signal_work_available(it);
                current_first_dispatch_index += count_for_this_thread;
            }
            else
            {
                signal_work_done(it);
            }
        }

        // Then we have the main thread itself do work, cause it would be waiting otherwise
        {
            count_for_this_thread := base_count_per_thread; 
            if remainder > 0 then { count_for_this_thread += 1; remainder -= 1; }
            if count_for_this_thread >  0
            {
                first_dispatch_index := current_first_dispatch_index;
                last_dispatch_index  := current_first_dispatch_index + count_for_this_thread - 1;
                for first_dispatch_index..last_dispatch_index
                    internal_procedure(it, procedure_arguments);
                current_first_dispatch_index += count_for_this_thread;
            }
        }

        // Make sure we've done all the work
        assert(remainder == 0);
        assert(current_first_dispatch_index == dispatch_count);

        // Wait for all threads to finish then return.
        for * per_cpu_dispatch_thread
        {
            wait_for_work_done(it);
        }
    }
}

cpu_dispatch_per_thread_internal :: (dispatch_count : int, internal_procedure : Internal_Procedure, procedure_arguments : *void)
{
    if #compile_time
    {
        for 0..dispatch_count-1
        {
            internal_procedure(0, procedure_arguments);
        }
    }
    else
    {
        assert(context.thread_index == 0);
        assert(context.dispatch_index == -1);

        // We dispatch dispatch_count work items for all the extra cpu_dispatch threads
        for * per_cpu_dispatch_thread
        {
            it.first_dispatch_index = 0;
            it.last_dispatch_index  = dispatch_count - 1;
            it.user_procedure = internal_procedure;
            it.user_data      = procedure_arguments;
            signal_work_available(it);
        }

        // Tell the main thread to do its part as well
        for 0..dispatch_count-1
        {
            internal_procedure(per_cpu_dispatch_thread.count, procedure_arguments);
        }

        // Wait for all threads to finish then return.
        for * per_cpu_dispatch_thread
        {
            wait_for_work_done(it);
        }
    }
}



signal_work_available :: (using per_thread_data : *Per_Thread_Data)
{
    work_flag_pointer := *work_flag;

    // Set the flag to 1 and make sure it was 0
    flag : s32 = 1;
    #asm { lock_xchg.d flag, [work_flag_pointer]; }
    assert(flag == 0);
}

wait_for_work_to_do :: (using per_thread_data : *Per_Thread_Data)
{
    work_flag_pointer := *work_flag;

    while true
    {
        // We first spin when waiting for work to be available. We do this
        // first because if the user does multiple calls to cpu_dispatch(...)
        // in a row, we might be fast enough that we catch a second call
        // immediately after the first one. Meaning that we don't even bother
        // yielding, or going to sleep, or whatever we want to do once we
        // spin enough.
        //
        // We'll wait here for 65536 cycles, which in a 5GHz processor should
        // be (65536/5e9)=13.1072 microseconds. So if the user manages to call
        // cpu_dispatch(...) twice in that amount of time, we'll catch it on
        // this first spin loop and we avoid big context switches.
        //
        SPIN_CYCLES :: 65536;
        spin_start := rdtsc();
        while true
        {
            // Loop here until flag is 1, note that the flag could either
            // be 0 (no work) or 2 (work finished), because after work is done
            // we could be waiting for more work before someone else has seen
            // that the work was done and has reset the flag
            flag : s32 = 0;
            #asm { mov.d flag, [work_flag_pointer]; }
            if flag == 1 then return;

            // Hint that we're on a spin-wait loop
            #asm { pause; }

            // Spin here for a few cycles before we yield
            if (rdtsc() - spin_start) < SPIN_CYCLES then break;
        }

        // If we have spun for enough cycles, we tell the OS it's fine to
        // switch us so someone else goes to do some work
        yield_to_another_thread();

        // If the value is zero, it means that the main thread is wanting us to
        // suspend execution until it becomes non-zero again. We do the check first
        // ourselves to avoid the potentially more expensive comparison on whatever
        // OS call this would go to.
        if should_threads_be_running == 0 then wait_while_value_matches(*should_threads_be_running, 0);
    }
}

signal_work_done :: (using per_thread_data : *Per_Thread_Data)
{
    work_flag_pointer := *work_flag;

    // Set the flag to 2, it could have been 0 or 1 because
    // sometimes we go from no-work to signal that it's done to
    // mean that worker thread had nothing to do so it's "done"
    flag : s32 = 2;
    #asm { lock_xchg.d flag, [work_flag_pointer]; }
    assert(flag == 0 || flag == 1);
}

wait_for_work_done :: (using per_thread_data : *Per_Thread_Data)
{
    work_flag_pointer := *work_flag;

    // Here we just spin while waiting without much concern
    // since this will be on the main thread and we don't want
    // context switching anyway. Plus we're expecting the loads
    // to be balanced, meaning that all threads, including the
    // main one, should finish roughly at the same time, so we
    // expect to be waiting very little
    while true
    {
        // Loop here until flag is 2
        flag : s32 = 0;
        #asm { mov.d flag, [work_flag_pointer]; }
        if flag == 2 then break;

        // 1 is the only allowed value here, because 0 would mean that
        // there's no work to be done, so we haven't signaled it and we
        // would be waiting for ever cause nobody will ever change the value
        assert(flag == 1);

        // Hint that we're on a spin-wait loop
        #asm { pause; }
    }

    // Set the flag to 0 and make sure it was 2
    flag : s32 = 0;
    #asm { lock_xchg.d flag, [work_flag_pointer]; }
    assert(flag == 2);
}



#if OS == .WINDOWS
{
    #import "Windows";
    yield_to_another_thread :: () { SwitchToThread(); }
    wait_while_value_matches :: (target : *s32, value : s32)
    {
        result := WaitOnAddress(target, *value, size_of(type_of(value)), INFINITE);
        assert(result == .TRUE);
    }
    signal_value_changed :: (target : *s32)
    {
        WakeByAddressAll(target);
    }

    kernel32 :: #system_library "kernel32";
    synchronization :: #system_library,no_dll "synchronization";
    SwitchToThread :: () -> BOOL #foreign kernel32;
    WaitOnAddress :: (Address : *void, CompareAddress : *void, AddressSize : SIZE_T, dwMilliseconds : DWORD) -> BOOL #foreign synchronization;
    WakeByAddressAll :: (Address : *void) #foreign synchronization;
}
else #if OS == .LINUX || OS == .MACOS
{
    #assert(false);
    /*
    #import "POSIX";
    yield_to_another_thread :: () { pthread_yield_np(); }
    wait_while_value_matches :: (target : *s32, value : s32)
    {
        // @@TODO: Maybe using futex?
    }
    signal_value_changed :: (target : *s32)
    {
        // @@TODO: Maybe using futex?
    }
    */
}



