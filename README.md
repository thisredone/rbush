## This fork

- support for fast updates and removals
- predicate function for `all`, `search`, and `raycast`
- `{ minXm, minYm, maxXm, maxY }` changed to `bbox: [minXm, minYm, maxXm, maxY]`
- ray casting with stack-based, ordered ray traversal algorithm from [this paper](https://www.scitepress.org/Papers/2015/53048/53048.pdf)
- finding collisions with the help of box-intersect for cross-leaf overlaps
- polling aggressively to avoid pressuring GC



#### Install

```bash
npm install rbush-full
```



#### Exports

```javascript
const { RBush, boxIntersect, rayBboxDistance, GrowingArray, GrowingArrayPool, ObjectStorage } = require('rbush-full/rbush.js')
```



#### Data format

```coffeescript
item =
  bbox: [0, 0, 1, 1]
  isStatic: false # static-to-static collisions aren't reported
  ...whateverYouWant
```



#### Results

`all()`, `search()` and `checkCollisions()` functions return a `GrowingArray` which implements an iterator.

```javascript
for(let item of tree.search([0, 0, 1, 1])) {
	// do something
}
```

For maximum performance though you need to iterate manually:

```coffeescript
result = tree.search([0, 0, 1, 1])
{ currentLen, current } = result
for i in [0...currentLen]
  item = current[i]
```



#### Update

After changing item `bbox` issue `tree.update(item)`



#### Ray casting

```coffee
origin = { x: 0, y: 0 }
dir = { x: 1, y: 0 } # normalized

response = tree.raycast origin, dir, range = Infinity, predicate
```

Raycast response is reusing the same object so the result must be consumed immediately

```coffeescript
raycastResponse = { dist: Infinity, item: null }
```



#### Checking collisions

Results are packed into a `GrowingArray` in a way that each two items correspond to one collision event

```coffeescript
result = @tree.checkCollisions()
{ currentLen, current } = result
for i in [0...currentLen] by 2
  o1 = current[i]
  o2 = current[i + 1]
```



#### ObjectStorage

This is the underlying structure that holds `tree.nonStatic` objects as well as `tree.leafNodes`. The purpose of it is to be able to store objects that change a lot in an array without paying much of the GC and CPU cost but using more memory. By calling  `storage.remove(item)` objects are marked as `_removed` which makes them ignored in further iteration.

Periodically calling `storage.maybeCondense(threshold)` or directly `storage.condense()`, for example if `storage.removalCount` is higher than some value, migrates the not `_removed` objects to an auxiliary array and swaps them afterwards. For `tree.nonStatic` objects a version of this process is integrated into `tree.checkCollisions()`. Since all are iterated anyway the cost of condensing is minimal.

###### API

```coffeescript
storage = new ObjectStorage(startingSize = 64)

storage.push(item)

item = storage.pop()

storage.clear()

# calls .condense() if .removalsCount > threshold
# by default threshold is the bigger of 50 or 10% of .currentLen
storaget.maybeCondense(threshold)

# get's rid of holes created by removing items
storage.condense()

# iteration with a iterator (in JS it's `in` instead of `from`)
for item from storage
  # do stuff

# manual iteration
{ current, currentLen } = storage
for i in [0...currentLen]
  item = current[i]
  if not item._removed
    # do stuff
```





Original readme below
------------


RBush
=====

RBush is a high-performance JavaScript library for 2D **spatial indexing** of points and rectangles.
It's based on an optimized **R-tree** data structure with **bulk insertion** support.

*Spatial index* is a special data structure for points and rectangles
that allows you to perform queries like "all items within this bounding box" very efficiently
(e.g. hundreds of times faster than looping over all items).
It's most commonly used in maps and data visualizations.

[![Build Status](https://github.com/mourner/rbush/workflows/Node/badge.svg?branch=master)](https://github.com/mourner/rbush/actions)
[![](https://img.shields.io/badge/simply-awesome-brightgreen.svg)](https://github.com/mourner/projects)

## Demos

The demos contain visualization of trees generated from 50k bulk-loaded random points.
Open web console to see benchmarks;
click on buttons to insert or remove items;
click to perform search under the cursor.

* [randomly clustered data](http://mourner.github.io/rbush/viz/viz-cluster.html)
* [uniformly distributed random data](http://mourner.github.io/rbush/viz/viz-uniform.html)

## Install

Install with NPM (`npm install rbush`), or use CDN links for browsers:
[rbush.js](https://unpkg.com/rbush@2.0.1/rbush.js),
[rbush.min.js](https://unpkg.com/rbush@2.0.1/rbush.min.js)

## Usage

### Importing RBush

```js
// as a ES module
import RBush from 'rbush';

// as a CommonJS module
const RBush = require('rbush');
```

### Creating a Tree

```js
const tree = new RBush();
```

An optional argument to `RBush` defines the maximum number of entries in a tree node.
`9` (used by default) is a reasonable choice for most applications.
Higher value means faster insertion and slower search, and vice versa.

```js
const tree = new RBush(16);
```

### Adding Data

Insert an item:

```js
const item = {
    minX: 20,
    minY: 40,
    maxX: 30,
    maxY: 50,
    foo: 'bar'
};
tree.insert(item);
```

### Removing Data

Remove a previously inserted item:

```js
tree.remove(item);
```

By default, RBush removes objects by reference.
However, you can pass a custom `equals` function to compare by value for removal,
which is useful when you only have a copy of the object you need removed (e.g. loaded from server):

```js
tree.remove(itemCopy, (a, b) => {
    return a.id === b.id;
});
```

Remove all items:

```js
tree.clear();
```

### Data Format

By default, RBush assumes the format of data points to be an object
with `minX`, `minY`, `maxX` and `maxY` properties.
You can customize this by overriding `toBBox`, `compareMinX` and `compareMinY` methods like this:

```js
class MyRBush extends RBush {
    toBBox([x, y]) { return {minX: x, minY: y, maxX: x, maxY: y}; }
    compareMinX(a, b) { return a.x - b.x; }
    compareMinY(a, b) { return a.y - b.y; }
}
const tree = new MyRBush();
tree.insert([20, 50]); // accepts [x, y] points
```

If you're indexing a static list of points (you don't need to add/remove points after indexing), you should use [kdbush](https://github.com/mourner/kdbush) which performs point indexing 5-8x faster than RBush.

### Bulk-Inserting Data

Bulk-insert the given data into the tree:

```js
tree.load([item1, item2, ...]);
```

Bulk insertion is usually ~2-3 times faster than inserting items one by one.
After bulk loading (bulk insertion into an empty tree),
subsequent query performance is also ~20-30% better.

Note that when you do bulk insertion into an existing tree,
it bulk-loads the given data into a separate tree
and inserts the smaller tree into the larger tree.
This means that bulk insertion works very well for clustered data
(where items in one update are close to each other),
but makes query performance worse if the data is scattered.

### Search

```js
const result = tree.search({
    minX: 40,
    minY: 20,
    maxX: 80,
    maxY: 70
});
```

Returns an array of data items (points or rectangles) that the given bounding box intersects.

Note that the `search` method accepts a bounding box in `{minX, minY, maxX, maxY}` format
regardless of the data format.

```js
const allItems = tree.all();
```

Returns all items of the tree.

### Collisions

```js
const result = tree.collides({minX: 40, minY: 20, maxX: 80, maxY: 70});
```

Returns `true` if there are any items intersecting the given bounding box, otherwise `false`.


### Export and Import

```js
// export data as JSON object
const treeData = tree.toJSON();

// import previously exported data
const tree = rbush(9).fromJSON(treeData);
```

Importing and exporting as JSON allows you to use RBush on both the server (using Node.js) and the browser combined,
e.g. first indexing the data on the server and and then importing the resulting tree data on the client for searching.

Note that the `nodeSize` option passed to the constructor must be the same in both trees for export/import to work properly.

### K-Nearest Neighbors

For "_k_ nearest neighbors around a point" type of queries for RBush,
check out [rbush-knn](https://github.com/mourner/rbush-knn).

## Performance

The following sample performance test was done by generating
random uniformly distributed rectangles of ~0.01% area and setting `maxEntries` to `16`
(see `debug/perf.js` script).
Performed with Node.js v6.2.2 on a Retina Macbook Pro 15 (mid-2012).

Test                         | RBush  | [old RTree](https://github.com/imbcmdth/RTree) | Improvement
---------------------------- | ------ | ------ | ----
insert 1M items one by one   | 3.18s  | 7.83s  | 2.5x
1000 searches of 0.01% area  | 0.03s  | 0.93s  | 30x
1000 searches of 1% area     | 0.35s  | 2.27s  | 6.5x
1000 searches of 10% area    | 2.18s  | 9.53s  | 4.4x
remove 1000 items one by one | 0.02s  | 1.18s  | 50x
bulk-insert 1M items         | 1.25s  | n/a    | 6.7x

## Algorithms Used

* single insertion: non-recursive R-tree insertion with overlap minimizing split routine from R\*-tree (split is very effective in JS, while other R\*-tree modifications like reinsertion on overflow and overlap minimizing subtree search are too slow and not worth it)
* single deletion: non-recursive R-tree deletion using depth-first tree traversal with free-at-empty strategy (entries in underflowed nodes are not reinserted, instead underflowed nodes are kept in the tree and deleted only when empty, which is a good compromise of query vs removal performance)
* bulk loading: OMT algorithm (Overlap Minimizing Top-down Bulk Loading) combined with Floyd–Rivest selection algorithm
* bulk insertion: STLT algorithm (Small-Tree-Large-Tree)
* search: standard non-recursive R-tree search

## Papers

* [R-trees: a Dynamic Index Structure For Spatial Searching](http://www-db.deis.unibo.it/courses/SI-LS/papers/Gut84.pdf)
* [The R*-tree: An Efficient and Robust Access Method for Points and Rectangles+](http://dbs.mathematik.uni-marburg.de/publications/myPapers/1990/BKSS90.pdf)
* [OMT: Overlap Minimizing Top-down Bulk Loading Algorithm for R-tree](http://ftp.informatik.rwth-aachen.de/Publications/CEUR-WS/Vol-74/files/FORUM_18.pdf)
* [Bulk Insertions into R-Trees Using the Small-Tree-Large-Tree Approach](http://www.cs.arizona.edu/~bkmoon/papers/dke06-bulk.pdf)
* [R-Trees: Theory and Applications (book)](http://www.apress.com/9781852339777)

## Development

```bash
npm install  # install dependencies

npm test     # lint the code and run tests
npm run perf # run performance benchmarks
npm run cov  # report test coverage
```

## Compatibility

RBush should run on Node and all major browsers that support ES5.
