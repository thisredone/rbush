boxIntersect = require('box-intersect')
MAX_REMOVALS_BEFORE_SWAP = 50


class TmpBbox
  CACHE_SIZE = 20
  bboxes = []
  nextBbox = 0

  for i in [0...CACHE_SIZE]
    bboxes.push [Infinity, Infinity, -Infinity, -Infinity]

  @get: ->
    bboxes[nextBbox++ & (CACHE_SIZE - 1)];


class GrowingArray
  constructor: (@size = 8, { @double = false } = {}) ->
    @current = new Array(@size)
    @other = new Array(@size) if @double
    @currentLen = 0
    @[Symbol.iterator] = ->
      i = 0; max = @currentLen; cur = @current
      next: ->
        if i < max
          value: cur[i++], done: false
        else
          done: true

  push: (item, items2) ->
    @enlarge() if @currentLen is @size
    @other[@currentLen] = item2 if item2?
    @current[@currentLen++] = item

  pop: ->
    @current[--@currentLen] if @currentLen > 0

  enlarge: ->
    @size = Math.floor(@size * 1.5)
    @current.length = @size
    @other?.length = @size


class GrowingArrayPool extends GrowingArray
  constructor: (size, @innerSize) ->
    super(size)

  get: ->
    @pop() or new GrowingArray(@innerSize)

  release: (item) ->
    @push item


class SortableStack extends GrowingArray
  constructor: (size) ->
    super(size, double: true)

  push: (item, value) ->
    @enlarge() if @currentLen is @size
    pos = 0

    while pos < @currentLen
      if value > @other[pos]
        break
      else
        pos++

    while pos <= @currentLen
      [newItem, newValue] = [@current[pos], @other[pos]]
      @current[pos] = item
      @other[pos] = value
      [item, value] = [newItem, newValue]
      pos++

    @currentLen++


class ObjectStorage extends GrowingArray
  constructor: (size) ->
    super(size, double: true)
    @removalsCount = 0
    @[Symbol.iterator] = ->
      i = 0; max = @currentLen; cur = @current
      next: ->
        while i < max
          value = cur[i++]
          if not value._removed
            return { value, done: false }
        done: true

  remove: (item) ->
    item._removed = true
    @condense() if ++@removalsCount > Math.max(@currentLen, 50) * 0.1

  condense: ->
    newIndex = 0
    for index in [0 ... @currentLen]
      item = @current[index]
      if item._removed
        item._removed = null
        continue
      @other[newIndex++] = item
    @swap newIndex

  swap: (@currentLen) ->
    [@current, @other, @removalsCount] = [@other, @current, 0]
    null


class LeafNodes extends ObjectStorage
  constructor: ->
    super(arguments...)
    @overlappingPool = new GrowingArrayPool(@size, Math.ceil(@size / 4))

  push: (item) ->
    super(arguments...)
    item.overlapping ?= @overlappingPool.get()

  remove: (item) ->
    super(arguments...)
    @overlappingPool.release item.overlapping
    item.overlapping = null


class RBush
  constructor: (maxEntries = 9) ->
    # max entries in a node is 9 by default; min node fill is 40% for best performance
    @_maxEntries = Math.max(4, maxEntries)
    @_minEntries = Math.max(2, Math.ceil(@_maxEntries * 0.4))
    @_collisionRunId = 0
    @_stacks = [0..8].map -> new SortableStack(maxEntries)
    @raycastResponse = dist: Infinity, item: null
    @nonStatic = new ObjectStorage(500)
    @result = new GrowingArray(32)
    @searchPath = new GrowingArray(256)
    @leafNodes = new LeafNodes(16)
    @clear()

  all: ->
    @result.currentLen = 0
    @searchPath.currentLen = 0
    @_all(@data)

  search: (bbox, predicate) ->
    node = @data
    @result.currentLen = 0
    return @result if not intersects(bbox, node.bbox)
    @searchPath.currentLen = 0

    while node
      for child in node.children when not child._ignore
        if intersects(bbox, child.bbox)
          if node.leaf
            if not predicate? or predicate(child)
              @result.push(child)
          else if contains(bbox, child.bbox)
            @_all(child, predicate)
          else
            @searchPath.push(child)
      node = @searchPath.pop()

    @result

  collides: (bbox) ->
    node = @data
    return false if not intersects(bbox, node)

    @searchPath.currentLen = 0
    while node
      for child in node.children
        if intersects(bbox, child.bbox)
          return true if node.leaf or contains(bbox, child.bbox)
          @searchPath.push(child)
      node = @searchPath.pop()

    return false

  update: (item) ->
    if contains(item.parent.bbox, item.bbox)
      return

    reinsert = true
    @remove(item, reinsert)
    @insert(item, reinsert)

  insert: (item, reinsert) ->
    unless item?.bbox
      log "[RBush::insert] can't add without bbox", item
      return
    if item._removed
      item._removed = null
      @nonStatic.removalsCount--
      reinsert = true
    @_insert(item)
    unless item.isStatic or reinsert
      @nonStatic.push(item)
    this

  clear: ->
    @data = createNode([])
    @leafNodes.currentLen = 0
    @leafNodes.push @data
    this

  remove: (item, reinsert) ->
    return unless item?
    parent = item.parent
    index = parent.children.indexOf(item)
    if index is -1
      throw "[RBush remove] ERROR: parent doesn't have that item"
    parent.children.splice index, 1
    unless item.isStatic or reinsert
      @nonStatic.remove(item)
    @_condense(parent)
    this

  checkCollisions: (cb) ->
    @_collisionRunId = 0 if ++@_collisionRunId > 99999
    { other, current, currentLen, removalsCount } = @nonStatic

    if removalsCount > MAX_REMOVALS_BEFORE_SWAP
      swapping = true
      newIndex = 0

    leafs = @leafNodes.current
    for i in [0...@leafNodes.currentLen]
      leaf = leafs[i]
      if not leaf._removed
        leaf.overlapping.currentLen = 0

    boxIntersect leafs, @leafNodes.currentLen, (leaf1, leaf2) ->
      leaf1.overlapping.push leaf2
      leaf2.overlapping.push leaf1
      undefined

    for index in [0...currentLen]
      item = current[index]
      continue if item._removed or item._ignore
      other[newIndex++] = item if swapping
      item._colRunId = @_collisionRunId
      leaf = item.parent

      for c in leaf.children when not c._ignore and c._colRunId isnt @_collisionRunId
        if intersects(item.bbox, c.bbox)
          cb item, c

      # using iterators here is much slower
      overlapping = leaf.overlapping
      if overlapping.currentLen
        for i in [0...overlapping.currentLen]
          otherLeaf = overlapping.current[i]
          if intersects(item.bbox, otherLeaf.bbox)
            for c in otherLeaf.children when not c._ignore and c._colRunId isnt @_collisionRunId
              if intersects(item.bbox, c.bbox)
                cb item, c
      null

    if swapping
      @nonStatic.swap(newIndex)
    null

  # _rayObjectDistance: (distToBbox, origin, dir, dstX, dstY, range, item) ->

  raycast: (origin, dir, range = Infinity, predicate) ->
    node = @data

    invDirx = 1 / dir.x
    invDiry = 1 / dir.y

    dstX = origin.x + dir.x * range
    dstY = origin.y + dir.y * range

    tmin = Infinity
    item = null

    for stack in @_stacks
      stack.currentLen = 0

    while node
      stack = @_stacks[node.height]

      if node.leaf
        for child in node.children when not child._ignore
          if not predicate? or predicate(child)
            t = rayBboxDistance(origin.x, origin.y, invDirx, invDiry, child.bbox)
            if t < range and t < tmin
              if @_rayObjectDistance?
                t = @_rayObjectDistance(t, origin, dir, dstX, dstY, range, child)
              if t < range and t < tmin
                tmin = t
                item = child
      else
        for child in node.children when not child._ignore
          t = rayBboxDistance(origin.x, origin.y, invDirx, invDiry, child.bbox)
          if t < range and t < tmin
            stack.push child, t

      while node
        popped = @_stacks[node.height].pop()
        if popped
          node = popped
          break
        node = node.parent

    @raycastResponse.dist = tmin
    @raycastResponse.item = item
    @raycastResponse

  _all: (node, predicate) ->
    i = @searchPath.currentLen

    while node
      if node.leaf
        for child in node.children when not child._ignore
          if not predicate? or predicate(child)
            @result.push(child)
      else
        for child in node.children
          @searchPath.push(child)

      break if @searchPath.currentLen is i
      node = @searchPath.pop()
    @result

  _chooseSubtree: (bbox, node) ->
    while true
      break if node.leaf

      minArea = Infinity
      minEnlargement = Infinity
      targetNode = null

      for child in node.children
        area = bboxArea(child.bbox)
        enlargement = enlargedArea(bbox, child.bbox) - area

        # choose entry with the least area enlargement
        if enlargement < minEnlargement
          minEnlargement = enlargement
          minArea = if area < minArea then area else minArea
          targetNode = child

        else if enlargement is minEnlargement
          # otherwise choose one with the smallest area
          if area < minArea
            minArea = area
            targetNode = child

      node = targetNode or node.children[0]

    node

  _insert: (item) ->
    bbox = item.bbox

    # find the best node for accommodating the item, saving all nodes along the path too
    node = @_chooseSubtree(bbox, @data)

    # put the item into the node
    node.children.push(item)
    item.parent = node
    extend(node.bbox, bbox)

    # split on node overflow; propagate upwards if necessary
    parent = node
    while parent?
      if parent.children.length > @_maxEntries
        @_split parent
      parent = parent.parent

    # adjust bboxes along the insertion path
    @_adjustParentBBoxes(bbox, node.parent)

  # split overflowed node into two
  _split: (node) ->
    M = node.children.length
    m = @_minEntries

    @_chooseSplitAxis(node, m, M)

    splitIndex = @_chooseSplitIndex(node, m, M)

    newNode = createNode(node.children.splice(splitIndex, node.children.length - splitIndex))
    newNode.height = node.height
    newNode.leaf = node.leaf
    if newNode.leaf
      @leafNodes.push newNode

    calcBBox(node)
    calcBBox(newNode)

    if node.parent?
      node.parent.children.push(newNode)
      newNode.parent = node.parent
    else
      @_splitRoot(node, newNode)

  _splitRoot: (node, newNode) ->
    # split root node
    @data = createNode([node, newNode])
    @data.height = node.height + 1
    if @data.height is @_stacks.length
      @_stacks.push new SortableStack(@_maxEntries)
    @data.leaf = false
    calcBBox(@data)

  _chooseSplitIndex: (node, m, M) ->
    index = null
    minOverlap = Infinity
    minArea = Infinity

    i = m - 1
    for i in [m..M - m]
      bbox1 = distBBox(node, 0, i)
      bbox2 = distBBox(node, i, M)

      overlap = intersectionArea(bbox1, bbox2)
      area = bboxArea(bbox1) + bboxArea(bbox2)

      # choose distribution with minimum overlap
      if (overlap < minOverlap)
        minOverlap = overlap
        index = i

        minArea = if area < minArea then area else minArea

      else if overlap is minOverlap
        # otherwise choose distribution with minimum area
        if (area < minArea)
          minArea = area
          index = i

    return index || M - m

  # sorts node children by the best axis for split
  _chooseSplitAxis: (node, m, M) ->
    xMargin = @_allDistMargin(node, m, M, (a, b) -> a.bbox[0] - b.bbox[0])
    yMargin = @_allDistMargin(node, m, M, (a, b) -> a.bbox[1] - b.bbox[1])

    # if total distributions margin value is minimal for x, sort by minX,
    # otherwise it's already sorted by minY
    if (xMargin < yMargin)
      node.children.sort((a, b) -> a.bbox[0] - b.bbox[0])

  # total margin of all possible split distributions where each node is at least m full
  _allDistMargin: (node, m, M, compare) ->
    node.children.sort(compare)

    leftBbox = distBBox(node, 0, m)
    rightBbox = distBBox(node, M - m, M)
    margin = bboxMargin(leftBbox) + bboxMargin(rightBbox)

    for i in [m...M - m]
      child = node.children[i]
      extend(leftBbox, child.bbox)
      margin += bboxMargin(leftBbox)

    for i in [M - m - 1..m]
      child = node.children[i]
      extend(rightBbox, child.bbox)
      margin += bboxMargin(rightBbox)

    margin

  _adjustParentBBoxes: (bbox, node) ->
    while node
      extend node.bbox, bbox
      node = node.parent
    null

  _condense: (node) ->
    # go upward, removing empty
    while node
      if node.children.length is 0
        if node.parent?
          siblings = node.parent.children
          siblings.splice siblings.indexOf(node), 1
          if node.leaf
            @leafNodes.remove node
        else
          return @clear()
      else
        calcBBox(node)
      node = node.parent
    null


# calculate node's bbox from bboxes of its children
calcBBox = (node) ->
  distBBox(node, 0, node.children.length, node)


# min bounding rectangle of node children from k to p-1
distBBox = (node, k, p, destNode) ->
  bbox = destNode?.bbox ? TmpBbox.get()
  bbox[0] = Infinity;
  bbox[1] = Infinity;
  bbox[2] = -Infinity;
  bbox[3] = -Infinity;

  for i in [k...p]
    extend(bbox, node.children[i].bbox)

  bbox


extend = (a, b) ->
  a[0] = Math.min(a[0], b[0]) # minX
  a[1] = Math.min(a[1], b[1]) # minY
  a[2] = Math.max(a[2], b[2]) # maxX
  a[3] = Math.max(a[3], b[3]) # maxY
  a


bboxArea = (a) -> (a[2] - a[0]) * (a[3] - a[1])
bboxMargin = (a) -> (a[2] - a[0]) + (a[3] - a[1])

enlargedArea = (a, b) ->
  (Math.max(b[2], a[2]) - Math.min(b[0], a[0])) * (Math.max(b[3], a[3]) - Math.min(b[1], a[1]))


intersectionArea = (a, b) ->
  minX = Math.max(a[0], b[0])
  minY = Math.max(a[1], b[1])
  maxX = Math.min(a[2], b[2])
  maxY = Math.min(a[3], b[3])

  Math.max(0, maxX - minX) * Math.max(0, maxY - minY)


contains = (a, b) ->
  a[0] <= b[0] && a[1] <= b[1] && b[2] <= a[2] && b[3] <= a[3]


intersects = (a, b) ->
  b[0] <= a[2] && b[1] <= a[3] && b[2] >= a[0] && b[3] >= a[1]


rayBboxDistance = (x, y, invdx, invdy, bbox) ->
  tx1 = (bbox[0] - x) * invdx
  tx2 = (bbox[2] - x) * invdx

  tmin = Math.min(tx1, tx2)
  tmax = Math.max(tx1, tx2)

  ty1 = (bbox[1] - y) * invdy
  ty2 = (bbox[3] - y) * invdy

  tmin = Math.max(tmin, Math.min(ty1, ty2))
  tmax = Math.min(tmax, Math.max(ty1, ty2))

  if tmax > Math.max(tmin, 0) then tmin else Infinity


createNode = (children) ->
  node =
    children: children
    height: 1
    leaf: true
    bbox: [Infinity, Infinity, -Infinity, -Infinity]
  if children?
    c.parent = node for c in children
  node


module.exports = RBush
