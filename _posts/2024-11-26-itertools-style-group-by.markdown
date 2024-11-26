---
layout: post
title:  "Python itertools style GROUP BY in SQL (with some help from AI)"
date:   2024-11-26 11:20:36 +0800
categories: blog
tags: clickhouse
---

![ClickHouse](/assets/img/2024-11-26-brave-search.png)

When I'm programming, I use AI assistants almost every day to auto complete my sentences or to quickly find answers to questions I know must have been discussed online many times before. But when I ask it to write some non-trivial code, it almost always disappoints.

Until last week, when it suddenly came up with a working solution to a tricky problem.



## The problem

What I wanted was to do a `GROUP BY` in SQL, but in the style of Python's itertools: it should only group consecutive rows with matching keys. 

If the input is:
```
┌─────┬───────┐
│ key │ value │
├─────┼───────┤
│  A  │  1000 │
│  A  │  1001 │
│  B  │  1002 │
│  B  │  1003 │
│  C  │  1004 │
│  C  │  1000 │
│  A  │  1001 │
│  A  │  1002 │
│  B  │  1003 │
└─────┴───────┘
```

the output should be:
```
┌─────┬─────────────┐
│ key │ total_value │
├─────┼─────────────┤
│  A  │     2001    │
│  B  │     2005    │
│  C  │     2004    │
│  A  │     2003    │
│  B  │     1003    │
└─────┴─────────────┘
```

and not:
```
┌─────┬─────────────┐
│ key │ total_value │
├─────┼─────────────┤
│  A  │     4004    │
│  B  │     3008    │
│  C  │     2004    │
└─────┴─────────────┘
```



## The prompt
Somehow I couldn't get the query right, so I decided to enter `sql consecutive group by like itertools` in Brave search, which I've been using instead of Google for a while now, and see what it would come up with.

It told me:
> SQL does not have a direct equivalent to Python’s itertools.groupby() function, which groups consecutive identical elements together. However, you can achieve similar results using window functions.

and it gave this example:

```
WITH ordered AS (
  SELECT created, country, LAG(country) OVER (ORDER BY created DESC) AS previous_country
  FROM checkins
),
grouped AS (
  SELECT country, created,
         COUNT(*) FILTER (WHERE previous_country IS NULL OR previous_country != country) 
                  OVER (ORDER BY created DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS grp
  FROM ordered
)
SELECT country, MIN(created) AS start, MAX(created) AS end,
       CAST(JULIANDAY(MAX(created)) - JULIANDAY(MIN(created)) AS INTEGER) AS days
FROM grouped
GROUP BY country, grp
ORDER BY start DESC;
```

Interesting. Scanning the code I didn't really see what it was trying to do at first, but I was curious to see if it would work.



## Turning this into valid ClickHouse SQL
It only took a few simple steps to turn this into a valid ClickHouse query working on the example input above.
 - replace the `checkins` table with a query producing our synthetic input,
 - replace the `country` and `created` columns with `key` and `index`,
 - replace the `LAG` function with the closest ClickHouse equivalent: `lagInFrame`,
 - replace `days` as the aggregate with the sum of the `value` column and sort the result ascending

```
WITH input AS (
    SELECT number AS index, char(65+((toInt32(number/2))%3)) AS key, 1000+number%5 AS value
    FROM numbers() LIMIT 9
),
ordered AS (
  SELECT index, value, key, lagInFrame(key) OVER (ORDER BY index DESC) AS previous_key
  FROM input
),
grouped AS (
  SELECT key, index, value,
         COUNT() FILTER (WHERE previous_key IS NULL OR previous_key != key)
                 OVER (ORDER BY index DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS grp
  FROM ordered
)
SELECT key, MIN(index) AS start, MAX(index) AS end, SUM(value) AS total_value
FROM grouped
GROUP BY key, grp
ORDER BY start ASC;
```

It is still essentially the same query as what Brave gave me, and to my surprise, it worked perfectly!

You can try it [here](https://fiddle.clickhouse.com/f326f670-b29e-45f3-a26a-261df4545254).

But I found the code very hard to read. The naming isn't very clear, and especially the repeated use of `DESC` ordering makes it hard to see what is going on.


## How does it work?
Let's look at the intermediate results. The `ordered` CTE adds a `lagInFrame(key) OVER (ORDER BY index DESC)` and names the column `previous_key`. But when we sort the output it in ascending order, we see the result is actually the next key:

```
WITH input AS (
    SELECT number AS index, char(65+((toInt32(number/2))%3)) AS key, 1000+number%5 AS value
    FROM numbers() LIMIT 9
),
ordered AS (
  SELECT index, value, key, lagInFrame(key) OVER (ORDER BY index DESC) AS previous_key
  FROM input
)
SELECT *,  FROM ordered ORDER BY index

┌───────┬───────┬─────┬──────────────┐
│ index │ value │ key │ previous_key │
├───────┼───────┼─────┼──────────────┤
│   0   │  1000 │  A  │      A       │
│   1   │  1001 │  A  │      B       │
│   2   │  1002 │  B  │      B       │
│   3   │  1003 │  B  │      C       │
│   4   │  1004 │  C  │      C       │
│   5   │  1000 │  C  │      A       │
│   6   │  1001 │  A  │      A       │
│   7   │  1002 │  A  │      B       │
│   8   │  1003 │  B  │              │
└───────┴───────┴─────┴──────────────┘
```


The `grouped` CTE then adds a `grp` column that counts the number of rows where the key changes, in the window between the current and all _preceding_ rows. But again it is using a descending sort on the input, so this is actually the number of changes in the remaining rows when sorted in ascending order:

```
WITH input AS (
    SELECT number AS index, char(65+((toInt32(number/2))%3)) AS key, 1000+number%5 AS value
    FROM numbers() LIMIT 9
),
ordered AS (
  SELECT index, value, key, lagInFrame(key) OVER (ORDER BY index DESC) AS previous_key
  FROM input
),
grouped AS (
  SELECT key, index, value,
         COUNT() FILTER (WHERE previous_key IS NULL OR previous_key != key)
                 OVER (ORDER BY index DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS grp
  FROM ordered
)
SELECT * FROM grouped ORDER BY index

┌─────┬───────┬───────┬─────┐
│ key │ index │ value │ grp │
├─────┼───────┼───────┼─────┤
│  A  │   0   │  1000 │  5  │
│  A  │   1   │  1001 │  5  │
│  B  │   2   │  1002 │  4  │
│  B  │   3   │  1003 │  4  │
│  C  │   4   │  1004 │  3  │
│  C  │   5   │  1000 │  3  │
│  A  │   6   │  1001 │  2  │
│  A  │   7   │  1002 │  2  │
│  B  │   8   │  1003 │  1  │
└─────┴───────┴───────┴─────┘
```

With this we can do a `GROUP BY grp` to get the desired result, since non-consecutive rows with the same key get different `grp` numbers.

## A small bug

But there's a small issue with this query: the `previous_key IS NULL` clause. It appears this is meant to handle last row that has no `previous_key` (or rather next key) and gets the default value.

This will fail if that default value is also a legal key value that appears in consecutive rows, since each row would then start a new group. We can test this in the example query by making `B` the default value: `lagInFrame(key, 1, 'B')` and changing the filter accordingly, which produces three groups for `B` instead of two.

The solution to this is simple: it is not necessary to check for this special case because it only occurs in the last row, which is always included in the `COUNT()` function's window. So whether it counts as a 0 or 1 determines whether the group numbers are 0 or 1 based, but does not affect the grouping itself.

We can safely remove the `previous_key IS NULL` clause to get:

```
WITH input AS (
    SELECT number AS index, char(65+((toInt32(number/2))%3)) AS key, 1000+number%5 AS value
    FROM numbers() LIMIT 9
),
ordered AS (
  SELECT index, value, key, lagInFrame(key) OVER (ORDER BY index DESC) AS previous_key
  FROM input
),
grouped AS (
  SELECT key, index, value,
         COUNT() FILTER (WHERE previous_key != key)
                 OVER (ORDER BY index DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS grp
  FROM ordered
)
SELECT key, MIN(index) AS start, MAX(index) AS end, SUM(value) AS total_value
FROM grouped
GROUP BY key, grp
ORDER BY start ASC;
```

From this query it is still not trivial to see that this is the case, so let's refactor it.


## Refactoring
We can remove the DESC orderings to make the query easier to read:
- `ORDER BY index DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` is equivalent to `ORDER BY index ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING`,
- and `lagInFrame(key) OVER (ORDER BY index DESC)` is equivalent to `leadInFrame(key) OVER ()`, and should be called next_key:

```
WITH input AS (
    SELECT number AS index, char(65+((toInt32(number/2))%3)) AS key, 1000+number%5 AS value
    FROM numbers() LIMIT 9
),
ordered AS (
  SELECT index, value, key, leadInFrame(key) OVER () AS next_key
  FROM input
),
grouped AS (
  SELECT key, index, value,
         COUNT() FILTER (WHERE next_key != key)
                 OVER (ORDER BY index ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS grp
  FROM ordered
)
SELECT key, MIN(index) AS start, SUM(value) AS total_value, grp
FROM grouped
GROUP BY key, grp
ORDER BY start ASC;
```

This is getting easier to read. It sets `grp` to the number of records between the current record and the end of the result set, where next_key is unequal to key. These records mark the end of a block with identical key values.

I still find the look ahead to be adding mental load, since in my mind I scan the table top to bottom. So instead of counting group endings until the end, we can count groups starts since the beginning instead. This also has the advantage that groups will be numbered in ascending order:
- replace `leadInFrame(key) OVER () AS next_key` with `lagInFrame(key) OVER () as previous_key` (this time it's really the previous key) to find the key change at the beginning of groups,
- and replace `ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING` with `ORDER BY index ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` to count these up to and including the current row:

```
WITH input AS (
    SELECT number AS index, char(65+((toInt32(number/2))%3)) AS key, 1000+number%5 AS value
    FROM numbers() LIMIT 9
),
ordered AS (
  SELECT index, value, key, lagInFrame(key) OVER () as previous_key
  FROM input
),
grouped AS (
  SELECT key, index, value,
         COUNT() FILTER (WHERE previous_key != key)
                 OVER (ORDER BY index ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS grp
  FROM ordered
)
SELECT key, MIN(index) AS start, SUM(value) AS total_value, grp
FROM grouped
GROUP BY key, grp
ORDER BY start ASC;
```

It should now be more clear that the only case where `lagInFrame(key)` would produce a default value is for the first record, and since this is always included in the range, it doesn't matter whether it's counted or not.

Using `lagInFrame` also has the added advantage of avoiding [this potential gotcha](https://github.com/ClickHouse/ClickHouse/issues/72354) in the `leadInFrame` function. It's all documented, but sometimes ClickHouse does some pretty counter unintuitive things.

One more refactoring to explicitly mark the start of each group with a 1, and sum up the number of group starts up until the current record gives this final result:

```
WITH input AS (
    SELECT number AS index, char(65+((toInt32(number/2))%3)) AS key, 1000+number%5 AS value FROM numbers() LIMIT 9
),
mark_start_of_groups AS (
  SELECT index, value, key, IF (key != lagInFrame(key) OVER (), 1, 0) AS start_of_group
  FROM input
),
numbered_groups AS (
  SELECT key, index, value,
         SUM(start_of_group) OVER (ORDER BY index ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
            AS group_number
  FROM mark_start_of_groups
)
SELECT key, group_number, SUM(value) AS total_value
FROM numbered_groups
GROUP BY key, group_number
ORDER BY group_number;
```

The intermediate results in `numbered_groups` now look like this:
```
┌─────┬───────┬───────┬────────────────┬─────┐
│ key │ index │ value │ start_of_group │ grp │
├─────┼───────┼───────┼────────────────┼─────┤
│  A  │   0   │  1000 │       1        │  1  │
│  A  │   1   │  1001 │       0        │  1  │
│  B  │   2   │  1002 │       1        │  2  │
│  B  │   3   │  1003 │       0        │  2  │
│  C  │   4   │  1004 │       1        │  3  │
│  C  │   5   │  1000 │       0        │  3  │
│  A  │   6   │  1001 │       1        │  4  │
│  A  │   7   │  1002 │       0        │  4  │
│  B  │   8   │  1003 │       1        │  5  │
└─────┴───────┴───────┴────────────────┴─────┘
```

And the final result is still correct:
```
┌─────┬──────────────┬─────────────┐
│ key │ group_number │ total_value │
├─────┼──────────────┼─────────────┤
│  A  │      1       │     2001    │
│  B  │      2       │     2005    │
│  C  │      3       │     2004    │
│  A  │      4       │     2003    │
│  B  │      5       │     1003    │
└─────┴──────────────┴─────────────┘
```


It's still not a trivial query, but much better than what we started with.

What surprised me most was that the solution Brave gave me was correct, but very difficult to read. Any human developer would come up with a much easier solution, which makes it hard to believe it was just echoing some online example it was trained on, so I'm really curious how it got to this result.

It doesn't take more than a few descending sorts and poorly labelled columns to confuse a human reader. I made a few mistakes even when refactoring the working code I started with.

But somehow Brave managed to successfully avoid all the easy to make mistakes and produce working code. Or maybe it just got lucky.
