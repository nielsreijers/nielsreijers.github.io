---
layout: post
title:  "Niels learns Rust 4 — Three different ways make the VM modular"
date:   2024-05-23 00:00:00 +0000
categories: blog
tags: rust
---

*This is part 4 in my journey to learn Rust by porting my embedded Java virtual machine to it.
Click [here](/blog/tag/rust) for the whole series.*

The original version of the VM was a modified version of the [Darjeeling virtual machine](https://darjeeling.sourceforge.net/files/msc_thesis_niels_brouwers_2009.pdf). It was setup in a very modular way, and can be easily compiled with different sets of components enabled.

These components offer various sorts of functionality such as wireless reprogramming, access to the device UART, the Java base library, etc. The [research project](https://newslabntu.github.io/wukong4iox/) it was used in was on orchestrating networks of heterogeneous Internet-of-Things devices. For this project it made sense to make even the Java virtual machine itself an optional component, so that we could build a version for the smallest devices that couldn't execute Java code but still participate in the network.


## Project layout

So before we start building the VM, let's setup the project layout first. The goal is to have components that can be optionally included when the VM is built, based on some configuration option. Each component should be able to register callbacks for a number hooks exposed by the core VM to initialise the component, allow it to interact with the garbage collector, to receive network messages, etc. At this stage we will only define one hook: `init()`, which will be called on startup.

To illustrate the different options, let's start with two components:
 - `jvm` will contain the actual Java virtual machine
 - `uart` will contain code to control the CPU's UART (universal asynchronous receiver / transmitter)

The project layout will look like this:
```
.
├── avrora.rs
├── main.rs
└── components
    ├── mod.rs
    ├── jvm
    │   └── mod.rs
    └── uart
        └── mod.rs

4 directories, 5 files
```

Rust uses modules to scope things hierarchically, which can be defined in three ways: 
 - a `mod modname { ... }` block,
 - a `modname.rs` file, so our project has a module named `avrora`,
 - and a subdirectory with a `mod.rs`, which defines a module named after the subdirectory. Here we have `components`, `components::jvm`, and `components::uart`.

Compilation starts with `main.rs`, or `lib.rs` for libraries. Modules in a different file or directory must be explicitly included in the project, otherwise they are simply ignored. In this case the lines `mod avrora;` and `mod components;` import the `avrora` and `components` modules, which are then available throughout the crate.

The goal is to optionally include `components::uart` and `components::vm`, depending on whether they are enabled according to some config setting, and to call their `init()` functions if they are.

I considered three ways to do this, that each taught me some interesting Rust features, so let's explore all three:


## Option A: build.rs

Cargo has the option to [run a Rust script](https://doc.rust-lang.org/cargo/reference/build-scripts.html), just before the code is built. The script has to be called `build.rs` and placed in the project's root directory.

We can use this to generate the code required to import the selected components. We will store the setting controlling which components are enabled in a separate config file, `vm-config.toml`, also in the project's root:

{% highlight toml %}
[capevm]
components = [ "jvm" ]
{% endhighlight %}

In this example, we've enabled the jvm, but not the uart component. Our build script should then produce a file containing the following code:

{% highlight rust %}
#[path = "/home/niels/git/capevm-rust/capevm/src/components/jvm/mod.rs"]
mod jvm;

pub fn init() {
    jvm::init();
}
{% endhighlight %}

Since Rust ignores code that isn't explicitly imported in the project, only the jvm module will be included in the final build, and the uart module will be skipped.

The generated code is just a temporary file that shouldn't be under source control, so we will generate it in Cargo's output directory and include it from `components/mod.rs`, which now contains just a single line:

{% highlight rust %}
include!(concat!(env!("OUT_DIR"), "/enabled_components.rs"));
{% endhighlight %}

The `#[path]` attribute in the generated code is necessary because module imports are relative to the location of the file doing the import, but the the `include!` macro in Rust works differently from the `#include` preprocessor directive in C. The included code is not simply pasted into a file, but parsed according to it's source location, which in this case is the Cargo output directory. Without the `#[path]` attribute telling Rust the component is in a different location, we would get the error below:

![Module not found](/assets/img/2024-05-23-module-not-found.png)

The complete build script looks like this:

{% highlight rust %}
{% raw %}
extern crate toml;

use std::fs;
use std::path::Path;
use toml::Value;

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=vm-config.toml");

    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    let out_dir = std::env::var("OUT_DIR").unwrap();
    let dest_path = Path::new(&out_dir).join("enabled_components.rs");

    let contents: String = fs::read_to_string("vm-config.toml").unwrap();
    let cargo_toml = contents.parse::<Value>().unwrap();

    let vm_components =
        if let Some(capevm_components) = cargo_toml.get("capevm")
                                        .and_then(Value::as_table)
                                        .and_then(|table| table.get("components"))
                                        .and_then(Value::as_array) {
            capevm_components.iter().filter_map(|v| v.as_str()).collect::<Vec<&str>>()
        } else {
            Vec::<&str>::default()
        };

    let mod_imports =
        vm_components.iter()
            .map(|name| format!(r#"
                #[path = "{manifest_dir}/src/components/{name}/mod.rs"]
                mod {name};"#, manifest_dir=manifest_dir, name=name))
            .collect::<Vec<_>>().join("\n");
    let mod_inits =
        vm_components.iter()
            .map(|name| format!("
                {}::init();", name))
            .collect::<Vec<_>>().join("\n");

    let generated_code =
        format!("{}
            
            pub fn init() {{
                {}
            }}", mod_imports, mod_inits);

    fs::write(dest_path, generated_code.as_bytes()).unwrap();
}
{% endraw %}
{% endhighlight %}

There are a few things to notice:

- `extern crate toml;` Just like the main application, the `build.rs` script can use external crates. They have to be declared in `Cargo.toml` as any other crate, but in a section called `[build-dependencies]` instead of `[dependencies]`.

- `println!("cargo:rerun-if-changed=...");` We can control [when Cargo runs the build script](https://doc.rust-lang.org/cargo/reference/build-scripts.html#change-detection) (and several other things) by writing to standard output. Here, these two lines tell Cargo to rerun the build script if either `build.rs` or `vm-config.toml` change.

- `std::env::var("CARGO_MANIFEST_DIR")`: Cargo exposes several parameters of the build process to the script through environment variables. In this case we use `OUT_DIR` to determine where the generated file should go, and `CARGO_MANIFEST_DIR` to know the location of the components.

- `unwrap()`: Rust's main way of error handling is by returning a `Result<T, E>`. This may contain either a `T` value or an `E` error. Normally we should handle an error, or pass it on using the [`?` operator](https://doc.rust-lang.org/rust-by-example/std/result/question_mark.html), but if we're sure no error can occur or don't mind the code panic if it did, `unwrap` will get the value out of the `Result`.

- `.and_then()`: The toml crate gave us a `Value` object to represent the contents of the toml file that can be searched by name. This returns an `Option<&Value>`, which can be `None` if the name isn't found. The `.and_then()` call allows us to string operations on Options if it contains a value, or keep `None` if it doesn't. It's sometimes called flatmap or bind in other languages.



## Option B: Cargo features

A second option is using Rust [features](https://doc.rust-lang.org/cargo/reference/features.html). This is much simpler, but it also has some downsides. We first declare a `[features]` section in `Cargo.toml` as follows:

{% highlight rust %}
[features]
default = ["jvm"]
jvm = []
uart = []
{% endhighlight %}

Each feature is simply a name with a list of dependencies. The `default` feature is included by default, together with any dependencies, recursively. In this example `default` depends on `jvm`, so this feature will be enabled, but `uart` will not be.

The named features can then be used in conditional compilation using the `#[cfg(feature = "...")]` attribute. Using this, we can implement `components/mod.rs` as follows:

{% highlight rust %}
#[cfg(feature = "jvm")]
mod jvm;
#[cfg(feature = "uart")]
mod uart;

pub fn init() {
    #[cfg(feature = "jvm")]
    jvm::init();
    #[cfg(feature = "uart")]
    uart::init();
}
{% endhighlight %}

The advantage of this approach is that it's much simpler than the build script. Also, we can control the selected features from the commandline: `--features="uart"` enables the uart feature, and `--no-default-features` overrides the `default` feature.

A disadvantage is that we need to manually list all the components in `components/mod.rs` to import them if their feature is enabled. In addition, we currently only have the `init()` function that should be called for all enabled features, but this list of possible hooks will grow when we add things like garbage collection and networking as some components may want to listen for incoming messages or register their own objects on the heap.

It's quite a hard coupling, and if the number of modules and/or hooks continues to grow, this approach could become hard to maintain.


## Option C: features + the inventory crate

Which brings us to option C: the `inventory` crate. This gives us a way to reduce this tight coupling between the components and core VM. Unfortunately, it doesn't work on the AVR, but it's still interesting to learn about.

The crate allows us to define some datatype, register instances of it from one part of the code, and collect them in another. In our case, the datatype could simply be a struct containing a function pointer to `init()`:

{% highlight rust %}
pub struct Component {
    init: fn()
}
{% endhighlight %}

The implementation of a component now looks like this:

{% highlight rust %}
pub fn init() {
    println!("jvm initialising...");
}

inventory::submit! {
    crate::components::Component{ init }
}
{% endhighlight %}


And the implementation of `components/mod.rs` becomes:

{% highlight rust %}
#[cfg(feature = "jvm")]
mod jvm;
#[cfg(feature = "uart")]
mod uart;

pub struct Component {
    init: fn()
}

inventory::collect!(Component);

pub fn init() {
    for component in inventory::iter::<Component> {
        (component.init)();
    }
}
{% endhighlight %}

The `collect!` macro creates an iterator we can use to loop over all the `Component` objects that were registered through `submit!()`. This iterator is initialised before we enter the `main()` function and without having to run any initialisation code ourselves.

The magic that makes this work is in the `submit!` macro. It can sometimes be useful (or just interesting) to see what a macro expands to. We can do with a Cargo extension called cargo-expand. After installing it (`cargo install cargo-expand`) we can show the expanded source with `cargo expand components::jvm`:

![cargo expand](/assets/img/2024-05-23-cargo-expand.png)

The magic happens by placing some code in specific linked sections. Looking at the source of the inventory crate (which is pretty dense, but under 500 lines, half of which are comments), we see that the linker sections that will be generated depend on the operating system. `.init_array` on Linux, would be `.CRT$XCU` on Windows and `__DATA,__mod_init_func` on macOS. Each of these contain code that will be run before entering the `main()` function.

On the AVR, this kind of code goes into an [`.initN` section](https://onlinedocs.microchip.com/pr/GUID-317042D4-BCCE-4065-BB05-AC4312DBC2C4-en-US-2/index.html?GUID-34931843-0F2B-49EE-A117-7AB61373F68D), but unfortunately the inventory crate doesn't work on the AVR:

![Inventory crate build error](/assets/img/2024-05-23-inventory-crate-build-error.png)

The error is a bit cryptic, especially the `the item is gated behind the 'ptr' feature` part. The crate uses a type called `core::sync::atomic::AtomicPtr`, which is unavailable for some reason. When we have a look at the implementation of this type, it turns out it has a conditional compilation attribute that says `#[cfg(target_has_atomic_load_store = "ptr")]`, which is only set [if the platform supports atomic pointer operations](https://users.rust-lang.org/t/which-platforms-support-atomic-operations-on-usize/62740).

The AVR doesn't. It's an 8-bit CPU and its pointers are 16 bit, so manipulating pointers always takes multiple reads or writes.


## Comparison and decision

We could probably recreate what the inventory crate does by just copying part of the code and modifying it to remove the need for `AtomicPtr`. But there's another reason why it's ultimately not the best choice here.

It works by creating a linked list of static `inventory::Node` objects that the iterator can loop over. This means it's using RAM, and even at only 4 bytes per object, on a device with only 4 KB RAM, we would prefer not to waste it on a static list that never changes.

So this leaves options A and B. Option A feels a bit more decoupled since the core vm code doesn't need to know about the components, whereas in option B requires us to register each component with a corresponding feature flag.

A downside for option A is that each component needs to define an implementation for `init()`, even if there's nothing to initialise, since the build script will always generate a call to it. The Rust compiler is quite good at removing dead code, so these will most likely be eliminated at compile time, but each time we add a similar hook later, which we will do for the garbage collector, each component needs to provide at least an empty implementation.

Since both the number of components and hooks will be limited, both options should work well. Option A has more moving parts, and less magic is always a good thing, I'll go ahead with option B for now.

As usual, the state of the code at the end of this step can be found on Github. I've uploaded all three options:
 - [Option A: build.rs](https://github.com/nielsreijers/capevm-rust/releases/tag/post-4-a)
 - [Option B: features](https://github.com/nielsreijers/capevm-rust/releases/tag/post-4-b)
 - [Option C: features + inventory](https://github.com/nielsreijers/capevm-rust/releases/tag/post-4-c) (doesn't compile on AVR)
 - [A minimal example of option C that works on the desktop](https://github.com/nielsreijers/rust-inventory-example).
