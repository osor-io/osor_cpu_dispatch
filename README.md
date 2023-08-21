# :trident: A CPU Dispatch module for Jai

A `cpu_dispatch`/`parallel-for` module for the Jai programming language. You can check the code in [module.jai](module.jai) then a few examples of how to use them in [example.jai](example.jai).

## How To

Before starting you have to call `cpu_dispatch_init` so it can create the threads to be used later:
```
main :: ()
{
    cpu_dispatch_init();
    defer cpu_dispatch_deinit();
    /*...*/
}
```

To dispatch a procedure 100 times amongst the available threads, you only have to declare it and call it via `cpu_dispatch` like this:
```
my_procedure :: () { /*...*/ }
cpu_dispatch(100, my_procedure);
```

If you want to pass parameters, you can pass them directly after the procedure argument, in the same order as if you were calling it:
```
my_procedure :: (a : int, b : float, c : string) { /*...*/ }
cpu_dispatch(100, my_procedure, 1, 2.3, "four");
```

You can access the which work item index the procedure is currently on via `context.dispatch_index`:
```
my_procedure :: () { print("Thread % is processing item %\n", context.thread_index, context.dispatch_index); }
cpu_dispatch(100, work);
```

There's more options to decide if you want the `cpu_dispatch` to balance the load, call your procedure once per available thread, etc. You can see them all working in the [examples](example.jai) file. They are also explained in more detail under `CPU_Dispatch_Mode` in the [module](module.jai) file, where you can also read an unchained rant about why I like this paradigm for threading and why you should add it to your toolbox.

## License

I want people to be able to just use this without thinking about licensing, although give me a shout if you do use it and attribution is appreciated 😊. Replicating STB's (https://github.com/nothings/stb) licensing stuff where you can choose to use public domain or MIT.
