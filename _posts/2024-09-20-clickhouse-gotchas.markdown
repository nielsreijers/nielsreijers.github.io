---
layout: post
title:  "ClickHouse Gotchas"
date:   2024-09-20 11:18:36 +0800
categories: blog
tags: clickhouse
---

![ClickHouse](/assets/img/2024-09-20-clickhouse.jpg)

I recently started using ClickHouse. It's a beautiful tool. For the right workloads, it's incredibly fast. "How on earth does it do that??"-fast.

It's optimised for a very specific kind of workload: ingesting huge amounts of data as fast as possible, analyse it, and after a while either aggregate it or throw it away. It's very good at handling timestamped data, and very wide tables where we use only a few columns in each query. Ingesting log file, for example from a web server, is one of the usecases where it shines.

Of course that speed doesn't come for free, otherwise every other database would be doing the same this. ClickHouse speaks (a subset of) ANSI SQL, but it's not a database. It's terrible at updating and selectively deleting data, doesn't have a concept of foreign keys, it takes some liberties with consistency and has a number of design choices that seem confusing at first.

A 'normal' relational database gives you a predictable and coherent framework within which to work, but ClickHouse is more like a set of tools you can combine in ways that may or may not work well together.

It achieves it's incredible performance in several ways.
- Data is spread over several files: columns in wide tables are split into separate files, so we don't need to access colums we're not using in a query.
- Data is partitioned according to some key (usually date/time), so we also don't need to access rows outside of the partition we're interested in, and deleting old partitions is cheap.
- Data within a partition is also split into 'parts': ClickHouse doesn't like updates or deletes, but it's great at accepting inserts at an incredible speed because it can just keep appending data concurrently to different parts.
- Background processing then combines these parts, depending on the type of table. For some this merge will replace old versions of a record with the latest insert. Others may sum up columns, or aggregate data with one of the wide collection of statistical functions available.
- Until that merge has happend, it's normal to see multiple records with the same primary key, and it's up to the user to handle this situation, or force ClickHouse to finalise the results.

All these choices make a lot of sense if you keep in mind the goal is to ingest and analyse as much data as possible. For example, if the system is under heavy load, it may decide not to waste resources aggregating data until the user asks for it, and some parts may never get merged.

These design choices and flexibility can also be confusing, and as a ClickHouse beginner I've cut myself several times. I decided to collect all the gotchas I fell for in this [Github repository](https://github.com/nielsreijers/clickhouse-gotchas).

![ClickHouse](/assets/img/2024-09-20-gotcha.jpg)

If you're also getting started with ClickHouse it may save you some time, or help understand the system better. Or it may just be entertaining reading. I'm certainly enjoying the process of getting to know this tool.
