---
layout: post
title:  "Code Previews are better than Reviews."
date:   2024-06-30 00:00:00 +0000
categories: blog
tags: [ software_engineering ]
---

A few months ago, I had a job interview with Cloudflare. Unfortunately they couldn't accommodate the fact that I live in Taiwan, but otherwise it went really well, and there's one remark the interviewer made that stuck with me.

It's something I've been excited about trying out for a long time, but so far never got the opportunity for: assigning each task to two developers, from the start.

![Bored developer alone](/assets/img/2024-06-30-bored-developer.jpg)


## Code reviews are broken

Code reviews are an essential part of software development. They're a line of defence against bugs, improve code quality, make sure standards are followed, etc, etc. As a developer, reviewing other people's code is as much a part of your job as writing your own.

But if I'm totally honest, I just don't like it. I'd much rather be writing my own code that reading yours, and I suspect I'm not the only one.

I try my best of course. I spend a serious amount of time trying to understand the code, go through my checklists, etc. But if a big complicated change gets dumped on you, it can be hard to put yourself to it, and you start wondering when you've spent enough time on it to approve without feeling guilty.

This old quote sums it up nicely:

> 10 line pull request: 10 comments
>
> 1000 line pull request: "looks good to me"

Since we spend a serious amount of time on code reviews, it's important to make sure that time is well spent, and I think there's a better way to do it.

But first, let's look at two problems with 'normal' code reviews:



## Code that benefits the most from reviews is often the least in need of them.

It's not always bad. There are a number of people I worked with that I love to get a pull request from. Their code is usually clear, well written and easy to understand, and the review may teach me a thing or two.

What's interesting is that it is much easier to add useful comments when you understand the code and the author's thinking. Usually there are still things that can be improved. An edge case that was missed, some identifier that could be renamed to better convey the code's intention. These things do matter.

This is how the review process should work. It doesn't take a lot of time, knowledge gets shared, and code quality goes up. But this code was already of a high standard.


Unfortunately, sometimes code is messy and you don't really understand what's going on. This is the sort of change that needs reviewing most, but the options available to the reviewer get much less attractive.

- Approve the change because the project is under pressure and there are more urgent things to work on than making this code pretty. Most people will agree this isn't the right way, but many will have seen this happen.

- Send it back saying it's too hard to understand.

- Suggest a different approach that might mean significant rework.

- Sit down with the author and work through it together.

Either way, the result sits somewhere on a spectrum from accepting a less than ideal change, or spending considerable time rewriting it.



## Reviews come too late

Another thing I've noticed is that when a review goes well, they're often from the same developers who tend to communicate about a coming change before sending you the pull request. "Hey, I'm working or this or that. What do you think about these two approaches I'm considering?"

By the time a pull request that needs some work ends up on your screen, someone already spent time writing that code. The change is there, and it probably works and passes all the tests. But it may not be the solution we want.

Assuming the review will improve the quality of the change, wouldn't it have been much more effective if the author had this input before writing the code? Or half way? Or during the whole process?



## Two names per task, from the start

I've had really good experiences with pair programming, but it's overkill for a trivial fix where a simple review will do. For a big complex change that was entirely pair programmed, adding another review by a third, fresh set of eyes can be useful.

How can we match the right level of interaction with each change? I suggest by simply assigning two names to each task, _right from the start_, making it clear they're equally responsible, and letting them figure it out. The pair may go the traditional route, with one coding and the other reviewing. Or they may pair program parts or all of it.

All teams divide work in one way or another. From what I understand about Cloudflare, you're not allowed to start work on a task, unless there are two names, not one, assigned to it. I don't know the details about their process, and I'm sure some corners are cut in practice. That's fine, it's the idea that matters.

When things go well, adding a second name may not make much difference to what happens in practice. It's when things don't go well that I think we can benefit from formalising the fact that two people should be responsible for a change:

- Some developers hestitate to bother a colleague and ask for input. Having a second name on the task lowers the threshold to ask for advice.
- Conversely, if the pair agreed one will do the coding and the other will review, the reviewer will be rightfully upset if they get a big complicated pull request without prior discussion. (_"Shouldn't we have discussed this first?"_) Making it clear who will review the change encourages the developer to keep them in the loop.
- I started this post admitting I really don't enjoy reviewing other people's code. But that completely changes when it's code someone wrote to implement an idea we had a good discussion about. Now it's _our_ code.

That last bit takes some cultural change. It's easy to adopt a rule and just tag an extra name onto each item on the task board, but won't help much if it's still _"Alice's change (reviewed by Bob)"_.

Ideally the review should be a formality. It shouldn't be a long process of first trying to understand what a change does, and then deciding if that's the right way to achieve the goal. It should be final check if what was implemented is really what was discussed and a last check for silly bugs and code consistency.

If it's really a pair effort, _"Alice and Bob's change"_, I think reviews will be more enjoyable, and we can write better code in less time.

![Happy developers pair programming](/assets/img/2024-06-30-happy-developers.png)

