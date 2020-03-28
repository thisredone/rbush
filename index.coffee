export default class RBush
  constructor: (maxEntries = 9) ->
    # max entries in a node is 9 by default; min node fill is 40% for best performance
    @_maxEntries = Math.max(4, maxEntries)
    @_minEntries = Math.max(2, Math.ceil(@_maxEntries * 0.4))
    @clear()

  all: ->
    @_all(@data, [])

  search: (bbox) ->
    node = @data
    result = []

    return result if not intersects(bbox, node)

    nodesToSearch = []

    while (node)
      for child in node.children
        if (intersects(bbox, child.bbox))
          if (node.leaf)
            result.push(child)
          else if (contains(bbox, child.bbox))
            @_all(child, result)
          else
            nodesToSearch.push(child)
      node = nodesToSearch.pop()

    return result

  collides: (bbox) ->
    node = @data

    return false if not intersects(bbox, node)

    nodesToSearch = []
    while (node)
      for child in node.children
        if (intersects(bbox, child.bbox))
          return true if (node.leaf || contains(bbox, child.bbox))
          nodesToSearch.push(child)
      node = nodesToSearch.pop()

    return false

  update: (item) ->
    if contains(item.parent.bbox, item.bbox)
      return
    @remove(item)
    @insert(item)

  insert: (item) ->
    unless item?.bbox
      log "[RBush::insert] can't add without bbox", item
      return
    @_insert(item, @data.height - 1)
    this

  clear: ->
    @data = createNode([])
    this

  remove: (item) ->
    parent = item.parent
    index = parent.children.indexOf(item)
    if index is -1
      throw "[Rbush remove] ERROR: parent doesn't have that item"
    parent.children.splice index, 1
    @_condense(parent)
    this

  _all: (node, result) ->
    nodesToSearch = []
    while (node)
      if (node.leaf)
        result.push(...node.children)
      else
        nodesToSearch.push(...node.children)

      node = nodesToSearch.pop()
    result

  _chooseSubtree: (bbox, node, level, path) ->
    while true
      path.push(node)

      if (node.leaf || path.length - 1 is level)
        break

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

        else if (enlargement is minEnlargement)
          # otherwise choose one with the smallest area
          if (area < minArea)
            minArea = area
            targetNode = child

      node = targetNode or node.children[0]

    return node

  _insert: (item, level, isNode) ->
    bbox = item.bbox
    insertPath = []

    # find the best node for accommodating the item, saving all nodes along the path too
    node = @_chooseSubtree(bbox, @data, level, insertPath)

    # put the item into the node
    node.children.push(item)
    item.parent = node
    extend(node.bbox, bbox)

    # split on node overflow; propagate upwards if necessary
    while (level >= 0)
      if (insertPath[level].children.length > @_maxEntries)
        @_split(insertPath, level)
        level--
      else
        break

    # adjust bboxes along the insertion path
    @_adjustParentBBoxes(bbox, insertPath, level)

  # split overflowed node into two
  _split: (insertPath, level) ->
    node = insertPath[level]
    M = node.children.length
    m = @_minEntries

    @_chooseSplitAxis(node, m, M)

    splitIndex = @_chooseSplitIndex(node, m, M)

    newNode = createNode(node.children.splice(splitIndex, node.children.length - splitIndex))
    newNode.height = node.height
    newNode.leaf = node.leaf

    calcBBox(node)
    calcBBox(newNode)

    if level
      parent = insertPath[level - 1]
      parent.children.push(newNode)
      newNode.parent = parent
    else
      @_splitRoot(node, newNode)

  _splitRoot: (node, newNode) ->
    # split root node
    @data = createNode([node, newNode])
    @data.height = node.height + 1
    @data.leaf = false
    calcBBox(@data)

  _chooseSplitIndex: (node, m, M) ->
    index = null
    minOverlap = Infinity
    minArea = Infinity

    i = m - 1
    for i in [m..M - m]
      node1 = distBBox(node, 0, i)
      node2 = distBBox(node, i, M)

      overlap = intersectionArea(node1.bbox, node2.bbox)
      area = bboxArea(node1.bbox) + bboxArea(node2.bbox)

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

    leftNode = distBBox(node, 0, m)
    rightNode = distBBox(node, M - m, M)
    margin = bboxMargin(leftNode.bbox) + bboxMargin(rightNode.bbox)

    for i in [m...M - m]
      child = node.children[i]
      extend(leftNode.bbox, child.bbox)
      margin += bboxMargin(leftNode.bbox)

    for i in [M - m - 1..m]
      child = node.children[i]
      extend(rightNode.bbox, child.bbox)
      margin += bboxMargin(rightNode.bbox)

    margin

  _adjustParentBBoxes: (bbox, path, level) ->
    return if level < 0
    # adjust bboxes along the given tree path
    for i in [level..0]
      extend path[i].bbox, bbox
    null

  _condense: (node) ->
    # go upward, removing empty
    while node
      if node.children.length is 0
        if node.parent?
          siblings = node.parent.children
          siblings.splice siblings.indexOf(node), 1
        else
          return @clear()
      else
        calcBBox(node)
      node = node.parent
    null


# calculate node's bbox from bboxes of its children
calcBBox = (node) ->
  distBBox(node, 0, node.children.length, null, node)


# min bounding rectangle of node children from k to p-1
distBBox = (node, k, p, toBBox, destNode) ->
  destNode ?= createNode(null)
  destNode.bbox[0] = Infinity;
  destNode.bbox[1] = Infinity;
  destNode.bbox[2] = -Infinity;
  destNode.bbox[3] = -Infinity;

  for i in [k...p]
    extend(destNode.bbox, node.children[i].bbox)

  destNode


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


createNode = (children) ->
  node =
    children: children
    height: 1,
    leaf: true,
    bbox: [Infinity, Infinity, -Infinity, -Infinity]
  children?.forEach (c) -> c.parent = node
  node
