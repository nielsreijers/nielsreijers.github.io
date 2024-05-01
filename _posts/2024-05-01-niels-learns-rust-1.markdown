---
layout: post
title:  "Niels learns Rust 1 — Why Rust?"
date:   2024-05-01 11:18:36 +0800
categories: jekyll update
---

I love learning new programming languages. A while ago, I made a list of all the languages I ever worked with, and got to 33. BBC Basic was my first, Scala the most recent addition.

In this series of posts I plan to describe my journey to add number 34: Rust.


# Why learn yet another new language?

The more languages you know, the easier it becomes to pick up a new one. Patterns start repeating and improvements get more incremental. Getting the hang of functional programming takes a bit longer, but if you already know Haskell, Scala will be easier to pick up and vice versa.

There is simply just a limited set of concepts. Each language picks a different subset and makes slightly different tradeoffs.

But besides opening up job opportunities, I still find I always learn something new from picking up a new language. It may have some unique features: Scala's `implicits` were new to me. Or the community may take a slightly different approach to common problems: we can learn a lot from Golang's concious choice not to support many features for the sake of simplicity.

Even if you never use a language in practice, knowing what's out there makes you a better developer.


# Why Rust?

So why learn Rust?

Because it does something fundamentally different from all the other languages I've worked with. It gives us a brand new approach to one of the oldest problems in programming: memory management. Rust's approach requires a new way to think about your code, the subtleties of which will take much longer to master than Golang or Scala. And that's what makes it interesting to me: an opportunity to learn and improve as a developer.

C and C++ are hard because they force you to manually manage your memory, with all the risks that come with it. This is error prone and lead to crashes and security vulnerabilities, but luckily we have a pretty good solution: garbage collection.

For most problems, the small performance price we pay for it is an easy choice, but there are cases where we can't use garbage collection. For these, Rust now offer a great alternative, where we neither need to `free()` memory ourselves, or depend on a garbage collector.

Besides this practical advantage of Rust, I'm also very curious to see how learning it will influence the way I design my code. Rust depends on very strict rules to ensure memory safety, and so requires more up front design. The promise is that this will lead to better code.


# Rust's approach to memory management

You can argue about whether Rust's approach is really a new, third, solution to this problem. Rust doesn't rely on a garbage collector and still automatically frees up memory for you, which at first made me think it was.

But having studied it for a bit longer I now prefer to think of it as another form of manual memory management. One that's verified by the compiler, so any mistake you make is now a compile time error rather than a runtime crash or security vulnerability.

Yes, Rust automatically will free the memory for you, but the fundamental problem isn't deciding when to free memory. The problem is clearly defining who *owns* a piece of data. Rust makes ownership and borrowing very explicit. You should have been thinking about this in your C or C++ code anyway, and in Rust the compiler forces you to do so.

Once you've structured your code in a way that conforms to Rust's ownership rules, freeing up memory becomes trivial: a value can be freed (dropped in Rust terms), every time the variable that owns it goes out of scope, or gets assigned a new value.

The key point to understand is that Rust can do this, because the ownership rules ensure there is always only one owner of a value, and no borrows (references) of a value will outlive the value itself.

This little example:

```
#[derive(Debug)]
struct Foo {
    data: u32,
}

impl Drop for Foo {
    fn drop(&mut self) {
        println!("Dropped {}.", self.data);
    }
}

fn main() {
    let a = Foo { data: 42 };
    let mut b = Foo { data: 43 };
    println!("a: {:?}", a);
    println!("b: {:?}", b);
    b = a;
    println!("b: {:?}", b);
}
```

will print:

```
a: Foo { data: 42 }
b: Foo { data: 43 }
Dropped 43.
b: Foo { data: 42 }
Dropped 42.
```

The original value in `b`, `Foo { data: 43 }` is dropped at the `b = a;` line because it lost its owner. At the same time the *variable* `a` becomes unusable because the *value* `Foo { data: 42 }` has been moved to `b`. This value is now owned by `b`, and it is dropped at the end of the `main` function, when `b` goes out of scope.

Try it on the Rust [playground](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&code=%23%5Bderive%28Debug%29%5D%0Astruct+Foo+%7B%0A++++data%3A+u32%2C%0A%7D%0A%0Aimpl+Drop+for+Foo+%7B%0A++++fn+drop%28%26mut+self%29+%7B%0A++++++++println%21%28%22Dropped+%7B%7D.%22%2C+self.data%29%3B%0A++++%7D%0A%7D%0A%0Afn+main%28%29+%7B%0A++++let+a+%3D+Foo+%7B+data%3A+42+%7D%3B%0A++++let+mut+b+%3D+Foo+%7B+data%3A+43+%7D%3B%0A++++println%21%28%22a%3A+%7B%3A%3F%7D%22%2C+a%29%3B%0A++++println%21%28%22b%3A+%7B%3A%3F%7D%22%2C+b%29%3B%0A++++b+%3D+a%3B%0A++++println%21%28%22b%3A+%7B%3A%3F%7D%22%2C+b%29%3B%0A%7D%0A%0A).


# That sounds rather restrictive

Of course there are many perfectly correct C programs that don't conform to Rust's strict ownership rules. The rules *are* limiting, but we know many examples where imposing limits on our code eventually leads to better designs.

There is a good reason we don't like to use goto anymore, why we don't make all class members public, why support for immutable data is getting more common, and why Golang limits itself to a minimalist set of features.

We impose these limits on ourselves because we believe it leads to better code in the long run, and Rust's ownership restrictions are no different.

I'm only just starting to learn Rust, so I have no gut feeling for how limiting it will be in practice, but I suspect after while thinking about ownership becomes second nature, and hopefully, code that mixes it up will start to feel a bit messy. If that's the case, learning Rust will have made me a better developer in any language.


# The project

So, I want to learn Rust. I picked up [Programming Rust, 2nd Edition](https://www.oreilly.com/library/view/programming-rust-2nd/9781492052586/), which is excellent. It's pretty dense at times (which I like), but it all makes sense to me when I read it. I did a bunch of the exercises, which aren't too hard, but did I really *get* it? I didn't feel I did.

To really learn a big language with new patterns like Rust, you have to do a project in it. Using it is the only way to really learn.

So I decided that porting my PhD work to Rust would be a good exercise. It's a Java virtual machine for resource constrained embedded CPUs that uses Ahead-of-Time compilation. If you're interested in the details, here's my [thesis](https://tdr.lib.ntu.edu.tw/handle/123456789/1247), but for now it's enough to know it's a JVM developed for tiny devices with about 4KB RAM, and that it compiles the JVM bytecode to native code to improve performance.

Several things make this an interesting case study for Rust:
 - A virtual machine is a good usecase for a systems language. We can't use garbage collection, because we're building it ourselves.
 - It's *very* low level. Compiling the JVM bytecode to native code means a lot of binary manipulation of memory and instructions, making sure every byte is in the right place.
 - On such a restricted device, every byte counts. A byte spent on the VM can't be spent on the application, so if it saves some memory, we prefer dirty tricks over nice abstractions.
 - These devices have a Harvard architecture. I'm curious to see how Rust handles this.
 - There was at least one bug when I was developing this VM in C, that cost me two days to hunt down and turned out to be a write to a null pointer at a point much earlier than where the problem surfaced. This is exactly what Rust promises to prevent.


I have no idea how long this project is going to take, but I expect I will learn a lot from it. I'm particularly curious to what extent I can stay within Rust's safety guarantees, and where I'll have to resort to `unsafe {}` code. This seems much more acceptable in Rust than in langauges like C#, but of course it should still be avoided where possible.

I'll keep writing new posts as the project progresses, documenting the things I've learned!

