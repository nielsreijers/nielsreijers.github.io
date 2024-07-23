---
layout: post
title:  "Niels learns Rust 5 — Testing an embedded system"
date:   2024-07-22 00:00:00 +0000
categories: blog
tags: [ rust ]
---

*This is part 5 in my journey to learn Rust by porting my embedded Java virtual machine to it.
Click [here](/blog/tag/rust) for the whole series.*

It's been a while since the last post. Other stuff got in the way, and I've been stuck for a while on how to implement the heap and garbage collector for my VM. During this process I wanted to write tests for some options I was considering, so this post will describe the approach I took to unit testing my VM (for now).

It will cover:

- Configuring aborting panics for tests
- Overriding Rust's default test harness
- defmt(-test)
- Proc macros


## Tests in embedded systems


Testing an embedded system is tricky. Resources are limited, we need use either external hardware or a simulator, and there's no screen to print the output to or obvious way to interface with the IDE.

It can be a good idea to split the code you want to test into a platform independent part that can be tested using the normal techniques on a development machine, and limit the device specific code that needs to be tested on the device. See [this](https://ferrous-systems.com/blog/test-embedded-app) article for a much more thorough discussion and suggested project layout.

Since I'm running the code on a simulator and the VM is still small enough to easily fit in the device memory, even with tests, I'll start with a simpler approach based on a library by the same people called [`defmt`](https://defmt.ferrous-systems.com/).



## Custom test harness

By default, the project I generated in [post 2](/blog/2024/05/06/niels-learns-rust-2.html) using the `avr-hal-template` template, doesn't support tests, as we can tell from the `Cargo.toml` it generated:

{% highlight toml %}
[[bin]]
name = "capevm"
test = false
bench = false
{% endhighlight %}

Running `cargo test` doesn't do anything, and simply prints `Finished 'test' profile`.

Of course this wasn't done without reason. After removing the `test = false` line, things immediately break down:
{% highlight text %}
error[E0152]: duplicate lang item in crate `core` (which `rustc_std_workspace_core` depends on): `sized`.
  |
  = note: the lang item is first defined in crate `core` (which `ufmt_write` depends on)
  = note: first definition in `core` loaded from /home/niels/git/capevm-rust/capevm/target/avr-atmega128/debug/deps/libcore-0538a43361b060d2.rmeta
  = note: second definition in `core` loaded from /home/niels/git/capevm-rust/capevm/target/avr-atmega128/debug/deps/libcore-f17641206fc9a410.rmeta
{% endhighlight %}

I haven't figured out all the details yet, but the conflict is caused by Rust's "panic" settings. When code panics, Rust's default behaviour is to unwind the stack, which allows it to safely  release any resources and potentially recover from the panic. However, this infrastructure takes up code space, and may not make sense for small devices, so Rust offers an alternative `abort` behaviour that simply terminates the program immediately.

Our current Cargo.toml contains the line `panic = "abort"` in the `[profile.dev]` and `[profile.release]` sections. If we remove this, we see why. Unwinding panics need the std library, but on the AVR we only have the small core subset, so we need to use the abort strategy:
![Unwinding panic requires std](/assets/img/2024-07-22-unwinding-panic-requires-std.png)

The problem is that when running test, we use the `test` profile, which inherits its settings from the `dev` profile but doesn't support the `abort` behaviour. Cargo is silent about this, unless we explicitly add a `[profile.test]` section and try to set it to abort.

When we look at the detailed compilation output (`cargo -v test`), we see Cargo compiles `core/src/lib.rs` twice, once with the `-C panic=abort` setting, and once without. When we look at the files in the error message, we see the one compiled with unwinding panics is slightly larger:

![Conflicting core libs 1](/assets/img/2024-07-22-conflicting-core-libs-1.png)

I'm still not sure why this happens, but I suspect proc macros (see below). They run under the `dev` profile and so still use `panic=abort`, while the rest of the test code, compiled with the `test` profile would now use unwinding panics. This would explain why Cargo compiles two different binaries for the core library, but it's not clear to me why they would conflict, since running proc macros should be a separate phase before the actual compilation starts.

Whatever the cause is, we need to compile all the code with the abort behaviour, but can't get Cargo to do this for tests compilations. Luckily there's a second place where we can control the panic behaviour: the target platform specification.

The default `panic = "unwind"` setting only really uses unwinding panics if this is supported by the platform. The `avr-spec` directory in our project contains JSON files that define various properties of the AVR cpus, and one of the settings we can add is `"panic-strategy": "abort"`. This forces aborting panics, regardless of what is specified in Cargo.toml, which means the `test` profile will now also use abort.

Interestingly, this is still not enough! Cargo still compiles two versions with and without the `-C panic=abort` flag. These still conflict, although the almost identical file sizes suggests they now both use aborting panics:

![Conflicting core libs 2](/assets/img/2024-07-22-conflicting-core-libs-2.png)

The solution is to remove the `panic = "abort"` lines from Cargo.toml, so Cargo won't add the compile flag at all, but leave it to `rustc` to decide based on the platform definition.

This really was a lot harder to figure out than it should have been. I guess this is not a very common scenario, but while Rust's error messages are usually very clear and immediately point you in the right direction, in this case it took a lot of experimenting to figure out what was going on.

With these two lines changed, it almost compiles, except for one last error: `error[E0463]: can't find crate for 'test'`. As mentioned before, Rusts standard test infrastructure (in the `test` crate) depends on the unwinding panic behaviour, which we have just disabled. We can override this by adding `harness = false` to the `[[bin]]` section in Cargo.toml:

{% highlight toml %}
[[bin]]
name = "capevm"
bench = false
harness = false
{% endhighlight %}

This tells Cargo we don't want to use the `test` crate, but will provide our own implementation. Cargo will simply compile the code as usual, but now with the `test` symbol defined, which we should use for conditional compilation to somehow run tests instead of the normal code.

Since we don't check for the `test` symbol yet, at this point it just runs the `main()` function:

![Cargo test runs main](/assets/img/2024-07-22-cargo-test-runs-main.png)



## Ferrous Systems 'defmt' framework

With that out of the way we can finally start thinking about how to implement tests. For this we will use a small part of a library called [`defmt`](https://defmt.ferrous-systems.com/) from [Ferrous Systems](https://ferrous-systems.com/). This is how the documentation describes it:

> defmt ("de format", short for "deferred formatting") is a highly efficient logging framework that targets resource-constrained devices, like microcontrollers.
>
> Features
> - println!-like formatting
> - Multiple logging levels: error, info, warn, debug, trace
> - Compile-time RUST_LOG-like filtering of logs: include/omit logging levels with module-level granularity
> - Timestamped logs

It's really quite a clever bit of code that let's you use the familiar `println!`-style logging on your device. The general idea is that the formatting is done on the host, and the device only communicates which format string to use and any values to fill in.

Unfortunately it's targetted at Cortex-M processors instead of the AVR, so we can't use it directly, but it's still interesting to look at how it achieves its goal, especially the way the format strings are stored.

Since the device doesn't do any formatting, it would be a waste of precious memory if it had to store the strings. Instead, [each string is interned as a single byte](https://defmt.ferrous-systems.com/interning)!

The trick is that these bytes are put in a separate section in the ELF image, and the actual string is stored in the symbol name. When the device wants to print a formatted string, it only sends the index of the string in this section to the host. The host then looks up the right symbol in the ELF image and knows what to print. A linker script places the section at address 0, so simply taking the address of the dummy byte that represents a string gives us the index we need:

![defmt symbols](/assets/img/2024-07-22-defmt-symbols.png)

This technique could be applied to the way we print strings in Avrora as well, since Avrora also reads the elf file and has access to all the symbols. But for now, we just want to add tests.

The `defmt` repository also contains a [testing framework](https://github.com/knurling-rs/defmt/tree/main/firmware/defmt-test) that uses `defmt` for output. It can be easily adapted for the AVR running in Avrora if we're willing to settle for a somewhat minimalist user experience.


## Using (avr-)defmt-test

The test framework shouldn't be tied to the VM, so I've made it into a separate crate that can be used in other AVR projects as well.

There are several ways to refer to external crates in Cargo.toml. To be able to simply refer to it by name, it needs to be published on [crates.io](https://crates.io/), but this code isn't mature enough for that.

Instead I put it in a [separate repository](https://github.com/nielsreijers/avr-defmt-test)
 in my github. Cargo can fetch dependencies directly from a github repository. By default it takes the most recent commit on the default branch, but for reproducible builds we should specify either a version tag or commit hash to. Since this crate is only needed for testing and not for release builds, it should go under `[dev-dependecies]`:

{% highlight toml %}
[dev-dependencies]
avr-defmt-test = { git = "https://github.com/nielsreijers/avr-defmt-test.git", tag = "0.1.0" }
{% endhighlight %}

We can also import a crate by path, so during development it can be convenient to import it like this to avoid having to push every change to github:

{% highlight toml %}
[dev-dependencies]
avr-defmt-test = { path = "../../avr-defmt-test" }
{% endhighlight %}

With the crate imported, using the framework is quite easy. In `main.rs` we just need to make sure we exclude the `main()` function, since that will be provided by `avr-defmt-test`, and to include the test code which I've put in a separate `tests` module:

{% highlight rust %}
mod avrora;
mod components;
#[cfg(test)]
mod tests;

#[cfg(not(test))]
#[arduino_hal::entry]
fn main() -> ! {
    init();
    avrora::print_flash_string!("Done");
    avrora::exit();
}
{% endhighlight %}

The implementation of the tests module looks like this:
{% highlight rust %}
use crate::avrora;

#[allow(unused_macros)]
#[macro_export]
macro_rules! avr_println {
    ($s:expr) => { {
        crate::avrora::print_flash_string!($s);
    } };
}

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    avrora::print_flash_string!("TEST FAILED!");
    avrora::exit();
}

#[avr_defmt_test::tests(avr_exit=crate::avrora::exit,
                        avr_println=avr_println)]
mod vm_tests {
    #[init]
    fn init() {
        crate::init();
    }

    #[test]
    fn test1() {
        assert_eq!(1, 1);
    }
}
{% endhighlight %}

All tests go into a single module, in this case `crate::tests::vm_tests`, which should be decorated with the `avr_defmt_test::tests` attribute.

To make `defmt-test` independent from Cortex-M specific `defmt`, I simply removed all references to it and replaced them with two dependencies that the user should inject: a macro to print a literal string, and a function to call to exit when the test run is finished.

In addition, a failing assert will cause a panic. In Rust's standard `tests` crate, this panic will be caught and recovered from so the test run can continue. Here, I've removed `panic_halt` and added a custom panic handler, that will print 'TEST FAILED!' and call the `avrora` library to stop the simulation. This replaces the `panic_halt` crate that just enters an endless loop since there's no way to really halt an embedded CPU.



## avr-defmt-test implementation: proc macros

How does this all work internally?

The `[avr_defmt_test::tests]` is a _proc macro_. Rust has two different macro mechanisms: declarative and procedural macros. They both expand to generate new Rust code, but other than that they're quite different beasts.

### Declarative macros

Declarative macros, like `print_flash_string` from [post 3](https://nielsreijers.com/blog/2024/05/10/niels-learns-rust-3.html), are a bit like improved C macros. The call simply gets replaced by the template defined by the macro. But they pattern match so you can have several implementations for different inputs, the template language is more expressive than in C, and most importantly: they're _hygenic_. This means a macro expansion can never accidentally capture an identifier.

A simple [example](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&code=macro_rules%21+test+%7B%0A++++%28%29+%3D%3E+%7B%0A++++++let+x+%3D+1%3B%0A++++++println%21%28%22test%27s+x%3A+%7B%7D%22%2C+x%29%3B%0A++++%7D%3B%0A%7D%0A%0Afn+main%28%29+%7B%0A++let+x+%3D+0%3B%0A++test%21%28%29%3B%0A++println%21%28%22main%27s+x%3A+%7B%7D%22%2C+x%29%3B%0A%7D):
{% highlight rust %}
macro_rules! test {
    () => {
      let x = 1;
      println!("test's x: {}", x);
    };
}

fn main() {
  let x = 0;
  test!();
  println!("main's x: {}", x);
}
{% endhighlight %}

If we expand the macro this becomes:

{% highlight rust %}
fn main() {
  let x = 0;
      let x = 1;
      println!("test's x: {}", x);
  println!("main's x: {}", x);
}
{% endhighlight %}

Using C macro's, this would print 1, 1 since the `let x = 1` in the macro expansion eclipses the earlier `let x = 0`. Rust's hygenic macro's guarantee this doesn't happen, and the macro gets its own `x`, so the output is 1, 0. In fact, removing the `let x = 1` line from the macro yield a compile error, since the macro also cannot use the `x` that happens to exist at its call site.

Unfortunately, there's no way to tell from the `cargo expand` command. Its output would suggest `main`'s `x` does get hidden, so simply copy pasting `cargo expand`'s output into a file isn't guaranteed to yield the same behaviour:

{% highlight rust %}
#![feature(prelude_import)]
#[prelude_import]
use std::prelude::rust_2021::*;
#[macro_use]
extern crate std;
fn main() {
    let x = 0;
    let x = 1;
    {
        ::std::io::_print(format_args!("test\'s x: {0}\n", x));
    };
    {
        ::std::io::_print(format_args!("main\'s x: {0}\n", x));
    };
}
{% endhighlight %}

### Procedural macros

Procedural macros on the other hand, work more like Common Lisp macros: they a stream of tokens as input, and produce a replacement stream of tokens that will be inserted where the macro was called.

There are three different types of proc macros:
- Function-like macros - `custom!(...)`
- Derive macros - `#[derive(CustomTrait)]`
- Attribute macros - `#[CustomAttribute]`

The first looks like a normal call, similar to declarative macros. The `#[derive(...)]` attribute has it's own class of procedural macros which can be used to provide default implementations for a trait. Finally, attribute macros can be used to define any custom attribute that will generate extra code for, or instead of, the definition to which it is applied.

They're complete Rust programs that run at compile time, similar to a `build.rs` script. Contrary to `build.rs` scripts, they must be defined in a separate crate, that needs to be defined as a `proc-macro` crate in Cargo.toml:

{% highlight toml %}
[lib]
proc-macro = true
{% endhighlight %}

In this case `avr-defmt-test` contains this function to define the macro:

{% highlight rust %}
#[proc_macro_attribute]
pub fn tests(args: TokenStream, input: TokenStream) -> TokenStream {
  ...
}
{% endhighlight %}

It has two input streams: `args` for the parameters passed to proc macro, and `input` for the code element the attribute is attached to. Both get replaced by whatever tokens the macro produces in its return `TokenStream`.

Procedural macros are not hygenic like declarative macros. On one hand this means we have to be careful not to accidentally capture or eclipse external symbols. On the other hand it also makes them more powerful in the sense that they can define new symbols that could be used in the code that called the macro. It's a sharp knife.

In summary, the main differences between declarative and procedural macros:

|                | Declarative macro           | Procedural macro                          |
| --             | --                          | --                                        |
| Input          | regex-like pattern matching | one or two `TokenStream`s                 |
| Implementation | simple template language    | rust code running at compile time         |
| Defined in     | normal code                 | separate proc macro crate                 |
| Hygenic        | yes                         | no                                        |



### avr-defmt-test

The `test` attribute needs to be attached to a module that will contain all the tests. The functions in that module all need to get an attribute, either `#[test]`, `#[init]`, `#[before_each]` or `#[after_each]`.

The proc macro then replaces this entire module with its own implementation that adds a `main()` function that calls each of the test methods, and either panics if a test fails, or prints "all tests passed!" and exits.

The changes needed to this work on the AVR turned out to be minimal. I decided to simplify the output a bit so the formatting code could be remove and the main function now simply prints the test name and result as literal strings. All the necessary changes are in [this commit](https://github.com/nielsreijers/avr-defmt-test/commit/af3cb069f7ca58e129d6215f2217e145b083823b).

The most interesting part was how to pass implementations for printing strings and exiting the test run. These were hardcoded in the original, but I wanted to make it more generic.

This is where the first `args` parameter of the attribute macro comes in, which contains the macro parameters. In the case of `#[avr_defmt_test::tests(avr_exit=crate::avrora::exit, avr_println=avr_println)]`, it contains the tokens for `avr_exit=crate::avrora::exit, avr_println=avr_println`.

Two very useful crate for this task are [`syn`](https://crates.io/crates/syn) and [`darling`](https://crates.io/crates/darling). The `syn` crate provides a parser that can turn the `TokenStream` into a more meaningful abstract syntax tree that the proc macro can then navigate and manipulate. In this case it turns the `args` tokens into a list containing two name/value pairs.

This is then used by `darling` to validate the arguments according to some structure that defines the valid parameters. The following struct tells `darling` that we have two required parameters, `avr_println` and `avr_exit` that both should be a `syn::Path`: an identifier, optionally qualified with a module path like `crate::avrora::exit`.

{% highlight rust %}
#[derive(Debug, FromMeta)]
struct MacroArgs {
    avr_println: syn::Path,
    avr_exit: syn::Path,
}
{% endhighlight %}

Wrapping the type in an `Option<>` would make them optional, but in this case we really need both.

After parsing the `args`, we get a `MacroArgs` instance that can be used in the rest of the macro code:

{% highlight rust %}
fn tests_impl(args: TokenStream, input: TokenStream) -> parse::Result<TokenStream> {
    let attr_args = NestedMeta::parse_meta_list(args.into())?;
    let args = MacroArgs::from_list(&attr_args)?;

    let avr_println = args.avr_println;
    let avr_exit = args.avr_exit;
    ...
{% endhighlight %}

The rest of the modifications to the original `defmt-test` are just some simplifications of the output, and replacing calls to `defmt` with the `avr_println` and `avr_exit` variables.


### cargo expand \-\-tests

After this step, running `cargo test` runs our dummy test:

![All tests passed!](/assets/img/2024-07-22-all-tests-passed.png)

Below is the complete expanded code for the `test` module. Simply running `cargo expand` won't work here, since that would expand the code for a normal release build. Adding the `--tests` parameter shows the macro expansion for a test build.

The code becomes quite long because of the expanded print statements, but we can see how the `vm_tests` module has been expanded. It still contains the original `init()` and `test1()` functions, but a main function has been added to it that, if we cut out all the clutter, looks something like this:

{% highlight rust %}
    mod vm_tests {
        #[export_name = "main"]
        unsafe extern "C" fn __defmt_test_entry() -> ! {
            ...
            let mut state = init();
            ...
            {
              ...
              ... print "running `test1`..."
              ...
              check_outcome(test1(), false);
              ...
            }
            ...
            ... print "all tests passed!"
            ...
            crate::avrora::exit()
        }
{% endhighlight %}

As usual the state of the code at the end of this step can be found [here](https://github.com/nielsreijers/capevm-rust/releases/tag/post-5) on Github.

<br>

<br>    

<br>

The complete expansion of the `tests` module:

{% highlight rust %}
#[cfg(test)]
mod tests {
    use crate::avrora;
    #[panic_handler]
    fn panic(_info: &core::panic::PanicInfo) -> ! {
        {
            use avr_progmem::progmem;
            use crate::avrora::print_flash_string_fn;
            static AVRORA_PROGMEMSTRING: ::avr_progmem::string::PmString<
                {
                    let s: &str = "TEST FAILED!\u{0}";
                    s.len()
                },
            > = {
                #[link_section = ".progmem.data"]
                static VALUE: [u8; {
                    let s: &str = "TEST FAILED!\u{0}";
                    s.len()
                }] = ::avr_progmem::wrapper::array_from_str("TEST FAILED!\u{0}");
                let pm = unsafe {
                    ::avr_progmem::wrapper::ProgMem::new(&raw const VALUE)
                };
                unsafe { ::avr_progmem::string::PmString::new(pm) }
            };
            print_flash_string_fn(AVRORA_PROGMEMSTRING);
        };
        avrora::exit();
    }
    #[cfg(test)]
    mod vm_tests {
        #[export_name = "main"]
        unsafe extern "C" fn __defmt_test_entry() -> ! {
            #[used]
            #[no_mangle]
            static DEFMT_TEST_COUNT: usize = {
                let mut counter = 0;
                {
                    counter += 1;
                }
                counter
            };
            #[allow(dead_code)]
            let mut state = init();
            let mut __defmt_test_number: usize = 1;
            {
                {
                    {
                        {
                            use avr_progmem::progmem;
                            use crate::avrora::print_flash_string_fn;
                            static AVRORA_PROGMEMSTRING: ::avr_progmem::string::PmString<
                                {
                                    let s: &str = "running `test1`...\u{0}";
                                    s.len()
                                },
                            > = {
                                #[link_section = ".progmem.data"]
                                static VALUE: [u8; {
                                    let s: &str = "running `test1`...\u{0}";
                                    s.len()
                                }] = ::avr_progmem::wrapper::array_from_str(
                                    "running `test1`...\u{0}",
                                );
                                let pm = unsafe {
                                    ::avr_progmem::wrapper::ProgMem::new(&raw const VALUE)
                                };
                                unsafe { ::avr_progmem::string::PmString::new(pm) }
                            };
                            print_flash_string_fn(AVRORA_PROGMEMSTRING);
                        };
                    };
                };
                check_outcome(test1(), false);
                __defmt_test_number += 1;
            }
            {
                {
                    use avr_progmem::progmem;
                    use crate::avrora::print_flash_string_fn;
                    static AVRORA_PROGMEMSTRING: ::avr_progmem::string::PmString<
                        {
                            let s: &str = "all tests passed!\u{0}";
                            s.len()
                        },
                    > = {
                        #[link_section = ".progmem.data"]
                        static VALUE: [u8; {
                            let s: &str = "all tests passed!\u{0}";
                            s.len()
                        }] = ::avr_progmem::wrapper::array_from_str(
                            "all tests passed!\u{0}",
                        );
                        let pm = unsafe {
                            ::avr_progmem::wrapper::ProgMem::new(&raw const VALUE)
                        };
                        unsafe { ::avr_progmem::string::PmString::new(pm) }
                    };
                    print_flash_string_fn(AVRORA_PROGMEMSTRING);
                };
            };
            crate::avrora::exit()
        }
        use avr_defmt_test::TestOutcome;
        pub fn check_outcome<T: TestOutcome>(outcome: T, should_error: bool) {
            if outcome.is_success() == should_error {
                if should_error {
                    {
                        {
                            use avr_progmem::progmem;
                            use crate::avrora::print_flash_string_fn;
                            static AVRORA_PROGMEMSTRING: ::avr_progmem::string::PmString<
                                {
                                    let s: &str = "`#[should_error]` \u{0}";
                                    s.len()
                                },
                            > = {
                                #[link_section = ".progmem.data"]
                                static VALUE: [u8; {
                                    let s: &str = "`#[should_error]` \u{0}";
                                    s.len()
                                }] = ::avr_progmem::wrapper::array_from_str(
                                    "`#[should_error]` \u{0}",
                                );
                                let pm = unsafe {
                                    ::avr_progmem::wrapper::ProgMem::new(&raw const VALUE)
                                };
                                unsafe { ::avr_progmem::string::PmString::new(pm) }
                            };
                            print_flash_string_fn(AVRORA_PROGMEMSTRING);
                        };
                    };
                }
                {
                    {
                        use avr_progmem::progmem;
                        use crate::avrora::print_flash_string_fn;
                        static AVRORA_PROGMEMSTRING: ::avr_progmem::string::PmString<
                            {
                                let s: &str = "FAILED\u{0}";
                                s.len()
                            },
                        > = {
                            #[link_section = ".progmem.data"]
                            static VALUE: [u8; {
                                let s: &str = "FAILED\u{0}";
                                s.len()
                            }] = ::avr_progmem::wrapper::array_from_str("FAILED\u{0}");
                            let pm = unsafe {
                                ::avr_progmem::wrapper::ProgMem::new(&raw const VALUE)
                            };
                            unsafe { ::avr_progmem::string::PmString::new(pm) }
                        };
                        print_flash_string_fn(AVRORA_PROGMEMSTRING);
                    };
                };
                crate::avrora::exit();
            }
            {
                {
                    use avr_progmem::progmem;
                    use crate::avrora::print_flash_string_fn;
                    static AVRORA_PROGMEMSTRING: ::avr_progmem::string::PmString<
                        {
                            let s: &str = "OK\u{0}";
                            s.len()
                        },
                    > = {
                        #[link_section = ".progmem.data"]
                        static VALUE: [u8; {
                            let s: &str = "OK\u{0}";
                            s.len()
                        }] = ::avr_progmem::wrapper::array_from_str("OK\u{0}");
                        let pm = unsafe {
                            ::avr_progmem::wrapper::ProgMem::new(&raw const VALUE)
                        };
                        unsafe { ::avr_progmem::string::PmString::new(pm) }
                    };
                    print_flash_string_fn(AVRORA_PROGMEMSTRING);
                };
            };
        }
        fn init() {
            crate::init();
        }
        fn test1() {
            match (&1, &1) {
                (left_val, right_val) => {
                    if !(*left_val == *right_val) {
                        let kind = ::core::panicking::AssertKind::Eq;
                        ::core::panicking::assert_failed(
                            kind,
                            &*left_val,
                            &*right_val,
                            ::core::option::Option::None,
                        );
                    }
                }
            };
        }
    }
}
{% endhighlight %}


