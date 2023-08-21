


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
cpu_dispatch :: (dispatch_count : int, $procedure : $P,                                                                         $mode : CPU_Dispatch_Mode = .CONTIGUOUS_ITEMS, $loc := #caller_location) { arguments : struct {}                                                       = .{};                           cpu_dispatch_internal(dispatch_count, procedure, *arguments, mode, loc); }
cpu_dispatch :: (dispatch_count : int, $procedure : $P, a0:$A0,                                                                 $mode : CPU_Dispatch_Mode = .CONTIGUOUS_ITEMS, $loc := #caller_location) { arguments : struct {a0:A0;}                                                 = .{a0};                         cpu_dispatch_internal(dispatch_count, procedure, *arguments, mode, loc); }
cpu_dispatch :: (dispatch_count : int, $procedure : $P, a0:$A0, a1:$A1,                                                         $mode : CPU_Dispatch_Mode = .CONTIGUOUS_ITEMS, $loc := #caller_location) { arguments : struct {a0:A0;a1:A1;}                                           = .{a0,a1};                      cpu_dispatch_internal(dispatch_count, procedure, *arguments, mode, loc); }
cpu_dispatch :: (dispatch_count : int, $procedure : $P, a0:$A0, a1:$A1, a2:$A2,                                                 $mode : CPU_Dispatch_Mode = .CONTIGUOUS_ITEMS, $loc := #caller_location) { arguments : struct {a0:A0;a1:A1;a2:A2;}                                     = .{a0,a1,a2};                   cpu_dispatch_internal(dispatch_count, procedure, *arguments, mode, loc); }
cpu_dispatch :: (dispatch_count : int, $procedure : $P, a0:$A0, a1:$A1, a2:$A2, a3:$A3,                                         $mode : CPU_Dispatch_Mode = .CONTIGUOUS_ITEMS, $loc := #caller_location) { arguments : struct {a0:A0;a1:A1;a2:A2;a3:A3;}                               = .{a0,a1,a2,a3};                cpu_dispatch_internal(dispatch_count, procedure, *arguments, mode, loc); }
cpu_dispatch :: (dispatch_count : int, $procedure : $P, a0:$A0, a1:$A1, a2:$A2, a3:$A3, a4:$A4,                                 $mode : CPU_Dispatch_Mode = .CONTIGUOUS_ITEMS, $loc := #caller_location) { arguments : struct {a0:A0;a1:A1;a2:A2;a3:A3;a4:A4;}                         = .{a0,a1,a2,a3,a4};             cpu_dispatch_internal(dispatch_count, procedure, *arguments, mode, loc); }
cpu_dispatch :: (dispatch_count : int, $procedure : $P, a0:$A0, a1:$A1, a2:$A2, a3:$A3, a4:$A4, a5:$A5,                         $mode : CPU_Dispatch_Mode = .CONTIGUOUS_ITEMS, $loc := #caller_location) { arguments : struct {a0:A0;a1:A1;a2:A2;a3:A3;a4:A4;a5:A5;}                   = .{a0,a1,a2,a3,a4,a5};          cpu_dispatch_internal(dispatch_count, procedure, *arguments, mode, loc); }
cpu_dispatch :: (dispatch_count : int, $procedure : $P, a0:$A0, a1:$A1, a2:$A2, a3:$A3, a4:$A4, a5:$A5, a6:$A6,                 $mode : CPU_Dispatch_Mode = .CONTIGUOUS_ITEMS, $loc := #caller_location) { arguments : struct {a0:A0;a1:A1;a2:A2;a3:A3;a4:A4;a5:A5;a6:A6;}             = .{a0,a1,a2,a3,a4,a5,a6};       cpu_dispatch_internal(dispatch_count, procedure, *arguments, mode, loc); }
cpu_dispatch :: (dispatch_count : int, $procedure : $P, a0:$A0, a1:$A1, a2:$A2, a3:$A3, a4:$A4, a5:$A5, a6:$A6, a7:$A7,         $mode : CPU_Dispatch_Mode = .CONTIGUOUS_ITEMS, $loc := #caller_location) { arguments : struct {a0:A0;a1:A1;a2:A2;a3:A3;a4:A4;a5:A5;a6:A6;a7:A7;}       = .{a0,a1,a2,a3,a4,a5,a6,a7};    cpu_dispatch_internal(dispatch_count, procedure, *arguments, mode, loc); }
cpu_dispatch :: (dispatch_count : int, $procedure : $P, a0:$A0, a1:$A1, a2:$A2, a3:$A3, a4:$A4, a5:$A5, a6:$A6, a7:$A7, a8:$A8, $mode : CPU_Dispatch_Mode = .CONTIGUOUS_ITEMS, $loc := #caller_location) { arguments : struct {a0:A0;a1:A1;a2:A2;a3:A3;a4:A4;a5:A5;a6:A6;a7:A7;a8:A8;} = .{a0,a1,a2,a3,a4,a5,a6,a7,a8}; cpu_dispatch_internal(dispatch_count, procedure, *arguments, mode, loc); }

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
    thread_count := max(cast(int)(cast(float32)get_number_of_processors() * percentage_of_processors_to_use), min_threads_to_create);
    per_cpu_dispatch_thread, per_cpu_dispatch_thread_original_memory = NewArray(thread_count, Per_Thread_Data, alignment = CACHE_LINE_SIZE);
    if !base_context_for_threads then base_context_for_threads = *context;
    THREAD_PROCEDURE :: #bake_arguments thread_procedure(on_thread_start = on_thread_start, on_thread_end = on_thread_end);
    for * per_cpu_dispatch_thread
    {
        it.* = .{};
        it._cpu_dispatch_thread_index = xx it_index;
        it.thread.starting_context = base_context_for_threads.*;
        init(*it.work_available_event);
        init(*it.work_done_event);
        it.thread.data = cast(*void)it;
        success := thread_init(*it.thread, THREAD_PROCEDURE, temporary_storage_size = cast(s32)temporary_storage_for_threads); 
        assert(success);
    }
    for * per_cpu_dispatch_thread thread_start(*it.thread);
}

cpu_dispatch_deinit :: ()
{
    for * per_cpu_dispatch_thread
    {
        it.should_stop = true;
        signal(*it.work_available_event);
        while !thread_is_done(*it.thread){}
        thread_deinit(*it.thread);
        destroy(*it.work_available_event);
        destroy(*it.work_done_event);
    }
    per_cpu_dispatch_thread.data = null;
    per_cpu_dispatch_thread.count = 0;
    free(per_cpu_dispatch_thread_original_memory);
}



#scope_file



#import "Basic";
#import "Compiler";
#import "Math";
#import "Thread";
#import "Atomics";
#import "System";



cpu_dispatch_internal :: (dispatch_count : int, $procedure : $Procedure, arguments : *$Arguments, $mode : CPU_Dispatch_Mode, $loc : Source_Code_Location)
{
    #insert #run generate_internal_procedure(Procedure, Arguments, mode, loc);
    #if mode == .CONTIGUOUS_ITEMS
    {
        cpu_dispatch_distributed_internal(dispatch_count, internal_procedure, arguments);
    }
    else #if mode == .LOAD_BALANCING
    {
        assert(cpu_dispatch_load_balancing_counter == 0);
        assert(cpu_dispatch_load_balancing_dispatch_count == 0);
        cpu_dispatch_load_balancing_counter = 0;
        cpu_dispatch_load_balancing_dispatch_count = dispatch_count;
        cpu_dispatch_per_thread_internal(1, internal_procedure, arguments);
        assert(cpu_dispatch_load_balancing_counter >= cpu_dispatch_load_balancing_dispatch_count);
        cpu_dispatch_load_balancing_counter = 0;
        cpu_dispatch_load_balancing_dispatch_count = 0;
    }
    else #if mode == .PER_THREAD
    {
        cpu_dispatch_per_thread_internal(dispatch_count, internal_procedure, arguments);
    }
    else
    {
        #assert(false);
    }
}



Internal_Procedure :: #type (thread_index : int, parameters : *void);
cpu_dispatch_load_balancing_counter        : s64 = 0;
cpu_dispatch_load_balancing_dispatch_count : s64 = 0;
generate_internal_procedure :: (Procedure_Type : Type, Arguments_Type : Type, mode : CPU_Dispatch_Mode = .CONTIGUOUS_ITEMS, $loc : Source_Code_Location) -> string
{
    procedure_info := cast(*Type_Info_Procedure)Procedure_Type;
    if procedure_info.type != .PROCEDURE
        compiler_report(tprint("The procedure to dispatch is not a procedure?! It's a %", Procedure_Type), loc);
    if procedure_info.return_types.count > 0
        compiler_report(tprint("Procedure % used in CPU Dispatch system cannot return anything!", Procedure_Type), loc);

    arguments_info := cast(*Type_Info_Struct)Arguments_Type;
    if arguments_info.type != .STRUCT
        compiler_report(tprint("The arguments type is somehow not a struct?! It's a %", Arguments_Type), loc);

    if procedure_info.argument_types.count != arguments_info.members.count
        compiler_report(tprint("The procedure takes % members, and the user provided %. These should match", procedure_info.argument_types.count, arguments_info.members.count), loc);

    info_to_name :: (info : *Type_Info) -> string
    {
        builder : String_Builder;
        defer reset(*builder);
        print_type_to_builder(*builder, info);
        return builder_to_string(*builder);
    }
    for procedure_argument : procedure_info.argument_types
        if procedure_argument != arguments_info.members[it_index].type
            compiler_report(tprint("Expected % but argument % it's a %", info_to_name(procedure_argument), it_index, info_to_name(arguments_info.members[it_index].type)), loc);

    // Generate an internal procedure that just wraps the call to the real procedure and 
    // passes in the arguments. This way we standarize the type of the outer procedure that
    // each thread will have to call and we don't have to worry about polymorphism outside
    // of here.
    builder : String_Builder;
    defer reset(*builder);
    p :: (format_string : string, args: ..Any) #expand { print_to_builder(*builder, format_string, ..args); } @PrintLike
    a :: (the_string : string) #expand { append(*builder, the_string); }
    generate_procedure_call :: () #expand
    {
        a("arguments := cast(*Arguments)pointer_to_arguments;\n");
        a("procedure(");
        for procedure_info.argument_types
        {
            if it_index == 0 then p("arguments.a%", it_index);
                             else p(", arguments.a%", it_index);
        }
        a(");\n");
    }
    p("internal_procedure :: (dispatch_index : int, pointer_to_arguments : *void) #no_abc \n{\n");
    if mode == .CONTIGUOUS_ITEMS || mode == .PER_THREAD
    {
        p("context.dispatch_index = dispatch_index;\n");
        generate_procedure_call();
        p("context.dispatch_index = -1;\n");
    }
    else if mode == .LOAD_BALANCING
    {
        a("while true\n");
        a("{\n");
        a("    context.dispatch_index = atomic_add(*cpu_dispatch_load_balancing_counter, 1);\n");
        a("    defer context.dispatch_index = -1;\n");
        a("    if context.dispatch_index >= cpu_dispatch_load_balancing_dispatch_count then break;\n");
        generate_procedure_call();
        a("}\n");
    }
    else
    {
        compiler_report(tprint("Somehow we ended up with an incorrect cpu_dispatch mode?? We don't know what % means", mode), loc);
    }
    p("}\n\n\n");

    return builder_to_string(*builder);

}



per_cpu_dispatch_thread : []Per_Thread_Data;
per_cpu_dispatch_thread_original_memory : *void;
CACHE_LINE_SIZE :: 64;
Per_Thread_Data :: struct
{
    Unpadded_Data :: struct
    {
        _cpu_dispatch_thread_index : s32;
        thread : Thread;
        work_available_event : Event;
        work_done_event      : Event;
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
        wait_for(*work_available_event);
        if should_stop then break;
        for first_dispatch_index..last_dispatch_index
            user_procedure(it, user_data);
        signal(*work_done_event);
    }
    #insert on_thread_end;
    return 0;
}



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
                signal(*it.work_available_event);
                current_first_dispatch_index += count_for_this_thread;
            }
            else
            {
                signal(*it.work_done_event);
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
            wait_for(*it.work_done_event);
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
            signal(*it.work_available_event);
        }

        // Tell the main thread to do its part as well
        for 0..dispatch_count-1
        {
            internal_procedure(per_cpu_dispatch_thread.count, procedure_arguments);
        }

        // Wait for all threads to finish then return.
        for * per_cpu_dispatch_thread
        {
            wait_for(*it.work_done_event);
        }
    }
}



#if OS == .WINDOWS
{
    #import "Windows";
    Event :: struct { event : HANDLE; }
    init :: (event : *Event) 
    {
        event.event = CreateEventW(null, 0, 0, null);
        assert(event != null);
    }
    destroy :: (event : *Event) {
        result := CloseHandle(event.event);
        assert(result != 0);
    }
    signal :: (event : *Event)
    {
        result := SetEvent(event.event);
        assert(result != .FALSE);
    }
    wait_for :: (event : *Event)
    {
        result := WaitForSingleObject(event.event, WIN_TIMEOUT_INFINITE);
        assert(result != WAIT_FAILED);
    }

    SetEvent :: (handle : HANDLE) -> BOOL #foreign kernel32;
    kernel32 :: #system_library "kernel32";
}
else #if OS == .LINUX || OS == .MACOS
{
    #assert(false);
    //
    // Here there's a pootential POSIX implementation, but I haven't
    // tested it yet so I'll leave it commented out for the time being.
    //
    // Maybe we prefer semaphores in general for both cases?
    //
    /*
    #import "POSIX";
    Event :: struct { condition : pthread_cond_t; }
    init :: (event : *Event) 
    {
        result := pthread_cond_init(*event.condition, null);
        assert(result == 0);
    }
    destroy :: (event : *Event)
    {
        result := pthread_cond_destroy(*event.condition);
        assert(result == 0);
    }
    signal :: (event : *Event)
    {
        result := pthread_cond_signal(*event.condition);
        assert(result == 0);
    }
    wait_for :: (event : *Event)
    {
        result := pthread_cond_wait(*event.condition);
        assert(result == 0);
    }
    */
}
